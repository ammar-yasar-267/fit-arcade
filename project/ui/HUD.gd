class_name GameHUD
extends CanvasLayer

## In-Game HUD & Overlay for FitArcade.
## Visual source of truth: references/05-game-running.png and references/06-paused.png.
## Spec from design-spec.md Section D3 and Play.tsx.

signal workout_completed(result: Dictionary)

const SESSION_DURATION := 32.0

# Ink + diagonal stripes, shared with the onboarding and delete-account overlays
const StripedBackdropClass = preload("res://ui/components/StripedBackdrop.gd")

# Sub-component: 6px Session Progress Bar
class SessionProgressBar extends Control:
	var progress: float = 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()
	var bar_color: Color = Tokens.VOLT:
		set(v):
			bar_color = v
			queue_redraw()
	## Track opacity: 0.1 normally, stronger in high-contrast mode so it reads in glare
	var track_alpha: float = 0.1:
		set(v):
			track_alpha = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var track_rect := Rect2(Vector2.ZERO, size)
		draw_rect(track_rect, Color(1, 1, 1, track_alpha), true)
		if progress > 0.001:
			var fill_rect := Rect2(Vector2.ZERO, Vector2(size.x * progress, size.y))
			draw_rect(fill_rect, bar_color, true)


# Sub-component: Top HUD Gradient Background
class TopGradientBg extends TextureRect:
	## `solid`: stay fully opaque behind the stats before fading (high-contrast mode),
	## instead of the normal dense-but-translucent fade.
	func _init(solid: bool = false) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_SCALE

		# Gradient.new() already holds a black->white pair; setting the arrays replaces
		# it outright (adding points on top left an opaque white stop at the bottom).
		var grad := Gradient.new()
		# Stays dense through the score row (y~175 of 230), then fades out.
		grad.offsets = PackedFloat32Array([0.0, 0.8 if solid else 0.65, 1.0])
		grad.colors = PackedColorArray([
			Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 1.0),
			Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 1.0 if solid else 0.85),
			Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.0),
		])

		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		tex.width = 16
		tex.height = 230
		texture = tex


# Sub-component: content wrapper framed by 4 corner brackets + faint tint,
# the same motif as the calibration frame guide.
class BracketFrame extends MarginContainer:
	var frame_color: Color = Tokens.VOLT

	func _init(color: Color = Tokens.VOLT) -> void:
		frame_color = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("margin_left", 30)
		add_theme_constant_override("margin_right", 30)
		add_theme_constant_override("margin_top", 26)
		add_theme_constant_override("margin_bottom", 26)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var arm := 22.0
		var t := 4.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(frame_color.r, frame_color.g, frame_color.b, 0.05), true)
		# Top-left, top-right, bottom-right, bottom-left
		draw_rect(Rect2(0, 0, arm, t), frame_color, true)
		draw_rect(Rect2(0, 0, t, arm), frame_color, true)
		draw_rect(Rect2(w - arm, 0, arm, t), frame_color, true)
		draw_rect(Rect2(w - t, 0, t, arm), frame_color, true)
		draw_rect(Rect2(w - arm, h - t, arm, t), frame_color, true)
		draw_rect(Rect2(w - t, h - arm, t, arm), frame_color, true)
		draw_rect(Rect2(0, h - t, arm, t), frame_color, true)
		draw_rect(Rect2(0, h - arm, t, arm), frame_color, true)


