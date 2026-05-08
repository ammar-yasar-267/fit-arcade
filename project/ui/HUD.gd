extends CanvasLayer

var score_label: Label
var timer_label: Label
var rep_label: Label
var form_label: Label

func _ready():
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	
	var top_row = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 32)
	vbox.add_child(top_row)
	
	score_label = Label.new()
	score_label.text = "Score: 0"
	score_label.add_theme_font_size_override("font_size", 24)
	top_row.add_child(score_label)
	
	timer_label = Label.new()
	timer_label.text = "Time: 0"
	timer_label.add_theme_font_size_override("font_size", 24)
	top_row.add_child(timer_label)
	
	rep_label = Label.new()
	rep_label.text = "Reps: 0"
	rep_label.add_theme_font_size_override("font_size", 24)
	top_row.add_child(rep_label)
	
	form_label = Label.new()
	form_label.add_theme_font_size_override("font_size", 28)
	form_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(form_label)
	
	ExerciseRecognizer.rep_completed.connect(_on_rep)
	ExerciseRecognizer.form_feedback.connect(_on_form)
	_update_labels()

func _exit_tree():
	if ExerciseRecognizer.rep_completed.is_connected(_on_rep):
		ExerciseRecognizer.rep_completed.disconnect(_on_rep)
	if ExerciseRecognizer.form_feedback.is_connected(_on_form):
		ExerciseRecognizer.form_feedback.disconnect(_on_form)

func update_score(score: int):
	score_label.text = "Score: " + str(score)

func update_time(time_left: float):
	timer_label.text = "Time: " + str(int(time_left))

func _on_rep():
	_update_labels()

func _on_form(message: String, is_good: bool):
	if not is_inside_tree(): return
	form_label.text = message
	if is_good:
		form_label.add_theme_color_override("font_color", Color("#22C55E"))
	else:
		form_label.add_theme_color_override("font_color", Color("#EF4444"))
	
	get_tree().create_timer(2.0).timeout.connect(
		func():
			if is_inside_tree(): form_label.text = ""
	)

func _update_labels():
	rep_label.text = "Reps: " + str(SessionManager.current_reps)
