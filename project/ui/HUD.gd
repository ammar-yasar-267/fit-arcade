extends CanvasLayer

const BRAND_CYAN = Color("#06B6D4")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")

var score_value_label: Label
var timer_value_label: Label
var rep_value_label: Label
var start_prompt_label: Label
var elapsed_time: float = 0.0
var is_timing: bool = false

func _make_stat_col(label_text: String, value_text: String, value_color: Color) -> Dictionary:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 54)
	val.add_theme_color_override("font_color", value_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(val)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lbl)

	return {"container": col, "value_label": val}

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 12
	panel.offset_left = 20
	panel.offset_right = -20
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.07, 0.82)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 0)
	panel.add_child(hbox)

	var score_data = _make_stat_col("SCORE", "0", BRAND_CYAN)
	score_value_label = score_data["value_label"]
	hbox.add_child(score_data["container"])

	var divider1 := ColorRect.new()
	divider1.color = Color(1, 1, 1, 0.1)
	divider1.custom_minimum_size = Vector2(1, 52)
	divider1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var div1_margin := MarginContainer.new()
	div1_margin.add_theme_constant_override("margin_left", 28)
	div1_margin.add_theme_constant_override("margin_right", 28)
	div1_margin.add_child(divider1)
	hbox.add_child(div1_margin)

	var timer_data = _make_stat_col("TIME", "0:00", TEXT_PRIMARY)
	timer_value_label = timer_data["value_label"]
	hbox.add_child(timer_data["container"])

	var divider2 := ColorRect.new()
	divider2.color = Color(1, 1, 1, 0.1)
	divider2.custom_minimum_size = Vector2(1, 52)
	divider2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var div2_margin := MarginContainer.new()
	div2_margin.add_theme_constant_override("margin_left", 28)
	div2_margin.add_theme_constant_override("margin_right", 28)
	div2_margin.add_child(divider2)
	hbox.add_child(div2_margin)

	var rep_data = _make_stat_col("REPS", "0", TEXT_PRIMARY)
	rep_value_label = rep_data["value_label"]
	hbox.add_child(rep_data["container"])

func _build_start_prompt() -> void:
	start_prompt_label = Label.new()
	start_prompt_label.text = "Do a rep to start"
	start_prompt_label.add_theme_font_size_override("font_size", 60)
	start_prompt_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	start_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	start_prompt_label.offset_left = -260
	start_prompt_label.offset_right = 260
	start_prompt_label.offset_top = -50
	start_prompt_label.offset_bottom = 50
	add_child(start_prompt_label)

func _ready():
	_build_top_bar()
	_build_start_prompt()

	ExerciseRecognizer.rep_completed.connect(_on_rep)

	var active_game = GameManager.get_active_game()
	if active_game:
		active_game.game_over.connect(_on_game_over)
		is_timing = true
		elapsed_time = 0.0

	_update_labels()

func _process(delta):
	var game = GameManager.get_active_game()

	if game and not game.is_running and is_timing:
		is_timing = false
		elapsed_time = 0.0
		update_time(0.0)
		_update_labels()
		if start_prompt_label:
			start_prompt_label.visible = true

	if game and game.is_running and not is_timing:
		is_timing = true
		elapsed_time = 0.0
		update_time(0.0)
		_update_labels()
		if start_prompt_label:
			start_prompt_label.visible = true

	if is_timing:
		elapsed_time += delta
		update_time(elapsed_time)


func _exit_tree():
	if ExerciseRecognizer.rep_completed.is_connected(_on_rep):
		ExerciseRecognizer.rep_completed.disconnect(_on_rep)
	var active_game = GameManager.get_active_game()
	if active_game and active_game.game_over.is_connected(_on_game_over):
		active_game.game_over.disconnect(_on_game_over)

func update_score(score: int):
	if score_value_label:
		score_value_label.text = str(score)

func update_time(time_left: float):
	if timer_value_label:
		var t = int(time_left)
		timer_value_label.text = "%d:%02d" % [t / 60.0, t % 60]

func _on_rep(_rep_count: int = 0):
	if start_prompt_label:
		start_prompt_label.visible = false
	_update_labels()

func _on_game_over(_score: int):
	is_timing = false
	elapsed_time = 0.0
	update_time(0.0)
	SessionManager.reset_session()
	_update_labels()
	if start_prompt_label:
		start_prompt_label.visible = true

func _update_labels():
	if rep_value_label:
		rep_value_label.text = str(SessionManager.current_reps)
