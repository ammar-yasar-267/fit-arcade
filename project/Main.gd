extends ColorRect

const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")
const BG_PRIMARY = Color(0.0157, 0.0157, 0.0627)
const BG_SECONDARY = Color("#0F0B21")

const ICON_DINO: Texture2D = preload("res://ui/assets/home/dino-jumping-jacks.svg")
const ICON_FLAPPY: Texture2D = preload("res://ui/assets/home/flappybird-arm-raises.svg")
const ICON_LANE: Texture2D = preload("res://ui/assets/home/lane-runner-lunges.svg")

var _game_cards: Dictionary = {}
var _maintenance_block: Control

func _get_game_accent(game_id: String) -> Color:
	match game_id:
		"dino": return Color("#F59E0B")
		"switcher": return Color("#22C55E")
		"flappy": return Color("#06B6D4")
		_: return BRAND_CYAN

func _ready() -> void:
	# Apply a simple gradient shader
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 top_color = vec4(0.0157, 0.0157, 0.0627, 1.0);
uniform vec4 bottom_color = vec4(0.059, 0.043, 0.129, 1.0);

void fragment() {
	COLOR = mix(top_color, bottom_color, UV.y);
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("top_color", Color(0.0157, 0.0157, 0.0627, 1.0))
	material.set_shader_parameter("bottom_color", Color(0.059, 0.043, 0.129, 1.0))
	set_material(material)
	
	_build_ui()
	if OS.get_name() == "Android":
		OS.request_permissions()
	_refresh_remote_state()
	if not Backend.has_local_profile():
		_show_player_card_intro()

	# Polling, not push — no native Firestore SDK means no persistent
	# connection, so this is the closest to "instant" a REST-only client
	# gets. Only runs while sitting on the home screen.
	var poll_timer := Timer.new()
	poll_timer.wait_time = 5.0
	poll_timer.autostart = true
	poll_timer.timeout.connect(_refresh_remote_state)
	add_child(poll_timer)

func _refresh_remote_state() -> void:
	await Backend.fetch_app_config()
	for game_id in _game_cards.keys():
		_set_game_card_disabled(game_id, not Backend.is_game_mode_enabled(game_id))
	_update_maintenance_block()

## Disabled game modes stay visible (so players know the mode exists) but get
## a blocking "Under Maintenance" ribbon over the card instead of being hidden.
func _set_game_card_disabled(game_id: String, disabled: bool) -> void:
	var card: PanelContainer = _game_cards[game_id]
	var existing := card.get_node_or_null("MaintenanceOverlay")
	if not disabled:
		if existing:
			existing.queue_free()
		return
	if existing:
		return

	var overlay := PanelContainer.new()
	overlay.name = "MaintenanceOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0157, 0.0157, 0.0627, 0.82)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	overlay.add_theme_stylebox_override("panel", style)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#EF4444", 0.18)
	badge_style.border_width_left = 1
	badge_style.border_width_right = 1
	badge_style.border_width_top = 1
	badge_style.border_width_bottom = 1
	badge_style.border_color = Color("#EF4444", 0.5)
	badge_style.corner_radius_top_left = 999
	badge_style.corner_radius_top_right = 999
	badge_style.corner_radius_bottom_left = 999
	badge_style.corner_radius_bottom_right = 999
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	badge_style.content_margin_top = 8
	badge_style.content_margin_bottom = 8
	badge.add_theme_stylebox_override("panel", badge_style)
	center.add_child(badge)

	var badge_label := Label.new()
	badge_label.text = "🔧 Under Maintenance"
	badge_label.add_theme_font_size_override("font_size", 16)
	badge_label.add_theme_color_override("font_color", Color("#EF4444"))
	badge.add_child(badge_label)

	card.add_child(overlay)

## Maintenance mode is a hard lock, not a hint: a full-screen, non-dismissable
## overlay that sits on top of everything (game cards, the leaderboard button,
## even an in-progress Player Card claim) and swallows all input, so nothing
## on the home screen is reachable while it's active.
func _update_maintenance_block() -> void:
	if not Backend.is_maintenance_mode():
		if _maintenance_block:
			_maintenance_block.queue_free()
			_maintenance_block = null
		return
	if _maintenance_block:
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0.0157, 0.0157, 0.0627, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = CARD_SURFACE
	pstyle.border_width_top = 4
	pstyle.border_color = Color("#EF4444")
	pstyle.corner_radius_top_left = 28
	pstyle.corner_radius_top_right = 28
	pstyle.corner_radius_bottom_left = 28
	pstyle.corner_radius_bottom_right = 28
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

	var icon := Label.new()
	icon.text = "🚧"
	icon.add_theme_font_size_override("font_size", 56)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(icon)

	var title := Label.new()
	title.text = "Under Maintenance"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#EF4444"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FitArcade is temporarily unavailable. Please check back soon."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(subtitle)

	_maintenance_block = overlay
	add_child(overlay)

