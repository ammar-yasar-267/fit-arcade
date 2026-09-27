extends Control

const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")

const MODES = [
	{"id": "dino", "label": "Dino"},
	{"id": "switcher", "label": "Switcher"},
	{"id": "flappy", "label": "Flappy"},
]

var _content_vbox: VBoxContainer
var _tab_buttons: Dictionary = {}
var _active_mode: String = "dino"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0157, 0.0157, 0.0627, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.flat = true
	back_btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	header_row.add_child(back_btn)

	var title := Label.new()
	title.text = "Leaderboards"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", BRAND_CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_row.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(64, 0)
	header_row.add_child(spacer)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	vbox.add_child(tabs)

	for mode in MODES:
		var btn := Button.new()
		btn.text = mode["label"]
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_tab_pressed.bind(mode["id"]))
		tabs.add_child(btn)
		_tab_buttons[mode["id"]] = btn

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_content_vbox)

	_update_tab_styles()
	_load_leaderboard(_active_mode)

func _on_tab_pressed(mode_id: String) -> void:
	if mode_id == _active_mode:
		return
	_active_mode = mode_id
	_update_tab_styles()
	_load_leaderboard(mode_id)

func _update_tab_styles() -> void:
	for mode_id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[mode_id]
		var active: bool = mode_id == _active_mode
		var style := StyleBoxFlat.new()
		style.bg_color = BRAND_CYAN if active else CARD_SURFACE
		style.corner_radius_top_left = 999
		style.corner_radius_top_right = 999
		style.corner_radius_bottom_left = 999
		style.corner_radius_bottom_right = 999
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color("#04101A") if active else TEXT_SECONDARY)

func _load_leaderboard(mode_id: String) -> void:
	for child in _content_vbox.get_children():
		child.queue_free()

	var loading := Label.new()
	loading.text = "Loading…"
	loading.add_theme_color_override("font_color", TEXT_SECONDARY)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(loading)

	var rows := await Backend.get_leaderboard(mode_id, 50)

	if mode_id != _active_mode:
		return # user switched tabs while this was loading
	for child in _content_vbox.get_children():
		child.queue_free()

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No scores yet — be the first."
		empty.add_theme_color_override("font_color", TEXT_SECONDARY)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_vbox.add_child(empty)
		return

	for i in range(rows.size()):
		_content_vbox.add_child(_make_row(i + 1, rows[i]))

func _make_row(rank: int, row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_SURFACE
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	var rank_label := Label.new()
	rank_label.text = "#%d" % rank
	rank_label.custom_minimum_size = Vector2(44, 0)
	rank_label.add_theme_font_size_override("font_size", 18)
	rank_label.add_theme_color_override("font_color", BRAND_CYAN)
	hbox.add_child(rank_label)

	var display_tag: String = row.get("display_tag", "")
	var tag_number: String = display_tag.split("#")[-1] if display_tag.find("#") != -1 else ""

	var name_label := Label.new()
	name_label.text = "%s  #%s" % [row.get("display_name", "?"), tag_number]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	hbox.add_child(name_label)

	var score_label := Label.new()
	score_label.text = str(row.get("score", 0))
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	hbox.add_child(score_label)

	return panel
