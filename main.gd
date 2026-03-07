extends Node2D

# --- MediaPipe ---
var task: MediaPipePoseLandmarker
var running_mode := MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM
var delegate := MediaPipeTaskBaseOptions.DELEGATE_CPU

# --- Camera ---
var camera_ext: CameraServerExtension
var camera_feed
var saved_debug := false
var frame_count := 0

@onready var camera_display: TextureRect = $CameraDisplay
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_tex_rect: TextureRect = $CameraViewport/CameraTexture

func _ready():
	# Step 1: Load the model
	var file := FileAccess.open("res://models/pose_landmarker_lite.task", FileAccess.READ)
	if file == null:
		print("ERROR: Could not open model file")
		return
	
	# Step 2: Set up the pose landmarker
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = delegate
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	
	task = MediaPipePoseLandmarker.new()
	task.initialize(base_options, running_mode)
	task.result_callback.connect(self._result_callback)
	
	print("Pose landmarker initialized!")
	
	# Step 3: Start camera
	CameraServer.monitoring_feeds = true
	camera_ext = CameraServerExtension.new()
	CameraServer.camera_feed_added.connect(self._on_feed_added)
	await get_tree().create_timer(1.0).timeout
	_try_start_camera()

func _try_start_camera():
	var feeds = CameraServer.feeds()
	print("Camera feeds available: ", feeds.size())
	
	if feeds.size() == 0:
		print("No feeds yet, waiting...")
		return
	
	camera_feed = feeds[0]
	
	# Set a format if available
	var formats = camera_feed.get_formats()
	print("Available formats: ", formats.size())
	if formats.size() > 0:
		camera_feed.set_format(0, {})
	
	# Set up CameraTexture to receive the feed
	var cam_texture := CameraTexture.new()
	cam_texture.camera_feed_id = camera_feed.get_id()
	cam_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	camera_tex_rect.texture = cam_texture
	
	# Size the viewport to match
	var tex_size = cam_texture.get_size()
	if tex_size != Vector2.ZERO:
		camera_viewport.size = Vector2i(tex_size)
	else:
		camera_viewport.size = Vector2i(640, 480)
	
	# Connect frame signal
	camera_feed.frame_changed.connect(self._on_frame, CONNECT_DEFERRED)
	camera_feed.feed_is_active = true
	print("Camera started: ", camera_feed.get_name())

func _on_feed_added(_id: int):
	if camera_feed != null:
		return
	_try_start_camera()

func _on_frame():
	if camera_viewport == null:
		return
	
	await RenderingServer.frame_post_draw
	
	if camera_viewport == null:
		return
	var tex = camera_viewport.get_texture()
	if tex == null:
		print("No texture from viewport")
		return
	var image = tex.get_image()
	if image == null or image.is_empty():
		print("Empty image from viewport")
		return
	
	print("Got image: ", image.get_size())
	
	frame_count += 1
	if frame_count == 100:
		var err = image.save_png("C:/FYP/debug_frame_100.png")
		print("Saved frame 100, result: ", err)
	
	# DEBUG: Save one frame to check if it has content
	if Engine.get_process_frames() == 30:
		image.save_png("res://debug_frame.png")
		print("Saved debug frame!")
	
	image.convert(Image.FORMAT_RGB8)
	
	call_deferred("_update_display", image)
	
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(image)
	task.detect_async(mp_image, Time.get_ticks_msec())

func _result_callback(result: MediaPipePoseLandmarkerResult, _image: MediaPipeImage, _timestamp_ms: int) -> void:
	var landmarks = result.pose_landmarks
	if landmarks.size() > 0:
		print("Pose detected! Landmarks: ", landmarks.size())

func _update_display(image: Image):
	if camera_display.texture == null:
		camera_display.texture = ImageTexture.create_from_image(image)
	elif Vector2i(camera_display.texture.get_size()) == image.get_size():
		camera_display.texture.update(image)
	else:
		camera_display.texture = ImageTexture.create_from_image(image)