func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 48)
	margin.add_child(vbox)

	# --- Header ---
	var header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "FitArcade"
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Move your body. Control the game."
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)

	# --- Game cards scroll ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var games_vbox = VBoxContainer.new()
	games_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_vbox.add_theme_constant_override("separation", 18)
	scroll.add_child(games_vbox)

	_create_game_card(games_vbox, "Chrome Dino", "Jumping Jacks", "dino")
	_create_game_card(games_vbox, "Lane Switcher", "Lunges", "switcher")
	_create_game_card(games_vbox, "Flappy Bird", "Arm Raises", "flappy")

	# Add footer spacing
	var footer_spacer = Control.new()
	footer_spacer.custom_minimum_size = Vector2(0, 32)
	games_vbox.add_child(footer_spacer)

	var leaderboard_btn := Button.new()
	leaderboard_btn.text = "🏆  Leaderboards"
	leaderboard_btn.add_theme_font_size_override("font_size", 18)
	leaderboard_btn.custom_minimum_size = Vector2(0, 52)
	leaderboard_btn.flat = true
	leaderboard_btn.add_theme_color_override("font_color", BRAND_CYAN)
	leaderboard_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://ui/LeaderboardScreen.tscn")
	)
	vbox.add_child(leaderboard_btn)

func _create_game_card(parent: Control, game_name: String, exercise_name: String, game_id: String) -> void:
	var accent = _get_game_accent(game_id)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 168)
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	# Add left colored border and subtle border
	style.border_width_left = 3
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = accent
	style.expand_margin_left = 0
	card.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	card.add_child(hbox)

	# Icon section - with better padding
	var icon_margin := MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 22)
	icon_margin.add_theme_constant_override("margin_right", 20)
	hbox.add_child(icon_margin)

	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(100, 100)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	icon_style.corner_radius_top_left = 16
	icon_style.corner_radius_top_right = 16
	icon_style.corner_radius_bottom_left = 16
	icon_style.corner_radius_bottom_right = 16
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_margin.add_child(icon_panel)

	var icon_box = CenterContainer.new()
	icon_panel.add_child(icon_box)

	var icon = TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	match game_id:
		"dino": icon.texture = ICON_DINO
		"flappy": icon.texture = ICON_FLAPPY
		"switcher": icon.texture = ICON_LANE
		_: icon.texture = ICON_DINO
	icon_box.add_child(icon)

	# Text content - improved layout
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 11)
	var vbox_margin := MarginContainer.new()
	vbox_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_margin.add_theme_constant_override("margin_right", 18)
	vbox_margin.add_child(vbox)
	hbox.add_child(vbox_margin)

	var name_label = Label.new()
	name_label.text = game_name
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(name_label)

	var pill = PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pill_style = StyleBoxFlat.new()
	pill_style.bg_color = Color(accent.r, accent.g, accent.b, 0.15)
	pill_style.border_width_left = 1
	pill_style.border_width_right = 1
	pill_style.border_width_top = 1
	pill_style.border_width_bottom = 1
	pill_style.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	pill_style.corner_radius_top_left = 999
	pill_style.corner_radius_top_right = 999
	pill_style.corner_radius_bottom_left = 999
	pill_style.corner_radius_bottom_right = 999
	pill_style.content_margin_left = 14
	pill_style.content_margin_right = 14
	pill_style.content_margin_top = 5
	pill_style.content_margin_bottom = 5
	pill.add_theme_stylebox_override("panel", pill_style)
	vbox.add_child(pill)

	var pill_label = Label.new()
	pill_label.text = exercise_name
	pill_label.add_theme_font_size_override("font_size", 16)
	pill_label.add_theme_color_override("font_color", accent)
	pill.add_child(pill_label)

	# Play strip - enhanced design with accent color
	var play_strip := Button.new()
	play_strip.custom_minimum_size = Vector2(128, 0)
	play_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = Color(accent.r, accent.g, accent.b, 0.2)
	play_style.corner_radius_top_right = 20
	play_style.corner_radius_bottom_right = 20
	play_style.border_width_left = 2
	play_style.border_color = accent
	play_strip.add_theme_stylebox_override("normal", play_style)
	var play_hover_style := play_style.duplicate()
	play_hover_style.bg_color = Color(accent.r, accent.g, accent.b, 0.35)
	play_strip.add_theme_stylebox_override("hover", play_hover_style)

	var play_center := CenterContainer.new()
	play_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_strip.add_child(play_center)

	var play_col := VBoxContainer.new()
	play_col.alignment = BoxContainer.ALIGNMENT_CENTER
	play_col.add_theme_constant_override("separation", 7)
	play_center.add_child(play_col)

	var play_arrow := Label.new()
	play_arrow.text = "▶"
	play_arrow.add_theme_font_size_override("font_size", 32)
	play_arrow.add_theme_color_override("font_color", accent)
	play_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_col.add_child(play_arrow)

	var play_text := Label.new()
	play_text.text = "PLAY"
	play_text.add_theme_font_size_override("font_size", 16)
	play_text.add_theme_color_override("font_color", accent)
	play_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_col.add_child(play_text)

	play_strip.pressed.connect(_on_game_selected.bind(game_id))
	hbox.add_child(play_strip)

	# Full card click overlay
	var full_click := Button.new()
	full_click.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_click.flat = true
	full_click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	full_click.pressed.connect(_on_game_selected.bind(game_id))
	card.add_child(full_click)

	full_click.mouse_entered.connect(func():
		style.bg_color = CARD_SURFACE.lightened(0.1)
		play_style.bg_color = Color(accent.r, accent.g, accent.b, 0.35)
	)
	full_click.mouse_exited.connect(func():
		style.bg_color = CARD_SURFACE
		play_style.bg_color = Color(accent.r, accent.g, accent.b, 0.2)
	)

	parent.add_child(card)
	_game_cards[game_id] = card

