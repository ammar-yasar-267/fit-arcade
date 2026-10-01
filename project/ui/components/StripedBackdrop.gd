extends Control

## Ink backdrop with the app's diagonal stripe texture (-45°, 12px pitch, white@0.03).
## Shared by the paused/primed overlays, onboarding and the delete-account confirm.
## Same pattern as the calibrate screen background.

var backdrop_alpha: float = 0.92

func _init(alpha: float = 0.92, blocks_input: bool = true) -> void:
	backdrop_alpha = alpha
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if blocks_input else Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, backdrop_alpha), true)

	var spacing := 12.0
	var col := Color(1, 1, 1, 0.03)
	var x := -size.y
	while x < size.x + size.y:
		draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), col, 2.0)
		x += spacing
