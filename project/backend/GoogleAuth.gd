class_name GoogleAuth
extends RefCounted

## Helper for Google OAuth 2.0 PKCE / Authorization Code Flow.
## Works on Desktop (Windows, macOS, Linux) and Android via system browser + local loopback listener (RFC 8252).
## Uses a background worker thread to ensure the TCP redirect is captured and responded to immediately,
## even while the Android app activity is paused in the background.

const REDIRECT_PORT_START := 8910
const REDIRECT_PORT_END := 8920
const AUTH_TIMEOUT_SEC := 90.0

class LoopbackWorker extends RefCounted:
	var server: TCPServer
	var state: String
	var is_done: bool = false
	var should_stop: bool = false
	var auth_code: String = ""
	var state_ok: bool = false

	func poll_loop() -> void:
		while not should_stop:
			if server and server.is_connection_available():
				var peer := server.take_connection()
				var wait_ticks := Time.get_ticks_msec() + 3000
				while peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() == 0 and Time.get_ticks_msec() < wait_ticks:
					OS.delay_msec(20)

				var bytes_avail := peer.get_available_bytes()
				if bytes_avail > 0:
					var request_str := peer.get_utf8_string(bytes_avail)
					var query_params := GoogleAuth._parse_http_query(request_str)

					if query_params.get("state", "") == state:
						state_ok = true
						auth_code = query_params.get("code", "")

					var html := GoogleAuth._build_browser_response_html(auth_code != "")
					var http_response := "HTTP/1.1 200 OK\r\n" + \
						"Content-Type: text/html; charset=utf-8\r\n" + \
						"Content-Length: %d\r\n" % html.to_utf8_buffer().size() + \
						"Connection: close\r\n\r\n" + html

					peer.put_data(http_response.to_utf8_buffer())
					OS.delay_msec(150)
					peer.disconnect_from_host()
					is_done = true
					break
			OS.delay_msec(40)


class NativeSignInState extends RefCounted:
	var completed: bool = false
	var result: Dictionary = {}

	func on_success(data: Dictionary) -> void:
		if completed:
			return
		completed = true
		result = {
			"ok": true,
			"id_token": str(data.get("idToken", "")),
			"access_token": str(data.get("accessToken", "")),
			"email": str(data.get("email", "")),
			"display_name": str(data.get("displayName", "")),
		}

	func on_failed(error_msg: String) -> void:
		if completed:
			return
		completed = true
		result = {
			"ok": false,
			"error": "sign_in_failed",
			"message": error_msg
		}


static func is_configured() -> bool:
	return FirebaseConfig.is_google_configured()


static func authenticate(node: Node) -> Dictionary:
	if not is_configured():
		return {
			"ok": false,
			"error": "not_configured",
			"message": "Google Client ID is not configured in FirebaseConfig.gd."
		}

	# Native Android Google Sign-In Sheet (play-services-auth)
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotGoogleSignIn"):
			var plugin: Object = Engine.get_singleton("GodotGoogleSignIn")
			print("[GoogleAuth] Using native Android GodotGoogleSignIn plugin")
			return await _authenticate_android_native(node, plugin)
		else:
			push_warning("[GoogleAuth] GodotGoogleSignIn singleton not found on Android, falling back.")

	# Desktop & Fallback: Loopback OAuth flow with background worker thread
	return await _authenticate_loopback(node)


static func _authenticate_android_native(node: Node, plugin: Object) -> Dictionary:
	var state := NativeSignInState.new()
	var success_cb := Callable(state, "on_success")
	var failed_cb := Callable(state, "on_failed")

	if plugin.has_signal("signInSuccess"):
		plugin.connect("signInSuccess", success_cb, Object.CONNECT_ONE_SHOT)
	if plugin.has_signal("signInFailed"):
		plugin.connect("signInFailed", failed_cb, Object.CONNECT_ONE_SHOT)

	plugin.call("signIn", FirebaseConfig.GOOGLE_CLIENT_ID)

	var start_ms := Time.get_ticks_msec()
	var timeout_ms := 60000
	var tree := node.get_tree()

	while not state.completed and (Time.get_ticks_msec() - start_ms) < timeout_ms:
		await tree.create_timer(0.1, true).timeout

	if plugin.is_connected("signInSuccess", success_cb):
		plugin.disconnect("signInSuccess", success_cb)
	if plugin.is_connected("signInFailed", failed_cb):
		plugin.disconnect("signInFailed", failed_cb)

	if not state.completed:
		return {
			"ok": false,
			"error": "timeout",
			"message": "Google Sign-In was cancelled or timed out."
		}

	return state.result


