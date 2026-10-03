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
signal google_linked_state_changed(is_linked: bool)

const DISPLAY_NAME_MIN := 3
const DISPLAY_NAME_MAX := 16
## Seconds before a request is abandoned. Without it an offline/stalled request
## would leave callers awaiting forever (e.g. a spinner on the onboarding screen).
const REQUEST_TIMEOUT_SEC := 8.0

const AUTH_FILE := "user://fitarcade_auth.cfg"
const CONFIG_CACHE_FILE := "user://fitarcade_remote_config.cfg"
const PROFILE_CACHE_FILE := "user://fitarcade_profile.cfg"
const VALID_GAME_MODES := ["dino", "switcher", "flappy"]
const BADGE_EMOJI := ["⚡", "🔥", "🏆", "💪", "🎯", "🚀", "⭐", "🎮"]

var uid: String = ""
var _id_token: String = ""
var _refresh_token: String = ""
var _id_token_expires_at: int = 0

var profile: Dictionary = {}
var _config_cache: Dictionary = {}

# --- In-memory leaderboard cache ---------------------------------------
var _leaderboard_cache: Dictionary = {}
const LEADERBOARD_CACHE_TTL_MS := 45000


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
	var now := int(Time.get_unix_time_from_system())
	if _id_token != "" and now < _id_token_expires_at - 180:
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
	var exp_in := int(res.data.get("expiresIn", "3600"))
	_id_token_expires_at = int(Time.get_unix_time_from_system()) + (exp_in if exp_in > 0 else 3600)
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
		_id_token_expires_at = 0
		if res.status == 400:
			push_warning("Auth token refresh returned 400 (account deleted or revoked). Clearing local identity.")
			_clear_local_identity()
			if get_tree() and get_tree().root.has_node("SessionManager"):
				var sm = get_tree().root.get_node("SessionManager")
				if sm.has_method("clear_local_data"):
					sm.clear_local_data()
			account_deleted.emit()
		return false
	uid = res.data.get("user_id", uid)
	_id_token = res.data.get("id_token", "")
	_refresh_token = res.data.get("refresh_token", _refresh_token)
	var exp_in := int(res.data.get("expires_in", "3600"))
	_id_token_expires_at = int(Time.get_unix_time_from_system()) + (exp_in if exp_in > 0 else 3600)
	_save_auth_cache()
	return true


func _load_auth_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_FILE) == OK:
		uid = cfg.get_value("auth", "uid", "")
		_refresh_token = cfg.get_value("auth", "refresh_token", "")
		_id_token = cfg.get_value("auth", "id_token", "")
		_id_token_expires_at = int(cfg.get_value("auth", "expires_at", 0))


func _save_auth_cache() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "uid", uid)
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.set_value("auth", "id_token", _id_token)
	cfg.set_value("auth", "expires_at", _id_token_expires_at)
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

	# Retry once if status 0 (e.g. connection reset or interrupted when returning from background browser)
	if response_code == 0:
		await get_tree().create_timer(0.25, true).timeout
		var retry_req := HTTPRequest.new()
		retry_req.timeout = REQUEST_TIMEOUT_SEC
		add_child(retry_req)
		var retry_err := retry_req.request(url, headers, method, body)
		if retry_err == OK:
			var retry_res: Array = await retry_req.request_completed
			retry_req.queue_free()
			response_code = retry_res[1]
			response_body = retry_res[3]
			text = response_body.get_string_from_utf8()
			parsed = JSON.parse_string(text) if text != "" else null
		else:
			retry_req.queue_free()

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


func is_google_linked() -> bool:
	return profile.get("google_linked", false)


func get_linked_email() -> String:
	return profile.get("google_email", "")


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
	var was_linked: bool = profile.get("google_linked", false)
	var linked_email: String = profile.get("google_email", "")
	profile = {
		"display_name": display_name,
		"display_tag": "%s#%s" % [display_name.to_lower(), tag],
		"tag_number": tag,
		"badge": generate_badge(seed_value),
		"created_at": now,
		"last_seen_at": now,
		"pending_sync": true,
	}
	if was_linked:
		profile["google_linked"] = true
		profile["google_email"] = linked_email
	_save_profile_cache(profile)
	return profile


func sync_pending_profile() -> void:
	if profile.get("pending_sync", false):
		await ensure_profile(profile.get("display_name", ""))


