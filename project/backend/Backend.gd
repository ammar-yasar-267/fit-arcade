extends Node

## Autoload. Thin REST client for Firebase Auth (anonymous identities) and
## Firestore, plus the FitArcade domain calls built on top of them
## (remote config, profiles, score submission, leaderboards).
##
## Everything here is plain HTTPRequest + JSON — no native Firebase SDK —
## so it exports cleanly alongside the existing GDMP/CameraServerExtension
## native plugins without adding another one.

signal auth_ready(uid: String)
signal auth_failed(reason: String)
signal config_loaded(config: Dictionary)
signal config_load_failed
signal account_deleted

const DISPLAY_NAME_MIN := 3
const DISPLAY_NAME_MAX := 16
## Seconds before a request is abandoned. Without it an offline/stalled request
## would leave callers awaiting forever (e.g. a spinner on the onboarding screen).
const REQUEST_TIMEOUT_SEC := 10.0

const AUTH_FILE := "user://fitarcade_auth.cfg"
const CONFIG_CACHE_FILE := "user://fitarcade_remote_config.cfg"
const PROFILE_CACHE_FILE := "user://fitarcade_profile.cfg"
const VALID_GAME_MODES := ["dino", "switcher", "flappy"]
const BADGE_EMOJI := ["⚡", "🔥", "🏆", "💪", "🎯", "🚀", "⭐", "🎮"]

var uid: String = ""
var _id_token: String = ""
var _refresh_token: String = ""

var profile: Dictionary = {}
var _config_cache: Dictionary = {}


func _ready() -> void:
	_load_auth_cache()
	_load_config_cache()
	_load_profile_cache()


# --- Auth -------------------------------------------------------------

## Single-flight: while one sign-in/refresh is running, other callers wait for its
## result instead of starting their own. Screens now fire several requests at once
## (e.g. the Hub loads three leaderboards in parallel), and without this a missing
## token would sign up one brand-new anonymous account per request.
signal _auth_task_done(ok: bool)
var _auth_task_running: bool = false

func ensure_authenticated() -> bool:
	if not FirebaseConfig.is_configured():
		auth_failed.emit("not_configured")
		return false
	if _id_token != "":
		return true
	if _auth_task_running:
		return await _auth_task_done
	_auth_task_running = true
	var ok := false
	if _refresh_token != "" and await _refresh_id_token():
		ok = true
	else:
		ok = await _sign_up_anonymous()
	_auth_task_running = false
	_auth_task_done.emit(ok)
	return ok


func _sign_up_anonymous() -> bool:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({"returnSecureToken": true})
	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	if not res.ok:
		auth_failed.emit("signup_failed")
		return false
	uid = res.data.get("localId", "")
	_id_token = res.data.get("idToken", "")
	_refresh_token = res.data.get("refreshToken", "")
	_save_auth_cache()
	auth_ready.emit(uid)
	return true


func _refresh_id_token() -> bool:
	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var body := "grant_type=refresh_token&refresh_token=%s" % _refresh_token
	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	if not res.ok:
		_id_token = ""
		_refresh_token = ""
		return false
	uid = res.data.get("user_id", uid)
	_id_token = res.data.get("id_token", "")
	_refresh_token = res.data.get("refresh_token", _refresh_token)
	_save_auth_cache()
	return true


func _load_auth_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_FILE) == OK:
		uid = cfg.get_value("auth", "uid", "")
		_refresh_token = cfg.get_value("auth", "refresh_token", "")


func _save_auth_cache() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "uid", uid)
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.save(AUTH_FILE)


# --- Low-level Firestore REST -----------------------------------------

func _firestore_base_url() -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % FirebaseConfig.PROJECT_ID


func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % _id_token,
		"Content-Type: application/json",
	])


func get_document(path: String) -> Dictionary:
	if not await ensure_authenticated():
		return {}
	var url := "%s/%s" % [_firestore_base_url(), path]
	var res := await _http_request(url, HTTPClient.METHOD_GET, _auth_headers())
	if not res.ok:
		return {}
	return FirestoreCodec.decode_document(res.data)


