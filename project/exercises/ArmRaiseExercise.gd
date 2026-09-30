class_name ArmRaiseExercise
extends ExerciseBase

## Arm Raise exercise detector.
## Tracks the angle at the shoulder (hip-shoulder-wrist).
## Start: arms at sides (angle < 30°)
## End: arms raised overhead (angle > 150°)
##
## Uses COCO-17 keypoint indices (see PoseKeypoints).
## We use the LEFT side by default; could average both for robustness.

const HIP_INDEX := PoseKeypoints.LEFT_HIP
const SHOULDER_INDEX := PoseKeypoints.LEFT_SHOULDER
const WRIST_INDEX := PoseKeypoints.LEFT_WRIST

## Right side for averaging
const R_HIP_INDEX := PoseKeypoints.RIGHT_HIP
const R_SHOULDER_INDEX := PoseKeypoints.RIGHT_SHOULDER
const R_WRIST_INDEX := PoseKeypoints.RIGHT_WRIST

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
	var r_hip = get_landmark_pos(landmarks, R_HIP_INDEX)
	var r_shoulder = get_landmark_pos(landmarks, R_SHOULDER_INDEX)
	var r_wrist = get_landmark_pos(landmarks, R_WRIST_INDEX)

	if l_hip == Vector3.ZERO or l_shoulder == Vector3.ZERO or l_wrist == Vector3.ZERO \
			or r_hip == Vector3.ZERO or r_shoulder == Vector3.ZERO or r_wrist == Vector3.ZERO:
		return current_state

	var left_angle = calculate_angle(l_hip, l_shoulder, l_wrist)
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
