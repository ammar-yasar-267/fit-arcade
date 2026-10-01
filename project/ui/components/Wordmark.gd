@tool
class_name Wordmark
extends MarginContainer

## Wordmark footer component: line - FITARCADE - line.
## Spec from Figma C8: display 20 uppercase, FIT in white, ARCADE in volt.

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_top", 32)
	add_theme_constant_override("margin_bottom", 4)

func _ready() -> void:
	for c in get_children():
		c.queue_free()

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	var line1 := ColorRect.new()
	line1.color = Tokens.LINE
	line1.custom_minimum_size = Vector2(0, 1)
	line1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(line1)

	var fit_lbl := Label.new()
	fit_lbl.text = "FIT"
	fit_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	fit_lbl.add_theme_font_size_override("font_size", 20)
	fit_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	hbox.add_child(fit_lbl)

	var arcade_lbl := Label.new()
	arcade_lbl.text = "ARCADE"
	arcade_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	arcade_lbl.add_theme_font_size_override("font_size", 20)
	arcade_lbl.add_theme_color_override("font_color", Tokens.VOLT)
	hbox.add_child(arcade_lbl)

	var line2 := ColorRect.new()
	line2.color = Tokens.LINE
	line2.custom_minimum_size = Vector2(0, 1)
	line2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(line2)
