class_name CalibrationScreen
extends Control

## Calibration screen for FitArcade.
## Visual source of truth: references/04-calibrate.png
## Spec from design-spec.md Section D2 and Calibrate.tsx.

const IconButtonClass = preload("res://ui/components/IconButton.gd")
const SkeletonClass = preload("res://ui/components/Skeleton.gd")

# Sub-component: Frame Guide with 2px stage-colored border, inner glow tint, and 4 corner brackets
class FrameGuide extends Control:
	var stage_color: Color = Tokens.SIGNAL:
		set(v):
			stage_color = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var arm_len := 24.0
		var arm_thick := 6.0

		# 1. Subtle inner translucent glow tint
		draw_rect(Rect2(Vector2.ZERO, size), Color(stage_color.r, stage_color.g, stage_color.b, 0.05), true)

		# 2. 2px border in stage color
		draw_rect(Rect2(Vector2.ZERO, size), stage_color, false, 2.0)

		# 3. 4 Corner brackets: 24x24 L-shapes with 6px arm thickness
		# Top-Left
		draw_rect(Rect2(0, 0, arm_len, arm_thick), stage_color, true)
		draw_rect(Rect2(0, 0, arm_thick, arm_len), stage_color, true)

		# Top-Right
		draw_rect(Rect2(w - arm_len, 0, arm_len, arm_thick), stage_color, true)
		draw_rect(Rect2(w - arm_thick, 0, arm_thick, arm_len), stage_color, true)

		# Bottom-Right
		draw_rect(Rect2(w - arm_len, h - arm_thick, arm_len, arm_thick), stage_color, true)
		draw_rect(Rect2(w - arm_thick, h - arm_len, arm_thick, arm_len), stage_color, true)

		# Bottom-Left
		draw_rect(Rect2(0, h - arm_thick, arm_len, arm_thick), stage_color, true)
		draw_rect(Rect2(0, h - arm_len, arm_thick, arm_len), stage_color, true)


# Sub-component: Custom Lock Progress Bar (12px tall, rounded 2px, filled with Tokens.VOLT)
class LockProgressBar extends Control:
	var progress: float = 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var track_sb := StyleBoxFlat.new()
		track_sb.bg_color = Color(1, 1, 1, 0.1)
		track_sb.corner_radius_top_left = 2
		track_sb.corner_radius_top_right = 2
		track_sb.corner_radius_bottom_left = 2
		track_sb.corner_radius_bottom_right = 2
		track_sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		if progress > 0.001:
			var fill_sb := StyleBoxFlat.new()
			fill_sb.bg_color = Tokens.VOLT
			fill_sb.corner_radius_top_left = 2
			fill_sb.corner_radius_top_right = 2
			fill_sb.corner_radius_bottom_left = 2
			fill_sb.corner_radius_bottom_right = 2
			fill_sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, Vector2(size.x * progress, size.y)))


# Sub-component: Pulsing Live Camera Dot
class LiveCamDot extends Control:
	var pulse_alpha: float = 1.0:
		set(v):
			pulse_alpha = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(8, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(4, 4), 4.0, Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, pulse_alpha))


# Hands-free lock: how long a person must be fully framed before the game starts,
# and the short beat after the bar fills. Keep these small so a ready player isn't kept waiting.
const LOCK_SECONDS := 0.5
const START_DELAY := 0.1
# Losing the frame drains the bar at the same speed it fills, so a single noisy
# detection frame doesn't wipe progress.
const LOCK_DRAIN_RATE := 1.0 / LOCK_SECONDS

# Active mode configuration
var _mode: Dictionary
var _stage: String = "close" # "close" | "missing" | "ready"
var _lock_progress: float = 0.0
var _simulated: bool = false
var _manual_override: bool = false
var _elapsed_time: float = 0.0
var _pulse_timer: float = 0.0
var _is_transitioning_to_game: bool = false
var _ui_visible: bool = true
var _last_pose_ms: int = -1

# Real pose landmarker instance (if present)
var landmarker_instance = null

# Node references
var _calib_ui_root: Control
var _bg_texture: GradientTexture2D
var _frame_guide: FrameGuide
var _skeleton_wrapper: Control
var _skeleton_figure: SkeletonFigure
var _cam_live_label: Label
var _cam_dot: LiveCamDot
var _framing_label: Label
var _big_text_label: Label
var _subline_label: Label
var _lock_bar: LockProgressBar

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_game_mode("dino")

