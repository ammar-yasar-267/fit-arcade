extends VisionTask

## PoseLandmarker — detects pose landmarks from camera feed.
## Forwards landmark data to ExerciseManager for rep detection.
## Loads and displays the selected game alongside the camera.
## Shows a PIP camera preview with rendered pose skeleton overlay.

var task: MediaPipePoseLandmarker
var task_file := "pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
var renderer: MediaPipePoseRenderer
var game_instance: GameBase = null
var pose_preview: TextureRect = null
var pose_canvas: CanvasLayer = null
var state_label: Label = null
var back_button: Button = null
var overlay_root: Control = null
# Timestamp of last detect_async call; -1 means no inference pending.
# Using a timestamp instead of a boolean prevents permanent lockup when
# MediaPipe does not call back (e.g. no person in frame).
var last_inference_ms: int = -1
# Using a timestamp instead of a boolean prevents permanent lockup when
# MediaPipe does not call back (e.g. no person in frame).
# Timeout value is read dynamically from Settings.

func _result_callback(result: MediaPipePoseLandmarkerResult, image: MediaPipeImage, _timestamp_ms: int) -> void:
	last_inference_ms = -1
	show_result(image, result)

func _ready() -> void:
	super ()
	$VBoxContainer.hide()
	
	# Use only the PIP preview for gameplay; hide the full-screen camera view.
	if image_view:
		image_view.hide()
		
	# Start game immediately
	_start_exercise_and_game()
	# Auto-open camera — handle Windows CameraServerExtension explicitly
	call_deferred("_auto_open_camera")

## Custom camera opener that handles Windows properly.
## On Windows, CameraServerExtension must exist BEFORE feeds can be discovered.
func _auto_open_camera() -> void:
	_reset()
	# Step 1: Enable monitoring
	if not CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = true
	# Step 2: On Windows, force-create the CameraServerExtension immediately
	if OS.get_name() in ["Windows", "iOS"] and camera_extension == null:
		camera_extension = CameraServerExtension.new()
		camera_extension.permission_result.connect(self._on_auto_permission_result)
		if not camera_extension.permission_granted():
			camera_extension.request_permission()
			return # Wait for permission callback
	# Step 3: Try to select a camera
	_select_camera()

func _on_auto_permission_result(granted: bool) -> void:
	if granted:
		_select_camera()
	else:
		permission_dialog.popup_centered()

func _init_task():
	var file := get_external_model(task_file)
	if file == null:
		return
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = delegate
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	task = MediaPipePoseLandmarker.new()
	task.initialize(base_options, running_mode)
	task.result_callback.connect(self._result_callback)
	renderer = MediaPipePoseRenderer.new()
	last_inference_ms = -1
	super ()

## Override _select_camera to auto-select first available camera
## instead of showing the dialog (which is hidden behind the game).
func _select_camera() -> void:
	_update_camera_feeds()
	var feeds = CameraServer.feeds()
	if feeds.size() == 0:
		# No feeds yet — retry after a short delay
		get_tree().create_timer(0.5).timeout.connect(_select_camera, CONNECT_ONE_SHOT)
		return
	# Try to auto-select the front camera, fallback to first feed
	camera_feed = feeds[0]
	for feed in feeds:
		if feed.get_position() == CameraFeed.FEED_FRONT:
			camera_feed = feed
			break
	# Auto-select a format that is less likely to overload mobile devices.
	var formats = camera_feed.get_formats()
	if formats.size() > 0:
		var selected_index := 0
		var selected_area := INF
		var fallback_index := 0
		var fallback_area := INF
		for i in range(formats.size()):
			var fmt = formats[i]
			var w: int = int(fmt.get("width", 0))
			var h: int = int(fmt.get("height", 0))
			if w <= 0 or h <= 0:
				continue
			var area: int = w * h
			if area < fallback_area:
				fallback_area = area
				fallback_index = i
			# Prefer <=720p when available; otherwise keep smallest valid format.
			if area <= 1280 * 720 and area < selected_area:
				selected_area = area
				selected_index = i
		if selected_area == INF:
			selected_index = fallback_index
		var format_ok: bool = camera_feed.set_format(selected_index, {})
		if not format_ok:
			for i in range(formats.size()):
				if i == selected_index:
					continue
				if camera_feed.set_format(i, {}):
					selected_index = i
					format_ok = true
					break
		if not format_ok:
			pass
	# Start the camera directly
	_start_camera()

