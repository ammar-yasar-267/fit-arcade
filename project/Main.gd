extends ColorRect

const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")

const ICON_DINO: Texture2D = preload("res://ui/assets/home/dino-jumping-jacks.svg")
const ICON_FLAPPY: Texture2D = preload("res://ui/assets/home/flappybird-arm-raises.svg")
const ICON_LANE: Texture2D = preload("res://ui/assets/home/lane-runner-lunges.svg")

func _get_game_accent(game_id: String) -> Color:
	match game_id:
		"dino": return Color("#F59E0B")
		"switcher": return Color("#22C55E")
		"flappy": return Color("#06B6D4")
		_: return BRAND_CYAN

func _ready() -> void:
	_build_ui()
	_add_settings_button()
	if OS.get_name() == "Android":
		OS.request_permissions()

func _add_settings_button() -> void:
	var btn := Button.new()
	btn.text = "⚙"
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 36)
	btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_top = 16
	btn.offset_right = -16
	btn.offset_left = btn.offset_right - 56
	btn.offset_bottom = btn.offset_top + 56
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/SettingsMenu.tscn"))
	add_child(btn)

func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	margin.add_child(vbox)

	# --- Header ---
	var header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "FitArcade"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Move your body. Control the game."
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)

	# --- Section header ---
	var section_row = VBoxContainer.new()
	section_row.add_theme_constant_override("separation", 8)
	vbox.add_child(section_row)

	var section_label = Label.new()
	section_label.text = "YOUR GAMES"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	section_row.add_child(section_label)

	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Color("#FFFFFF", 0.08))
	section_row.add_child(sep)

	# --- Game cards scroll ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var games_vbox = VBoxContainer.new()
	games_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(games_vbox)

	_create_game_card(games_vbox, "Chrome Dino", "Jumping Jacks", "dino")
	_create_game_card(games_vbox, "Lane Switcher", "Lunges", "switcher")
	_create_game_card(games_vbox, "Flappy Bird", "Arm Raises", "flappy")

func _create_game_card(parent: Control, game_name: String, exercise_name: String, game_id: String) -> void:
	var accent = _get_game_accent(game_id)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 180)
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	card.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	card.add_child(hbox)

	# Left accent strip
	var accent_strip = ColorRect.new()
	accent_strip.color = accent
	accent_strip.custom_minimum_size = Vector2(4, 0)
	accent_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(accent_strip)

	# Icon section
	var icon_margin := MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 18)
	icon_margin.add_theme_constant_override("margin_right", 16)
	hbox.add_child(icon_margin)

	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(100, 100)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(accent.r, accent.g, accent.b, 0.15)
	icon_style.corner_radius_top_left = 18
	icon_style.corner_radius_top_right = 18
	icon_style.corner_radius_bottom_left = 18
	icon_style.corner_radius_bottom_right = 18
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_margin.add_child(icon_panel)

	var icon_box = CenterContainer.new()
	icon_panel.add_child(icon_box)

	var icon = TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(68, 68)
	match game_id:
		"dino": icon.texture = ICON_DINO
		"flappy": icon.texture = ICON_FLAPPY
		"switcher": icon.texture = ICON_LANE
		_: icon.texture = ICON_DINO
	icon_box.add_child(icon)

	# Text content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	var vbox_margin := MarginContainer.new()
	vbox_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_margin.add_theme_constant_override("margin_right", 12)
	vbox_margin.add_child(vbox)
	hbox.add_child(vbox_margin)

	var name_label = Label.new()
	name_label.text = game_name
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(name_label)

	var pill = PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pill_style = StyleBoxFlat.new()
	pill_style.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	pill_style.border_width_left = 1
	pill_style.border_width_right = 1
	pill_style.border_width_top = 1
	pill_style.border_width_bottom = 1
	pill_style.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	pill_style.corner_radius_top_left = 999
	pill_style.corner_radius_top_right = 999
	pill_style.corner_radius_bottom_left = 999
	pill_style.corner_radius_bottom_right = 999
	pill_style.content_margin_left = 12
	pill_style.content_margin_right = 12
	pill_style.content_margin_top = 4
	pill_style.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", pill_style)
	vbox.add_child(pill)

	var pill_label = Label.new()
	pill_label.text = exercise_name
	pill_label.add_theme_font_size_override("font_size", 19)
	pill_label.add_theme_color_override("font_color", accent)
	pill.add_child(pill_label)

	# Play strip
	var play_strip := Button.new()
	play_strip.custom_minimum_size = Vector2(90, 0)
	play_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var play_style := StyleBoxFlat.new()
	var base_play_color = accent.darkened(0.3)
	play_style.bg_color = base_play_color
	play_style.corner_radius_top_right = 16
	play_style.corner_radius_bottom_right = 16
	play_strip.add_theme_stylebox_override("normal", play_style)
	var play_hover_style := play_style.duplicate()
	play_hover_style.bg_color = accent.darkened(0.15)
	play_strip.add_theme_stylebox_override("hover", play_hover_style)

	var play_center := CenterContainer.new()
	play_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_strip.add_child(play_center)

	var play_col := VBoxContainer.new()
	play_col.alignment = BoxContainer.ALIGNMENT_CENTER
	play_col.add_theme_constant_override("separation", 2)
	play_center.add_child(play_col)

	var play_arrow := Label.new()
	play_arrow.text = "▶"
	play_arrow.add_theme_font_size_override("font_size", 26)
	play_arrow.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	play_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_col.add_child(play_arrow)

	var play_text := Label.new()
	play_text.text = "PLAY"
	play_text.add_theme_font_size_override("font_size", 14)
	play_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
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
		style.bg_color = CARD_SURFACE.lightened(0.08)
		play_style.bg_color = base_play_color.lightened(0.15)
	)
	full_click.mouse_exited.connect(func():
		style.bg_color = CARD_SURFACE
		play_style.bg_color = base_play_color
	)

	parent.add_child(card)

func _on_game_selected(game_id: String) -> void:
	GameManager.selected_game_name = game_id
	get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")