## Validates that the locally cached profile still exists on the server.
## If the account was deleted on another device, clears local state and emits account_deleted.
## Does NOT interfere with offline play: network errors (status 0) preserve the local account.
func validate_session() -> bool:
	if not has_local_profile():
		return false

	if not await ensure_authenticated():
		# Offline or network issue: keep local profile so game remains completely playable offline
		return false

	var url := "%s/profiles/%s" % [_firestore_base_url(), uid]
	var res := await _http_request(url, HTTPClient.METHOD_GET, _auth_headers())
	if res.status == 404:
		# The server explicitly responded 404 Not Found: the account was deleted in the cloud!
		push_warning("Session validation: Remote profile for UID %s no longer exists in Firestore (HTTP 404). Clearing local session." % uid)
		_clear_local_identity()
		if get_tree() and get_tree().root.has_node("SessionManager"):
			var sm = get_tree().root.get_node("SessionManager")
			if sm.has_method("clear_local_data"):
				sm.clear_local_data()
		account_deleted.emit()
		return false

	if res.ok and typeof(res.data) == TYPE_DICTIONARY:
		var remote_profile := FirestoreCodec.decode_document(res.data)
		if not remote_profile.is_empty():
			var needs_heal := false
			# If the remote profile still has google_email from older builds, heal it (delete from remote)
			if remote_profile.has("google_email"):
				needs_heal = true

			# 1) Preserve locally verified Google link state if remote is missing it
			if profile.get("google_linked", false) and not remote_profile.get("google_linked", false):
				remote_profile["google_linked"] = true
				needs_heal = true

			# 2) If linked, ensure we have the private email cached locally from Firebase Auth (not Firestore)
			if remote_profile.get("google_linked", false) or profile.get("google_linked", false):
				remote_profile["google_linked"] = true
				var local_email: String = profile.get("google_email", "")
				if local_email == "":
					var auth_info := await _fetch_auth_user_info()
					local_email = auth_info.get("email", "")
				remote_profile["google_email"] = local_email

			# 3) If still not marked linked, check Firebase Auth provider info directly
			if not remote_profile.get("google_linked", false):
				var auth_info := await _fetch_auth_user_info()
				if auth_info.get("google_linked", false):
					remote_profile["google_linked"] = true
					remote_profile["google_email"] = auth_info.get("email", "")
					needs_heal = true

			profile = remote_profile
			_save_profile_cache(profile)
			if needs_heal:
				await _save_remote_profile(profile)
				google_linked_state_changed.emit(true)
			return true

	# Offline or temporary server error: keep local profile intact for offline play
	return false


func _fetch_auth_user_info() -> Dictionary:
	if _id_token == "":
		return {}
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])
	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify({"idToken": _id_token}))
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY or not res.data.has("users"):
		return {}
	var users: Array = res.data.get("users", [])
	if users.is_empty():
		return {}
	var user_data: Dictionary = users[0]
	var is_linked := false
	var email: String = user_data.get("email", "")
	var providers: Array = user_data.get("providerUserInfo", [])
	for p in providers:
		if typeof(p) == TYPE_DICTIONARY and p.get("providerId", "") == "google.com":
			is_linked = true
			if email == "":
				email = p.get("email", "")
			break
	return {"google_linked": is_linked, "email": email}


## Saves public profile attributes to Firestore.
## NEVER writes personal email to the public Firestore profile.
## Explicitly clears google_email from remote Firestore if it was previously present.
func _save_remote_profile(data: Dictionary) -> bool:
	if not await ensure_authenticated():
		return false
	var public_data := data.duplicate(true)
	public_data.erase("google_email")
	public_data.erase("pending_sync")

	var mask_parts: PackedStringArray = []
	for k in public_data.keys():
		mask_parts.append("updateMask.fieldPaths=%s" % str(k))
	# Explicitly include google_email in updateMask while omitting it from fields so Firestore deletes it
	mask_parts.append("updateMask.fieldPaths=google_email")

	var url := "%s/profiles/%s?%s" % [_firestore_base_url(), uid, "&".join(mask_parts)]
	var body := JSON.stringify(FirestoreCodec.encode_fields(public_data))
	var res := await _http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), body)
	return res.ok


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
	var is_linked: bool = existing.get("google_linked", false) or profile.get("google_linked", false)
	if is_linked:
		data["google_linked"] = true
		var email_val: String = profile.get("google_email", "")
		if email_val == "":
			email_val = existing.get("google_email", "")
		data["google_email"] = email_val
	if await _save_remote_profile(data):
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