func _ready() -> void:
	# Determine active mode
	var active_id = ""
	if GameManager.pending_game_name != "":
		active_id = GameManager.pending_game_name
	elif GameManager.selected_game_name != "":
		active_id = GameManager.selected_game_name
	else:
		active_id = "dino"

	# CRITICAL: selected_game_name MUST be empty during calibration so PoseLandmarker
	# starts in calibration camera mode instead of immediately launching the game!
	GameManager.pending_game_name = active_id
	GameManager.selected_game_name = ""
	set_game_mode(active_id)

	_build_ui()
	set_stage("close")

	# Real camera / pose initialization
	CalibrationManager.reset_calibration()
	if ResourceLoader.exists("res://vision/pose_landmarker/PoseLandmarker.tscn"):
		var pose_scene = load("res://vision/pose_landmarker/PoseLandmarker.tscn")
		landmarker_instance = pose_scene.instantiate()
		landmarker_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		landmarker_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		landmarker_instance.add_theme_constant_override("margin_left", 0)
		landmarker_instance.add_theme_constant_override("margin_top", 0)
		landmarker_instance.add_theme_constant_override("margin_right", 0)
		landmarker_instance.add_theme_constant_override("margin_bottom", 0)
		var vbc = landmarker_instance.get_node_or_null("VBoxContainer")
		if vbc:
			vbc.hide()
		add_child(landmarker_instance)
		# Send landmarker behind UI overlays
		move_child(landmarker_instance, 0)
		if ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
			ExerciseRecognizer.pose_processed.disconnect(_on_pose_processed)
		ExerciseRecognizer.pose_processed.connect(_on_pose_processed)

	# Check if user requested to skip calibration via settings
	if Settings.skip_calibration:
		call_deferred("_on_ready_complete")
		return

func _draw() -> void:
	if not _ui_visible:
		return

	# 1. Radial gradient ellipse background: #2A2D33 -> #0B0B0C at 70%
	if not _bg_texture:
		var grad := Gradient.new()
		grad.set_color(0, Color("#2A2D33"))
		grad.set_color(1, Color("#0B0B0C"))
		_bg_texture = GradientTexture2D.new()
		_bg_texture.gradient = grad
		_bg_texture.fill = GradientTexture2D.FILL_RADIAL
		_bg_texture.fill_from = Vector2(0.5, 0.3)
		_bg_texture.fill_to = Vector2(0.85, 0.85)
		_bg_texture.width = 128
		_bg_texture.height = 128

	draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, size), false)

	# 2. Diagonal stripes overlay at -45 deg, repeating every 12px, 2px wide, white@0.025
	var spacing := 12.0
	var col := Color(1, 1, 1, 0.025)
	var x := -size.y
	while x < size.x + size.y:
		draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), col, 2.0)
		x += spacing

func _process(delta: float) -> void:
	# Pulse live cam dot and track elapsed time
	_pulse_timer += delta
	_elapsed_time += delta
	if _cam_dot:
		_cam_dot.pulse_alpha = 0.4 + 0.6 * (0.5 + 0.5 * sin(_pulse_timer * 6.0))

	# Progression state machine (only if in simulated test mode)
	if _simulated and not _manual_override and not _is_transitioning_to_game:
		if _elapsed_time < 1.8:
			if _stage != "close":
				set_stage("close")
		elif _elapsed_time < 3.8:
			if _stage != "missing":
				set_stage("missing")
		else:
			if _stage != "ready":
				set_stage("ready")
			var lock_val = clampf((_elapsed_time - 3.8) / LOCK_SECONDS, 0.0, 1.0)
			set_lock_progress(lock_val)
			if lock_val >= 1.0 and not _is_transitioning_to_game:
				_is_transitioning_to_game = true
				var tween = create_tween()
				tween.tween_interval(START_DELAY)
				tween.tween_callback(_on_ready_complete)

func _unhandled_input(event: InputEvent) -> void:
	if not _ui_visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	if _is_transitioning_to_game:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			set_stage("ready")
			set_lock_progress(1.0)
			_is_transitioning_to_game = true
			var tween = create_tween()
			tween.tween_interval(0.2)
			tween.tween_callback(_on_ready_complete)