static func sign_out() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("GodotGoogleSignIn"):
		var plugin: Object = Engine.get_singleton("GodotGoogleSignIn")
		if plugin.has_method("signOut"):
			plugin.call("signOut")


static func _authenticate_loopback(node: Node) -> Dictionary:
	var tree := node.get_tree()
	var server := TCPServer.new()
	var port := REDIRECT_PORT_START
	var bound := false

	for p in range(REDIRECT_PORT_START, REDIRECT_PORT_END + 1):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			bound = true
			break

	if not bound:
		return {
			"ok": false,
			"error": "port_busy",
			"message": "Could not bind local port for Google authentication."
		}

	var redirect_uri := "http://127.0.0.1:%d" % port
	var code_verifier := _generate_code_verifier()
	var code_challenge := _generate_code_challenge(code_verifier)
	var state := _generate_random_token(16)

	var auth_url := "https://accounts.google.com/o/oauth2/v2/auth?" + \
		"client_id=" + _get_desktop_client_id().uri_encode() + \
		"&redirect_uri=" + redirect_uri.uri_encode() + \
		"&response_type=code" + \
		"&scope=" + "openid%20email%20profile" + \
		"&code_challenge=" + code_challenge.uri_encode() + \
		"&code_challenge_method=S256" + \
		"&state=" + state.uri_encode()

	var worker := LoopbackWorker.new()
	worker.server = server
	worker.state = state

	var thread := Thread.new()
	thread.start(Callable(worker, "poll_loop"))

	var open_err := OS.shell_open(auth_url)
	if open_err != OK:
		worker.should_stop = true
		thread.wait_to_finish()
		server.stop()
		return {
			"ok": false,
			"error": "browser_error",
			"message": "Could not open browser for Google authentication."
		}

	var start_time := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start_time) < int(AUTH_TIMEOUT_SEC * 1000.0) and not worker.is_done:
		await tree.create_timer(0.2, true).timeout

	worker.should_stop = true
	thread.wait_to_finish()
	server.stop()

	var auth_code: String = worker.auth_code
	var state_ok: bool = worker.state_ok

	if auth_code == "":
		return {
			"ok": false,
			"error": "timeout",
			"message": "Google authentication timed out or was cancelled."
		}

	if not state_ok:
		return {
			"ok": false,
			"error": "state_mismatch",
			"message": "Security validation failed. Please try again."
		}

	# Exchange authorization code for tokens
	return await _exchange_code_for_tokens(node, auth_code, redirect_uri, code_verifier)


static func _get_desktop_client_id() -> String:
	if FirebaseConfig.GOOGLE_DESKTOP_CLIENT_ID != "":
		return FirebaseConfig.GOOGLE_DESKTOP_CLIENT_ID
	return FirebaseConfig.GOOGLE_CLIENT_ID

static func _get_client_secret() -> String:
	if FirebaseConfig.GOOGLE_CLIENT_SECRET != "":
		return FirebaseConfig.GOOGLE_CLIENT_SECRET
	for p in ["res://backend/local_dev_secret.txt", "user://local_dev_secret.txt"]:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f:
				var sec := f.get_as_text().strip_edges()
				if sec != "":
					return sec
	return ""