# --- Google Account Linking ---------------------------------------------

## Links the current anonymous player identity to a Google account using an OAuth ID Token
## or Access Token. Preserves the player's UID, scores, and stats while upgrading identity.
func link_google_account(google_id_token: String, google_access_token: String = "") -> Dictionary:
	if not await ensure_authenticated():
		return {"ok": false, "error": "auth", "message": "Not authenticated with game server."}

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])

	var post_body := ""
	if google_id_token != "":
		post_body = "id_token=%s&providerId=google.com" % google_id_token
	elif google_access_token != "":
		post_body = "access_token=%s&providerId=google.com" % google_access_token
	else:
		return {"ok": false, "error": "missing_token", "message": "No Google credential provided."}

	var body := JSON.stringify({
		"idToken": _id_token,
		"postBody": post_body,
		"requestUri": "http://localhost",
		"returnSecureToken": true,
	})

	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	if not res.ok:
		var err_msg := ""
		if typeof(res.data) == TYPE_DICTIONARY and res.data.has("error"):
			err_msg = str(res.data["error"].get("message", ""))

		push_warning("link_google_account failed (HTTP %d): %s" % [res.status, err_msg])

		if err_msg.begins_with("FEDERATED_USER_ID_ALREADY_LINKED") or err_msg.begins_with("EMAIL_EXISTS"):
			return {
				"ok": false,
				"error": "already_linked_other",
				"message": "This Google account is already linked to another player. You can sign in with it to restore your account."
			}
		elif err_msg.begins_with("PROVIDER_ALREADY_LINKED"):
			return {
				"ok": false,
				"error": "already_linked",
				"message": "This account is already linked to Google."
			}
		elif err_msg.begins_with("INVALID_IDP_RESPONSE") or err_msg.begins_with("INVALID_ID_TOKEN"):
			return {
				"ok": false,
				"error": "invalid_token",
				"message": "Google authentication failed. Please try again."
			}
		return {
			"ok": false,
			"error": _error_for_status(res.status),
			"message": "Could not link Google account. Check your connection."
		}

	# Update auth tokens
	_id_token = res.data.get("idToken", _id_token)
	_refresh_token = res.data.get("refreshToken", _refresh_token)
	var exp_in := int(res.data.get("expiresIn", "3600"))
	_id_token_expires_at = int(Time.get_unix_time_from_system()) + (exp_in if exp_in > 0 else 3600)
	_save_auth_cache()

	var email: String = res.data.get("email", "")
	profile["google_linked"] = true
	profile["google_email"] = email
	profile["last_seen_at"] = Time.get_datetime_string_from_system(true)

	# Fetch remote profile only if local profile is incomplete
	if profile.get("display_name", "") == "":
		var existing := await get_document("profiles/%s" % uid)
		for k in existing:
			if not profile.has(k) or str(profile[k]) == "":
				profile[k] = existing[k]

	_save_profile_cache(profile)
	await _save_remote_profile(profile)

	google_linked_state_changed.emit(true)
	return {"ok": true, "email": email, "message": "Google account successfully connected."}


