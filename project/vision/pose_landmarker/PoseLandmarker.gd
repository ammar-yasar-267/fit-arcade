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
	# Start the active exercise
	ExerciseManager.start_exercise()

	# Load and start the game
	var game_name: String = GameManager.selected_game_name
	if game_name != "":
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

	# Create PIP pose preview overlay on top of everything
	_create_pose_preview()

func _create_pose_preview() -> void:
	pose_canvas = CanvasLayer.new()
	pose_canvas.layer = 10 # On top of everything
	
	# Minimal HUD back button
	var hud_back := Button.new()
	hud_back.text = "Back"
	hud_back.anchors_preset = Control.PRESET_TOP_LEFT
	hud_back.offset_left = 10
	hud_back.offset_top = 10
	hud_back.offset_right = 110
	hud_back.offset_bottom = 58
	hud_back.add_theme_font_size_override("font_size", 22)
	hud_back.pressed.connect(_back)
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.08, 0.09, 0.12, 0.88)
	back_style.corner_radius_top_left = 12
	back_style.corner_radius_top_right = 12
	back_style.corner_radius_bottom_left = 12
	back_style.corner_radius_bottom_right = 12
	hud_back.add_theme_stylebox_override("normal", back_style)
	pose_canvas.add_child(hud_back)

	# Camera preview with pose skeleton — top-right corner
	var preview_container := PanelContainer.new()
	preview_container.anchors_preset = Control.PRESET_TOP_RIGHT
	preview_container.anchor_left = 0.62
	preview_container.anchor_top = 0.0
	preview_container.anchor_right = 1.0
	preview_container.anchor_bottom = 0.31
	preview_container.offset_left = -8.0
	preview_container.offset_top = 8.0
	preview_container.offset_right = -8.0
	preview_container.offset_bottom = 0.0
	preview_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Dark semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	preview_container.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Preview label
	var label := Label.new()
	label.text = "Camera"
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# Pose image
	pose_preview = TextureRect.new()
	pose_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pose_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pose_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pose_preview.texture = ImageTexture.new()
	vbox.add_child(pose_preview)

	# Compact session info
	state_label = Label.new()
	state_label.text = "Reps: 0"
	state_label.add_theme_font_size_override("font_size", 12)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(state_label)

	preview_container.add_child(vbox)
	pose_canvas.add_child(preview_container)
	add_child(pose_canvas)

	# Connect exercise signals for debug display
	ExerciseManager.rep_completed.connect(_on_preview_rep)
	ExerciseManager.form_invalid.connect(_on_preview_form)
	if ExerciseManager.get_active_exercise():
		ExerciseManager.get_active_exercise().state_changed.connect(_on_preview_state)

func _on_preview_rep(rep_count: int) -> void:
	if state_label:
		state_label.text = "Reps: %d" % rep_count

func _on_preview_form(message: String) -> void:
	if state_label:
		state_label.text = "Reps: %d | %s" % [ExerciseManager.get_active_exercise().rep_count if ExerciseManager.get_active_exercise() else 0, message]

func _on_preview_state(new_state: int) -> void:
	pass

func _get_state_name(state: int) -> String:
	match state:
		ExerciseBase.State.IDLE: return "IDLE"
		ExerciseBase.State.START_POSITION: return "START"
		ExerciseBase.State.MOVEMENT_PHASE: return "MOVING"
		ExerciseBase.State.END_POSITION: return "END"
		ExerciseBase.State.REP_COUNTED: return "REP!"
		_: return "?"

func _on_game_over(_score: int) -> void:
	ExerciseManager.stop_exercise()

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
	var output_image := renderer.render(image, result.pose_landmarks)
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
		ExerciseManager.process_landmarks(result.pose_landmarks[0])

func _exit_tree() -> void:
	super ()
	ExerciseManager.stop_exercise()
	GameManager.clear_active_game()
	if game_instance:
		game_instance.queue_free()
		game_instance = null