## Same as get_document(), but skips the anonymous-auth round trip entirely.
## Only valid for paths firestore.rules marks "allow read: if true" — right
## now that's just app_config/global — since this sends no Authorization
## header at all. Cuts the slowest step out of the maintenance/game-mode
## check on cold launch.
func get_public_document(path: String) -> Dictionary:
	var url := "%s/%s" % [_firestore_base_url(), path]
	var res := await _http_request(url, HTTPClient.METHOD_GET, PackedStringArray())
	if not res.ok:
		return {}
	return FirestoreCodec.decode_document(res.data)


## Create-or-overwrite a document at an exact path (e.g. "profiles/abc123").
func set_document(path: String, data: Dictionary) -> bool:
	if not await ensure_authenticated():
		return false
	var url := "%s/%s" % [_firestore_base_url(), path]
	var body := JSON.stringify(FirestoreCodec.encode_fields(data))
	var res := await _http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), body)
	return res.ok


## Create a new document with an auto-generated id inside a collection
## (e.g. "scores"). Returns the decoded document, or {} on failure.
func create_document(collection_path: String, data: Dictionary) -> Dictionary:
	if not await ensure_authenticated():
		return {}
	var url := "%s/%s" % [_firestore_base_url(), collection_path]
	var body := JSON.stringify(FirestoreCodec.encode_fields(data))
	var res := await _http_request(url, HTTPClient.METHOD_POST, _auth_headers(), body)
	if not res.ok:
		return {}
	return FirestoreCodec.decode_document(res.data)


func _run_query(structured_query: Dictionary) -> Array:
	return (await _run_query_result(structured_query)).docs


## Like _run_query(), but says whether the request worked, so callers can tell
## "no results" from "couldn't reach the server".
func _run_query_result(structured_query: Dictionary) -> Dictionary:
	if not await ensure_authenticated():
		return {"ok": false, "docs": []}
	var url := "%s:runQuery" % _firestore_base_url()
	var body := JSON.stringify({"structuredQuery": structured_query})
	var res := await _http_request(url, HTTPClient.METHOD_POST, _auth_headers(), body)
	if not res.ok or typeof(res.data) != TYPE_ARRAY:
		return {"ok": false, "docs": []}
	var docs := []
	for entry in res.data:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("document"):
			docs.append(FirestoreCodec.decode_document(entry["document"]))
	return {"ok": true, "docs": docs}


func _http_request(url: String, method: int, headers: PackedStringArray, body: String = "") -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT_SEC
	add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		push_warning("Backend HTTPRequest failed to start (err %d): %s" % [err, url])
		req.queue_free()
		return {"ok": false, "status": 0, "data": null}
	var result: Array = await req.request_completed
	req.queue_free()
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	var text := response_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null
	if response_code < 200 or response_code >= 300:
		push_warning("Backend HTTP request returned status %d for %s: %s" % [response_code, url, text])
	return {
		"ok": response_code >= 200 and response_code < 300,
		"status": response_code,
		"data": parsed,
	}


# --- Remote config (admin switches) ------------------------------------

func fetch_app_config() -> Dictionary:
	var doc := await get_public_document("app_config/global")
	if doc.is_empty():
		config_load_failed.emit()
		return _config_cache
	_config_cache = doc
	_save_config_cache(doc)
	config_loaded.emit(doc)
	return doc


## True once any remote config has been received (this session or a previous one).
## Before that, game locks and maintenance mode simply aren't known yet.
func has_config() -> bool:
	return not _config_cache.is_empty()


func is_game_mode_enabled(game_id: String) -> bool:
	var modes: Dictionary = _config_cache.get("game_modes", {})
	return modes.get(game_id, true)


func is_maintenance_mode() -> bool:
	return _config_cache.get("maintenance_mode", false)