## Signs in to an existing Google-linked account (e.g. restoring identity across devices).
func sign_in_with_google(google_id_token: String, google_access_token: String = "") -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])

	var post_body := ""
	if google_id_token != "":
		post_body = "id_token=%s&providerId=google.com" % google_id_token
	elif google_access_token != "":
		post_body = "access_token=%s&providerId=google.com" % google_access_token
	else:
		return {"ok": false, "error": "missing_token", "message": "No Google credential provided."}

	var body := JSON.stringify({
		"postBody": post_body,
		"requestUri": "http://localhost",
		"returnSecureToken": true,
	})

	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	if not res.ok:
		var err_msg := ""
		if typeof(res.data) == TYPE_DICTIONARY and res.data.has("error"):
			err_msg = str(res.data["error"].get("message", ""))
		push_warning("sign_in_with_google failed (HTTP %d): %s" % [res.status, err_msg])
		return {"ok": false, "error": _error_for_status(res.status), "message": "Failed to sign in with Google. Check connection."}

	uid = res.data.get("localId", uid)
	_id_token = res.data.get("idToken", _id_token)
	_refresh_token = res.data.get("refreshToken", _refresh_token)
	var exp_in := int(res.data.get("expiresIn", "3600"))
	_id_token_expires_at = int(Time.get_unix_time_from_system()) + (exp_in if exp_in > 0 else 3600)
	_save_auth_cache()

	# Fetch existing profile from Firestore
	var existing := await get_document("profiles/%s" % uid)
	var is_existing_player: bool = not existing.is_empty() and str(existing.get("display_name", "")) != ""
	if is_existing_player:
		profile = existing
	else:
		var email: String = res.data.get("email", "")
		var google_display_name: String = res.data.get("displayName", "")
		var clean_name: String = normalize_display_name(google_display_name) if google_display_name != "" else ""
		if clean_name != "" and validate_display_name(clean_name) == "":
			profile = {
				"display_name": clean_name,
				"display_tag": "%s#%s" % [clean_name.to_lower(), generate_tag(uid)],
				"tag_number": generate_tag(uid),
				"badge": generate_badge(uid),
				"created_at": Time.get_datetime_string_from_system(true),
				"last_seen_at": Time.get_datetime_string_from_system(true),
			}
		else:
			var fallback_name := email.split("@")[0] if email != "" else ""
			fallback_name = normalize_display_name(fallback_name)
			if fallback_name.length() > DISPLAY_NAME_MAX:
				fallback_name = fallback_name.substr(0, DISPLAY_NAME_MAX)
			profile = {
				"display_name": fallback_name,
				"display_tag": "%s#%s" % [fallback_name.to_lower(), generate_tag(uid)],
				"tag_number": generate_tag(uid),
				"badge": generate_badge(uid),
				"created_at": Time.get_datetime_string_from_system(true),
				"last_seen_at": Time.get_datetime_string_from_system(true),
			}

	profile["google_linked"] = true
	profile["google_email"] = res.data.get("email", "")
	_save_profile_cache(profile)

	# Always ensure remote Firestore document is saved with google_linked, omitting personal email!
	await _save_remote_profile(profile)

	auth_ready.emit(uid)
	google_linked_state_changed.emit(true)
	return {
		"ok": true,
		"uid": uid,
		"profile": profile,
		"email": profile["google_email"],
		"is_existing_player": is_existing_player
	}


## Unlinks Google provider from the current account, reverting it to anonymous credentials.
func unlink_google_account() -> Dictionary:
	if not await ensure_authenticated():
		return {"ok": false, "error": "auth"}

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:unlink?key=%s" % FirebaseConfig.API_KEY
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({
		"idToken": _id_token,
		"deleteProvider": ["google.com"]
	})

	var res := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	if not res.ok:
		return {"ok": false, "error": _error_for_status(res.status)}

	_id_token = res.data.get("idToken", _id_token)
	_refresh_token = res.data.get("refreshToken", _refresh_token)
	var exp_in := int(res.data.get("expiresIn", "3600"))
	_id_token_expires_at = int(Time.get_unix_time_from_system()) + (exp_in if exp_in > 0 else 3600)
	_save_auth_cache()

	profile["google_linked"] = false
	profile.erase("google_email")
	profile["last_seen_at"] = Time.get_datetime_string_from_system(true)
	_save_profile_cache(profile)

	await _save_remote_profile(profile)

	GoogleAuth.sign_out()
	google_linked_state_changed.emit(false)
	return {"ok": true}


