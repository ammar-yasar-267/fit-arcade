@tool
class_name GameRow
extends VBoxContainer

## Accordion game row component for Hub screen.
## Spec from Figma C7: Header with color bar, exercise name, stats, and expandable preview + start button.

const MovePreviewClass = preload("res://ui/components/MovePreview.gd")
const SkeletonBarClass = preload("res://ui/components/SkeletonBar.gd")

signal row_selected(mode_id: String)
signal start_pressed(mode_id: String)

@export var mode_id: String = "dino"
@export var exercise_name: String = "JUMPING JACKS"
@export var game_name: String = "DINO RUNNER"
@export var action_text: String = "Jack = Jump"
@export var mode_color: Color = Color("#D4FF3A")
@export var is_locked: bool = false:
	set(v):
		is_locked = v
		if _stats_container:
			_stats_container.visible = not is_locked
		if _move_preview:
			_move_preview.is_locked = is_locked
		_setup_start_btn_styles()
		_update_active_state(false)

@export var is_active: bool = false:
	set(v):
		if is_active == v:
			return
		is_active = v
		_update_active_state()

@export var rank_text: String = "—":
	set(v):
		rank_text = v
		if _rank_val_label:
			_rank_val_label.text = v
@export var best_score_text: String = "—":
	set(v):
		best_score_text = v
		if _best_val_label:
			_best_val_label.text = v

## RANK and BEST come from the cloud leaderboard. While a value is loading it shows
## a pulsing placeholder (same footprint as the number) instead of a stale "—".
@export var rank_loading: bool = false:
	set(v):
		rank_loading = v
		_apply_stat_loading()
@export var best_loading: bool = false:
	set(v):
		best_loading = v
		_apply_stat_loading()
@export var phase: float = 0.0:
	set(v):
		phase = v
		if _move_preview and is_active and not is_locked:
			_move_preview.phase = v

# Node references
var _header_btn: Button
var _color_bar: ColorRect
var _exercise_label: Label
var _subline_label: Label
var _stats_container: HBoxContainer
var _rank_val_label: Label
var _best_val_label: Label
var _rank_skeleton: Control
var _best_skeleton: Control

var _body_clip: Control
var _body_margin: MarginContainer
var _move_preview: Control
var _action_label: Label
var _start_btn: Button
var _bottom_line: ColorRect

# 88px preview + 16px bottom padding = 104px
var _body_target_height: float = 104.0
var _body_tween: Tween

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

func _ready() -> void:
	_build_ui()
	_update_active_state(false)
	_apply_stat_loading()