func get_setting(key: String, default_value):
	var settings: Dictionary = _config_cache.get("settings", {})
	return settings.get(key, default_value)


func _load_config_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_CACHE_FILE) == OK:
		var raw = cfg.get_value("config", "json", "")
		if raw != "":
			var parsed = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				_config_cache = parsed


func _save_config_cache(doc: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("config", "json", JSON.stringify(doc))
	cfg.save(CONFIG_CACHE_FILE)


# --- Player Card (profile) ----------------------------------------------

## Deterministic 4-digit tag derived from the uid — "Ammar#0423" style.
## No collision bookkeeping needed since the uid is already unique.
static func generate_tag(seed_uid: String) -> String:
	var h := hash(seed_uid)
	return "%04d" % (abs(h) % 10000)


## Deterministic badge emoji derived from the uid — same idea as the tag,
## just a visual flourish for the Player Card / leaderboard rows.
static func generate_badge(seed_uid: String) -> String:
	var h := hash(seed_uid + "badge")
	return BADGE_EMOJI[abs(h) % BADGE_EMOJI.size()]


func has_local_profile() -> bool:
	return profile.get("display_name", "") != ""


## Trim and collapse runs of spaces, so "  Kai   Vega " becomes "Kai Vega".
static func normalize_display_name(raw: String) -> String:
	var cleaned := raw.strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	return cleaned


## Returns "" when the name is acceptable, otherwise a short reason for the UI.
## ASCII only: the display font (Anton) has no glyphs beyond Latin.
static func validate_display_name(raw: String) -> String:
	var cleaned := normalize_display_name(raw)
	if cleaned.length() < DISPLAY_NAME_MIN:
		return "AT LEAST %d CHARACTERS" % DISPLAY_NAME_MIN
	if cleaned.length() > DISPLAY_NAME_MAX:
		return "AT MOST %d CHARACTERS" % DISPLAY_NAME_MAX
	var allowed := RegEx.new()
	allowed.compile("^[A-Za-z0-9 _.\\-]+$")
	if allowed.search(cleaned) == null:
		return "LETTERS, NUMBERS, SPACE, _ - . ONLY"
	return ""


## Offline fallback for onboarding: saves the profile on this device only and
## flags it so sync_pending_profile() pushes it to Firestore once we're online.
## Keeps the app usable without a connection, like the rest of the game.
func save_local_profile(display_name: String) -> Dictionary:
	var seed_value := uid if uid != "" else str(randi())
	var tag := generate_tag(seed_value)
	var now := Time.get_datetime_string_from_system(true)
	profile = {
		"display_name": display_name,
		"display_tag": "%s#%s" % [display_name.to_lower(), tag],
		"tag_number": tag,
		"badge": generate_badge(seed_value),
		"created_at": now,
		"last_seen_at": now,
		"pending_sync": true,
	}
	_save_profile_cache(profile)
	return profile


func sync_pending_profile() -> void:
	if profile.get("pending_sync", false):
		await ensure_profile(profile.get("display_name", ""))


func ensure_profile(display_name: String) -> Dictionary:
	if not await ensure_authenticated():
		return {}
	var tag := generate_tag(uid)
	# Stored as a plain "YYYY-MM-DD HH:MM:SS" string (Firestore stringValue,
	# not a native Timestamp) — zero-padded so it still sorts correctly.
	var now := Time.get_datetime_string_from_system(true)
	var existing := await get_document("profiles/%s" % uid)
	var data := {
		"display_name": display_name,
		"display_tag": "%s#%s" % [display_name.to_lower(), tag],
		"tag_number": tag,
		"badge": generate_badge(uid),
		"last_seen_at": now,
	}
	data["created_at"] = existing.get("created_at", now)
	if await set_document("profiles/%s" % uid, data):
		profile = data
		_save_profile_cache(data)
	return profile


func _load_profile_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_CACHE_FILE) == OK:
		var raw = cfg.get_value("profile", "json", "")
		if raw != "":
			var parsed = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				profile = parsed


