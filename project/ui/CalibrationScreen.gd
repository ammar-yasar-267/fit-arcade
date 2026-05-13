extends Control

const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")
const SUCCESS = Color("#22C55E")
const WARNING = Color("#F59E0B")

@onready var pose_landmarker_scene = preload("res://vision/pose_landmarker/PoseLandmarker.tscn")

var landmarker_instance = null
var overlay_rect: ColorRect
var title_label: Label
var status_chip_label: Label
var detail_label: Label
var step_label: Label
var ready_button: Button
var status_chip: Control
var pause_menu_visible: bool = false
var awaiting_start: bool = false

func _game_display_name(game_id: String) -> String:
	match game_id:
		"dino": return "Chrome Dino"
		"switcher": return "Lane Switcher"
		"flappy": return "Flappy Bird"
		_: return game_id.capitalize()

func _ready():
	GameManager.pending_game_name = GameManager.selected_game_name
	GameManager.selected_game_name = ""
	CalibrationManager.reset_calibration()

	landmarker_instance = pose_landmarker_scene.instantiate()
	add_child(landmarker_instance)

	overlay_rect = ColorRect.new()
	overlay_rect.color = Color(0.02, 0.02, 0.07, 0.55)
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_rect.gui_input.connect(_on_overlay_input)
	add_child(overlay_rect)

	# Root layout: full-rect VBox aligned to bottom so card sits in lower portion
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 8)
	root_margin.add_theme_constant_override("margin_right", 8)
	root_margin.add_theme_constant_override("margin_bottom", 40)
	overlay_rect.add_child(root_margin)

	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_END
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 20)
	root_margin.add_child(outer)

	var hero_card = PanelContainer.new()
	hero_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero_card.custom_minimum_size = Vector2(450, 0)
	var hero_style = StyleBoxFlat.new()
	hero_style.bg_color = CARD_SURFACE
	hero_style.border_width_top = 4
	hero_style.border_color = BRAND_CYAN
	hero_style.corner_radius_top_left = 24
	hero_style.corner_radius_top_right = 24
	hero_style.corner_radius_bottom_left = 24
	hero_style.corner_radius_bottom_right = 24
	hero_style.content_margin_left = 24
	hero_style.content_margin_right = 24
	hero_style.content_margin_top = 20
	hero_style.content_margin_bottom = 20
	hero_style.shadow_color = Color(0, 0, 0, 0.4)
	hero_style.shadow_size = 24
	hero_card.add_theme_stylebox_override("panel", hero_style)
	outer.add_child(hero_card)

	var hero = VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 10)
	hero_card.add_child(hero)

	title_label = Label.new()
	title_label.text = "Calibration"
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", BRAND_CYAN)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(title_label)

	var game_name_label := Label.new()
	game_name_label.text = "For: %s" % _game_display_name(GameManager.pending_game_name)
	game_name_label.add_theme_font_size_override("font_size", 16)
	game_name_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	game_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(game_name_label)

	var subtitle = Label.new()
	subtitle.text = "Get your full body in frame"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero.add_child(subtitle)

	var status_chip = PanelContainer.new()
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var chip_style = StyleBoxFlat.new()
	chip_style.bg_color = Color(BRAND_CYAN.r, BRAND_CYAN.g, BRAND_CYAN.b, 0.15)
	chip_style.border_width_left = 2
	chip_style.border_width_right = 2
	chip_style.border_width_top = 2
	chip_style.border_width_bottom = 2
	chip_style.border_color = BRAND_CYAN
	chip_style.corner_radius_top_left = 12
	chip_style.corner_radius_top_right = 12
	chip_style.corner_radius_bottom_left = 12
	chip_style.corner_radius_bottom_right = 12
	chip_style.content_margin_left = 20
	chip_style.content_margin_right = 20
	chip_style.content_margin_top = 8
	chip_style.content_margin_bottom = 10
	status_chip.add_theme_stylebox_override("panel", chip_style)
	self.status_chip = status_chip

	status_chip_label = Label.new()
	status_chip_label.text = "Waiting for pose"
	status_chip_label.add_theme_font_size_override("font_size", 18)
	status_chip_label.add_theme_color_override("font_color", BRAND_CYAN)
	status_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.add_child(status_chip_label)
	hero.add_child(status_chip)

	detail_label = Label.new()
	detail_label.text = "Step into the camera view so I can see your full body."
	detail_label.add_theme_font_size_override("font_size", 20)
	detail_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(310, 0)
	hero.add_child(detail_label)

	step_label = Label.new()
	step_label.text = ""
	step_label.add_theme_font_size_override("font_size", 18)
	step_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.visible = false
	hero.add_child(step_label)

	ready_button = Button.new()
	ready_button.text = "Let's Go"
	ready_button.add_theme_font_size_override("font_size", 24)
	ready_button.add_theme_color_override("font_color", BRAND_CYAN)
	ready_button.custom_minimum_size = Vector2(260, 50)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("#11102B", 0.9)
	button_style.border_width_left = 3
	button_style.border_width_right = 3
	button_style.border_width_top = 3
	button_style.border_width_bottom = 3
	button_style.border_color = BRAND_CYAN
	button_style.corner_radius_top_left = 16
	button_style.corner_radius_top_right = 16
	button_style.corner_radius_bottom_left = 16
	button_style.corner_radius_bottom_right = 16
	button_style.content_margin_left = 28
	button_style.content_margin_right = 28
	button_style.content_margin_top = 12
	button_style.content_margin_bottom = 12
	button_style.shadow_color = Color(0, 0, 0, 0.4)
	button_style.shadow_size = 10
	ready_button.add_theme_stylebox_override("normal", button_style)
	var button_hover = button_style.duplicate()
	button_hover.bg_color = Color("#1A1640")
	button_hover.border_color = Color("#0891B2")
	ready_button.add_theme_stylebox_override("hover", button_hover)
	ready_button.hide()
	ready_button.pressed.connect(_on_ready_pressed)
	hero.add_child(ready_button)

	if not ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.connect(_on_pose_processed)

	_update_ui_from_diagnosis(CalibrationManager.analyze_calibration_pose(null))