func _apply_stat_loading() -> void:
	if not _rank_val_label or not _rank_skeleton:
		return
	_rank_val_label.visible = not rank_loading
	_rank_skeleton.visible = rank_loading
	_best_val_label.visible = not best_loading
	_best_skeleton.visible = best_loading

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# --- Header Button ---
	# Button minimum height 80px, with 14px top and 14px bottom margins
	# gives 52px inner space for the 50px text column.
	_header_btn = Button.new()
	_header_btn.name = "HeaderBtn"
	_header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_btn.custom_minimum_size = Vector2(0, 80)
	_header_btn.flat = true
	_header_btn.focus_mode = Control.FOCUS_NONE
	_header_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var empty_style := StyleBoxEmpty.new()
	_header_btn.add_theme_stylebox_override("normal", empty_style)
	_header_btn.add_theme_stylebox_override("hover", empty_style)
	_header_btn.add_theme_stylebox_override("pressed", empty_style)
	_header_btn.add_theme_stylebox_override("focus", empty_style)
	_header_btn.pressed.connect(func(): row_selected.emit(mode_id))
	add_child(_header_btn)

	var header_margin := MarginContainer.new()
	header_margin.name = "HeaderMargin"
	header_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_margin.add_theme_constant_override("margin_top", 14)
	header_margin.add_theme_constant_override("margin_bottom", 14)
	_header_btn.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_theme_constant_override("separation", 12)
	header_margin.add_child(header_hbox)

	# 6px color bar
	_color_bar = ColorRect.new()
	_color_bar.name = "ColorBar"
	_color_bar.custom_minimum_size = Vector2(6, 0)
	_color_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_color_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(_color_bar)

	# Text column
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 4)
	header_hbox.add_child(text_col)

	_exercise_label = Label.new()
	_exercise_label.name = "ExerciseLabel"
	_exercise_label.text = exercise_name.to_upper()
	_exercise_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exercise_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_exercise_label.add_theme_font_size_override("font_size", 28)
	_exercise_label.add_theme_constant_override("line_spacing", 0)
	_exercise_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_exercise_label.clip_text = false
	text_col.add_child(_exercise_label)

	_subline_label = Label.new()
	_subline_label.name = "SublineLabel"
	_subline_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subline_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_subline_label.add_theme_font_size_override("font_size", 10)
	_subline_label.add_theme_constant_override("line_spacing", 0)
	_subline_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_subline_label.clip_text = false
	text_col.add_child(_subline_label)

	# Stats column (hidden if locked)
	_stats_container = HBoxContainer.new()
	_stats_container.name = "StatsContainer"
	_stats_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_container.add_theme_constant_override("separation", 16)
	_stats_container.visible = not is_locked
	header_hbox.add_child(_stats_container)

	# RANK cell
	var rank_cell := VBoxContainer.new()
	rank_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_cell.add_theme_constant_override("separation", 2)
	_stats_container.add_child(rank_cell)

	var rank_cap := Label.new()
	rank_cap.text = "RANK"
	rank_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_cap.add_theme_font_override("font", Tokens.FONT_MONO)
	rank_cap.add_theme_font_size_override("font_size", 9)
	rank_cap.add_theme_color_override("font_color", Tokens.DIM)
	rank_cap.clip_text = false
	rank_cap.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	rank_cell.add_child(rank_cap)

	_rank_val_label = Label.new()
	_rank_val_label.text = rank_text
	_rank_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rank_val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_val_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_rank_val_label.add_theme_font_size_override("font_size", 18)
	_rank_val_label.clip_text = false
	_rank_val_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	rank_cell.add_child(_rank_val_label)
	_rank_skeleton = SkeletonBarClass.slot(30, 14, 27, true)
	rank_cell.add_child(_rank_skeleton)

	# BEST cell
	var best_cell := VBoxContainer.new()
	best_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	best_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	best_cell.add_theme_constant_override("separation", 2)
	_stats_container.add_child(best_cell)

	var best_cap := Label.new()
	best_cap.text = "BEST"
	best_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	best_cap.add_theme_font_override("font", Tokens.FONT_MONO)
	best_cap.add_theme_font_size_override("font_size", 9)
	best_cap.add_theme_color_override("font_color", Tokens.DIM)
	best_cap.clip_text = false
	best_cap.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	best_cell.add_child(best_cap)

	_best_val_label = Label.new()
	_best_val_label.text = best_score_text
	_best_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best_val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_val_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_best_val_label.add_theme_font_size_override("font_size", 18)
	_best_val_label.clip_text = false
	_best_val_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	best_cell.add_child(_best_val_label)
	_best_skeleton = SkeletonBarClass.slot(54, 14, 27, true)
	best_cell.add_child(_best_skeleton)

	# 4px right spacing for stats
	var r_pad := Control.new()
	r_pad.custom_minimum_size = Vector2(4, 0)
	r_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(r_pad)

	# --- Expandable Body ---
	_body_clip = Control.new()
	_body_clip.name = "BodyClip"
	_body_clip.clip_contents = true
	_body_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_clip.custom_minimum_size = Vector2(0, _body_target_height if is_active else 0.0)
	_body_clip.size = Vector2(0, _body_target_height if is_active else 0.0)
	_body_clip.visible = is_active
	add_child(_body_clip)

	_body_margin = MarginContainer.new()
	_body_margin.name = "BodyMargin"
	_body_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_body_margin.offset_left = 0
	_body_margin.offset_top = 0
	_body_margin.offset_right = 0
	_body_margin.offset_bottom = _body_target_height
	_body_margin.add_theme_constant_override("margin_left", 18)
	_body_margin.add_theme_constant_override("margin_top", 0)
	_body_margin.add_theme_constant_override("margin_bottom", 16)
	_body_clip.add_child(_body_margin)

	var body_hbox := HBoxContainer.new()
	body_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_hbox.add_theme_constant_override("separation", 12)
	_body_margin.add_child(body_hbox)

	# MovePreview (72x88)
	_move_preview = MovePreviewClass.new()
	_move_preview.name = "MovePreview"
	_move_preview.mode = mode_id
	_move_preview.mode_color = mode_color
	_move_preview.is_locked = is_locked
	body_hbox.add_child(_move_preview)

	# Right column (action text + StartButton)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_hbox.add_child(right_col)

	_action_label = Label.new()
	_action_label.text = action_text
	_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_label.add_theme_font_override("font", Tokens.FONT_SANS_SEMIBOLD)
	_action_label.add_theme_font_size_override("font_size", 14)
	_action_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_action_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_action_label.clip_text = false
	right_col.add_child(_action_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(spacer)

	_start_btn = Button.new()
	_start_btn.name = "StartButton"
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.custom_minimum_size = Vector2(0, 40)
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_setup_start_btn_styles()
	_start_btn.pressed.connect(func(): start_pressed.emit(mode_id))
	_start_btn.button_down.connect(func():
		_start_btn.pivot_offset = _start_btn.size * 0.5
		var tw = create_tween()
		tw.tween_property(_start_btn, "scale", Vector2(0.98, 0.98), 0.08)
	)
	_start_btn.button_up.connect(func():
		_start_btn.pivot_offset = _start_btn.size * 0.5
		var tw = create_tween()
		tw.tween_property(_start_btn, "scale", Vector2(1.0, 1.0), 0.08)
	)
	right_col.add_child(_start_btn)

	# --- Bottom Border Line ---
	# Actual ColorRect node so VBoxContainer layout guarantees it stays exactly at the bottom
	# without any redraw lag or overlap during accordion transitions.
	_bottom_line = ColorRect.new()
	_bottom_line.name = "BottomLine"
	_bottom_line.custom_minimum_size = Vector2(0, 1)
	_bottom_line.color = Tokens.LINE
	_bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_line)