func _start_exercise_and_game() -> void:
	var game_name: String = GameManager.selected_game_name
	
	if game_name != "":
		# GAME MODE: hide full-screen camera, use PIP preview only
		if image_view:
			image_view.hide()
		$VBoxContainer.hide()
		
		var scene_path := GameManager.get_game_scene_path(game_name)
		if scene_path != "":
			var game_scene := load(scene_path) as PackedScene
			if game_scene:
				game_instance = game_scene.instantiate() as GameBase
				if game_instance:
					add_child(game_instance)
					GameManager.set_active_game(game_instance)
					game_instance.start_game()
					game_instance.game_over.connect(_on_game_over)
		_create_pose_preview()
	else:
		# CALIBRATION MODE: show full-screen camera feed
		$VBoxContainer.show()
		if $VBoxContainer.has_node("Title"): $VBoxContainer/Title.hide()
		if $VBoxContainer.has_node("Buttons"): $VBoxContainer/Buttons.hide()
		if $VBoxContainer.has_node("ExternalFileDisabled"): $VBoxContainer/ExternalFileDisabled.hide()
		if $VBoxContainer.has_node("ProgressBar"): $VBoxContainer/ProgressBar.hide()
		if image_view:
			image_view.show()
			image_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
			image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _create_pose_preview() -> void:
	pose_canvas = CanvasLayer.new()
	pose_canvas.layer = 10 # On top of everything
	
	overlay_root = Control.new()
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pose_canvas.add_child(overlay_root)

	# Top chips row: back + status
	var top_bar := HBoxContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 12
	top_bar.offset_top = 12
	top_bar.offset_right = -12
	top_bar.add_theme_constant_override("separation", 10)
	overlay_root.add_child(top_bar)

	back_button = _make_chip_button("Back")
	back_button.pressed.connect(_back)
	top_bar.add_child(back_button)

	# Camera preview with pose skeleton — bottom dock
	var preview_container := PanelContainer.new()
	preview_container.anchors_preset = Control.PRESET_BOTTOM_WIDE
	preview_container.anchor_left = 0.10
	preview_container.anchor_top = 0.78
	preview_container.anchor_right = 0.90
	preview_container.anchor_bottom = 1.0
	preview_container.offset_left = 0.0
	preview_container.offset_top = -6.0
	preview_container.offset_right = 0.0
	preview_container.offset_bottom = -6.0
	preview_container.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Dark semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.58)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	preview_container.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Preview title and state chip
	var label := Label.new()
	label.text = "Pose Preview"
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.63,0.61,0.75))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# Pose image (camera + skeleton)
	pose_preview = TextureRect.new()
	pose_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pose_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pose_preview.custom_minimum_size = Vector2(460, 180)
	pose_preview.texture = ImageTexture.new()
	vbox.add_child(pose_preview)

	# Compact state label
	state_label = Label.new()
	state_label.text = "Reps: 0"
	state_label.add_theme_font_size_override("font_size", 22)
	state_label.add_theme_color_override("font_color", Color(0.63,0.61,0.75))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var state_chip := _make_chip_panel()
	state_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	state_chip.add_child(state_label)
	vbox.add_child(state_chip)

	preview_container.add_child(vbox)
	pose_canvas.add_child(preview_container)
	add_child(pose_canvas)

	# Connect exercise signals for debug display
	ExerciseRecognizer.rep_completed.connect(_on_preview_rep)
	ExerciseRecognizer.form_feedback.connect(_on_preview_form)
	if game_instance and not game_instance.score_changed.is_connected(_on_game_score_changed):
		game_instance.score_changed.connect(_on_game_score_changed)

func _make_chip_panel() -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", style)
	return chip

func _make_chip_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(0, 36)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.12, 0.14, 0.19, 0.95)
	btn.add_theme_stylebox_override("hover", hover)
	return btn



func _on_preview_rep() -> void:
	if state_label:
		state_label.text = "Reps: %d" % SessionManager.current_reps

func _on_game_score_changed(score_value: int) -> void:
	pass

func _on_preview_form(message: String, is_good: bool) -> void:
	if state_label:
		# Short inline state message
		state_label.text = "Reps: %d — %s" % [SessionManager.current_reps, message]

func _on_preview_state(new_state: int) -> void:
	pass

func _get_state_name(state: int) -> String:
	match state:
		ExerciseRecognizer.State.IDLE: return "IDLE"
		ExerciseRecognizer.State.START_POSITION: return "START"
		ExerciseRecognizer.State.MOVEMENT_PHASE: return "MOVING"
		ExerciseRecognizer.State.END_POSITION: return "END"
		ExerciseRecognizer.State.REP_COUNTED: return "REP!"
		_: return "?"

