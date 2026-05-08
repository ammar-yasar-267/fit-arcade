extends ColorRect

# Colors
const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")

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
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Exergaming Platform"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	vbox.add_child(header)

	# --- Stats Row ---
	var stats_hbox = HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 16)
	stats_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stats_hbox)
	
	_create_stat_card(stats_hbox, "Streak", str(SessionManager.daily_streak) + " Days")
	_create_stat_card(stats_hbox, "Reps", str(SessionManager.total_reps_today))
	_create_stat_card(stats_hbox, "Score", str(SessionManager.session_score))

	# --- Game Selection ---
	var games_label = Label.new()
	games_label.text = "Select Mode"
	games_label.add_theme_font_size_override("font_size", 24)
	games_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(games_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var games_vbox = VBoxContainer.new()
	games_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(games_vbox)

	_create_game_card(games_vbox, "Chrome Dino", "Jumping Jacks", "dino")
	_create_game_card(games_vbox, "3-Lane Switcher", "Lunges", "switcher")
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
	val_label.add_theme_font_size_override("font_size", 24)
	val_label.add_theme_color_override("font_color", BRAND_CYAN)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(val_label)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	panel.add_child(vbox)
	parent.add_child(panel)

func _create_game_card(parent: Control, game_name: String, exercise_name: String, game_id: String) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 100)
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	btn.add_theme_stylebox_override("normal", style)
	
	var hover = style.duplicate()
	hover.bg_color = CARD_SURFACE.lightened(0.1)
	btn.add_theme_stylebox_override("hover", hover)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var name_label = Label.new()
	name_label.text = game_name
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var ex_label = Label.new()
	ex_label.text = "Exercise: " + exercise_name
	ex_label.add_theme_font_size_override("font_size", 16)
	ex_label.add_theme_color_override("font_color", BRAND_CYAN)
	ex_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ex_label)
	
	btn.add_child(vbox)
	btn.pressed.connect(_on_game_selected.bind(game_id))
	parent.add_child(btn)

func _on_game_selected(game_id: String) -> void:
	GameManager.selected_game_name = game_id
	get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")