# Sub-component: Rep Flash Overlay (transient screen border & floating badge)
class RepFlashOverlay extends Control:
	var flash_color: Color = Tokens.VOLT
	var badge_text: String = "+1 REP"
	var text_color: Color = Tokens.INK
	var is_active: bool = false
	# Tweened properties: redraw on every change or the fade/pop never animates.
	var flash_alpha: float = 0.0:
		set(v):
			flash_alpha = v
			queue_redraw()
	var badge_scale: float = 1.0:
		set(v):
			badge_scale = v
			queue_redraw()
	var _tween: Tween

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func trigger(good: bool, msg: String = "") -> void:
		# Rapid reps must not leave an older tween fighting the new flash.
		if _tween and _tween.is_valid():
			_tween.kill()
		is_active = true
		if good:
			flash_color = Tokens.VOLT
			badge_text = "+1 REP"
			text_color = Tokens.INK
		else:
			flash_color = Tokens.SIGNAL
			badge_text = msg if msg != "" else "GO DEEPER"
			text_color = Tokens.WHITE

		flash_alpha = 1.0
		badge_scale = 1.25
		queue_redraw()

		var tw := create_tween().set_parallel(true)
		_tween = tw
		tw.tween_property(self, "flash_alpha", 0.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(self, "badge_scale", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.chain().tween_callback(func():
			is_active = false
			queue_redraw()
		)

	func _draw() -> void:
		if not is_active or flash_alpha <= 0.001:
			return

		# 10px inner border flash
		var b_col := Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha * 0.9)
		draw_rect(Rect2(Vector2.ZERO, size), b_col, false, 10.0)

		# Floating centered badge at 44% height
		var center_y := size.y * 0.44
		var font: Font = Tokens.FONT_DISPLAY
		var font_sz := 48
		var str_sz := font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz)
		var pad_h := 24.0
		var pad_v := 8.0
		var badge_w := (str_sz.x + pad_h * 2.0) * badge_scale
		var badge_h := (str_sz.y + pad_v * 2.0) * badge_scale
		var badge_rect := Rect2((size.x - badge_w) * 0.5, center_y - badge_h * 0.5, badge_w, badge_h)

		var fill_col := Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha)
		draw_rect(badge_rect, fill_col, true)

		var text_pos := Vector2(badge_rect.position.x + (badge_w - str_sz.x * badge_scale) * 0.5, badge_rect.position.y + badge_h * 0.75)
		draw_string(font, text_pos, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_sz * badge_scale), Color(text_color.r, text_color.g, text_color.b, flash_alpha))


# Sub-component: PIP Camera Card (96x144, 2px border, IN FRAME tag)
class PipCameraCard extends PanelContainer:
	var pip_preview: TextureRect

	func _init(high_contrast: bool = false) -> void:
		custom_minimum_size = Vector2(96, 144)
		size = Vector2(96, 144)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111111")
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 1.0, 1.0, 1.0 if high_contrast else 0.8)
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 2
		add_theme_stylebox_override("panel", style)

		# Video TextureRect
		pip_preview = TextureRect.new()
		pip_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		pip_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pip_preview.texture = ImageTexture.new()
		pip_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pip_preview)

		# Top-left "● IN FRAME" tag. A PanelContainer stretches every child to its full
		# rect (and an HBox stretches children vertically), which turned the 6x6 dot
		# into a full-height green bar across the feed. So the tag lives in a plain
		# overlay Control, positioned at its own minimum size, with a dark pill behind
		# it so it stays readable over any camera image.
		var overlay := Control.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)

		var tag_pill := PanelContainer.new()
		tag_pill.position = Vector2(4, 4)
		tag_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pill_sb := StyleBoxFlat.new()
		pill_sb.bg_color = Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.95 if high_contrast else 0.65)
		pill_sb.corner_radius_top_left = 2
		pill_sb.corner_radius_top_right = 2
		pill_sb.corner_radius_bottom_left = 2
		pill_sb.corner_radius_bottom_right = 2
		pill_sb.content_margin_left = 5
		pill_sb.content_margin_right = 5
		pill_sb.content_margin_top = 2
		pill_sb.content_margin_bottom = 2
		tag_pill.add_theme_stylebox_override("panel", pill_sb)
		overlay.add_child(tag_pill)

		var tag_hbox := HBoxContainer.new()
		tag_hbox.add_theme_constant_override("separation", 5)
		tag_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_pill.add_child(tag_hbox)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(6, 6)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Tokens.VOLT
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_hbox.add_child(dot)

		var tag_lbl := Label.new()
		tag_lbl.text = "IN FRAME"
		tag_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
		tag_lbl.add_theme_font_size_override("font_size", 10 if high_contrast else 9)
		tag_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_hbox.add_child(tag_lbl)

	func get_pip_preview() -> TextureRect:
		return pip_preview


