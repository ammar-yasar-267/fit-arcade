extends CanvasLayer

const BRAND_CYAN = Color("#06B6D4")
const CARD_SURFACE = Color("#1A1640")
const TEXT_PRIMARY = Color("#FFFFFF")
const TEXT_SECONDARY = Color("#A09CC0")

var score_value_label: Label
var timer_value_label: Label
var rep_value_label: Label
var form_label: Label
var form_chip: PanelContainer
var start_prompt_label: Label
var elapsed_time: float = 0.0
var is_timing: bool = false

func _make_chip(label_text: String, value_text: String, value_color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 26)
	value.add_theme_color_override("font_color", value_color)
	row.add_child(value)

	return chip

func _ready():
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 12
	panel.offset_left = 24
	panel.offset_right = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.07, 0.6)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var score_chip := _make_chip("Score", "0", BRAND_CYAN)
	score_value_label = score_chip.get_child(0).get_child(1) as Label
	hbox.add_child(score_chip)

	var timer_chip := _make_chip("Time", "0", TEXT_PRIMARY)
	timer_value_label = timer_chip.get_child(0).get_child(1) as Label
	hbox.add_child(timer_chip)

	var rep_chip := _make_chip("Reps", "0", TEXT_PRIMARY)
	rep_value_label = rep_chip.get_child(0).get_child(1) as Label
	hbox.add_child(rep_chip)

	form_chip = _make_chip("", "", TEXT_PRIMARY)
	form_chip.visible = false
	form_label = form_chip.get_child(0).get_child(1) as Label
	form_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Add spacer to push form chip down
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)
	vbox.add_child(form_chip)
	
	# Add start prompt label
	var prompt_spacer = Control.new()
	prompt_spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(prompt_spacer)
	
	start_prompt_label = Label.new()
	start_prompt_label.text = "Do a rep to start"
	start_prompt_label.add_theme_font_size_override("font_size", 45)
	start_prompt_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	start_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(start_prompt_label)

	ExerciseRecognizer.rep_completed.connect(_on_rep)
	ExerciseRecognizer.form_feedback.connect(_on_form)
	
	# Connect to game signals
	var active_game = GameManager.get_active_game()
	if active_game:
		active_game.game_over.connect(_on_game_over)
		is_timing = true
		elapsed_time = 0.0
	
	_update_labels()

func _process(delta):
	var game = GameManager.get_active_game()
	if game and game.is_running and not is_timing:
		is_timing = true
		elapsed_time = 0.0
		update_time(0.0)
	
	if is_timing:
		elapsed_time += delta
		update_time(elapsed_time)

func _exit_tree():
	if ExerciseRecognizer.rep_completed.is_connected(_on_rep):
		ExerciseRecognizer.rep_completed.disconnect(_on_rep)
	if ExerciseRecognizer.form_feedback.is_connected(_on_form):
		ExerciseRecognizer.form_feedback.disconnect(_on_form)
	var active_game = GameManager.get_active_game()
	if active_game and active_game.game_over.is_connected(_on_game_over):
		active_game.game_over.disconnect(_on_game_over)

func update_score(score: int):
	if score_value_label:
		score_value_label.text = str(score)

func update_time(time_left: float):
	if timer_value_label:
		timer_value_label.text = str(int(time_left))

func _on_rep():
	start_prompt_label.visible = false
	_update_labels()

func _on_game_over(_score: int):
	is_timing = false
	elapsed_time = 0.0
	update_time(0.0)
	start_prompt_label.visible = true

func _on_form(message: String, is_good: bool):
	if not is_inside_tree(): return
	if form_chip:
		form_chip.visible = true
	if form_label:
		var status_text = "+1 Rep" if is_good else "Adjust Form"
		form_label.text = status_text
		if is_good:
			form_label.add_theme_color_override("font_color", Color("#22C55E"))
		else:
			form_label.add_theme_color_override("font_color", Color("#F59E0B"))

	get_tree().create_timer(2.2).timeout.connect(
		func():
			if is_inside_tree() and form_label:
				form_label.text = ""
			if is_inside_tree() and form_chip:
				form_chip.visible = false
	)

func _update_labels():
	if rep_value_label:
		rep_value_label.text = str(SessionManager.current_reps)
