extends Node

var current_reps: int = 0
var total_reps_today: int = 0
var session_score: int = 0
var daily_streak: int = 1

# Efficiency metrics
var frames_processed: int = 0
var _session_start_ms: int = -1
var _latency_total_ms: float = 0.0
var _latency_count: int = 0

func reset_session():
	current_reps = 0
	session_score = 0
	frames_processed = 0
	_session_start_ms = -1
	_latency_total_ms = 0.0
	_latency_count = 0

func add_rep():
	current_reps += 1
	total_reps_today += 1

func record_inference(duration_ms: float) -> void:
	if _session_start_ms < 0:
		_session_start_ms = Time.get_ticks_msec()
	frames_processed += 1
	_latency_total_ms += duration_ms
	_latency_count += 1

func get_avg_latency_ms() -> float:
	if _latency_count == 0:
		return 0.0
	return _latency_total_ms / _latency_count

func get_effective_fps() -> float:
	if _session_start_ms < 0 or frames_processed < 2:
		return 0.0
	var elapsed_s: float = (Time.get_ticks_msec() - _session_start_ms) / 1000.0
	if elapsed_s <= 0.0:
		return 0.0
	return frames_processed / elapsed_s
