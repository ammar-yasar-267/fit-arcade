extends VisionTask

## PoseLandmarker — detects pose landmarks from camera feed.
## Forwards landmark data to ExerciseManager for rep detection.
## Loads and displays the selected game alongside the camera.
## Shows a PIP camera preview with rendered pose skeleton overlay.

var graph: MoveNetGraph
var task_file := "pose_landmarker/movenet_lightning/movenet_singlepose_lightning_f16.tflite"
var renderer: MediaPipePoseRenderer
var _last_camera_image: MediaPipeImage = null
var game_instance: GameBase = null
var _game_viewport: SubViewport = null
var game_canvas: CanvasLayer = null
var pose_preview: TextureRect = null
var pose_canvas: CanvasLayer = null
var state_label: Label = null
var back_button: Button = null
var overlay_root: Control = null
var pause_overlay_ref: ColorRect = null
var _paused_exercise = null
# Timestamp of last detect_async call; -1 means no inference pending.
# Using a timestamp instead of a boolean prevents permanent lockup when
# MediaPipe does not call back (e.g. no person in frame).
var last_inference_ms: int = -1
## Id (packet timestamp) of the most recent frame handed to the model. Only its answer
## frees the in-flight gate; a late answer for an older frame mustn't.
var _latest_sent_id: int = -1

# HUD elements for gameplay
var score_label: Label = null
var timer_label: Label = null
var rep_label: Label = null
var prompt_label: Label = null
var elapsed_time: float = 0.0
var is_timing: bool = false

func _on_graph_packets(packets: Dictionary) -> void:
	var result_us := Time.get_ticks_usec()
	# MediaPipe carries the input frame's timestamp through to its output, so the answer
	# is matched to ITS frame. With no pose found there is no output packet to read an id
	# from; MediaPipe still answers in send order, so that's the oldest outstanding frame.
	var frame_id: int
	if packets.has("pose_landmarks"):
		frame_id = (packets["pose_landmarks"] as MediaPipePacket).timestamp
	else:
		frame_id = PerfStats.oldest_pending_id()
	PerfStats.frame_result(frame_id, result_us)
	if frame_id == _latest_sent_id or frame_id == -1:
		last_inference_ms = -1

	_handle_graph_result(packets)
	PerfStats.frame_done(frame_id)

## Recognition, drawing and UI updates for one model result. Everything in here counts
## towards the frame's "post" time.
func _handle_graph_result(packets: Dictionary) -> void:
	if not packets.has("pose_landmarks") or _last_camera_image == null:
		show_result(_last_camera_image, null)
		return
	var packet: MediaPipePacket = packets["pose_landmarks"]
	var raw := packet.get() as MediaPipeNormalizedLandmarks
	show_result(_last_camera_image, _fix_landmark_order(raw) if raw != null else null)

## MoveNet's raw output tensor is laid out per-keypoint as (y, x, score), but
## TensorsToLandmarksCalculator decodes it positionally as (x, y, z) — so the
## landmarks coming out of the graph have x/y swapped and confidence sitting in z.
## MediaPipeNormalizedLandmark has no GDScript setters, so the fix has to go through
## a fresh NormalizedLandmarkList proto rather than mutating the existing object.
func _fix_landmark_order(raw: MediaPipeNormalizedLandmarks) -> MediaPipeNormalizedLandmarks:
	# set_repeated_field() only sets an *existing* index — it doesn't grow the list —
	# so building a fresh 17-element NormalizedLandmarkList has to go through raw
	# protobuf bytes (see MoveNetGraph._append_float_field/_append_message_field),
	# the same way the calculator options did.
	var raw_points := raw.get_landmarks()
	var buffer := PackedByteArray()
	for pt in raw_points:
		var lm_bytes := PackedByteArray()
		MoveNetGraph._append_float_field(lm_bytes, 1, pt.y) # x <- MoveNet's y
		MoveNetGraph._append_float_field(lm_bytes, 2, pt.x) # y <- MoveNet's x
		MoveNetGraph._append_float_field(lm_bytes, 4, pt.z) # visibility <- MoveNet's score
		MoveNetGraph._append_message_field(buffer, 1, lm_bytes) # field 1 = repeated NormalizedLandmark landmark
	var list_proto := MediaPipeProto.new()
	list_proto.initialize("mediapipe.NormalizedLandmarkList")
	if not buffer.is_empty():
		list_proto.parse_from_buffer(buffer)
	return list_proto.get_packet().get() as MediaPipeNormalizedLandmarks

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
	print("DEBUG: _auto_open_camera() called, OS: ", OS.get_name())
	# Step 1: Enable monitoring
	if not CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = true
	# Step 2: On Windows/iOS/Android, force-create the CameraServerExtension immediately
	if OS.get_name() in ["Windows", "iOS", "Android"] and camera_extension == null:
		print("DEBUG: Creating CameraServerExtension for ", OS.get_name())
		camera_extension = CameraServerExtension.new()
		camera_extension.permission_result.connect(self._on_auto_permission_result)
		var perm_granted = camera_extension.permission_granted()
		print("DEBUG: permission_granted() returned: ", perm_granted)
		if not perm_granted:
			print("DEBUG: Requesting camera permission...")
			camera_extension.request_permission()
			if OS.get_name() == "Android":
				OS.request_permissions()
			return # Wait for permission callback
	# Step 3: Try to select a camera
	print("DEBUG: Proceeding to _select_camera()")
	_select_camera()

