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

func _ready():
	GameManager.pending_game_name = GameManager.selected_game_name
	GameManager.selected_game_name = ""
	CalibrationManager.reset_calibration()
	
	landmarker_instance = pose_landmarker_scene.instantiate()
	add_child(landmarker_instance)
	
	overlay_rect = ColorRect.new()
	overlay_rect.color = Color(0.02, 0.02, 0.07, 0.78)
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay_rect)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 24)
	overlay_rect.add_child(margin)
	
	var outer = VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 18)
	margin.add_child(outer)
	
	var hero_card = PanelContainer.new()
	hero_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hero_style = StyleBoxFlat.new()
	hero_style.bg_color = CARD_SURFACE
	hero_style.corner_radius_top_left = 22
	hero_style.corner_radius_top_right = 22
	hero_style.corner_radius_bottom_left = 22
	hero_style.corner_radius_bottom_right = 22
	hero_style.content_margin_left = 24
	hero_style.content_margin_right = 24
	hero_style.content_margin_top = 24
	hero_style.content_margin_bottom = 22
	hero_card.add_theme_stylebox_override("panel", hero_style)
	outer.add_child(hero_card)
	
	var hero = VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 14)
	hero_card.add_child(hero)
	
	title_label = Label.new()
	title_label.text = "Calibration"
	title_label.add_theme_font_size_override("font_size", 61)
	title_label.add_theme_color_override("font_color", BRAND_CYAN)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(title_label)
	
	var subtitle = Label.new()
	subtitle.text = "Get your body fully in frame before starting the game"
	subtitle.add_theme_font_size_override("font_size", 27)
	subtitle.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero.add_child(subtitle)
	
	var status_chip = PanelContainer.new()
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var chip_style = StyleBoxFlat.new()
	chip_style.bg_color = Color("#171532")
	chip_style.corner_radius_top_left = 999
	chip_style.corner_radius_top_right = 999
	chip_style.corner_radius_bottom_left = 999
	chip_style.corner_radius_bottom_right = 999
	chip_style.content_margin_left = 12
	chip_style.content_margin_right = 12
	chip_style.content_margin_top = 6
	chip_style.content_margin_bottom = 6
	status_chip.add_theme_stylebox_override("panel", chip_style)
	
	status_chip_label = Label.new()
	status_chip_label.text = "Waiting for pose"
	status_chip_label.add_theme_font_size_override("font_size", 21)
	status_chip_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	status_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.add_child(status_chip_label)
	hero.add_child(status_chip)
	
	detail_label = Label.new()
	detail_label.text = "Step into the camera view so I can see your full body."
	detail_label.add_theme_font_size_override("font_size", 32)
	detail_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero.add_child(detail_label)
	
	step_label = Label.new()
	step_label.text = ""
	step_label.add_theme_font_size_override("font_size", 22)
	step_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Keep the verbose step list hidden by default to reduce visual clutter
	step_label.visible = false
	hero.add_child(step_label)
	
	ready_button = Button.new()
	ready_button.text = "Continuing to game..."
	ready_button.add_theme_font_size_override("font_size", 35)
	ready_button.add_theme_color_override("font_color", TEXT_PRIMARY)
	ready_button.custom_minimum_size = Vector2(0, 60)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("#151331")
	button_style.border_color = BRAND_CYAN
	button_style.border_width_left = 1
	button_style.border_width_right = 1
	button_style.border_width_top = 1
	button_style.border_width_bottom = 1
	button_style.corner_radius_top_left = 16
	button_style.corner_radius_top_right = 16
	button_style.corner_radius_bottom_left = 16
	button_style.corner_radius_bottom_right = 16
	button_style.content_margin_left = 20
	button_style.content_margin_right = 20
	button_style.content_margin_top = 12
	button_style.content_margin_bottom = 12
	ready_button.add_theme_stylebox_override("normal", button_style)
	var button_hover = button_style.duplicate()
	button_hover.bg_color = Color("#1B1840")
	ready_button.add_theme_stylebox_override("hover", button_hover)
	ready_button.hide()
	ready_button.pressed.connect(_on_ready_pressed)
	outer.add_child(ready_button)
	
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
		detail_label.text = "Perfect framing. You’re ready to start the game."
		step_label.text = ""
		ready_button.show()
		var timer = get_tree().create_timer(1.2)
		timer.timeout.connect(_on_ready_pressed)

func _update_ui_from_diagnosis(diagnosis: Dictionary) -> void:
	if diagnosis.is_empty():
		return

	var message = str(diagnosis.get("message", ""))
	var detail = str(diagnosis.get("detail", ""))
	var missing: Array = diagnosis.get("missing", [])

	if status_chip_label:
		status_chip_label.text = message
		status_chip_label.add_theme_color_override("font_color", SUCCESS if diagnosis.get("ready", false) else WARNING)

	if detail_label:
		# Show a single concise line of guidance only
		detail_label.text = detail

	# Hide verbose step list to keep UI minimal; optionally surface top hint only
	if step_label:
		step_label.visible = false

func _build_step_items(missing: Array, is_ready: bool) -> Array[String]:
	if is_ready:
		return ["Hold still for a beat", "Keep your full body visible", "Press Continue when the button appears"]

	if missing.is_empty():
		return ["Step back until your full body fits in frame", "Keep both wrists and ankles visible", "Hold the pose steady"]

	var steps: Array[String] = []
	for item in missing:
		match str(item):
			"your head": steps.append("Move back or lower the camera so your head is visible")
			"your left wrist": steps.append("Raise your left arm into view")
			"your right wrist": steps.append("Raise your right arm into view")
			"your left ankle": steps.append("Step back so your left foot is visible")
			"your right ankle": steps.append("Step back so your right foot is visible")
			_: steps.append("Keep your full body inside the frame")

	steps.append("Hold the pose steady until calibration finishes")
	return steps

func _format_steps(steps: Array[String]) -> String:
	if steps.is_empty():
		return ""
	var lines: Array[String] = []
	for step in steps:
		lines.append("• %s" % step)
	return "\n".join(lines)

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
