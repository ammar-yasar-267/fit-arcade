extends GameBase

@onready var rep_label: Label = $UI/RepLabel
@onready var state_label: Label = $UI/StateLabel
@onready var feedback_label: Label = $UI/FeedbackLabel

var feedback_timer := 0.0

func _init() -> void:
	game_name = "Rep Tester"

func _ready() -> void:
	# Keep background but size it to full screen
	var bg: ColorRect = $Background
	bg.size = get_viewport_rect().size
	
	if ExerciseManager.get_active_exercise():
		ExerciseManager.get_active_exercise().state_changed.connect(_on_state_changed)
	
	start_game()

func start_game() -> void:
	super ()
	rep_label.text = "0 Reps"
	state_label.text = "State: IDLE"
	feedback_label.text = "Get in position!"

func _process(delta: float) -> void:
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_label.text = ""

func on_rep_completed(rep_count: int) -> void:
	if not is_running:
		return
	rep_label.text = "%d Reps" % rep_count
	feedback_label.add_theme_color_override("font_color", Color.GREEN)
	feedback_label.text = "Good rep!"
	feedback_timer = 2.0

func on_form_invalid(message: String) -> void:
	if not is_running:
		return
	feedback_label.add_theme_color_override("font_color", Color.RED)
	feedback_label.text = message
	feedback_timer = 3.0

func _on_state_changed(new_state: int) -> void:
	if not is_running:
		return
	state_label.text = "State: %s" % _get_state_name(new_state)

func _get_state_name(state: int) -> String:
	match state:
		ExerciseBase.State.IDLE: return "IDLE"
		ExerciseBase.State.START_POSITION: return "START"
		ExerciseBase.State.MOVEMENT_PHASE: return "MOVING"
		ExerciseBase.State.END_POSITION: return "END"
		ExerciseBase.State.REP_COUNTED: return "REP!"
		_: return "?"
