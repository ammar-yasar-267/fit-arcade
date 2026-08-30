extends VisionTask

## PoseLandmarker — detects pose landmarks from camera feed.
## Forwards landmark data to ExerciseManager for rep detection.
## Loads and displays the selected game alongside the camera.
## Shows a PIP camera preview with rendered pose skeleton overlay.

var task: MediaPipePoseLandmarker
var task_file := "pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
var renderer: MediaPipePoseRenderer
var game_instance: GameBase = null
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

# HUD elements for gameplay
var score_label: Label = null
var timer_label: Label = null
var rep_label: Label = null
var prompt_label: Label = null
var elapsed_time: float = 0.0
var is_timing: bool = false

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
					
					# HUD.gd (inside the game scene) is the primary in-game HUD
					
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
	pose_canvas.layer = 10

	overlay_root = Control.new()
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pose_canvas.add_child(overlay_root)

	# --- Full-screen invisible tap area → shows pause menu ---
	var tap_btn := Button.new()
	tap_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap_btn.flat = true
	var tap_style := StyleBoxFlat.new()
	tap_style.bg_color = Color(0, 0, 0, 0)
	tap_btn.add_theme_stylebox_override("normal", tap_style)
	tap_btn.add_theme_stylebox_override("hover", tap_style)
	tap_btn.add_theme_stylebox_override("pressed", tap_style)
	tap_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	tap_btn.pressed.connect(_on_screen_tapped)
	overlay_root.add_child(tap_btn)

	# --- Pause overlay (hidden by default) ---
	pause_overlay_ref = ColorRect.new()
	pause_overlay_ref.color = Color(0, 0, 0, 0.78)
	pause_overlay_ref.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay_ref.visible = false

	var pause_center := CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay_ref.add_child(pause_center)

	var pause_card := PanelContainer.new()
	pause_card.custom_minimum_size = Vector2(380, 0)
	var pause_card_style := StyleBoxFlat.new()
	pause_card_style.bg_color = Color("#1A1640")
	pause_card_style.border_width_top = 4
	pause_card_style.border_color = Color("#06B6D4")
	pause_card_style.corner_radius_top_left = 24
	pause_card_style.corner_radius_top_right = 24
	pause_card_style.corner_radius_bottom_left = 24
	pause_card_style.corner_radius_bottom_right = 24
	pause_card_style.content_margin_left = 32
	pause_card_style.content_margin_right = 32
	pause_card_style.content_margin_top = 32
	pause_card_style.content_margin_bottom = 32
	pause_card_style.shadow_color = Color(0, 0, 0, 0.5)
	pause_card_style.shadow_size = 20
	pause_card.add_theme_stylebox_override("panel", pause_card_style)
	pause_center.add_child(pause_card)

	var pause_inner := VBoxContainer.new()
	pause_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_inner.add_theme_constant_override("separation", 24)
	pause_card.add_child(pause_inner)

	var pause_title := Label.new()
	pause_title.text = "Paused"
	pause_title.add_theme_font_size_override("font_size", 52)
	pause_title.add_theme_color_override("font_color", Color("#06B6D4"))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_inner.add_child(pause_title)

	var resume_btn := _make_pause_btn("Resume", true)
	resume_btn.pressed.connect(_resume_game)
	pause_inner.add_child(resume_btn)

	var pause_menu_btn := _make_pause_btn("Main Menu", false)
	pause_menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	pause_inner.add_child(pause_menu_btn)

	overlay_root.add_child(pause_overlay_ref)

	# --- Bottom dock: camera only, fixed-width centered card ---
	var dock := PanelContainer.new()
	dock.anchor_left = 0.5
	dock.anchor_right = 0.5
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = -185
	dock.offset_right = 185
	dock.offset_top = -200
	dock.offset_bottom = -16
	var dock_style := StyleBoxFlat.new()
	dock_style.bg_color = Color("#08081C", 0.96)
	dock_style.border_color = Color("#06B6D4", 0.4)
	dock_style.border_width_top = 2
	dock_style.corner_radius_top_left = 32
	dock_style.corner_radius_top_right = 32
	dock_style.corner_radius_bottom_left = 32
	dock_style.corner_radius_bottom_right = 32
	dock_style.content_margin_left = 20
	dock_style.content_margin_right = 20
	dock_style.content_margin_top = 18
	dock_style.content_margin_bottom = 18
	dock.add_theme_stylebox_override("panel", dock_style)
	overlay_root.add_child(dock)

	var dock_center := CenterContainer.new()
	dock_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(dock_center)

	# Camera feed — centered, fixed width
	var cam_panel := PanelContainer.new()
	cam_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cam_style := StyleBoxFlat.new()
	cam_style.bg_color = Color(0, 0, 0, 0.5)
	cam_style.corner_radius_top_left = 10
	cam_style.corner_radius_top_right = 10
	cam_style.corner_radius_bottom_left = 10
	cam_style.corner_radius_bottom_right = 10
	cam_panel.add_theme_stylebox_override("panel", cam_style)
	dock_center.add_child(cam_panel)

	pose_preview = TextureRect.new()
	pose_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pose_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pose_preview.custom_minimum_size = Vector2(250, 148)
	pose_preview.texture = ImageTexture.new()
	cam_panel.add_child(pose_preview)

	# Hidden labels — kept so signal handlers don't crash
	timer_label = Label.new()
	timer_label.visible = false
	overlay_root.add_child(timer_label)

	score_label = Label.new()
	score_label.visible = false
	overlay_root.add_child(score_label)

	rep_label = Label.new()
	rep_label.visible = false
	overlay_root.add_child(rep_label)

	prompt_label = Label.new()
	prompt_label.visible = false
	overlay_root.add_child(prompt_label)

	add_child(pose_canvas)

	# Connect signals
	ExerciseRecognizer.rep_completed.connect(_on_preview_rep)
	if game_instance:
		if not game_instance.score_changed.is_connected(_on_game_score_changed):
			game_instance.score_changed.connect(_on_game_score_changed)
		if not game_instance.game_over.is_connected(_on_game_over_reset):
			game_instance.game_over.connect(_on_game_over_reset)
		is_timing = false
		elapsed_time = 0.0