func _on_pose_processed(pose_landmarks) -> void:
	if _manual_override or not pose_landmarks or _is_transitioning_to_game or not _ui_visible:
		return

	# Real time since the previous pose result. Pose results arrive at the inference
	# rate (often well below the render rate), so the render frame's delta would make
	# the lock bar fill several times slower than LOCK_SECONDS.
	var now_ms := Time.get_ticks_msec()
	var dt := 0.0 if _last_pose_ms < 0 else clampf((now_ms - _last_pose_ms) / 1000.0, 0.0, 0.2)
	_last_pose_ms = now_ms

	var res = CalibrationManager.analyze_calibration_pose(pose_landmarks)

	# 1. If nobody is detected, or if person is too close:
	# Keep in stage "close" ("STEP BACK"). It will NEVER disappear when nobody is in frame!
	if not res.get("is_present", true) or res.message.find("Too close") != -1 or res.message.find("close") != -1:
		_lock_progress = maxf(0.0, _lock_progress - dt * LOCK_DRAIN_RATE)
		set_lock_progress(_lock_progress)
		if _stage != "close":
			set_stage("close")
		return

	# 2. Minimum dwell time on stage 1 ("close" / "STEP BACK")
	# Even if a person is in frame, give them at least 1.8 seconds to read "STEP BACK"
	# before moving to "missing" limbs, so stage 1 doesn't flash and vanish in 16ms!
	if _elapsed_time < 1.8 and not res.ready:
		if _stage != "close":
			set_stage("close")
		return

	# 3. Ready state (good framing)
	if res.ready:
		CalibrationManager.compute_and_save_thresholds(pose_landmarks)
		if _stage != "ready":
			set_stage("ready")
		_lock_progress = clampf(_lock_progress + dt / LOCK_SECONDS, 0.0, 1.0)
		set_lock_progress(_lock_progress)
		if _lock_progress >= 1.0 and not _is_transitioning_to_game:
			_is_transitioning_to_game = true
			var tween = create_tween()
			tween.tween_interval(START_DELAY)
			tween.tween_callback(_on_ready_complete)
	else:
		# Missing limbs stage
		_lock_progress = maxf(0.0, _lock_progress - dt * LOCK_DRAIN_RATE)
		set_lock_progress(_lock_progress)
		if _stage != "missing":
			set_stage("missing")
		_update_missing_text(res)

func _update_missing_text(res: Dictionary) -> void:
	if _stage != "missing":
		return
	var missing: Array = res.get("missing", [])
	var target_limb: String = str(_mode.get("limb", ""))

	if _mode["id"] == "dino":
		if missing.has("arms") and missing.has("legs"):
			target_limb = "ARMS & LEGS"
		elif missing.has("arms"):
			target_limb = "ARMS"
		elif missing.has("legs"):
			target_limb = "LEGS"
		else:
			target_limb = "ARMS & LEGS"
	elif _mode["id"] == "lane":
		target_limb = "KNEES"
	elif _mode["id"] == "flappy":
		target_limb = "ARMS"

	_set_headline_text("SHOW %s" % target_limb.to_upper(), Tokens.FLAME)
	if _subline_label:
		_subline_label.text = "%s needs your %s in frame" % [_mode["exercise"], target_limb.to_lower()]
	if _skeleton_figure:
		_skeleton_figure.missing_limb = target_limb

