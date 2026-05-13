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

	# Back button — sits above the overlay so it's always tappable
	var back_btn := Button.new()
	back_btn.text = "‹  Back"
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	back_btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var back_normal := StyleBoxFlat.new()
	back_normal.bg_color = Color(0.06, 0.06, 0.14, 0.85)
	back_normal.border_width_left = 1
	back_normal.border_width_right = 1
	back_normal.border_width_top = 1
	back_normal.border_width_bottom = 1
	back_normal.border_color = Color(1, 1, 1, 0.12)
	back_normal.corner_radius_top_left = 999
	back_normal.corner_radius_top_right = 999
	back_normal.corner_radius_bottom_left = 999
	back_normal.corner_radius_bottom_right = 999
	back_normal.content_margin_left = 18
	back_normal.content_margin_right = 18
	back_normal.content_margin_top = 8
	back_normal.content_margin_bottom = 8
	back_btn.add_theme_stylebox_override("normal", back_normal)
	var back_hover := back_normal.duplicate()
	back_hover.bg_color = Color(0.1, 0.1, 0.22, 0.95)
	back_hover.border_color = Color(1, 1, 1, 0.25)
	back_btn.add_theme_stylebox_override("hover", back_hover)
	back_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back_btn.offset_top = 16
	back_btn.offset_left = 16
	back_btn.offset_right = 130
	back_btn.offset_bottom = 58
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	add_child(back_btn)

	overlay_rect = ColorRect.new()
	overlay_rect.color = Color(0.02, 0.02, 0.07, 0.55)
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay_rect)

	# Root layout: full-rect VBox aligned to bottom so card sits in lower portion
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_bottom", 48)
	overlay_rect.add_child(root_margin)

	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_theme_constant_override("separation", 20)
	root_margin.add_child(outer)

	var hero_card = PanelContainer.new()
	hero_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero_card.custom_minimum_size = Vector2(500, 0)
	var hero_style = StyleBoxFlat.new()
	hero_style.bg_color = CARD_SURFACE
	hero_style.border_width_top = 4
	hero_style.border_color = BRAND_CYAN
	hero_style.corner_radius_top_left = 28
	hero_style.corner_radius_top_right = 28
	hero_style.corner_radius_bottom_left = 28
	hero_style.corner_radius_bottom_right = 28
	hero_style.content_margin_left = 32
	hero_style.content_margin_right = 32
	hero_style.content_margin_top = 28
	hero_style.content_margin_bottom = 28
	hero_style.shadow_color = Color(0, 0, 0, 0.4)
	hero_style.shadow_size = 24
	hero_card.add_theme_stylebox_override("panel", hero_style)
	outer.add_child(hero_card)

	var hero = VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 12)
	hero_card.add_child(hero)

	title_label = Label.new()
	title_label.text = "Calibration"
	title_label.add_theme_font_size_override("font_size", 44)
	title_label.add_theme_color_override("font_color", BRAND_CYAN)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(title_label)

	var game_name_label := Label.new()
	game_name_label.text = "For: %s" % _game_display_name(GameManager.pending_game_name)
	game_name_label.add_theme_font_size_override("font_size", 18)
	game_name_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	game_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(game_name_label)

	var subtitle = Label.new()
	subtitle.text = "Get your full body in frame"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero.add_child(subtitle)

	var status_chip = PanelContainer.new()
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var chip_style = StyleBoxFlat.new()
	chip_style.bg_color = Color("#11102B")
	chip_style.border_width_left = 2
	chip_style.border_width_right = 2
	chip_style.border_width_top = 2
	chip_style.border_width_bottom = 2
	chip_style.border_color = Color("#06B6D4", 0.4)
	chip_style.corner_radius_top_left = 12
	chip_style.corner_radius_top_right = 12
	chip_style.corner_radius_bottom_left = 12
	chip_style.corner_radius_bottom_right = 12
	chip_style.content_margin_left = 20
	chip_style.content_margin_right = 20
	chip_style.content_margin_top = 8
	chip_style.content_margin_bottom = 8
	status_chip.add_theme_stylebox_override("panel", chip_style)

	status_chip_label = Label.new()
	status_chip_label.text = "Waiting for pose"
	status_chip_label.add_theme_font_size_override("font_size", 19)
	status_chip_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	status_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.add_child(status_chip_label)
	hero.add_child(status_chip)

	detail_label = Label.new()
	detail_label.text = "Step into the camera view so I can see your full body."
	detail_label.add_theme_font_size_override("font_size", 21)
	detail_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero.add_child(detail_label)

	step_label = Label.new()
	step_label.text = ""
	step_label.add_theme_font_size_override("font_size", 20)
	step_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.visible = false
	hero.add_child(step_label)

	ready_button = Button.new()
	ready_button.text = "Let's Go →"
	ready_button.add_theme_font_size_override("font_size", 26)
	ready_button.add_theme_color_override("font_color", BRAND_CYAN)
	ready_button.custom_minimum_size = Vector2(300, 60)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("#11102B", 0.9)
	button_style.border_width_left = 3
	button_style.border_width_right = 3
	button_style.border_width_top = 3
	button_style.border_width_bottom = 3
	button_style.border_color = BRAND_CYAN
	button_style.corner_radius_top_left = 18
	button_style.corner_radius_top_right = 18
	button_style.corner_radius_bottom_left = 18
	button_style.corner_radius_bottom_right = 18
	button_style.content_margin_left = 32
	button_style.content_margin_right = 32
	button_style.content_margin_top = 14
	button_style.content_margin_bottom = 14
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

	if status_chip_label:
		status_chip_label.text = message
		status_chip_label.add_theme_color_override("font_color", SUCCESS if diagnosis.get("ready", false) else WARNING)

	if detail_label:
		detail_label.text = detail

	if step_label:
		step_label.visible = false

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