func _on_game_over(score: int) -> void:
	ExerciseRecognizer.set_active_exercise("")
	# Styled game-over overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(460, 0)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color("#1A1640")
	pstyle.corner_radius_top_left = 22
	pstyle.corner_radius_top_right = 22
	pstyle.corner_radius_bottom_left = 22
	pstyle.corner_radius_bottom_right = 22
	pstyle.content_margin_left = 18
	pstyle.content_margin_right = 18
	pstyle.content_margin_top = 18
	pstyle.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", pstyle)

	var inner = VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	var title = Label.new()
	title.text = "Game Over"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 61)
	title.add_theme_color_override("font_color", Color("#06B6D4"))
	inner.add_child(title)

	var chips_row := HBoxContainer.new()
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.add_theme_constant_override("separation", 8)

	var score_chip := _make_result_chip("Score", str(score))
	var reps_chip := _make_result_chip("Reps", str(SessionManager.current_reps))
	chips_row.add_child(score_chip)
	chips_row.add_child(reps_chip)
	inner.add_child(chips_row)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var replay_btn = Button.new()
	replay_btn.text = "Play Again"
	replay_btn.add_theme_font_size_override("font_size", 29)
	replay_btn.custom_minimum_size = Vector2(140, 48)
	var replay_style = StyleBoxFlat.new()
	replay_style.bg_color = Color("#06B6D4")
	replay_style.corner_radius_top_left = 12
	replay_style.corner_radius_top_right = 12
	replay_style.corner_radius_bottom_left = 12
	replay_style.corner_radius_bottom_right = 12
	replay_style.content_margin_left = 16
	replay_style.content_margin_right = 16
	replay_style.content_margin_top = 10
	replay_style.content_margin_bottom = 10
	replay_btn.add_theme_stylebox_override("normal", replay_style)
	var replay_hover = replay_style.duplicate()
	replay_hover.bg_color = Color("#0891B2")
	replay_btn.add_theme_stylebox_override("hover", replay_hover)
	replay_btn.pressed.connect(func():
		if game_instance and game_instance.has_method("start_game"):
			game_instance.start_game()
			if overlay.get_parent(): overlay.get_parent().remove_child(overlay)
	)
	buttons.add_child(replay_btn)

	var return_btn = Button.new()
	return_btn.text = "Return to Menu"
	return_btn.add_theme_font_size_override("font_size", 29)
	return_btn.custom_minimum_size = Vector2(140, 48)
	var return_style = StyleBoxFlat.new()
	return_style.bg_color = Color("#171532")
	return_style.border_color = Color("#06B6D4")
	return_style.border_width_left = 1
	return_style.border_width_right = 1
	return_style.border_width_top = 1
	return_style.border_width_bottom = 1
	return_style.corner_radius_top_left = 12
	return_style.corner_radius_top_right = 12
	return_style.corner_radius_bottom_left = 12
	return_style.corner_radius_bottom_right = 12
	return_style.content_margin_left = 16
	return_style.content_margin_right = 16
	return_style.content_margin_top = 10
	return_style.content_margin_bottom = 10
	return_btn.add_theme_stylebox_override("normal", return_style)
	var return_hover = return_style.duplicate()
	return_hover.bg_color = Color("#1B1840")
	return_btn.add_theme_stylebox_override("hover", return_hover)
	return_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://Main.tscn")
	)
	buttons.add_child(return_btn)
	inner.add_child(buttons)
	root.add_child(panel)

	if pose_canvas:
		pose_canvas.add_child(overlay)
	else:
		add_child(overlay)

func _make_result_chip(label_text: String, value_text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.16, 0.95)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	chip.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color(0.63,0.61,0.75))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 24)
	value.add_theme_color_override("font_color", Color(1,1,1))
	row.add_child(value)
	return chip

func _camera_frame(image: MediaPipeImage) -> void:
	# Update pose preview with every captured frame for smooth display,
	# independently of how fast inference runs.
	if pose_preview and pose_preview.texture is ImageTexture:
		var raw := image.image
		if raw:
			var tex := pose_preview.texture as ImageTexture
			raw.convert(Image.FORMAT_RGB8)
			if Vector2i(tex.get_size()) == raw.get_size():
				tex.call_deferred("update", raw)
			else:
				tex.call_deferred("set_image", raw)
	super(image)

func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	if task:
		var now := Time.get_ticks_msec()
		# Skip if a previous inference is still in flight (within timeout window).
		if last_inference_ms >= 0 and now - last_inference_ms < Settings.inference_timeout_ms:
			return
		last_inference_ms = now
		task.detect_async(image, timestamp_ms)

func show_result(image: MediaPipeImage, result: MediaPipePoseLandmarkerResult) -> void:
	var render_source := _get_preview_render_source(image)
	var output_image := renderer.render(render_source, result.pose_landmarks)
	var img := output_image.image
	
	# Update full-screen camera view (if visible) -> VisionTask method handles the thread safety
	if image_view and image_view.visible:
		update_image(img)
	else:
		img.convert(Image.FORMAT_RGB8)

	# Update the pose PIP preview
	if pose_preview and pose_preview.texture:
		if pose_preview.texture is ImageTexture:
			var tex := pose_preview.texture as ImageTexture
			if Vector2i(tex.get_size()) == img.get_size():
				tex.call_deferred("update", img)
			else:
				tex.call_deferred("set_image", img)
	# Forward landmarks to exercise recognition system
	if result.pose_landmarks.size() > 0:
		ExerciseRecognizer.process_pose(result.pose_landmarks[0])

func _get_preview_render_source(image: MediaPipeImage) -> MediaPipeImage:
	return image

func _exit_tree() -> void:
	super ()
	GameManager.clear_active_game()
	if game_instance:
		game_instance.queue_free()
		game_instance = null
