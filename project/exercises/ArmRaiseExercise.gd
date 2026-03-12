class_name ArmRaiseExercise
extends ExerciseBase

## Arm Raise exercise detector.
## Tracks the angle at the shoulder (hip-shoulder-wrist).
## Start: arms at sides (angle < 30°)
## End: arms raised overhead (angle > 150°)
##
## MediaPipe Pose landmark indices:
##   Left:  hip=23, shoulder=11, wrist=15
##   Right: hip=24, shoulder=12, wrist=16
## We use the LEFT side by default; could average both for robustness.

## Landmark indices: hip(23) - shoulder(11) - wrist(15)
const HIP_INDEX := 23
const SHOULDER_INDEX := 11
const WRIST_INDEX := 15

## Right side for averaging
const R_HIP_INDEX := 24
const R_SHOULDER_INDEX := 12
const R_WRIST_INDEX := 16

func _init() -> void:
	exercise_name = "Arm Raises"

func _get_angle_thresholds() -> Dictionary:
	return {
		"start_max": Settings.arm_raise_start_max,
		"end_min": Settings.arm_raise_end_min,
	}

func _get_landmark_indices() -> Array[int]:
	# hip - shoulder - wrist (angle measured at shoulder)
	return [HIP_INDEX, SHOULDER_INDEX, WRIST_INDEX]

func _get_form_correction_message() -> String:
	return "Raise your arms smoothly overhead"

## Override to use average of both arms for more robust detection
func analyze_landmarks(landmarks: MediaPipeNormalizedLandmarks) -> void:
	if not is_active:
		return

	# Left side
	var l_hip := get_landmark_pos(landmarks, HIP_INDEX)
	var l_shoulder := get_landmark_pos(landmarks, SHOULDER_INDEX)
	var l_wrist := get_landmark_pos(landmarks, WRIST_INDEX)
	var left_angle := calculate_angle(l_hip, l_shoulder, l_wrist)

	# Right side
	var r_hip := get_landmark_pos(landmarks, R_HIP_INDEX)
	var r_shoulder := get_landmark_pos(landmarks, R_SHOULDER_INDEX)
	var r_wrist := get_landmark_pos(landmarks, R_WRIST_INDEX)
	var right_angle := calculate_angle(r_hip, r_shoulder, r_wrist)

	# Use the leading arm so one weak/noisy side does not suppress rep detection.
	var rep_angle: float = max(left_angle, right_angle)
	_update_fsm(rep_angle)