# Active Mode Config
var _mode_id: String = "dino"
var _mode_color: Color = Tokens.VOLT
var _exercise_name: String = "JUMPING JACKS"
var _exercise_singular: String = "JUMPING JACK"

# Game & State
var current_score: int = 0
var current_reps: int = 0
var elapsed_time: float = 0.0
var is_timing: bool = false
var has_started_first_rep: bool = false
var is_paused: bool = false
var is_finishing: bool = false

# UI Nodes
var _root_ctrl: Control
var _top_bar: MarginContainer
var _rep_label: Label
var _time_label: Label
var _score_label: Label
var _progress_bar: SessionProgressBar
var _primed_overlay: Control
var _primed_action_bob: Control
var _primed_dot: ColorRect
var _pause_hint: Label
var _paused_overlay: Control
var _paused_subline: Label
var _rep_flash: RepFlashOverlay
var _pip_card: PipCameraCard
var _cue_container: Control
var _debug_overlay: PanelContainer
var _debug_label: Label

var _bob_timer: float = 0.0
var _debug_timer: float = 0.0
const DEBUG_REFRESH_SECONDS := 0.25

## Settings > "High contrast HUD". Read once per UI build: the setting is changed on
## another screen, so it can't change while a workout is running.
var _high_contrast: bool = false

## Dark outline for HUD text, heavier and fully opaque in high-contrast mode.
func _legible(lbl: Label, outline_px: int, outline_alpha: float = 0.9) -> Label:
	if _high_contrast:
		return Tokens.make_legible(lbl, outline_px + 3, 1.0)
	return Tokens.make_legible(lbl, outline_px, outline_alpha)

func _caption_size() -> int:
	return 12 if _high_contrast else 11

func _init() -> void:
	layer = 5

func _ready() -> void:
	# Determine game mode from GameManager
	_mode_id = GameManager.selected_game_name
	if _mode_id == "":
		_mode_id = GameManager.pending_game_name
	if _mode_id == "":
		_mode_id = "dino"

	match _mode_id:
		"dino":
			_mode_color = Tokens.VOLT
			_exercise_name = "JUMPING JACKS"
			_exercise_singular = "JUMPING JACK"
		"lane", "switcher":
			_mode_id = "lane"
			_mode_color = Tokens.CYAN
			_exercise_name = "SIDE LUNGES"
			_exercise_singular = "SIDE LUNGE"
		"flappy":
			_mode_color = Tokens.FLAME
			_exercise_name = "ARM RAISES"
			_exercise_singular = "ARM RAISE"

	_build_ui()

	if not ExerciseRecognizer.rep_completed.is_connected(_on_rep):
		ExerciseRecognizer.rep_completed.connect(_on_rep)
	if not ExerciseRecognizer.form_feedback.is_connected(_on_form_feedback):
		ExerciseRecognizer.form_feedback.connect(_on_form_feedback)

	var active_game = GameManager.get_active_game()
	if active_game:
		bind_game(active_game)

	_update_labels()

func bind_game(game: GameBase) -> void:
	if game == null:
		return
	if not game.game_over.is_connected(_on_game_over):
		game.game_over.connect(_on_game_over)
	if not game.score_changed.is_connected(update_score):
		game.score_changed.connect(update_score)

func _exit_tree() -> void:
	if ExerciseRecognizer.rep_completed.is_connected(_on_rep):
		ExerciseRecognizer.rep_completed.disconnect(_on_rep)
	if ExerciseRecognizer.form_feedback.is_connected(_on_form_feedback):
		ExerciseRecognizer.form_feedback.disconnect(_on_form_feedback)
	var active_game = GameManager.get_active_game()
	if active_game:
		if active_game.game_over.is_connected(_on_game_over):
			active_game.game_over.disconnect(_on_game_over)
		if active_game.score_changed.is_connected(update_score):
			active_game.score_changed.disconnect(update_score)

