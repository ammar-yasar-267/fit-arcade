class_name ExerciseBase
extends RefCounted

## Base class for exercise detection using FSM-based rep counting.
## Subclasses override thresholds and landmark indices for specific exercises.

signal rep_completed(rep_count: int)
signal form_invalid(message: String)
signal state_changed(new_state: int)

## FSM states per SRS §3.5.1
enum State {
	IDLE,
	START_POSITION,
	MOVEMENT_PHASE,
	END_POSITION,
	REP_COUNTED,
}

var exercise_name: String = "Base Exercise"
var rep_count: int = 0
var current_state: State = State.IDLE
var is_active: bool = false

## Override in subclass — angle thresholds for form validation
## Returns: { "start_max": float, "end_min": float }
func _get_angle_thresholds() -> Dictionary:
	return {"start_max": 30.0, "end_min": 150.0}

## Override in subclass — which landmark indices to track
## Returns: [point_a, joint_b, point_c] for angle calculation
func _get_landmark_indices() -> Array[int]:
	return [0, 0, 0]

## Override in subclass — form validation message
func _get_form_correction_message() -> String:
	return "Check your form"

## Calculate 2D angle at joint b formed by points a-b-c (in degrees), ignoring Z
static func calculate_angle(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ba := Vector2(a.x - b.x, a.y - b.y)
	var bc := Vector2(c.x - b.x, c.y - b.y)
	var cosine := ba.dot(bc) / (ba.length() * bc.length() + 0.0001)
	cosine = clampf(cosine, -1.0, 1.0)
	return rad_to_deg(acos(cosine))

## Extract a landmark position as Vector3 from normalized landmarks
static func get_landmark_pos(landmarks: MediaPipeNormalizedLandmarks, index: int) -> Vector3:
	var landmark_list = landmarks.get_landmarks()
	if index < landmark_list.size():
		var pt = landmark_list[index]
		return Vector3(pt.x, pt.y, pt.z)
	return Vector3.ZERO

## Main entry point — call each frame with new landmark data
func analyze_landmarks(landmarks: MediaPipeNormalizedLandmarks) -> void:
	if not is_active:
		return

	var indices := _get_landmark_indices()
	if indices.size() < 3:
		return

	var a := get_landmark_pos(landmarks, indices[0])
	var b := get_landmark_pos(landmarks, indices[1])
	var c := get_landmark_pos(landmarks, indices[2])
	var angle := calculate_angle(a, b, c)

	_update_fsm(angle)

## FSM state transitions
func _update_fsm(angle: float) -> void:
	var thresholds := _get_angle_thresholds()
	var start_max: float = thresholds.get("start_max", 30.0)
	var end_min: float = thresholds.get("end_min", 150.0)
	var prev_state := current_state

	match current_state:
		State.IDLE:
			if angle <= start_max:
				current_state = State.START_POSITION
		State.START_POSITION:
			if angle >= end_min:
				# Frame was skipped — jumped straight past movement window, still count it.
				current_state = State.END_POSITION
			elif angle > start_max:
				current_state = State.MOVEMENT_PHASE
		State.MOVEMENT_PHASE:
			if angle >= end_min:
				current_state = State.END_POSITION
			elif angle <= start_max:
				# Went back to start without completing
				current_state = State.START_POSITION
		State.END_POSITION:
			rep_count += 1
			current_state = State.REP_COUNTED
			rep_completed.emit.call_deferred(rep_count)
		State.REP_COUNTED:
			# Wait for arms to come back down to start next rep
			if angle <= start_max:
				current_state = State.START_POSITION

	if current_state != prev_state:
		state_changed.emit.call_deferred(current_state)

func start() -> void:
	is_active = true
	rep_count = 0
	current_state = State.IDLE

func stop() -> void:
	is_active = false
	current_state = State.IDLE
