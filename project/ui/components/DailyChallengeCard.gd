@tool
class_name DailyChallengeCard
extends PanelContainer

## Daily challenge interactive card on the Hub.
## Spec from Figma C5: Panel with text column, progress ring, and volt play block.

const ProgressRingClass = preload("res://ui/components/ProgressRing.gd")

signal challenge_pressed(mode_id: String)

@export var mode_id: String = "lane":
	set(v):
		mode_id = v
		if is_inside_tree():
			_setup_ui()

@export var is_locked: bool = false:
	set(v):
		is_locked = v
		if is_inside_tree():
			_setup_ui()

@export var title: String = "40 SIDE LUNGES":
	set(v):
		title = v
		if is_inside_tree():
			_setup_ui()

@export var current_progress: int = 0:
	set(v):
		current_progress = v
		if is_inside_tree():
			_setup_ui()

@export var total_target: int = 40:
	set(v):
		total_target = v
		if is_inside_tree():
			_setup_ui()

@export var time_left_text: String = "7H LEFT":
	set(v):
		time_left_text = v
		if is_inside_tree():
			_setup_ui()

@export var subline_text: String = "Under 2:00 · +500 XP":
	set(v):
		subline_text = v
		if is_inside_tree():
			_setup_ui()

var _is_hovered: bool = false
var _is_pressed: bool = false

var _panel_style: StyleBoxFlat
var _play_block: Control
var _click_btn: Button

func _init() -> void:
	custom_minimum_size = Vector2(0, 80)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	_setup_ui()

func update_challenge(data: Dictionary) -> void:
	mode_id = data.get("mode_id", mode_id)
	title = data.get("title", title)
	current_progress = data.get("current_progress", current_progress)
	total_target = data.get("total_target", total_target)
	time_left_text = data.get("time_left", time_left_text)
	subline_text = data.get("subline", subline_text)
	_setup_ui()

func _setup_ui() -> void:
	for c in get_children():
		c.queue_free()

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Tokens.PANEL
	_panel_style.draw_center = true
	_panel_style.border_width_left = 0
	_panel_style.border_width_top = 0
	_panel_style.border_width_right = 0
	_panel_style.border_width_bottom = 0
	_panel_style.content_margin_left = 16
	_panel_style.content_margin_right = 12
	_panel_style.content_margin_top = 12
	_panel_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", _panel_style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(hbox)

	# --- Text column (expands) ---
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	# Line 1: RichTextLabel for DAILY CHALLENGE · [TIME] LEFT
	var rtl1 := RichTextLabel.new()
	rtl1.bbcode_enabled = true
	rtl1.fit_content = true
	rtl1.scroll_active = false
	rtl1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl1.add_theme_font_override("normal_font", Tokens.FONT_MONO)
	rtl1.add_theme_font_size_override("normal_font_size", 10)
	var dim_hex = Tokens.DIM.to_html(false)
	var left_hex = Color(1, 1, 1, 0.6).to_html(false)
	rtl1.text = "[color=#%s]DAILY CHALLENGE · [/color][color=#%s]%s[/color]" % [dim_hex, left_hex, time_left_text]
	text_col.add_child(rtl1)

	# Line 2: e.g. 40 SIDE LUNGES
	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Tokens.TEXT)
	text_col.add_child(title_lbl)

	# Line 3: Under 2:00 · +500 XP
	var rtl3 := RichTextLabel.new()
	rtl3.bbcode_enabled = true
	rtl3.fit_content = true
	rtl3.scroll_active = false
	rtl3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl3.add_theme_font_override("normal_font", Tokens.FONT_SANS_SEMIBOLD)
	rtl3.add_theme_font_size_override("normal_font_size", 12)
	var sub_hex = Color(1, 1, 1, 0.5).to_html(false)
	var dot_hex = Color(1, 1, 1, 0.2).to_html(false)
	var volt_hex = Tokens.VOLT.to_html(false)

	# Format subline_text if it contains "·"
	if subline_text.contains("·"):
		var parts := subline_text.split("·")
		var part1 := parts[0].strip_edges()
		var part2 := parts[1].strip_edges()
		rtl3.text = "[color=#%s]%s[/color] [color=#%s]·[/color] [color=#%s]%s[/color]" % [sub_hex, part1, dot_hex, volt_hex, part2]
	else:
		rtl3.text = "[color=#%s]%s[/color]" % [sub_hex, subline_text]
	text_col.add_child(rtl3)

	# --- ProgressRing ---
	var ring = ProgressRingClass.new()
	ring.current_val = current_progress
	ring.max_val = total_target
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(ring)

	# --- PlayBlock (36x56) ---
	_play_block = ColorRect.new()
	_play_block.name = "PlayBlock"
	_play_block.custom_minimum_size = Vector2(36, 56)
	_play_block.color = Tokens.VOLT
	_play_block.pivot_offset = Vector2(18, 28)
	_play_block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_play_block)

	var play_icon := Control.new()
	play_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_icon.draw.connect(func():
		var s: float = 16.0 / 24.0
		var offset := Vector2((play_icon.size.x - 16.0) * 0.5 + 1.0, (play_icon.size.y - 16.0) * 0.5)
		var pts := PackedVector2Array([
			offset + Vector2(7.0 * s, 4.5 * s),
			offset + Vector2(7.0 * s, 19.5 * s),
			offset + Vector2(19.5 * s, 12.0 * s)
		])
		play_icon.draw_colored_polygon(pts, Tokens.INK)
	)
	_play_block.add_child(play_icon)

	# --- Clickable Button Overlay ---
	_click_btn = Button.new()
	_click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_click_btn.flat = true
	_click_btn.focus_mode = Control.FOCUS_NONE
	_click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	_click_btn.add_theme_stylebox_override("normal", empty_sb)
	_click_btn.add_theme_stylebox_override("hover", empty_sb)
	_click_btn.add_theme_stylebox_override("pressed", empty_sb)
	_click_btn.add_theme_stylebox_override("focus", empty_sb)

	_click_btn.mouse_entered.connect(_on_mouse_entered)
	_click_btn.mouse_exited.connect(_on_mouse_exited)
	_click_btn.button_down.connect(_on_button_down)
	_click_btn.button_up.connect(_on_button_up)
	_click_btn.pressed.connect(_on_pressed)
	add_child(_click_btn)

func _draw() -> void:
	var b_color: Color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.8) if _is_hovered else Tokens.LINE
	var border_rect := Rect2(0.5, 0.5, size.x - 1.0, size.y - 1.0)
	draw_rect(border_rect, b_color, false, 1.0)

func _on_mouse_entered() -> void:
	_is_hovered = true
	if _play_block and _play_block is ColorRect:
		_play_block.color = Tokens.VOLT.lightened(0.1)
	queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	if _play_block and _play_block is ColorRect:
		_play_block.color = Tokens.VOLT
	queue_redraw()

func _on_button_down() -> void:
	_is_pressed = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.99, 0.99), 0.08)
	if _play_block:
		tw.tween_property(_play_block, "scale", Vector2(0.95, 0.95), 0.08)
		_play_block.queue_redraw()

func _on_button_up() -> void:
	_is_pressed = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	if _play_block:
		tw.tween_property(_play_block, "scale", Vector2(1.0, 1.0), 0.08)
		_play_block.queue_redraw()

func _on_pressed() -> void:
	if not is_locked:
		challenge_pressed.emit(mode_id)