func _process(delta: float) -> void:
	if is_paused or is_finishing:
		return

	# Primed overlay: bob the action tag and pulse the READY dot
	if _primed_action_bob and _primed_overlay and _primed_overlay.visible:
		_bob_timer += delta * 4.0
		var bob := 4.0 * sin(_bob_timer)
		_primed_action_bob.offset_top = bob
		_primed_action_bob.offset_bottom = bob
		if _primed_dot:
			_primed_dot.modulate.a = 0.4 + 0.6 * (0.5 + 0.5 * sin(_bob_timer * 1.5))

	# Timing loop
	if is_timing:
		elapsed_time += delta
		_time_label.text = _format_time(elapsed_time)
		if _progress_bar:
			_progress_bar.progress = elapsed_time / SESSION_DURATION

		# Workout completes after 32 seconds
		if elapsed_time >= SESSION_DURATION:
			_complete_workout()

	# Diagnostics: refreshed 4x a second, since per-frame text is unreadable
	if _debug_label and Settings.show_debug_info:
		_debug_timer += delta
		if _debug_timer >= DEBUG_REFRESH_SECONDS:
			_debug_timer = 0.0
			_update_debug_overlay()

func _update_debug_overlay() -> void:
	var accel := "GPU" if Settings.use_hardware_accel() else "CPU"
	_debug_label.text = PerfStats.format_overlay(PerfStats.snapshot(), PerfStats.memory_info(), Engine.get_frames_per_second(), accel)

func _unhandled_input(event: InputEvent) -> void:
	if is_finishing:
		return

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return

	# Tap anywhere on screen to pause
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if has_started_first_rep and not is_paused:
			toggle_pause()
			get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if is_finishing:
		return
	set_paused(not is_paused)

func set_paused(paused: bool) -> void:
	is_paused = paused
	var active_game = GameManager.get_active_game()
	if active_game:
		active_game.is_running = not is_paused

	if _paused_overlay:
		_paused_overlay.visible = is_paused
		if is_paused:
			_paused_subline.text = "TIMERS FROZEN · %d REPS · %s" % [current_reps, _format_time(elapsed_time)]

	if _pip_card:
		_pip_card.visible = not is_paused

	if _pause_hint:
		_pause_hint.visible = has_started_first_rep and not is_paused

func update_score(score: int) -> void:
	current_score = score
	if _score_label:
		_score_label.text = _format_number(current_score)

func _on_rep(_rep_count: int = 0) -> void:
	current_reps = SessionManager.current_reps
	_update_labels()

	# First rep starts the workout session and timer!
	if not has_started_first_rep:
		has_started_first_rep = true
		is_timing = true
		if _primed_overlay:
			var tw := create_tween()
			tw.tween_property(_primed_overlay, "modulate:a", 0.0, 0.25)
			tw.tween_callback(func(): _primed_overlay.visible = false)
		if _pause_hint:
			_pause_hint.visible = true

	# Trigger visual rep flash
	if _rep_flash:
		_rep_flash.trigger(true, "+1 REP")

func _on_form_feedback(message: String, is_good: bool) -> void:
	if not is_good and _rep_flash and has_started_first_rep:
		_rep_flash.trigger(false, message)

func _on_game_over(final_score: int, _reps: int = 0) -> void:
	if is_finishing:
		return
	current_score = final_score
	_complete_workout()

func _complete_workout() -> void:
	if is_finishing:
		return
	is_finishing = true
	is_timing = false

	var active_game = GameManager.get_active_game()
	if active_game:
		active_game.is_running = false

	# Cleanly stop camera feed before changing scenes to prevent deadlock with C++ camera thread
	_stop_active_camera()

	var best := SessionManager.get_best_score(_mode_id)
	var is_pb: bool = current_score > best

	# Persist workout
	SessionManager.record_workout(_mode_id, current_score, current_reps)
	var backend_mode: String = "switcher" if _mode_id in ["lane", "switcher"] else _mode_id
	Backend.submit_score(backend_mode, current_score, current_reps)

	# Store result bundle for SummaryScreen
	SessionManager.last_workout_result = {
		"game_mode": _mode_id,
		"score": current_score,
		"reps": current_reps,
		"active_time": elapsed_time,
		# Median whole-pipeline latency for the session; 0 (shown as "—") if too few frames
		# were processed to trust a figure
		"latency_ms": PerfStats.session_latency_ms(),
		"is_pb": is_pb,
		"previous_best": best
	}

	# Clean transition to SummaryScreen
	get_tree().change_scene_to_file("res://ui/SummaryScreen.tscn")

