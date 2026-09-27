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

func ensure_authenticated() -> bool:
	if not FirebaseConfig.is_configured():
		auth_failed.emit("not_configured")
		return false
	if _id_token != "":
		return true
	if _refresh_token != "" and await _refresh_id_token():
		return true
	return await _sign_up_anonymous()


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
	if not await ensure_authenticated():
		return []
	var url := "%s:runQuery" % _firestore_base_url()
	var body := JSON.stringify({"structuredQuery": structured_query})
	var res := await _http_request(url, HTTPClient.METHOD_POST, _auth_headers(), body)
	if not res.ok or typeof(res.data) != TYPE_ARRAY:
		return []
	var docs := []
	for entry in res.data:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("document"):
			docs.append(FirestoreCodec.decode_document(entry["document"]))
	return docs


func _http_request(url: String, method: int, headers: PackedStringArray, body: String = "") -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "data": null}
	var result: Array = await req.request_completed
	req.queue_free()
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	var text := response_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null
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


# --- Scores & leaderboards ------------------------------------------------

func submit_score(game_mode: String, score: int, reps: int) -> bool:
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
	return await _run_query({
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
