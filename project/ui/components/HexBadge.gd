@tool
class_name HexBadge
extends Control

## Hexagonal player badge drawn natively with polygon and Anton display font.
## Specs from Figma C3: 44x44 volt fill, hexagon clip, Anton 18 ink text.

@export var text: String = "KV":
	set(v):
		text = v
		queue_redraw()

@export var bg_color: Color = Color("#D4FF3A"):
	set(v):
		bg_color = v
		queue_redraw()

@export var text_color: Color = Color("#0B0B0C"):
	set(v):
		text_color = v
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Points: (50% 0, 100% 25%, 100% 75%, 50% 100%, 0 75%, 0 25%)
	var pts := PackedVector2Array([
		Vector2(w * 0.50, 0.0),
		Vector2(w, h * 0.25),
		Vector2(w, h * 0.75),
		Vector2(w * 0.50, h),
		Vector2(0.0, h * 0.75),
		Vector2(0.0, h * 0.25)
	])
	draw_colored_polygon(pts, bg_color)

	# Draw initials centered
	var font: Font = Tokens.FONT_DISPLAY
	var font_size: int = 18
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var font_ascent := font.get_ascent(font_size)
	var font_descent := font.get_descent(font_size)
	var text_h := font_ascent + font_descent
	var pos := Vector2((w - text_w) * 0.5, (h - text_h) * 0.5 + font_ascent)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
