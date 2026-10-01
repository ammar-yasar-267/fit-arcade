@tool
class_name PageHeader
extends VBoxContainer

## Reusable PageHeader for Leaderboard and Settings screens.
## Spec from design-spec.md Section C2 and PageHeader.tsx.
## Row 1: BackButton (40x40) + "HUB / TITLE" breadcrumb.
## Row 2: 20px gap, huge display title (56px uppercase).

const IconButtonClass = preload("res://ui/components/IconButton.gd")

signal back_pressed

@export var title: String = "LEADERBOARD":
	set(v):
		title = v
		_update_labels()

@export var breadcrumb_parent: String = "HUB":
	set(v):
		breadcrumb_parent = v
		_update_labels()

var _back_btn: Button
var _crumb_parent_lbl: Label
var _crumb_slash_lbl: Label
var _crumb_title_lbl: Label
var _title_lbl: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 20)

func _ready() -> void:
	_build_ui()
	_update_labels()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Row 1: Back button + Breadcrumbs
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_BEGIN
	row1.add_theme_constant_override("separation", 12)
	add_child(row1)

	_back_btn = IconButtonClass.new()
	_back_btn.name = "BackButton"
	_back_btn.icon_type = "back"
	_back_btn.is_back_button = true
	_back_btn.pressed.connect(func(): back_pressed.emit())
	row1.add_child(_back_btn)

	var crumb_box := HBoxContainer.new()
	crumb_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crumb_box.add_theme_constant_override("separation", 6)
	row1.add_child(crumb_box)

	_crumb_parent_lbl = Label.new()
	_crumb_parent_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	_crumb_parent_lbl.add_theme_font_size_override("font_size", 11)
	_crumb_parent_lbl.add_theme_color_override("font_color", Tokens.DIM)
	crumb_box.add_child(_crumb_parent_lbl)

	_crumb_slash_lbl = Label.new()
	_crumb_slash_lbl.text = "/"
	_crumb_slash_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	_crumb_slash_lbl.add_theme_font_size_override("font_size", 11)
	_crumb_slash_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	crumb_box.add_child(_crumb_slash_lbl)

	_crumb_title_lbl = Label.new()
	_crumb_title_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	_crumb_title_lbl.add_theme_font_size_override("font_size", 11)
	_crumb_title_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	crumb_box.add_child(_crumb_title_lbl)

	# Row 2: Page Title
	_title_lbl = Label.new()
	_title_lbl.name = "PageTitle"
	_title_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_title_lbl.add_theme_font_size_override("font_size", 52)
	_title_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	_title_lbl.add_theme_constant_override("line_spacing", -6)
	_title_lbl.clip_text = false
	_title_lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_title_lbl)

func _update_labels() -> void:
	if _crumb_parent_lbl:
		_crumb_parent_lbl.text = breadcrumb_parent.to_upper()
	if _crumb_title_lbl:
		_crumb_title_lbl.text = title.to_upper()
	if _title_lbl:
		_title_lbl.text = title.to_upper()