func _setup_start_btn_styles() -> void:
	if not _start_btn:
		return

	for c in _start_btn.get_children():
		c.queue_free()

	if is_locked:
		var locked_sb := Tokens.make_panel_style(Color("#2A2A2E"), Color(0, 0, 0, 0), 0)
		_start_btn.add_theme_stylebox_override("normal", locked_sb)
		_start_btn.add_theme_stylebox_override("disabled", locked_sb)
		_start_btn.disabled = true

		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.text = "UNDER MAINTENANCE"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Tokens.DIM)
		lbl.clip_text = false
		lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_start_btn.add_child(lbl)
	else:
		var norm_sb := Tokens.make_panel_style(mode_color, Color(0, 0, 0, 0), 0)
		var hov_sb := Tokens.make_panel_style(mode_color.lightened(0.1), Color(0, 0, 0, 0), 0)
		_start_btn.add_theme_stylebox_override("normal", norm_sb)
		_start_btn.add_theme_stylebox_override("hover", hov_sb)
		_start_btn.add_theme_stylebox_override("pressed", hov_sb)
		_start_btn.disabled = false

		var inner_hbox := HBoxContainer.new()
		inner_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		inner_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner_hbox.add_theme_constant_override("separation", 8)
		_start_btn.add_child(inner_hbox)

		var icon := Control.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(func():
			var s: float = 14.0 / 24.0
			var pts := PackedVector2Array([
				Vector2(7.0 * s, 4.5 * s),
				Vector2(7.0 * s, 19.5 * s),
				Vector2(19.5 * s, 12.0 * s)
			])
			icon.draw_colored_polygon(pts, Tokens.INK)
		)
		inner_hbox.add_child(icon)

		var lbl := Label.new()
		lbl.text = "START"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Tokens.INK)
		lbl.clip_text = false
		lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		inner_hbox.add_child(lbl)

func _update_active_state(animate: bool = true) -> void:
	if not _color_bar:
		return

	# Color bar: signal if locked, else mode_color. Opacity 1 if active, 0.35 if inactive
	if is_locked:
		_color_bar.color = Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 1.0 if is_active else 0.35)
	else:
		_color_bar.color = Color(mode_color.r, mode_color.g, mode_color.b, 1.0 if is_active else 0.35)

	# Exercise label color
	if is_locked:
		_exercise_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	elif is_active:
		_exercise_label.add_theme_color_override("font_color", Tokens.WHITE)
	else:
		_exercise_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	# Subline label color & text
	if is_locked:
		_subline_label.text = "BACK SOON"
		_subline_label.add_theme_color_override("font_color", Tokens.SIGNAL)
	else:
		_subline_label.text = game_name.to_upper()
		_subline_label.add_theme_color_override("font_color", mode_color if is_active else Tokens.DIM)

	# Stats value colors
	if not is_locked and _rank_val_label and _best_val_label:
		var stat_col := Tokens.WHITE if is_active else Color(1, 1, 1, 0.5)
		_rank_val_label.add_theme_color_override("font_color", stat_col)
		_best_val_label.add_theme_color_override("font_color", stat_col)

	# Animate accordion height
	var target_h: float = _body_target_height if is_active else 0.0
	if _body_clip:
		if _body_tween and _body_tween.is_valid():
			_body_tween.kill()

		if animate:
			if is_active:
				_body_clip.visible = true
			_body_tween = create_tween()
			_body_tween.tween_method(func(h: float):
				_body_clip.custom_minimum_size.y = h
				_body_clip.size.y = h
				_body_clip.update_minimum_size()
				queue_sort()
				var p = get_parent()
				if p and p is Container:
					p.queue_sort()
			, _body_clip.custom_minimum_size.y, target_h, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if not is_active:
				_body_tween.tween_callback(func():
					if not is_active:
						_body_clip.visible = false
						_body_clip.custom_minimum_size.y = 0.0
						_body_clip.size.y = 0.0
						_body_clip.update_minimum_size()
						queue_sort()
						var p = get_parent()
						if p and p is Container:
							p.queue_sort()
				)
		else:
			_body_clip.custom_minimum_size.y = target_h
			_body_clip.size.y = target_h
			_body_clip.visible = is_active
			_body_clip.update_minimum_size()
			queue_sort()
			var p = get_parent()
			if p and p is Container:
				p.queue_sort()
