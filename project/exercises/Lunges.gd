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

	if l_ankle == Vector3.ZERO or r_ankle == Vector3.ZERO:
		hold_count = 0
		return current_state

	var shoulder_y  = (l_shoulder.y + r_shoulder.y) / 2.0
	var hip_y       = (l_hip.y     + r_hip.y)      / 2.0
	var ankle_y     = (l_ankle.y   + r_ankle.y)    / 2.0
	var body_height = ankle_y - shoulder_y + 0.001
	var hip_ratio   = (hip_y - shoulder_y) / body_height

	# Clamp to ignore wild tracking artifacts (like the 3.689 spike)
	if hip_ratio < 0.0 or hip_ratio > 1.5:
		hold_count = 0
		return current_state

	frame_counter += 1
	if frame_counter % 15 == 0:
		print("Lunge Debug | hip_ratio: %.3f | hold: %d | state: %s" % [hip_ratio, hold_count, str(current_state)])

	# Calibrated from user data:
	#   Standing: ~0.40–0.49   → is_start when < 0.46
	#   Lunge:    ~0.50–0.56   → is_end when > 0.50 sustained
	var is_start = hip_ratio < 0.46

	# For END we use a sustained hold counter to reject single-frame spikes
	if hip_ratio > 0.50:
		hold_count += 1
	else:
		hold_count = 0

	var is_end = hold_count >= HOLD_REQUIRED

	# Front camera mirrors horizontally, so left ankle in landmark space
	# = user's RIGHT foot in real life. Swap accordingly.
	if hip_ratio > 0.48:
		if l_ankle.y > r_ankle.y:
			lunge_side = 1  # left ankle lower in camera = right foot forward
		else:
			lunge_side = 0  # right ankle lower in camera = left foot forward

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
