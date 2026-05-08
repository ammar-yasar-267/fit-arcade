class_name ExerciseBase
extends RefCounted

## Base class for exercise detection using FSM-based rep counting.
## Subclasses override thresholds and landmark indices for specific exercises.

var exercise_name: String = "Base Exercise"

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

## Main entry point — called by ExerciseRecognizer each frame
func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	return ExerciseRecognizer.State.IDLE
