extends ExerciseBase

func _init():
	exercise_name = "Jumping Jacks"

var frame_counter = 0

func process_frame(landmarks: MediaPipeNormalizedLandmarks, current_state: ExerciseRecognizer.State) -> ExerciseRecognizer.State:
	var l_hip = get_landmark_pos(landmarks, PoseKeypoints.LEFT_HIP)
	var r_hip = get_landmark_pos(landmarks, PoseKeypoints.RIGHT_HIP)
	var l_shoulder = get_landmark_pos(landmarks, PoseKeypoints.LEFT_SHOULDER)
	var r_shoulder = get_landmark_pos(landmarks, PoseKeypoints.RIGHT_SHOULDER)
	var l_wrist = get_landmark_pos(landmarks, PoseKeypoints.LEFT_WRIST)
	var r_wrist = get_landmark_pos(landmarks, PoseKeypoints.RIGHT_WRIST)
	var l_ankle = get_landmark_pos(landmarks, PoseKeypoints.LEFT_ANKLE)
	var r_ankle = get_landmark_pos(landmarks, PoseKeypoints.RIGHT_ANKLE)

	var l_knee = get_landmark_pos(landmarks, PoseKeypoints.LEFT_KNEE)
	var r_knee = get_landmark_pos(landmarks, PoseKeypoints.RIGHT_KNEE)

	if (l_ankle == Vector3.ZERO or r_ankle == Vector3.ZERO) and (l_knee == Vector3.ZERO or r_knee == Vector3.ZERO):
		return current_state
		
	# Fallback to knees if ankles are missing
	var left_low = l_ankle if l_ankle != Vector3.ZERO else l_knee
	var right_low = r_ankle if r_ankle != Vector3.ZERO else r_knee
		
	# Arm angle (using max of both arms to be generous)
	var l_arm_angle = calculate_angle(l_hip, l_shoulder, l_wrist)
	var r_arm_angle = calculate_angle(r_hip, r_shoulder, r_wrist)
	var arm_angle = max(l_arm_angle, r_arm_angle)
	
	# Leg angle (angle between left leg-low, hip center, right leg-low)
	var hip_center = Vector3((l_hip.x + r_hip.x) / 2.0, (l_hip.y + r_hip.y) / 2.0, 0)
	var leg_angle = calculate_angle(left_low, hip_center, right_low)
	
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
