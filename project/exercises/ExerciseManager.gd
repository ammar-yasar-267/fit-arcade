extends Node

## Autoload singleton. Registry of available exercises.
## Routes pose landmark data to the currently active exercise.

signal rep_completed(rep_count: int)
signal form_invalid(message: String)
signal exercise_changed(exercise_name: String)

var _exercises: Dictionary = {}
var _active_exercise: ExerciseBase = null

func _ready() -> void:
	_register_default_exercises()

func _register_default_exercises() -> void:
	register_exercise(ArmRaiseExercise.new())

func register_exercise(exercise: ExerciseBase) -> void:
	_exercises[exercise.exercise_name] = exercise

func get_exercise_names() -> Array:
	return _exercises.keys()

func get_active_exercise() -> ExerciseBase:
	return _active_exercise

func set_active_exercise(exercise_name: String) -> bool:
	if not _exercises.has(exercise_name):
		return false

	if _active_exercise:
		_active_exercise.stop()
		# Disconnect old signals
		if _active_exercise.rep_completed.is_connected(_on_rep_completed):
			_active_exercise.rep_completed.disconnect(_on_rep_completed)
		if _active_exercise.form_invalid.is_connected(_on_form_invalid):
			_active_exercise.form_invalid.disconnect(_on_form_invalid)

	_active_exercise = _exercises[exercise_name]
	_active_exercise.rep_completed.connect(_on_rep_completed)
	_active_exercise.form_invalid.connect(_on_form_invalid)
	exercise_changed.emit(exercise_name)
	return true

func start_exercise() -> void:
	if _active_exercise:
		_active_exercise.start()

func stop_exercise() -> void:
	if _active_exercise:
		_active_exercise.stop()

## Called by PoseLandmarker each frame with new landmark data
func process_landmarks(landmarks: MediaPipeNormalizedLandmarks) -> void:
	if _active_exercise and _active_exercise.is_active:
		_active_exercise.analyze_landmarks(landmarks)

func _on_rep_completed(count: int) -> void:
	rep_completed.emit(count)

func _on_form_invalid(message: String) -> void:
	form_invalid.emit(message)