func _on_game_selected(game_id: String) -> void:
	GameManager.selected_game_name = game_id
	get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")

func _show_player_card_intro() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = CARD_SURFACE
	pstyle.border_width_top = 4
	pstyle.border_color = BRAND_CYAN
	pstyle.corner_radius_top_left = 28
	pstyle.corner_radius_top_right = 28
	pstyle.corner_radius_bottom_left = 28
	pstyle.corner_radius_bottom_right = 28
	pstyle.content_margin_left = 32
	pstyle.content_margin_right = 32
	pstyle.content_margin_top = 32
	pstyle.content_margin_bottom = 32
	pstyle.shadow_color = Color(0, 0, 0, 0.5)
	pstyle.shadow_size = 24
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 18)
	panel.add_child(inner)

	var title := Label.new()
	title.text = "Claim Your Player Card"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pick a name — we'll hand you a badge and a number for the leaderboard."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(subtitle)

	var name_input := LineEdit.new()
	name_input.placeholder_text = "Your name"
	name_input.max_length = 20
	inner.add_child(name_input)

	var status_label := Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color("#EF4444"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(status_label)

	var claim_btn := Button.new()
	claim_btn.text = "Claim Card"
	claim_btn.add_theme_font_size_override("font_size", 20)
	claim_btn.custom_minimum_size = Vector2(0, 52)
	var claim_style := StyleBoxFlat.new()
	claim_style.bg_color = BRAND_CYAN
	claim_style.corner_radius_top_left = 14
	claim_style.corner_radius_top_right = 14
	claim_style.corner_radius_bottom_left = 14
	claim_style.corner_radius_bottom_right = 14
	claim_btn.add_theme_stylebox_override("normal", claim_style)
	claim_btn.add_theme_color_override("font_color", Color("#04101A"))
	inner.add_child(claim_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip for now"
	skip_btn.flat = true
	skip_btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	inner.add_child(skip_btn)

	skip_btn.pressed.connect(func(): overlay.queue_free())

	claim_btn.pressed.connect(func():
		var chosen_name := name_input.text.strip_edges()
		if chosen_name == "":
			status_label.text = "Enter a name first."
			return
		status_label.text = ""
		claim_btn.disabled = true
		claim_btn.text = "Claiming…"
		var result := await Backend.ensure_profile(chosen_name)
		if result.get("display_name", "") == "":
			claim_btn.disabled = false
			claim_btn.text = "Claim Card"
			status_label.text = "Couldn't reach the server — check your connection and try again."
			return
		for child in inner.get_children():
			child.queue_free()
		var badge := Label.new()
		badge.text = result.get("badge", "🎮")
		badge.add_theme_font_size_override("font_size", 64)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(badge)
		var reveal_name := Label.new()
		reveal_name.text = "%s #%s" % [result.get("display_name", ""), result.get("tag_number", "")]
		reveal_name.add_theme_font_size_override("font_size", 26)
		reveal_name.add_theme_color_override("font_color", TEXT_PRIMARY)
		reveal_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(reveal_name)
		var reveal_sub := Label.new()
		reveal_sub.text = "Your card is ready. Good luck out there."
		reveal_sub.add_theme_font_size_override("font_size", 15)
		reveal_sub.add_theme_color_override("font_color", TEXT_SECONDARY)
		reveal_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(reveal_sub)
		var go_btn := Button.new()
		go_btn.text = "Let's Go"
		go_btn.add_theme_font_size_override("font_size", 20)
		go_btn.custom_minimum_size = Vector2(0, 52)
		go_btn.add_theme_stylebox_override("normal", claim_style)
		go_btn.add_theme_color_override("font_color", Color("#04101A"))
		go_btn.pressed.connect(func(): overlay.queue_free())
		inner.add_child(go_btn)
	)