func _stop_active_camera() -> void:
	# Recursively search the scene tree for any node with _reset() to stop the camera thread cleanly
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node != null and is_instance_valid(node):
			if node.has_method("_reset") and node != self:
				node._reset()
			for child in node.get_children():
				stack.push_back(child)

func _update_labels() -> void:
	if _rep_label:
		_rep_label.text = str(current_reps)
	if _time_label:
		_time_label.text = _format_time(elapsed_time)
	if _score_label:
		_score_label.text = _format_number(current_score)

func _format_time(s: float) -> String:
	var total_sec := int(s)
	return "%d:%02d" % [total_sec / 60, total_sec % 60]

func _format_number(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out

# -----------------------------------------------------------------------------
# UI Construction
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	_high_contrast = Settings.high_contrast_hud
	# PoseLandmarker reparents the HUD out of the game's SubViewport, which runs
	# _ready (and so this) a second time. Drop the first pass or both copies of
	# the UI stay on screen: the stale primed overlay never hides after a rep.
	if _root_ctrl:
		remove_child(_root_ctrl)
		_root_ctrl.queue_free()
		_root_ctrl = null

	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root_ctrl)

	# 1. Top HUD Bar (Gradient fade + Reps on Left + Time/Score on Right + 6px Bar)
	_build_top_hud()

	# 2. Pause Hint ("TAP ANYWHERE TO PAUSE")
	_pause_hint = Label.new()
	_pause_hint.text = "TAP ANYWHERE TO PAUSE"
	_pause_hint.add_theme_font_override("font", Tokens.FONT_MONO)
	_pause_hint.add_theme_font_size_override("font_size", 12 if _high_contrast else 11)
	_pause_hint.add_theme_color_override("font_color", Color(1, 1, 1, 1.0 if _high_contrast else 0.8))
	_legible(_pause_hint, 3)
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pause_hint.offset_top = 34
	_pause_hint.offset_bottom = 50
	_pause_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_hint.visible = false
	_root_ctrl.add_child(_pause_hint)

	# 3. Game-specific bottom cues (Lane Switcher & Flappy)
	_build_game_cues()

	# 4. PIP Camera Card (96x144 at bottom-right per spec D3)
	_build_pip_card()

	# 5. Primed Overlay ("READY · STEP BACK", "FIRST REP STARTS IT", "DO 1...")
	_build_primed_overlay()

	# 6. Rep Flash Overlay
	_rep_flash = RepFlashOverlay.new()
	_root_ctrl.add_child(_rep_flash)

	# 7. Paused Overlay
	_build_paused_overlay()

	# 8. Diagnostics Pill (if enabled)
	_build_debug_overlay()

func _build_pip_card() -> void:
	_pip_card = PipCameraCard.new(_high_contrast)
	_pip_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pip_card.offset_right = -12
	_pip_card.offset_bottom = -12
	_pip_card.offset_left = -108
	_pip_card.offset_top = -156
	_root_ctrl.add_child(_pip_card)

func get_pip_preview() -> TextureRect:
	if _pip_card:
		return _pip_card.get_pip_preview()
	return null