func _save_profile_cache(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "json", JSON.stringify(data))
	cfg.save(PROFILE_CACHE_FILE)


# --- Account deletion ----------------------------------------------------

## Permanently deletes this player: score history, leaderboard rows, profile and
## the Firebase Auth identity, then wipes the local identity/profile caches.
## Returns {"ok": bool, "error": "" | "network" | "permission" | "server" | "auth"}.
##
## Order matters for retries: cloud data first, the Auth account last, local
## state only once everything remote succeeded. If any step fails we keep the
## tokens so the player can simply try again; every step is safe to repeat
## (deleting an already-deleted document is a no-op).
func delete_account() -> Dictionary:
	var has_cloud_identity := FirebaseConfig.is_configured() and (_refresh_token != "" or _id_token != "")
	if has_cloud_identity:
		# Tokens last ~1h and nothing tracks expiry, so start from a fresh one.
		# Don't fall through to ensure_authenticated(): a failed refresh there would
		# sign up a brand-new anonymous user and we'd "delete" the wrong account.
		if _refresh_token != "" and not await _refresh_id_token():
			return {"ok": false, "error": "auth"}

		var my_uid := uid
		var scores := await _query_document_names({
			"from": [{"collectionId": "scores"}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "uid"},
				"op": "EQUAL",
				"value": {"stringValue": my_uid},
			}},
			"select": {"fields": [{"fieldPath": "__name__"}]},
		})
		if not scores.ok:
			return {"ok": false, "error": scores.error}

		var names: Array = scores.names
		for mode in VALID_GAME_MODES:
			names.append(_document_resource_name("best_scores/%s_%s" % [my_uid, mode]))
		names.append(_document_resource_name("profiles/%s" % my_uid))

		# Commits are capped (500 writes); 100 per request keeps payloads small.
		var batch_size := 100
		for start in range(0, names.size(), batch_size):
			var res := await _commit_deletes(names.slice(start, start + batch_size))
			if not res.ok:
				push_warning("delete_account: Firestore commit failed (HTTP %d): %s" % [res.status, JSON.stringify(res.data)])
				return {"ok": false, "error": _error_for_status(res.status)}

		var auth_res := await _delete_auth_account()
		if not auth_res.ok:
			push_warning("delete_account: Auth delete failed (HTTP %d): %s" % [auth_res.status, JSON.stringify(auth_res.data)])
			return {"ok": false, "error": _error_for_status(auth_res.status)}

	_clear_local_identity()
	account_deleted.emit()
	return {"ok": true, "error": ""}


func _document_resource_name(path: String) -> String:
	return "projects/%s/databases/(default)/documents/%s" % [FirebaseConfig.PROJECT_ID, path]


## Firestore's `commit` takes full resource names, which is exactly what a
## `__name__` projection returns, so the two chain directly.
func _commit_deletes(resource_names: Array) -> Dictionary:
	var writes := []
	for resource_name in resource_names:
		writes.append({"delete": resource_name})
	var url := "%s:commit" % _firestore_base_url()
	return await _http_request(url, HTTPClient.METHOD_POST, _auth_headers(), JSON.stringify({"writes": writes}))


## Collects every matching document name, paging with `offset` until a page
## comes back short. Nothing is deleted while paging, so offsets stay stable.
func _query_document_names(structured_query: Dictionary, page_size: int = 100) -> Dictionary:
	var all_names: Array = []
	var url := "%s:runQuery" % _firestore_base_url()
	for _page in range(100):
		var body := structured_query.duplicate(true)
		body["limit"] = page_size
		body["offset"] = all_names.size()
		var res := await _http_request(url, HTTPClient.METHOD_POST, _auth_headers(), JSON.stringify({"structuredQuery": body}))
		if not res.ok or typeof(res.data) != TYPE_ARRAY:
			return {"ok": false, "error": _error_for_status(res.status), "names": []}
		var page_count := 0
		for entry in res.data:
			if typeof(entry) == TYPE_DICTIONARY and entry.has("document"):
				all_names.append(entry["document"].get("name", ""))
				page_count += 1
		if page_count < page_size:
			break
	return {"ok": true, "error": "", "names": all_names}


