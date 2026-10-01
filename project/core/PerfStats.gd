extends Node

## Autoload. Measures the pose-tracking pipeline for the debug overlay and the Summary.
##
## One camera frame goes through these stages, each timed with the microsecond clock:
##
##   camera delivers frame ──► prep ──► infer ──► post ──► done
##        (frame_arrived)    capture,   model     recognise
##                           readback,  runs      reps, draw
##                           resize     (send →   skeleton,
##                           (→ send)   callback) update UI
##
##   prep + infer + post = the app's whole pipeline for that frame ("total").
##
## What this CANNOT see: the camera hardware / OS delay before the frame reaches Godot.
## Every figure here is "from the moment the app received the frame".
##
## Each result is matched to its own frame by id (the packet timestamp, which MediaPipe
## carries through to the output). That keeps the numbers right even when a result
## arrives late, after the app has already given up on it and sent a newer frame.
##
## Every method takes an optional clock value so tests can drive a fake timeline.

## Recent frames averaged for the live numbers
const WINDOW := 30
## Rates (camera/track fps, drop %) are counted over this long
const RATE_WINDOW_US := 2_000_000
## The whole-session figure isn't shown until it rests on at least this many results
const MIN_SESSION_SAMPLES := 10
## Samples needed before the live latency is shown (avoids a noisy first reading)
const MIN_LIVE_SAMPLES := 5
const MAX_SESSION_SAMPLES := 20000
## A frame that never produces a result is forgotten after this long
const PENDING_TTL_US := 10_000_000

var _pending: Dictionary = {}          # id -> {"arrive": us, "sent": us, "result": us}
var _recent: Array = []                # last WINDOW results: {prep, infer, post, total} in ms
var _session_totals: Array = []        # every result's total, for the session median
var _arrivals: Array = []              # µs: camera frames delivered
var _sent_times: Array = []            # µs: frames given to the model
var _done_times: Array = []            # µs: results fully processed
var lost_frames: int = 0               # sent but never answered
var skipped_by_reason: Dictionary = {}

func reset() -> void:
	_pending.clear()
	_recent.clear()
	_session_totals.clear()
	_arrivals.clear()
	_sent_times.clear()
	_done_times.clear()
	lost_frames = 0
	skipped_by_reason.clear()

# --- Pipeline hooks --------------------------------------------------------------

## A camera frame reached the app.
func frame_arrived(now_us: int = -1) -> void:
	_arrivals.append(_now(now_us))
	_prune(_arrivals, _now(now_us))

## A camera frame was NOT sent to the model. `reason`: "busy" (the previous capture was
## still in progress), "interval" (frame-rate limiter) or "inflight" (model still working).
func frame_skipped(reason: String) -> void:
	skipped_by_reason[reason] = skipped_by_reason.get(reason, 0) + 1

## A frame is being handed to the model. `arrive_us` is when that frame reached the app.
func frame_sent(id: int, arrive_us: int, now_us: int = -1) -> void:
	var now := _now(now_us)
	_pending[id] = {"arrive": arrive_us, "sent": now, "result": -1}
	_sent_times.append(now)
	_prune(_sent_times, now)
	_forget_stale(now)

## The model answered. Returns false if `id` isn't a frame we know about.
func frame_result(id: int, now_us: int = -1) -> bool:
	if not _pending.has(id):
		return false
	_pending[id]["result"] = _now(now_us)
	return true

## The result has been fully handled (recognition, drawing, UI). Closes the frame and
## records its stage timings.
func frame_done(id: int, now_us: int = -1) -> void:
	var now := _now(now_us)
	if not _pending.has(id) or _pending[id]["result"] < 0:
		return
	var f: Dictionary = _pending[id]
	_pending.erase(id)
	var sample := {
		"prep": (f["sent"] - f["arrive"]) / 1000.0,
		"infer": (f["result"] - f["sent"]) / 1000.0,
		"post": (now - f["result"]) / 1000.0,
		"total": (now - f["arrive"]) / 1000.0,
	}
	_recent.append(sample)
	if _recent.size() > WINDOW:
		_recent.pop_front()
	if _session_totals.size() < MAX_SESSION_SAMPLES:
		_session_totals.append(sample["total"])
	_done_times.append(now)
	_prune(_done_times, now)

## Oldest frame still awaiting its result, or -1. For output packets that carry no id
## (the model found no pose), which MediaPipe still delivers in send order.
func oldest_pending_id() -> int:
	var best := -1
	var best_sent := 0
	for id in _pending:
		var sent: int = _pending[id]["sent"]
		if best == -1 or sent < best_sent:
			best = id
			best_sent = sent
	return best

# --- Readouts ------------------------------------------------------------------------