func _on_auto_permission_result(granted: bool) -> void:
	print("DEBUG: _on_auto_permission_result called with granted=", granted)
	if granted:
		_select_camera()
	else:
		print("DEBUG: Permission denied, showing dialog")
		permission_dialog.popup_centered()

func _init_task():
	var file := get_external_model(task_file)
	if file == null:
		return
	var bytes := file.get_buffer(file.get_length())
	var model_path := _ensure_model_on_disk(bytes)
	graph = MoveNetGraph.new(model_path, Settings.use_hardware_accel())
	graph.packets_callback.connect(self._on_graph_packets)
	graph.error.connect(func(msg): push_error("MoveNet graph error: ", msg))
	renderer = MediaPipePoseRenderer.new()
	last_inference_ms = -1
	super ()

## InferenceCalculator needs a real filesystem path (not a res:// pck entry), so
## the bundled model is copied to user:// once and referenced by its absolute path.
## Re-checks size on every launch rather than trusting "file exists" — an earlier
## crashy/interrupted run could otherwise leave a truncated copy cached forever,
## silently feeding InferenceCalculator garbage on every later run.
func _ensure_model_on_disk(bytes: PackedByteArray) -> String:
	var dir := "user://movenet"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("movenet_singlepose_lightning_f16.tflite")
	var needs_write := true
	if FileAccess.file_exists(path):
		needs_write = FileAccess.get_size(path) != bytes.size()
	if needs_write:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
	return ProjectSettings.globalize_path(path)

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
					# Create a dedicated CanvasLayer for the game (Layer 1, below HUD)
					game_canvas = CanvasLayer.new()
					game_canvas.layer = 1
					add_child(game_canvas)
					# Calculate logical dimensions to fill height
					var window_size = get_viewport().get_visible_rect().size
					if window_size.y == 0: window_size = Vector2(540, 960)
					
					var aspect = float(window_size.x) / float(window_size.y)
					var logical_height = 960.0
					var logical_width = logical_height * aspect
					
					# Create the Viewport
					var viewport = SubViewport.new()
					viewport.size = Vector2i(int(logical_width), int(logical_height))
					viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					viewport.handle_input_locally = true
					viewport.transparent_bg = false
					_game_viewport = viewport
					
					# Create the display texture FIRST
					var game_display = TextureRect.new()
					game_display.set_anchors_preset(Control.PRESET_FULL_RECT)
					game_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					game_display.stretch_mode = TextureRect.STRETCH_SCALE
					game_canvas.add_child(game_display)
					
					# Add viewport to tree
					add_child(viewport)
					viewport.add_child(game_instance)
					
					# Link texture (must happen AFTER adding viewport to tree)
					game_display.texture = viewport.get_texture()
					
					# Center the game content
					if game_instance is Node2D:
						game_instance.position.x = (logical_width - 540.0) / 2.0
					
					GameManager.set_active_game(game_instance)

					# Reparent HUD to main window CanvasLayer so HUD controls, top bar,
					# primed overlay, paused overlay, and PIP card operate cleanly at
					# native viewport coordinates:
					var hud_node = game_instance.get_node_or_null("HUD")
					if hud_node:
						game_instance.remove_child(hud_node)
						hud_node.request_ready()
						add_child(hud_node)
						game_instance.hud = hud_node
						if hud_node.has_method("bind_game"):
							hud_node.bind_game(game_instance)
					
					game_instance.start_game()
					if not game_instance.game_over.is_connected(_on_game_over):
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

func _preview_views() -> Array:
	return [image_view, pose_preview]

