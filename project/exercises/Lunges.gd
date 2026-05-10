extends ExerciseBase

## Lunge detection using hip descent ratio.
## Requires the descent to be SUSTAINED for several frames to reject jitter.
## Stores lunge_side (0=left, 1=right) at the moment the lunge peaks,
## based on which ankle is lower on screen (higher Y) — the leading foot.

func _init():
	exercise_name = "Lunges"

## Accessible by SwitcherGame to know which direction to switch
var lunge_side: int = -1

var frame_counter := 0
var hold_count := 0       # frames we've been above the END threshold
const HOLD_REQUIRED := 4  # must sustain for this many frames to confirm lunge

func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	var l_shoulder = get_landmark_pos(landmarks, 11)
	var r_shoulder = get_landmark_pos(landmarks, 12)
	var l_hip      = get_landmark_pos(landmarks, 23)
	var r_hip      = get_landmark_pos(landmarks, 24)
	var l_ankle    = get_landmark_pos(landmarks, 27)
	var r_ankle    = get_landmark_pos(landmarks, 28)
	var l_knee     = get_landmark_pos(landmarks, 25)
	var r_knee     = get_landmark_pos(landmarks, 26)

	# Use knees if ankles are missing to allow user to stand closer
	var lower_ref_y: float
	if l_ankle != Vector3.ZERO and r_ankle != Vector3.ZERO:
		lower_ref_y = (l_ankle.y + r_ankle.y) / 2.0
	elif l_knee != Vector3.ZERO and r_knee != Vector3.ZERO:
		# If using knees, we adjust the height to estimate where ankles would be
		lower_ref_y = ((l_knee.y + r_knee.y) / 2.0) + 0.15 
	else:
		hold_count = 0
		return current_state

	var shoulder_y  = (l_shoulder.y + r_shoulder.y) / 2.0
	var hip_y       = (l_hip.y     + r_hip.y)      / 2.0
	var body_height = lower_ref_y - shoulder_y + 0.001
	var hip_ratio   = (hip_y - shoulder_y) / body_height

	# Clamp to ignore wild tracking artifacts
	if hip_ratio < 0.0 or hip_ratio > 2.0:
		hold_count = 0
		return current_state

	frame_counter += 1
	if frame_counter % 20 == 0:
		print("Lunge Debug | hip_ratio: %.3f | hold: %d | state: %s" % [hip_ratio, hold_count, str(current_state)])

	# Adjusted sensitivity for better detection when closer
	# Standing: ~0.40–0.47
	# Lunge:    ~0.49–0.58
	var is_start = hip_ratio < 0.45
	
	if hip_ratio > 0.49:
		hold_count += 1
	else:
		hold_count = 0
		
	var is_end = hold_count >= 3 # Reduced hold required for snappier detection

	# Side detection: compare ankles if possible, otherwise use knees
	if hip_ratio > 0.47:
		var left_lower = l_ankle.y if l_ankle != Vector3.ZERO else l_knee.y
		var right_lower = r_ankle.y if r_ankle != Vector3.ZERO else r_knee.y
		
		if left_lower > right_lower:
			lunge_side = 1  # Right foot forward
		else:
			lunge_side = 0  # Left foot forward

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
			hold_count = 0
			return ExerciseRecognizer.State.REP_COUNTED

	return current_state
