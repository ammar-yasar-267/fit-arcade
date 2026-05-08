extends Control

const BRAND_CYAN = Color("#06B6D4")

@onready var pose_landmarker_scene = preload("res://vision/pose_landmarker/PoseLandmarker.tscn")
var landmarker_instance = null
var overlay_rect: ColorRect
var instructions_label: Label
var ready_button: Button

func _ready():
	GameManager.pending_game_name = GameManager.selected_game_name
	GameManager.selected_game_name = "" # Prevent auto-loading game
	CalibrationManager.reset_calibration()
	
	landmarker_instance = pose_landmarker_scene.instantiate()
	add_child(landmarker_instance)
	
	# Add UI overlay
	overlay_rect = ColorRect.new()
	overlay_rect.color = Color(0, 0, 0, 0.6)
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay_rect)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	overlay_rect.add_child(vbox)
	
	instructions_label = Label.new()
	instructions_label.text = "Get Ready\nFrame Yourself\nStand 6-8 ft from the camera.\nYour full body must fit in the frame."
	instructions_label.add_theme_font_size_override("font_size", 24)
	instructions_label.add_theme_color_override("font_color", Color.WHITE)
	instructions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(instructions_label)
	
	ready_button = Button.new()
	ready_button.text = "Start Game"
	ready_button.add_theme_font_size_override("font_size", 28)
	ready_button.add_theme_color_override("font_color", BRAND_CYAN)
	ready_button.custom_minimum_size = Vector2(0, 64)
	ready_button.hide()
	ready_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(ready_button)
	
	if not ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.connect(_on_pose_processed)

func _on_pose_processed(landmarks):
	if not CalibrationManager.is_calibrated:
		if CalibrationManager.compute_and_save_thresholds(landmarks):
			instructions_label.text = "Calibration Complete!\nPerfect posture detected."
			ready_button.show()
			# Auto-start after a brief delay
			var t = get_tree().create_timer(1.5)
			t.timeout.connect(_on_ready_pressed)

func _on_ready_pressed():
	# Prevent double-firing
	if CalibrationManager.is_calibrated == false:
		return
	if ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.disconnect(_on_pose_processed)
	
	# Hide the calibration overlay
	overlay_rect.hide()
	
	# Hide the full-screen camera / VisionTask UI from the landmarker
	var vbox = landmarker_instance.get_node_or_null("VBoxContainer")
	if vbox:
		vbox.hide()
	var img_view = landmarker_instance.get_node_or_null("VBoxContainer/Image")
	if img_view:
		img_view.hide()
	
	# Now tell the landmarker to load the game
	GameManager.selected_game_name = GameManager.pending_game_name
	if landmarker_instance.has_method("_start_exercise_and_game"):
		landmarker_instance._start_exercise_and_game()