func _create_pose_preview() -> void:
	# Bind directly to HUD's PIP preview
	var active_game = GameManager.get_active_game()
	var hud_node: GameHUD = null
	if active_game:
		if active_game.get("hud") != null and active_game.hud is GameHUD:
			hud_node = active_game.hud
		elif active_game.has_node("HUD"):
			hud_node = active_game.get_node("HUD") as GameHUD
	if hud_node == null:
		hud_node = get_node_or_null("HUD") as GameHUD

	if hud_node and hud_node.has_method("get_pip_preview"):
		pose_preview = hud_node.get_pip_preview()
		_apply_preview_mirror()
		if not ExerciseRecognizer.rep_completed.is_connected(_on_preview_rep):
			ExerciseRecognizer.rep_completed.connect(_on_preview_rep)
		return

	# Fallback if running standalone PoseLandmarker scene without HUD (spec D3: 96x144, 2px border):
	pose_canvas = CanvasLayer.new()
	pose_canvas.layer = 5
	add_child(pose_canvas)

	var pip_card := PanelContainer.new()
	pip_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pip_card.offset_right = -12
	pip_card.offset_bottom = -12
	pip_card.offset_left = -108
	pip_card.offset_top = -156
	pip_card.custom_minimum_size = Vector2(96, 144)
	pip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111111")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 1.0, 1.0, 0.8)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	pip_card.add_theme_stylebox_override("panel", style)
	pose_canvas.add_child(pip_card)

	pose_preview = TextureRect.new()
	pose_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	pose_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pose_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pose_preview.texture = ImageTexture.new()
	pose_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip_card.add_child(pose_preview)
	_apply_preview_mirror()

	if not ExerciseRecognizer.rep_completed.is_connected(_on_preview_rep):
		ExerciseRecognizer.rep_completed.connect(_on_preview_rep)

func _on_preview_rep() -> void:
	if rep_label:
		rep_label.text = str(SessionManager.current_reps)
	if prompt_label:
		prompt_label.visible = false
	# If game hasn't started yet, first rep starts it
	if game_instance and game_instance.is_running and not is_timing:
		is_timing = true
		elapsed_time = 0.0

func _on_game_score_changed(score_value: int) -> void:
	if score_label:
		score_label.text = str(score_value)

func _on_game_over_reset(_score: int) -> void:
	is_timing = false
	# prompt handled by HUD.gd

func _on_preview_form(_message: String, _is_good: bool) -> void:
	pass

func _get_state_name(state: int) -> String:
	match state:
		ExerciseRecognizer.State.IDLE: return "IDLE"
		ExerciseRecognizer.State.START_POSITION: return "START"
		ExerciseRecognizer.State.MOVEMENT_PHASE: return "MOVING"
		ExerciseRecognizer.State.END_POSITION: return "END"
		ExerciseRecognizer.State.REP_COUNTED: return "REP!"
		_: return "?"

func _on_game_over(_score: int, _reps: int = 0) -> void:
	if _paused_exercise != null:
		ExerciseRecognizer.current_exercise = _paused_exercise
		_paused_exercise = null
	if game_instance:
		game_instance.process_mode = Node.PROCESS_MODE_INHERIT

func _process(delta: float) -> void:
	if is_timing:
		elapsed_time += delta
		if timer_label:
			var mins = int(elapsed_time) / 60.0
			var secs = int(elapsed_time) % 60
			timer_label.text = "%02d:%02d" % [mins, secs]

	super (delta)

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
	super (image)

func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	if graph:
		var now := Time.get_ticks_msec()
		# Skip if a previous inference is still in flight (within timeout window).
		if last_inference_ms >= 0 and now - last_inference_ms < Settings.inference_timeout_ms:
			PerfStats.frame_skipped("inflight")
			return
		last_inference_ms = now
		_last_camera_image = image
		# PoseRenderer.gd's proven-working pattern uses get_image_frame_packet()
		# (mediapipe::ImageFrame), not get_packet() (mediapipe::Image) — switching
		# to match it, since all-17-points-collapsed-to-one-value output suggests
		# the graph was receiving degenerate/blank image data via the Image path.
		var packet := image.get_image_frame_packet()
		var frame_id := timestamp_ms * 1000
		packet.timestamp = frame_id
		_latest_sent_id = frame_id
		# Everything from the camera frame arriving up to this send is the "prep" stage
		PerfStats.frame_sent(frame_id, _frame_arrive_us)
		graph.send({"input_image": packet})

func show_result(image: MediaPipeImage, landmarks: MediaPipeNormalizedLandmarks) -> void:
	if image == null:
		return
	var render_source := _get_preview_render_source(image)
	var multi_landmarks: Array[MediaPipeNormalizedLandmarks] = []
	var is_in_calibration: bool = (get_parent() is CalibrationScreen) and (game_instance == null)
	if landmarks != null and Settings.show_skeleton and not is_in_calibration:
		multi_landmarks.append(landmarks)
	var output_image := renderer.render(render_source, multi_landmarks)
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
	if landmarks != null:
		ExerciseRecognizer.process_pose(landmarks)

func _get_preview_render_source(image: MediaPipeImage) -> MediaPipeImage:
	return image

func _unhandled_input(event: InputEvent) -> void:
	if _game_viewport and is_instance_valid(_game_viewport):
		_game_viewport.push_input(event)

func _exit_tree() -> void:
	_reset()
	_game_viewport = null
	if ExerciseRecognizer.rep_completed.is_connected(_on_preview_rep):
		ExerciseRecognizer.rep_completed.disconnect(_on_preview_rep)
	GameManager.clear_active_game()
	if game_instance:
		game_instance.queue_free()
		game_instance = null
	super()
