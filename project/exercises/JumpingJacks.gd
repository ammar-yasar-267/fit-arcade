extends ExerciseBase

func _init():
	exercise_name = "Jumping Jacks"

var frame_counter = 0

func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	var l_hip = get_landmark_pos(landmarks, 23)
	var r_hip = get_landmark_pos(landmarks, 24)
	var l_shoulder = get_landmark_pos(landmarks, 11)
	var r_shoulder = get_landmark_pos(landmarks, 12)
	var l_wrist = get_landmark_pos(landmarks, 15)
	var r_wrist = get_landmark_pos(landmarks, 16)
	var l_ankle = get_landmark_pos(landmarks, 27)
	var r_ankle = get_landmark_pos(landmarks, 28)
	
	if l_ankle == Vector3.ZERO or r_ankle == Vector3.ZERO:
		return current_state
		
	# Arm angle (using max of both arms to be generous)
	var l_arm_angle = calculate_angle(l_hip, l_shoulder, l_wrist)
	var r_arm_angle = calculate_angle(r_hip, r_shoulder, r_wrist)
	var arm_angle = max(l_arm_angle, r_arm_angle)
	
	# Leg angle (angle between left ankle, hip center, right ankle)
	var hip_center = Vector3((l_hip.x + r_hip.x) / 2.0, (l_hip.y + r_hip.y) / 2.0, 0)
	var leg_angle = calculate_angle(l_ankle, hip_center, r_ankle)
	
	# Start: arms down at sides (angle < 60 degrees)
	var is_start = arm_angle < 60.0
	# End: arms raised (angle > 120 degrees) and legs spread (angle > 20 degrees)
	var is_end = arm_angle > 120.0 and leg_angle > 20.0
	
	frame_counter += 1
	if frame_counter % 15 == 0:
		print("JJ Debug | Arm Angle: %3.1f | Leg Angle: %3.1f" % [arm_angle, leg_angle])
	
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
