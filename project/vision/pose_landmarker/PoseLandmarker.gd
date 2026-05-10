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
					
					# Hide the game's internal HUD (if it's not needed)
					var game_hud = game_instance.get_node_or_null("HUD")
					if game_hud and game_name != "dino": # Keep dino HUD if it's causing issues
						game_hud.visible = false
					
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
	pose_canvas.layer = 10 # On top of game
	
	overlay_root = Control.new()
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pose_canvas.add_child(overlay_root)

	# Top chips row: back + status
	var top_bar := HBoxContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 10
	top_bar.offset_top = 10
	top_bar.offset_right = -10
	top_bar.add_theme_constant_override("separation", 10)
	overlay_root.add_child(top_bar)

	back_button = Button.new()
	back_button.text = "← BACK"
	back_button.add_theme_font_size_override("font_size", 32)
	back_button.custom_minimum_size = Vector2(160, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color("#1A1640", 0.8)
	back_style.border_width_left = 2
	back_style.border_width_right = 2
	back_style.border_width_top = 2
	back_style.border_width_bottom = 2
	back_style.border_color = Color("#06B6D4", 0.5)
	back_style.corner_radius_top_left = 16
	back_style.corner_radius_top_right = 16
	back_style.corner_radius_bottom_left = 16
	back_style.corner_radius_bottom_right = 16
	back_style.content_margin_top = 8
	back_style.content_margin_bottom = 8
	back_style.content_margin_left = 20
	back_style.content_margin_right = 20
	back_button.add_theme_stylebox_override("normal", back_style)
	
	var back_hover := back_style.duplicate()
	back_hover.bg_color = Color("#2A2660", 0.9)
	back_hover.border_color = Color("#06B6D4", 1.0)
	back_button.add_theme_stylebox_override("hover", back_hover)
	
	back_button.pressed.connect(_back)
	top_bar.add_child(back_button)

	# Spacer to push timer to the right
	var mid_spacer := Control.new()
	mid_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(mid_spacer)
	
	var timer_panel := PanelContainer.new()
	timer_panel.custom_minimum_size = Vector2(160, 56) # Same as back button
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color("#1A1640", 0.7) # Match back button theme
	tstyle.border_width_left = 2
	tstyle.border_width_right = 2
	tstyle.border_width_top = 2
	tstyle.border_width_bottom = 2
	tstyle.border_color = Color("#06B6D4", 0.6) # Cyan border for "active" timer
	tstyle.corner_radius_top_left = 16
	tstyle.corner_radius_top_right = 16
	tstyle.corner_radius_bottom_left = 16
	tstyle.corner_radius_bottom_right = 16
	tstyle.content_margin_top = 8
	tstyle.content_margin_bottom = 8
	tstyle.content_margin_left = 20
	tstyle.content_margin_right = 20
	timer_panel.add_theme_stylebox_override("panel", tstyle)
	top_bar.add_child(timer_panel)
	
	timer_label = Label.new()
	timer_label.text = "00:00"
	timer_label.add_theme_font_size_override("font_size", 32) # Same as back button
	timer_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_panel.add_child(timer_label)
	

	# Bottom dock: Wide bar with space on sides
	var preview_container := PanelContainer.new()
	preview_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	preview_container.anchor_left = 0.1
	preview_container.anchor_right = 0.9
	preview_container.anchor_top = 0.82
	preview_container.anchor_bottom = 0.98
	preview_container.offset_left = 0
	preview_container.offset_right = 0
	preview_container.offset_top = 0
	preview_container.offset_bottom = 0
	preview_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	preview_container.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Deep navy theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0A1A", 0.85) # Slight transparency
	style.border_color = Color("#06B6D4")
	style.border_width_top = 2
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	preview_container.add_theme_stylebox_override("panel", style)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 20)
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_container.add_child(main_hbox)

	# --- Left Side: Score ---
	var score_box := VBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	score_label = Label.new()
	score_label.text = "0"
	score_label.add_theme_font_size_override("font_size", 64)
	score_label.add_theme_color_override("font_color", Color("#06B6D4"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(score_label)
	
	var score_title := Label.new()
	score_title.text = "SCORE"
	score_title.add_theme_font_size_override("font_size", 28)
	score_title.add_theme_color_override("font_color", Color("#A09CC0"))
	score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(score_title)
	main_hbox.add_child(score_box)

	# --- Center: Camera Preview ---
	var camera_box := VBoxContainer.new()
	camera_box.alignment = BoxContainer.ALIGNMENT_CENTER
	camera_box.add_theme_constant_override("separation", 10)

	# Pose image (camera + skeleton)
	pose_preview = TextureRect.new()
	pose_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pose_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pose_preview.custom_minimum_size = Vector2(240, 135)
	pose_preview.texture = ImageTexture.new()
	
	# Add a subtle border around the camera feed
	var cam_border := PanelContainer.new()
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0, 0, 0, 0.4)
	bstyle.border_width_left = 2
	bstyle.border_width_right = 2
	bstyle.border_width_top = 2
	bstyle.border_width_bottom = 2
	bstyle.border_color = Color(0.2, 0.2, 0.4)
	bstyle.corner_radius_top_left = 4
	bstyle.corner_radius_top_right = 4
	bstyle.corner_radius_bottom_left = 4
	bstyle.corner_radius_bottom_right = 4
	cam_border.add_theme_stylebox_override("panel", bstyle)
	cam_border.add_child(pose_preview)
	camera_box.add_child(cam_border)
	
	main_hbox.add_child(camera_box)

	# --- Right Side: Reps ---
	var rep_box := VBoxContainer.new()
	rep_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	rep_label = Label.new()
	rep_label.text = "0"
	rep_label.add_theme_font_size_override("font_size", 64)
	rep_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	rep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rep_box.add_child(rep_label)

	var rep_title := Label.new()
	rep_title.text = "REPS"
	rep_title.add_theme_font_size_override("font_size", 28)
	rep_title.add_theme_color_override("font_color", Color("#A09CC0"))
	rep_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rep_box.add_child(rep_title)
	main_hbox.add_child(rep_box)
	
	# --- Center Screen: Start Prompt ---
	prompt_label = Label.new()
	prompt_label.text = "DO A REP TO START"
	prompt_label.add_theme_font_size_override("font_size", 48)
	prompt_label.add_theme_color_override("font_color", Color("#FFFFFF", 0.7))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	pose_canvas.add_child(prompt_label)

	pose_canvas.add_child(preview_container)
	add_child(pose_canvas)

	# Connect exercise signals for debug display
	ExerciseRecognizer.rep_completed.connect(_on_preview_rep)
	if game_instance:
		if not game_instance.score_changed.is_connected(_on_game_score_changed):
			game_instance.score_changed.connect(_on_game_score_changed)
		if not game_instance.game_over.is_connected(_on_game_over_reset):
			game_instance.game_over.connect(_on_game_over_reset)
		is_timing = false # Wait for first rep to start timing
		elapsed_time = 0.0

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
	# We don't reset elapsed_time here so it stays visible on the HUD during Game Over
	if prompt_label:
		prompt_label.visible = true

func _on_preview_form(message: String, is_good: bool) -> void:
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
	panel.custom_minimum_size = Vector2(520, 0) # Slightly wider
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
	inner.add_theme_constant_override("separation", 24) # More space
	panel.add_child(inner)

	var title = Label.new()
	title.text = "Game Over"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 61)
	title.add_theme_color_override("font_color", Color("#06B6D4"))
	inner.add_child(title)

	var chips_row := HBoxContainer.new()
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.add_theme_constant_override("separation", 20) # More space between chips

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
	chip.custom_minimum_size = Vector2(180, 120)
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
	value.add_theme_font_size_override("font_size", 54) # Much larger
	value.add_theme_color_override("font_color", Color("#FFFFFF"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(value)
	return chip

func _process(delta: float) -> void:
	if is_timing:
		elapsed_time += delta
		if timer_label:
			var mins = int(elapsed_time) / 60
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