func _build_top_hud() -> void:
	# Layout (y): label 56 | REPS digits 72-153 | TIME digits 72-114, SCORE digits 142-174
	# | progress bar 182-188. The gradient reaches past the bar so it stays legible.
	const TOP := 56.0
	const BAR_GAP := 8.0

	var grad_bg := TopGradientBg.new(_high_contrast)
	grad_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	grad_bg.offset_bottom = 230
	_root_ctrl.add_child(grad_bg)

	_top_bar = MarginContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_top = TOP
	_top_bar.offset_left = Tokens.SCREEN_PADDING_LEFT
	_top_bar.offset_right = -Tokens.SCREEN_PADDING_RIGHT
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_ctrl.add_child(_top_bar)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(hbox)

	# Left: REPS (mono 10 label + giant display 92 value)
	var reps_vbox := VBoxContainer.new()
	reps_vbox.add_theme_constant_override("separation", 2)
	reps_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(reps_vbox)

	reps_vbox.add_child(_make_stat_caption("REPS", HORIZONTAL_ALIGNMENT_LEFT))
	_rep_label = Tokens.tight_display_label("0", 92, _mode_color, HORIZONTAL_ALIGNMENT_LEFT, 150.0)
	_legible(_rep_label, 6, 0.75)
	reps_vbox.add_child(_rep_label.get_parent())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# Right: TIME & SCORE, each caption stacked above its value, right-aligned
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 2)
	right_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_vbox)

	right_vbox.add_child(_make_stat_caption("TIME", HORIZONTAL_ALIGNMENT_RIGHT))
	_time_label = Tokens.tight_display_label("0:00", 48, Tokens.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	_legible(_time_label, 5, 0.75)
	right_vbox.add_child(_time_label.get_parent())

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_vbox.add_child(gap)

	right_vbox.add_child(_make_stat_caption("SCORE", HORIZONTAL_ALIGNMENT_RIGHT))
	_score_label = Tokens.tight_display_label("0", 36, Tokens.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	_legible(_score_label, 4, 0.75)
	right_vbox.add_child(_score_label.get_parent())

	# The right column is the taller one: 2 captions + 2 values + gaps.
	var caption_h := ceilf(Tokens.FONT_MONO.get_height(_caption_size()))
	var column_h := (caption_h + 2 + ceilf(48 * Tokens.DISPLAY_CAP_HEIGHT)) + 10 + (caption_h + 2 + ceilf(36 * Tokens.DISPLAY_CAP_HEIGHT))
	_top_bar.offset_bottom = TOP + column_h

	# 6px Session progress bar (below the stats)
	_progress_bar = SessionProgressBar.new()
	_progress_bar.bar_color = _mode_color
	_progress_bar.track_alpha = 0.3 if _high_contrast else 0.1
	_progress_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progress_bar.offset_top = _top_bar.offset_bottom + BAR_GAP
	_progress_bar.offset_bottom = _progress_bar.offset_top + 6
	_progress_bar.offset_left = Tokens.SCREEN_PADDING_LEFT
	_progress_bar.offset_right = -Tokens.SCREEN_PADDING_RIGHT
	_root_ctrl.add_child(_progress_bar)

func _make_stat_caption(text: String, align: HorizontalAlignment) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	lbl.add_theme_font_size_override("font_size", _caption_size())
	# Lighter than DIM (#8A8A92) so it holds up over bright game backgrounds; pure white
	# in high-contrast mode
	var caption_color := Tokens.WHITE if _high_contrast else Color(Tokens.TEXT.r, Tokens.TEXT.g, Tokens.TEXT.b, 0.78)
	lbl.add_theme_color_override("font_color", caption_color)
	lbl.horizontal_alignment = align
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _legible(lbl, 3)

func _build_primed_overlay() -> void:
	_primed_overlay = Control.new()
	_primed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_primed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_ctrl.add_child(_primed_overlay)

	# Ink backdrop with the app's stripe texture (same family as calibrate/paused);
	# dark enough for contrast over any game background, but input passes through.
	var backdrop := StripedBackdropClass.new(0.82, false)
	_primed_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_primed_overlay.add_child(center)

	# No card: the content sits directly on the backdrop inside corner brackets,
	# echoing the calibration frame guide.
	var frame := BracketFrame.new(_mode_color)
	center.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(vbox)

	# "● READY · STEP BACK": mode-colored pulsing dot + dim mono caption
	var ready_row := HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_row.add_theme_constant_override("separation", 8)
	ready_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ready_row)

	var dot_holder := CenterContainer.new()
	dot_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_row.add_child(dot_holder)
	_primed_dot = ColorRect.new()
	_primed_dot.custom_minimum_size = Vector2(7, 7)
	_primed_dot.color = _mode_color
	_primed_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_holder.add_child(_primed_dot)

	var ready_lbl := Label.new()
	ready_lbl.text = "READY  ·  STEP BACK"
	ready_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	ready_lbl.add_theme_font_size_override("font_size", 12)
	ready_lbl.add_theme_color_override("font_color", Tokens.DIM)
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_row.add_child(ready_lbl)

	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 12)
	sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sp1)

	# Two display lines, trimmed to their ink height so they stack tightly (spec lh 0.9)
	var line1 := Tokens.tight_display_label("FIRST REP", 64, Tokens.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	vbox.add_child(line1.get_parent())

	var line_gap := Control.new()
	line_gap.custom_minimum_size = Vector2(0, 4)
	line_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(line_gap)

	var line2 := Tokens.tight_display_label("STARTS IT", 64, _mode_color, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	vbox.add_child(line2.get_parent())

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 22)
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sp2)

	# "DO 1 JUMPING JACK" as a solid mode-colored tag (like the rep-flash badge).
	# It bobs, so it sits in a fixed-height holder whose anchored child is nudged via
	# offsets; a container child's position would be reset on every layout pass.
	var action_holder := Control.new()
	action_holder.custom_minimum_size = Vector2(0, 40)
	action_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(action_holder)

	_primed_action_bob = CenterContainer.new()
	_primed_action_bob.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_primed_action_bob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_holder.add_child(_primed_action_bob)

	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = _mode_color
	tag_sb.corner_radius_top_left = 2
	tag_sb.corner_radius_top_right = 2
	tag_sb.corner_radius_bottom_left = 2
	tag_sb.corner_radius_bottom_right = 2
	tag_sb.content_margin_left = 18
	tag_sb.content_margin_right = 18
	tag_sb.content_margin_top = 6
	tag_sb.content_margin_bottom = 6
	tag.add_theme_stylebox_override("panel", tag_sb)
	_primed_action_bob.add_child(tag)

	var tag_lbl := Label.new()
	tag_lbl.text = "DO 1 %s" % _exercise_singular
	tag_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
	tag_lbl.add_theme_font_size_override("font_size", 18)
	tag_lbl.add_theme_color_override("font_color", Tokens.INK)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(tag_lbl)

