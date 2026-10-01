@tool
class_name ProgressRing
extends Control

## Circular progress indicator with fractional text.
## Spec from Figma C5: 56x56, r=24, stroke 4, track white@0.08, arc volt, "14/40" text.

@export var current_val: int = 14:
	set(v):
		current_val = v
		queue_redraw()

@export var max_val: int = 40:
	set(v):
		max_val = v
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size * 0.5
	var radius := 24.0
	var stroke_w := 4.0

	# Track circle
	var track_color := Color(1.0, 1.0, 1.0, 0.08)
	draw_arc(center, radius, 0, TAU, 48, track_color, stroke_w, true)

	# Progress arc starting at 12 o'clock (-PI/2)
	var pct: float = clampf(float(current_val) / float(maxf(1, max_val)), 0.0, 1.0)
	if pct > 0.0:
		var start_angle := -PI * 0.5
		var end_angle := start_angle + TAU * pct
		draw_arc(center, radius, start_angle, end_angle, 36, Tokens.VOLT, stroke_w, true)

	# Draw "14" and "/40" on same baseline
	var font: Font = Tokens.FONT_DISPLAY
	var cur_str := str(current_val)
	var max_str := "/%d" % max_val

	var sz_cur := 18
	var sz_max := 12

	var w_cur := font.get_string_size(cur_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz_cur).x
	var w_max := font.get_string_size(max_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz_max).x
	var total_w := w_cur + w_max

	var ascent_cur := font.get_ascent(sz_cur)
	var descent_cur := font.get_descent(sz_cur)
	var text_h := ascent_cur + descent_cur

	var baseline_y := (size.y - text_h) * 0.5 + ascent_cur
	var start_x := (size.x - total_w) * 0.5

	# Draw current value
	draw_string(font, Vector2(start_x, baseline_y), cur_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz_cur, Tokens.TEXT)
	# Draw max value
	draw_string(font, Vector2(start_x + w_cur, baseline_y), max_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sz_max, Tokens.DIM)
