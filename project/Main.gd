extends ColorRect

# Colors
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

func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	margin.add_child(vbox)

	# --- Header ---
	var header = VBoxContainer.new()
	var title = Label.new()
	title.text = "FitArcade"
	title.add_theme_font_size_override("font_size", 77)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Exergaming Platform"
	subtitle.add_theme_font_size_override("font_size", 29)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	vbox.add_child(header)

	# --- Game Selection ---
	var games_label = Label.new()
	games_label.text = "Choose a workout"
	games_label.add_theme_font_size_override("font_size", 42)
	games_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	games_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(games_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var games_vbox = VBoxContainer.new()
	games_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(games_vbox)

	_create_game_card(games_vbox, "Chrome Dino", "Jumping Jacks", "dino")
	_create_game_card(games_vbox, "Lane Switcher", "Lunges", "switcher")
	_create_game_card(games_vbox, "Flappy Bird", "Arm Raises", "flappy")

func _create_stat_card(parent: Control, title: String, value: String) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	var val_label = Label.new()
	val_label.text = value
	val_label.add_theme_font_size_override("font_size", 38)
	val_label.add_theme_color_override("font_color", BRAND_CYAN)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(val_label)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	panel.add_child(vbox)
	parent.add_child(panel)

func _create_game_card(parent: Control, game_name: String, exercise_name: String, game_id: String) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 132)
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	btn.add_theme_stylebox_override("normal", style)

	var hover = style.duplicate()
	hover.bg_color = CARD_SURFACE.lightened(0.06)
	btn.add_theme_stylebox_override("hover", hover)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)

	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(88, 88)
	var icon_panel_style = StyleBoxFlat.new()
	icon_panel_style.bg_color = Color("#121028")
	icon_panel_style.border_width_left = 0
	icon_panel_style.border_width_right = 0
	icon_panel_style.border_width_top = 0
	icon_panel_style.border_width_bottom = 0
	icon_panel_style.corner_radius_top_left = 18
	icon_panel_style.corner_radius_top_right = 18
	icon_panel_style.corner_radius_bottom_left = 18
	icon_panel_style.corner_radius_bottom_right = 18
	icon_panel_style.content_margin_left = 10
	icon_panel_style.content_margin_right = 10
	icon_panel_style.content_margin_top = 10
	icon_panel_style.content_margin_bottom = 10
	icon_panel.add_theme_stylebox_override("panel", icon_panel_style)

	var icon_box = CenterContainer.new()
	icon_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_panel.add_child(icon_box)

	var icon = TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	match game_id:
		"dino": icon.texture = ICON_DINO
		"flappy": icon.texture = ICON_FLAPPY
		"switcher": icon.texture = ICON_LANE
		_: icon.texture = ICON_DINO

	icon_box.add_child(icon)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)

	var name_label = Label.new()
	name_label.text = game_name
	name_label.add_theme_font_size_override("font_size", 35)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(name_label)

	var pill = PanelContainer.new()
	pill.custom_minimum_size = Vector2(0, 0)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pill_style = StyleBoxFlat.new()
	pill_style.bg_color = Color("#201C48")
	pill_style.border_width_left = 0
	pill_style.border_width_right = 0
	pill_style.border_width_top = 0
	pill_style.border_width_bottom = 0
	pill_style.corner_radius_top_left = 999
	pill_style.corner_radius_top_right = 999
	pill_style.corner_radius_bottom_left = 999
	pill_style.corner_radius_bottom_right = 999
	pill_style.content_margin_left = 10
	pill_style.content_margin_right = 10
	pill_style.content_margin_top = 5
	pill_style.content_margin_bottom = 5
	pill.add_theme_stylebox_override("panel", pill_style)

	var pill_label = Label.new()
	pill_label.text = exercise_name
	pill_label.add_theme_font_size_override("font_size", 21)
	pill_label.add_theme_color_override("font_color", _get_game_accent(game_id))
	pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pill_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.add_child(pill_label)
	vbox.add_child(pill)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var play_strip := Button.new()
	play_strip.custom_minimum_size = Vector2(86, 0)
	play_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_strip.focus_mode = Control.FOCUS_NONE
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = _get_game_accent(game_id).darkened(0.28)
	play_style.corner_radius_top_left = 18
	play_style.corner_radius_top_right = 18
	play_style.corner_radius_bottom_left = 18
	play_style.corner_radius_bottom_right = 18
	play_style.content_margin_left = 10
	play_style.content_margin_right = 10
	play_style.content_margin_top = 10
	play_style.content_margin_bottom = 10
	play_strip.add_theme_stylebox_override("normal", play_style)
	var play_hover := play_style.duplicate()
	play_hover.bg_color = _get_game_accent(game_id).darkened(0.18)
	play_strip.add_theme_stylebox_override("hover", play_hover)
	var play_box := CenterContainer.new()
	play_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_strip.add_child(play_box)
	var play_icon := Label.new()
	play_icon.text = "▶"
	play_icon.add_theme_font_size_override("font_size", 54)
	play_icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.36))
	play_box.add_child(play_icon)
	play_strip.pressed.connect(_on_game_selected.bind(game_id))
	play_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	hbox.add_child(icon_panel)
	hbox.add_child(vbox)
	hbox.add_child(spacer)
	hbox.add_child(play_strip)

	btn.add_child(hbox)
	btn.pressed.connect(_on_game_selected.bind(game_id))
	parent.add_child(btn)

func _on_game_selected(game_id: String) -> void:
	GameManager.selected_game_name = game_id
	get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")
