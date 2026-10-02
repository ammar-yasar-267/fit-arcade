extends ColorRect

## Main App State Machine and Screen Host for FitArcade.
## Implements the navigation architecture from design-spec.md Section A & G.
## Manages global app state (screen, mode, locked states, run count)
## while keeping existing backend and game management systems functional.

const HubScene = preload("res://ui/screens/Hub.tscn")
const OnboardingScene = preload("res://ui/screens/Onboarding.tscn")

## Settings > "Replay onboarding" sets this engine meta, then reloads Main. It has to
## survive a scene change but must never persist across launches, hence meta
## rather than a saved setting.
const REPLAY_ONBOARDING_META := "replay_onboarding"

var screen: String = "hub"
var mode_id: String = "dino"
var run: int = 0
var locked_modes: Dictionary = {"dino": false, "lane": false, "flappy": false}
var app_settings: Dictionary = {"accel": "GPU", "jack": 150, "lunge": 100, "arm": 120}

var _screen_host: Control
var _active_screen_node: Node
var _maintenance_block: Control

func _ready() -> void:
	color = Tokens.INK

	_screen_host = get_node_or_null("ScreenHost")
	if not _screen_host:
		_screen_host = Control.new()
		_screen_host.name = "ScreenHost"
		_screen_host.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_screen_host)

	if OS.get_name() == "Android":
		OS.request_permissions()

	# Locks and maintenance mode come from remote config. Apply the copy cached from
	# the last session first, so the very first frame already matches it; the network
	# refresh below then only has to correct what changed. (Before this, every game
	# looked unlocked until the first round trip finished.)
	_apply_remote_state()
	_refresh_remote_state()

	# Periodic poll for remote state (maintenance & locks)
	var poll_timer := Timer.new()
	poll_timer.wait_time = 5.0
	poll_timer.autostart = true
	poll_timer.timeout.connect(_refresh_remote_state)
	add_child(poll_timer)

	# One-shot: consume the replay request so a later relaunch goes back to normal
	var replay_onboarding: bool = Engine.has_meta(REPLAY_ONBOARDING_META)
	if replay_onboarding:
		Engine.remove_meta(REPLAY_ONBOARDING_META)

	# No profile yet (first launch, or the account was deleted): ask for a name first
	if replay_onboarding:
		show_screen("onboarding", true)
	else:
		show_screen("hub" if Backend.has_local_profile() else "onboarding")

	# A name saved offline during onboarding gets pushed to the server once we can
	Backend.sync_pending_profile()

func show_screen(target_screen: String, replay: bool = false) -> void:
	screen = target_screen

	if _active_screen_node and is_instance_valid(_active_screen_node):
		_active_screen_node.queue_free()
		_active_screen_node = null

	match target_screen:
		"onboarding":
			var onboarding = OnboardingScene.instantiate()
			onboarding.replay_mode = replay
			onboarding.completed.connect(_on_onboarding_completed)
			onboarding.cancelled.connect(_on_onboarding_completed)
			_screen_host.add_child(onboarding)
			_active_screen_node = onboarding

		"hub":
			var hub = HubScene.instantiate()
			hub.locked_modes = locked_modes
			hub.mode_picked.connect(_on_hub_mode_picked)
			hub.nav_requested.connect(_on_hub_nav_requested)
			_screen_host.add_child(hub)
			_active_screen_node = hub

		"calibrate":
			# Set GameManager pending mode and launch calibration
			GameManager.pending_game_name = mode_id
			GameManager.selected_game_name = ""
			if ResourceLoader.exists("res://ui/CalibrationScreen.tscn"):
				get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")

		"leaderboard":
			if ResourceLoader.exists("res://ui/LeaderboardScreen.tscn"):
				get_tree().change_scene_to_file("res://ui/LeaderboardScreen.tscn")

		"settings":
			if ResourceLoader.exists("res://ui/SettingsScreen.tscn"):
				get_tree().change_scene_to_file("res://ui/SettingsScreen.tscn")
			elif ResourceLoader.exists("res://SettingsMenu.tscn"):
				get_tree().change_scene_to_file("res://SettingsMenu.tscn")

		_:
			push_warning("Unknown target screen: %s" % target_screen)

func _on_onboarding_completed() -> void:
	show_screen("hub")

func _on_hub_mode_picked(picked_mode: String) -> void:
	mode_id = picked_mode
	run += 1
	if get_tree().root.has_node("SessionManager"):
		SessionManager.set_last_played_mode(picked_mode)
	show_screen("calibrate")

func _on_hub_nav_requested(screen_name: String) -> void:
	show_screen(screen_name)

func _refresh_remote_state() -> void:
	await Backend.fetch_app_config()
	_apply_remote_state()

## Applies whatever remote config Backend currently holds (cached from a previous
## session, or just fetched). With no config at all the defaults are "unlocked, no
## maintenance": a first-ever launch offline can't know better, and shouldn't block play.
func _apply_remote_state() -> void:
	for m_id in ["dino", "lane", "flappy"]:
		var backend_key = "switcher" if m_id == "lane" else m_id
		locked_modes[m_id] = not Backend.is_game_mode_enabled(backend_key)

	if _active_screen_node and _active_screen_node.has_method("set_locked_modes"):
		_active_screen_node.locked_modes = locked_modes
	elif _active_screen_node and "locked_modes" in _active_screen_node:
		_active_screen_node.locked_modes = locked_modes

	_update_maintenance_block()

func _update_maintenance_block() -> void:
	if not Backend.is_maintenance_mode():
		if _maintenance_block:
			_maintenance_block.queue_free()
			_maintenance_block = null
		return
	if _maintenance_block:
		return

	var overlay := ColorRect.new()
	overlay.color = Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var pstyle := Tokens.make_panel_style(Tokens.PANEL, Tokens.SIGNAL, 2)
	pstyle.content_margin_left = 32
	pstyle.content_margin_right = 32
	pstyle.content_margin_top = 32
	pstyle.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 14)
	panel.add_child(inner)

	var title := Label.new()
	title.text = "UNDER MAINTENANCE"
	title.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Tokens.SIGNAL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FitArcade is temporarily unavailable. Please check back soon."
	subtitle.add_theme_font_override("font", Tokens.FONT_SANS)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Tokens.DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(subtitle)

	_maintenance_block = overlay
	add_child(overlay)