## Everything the overlay shows. Values are -1 while there isn't enough data yet.
func snapshot(now_us: int = -1) -> Dictionary:
	var now := _now(now_us)
	_prune(_arrivals, now)
	_prune(_sent_times, now)
	_prune(_done_times, now)

	var window_s := RATE_WINDOW_US / 1_000_000.0
	var snap := {
		"cam_fps": -1.0, "track_fps": -1.0, "drop_pct": -1.0,
		"samples": _recent.size(),
		"prep_ms": -1.0, "infer_ms": -1.0, "post_ms": -1.0, "total_ms": -1.0, "total_p95_ms": -1.0,
		"session_median_ms": session_latency_ms(), "session_samples": _session_totals.size(),
		"lost": lost_frames,
	}
	if not _arrivals.is_empty():
		snap["cam_fps"] = _arrivals.size() / window_s
		snap["drop_pct"] = 100.0 * (1.0 - float(_sent_times.size()) / float(_arrivals.size()))
		snap["drop_pct"] = clampf(snap["drop_pct"], 0.0, 100.0)
	if not _done_times.is_empty():
		snap["track_fps"] = _done_times.size() / window_s

	if _recent.size() >= MIN_LIVE_SAMPLES:
		snap["prep_ms"] = _mean("prep")
		snap["infer_ms"] = _mean("infer")
		snap["post_ms"] = _mean("post")
		snap["total_ms"] = _mean("total")
		var totals: Array = []
		for s in _recent:
			totals.append(s["total"])
		snap["total_p95_ms"] = percentile(totals, 95.0)
	return snap

## Typical pipeline latency over the whole session so far (the median, so slow warm-up
## frames don't skew it), or 0.0 when there aren't enough samples to trust.
func session_latency_ms() -> float:
	if _session_totals.size() < MIN_SESSION_SAMPLES:
		return 0.0
	return percentile(_session_totals, 50.0)

static func percentile(values: Array, pct: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	# Linear interpolation between the two nearest ranks
	var rank := (pct / 100.0) * (sorted.size() - 1)
	var lo := int(floor(rank))
	var hi := int(ceil(rank))
	return lerpf(float(sorted[lo]), float(sorted[hi]), rank - lo)

# --- Memory ----------------------------------------------------------------------------

## engine_mb: memory Godot itself allocated (does NOT include the pose model runtime or
##            graphics driver, so it is far below the real total).
## gpu_mb:    video memory Godot is tracking (textures + buffers).
## process_mb: the process's real resident memory, or -1 where the OS doesn't expose it
##            to the app (it can only be read on Android/Linux).
func memory_info() -> Dictionary:
	return {
		"engine_mb": OS.get_static_memory_usage() / 1048576.0,
		"gpu_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"process_mb": _process_memory_mb(),
	}

func _process_memory_mb() -> float:
	if OS.get_name() in ["Android", "Linux"] and FileAccess.file_exists("/proc/self/status"):
		return parse_vm_rss_mb(FileAccess.get_file_as_string("/proc/self/status"))
	return -1.0

## "VmRSS:    123456 kB" from /proc/self/status -> megabytes, or -1 if absent.
static func parse_vm_rss_mb(status_text: String) -> float:
	for line in status_text.split("\n"):
		if line.begins_with("VmRSS:"):
			var digits := line.substr(6).strip_edges().split(" ", false)
			if digits.size() > 0 and digits[0].is_valid_int():
				return int(digits[0]) / 1024.0
	return -1.0

# --- Overlay text --------------------------------------------------------------------

## The debug overlay, three lines. Anything not measured yet shows "—" rather than 0.
static func format_overlay(snap: Dictionary, mem: Dictionary, render_fps: int, accel: String) -> String:
	var cam := _rate_text(snap["cam_fps"])
	var track := _rate_text(snap["track_fps"])
	var drop: String = "—" if snap["drop_pct"] < 0.0 else "%d%%" % roundi(snap["drop_pct"])
	var line1 := "FPS %d · TRACK %s/s · CAM %s/s · DROP %s" % [render_fps, track, cam, drop]

	var line2: String
	if snap["total_ms"] < 0.0:
		line2 = "LAT warming up… (%d/%d frames)" % [snap["samples"], MIN_LIVE_SAMPLES]
	else:
		line2 = "LAT %d ms (p95 %d) = prep %d + infer %d + post %d" % [
			roundi(snap["total_ms"]), roundi(snap["total_p95_ms"]),
			roundi(snap["prep_ms"]), roundi(snap["infer_ms"]), roundi(snap["post_ms"])]

	var line3 := "MEM "
	if mem["process_mb"] >= 0.0:
		line3 += "app %d · " % roundi(mem["process_mb"])
	line3 += "engine %d · gpu %d MB" % [roundi(mem["engine_mb"]), roundi(mem["gpu_mb"])]
	line3 += " · ACCEL %s" % accel
	return "%s\n%s\n%s" % [line1, line2, line3]

static func _rate_text(value: float) -> String:
	return "—" if value < 0.0 else "%d" % roundi(value)

# --- Internals ---------------------------------------------------------------------------

func _now(now_us: int) -> int:
	return now_us if now_us >= 0 else Time.get_ticks_usec()

func _prune(times: Array, now: int) -> void:
	while not times.is_empty() and now - times[0] > RATE_WINDOW_US:
		times.pop_front()

func _mean(key: String) -> float:
	var sum := 0.0
	for s in _recent:
		sum += s[key]
	return sum / _recent.size()

## Frames that were sent but never answered: drop them from the pending set and count them.
func _forget_stale(now: int) -> void:
	for id in _pending.keys():
		if now - _pending[id]["sent"] > PENDING_TTL_US:
			_pending.erase(id)
			lost_frames += 1
