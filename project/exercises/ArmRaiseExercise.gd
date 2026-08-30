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

func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	var l_hip = get_landmark_pos(landmarks, HIP_INDEX)
	var l_shoulder = get_landmark_pos(landmarks, SHOULDER_INDEX)
	var l_wrist = get_landmark_pos(landmarks, WRIST_INDEX)
	var left_angle = calculate_angle(l_hip, l_shoulder, l_wrist)

	var r_hip = get_landmark_pos(landmarks, R_HIP_INDEX)
	var r_shoulder = get_landmark_pos(landmarks, R_SHOULDER_INDEX)
	var r_wrist = get_landmark_pos(landmarks, R_WRIST_INDEX)
	var right_angle = calculate_angle(r_hip, r_shoulder, r_wrist)

	var max_angle = max(left_angle, right_angle)
	var min_angle = min(left_angle, right_angle)
	var thresholds = _get_angle_thresholds()
	var start_max = thresholds.get("start_max", 30.0)
	var end_min = thresholds.get("end_min", 150.0)

	# Both arms must be down for start, both must be raised for end
	var is_start = max_angle <= start_max
	var is_end = min_angle >= end_min
	
	match current_state:
		ExerciseRecognizer.State.IDLE, ExerciseRecognizer.State.REP_COUNTED, ExerciseRecognizer.State.INVALID:
			if is_start:
				return ExerciseRecognizer.State.START_POSITION
			return ExerciseRecognizer.State.IDLE
		ExerciseRecognizer.State.START_POSITION:
			if is_end:
				return ExerciseRecognizer.State.END_POSITION
			elif not is_start and not is_end:
				return ExerciseRecognizer.State.MOVEMENT_PHASE
		ExerciseRecognizer.State.MOVEMENT_PHASE:
			if is_end:
				return ExerciseRecognizer.State.END_POSITION
			elif is_start:
				return ExerciseRecognizer.State.START_POSITION
		ExerciseRecognizer.State.END_POSITION:
			return ExerciseRecognizer.State.REP_COUNTED
			
	return current_state