## Signs out the current player identity on this device.
## Leaves cloud data intact while clearing local device caches and session state.
func sign_out() -> void:
	_clear_local_identity()
	if get_tree() and get_tree().root.has_node("SessionManager"):
		var sm = get_tree().root.get_node("SessionManager")
		if sm.has_method("clear_local_data"):
			sm.clear_local_data()
	GoogleAuth.sign_out()
	google_linked_state_changed.emit(false)
	account_deleted.emit()


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
		# Ensure we have a valid id token. Use the one already in memory if
		# present (matches ensure_authenticated() behaviour); only refresh when
		# we don't have one. Don't fall through to ensure_authenticated() because
		# a failed refresh there would sign up a new anonymous user and we'd
		# "delete" the wrong account.
		if _id_token == "":
			if _refresh_token == "":
				# Nothing usable — can't authenticate.
				return {"ok": false, "error": "auth"}
			# Save tokens before the refresh attempt. _refresh_id_token() clears
			# both tokens on failure; we restore them here so that a transient
			# network error doesn't corrupt local state and make a second tap
			# silently 'succeed' without touching Firebase.
			var saved_refresh := _refresh_token
			var saved_uid := uid
			if not await _refresh_id_token():
				_refresh_token = saved_refresh
				uid = saved_uid
				_save_auth_cache()
				return {"ok": false, "error": "auth"}

		var my_uid := uid
		var query_body := {
			"from": [{"collectionId": "scores"}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "uid"},
				"op": "EQUAL",
				"value": {"stringValue": my_uid},
			}},
			"select": {"fields": [{"fieldPath": "__name__"}]},
		}
		var scores := await _query_document_names(query_body)
		# Transparently retry once on a network/timeout failure (status 0).
		# The first request after a cold start often loses the race against the
		# 10s timeout while TLS is being established; a second attempt succeeds
		# immediately on the warm connection.
		if not scores.ok and scores.error == "network":
			await get_tree().create_timer(1.0).timeout
			scores = await _query_document_names(query_body)
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
				# Network/timeout: retry once on the now-warm connection.
				if res.status == 0:
					await get_tree().create_timer(1.0).timeout
					res = await _commit_deletes(names.slice(start, start + batch_size))
				# 401 = expired id token — refresh once and retry the same batch.
				elif res.status == 401 and _refresh_token != "":
					if await _refresh_id_token():
						res = await _commit_deletes(names.slice(start, start + batch_size))
				if not res.ok:
					return {"ok": false, "error": "auth" if res.status == 401 else _error_for_status(res.status)}

		var auth_res := await _delete_auth_account()
		if not auth_res.ok:
			push_warning("delete_account: Auth delete failed (HTTP %d): %s" % [auth_res.status, JSON.stringify(auth_res.data)])
			# The Firestore data was already removed; try one token refresh so the
			# auth account delete can still succeed on the same attempt.
			if auth_res.status == 401 and _refresh_token != "":
				if await _refresh_id_token():
					auth_res = await _delete_auth_account()
			if not auth_res.ok:
				return {"ok": false, "error": "auth" if auth_res.status == 401 else _error_for_status(auth_res.status)}

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
	_id_token_expires_at = 0
	_leaderboard_cache.clear()
	profile = {}
	GoogleAuth.sign_out()
	for file_path: String in [AUTH_FILE, PROFILE_CACHE_FILE]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
			var da := DirAccess.open("user://")
			if da:
				var fname: String = file_path.replace("user://", "")
				if da.file_exists(fname):
					da.remove(fname)


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

	_leaderboard_cache.clear()

	var score_payload := {
		"uid": uid,
		"display_name": profile.get("display_name", ""),
		"display_tag": profile.get("display_tag", ""),
		"game_mode": game_mode,
		"score": score,
		"reps": reps,
		"created_at": Time.get_datetime_string_from_system(true),
	}

	var doc := await create_document("scores", score_payload)
	if doc.is_empty():
		return false
	await _update_best_score(game_mode, score)
	return true


## Best-effort read-then-write; fine for a single device updating its own
## row sequentially. Not a Firestore transaction — security rules are the
## actual backstop against a lower score overwriting a higher one.
func _update_best_score(game_mode: String, score: int) -> bool:
	var local_best := 0
	if get_tree() and get_tree().root.has_node("SessionManager"):
		var sm = get_tree().root.get_node("SessionManager")
		if sm.has_method("get_best_score"):
			local_best = sm.get_best_score(game_mode)

	# If the current score is strictly lower than our known local best, skip network write
	if local_best > score:
		return false

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


## Returns {"ok": bool, "rows": Array}. Serves from in-memory cache if queried within LEADERBOARD_CACHE_TTL_MS.
func fetch_leaderboard(game_mode: String, limit: int = 20, force_refresh: bool = false) -> Dictionary:
	var cache_key := "%s_%d" % [game_mode, limit]
	var now := Time.get_ticks_msec()
	if not force_refresh and _leaderboard_cache.has(cache_key):
		var entry: Dictionary = _leaderboard_cache[cache_key]
		if now - int(entry.get("timestamp", 0)) < LEADERBOARD_CACHE_TTL_MS:
			return {"ok": true, "rows": entry.get("rows", [])}

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
	if res.ok:
		_leaderboard_cache[cache_key] = {
			"timestamp": now,
			"rows": res.docs,
		}
	return {"ok": res.ok, "rows": res.docs}


func invalidate_leaderboard_cache() -> void:
	_leaderboard_cache.clear()
