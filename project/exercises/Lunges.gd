extends ExerciseBase

## Lunge detection using knee bend angle (hip → knee → ankle).
## This gives a 50-80° signal change vs the ~0.06 unit hip-ratio change,
## making it far more robust against noise and distance variation.
## Asymmetry requirement (one knee bends much more than the other)
## rejects squats, sitting, and other symmetric bends.

func _init():
	exercise_name = "Lunges"

var lunge_side: int = -1

var frame_counter := 0
var hold_count := 0
var dropout_count := 0
const HOLD_REQUIRED := 3    # ~150ms at 20fps — user's lunges are shallow and brief
const DROPOUT_ALLOWED := 1  # tight: we don't want stale counts carrying over

func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	var l_hip   = get_landmark_pos(landmarks, 23)
	var r_hip   = get_landmark_pos(landmarks, 24)
	var l_knee  = get_landmark_pos(landmarks, 25)
	var r_knee  = get_landmark_pos(landmarks, 26)
	var l_ankle = get_landmark_pos(landmarks, 27)
	var r_ankle = get_landmark_pos(landmarks, 28)

	if l_hip == Vector3.ZERO or r_hip == Vector3.ZERO:
		return current_state
	if l_knee == Vector3.ZERO or r_knee == Vector3.ZERO:
		return current_state
	if l_ankle == Vector3.ZERO or r_ankle == Vector3.ZERO:
		# Ankles required for knee angle — user needs to step back from camera
		return current_state

	var l_angle = calculate_angle(l_hip, l_knee, l_ankle)
	var r_angle = calculate_angle(r_hip, r_knee, r_ankle)
	var min_angle  = min(l_angle, r_angle)
	var asymmetry  = abs(l_angle - r_angle)

	frame_counter += 1
	if frame_counter % 15 == 0:
		print("Lunge | L=%.1f° R=%.1f° asym=%.1f° hold=%d drop=%d | %s" % [l_angle, r_angle, asymmetry, hold_count, dropout_count, str(current_state)])

	# Standing:   both knees straight, min_angle > 155°
	# Lunge:      one knee clearly bent (< 140°) AND asymmetric (> 20°)
	#             Asymmetry rejects squats/sitting where both knees bend together.
	#             140° threshold based on observed data: user's lunges reach 126-140°.
	var is_start   = min_angle > 155.0
	var is_lunging = min_angle < 140.0 and asymmetry > 20.0

	if is_lunging:
		hold_count += 1
		dropout_count = 0
	else:
		dropout_count += 1
		if dropout_count > DROPOUT_ALLOWED:
			hold_count = 0

	var is_end = hold_count >= HOLD_REQUIRED

	# Side: whichever knee is more bent is the lunging leg
	if is_lunging:
		lunge_side = 0 if l_angle < r_angle else 1

	match current_state:
		ExerciseRecognizer.State.IDLE, ExerciseRecognizer.State.REP_COUNTED, ExerciseRecognizer.State.INVALID:
			if is_start:
				return ExerciseRecognizer.State.START_POSITION
			return ExerciseRecognizer.State.IDLE
		ExerciseRecognizer.State.START_POSITION:
			if is_end:
				return ExerciseRecognizer.State.END_POSITION
			elif not is_start:
				return ExerciseRecognizer.State.MOVEMENT_PHASE
		ExerciseRecognizer.State.MOVEMENT_PHASE:
			if is_end:
				return ExerciseRecognizer.State.END_POSITION
			elif is_start:
				return ExerciseRecognizer.State.START_POSITION
		ExerciseRecognizer.State.END_POSITION:
			hold_count = 0
			dropout_count = 0
			return ExerciseRecognizer.State.REP_COUNTED

	return current_state