func _delete_auth_account() -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])
	return await _http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify({"idToken": _id_token}))


func _error_for_status(status: int) -> String:
	if status == 0:
		return "network"
	if status == 401 or status == 403:
		return "permission"
	return "server"


func _clear_local_identity() -> void:
	uid = ""
	_id_token = ""
	_refresh_token = ""
	profile = {}
	for file_path in [AUTH_FILE, PROFILE_CACHE_FILE]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


# --- Scores & leaderboards ------------------------------------------------

## "idle" (nothing submitted yet) | "pending" | "ok" | "failed". Lets a screen that
## appears while the upload is still running (the Summary) show the true state
## instead of assuming success.
var submit_state: String = "idle"
signal score_submit_finished(ok: bool)

func submit_score(game_mode: String, score: int, reps: int) -> bool:
	submit_state = "pending"
	var ok := await _submit_score(game_mode, score, reps)
	submit_state = "ok" if ok else "failed"
	score_submit_finished.emit(ok)
	return ok


## Leaderboard position a score would hold on an already-fetched board, as "#N".
## Ranks by score rather than by finding the player's row, so it's right even if
## their own upload hasn't landed yet. "—" when there's no score to rank, and
## "N+" when more than `board_limit` players are ahead (the board is capped).
static func rank_label(board_rows: Array, score: int, board_limit: int) -> String:
	if score <= 0:
		return "—"
	var ahead := 0
	for row in board_rows:
		if int(row.get("score", 0)) > score:
			ahead += 1
	if ahead >= board_limit:
		return "%d+" % board_limit
	return "#%d" % (ahead + 1)


func _submit_score(game_mode: String, score: int, reps: int) -> bool:
	if not VALID_GAME_MODES.has(game_mode):
		return false
	if not await ensure_authenticated():
		return false
	var doc := await create_document("scores", {
		"uid": uid,
		"display_name": profile.get("display_name", ""),
		"display_tag": profile.get("display_tag", ""),
		"game_mode": game_mode,
		"score": score,
		"reps": reps,
		"created_at": Time.get_datetime_string_from_system(true),
	})
	if doc.is_empty():
		return false
	await _update_best_score(game_mode, score)
	return true


## Best-effort read-then-write; fine for a single device updating its own
## row sequentially. Not a Firestore transaction — security rules are the
## actual backstop against a lower score overwriting a higher one.
func _update_best_score(game_mode: String, score: int) -> bool:
	var doc_id := "%s_%s" % [uid, game_mode]
	var existing := await get_document("best_scores/%s" % doc_id)
	if not existing.is_empty() and int(existing.get("score", 0)) >= score:
		return false
	return await set_document("best_scores/%s" % doc_id, {
		"uid": uid,
		"display_name": profile.get("display_name", ""),
		"display_tag": profile.get("display_tag", ""),
		"game_mode": game_mode,
		"score": score,
		"updated_at": Time.get_datetime_string_from_system(true),
	})


func get_leaderboard(game_mode: String, limit: int = 20) -> Array:
	return (await fetch_leaderboard(game_mode, limit)).rows


## Returns {"ok": bool, "rows": Array}. `ok` is false when the request failed
## (offline, signed out, server error), as opposed to a board with no scores yet.
func fetch_leaderboard(game_mode: String, limit: int = 20) -> Dictionary:
	var res := await _run_query_result({
		"from": [{"collectionId": "best_scores"}],
		"where": {
			"fieldFilter": {
				"field": {"fieldPath": "game_mode"},
				"op": "EQUAL",
				"value": {"stringValue": game_mode},
			}
		},
		"orderBy": [{"field": {"fieldPath": "score"}, "direction": "DESCENDING"}],
		"limit": limit,
	})
	return {"ok": res.ok, "rows": res.docs}
