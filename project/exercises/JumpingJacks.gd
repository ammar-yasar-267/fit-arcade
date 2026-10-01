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
		
	# Fallback to elbows if wrists are missing
	var l_hand = l_wrist if l_wrist != Vector3.ZERO else get_landmark_pos(landmarks, PoseKeypoints.LEFT_ELBOW)
	var r_hand = r_wrist if r_wrist != Vector3.ZERO else get_landmark_pos(landmarks, PoseKeypoints.RIGHT_ELBOW)
	if l_hand == Vector3.ZERO or r_hand == Vector3.ZERO or l_shoulder == Vector3.ZERO or r_shoulder == Vector3.ZERO:
		return current_state
		
	# Arm angles for both arms
	var l_arm_angle = calculate_angle(l_hip, l_shoulder, l_hand)
	var r_arm_angle = calculate_angle(r_hip, r_shoulder, r_hand)
	var max_arm_angle = max(l_arm_angle, r_arm_angle)
	
	# Leg metrics: angle and spread ratio relative to hip width
	var hip_center = Vector3((l_hip.x + r_hip.x) / 2.0, (l_hip.y + r_hip.y) / 2.0, 0)
	var leg_angle = calculate_angle(left_low, hip_center, right_low)
	var hip_width = abs(l_hip.x - r_hip.x)
	var leg_spread = abs(left_low.x - right_low.x)
	var spread_ratio = leg_spread / maxf(hip_width, 0.001) if hip_width > 0.01 else 1.0
	
	# Start: arms down at sides AND legs together
	var arms_down = l_arm_angle < 55.0 and r_arm_angle < 55.0
	var legs_together = leg_angle < 22.0 or spread_ratio < 1.35
	var is_start = arms_down and legs_together

	# End: both arms raised overhead AND legs jumped wide
	var arms_up = l_arm_angle > 90.0 and r_arm_angle > 90.0 and max_arm_angle > 115.0
	var legs_spread = leg_angle > 26.0 and spread_ratio > 1.45
	var is_end = arms_up and legs_spread
	
	frame_counter += 1
	if frame_counter % 15 == 0:
		print("JJ Debug | Arms: L=%.1f R=%.1f | Leg Angle: %.1f | SpreadRatio: %.2f | start=%s end=%s" % [l_arm_angle, r_arm_angle, leg_angle, spread_ratio, str(is_start), str(is_end)])
	
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
