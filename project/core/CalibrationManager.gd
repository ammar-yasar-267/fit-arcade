extends Node

var baseline_posture: Dictionary = {}
var is_calibrated: bool = false

func analyze_calibration_pose(pose_landmarks) -> Dictionary:
	var result := {
		"ready": false,
		"is_present": false,
		"message": "",
		"detail": "",
		"missing": [],
	}

	if pose_landmarks == null:
		result.message = "Too close to camera"
		result.detail = "Body cut off — move 2–3 m away"
		result.is_present = false
		return result

	var landmarks = pose_landmarks.get_landmarks()
	if landmarks.size() < PoseKeypoints.NUM_KEYPOINTS:
		result.message = "Too close to camera"
		result.detail = "Body cut off — move 2–3 m away"
		result.is_present = false
		return result

	# 1. Presence check: are core torso landmarks visible?
	var nose = landmarks[PoseKeypoints.NOSE]
	var l_sh = landmarks[PoseKeypoints.LEFT_SHOULDER]
	var r_sh = landmarks[PoseKeypoints.RIGHT_SHOULDER]
	var l_hip = landmarks[PoseKeypoints.LEFT_HIP]
	var r_hip = landmarks[PoseKeypoints.RIGHT_HIP]

	var core_confidence = maxf(l_sh.visibility, r_sh.visibility)
	if core_confidence < 0.30 and nose.visibility < 0.30:
		# Nobody in frame
		result.is_present = false
		result.message = "Too close to camera"
		result.detail = "Body cut off — move 2–3 m away"
		return result

	result.is_present = true

	# 2. Too close check:
	# If player is standing right next to the camera, shoulders take up a huge portion of width,
	# or head is at top edge and hips are near bottom.
	var shoulder_width = abs(l_sh.x - r_sh.x)
	var is_too_close = shoulder_width > 0.44 or (nose.y < 0.05 and (l_hip.y > 0.80 or r_hip.y > 0.80))
	if is_too_close:
		result.message = "Too close to camera"
		result.detail = "Body cut off — move 2–3 m away"
		return result

	var game := GameManager.pending_game_name if typeof(GameManager) != TYPE_NIL else ""
	if game == "":
		game = "dino"

	var l_wr = landmarks[PoseKeypoints.LEFT_WRIST]
	var r_wr = landmarks[PoseKeypoints.RIGHT_WRIST]
	var l_el = landmarks[PoseKeypoints.LEFT_ELBOW]
	var r_el = landmarks[PoseKeypoints.RIGHT_ELBOW]
	var l_kn = landmarks[PoseKeypoints.LEFT_KNEE]
	var r_kn = landmarks[PoseKeypoints.RIGHT_KNEE]
	var l_ank = landmarks[PoseKeypoints.LEFT_ANKLE]
	var r_ank = landmarks[PoseKeypoints.RIGHT_ANKLE]

	match game:
		"dino":
			# JUMPING JACKS: Requires full body in frame (both ARMS and LEGS)
			# Arms check: wrists in bounds with good visibility, or elbows visible with vertical headroom
			var left_arm_ok = (l_wr.visibility >= 0.35 and l_wr.x >= 0.02 and l_wr.x <= 0.98 and l_wr.y >= 0.02 and l_wr.y <= 0.95) or (l_el.visibility >= 0.35 and l_el.x >= 0.05 and l_el.x <= 0.95 and l_el.y <= 0.85)
			var right_arm_ok = (r_wr.visibility >= 0.35 and r_wr.x >= 0.02 and r_wr.x <= 0.98 and r_wr.y >= 0.02 and r_wr.y <= 0.95) or (r_el.visibility >= 0.35 and r_el.x >= 0.05 and r_el.x <= 0.95 and r_el.y <= 0.85)
			var arms_ok = left_arm_ok and right_arm_ok

			# Legs check: knees must be clearly in frame (not cut off at bottom of screen)
			var left_knee_ok = l_kn.visibility >= 0.35 and l_kn.y >= 0.35 and l_kn.y <= 0.88 and l_kn.x >= 0.05 and l_kn.x <= 0.95
			var right_knee_ok = r_kn.visibility >= 0.35 and r_kn.y >= 0.35 and r_kn.y <= 0.88 and r_kn.x >= 0.05 and r_kn.x <= 0.95
			var ankles_ok = l_ank.visibility >= 0.30 and r_ank.visibility >= 0.30 and l_ank.y <= 0.98 and r_ank.y <= 0.98
			var knees_high = l_kn.y <= 0.80 and r_kn.y <= 0.80
			var legs_ok = left_knee_ok and right_knee_ok and (ankles_ok or knees_high)

			if not arms_ok and not legs_ok:
				result.missing = ["arms", "legs"]
				result.message = "Show your arms and legs"
				result.detail = "Step back so your full body from hands to feet is in frame."
			elif not arms_ok:
				result.missing = ["arms"]
				result.message = "Show your arms"
				result.detail = "Raise your arms into view for Jumping Jacks."
			elif not legs_ok:
				result.missing = ["legs"]
				result.message = "Show your legs"
				result.detail = "Step back so your legs are visible in frame."
			else:
				result.ready = true
				result.message = "Good framing"
				result.detail = "Hold steady and keep your full body in frame."

		"lane", "switcher":
			# SIDE LUNGES: Requires KNEES strictly in frame with clear lower body clearance
			var left_knee_ok = l_kn.visibility >= 0.35 and l_kn.y >= 0.35 and l_kn.y <= 0.88 and l_kn.x >= 0.05 and l_kn.x <= 0.95
			var right_knee_ok = r_kn.visibility >= 0.35 and r_kn.y >= 0.35 and r_kn.y <= 0.88 and r_kn.x >= 0.05 and r_kn.x <= 0.95
			# Both hips must be visible to ensure torso is framed
			var hips_ok = l_hip.visibility >= 0.35 and r_hip.visibility >= 0.35 and l_hip.y <= 0.75 and r_hip.y <= 0.75
			# Lower leg clearance: ankles visible or knees high enough that bending doesn't drop off screen
			var ankles_ok = l_ank.visibility >= 0.28 and r_ank.visibility >= 0.28 and l_ank.y <= 0.98 and r_ank.y <= 0.98
			var knees_clear = l_kn.y <= 0.80 and r_kn.y <= 0.80

			if not left_knee_ok or not right_knee_ok or not hips_ok or not (ankles_ok or knees_clear):
				result.missing = ["knees"]
				result.message = "Show your knees"
				result.detail = "Side Lunges needs your knees and legs clearly in frame."
			else:
				result.ready = true
				result.message = "Good framing"
				result.detail = "Hold steady and keep your body in frame."

		"flappy":
			# ARM RAISES: Requires ARMS in frame
			var left_arm_ok = (l_wr.visibility >= 0.35 and l_wr.x >= 0.02 and l_wr.x <= 0.98 and l_wr.y >= 0.02 and l_wr.y <= 0.95) or (l_el.visibility >= 0.35 and l_el.x >= 0.05 and l_el.x <= 0.95 and l_el.y <= 0.85)
			var right_arm_ok = (r_wr.visibility >= 0.35 and r_wr.x >= 0.02 and r_wr.x <= 0.98 and r_wr.y >= 0.02 and r_wr.y <= 0.95) or (r_el.visibility >= 0.35 and r_el.x >= 0.05 and r_el.x <= 0.95 and r_el.y <= 0.85)
			var shoulders_ok = l_sh.visibility >= 0.35 and r_sh.visibility >= 0.35

			if not left_arm_ok or not right_arm_ok or not shoulders_ok:
				result.missing = ["arms"]
				result.message = "Show your arms"
				result.detail = "Arm Raises needs your arms in frame."
			else:
				result.ready = true
				result.message = "Good framing"
				result.detail = "Hold steady and keep your arms in frame."

	return result

func compute_and_save_thresholds(pose_landmarks) -> bool:
	if pose_landmarks:
		var res = analyze_calibration_pose(pose_landmarks)
		if res.ready:
			baseline_posture = {"landmarks_detected": true}
			return true
	return false

func reset_calibration():
	is_calibrated = false
	baseline_posture.clear()
