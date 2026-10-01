@tool
class_name WeekStrip
extends PanelContainer

## Weekly summary card showing total reps and 7-day bar chart.
## Specs from Figma C4.

@export var total_reps: int = 0:
	set(v):
		total_reps = v
		if is_inside_tree():
			_build_content()

@export var week_data: Array[Dictionary] = []:
	set(v):
		week_data = v
		if is_inside_tree():
			_build_content()

@export var today_index: int = -1:
	set(v):
		today_index = v
		if is_inside_tree():
			_build_content()

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	if week_data.is_empty() and get_tree() and get_tree().root and get_tree().root.has_node("SessionManager"):
		var w_info = SessionManager.get_weekly_data()
		total_reps = w_info.get("total_reps", 0)
		week_data = w_info.get("days", [])
		today_index = w_info.get("today_index", -1)

	# Setup panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.PANEL
	style.draw_center = true
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)

	_build_content()

func _draw() -> void:
	var border_rect := Rect2(0.5, 0.5, size.x - 1.0, size.y - 1.0)
	draw_rect(border_rect, Tokens.LINE, false, 1.0)

func update_data(total: int, data: Array[Dictionary], today_idx: int = -1) -> void:
	total_reps = total
	week_data = data
	today_index = today_idx
	_build_content()

func _build_content() -> void:
	for c in get_children():
		c.queue_free()

	var root_hbox := HBoxContainer.new()
	root_hbox.add_theme_constant_override("separation", 20)
	root_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(root_hbox)

	# --- Left column: THIS WEEK & Total REPS ---
	var left_col := VBoxContainer.new()
	left_col.size_flags_vertical = Control.SIZE_SHRINK_END
	left_col.add_theme_constant_override("separation", 2)
	root_hbox.add_child(left_col)

	var label_this_week := Label.new()
	label_this_week.text = "THIS WEEK"
	label_this_week.add_theme_font_override("font", Tokens.FONT_MONO)
	label_this_week.add_theme_font_size_override("font_size", 11)
	label_this_week.add_theme_color_override("font_color", Tokens.DIM)
	left_col.add_child(label_this_week)

	var reps_rtl := RichTextLabel.new()
	reps_rtl.bbcode_enabled = true
	reps_rtl.fit_content = true
	reps_rtl.scroll_active = false
	reps_rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	reps_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reps_rtl.add_theme_font_override("normal_font", Tokens.FONT_DISPLAY)
	var dim_hex: String = Tokens.DIM.to_html(false)
	var text_hex: String = Tokens.TEXT.to_html(false)
	reps_rtl.text = "[color=#%s][font_size=48]%d[/font_size][/color][color=#%s][font_size=18] REPS[/font_size][/color]" % [text_hex, total_reps, dim_hex]
	left_col.add_child(reps_rtl)

	# --- Right column: 7-bar chart ---
	var chart_hbox := HBoxContainer.new()
	chart_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_hbox.size_flags_vertical = Control.SIZE_SHRINK_END
	chart_hbox.custom_minimum_size = Vector2(0, 64)
	chart_hbox.add_theme_constant_override("separation", 8)
	root_hbox.add_child(chart_hbox)

	var max_reps := 1
	for day in week_data:
		var r: int = day.get("reps", 0)
		if r > max_reps:
			max_reps = r

	for i in range(week_data.size()):
		var day = week_data[i]
		var reps: int = day.get("reps", 0)
		var is_today: bool = (i == today_index) if today_index >= 0 else day.get("is_today", false)

		var bar_height: float = maxf(3.0, (float(reps) / float(max_reps)) * 46.0) if max_reps > 0 and reps > 0 else 3.0

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_END
		col.alignment = BoxContainer.ALIGNMENT_END
		col.add_theme_constant_override("separation", 4)
		chart_hbox.add_child(col)

		# Bar rect
		var bar := ColorRect.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, bar_height)
		if is_today:
			bar.color = Tokens.VOLT
		elif reps > 0:
			bar.color = Tokens.BAR_IDLE
		else:
			bar.color = Tokens.BAR_ZERO
		col.add_child(bar)

		# Day letter label
		var day_label := Label.new()
		day_label.text = day.get("d", "")
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day_label.add_theme_font_override("font", Tokens.FONT_MONO)
		day_label.add_theme_font_size_override("font_size", 10)
		day_label.add_theme_color_override("font_color", Tokens.VOLT if is_today else Tokens.DIM)
		col.add_child(day_label)
