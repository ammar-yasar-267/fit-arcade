extends Node

enum State {IDLE, START_POSITION, MOVEMENT_PHASE, END_POSITION, REP_COUNTED, INVALID}

signal rep_completed
signal form_feedback(message, is_good)
signal pose_processed(landmarks)

var current_exercise = null
var current_state: State = State.IDLE
var available_exercises = {}

func _ready():
	available_exercises["Jumping Jacks"] = preload("res://exercises/JumpingJacks.gd").new()
	available_exercises["Lunges"] = preload("res://exercises/Lunges.gd").new()
	available_exercises["Arm Raises"] = preload("res://exercises/ArmRaiseExercise.gd").new()

func set_active_exercise(exercise_name: String):
	if available_exercises.has(exercise_name):
		current_exercise = available_exercises[exercise_name]
		current_state = State.IDLE

func process_pose(landmarks):
	emit_signal("pose_processed", landmarks)
	if current_exercise == null: return
	
	var new_state = current_exercise.process_frame(landmarks, current_state)
	if new_state != current_state:
		_on_state_changed(new_state)
		current_state = new_state

func _on_state_changed(new_state: State):
	if new_state == State.REP_COUNTED:
		SessionManager.add_rep()
		emit_signal("rep_completed")
		emit_signal("form_feedback", "Great form!", true)
		current_state = State.IDLE # Reset for next rep
	elif new_state == State.INVALID:
		emit_signal("form_feedback", "Form broken, resetting", false)
		current_state = State.IDLE # Reset to idle