func _build_paused_overlay() -> void:
	_paused_overlay = Control.new()
	_paused_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paused_overlay.z_index = 50
	_paused_overlay.visible = false
	_root_ctrl.add_child(_paused_overlay)

	var bg := StripedBackdropClass.new(0.92, true)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paused_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paused_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Tokens.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_paused_subline = Label.new()
	_paused_subline.text = "TIMERS FROZEN · 0 REPS · 0:00"
	_paused_subline.add_theme_font_override("font", Tokens.FONT_MONO)
	_paused_subline.add_theme_font_size_override("font_size", 12)
	_paused_subline.add_theme_color_override("font_color", Tokens.DIM)
	_paused_subline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_paused_subline)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(sp)

	# RESUME Button (volt fill, ink text, display 24)
	var resume_btn := Button.new()
	resume_btn.text = "RESUME"
	resume_btn.custom_minimum_size = Vector2(224, 54)
	resume_btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	resume_btn.add_theme_font_size_override("font_size", 24)
	resume_btn.add_theme_color_override("font_color", Tokens.INK)
	resume_btn.add_theme_color_override("font_hover_color", Tokens.INK)
	resume_btn.add_theme_color_override("font_pressed_color", Tokens.INK)

	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Tokens.VOLT
	r_style.corner_radius_top_left = 2
	r_style.corner_radius_top_right = 2
	r_style.corner_radius_bottom_left = 2
	r_style.corner_radius_bottom_right = 2
	resume_btn.add_theme_stylebox_override("normal", r_style)
	resume_btn.add_theme_stylebox_override("hover", r_style)
	resume_btn.add_theme_stylebox_override("pressed", r_style)
	resume_btn.pressed.connect(func(): set_paused(false))
	vbox.add_child(resume_btn)

	# END WORKOUT Button (1px white@0.4 border, display 20)
	var end_btn := Button.new()
	end_btn.text = "END WORKOUT"
	end_btn.custom_minimum_size = Vector2(224, 48)
	end_btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	end_btn.add_theme_font_size_override("font_size", 20)
	end_btn.add_theme_color_override("font_color", Tokens.WHITE)
	end_btn.add_theme_color_override("font_hover_color", Tokens.WHITE)
	end_btn.add_theme_color_override("font_pressed_color", Tokens.WHITE)

	var e_style := StyleBoxFlat.new()
	e_style.bg_color = Color(0, 0, 0, 0)
	e_style.border_width_left = 1
	e_style.border_width_right = 1
	e_style.border_width_top = 1
	e_style.border_width_bottom = 1
	e_style.border_color = Color(1, 1, 1, 0.4)
	e_style.corner_radius_top_left = 2
	e_style.corner_radius_top_right = 2
	e_style.corner_radius_bottom_left = 2
	e_style.corner_radius_bottom_right = 2
	end_btn.add_theme_stylebox_override("normal", e_style)

	var e_hover := e_style.duplicate() as StyleBoxFlat
	e_hover.bg_color = Color(1, 1, 1, 0.08)
	end_btn.add_theme_stylebox_override("hover", e_hover)
	end_btn.add_theme_stylebox_override("pressed", e_hover)

	end_btn.pressed.connect(func():
		set_paused(false)
		_complete_workout()
	)
	vbox.add_child(end_btn)

