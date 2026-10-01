@tool
class_name IconButton
extends Button

## Standard 40x40 icon button for Hub, Back navigation, and actions.
## Implements the exact vector glyphs from Figma spec C1.

@export_enum("leaderboard", "settings", "back") var icon_type: String = "leaderboard":
	set(v):
		icon_type = v
		queue_redraw()

@export var is_back_button: bool = false:
	set(v):
		is_back_button = v
		queue_redraw()

var _is_hovered: bool = false
var _is_pressed: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pivot_offset = Vector2(20, 20)
	flat = true
	focus_mode = Control.FOCUS_NONE

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()

func _on_button_down() -> void:
	_is_pressed = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.95, 0.95), 0.08)
	queue_redraw()

func _on_button_up() -> void:
	_is_pressed = false
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg_color := Color(0, 0, 0, 0)
	var border_color := Tokens.LINE
	var stroke_color := Tokens.WHITE
	var stroke_w := 2.2

	if is_back_button:
		bg_color = Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.6)
		stroke_w = 2.5

	if _is_hovered or _is_pressed:
		bg_color = Tokens.VOLT
		border_color = Tokens.VOLT
		stroke_color = Tokens.INK

	# Draw background fill
	if bg_color.a > 0.0:
		draw_rect(rect, bg_color, true)

	# Draw 1px border inset by 0.5px so bottom and right are never cut off
	var border_rect := Rect2(0.5, 0.5, size.x - 1.0, size.y - 1.0)
	draw_rect(border_rect, border_color, false, 1.0)

	# Transform coordinates from 24x24 viewBox to centered 20x20 area
	var s: float = 20.0 / 24.0
	var offset := Vector2((size.x - 20.0) * 0.5, (size.y - 20.0) * 0.5)

	match icon_type:
		"leaderboard":
			_draw_leaderboard(offset, s, stroke_color, stroke_w)
		"settings":
			_draw_settings(offset, s, stroke_color, stroke_w)
		"back":
			_draw_back(offset, s, stroke_color, stroke_w)

func _pt(offset: Vector2, s: float, x: float, y: float) -> Vector2:
	return offset + Vector2(x * s, y * s)

func _draw_leaderboard(offset: Vector2, s: float, col: Color, w: float) -> void:
	# M9 20V8h6v12
	var p1 := PackedVector2Array([
		_pt(offset, s, 9, 20),
		_pt(offset, s, 9, 8),
		_pt(offset, s, 15, 8),
		_pt(offset, s, 15, 20)
	])
	draw_polyline(p1, col, w, true)

	# M3 20v-7h6
	var p2 := PackedVector2Array([
		_pt(offset, s, 3, 20),
		_pt(offset, s, 3, 13),
		_pt(offset, s, 9, 13)
	])
	draw_polyline(p2, col, w, true)

	# M15 20v-9h6v9
	var p3 := PackedVector2Array([
		_pt(offset, s, 15, 20),
		_pt(offset, s, 15, 11),
		_pt(offset, s, 21, 11),
		_pt(offset, s, 21, 20)
	])
	draw_polyline(p3, col, w, true)

	# M2 20h20
	draw_line(_pt(offset, s, 2, 20), _pt(offset, s, 22, 20), col, w, true)

func _draw_settings(offset: Vector2, s: float, col: Color, w: float) -> void:
	# M4 7h9
	draw_line(_pt(offset, s, 4, 7), _pt(offset, s, 13, 7), col, w, true)
	# M17 7h3
	draw_line(_pt(offset, s, 17, 7), _pt(offset, s, 20, 7), col, w, true)
	# M4 17h3
	draw_line(_pt(offset, s, 4, 17), _pt(offset, s, 7, 17), col, w, true)
	# M11 17h9
	draw_line(_pt(offset, s, 11, 17), _pt(offset, s, 20, 17), col, w, true)

	# rect at (13, 5), size 4x4
	var r1 := Rect2(_pt(offset, s, 13, 5), Vector2(4 * s, 4 * s))
	draw_rect(r1, col, false, w)

	# rect at (7, 15), size 4x4
	var r2 := Rect2(_pt(offset, s, 7, 15), Vector2(4 * s, 4 * s))
	draw_rect(r2, col, false, w)

func _draw_back(offset: Vector2, s: float, col: Color, w: float) -> void:
	# M14.5 5.5 L8 12 L14.5 18.5
	var p := PackedVector2Array([
		_pt(offset, s, 14.5, 5.5),
		_pt(offset, s, 8.0, 12.0),
		_pt(offset, s, 14.5, 18.5)
	])
	draw_polyline(p, col, w, true)