func _on_pose_processed(landmarks):
	if CalibrationManager.is_calibrated:
		return
	if pause_menu_visible:
		return

	var diagnosis = CalibrationManager.analyze_calibration_pose(landmarks)
	_update_ui_from_diagnosis(diagnosis)

	if diagnosis.get("ready", false) and CalibrationManager.compute_and_save_thresholds(landmarks):
		awaiting_start = true
		status_chip_label.text = "Calibration complete"
		detail_label.text = "Perfect framing. You're ready to go."
		step_label.text = ""
		ready_button.show()
		var timer = get_tree().create_timer(1.2)
		timer.timeout.connect(_on_ready_pressed)

func _update_ui_from_diagnosis(diagnosis: Dictionary) -> void:
	if diagnosis.is_empty():
		return

	var message = str(diagnosis.get("message", ""))
	var detail = str(diagnosis.get("detail", ""))
	var is_ready = diagnosis.get("ready", false)

	if status_chip_label:
		status_chip_label.text = message
		var status_color = SUCCESS if is_ready else WARNING
		status_chip_label.add_theme_color_override("font_color", status_color)
		
		# Update chip border color based on state
		if status_chip:
			var chip_style = status_chip.get_theme_stylebox("panel").duplicate()
			chip_style.border_color = status_color
			status_chip.add_theme_stylebox_override("panel", chip_style)

	if detail_label:
		detail_label.text = detail

	if step_label:
		step_label.visible = false

func _on_overlay_input(event: InputEvent) -> void:
	if pause_menu_visible:
		return
	
	if event is InputEventMouseButton and event.pressed:
		_show_pause_menu()

func _show_pause_menu() -> void:
	pause_menu_visible = true
	
	# Create dark overlay
	var menu_overlay = ColorRect.new()
	menu_overlay.color = Color(0, 0, 0, 0.78)
	menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_overlay.name = "PauseMenuOverlay"
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(menu_overlay)
	
	# Center container for menu
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_overlay.add_child(center)
	
	# Create menu panel matching game pause design
	var menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(380, 0)
	menu_panel.name = "PauseMenuPanel"
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = CARD_SURFACE
	panel_style.border_width_top = 4
	panel_style.border_color = BRAND_CYAN
	panel_style.corner_radius_top_left = 24
	panel_style.corner_radius_top_right = 24
	panel_style.corner_radius_bottom_left = 24
	panel_style.corner_radius_bottom_right = 24
	panel_style.content_margin_left = 32
	panel_style.content_margin_right = 32
	panel_style.content_margin_top = 32
	panel_style.content_margin_bottom = 32
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 20
	menu_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(menu_panel)
	
	var menu_vbox = VBoxContainer.new()
	menu_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_vbox.add_theme_constant_override("separation", 24)
	menu_panel.add_child(menu_vbox)
	
	var title = Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_vbox.add_child(title)
	
	# Resume button (primary - cyan)
	var resume_btn = _make_pause_btn("Resume", true)
	resume_btn.pressed.connect(_close_pause_menu)
	menu_vbox.add_child(resume_btn)
	
	# Back to menu button (secondary - dark with border)
	var back_btn = _make_pause_btn("Main Menu", false)
	back_btn.pressed.connect(_go_back_to_menu)
	menu_vbox.add_child(back_btn)

func _make_pause_btn(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 26)
	btn.custom_minimum_size = Vector2(300, 58)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = BRAND_CYAN
	else:
		style.bg_color = Color("#11102B")
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = BRAND_CYAN
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	if primary:
		hover.bg_color = Color("#0891B2")
	else:
		hover.bg_color = Color("#1A1640")
	btn.add_theme_stylebox_override("hover", hover)
	return btn

func _close_pause_menu() -> void:
	pause_menu_visible = false
	var overlay = get_node_or_null("PauseMenuOverlay")
	if overlay:
		overlay.queue_free()

func _go_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_ready_pressed():
	if not CalibrationManager.is_calibrated:
		return
	if not awaiting_start:
		return
	awaiting_start = false

	if ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.disconnect(_on_pose_processed)

	overlay_rect.hide()

	var vbox = landmarker_instance.get_node_or_null("VBoxContainer")
	if vbox:
		vbox.hide()
	var img_view = landmarker_instance.get_node_or_null("VBoxContainer/Image")
	if img_view:
		img_view.hide()

	GameManager.selected_game_name = GameManager.pending_game_name
	if landmarker_instance.has_method("_start_exercise_and_game"):
		landmarker_instance._start_exercise_and_game()