func _build_ui() -> void:
	if not _calib_ui_root or not is_instance_valid(_calib_ui_root):
		_calib_ui_root = Control.new()
		_calib_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_calib_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_calib_ui_root)
	else:
		for c in _calib_ui_root.get_children():
			c.queue_free()

	# -------------------------------------------------------------------------
	# 1. Frame Guide: Left 32, Right 32, Top 128, Bottom 260 from bottom
	# -------------------------------------------------------------------------
	_frame_guide = FrameGuide.new()
	_frame_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_guide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_guide.offset_left = 32
	_frame_guide.offset_right = -32
	_frame_guide.offset_top = 128
	_frame_guide.offset_bottom = -260
	_calib_ui_root.add_child(_frame_guide)

	# Skeleton Wrapper inside Frame Guide (width 326, height 456)
	_skeleton_wrapper = Control.new()
	_skeleton_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skeleton_wrapper.custom_minimum_size = Vector2(326, 456)
	_skeleton_wrapper.size = Vector2(326, 456)
	_skeleton_wrapper.pivot_offset = Vector2(163, 228)
	_frame_guide.add_child(_skeleton_wrapper)

	# Skeleton Figure centered inside wrapper
	_skeleton_figure = SkeletonClass.new()
	_skeleton_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skeleton_figure.mode = str(_mode.get("id", "dino"))
	_skeleton_figure.phase = 0.0
	_skeleton_figure.pose_color = Color.WHITE
	_skeleton_figure.custom_minimum_size = Vector2(280, 364)
	_skeleton_figure.size = Vector2(280, 364)
	_skeleton_figure.position = Vector2((326 - 280) / 2.0, (456 - 364) / 2.0)
	_skeleton_wrapper.add_child(_skeleton_figure)

	# -------------------------------------------------------------------------
	# 2. Bottom Panel: Framing label, Big text, Subline, Lock bar, Guide note
	# -------------------------------------------------------------------------
	var bot_margin := MarginContainer.new()
	bot_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot_margin.offset_top = -225
	bot_margin.offset_bottom = 0
	bot_margin.offset_left = 18
	bot_margin.offset_right = -18
	bot_margin.add_theme_constant_override("margin_bottom", 20)
	bot_margin.add_theme_constant_override("margin_left", 0)
	bot_margin.add_theme_constant_override("margin_right", 0)
	bot_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	bot_margin.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and not _is_transitioning_to_game:
			set_stage("ready")
			set_lock_progress(1.0)
			_is_transitioning_to_game = true
			var tween = create_tween()
			tween.tween_interval(0.2)
			tween.tween_callback(_on_ready_complete)
	)
	_calib_ui_root.add_child(bot_margin)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_vbox.add_theme_constant_override("separation", 0)
	bot_margin.add_child(bot_vbox)

	_framing_label = Label.new()
	_framing_label.text = "FRAMING 1/3"
	_framing_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_framing_label.add_theme_font_size_override("font_size", 11)
	_framing_label.add_theme_color_override("font_color", Tokens.SIGNAL)
	bot_vbox.add_child(_framing_label)

	bot_vbox.add_child(_make_spacer(2))

	_big_text_label = Label.new()
	_big_text_label.text = "STEP BACK"
	_big_text_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_big_text_label.add_theme_font_size_override("font_size", 52)
	_big_text_label.add_theme_constant_override("line_spacing", -6)
	_big_text_label.add_theme_color_override("font_color", Tokens.SIGNAL)
	bot_vbox.add_child(_big_text_label)

	bot_vbox.add_child(_make_spacer(4))

	_subline_label = Label.new()
	_subline_label.text = "Body cut off — move 2–3 m away"
	_subline_label.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
	_subline_label.add_theme_font_size_override("font_size", 15)
	_subline_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_subline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_vbox.add_child(_subline_label)

	bot_vbox.add_child(_make_spacer(14))

	_lock_bar = LockProgressBar.new()
	_lock_bar.progress = 0.0
	bot_vbox.add_child(_lock_bar)

	bot_vbox.add_child(_make_spacer(8))

	var guide_label := Label.new()
	guide_label.text = "HANDS-FREE · AUTO-STARTS ONCE YOU'RE FULLY IN FRAME"
	guide_label.add_theme_font_override("font", Tokens.FONT_MONO)
	guide_label.add_theme_font_size_override("font_size", 10)
	guide_label.add_theme_color_override("font_color", Tokens.DIM)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_vbox.add_child(guide_label)

	# -------------------------------------------------------------------------
	# 3. Top Bar: Back button on left, Pulse dot + "CAM LIVE · {GAME}" on right
	# Placed on top of all guides with z_index = 20 to ensure it always gets clicks
	# -------------------------------------------------------------------------
	var top_bar := MarginContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = Tokens.SAFE_TOP_OFFSET
	top_bar.offset_bottom = Tokens.SAFE_TOP_OFFSET + 48
	top_bar.offset_left = 20
	top_bar.offset_right = -20
	top_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	top_bar.z_index = 20
	_calib_ui_root.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	top_bar.add_child(top_hbox)

	var back_btn := IconButtonClass.new()
	back_btn.icon_type = "back"
	back_btn.is_back_button = true
	back_btn.custom_minimum_size = Vector2(44, 44)
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.pressed.connect(_on_back_pressed)
	top_hbox.add_child(back_btn)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hbox.add_child(top_spacer)

	var live_hbox := HBoxContainer.new()
	live_hbox.add_theme_constant_override("separation", 8)
	live_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	live_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hbox.add_child(live_hbox)

	_cam_dot = LiveCamDot.new()
	live_hbox.add_child(_cam_dot)

	_cam_live_label = Label.new()
	_cam_live_label.text = "CAM LIVE · %s" % str(_mode.get("game", "Dino Runner")).to_upper()
	_cam_live_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_cam_live_label.add_theme_font_size_override("font_size", 10)
	_cam_live_label.add_theme_color_override("font_color", Tokens.WHITE)
	live_hbox.add_child(_cam_live_label)

func set_game_mode(mode_id: String) -> void:
	var target_id = "dino"
	if mode_id == "lane" or mode_id == "switcher":
		target_id = "lane"
	elif mode_id == "flappy":
		target_id = "flappy"
	elif mode_id == "dino":
		target_id = "dino"

	for m in Tokens.MODES:
		if m["id"] == target_id:
			_mode = m.duplicate()
			break

	if _mode.is_empty():
		_mode = Tokens.MODES[0].duplicate()

	if _cam_live_label:
		_cam_live_label.text = "CAM LIVE · %s" % _mode["game"].to_upper()
	if _skeleton_figure:
		_skeleton_figure.mode = _mode["id"]

	# Refresh current stage texts for the newly set game mode
	set_stage(_stage)