func _build_game_cues() -> void:
	if _mode_id == "lane":
		# Lane Switcher: "◀ LUNGE L" and "LUNGE R ▶" (anchored bottom 14, left 16, right 120)
		var lane_box := HBoxContainer.new()
		lane_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		lane_box.offset_bottom = -12
		lane_box.offset_top = -40
		lane_box.offset_left = 16
		lane_box.offset_right = -120
		lane_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root_ctrl.add_child(lane_box)

		# Near-opaque cyan + dark outline: the old 0.6 alpha vanished into the lane art
		var l_lbl := Label.new()
		l_lbl.text = "◀ LUNGE L"
		l_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		l_lbl.add_theme_font_size_override("font_size", 18)
		l_lbl.add_theme_color_override("font_color", Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 1.0 if _high_contrast else 0.95))
		_legible(l_lbl, 4)
		lane_box.add_child(l_lbl)

		var lane_sp := Control.new()
		lane_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane_box.add_child(lane_sp)

		var r_lbl := Label.new()
		r_lbl.text = "LUNGE R ▶"
		r_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		r_lbl.add_theme_font_size_override("font_size", 18)
		r_lbl.add_theme_color_override("font_color", Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 1.0 if _high_contrast else 0.95))
		_legible(r_lbl, 4)
		lane_box.add_child(r_lbl)

	elif _mode_id == "flappy":
		# Flappy Flight: "▲ RAISE ARMS TO RISE" (bottom 40, left 16). offset_top has to be
		# set too: with a bottom anchor and offset_top left at 0, the label's top edge sat
		# at the screen's bottom edge and the whole hint rendered off-screen.
		var flappy_lbl := Label.new()
		flappy_lbl.text = "▲ RAISE ARMS TO RISE"
		flappy_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		flappy_lbl.add_theme_font_size_override("font_size", 18)
		flappy_lbl.add_theme_color_override("font_color", Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 1.0 if _high_contrast else 0.95))
		_legible(flappy_lbl, 4)
		flappy_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		flappy_lbl.offset_left = 16
		flappy_lbl.offset_bottom = -40
		flappy_lbl.offset_top = -40 - ceilf(Tokens.FONT_DISPLAY.get_height(18))
		flappy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root_ctrl.add_child(flappy_lbl)

func _build_debug_overlay() -> void:
	if not Settings.show_debug_info:
		return
	_debug_overlay = PanelContainer.new()
	_debug_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_overlay.offset_left = 20
	_debug_overlay.offset_top = 204
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Tokens.LINE
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_debug_overlay.add_theme_stylebox_override("panel", style)
	_root_ctrl.add_child(_debug_overlay)

	_debug_label = Label.new()
	_debug_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_debug_label.add_theme_font_size_override("font_size", 10)
	_debug_label.add_theme_color_override("font_color", Tokens.VOLT)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_overlay.add_child(_debug_label)
	# Diagnostics must not swallow the tap-to-pause taps that land on them
	_debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_debug_overlay()