func _make_dock_icon_btn(icon: String, icon_size: int) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(76, 76)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", icon_size)
	btn.add_theme_color_override("font_color", Color("#9896C8"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#12112E")
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color("#06B6D4", 0.5)
	normal.corner_radius_top_left = 999
	normal.corner_radius_top_right = 999
	normal.corner_radius_bottom_left = 999
	normal.corner_radius_bottom_right = 999
	normal.shadow_color = Color("#06B6D4", 0.18)
	normal.shadow_size = 10
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 16
	normal.content_margin_bottom = 16
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("#1C1A4A")
	hover.border_color = Color("#06B6D4", 1.0)
	hover.shadow_color = Color("#06B6D4", 0.45)
	hover.shadow_size = 16
	btn.add_theme_stylebox_override("hover", hover)
	return btn

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


func _on_screen_tapped() -> void:
	if pause_overlay_ref and not pause_overlay_ref.visible:
		if game_instance and game_instance.is_running:
			_paused_exercise = ExerciseRecognizer.current_exercise
			ExerciseRecognizer.current_exercise = null
			game_instance.process_mode = Node.PROCESS_MODE_DISABLED
			pause_overlay_ref.show()

func _resume_game() -> void:
	if _paused_exercise != null:
		ExerciseRecognizer.current_exercise = _paused_exercise
		_paused_exercise = null
	if game_instance:
		game_instance.process_mode = Node.PROCESS_MODE_INHERIT
	if pause_overlay_ref:
		pause_overlay_ref.hide()

func _make_pause_btn(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 26)
	btn.custom_minimum_size = Vector2(300, 58)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = Color("#06B6D4")
	else:
		style.bg_color = Color("#11102B")
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color("#06B6D4")
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

func _on_game_over(score: int) -> void:
	# If the game ended while paused, restore the exercise so Play Again works
	if _paused_exercise != null:
		ExerciseRecognizer.current_exercise = _paused_exercise
		_paused_exercise = null
	if game_instance:
		game_instance.process_mode = Node.PROCESS_MODE_INHERIT

	if pause_overlay_ref and pause_overlay_ref.visible:
		pause_overlay_ref.hide()

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color("#1A1640")
	pstyle.border_width_top = 4
	pstyle.border_color = Color("#06B6D4")
	pstyle.corner_radius_top_left = 28
	pstyle.corner_radius_top_right = 28
	pstyle.corner_radius_bottom_left = 28
	pstyle.corner_radius_bottom_right = 28
	pstyle.content_margin_left = 32
	pstyle.content_margin_right = 32
	pstyle.content_margin_top = 32
	pstyle.content_margin_bottom = 32
	pstyle.shadow_color = Color(0, 0, 0, 0.5)
	pstyle.shadow_size = 24
	panel.add_theme_stylebox_override("panel", pstyle)
	root.add_child(panel)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 28)
	panel.add_child(inner)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("#06B6D4"))
	inner.add_child(title)

	var secs := int(elapsed_time)
	var time_str := "%d:%02d" % [secs / 60.0, secs % 60]

	var chips_row := HBoxContainer.new()
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.add_theme_constant_override("separation", 12)
	chips_row.add_child(_make_result_chip("Score", str(score)))
	chips_row.add_child(_make_result_chip("Time", time_str))
	chips_row.add_child(_make_result_chip("Reps", str(SessionManager.current_reps)))
	inner.add_child(chips_row)

	var btns_col := VBoxContainer.new()
	btns_col.add_theme_constant_override("separation", 12)
	inner.add_child(btns_col)

	var replay_btn := _make_pause_btn("Play Again", true)
	replay_btn.pressed.connect(func():
		if game_instance and game_instance.has_method("start_game"):
			game_instance.start_game()
			if overlay.get_parent():
				overlay.get_parent().remove_child(overlay)
	)
	btns_col.add_child(replay_btn)

	var menu_btn := _make_pause_btn("Main Menu", false)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	btns_col.add_child(menu_btn)


	if pose_canvas:
		pose_canvas.add_child(overlay)
	else:
		add_child(overlay)

func _make_result_chip(label_text: String, value_text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(130, 90)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#11102B")
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color("#06B6D4", 0.4)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	chip.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(vbox)

	var label := Label.new()
	label.text = label_text.to_upper()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#A09CC0"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 38)
	value.add_theme_color_override("font_color", Color("#FFFFFF"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(value)
	return chip

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