func set_stage(stage_name: String) -> void:
	_stage = stage_name
	var stage_color: Color = Tokens.SIGNAL
	var framing_num: String = "1"
	var big_str: String = ""
	var sub_str: String = ""

	match _stage:
		"close":
			stage_color = Tokens.SIGNAL
			framing_num = "1"
			big_str = "STEP BACK"
			sub_str = "Body cut off — move 2–3 m away"

			if _skeleton_figure:
				_skeleton_figure.pose_color = Color.WHITE
				_skeleton_figure.missing_limb = ""
			if _skeleton_wrapper:
				_skeleton_wrapper.scale = Vector2(1.85, 1.85)
				_skeleton_wrapper.position = Vector2(0, 48)

		"missing":
			stage_color = Tokens.FLAME
			framing_num = "2"
			big_str = "SHOW %s" % str(_mode.get("limb", "ARMS & LEGS")).to_upper()
			sub_str = "%s needs your %s in frame" % [str(_mode.get("exercise", "Jumping Jacks")), str(_mode.get("limb", "arms & legs")).to_lower()]

			if _skeleton_figure:
				_skeleton_figure.pose_color = Color.WHITE
				_skeleton_figure.missing_limb = str(_mode.get("limb", "ARMS & LEGS"))
			if _skeleton_wrapper:
				_skeleton_wrapper.scale = Vector2(1.0, 1.0)
				_skeleton_wrapper.position = Vector2.ZERO

		"ready":
			stage_color = Tokens.VOLT
			framing_num = "3"
			big_str = "HOLD STILL"
			sub_str = "Locking in…"

			if _skeleton_figure:
				_skeleton_figure.pose_color = Tokens.VOLT
				_skeleton_figure.missing_limb = ""
			if _skeleton_wrapper:
				_skeleton_wrapper.scale = Vector2(1.0, 1.0)
				_skeleton_wrapper.position = Vector2.ZERO

	if _frame_guide:
		_frame_guide.stage_color = stage_color
	if _framing_label:
		_framing_label.text = "FRAMING %s/3" % framing_num
		_framing_label.add_theme_color_override("font_color", stage_color)
	_set_headline_text(big_str, stage_color)
	if _subline_label:
		_subline_label.text = sub_str

func _set_headline_text(big_text: String, stage_color: Color) -> void:
	if not _big_text_label:
		return
	_big_text_label.text = big_text
	_big_text_label.add_theme_color_override("font_color", stage_color)
	if big_text.length() > 12:
		_big_text_label.add_theme_font_size_override("font_size", 34)
	elif big_text.length() > 9:
		_big_text_label.add_theme_font_size_override("font_size", 42)
	else:
		_big_text_label.add_theme_font_size_override("font_size", 52)

func set_lock_progress(pct: float) -> void:
	_lock_progress = pct
	if _lock_bar:
		_lock_bar.progress = _lock_progress

func set_simulated(enabled: bool) -> void:
	_simulated = enabled

func set_manual_override(enabled: bool) -> void:
	_manual_override = enabled

func _make_spacer(height: int) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp

func _on_ready_complete() -> void:
	CalibrationManager.is_calibrated = true
	GameManager.selected_game_name = _mode["id"]

	if ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.disconnect(_on_pose_processed)

	_ui_visible = false
	if _calib_ui_root and is_instance_valid(_calib_ui_root):
		_calib_ui_root.hide()
	queue_redraw()

	if landmarker_instance and landmarker_instance.has_method("_start_exercise_and_game"):
		landmarker_instance._start_exercise_and_game()
	elif ResourceLoader.exists("res://ui/HUD.tscn"):
		get_tree().change_scene_to_file("res://ui/HUD.tscn")
	else:
		get_tree().change_scene_to_file("res://Main.tscn")

func _on_back_pressed() -> void:
	_is_transitioning_to_game = true
	if ExerciseRecognizer.pose_processed.is_connected(_on_pose_processed):
		ExerciseRecognizer.pose_processed.disconnect(_on_pose_processed)
	if landmarker_instance and is_instance_valid(landmarker_instance):
		if landmarker_instance.has_method("_reset"):
			landmarker_instance._reset()
		landmarker_instance.queue_free()
		landmarker_instance = null
	GameManager.selected_game_name = ""
	GameManager.pending_game_name = ""
	get_tree().change_scene_to_file("res://Main.tscn")
