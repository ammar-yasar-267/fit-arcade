@tool
class_name SectionHeading
extends HBoxContainer

## Section heading: Title + expanding 1px line rule + subtitle.
## Spec from Figma C6: "GAMES" | 1px line | "PICK ONE · 3 MODES".

@export var title: String = "GAMES"
@export var subtitle: String = "PICK ONE · 3 MODES"

func _init() -> void:
	add_theme_constant_override("separation", 12)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	for c in get_children():
		c.queue_free()

	# Title: display 24 uppercase
	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Tokens.TEXT)
	add_child(title_lbl)

	# 1px line rule expanding horizontally
	var line := ColorRect.new()
	line.color = Tokens.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(line)

	# Subtitle: mono 10 tracking 0.1em dim
	var sub_lbl := Label.new()
	sub_lbl.text = subtitle.to_upper()
	sub_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", Tokens.DIM)
	add_child(sub_lbl)