static func _exchange_code_for_tokens(node: Node, code: String, redirect_uri: String, code_verifier: String) -> Dictionary:
	var token_url := "https://oauth2.googleapis.com/token"
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var desktop_id := _get_desktop_client_id()
	var secret := _get_client_secret()
	var body_parts := [
		"code=" + code.uri_encode(),
		"client_id=" + desktop_id.uri_encode(),
		"grant_type=authorization_code",
		"redirect_uri=" + redirect_uri.uri_encode(),
		"code_verifier=" + code_verifier.uri_encode(),
	]
	if secret != "":
		body_parts.append("client_secret=" + secret.uri_encode())

	var body := "&".join(body_parts)

	var req := HTTPRequest.new()
	req.timeout = 20.0
	node.add_child(req)

	var err := req.request(token_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "network", "message": "Failed to exchange code for tokens."}

	var res: Array = await req.request_completed
	req.queue_free()

	var status_code: int = res[1]
	var resp_bytes: PackedByteArray = res[3]
	var resp_str := resp_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(resp_str) if resp_str != "" else null

	# Retry once if status 0 (e.g. connection reset when returning from background browser)
	if status_code == 0:
		await node.get_tree().create_timer(0.5, true).timeout
		var retry_req := HTTPRequest.new()
		retry_req.timeout = 20.0
		node.add_child(retry_req)
		var retry_err := retry_req.request(token_url, headers, HTTPClient.METHOD_POST, body)
		if retry_err == OK:
			var retry_res: Array = await retry_req.request_completed
			retry_req.queue_free()
			status_code = retry_res[1]
			resp_bytes = retry_res[3]
			resp_str = resp_bytes.get_string_from_utf8()
			parsed = JSON.parse_string(resp_str) if resp_str != "" else null
		else:
			retry_req.queue_free()

	if status_code < 200 or status_code >= 300 or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GoogleAuth token exchange failed (%d): %s" % [status_code, resp_str])
		return {"ok": false, "error": "exchange_failed", "message": "Failed to obtain Google tokens."}

	var id_token: String = parsed.get("id_token", "")
	var access_token: String = parsed.get("access_token", "")

	if id_token == "" and access_token == "":
		return {"ok": false, "error": "missing_token", "message": "No tokens returned from Google."}

	return {
		"ok": true,
		"id_token": id_token,
		"access_token": access_token,
		"error": "",
		"message": ""
	}


static func _parse_http_query(request_str: String) -> Dictionary:
	var result := {}
	var lines := request_str.split("\r\n")
	if lines.size() == 0:
		return result
	var req_line := lines[0] # e.g. "GET /?code=xxx&state=yyy HTTP/1.1"
	var parts := req_line.split(" ")
	if parts.size() < 2:
		return result
	var path := parts[1]
	var q_idx := path.find("?")
	if q_idx == -1:
		return result
	var query := path.substr(q_idx + 1)
	var pairs := query.split("&")
	for pair in pairs:
		var kv := pair.split("=")
		if kv.size() == 2:
			result[kv[0]] = kv[1].uri_decode()
	return result


static func _generate_code_verifier() -> String:
	return _generate_random_token(48)


static func _generate_code_challenge(verifier: String) -> String:
	var hashing_context := HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(verifier.to_ascii_buffer())
	var digest := hashing_context.finish()
	return _base64_url_encode(digest)


static func _generate_random_token(length: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	var res := ""
	for i in range(length):
		res += chars[randi() % chars.length()]
	return res


static func _base64_url_encode(bytes: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(bytes)
	return b64.replace("+", "-").replace("/", "_").replace("=", "")


static func _build_browser_response_html(success: bool) -> String:
	if success:
		return """<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>FitArcade — Connected</title>
	<style>
		body {
			background: #050506;
			color: #FFFFFF;
			font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
			display: flex;
			align-items: center;
			justify-content: center;
			height: 100vh;
			margin: 0;
			text-align: center;
		}
		.card {
			background: #151517;
			border: 1px solid #2A2A2E;
			padding: 40px 32px;
			max-width: 360px;
			box-shadow: 0 8px 32px rgba(0,0,0,0.5);
		}
		h1 {
			color: #D4FF3A;
			margin: 0 0 12px;
			font-size: 24px;
			letter-spacing: 2px;
		}
		p {
			color: #8A8A92;
			font-size: 14px;
			line-height: 1.5;
			margin: 0 0 24px;
		}
		.btn {
			display: inline-block;
			background: #D4FF3A;
			color: #0B0B0C;
			font-weight: bold;
			font-size: 13px;
			padding: 12px 24px;
			text-decoration: none;
			letter-spacing: 1px;
		}
	</style>
</head>
<body>
	<div class="card">
		<h1>CONNECTED</h1>
		<p>Google verification complete. Return to FitArcade to continue.</p>
		<a href="intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=com.fitarcade.app;end" class="btn">RETURN TO FITARCADE</a>
	</div>
	<script>
		setTimeout(function() {
			window.location.href = "intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=com.fitarcade.app;end";
		}, 300);
	</script>
</body>
</html>"""
	else:
		return """<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>FitArcade — Error</title>
	<style>
		body { background: #050506; color: #FFFFFF; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; }
		.card { background: #151517; border: 1px solid #FF3B2F; padding: 40px 32px; max-width: 360px; }
		h1 { color: #FF3B2F; margin: 0 0 12px; }
		p { color: #8A8A92; font-size: 14px; }
	</style>
</head>
<body>
	<div class="card">
		<h1>SIGN-IN FAILED</h1>
		<p>Authentication could not be completed. Please return to FitArcade and try again.</p>
	</div>
</body>
</html>"""
