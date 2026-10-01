@tool
class_name IdentityBar
extends HBoxContainer

## Identity bar component for the Hub header.
## HexBadge + Name Block + Leaderboard Button + Settings Button.

const HexBadgeClass = preload("res://ui/components/HexBadge.gd")
const IconButtonClass = preload("res://ui/components/IconButton.gd")
const SkeletonBarClass = preload("res://ui/components/SkeletonBar.gd")

signal leaderboard_pressed
signal settings_pressed

## While true the name, tag and badge show pulsing placeholders instead of text, for
## when the player's profile hasn't been loaded yet. There are no fake defaults:
## nothing here pretends to be a real player.
@export var loading: bool = false:
	set(v):
		loading = v
		_apply_loading()

@export var player_name: String = "":
	set(v):
		player_name = v
		if _name_label:
			_name_label.text = v

@export var tag_text: String = "":
	set(v):
		tag_text = v
		_update_subline()

@export var level: int = 1:
	set(v):
		level = v
		_update_subline()

@export var badge_initials: String = "":
	set(v):
		badge_initials = v
		if _hex_badge and not loading:
			_hex_badge.text = v

var _hex_badge: Control
var _name_label: Label
var _sub_label: Label
var _name_skeleton: Control
var _sub_skeleton: Control
var _btn_leaderboard: Button
var _btn_settings: Button

func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(0, 44)

func _ready() -> void:
	# Avoid duplicate children if instantiated from scene
	if get_child_count() > 0:
		_hex_badge = get_node_or_null("HexBadge")
		var name_col = get_node_or_null("NameCol")
		if name_col:
			_name_label = name_col.get_node_or_null("NameLabel")
			_sub_label = name_col.get_node_or_null("SubLabel")
		_btn_leaderboard = get_node_or_null("BtnLeaderboard")
		_btn_settings = get_node_or_null("BtnSettings")
		if _btn_leaderboard:
			_btn_leaderboard.pressed.connect(func(): leaderboard_pressed.emit())
		if _btn_settings:
			_btn_settings.pressed.connect(func(): settings_pressed.emit())
		return

	# Build programmatically if created via script
	_hex_badge = HexBadgeClass.new()
	_hex_badge.name = "HexBadge"
	_hex_badge.text = badge_initials
	_hex_badge.custom_minimum_size = Vector2(44, 44)
	_hex_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hex_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_hex_badge)

	var name_col := VBoxContainer.new()
	name_col.name = "NameCol"
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_theme_constant_override("separation", 4)
	add_child(name_col)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = player_name
	_name_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Tokens.TEXT)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_col.add_child(_name_label)

	_sub_label = Label.new()
	_sub_label.name = "SubLabel"
	_sub_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_sub_label.add_theme_font_size_override("font_size", 10)
	_sub_label.add_theme_color_override("font_color", Tokens.DIM)
	name_col.add_child(_sub_label)
	_update_subline()

	# Skeleton stand-ins, sized to the text they replace so nothing shifts on load
	_name_skeleton = SkeletonBarClass.slot(120, 16, 30)
	_name_skeleton.visible = false
	name_col.add_child(_name_skeleton)
	_sub_skeleton = SkeletonBarClass.slot(72, 8, 14)
	_sub_skeleton.visible = false
	name_col.add_child(_sub_skeleton)

	_btn_leaderboard = IconButtonClass.new()
	_btn_leaderboard.name = "BtnLeaderboard"
	_btn_leaderboard.icon_type = "leaderboard"
	_btn_leaderboard.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_leaderboard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn_leaderboard.pressed.connect(func(): leaderboard_pressed.emit())
	add_child(_btn_leaderboard)

	_btn_settings = IconButtonClass.new()
	_btn_settings.name = "BtnSettings"
	_btn_settings.icon_type = "settings"
	_btn_settings.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn_settings.pressed.connect(func(): settings_pressed.emit())
	add_child(_btn_settings)
	_apply_loading()

func _update_subline() -> void:
	if _sub_label:
		_sub_label.text = "%s · LVL %d" % [tag_text, level] if tag_text != "" else "LVL %d" % level

func _apply_loading() -> void:
	if not _name_label or not _name_skeleton:
		return
	_name_label.visible = not loading
	_sub_label.visible = not loading
	_name_skeleton.visible = loading
	_sub_skeleton.visible = loading
	if _hex_badge:
		# Greyed-out hexagon with no initials until there's a real player behind it
		_hex_badge.bg_color = Tokens.LINE if loading else Tokens.VOLT
		_hex_badge.text = "" if loading else badge_initials
