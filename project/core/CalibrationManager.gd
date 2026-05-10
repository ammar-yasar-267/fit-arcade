extends Node

var baseline_posture: Dictionary = {}
var is_calibrated: bool = false

func analyze_calibration_pose(pose_landmarks) -> Dictionary:
	var result := {
		"ready": false,
		"message": "",
		"detail": "",
		"missing": [],
	}

	if pose_landmarks == null:
		result.message = "Waiting for your pose"
		result.detail = "Step into the camera view so I can see your full body."
		return result

	var landmarks = pose_landmarks.get_landmarks()
	if landmarks.size() < 33:
		result.message = "Pose not fully detected"
		result.detail = "Keep your full body in frame until all key points are visible."
		return result

	var missing_parts: Array[String] = []
	# Decide which key points are required based on the selected pending game
	var game := GameManager.pending_game_name if typeof(GameManager) != TYPE_NIL else ""
	var key_points = []

	# Default: require head + wrists + ankles (full-body)
	key_points = [
		{"idx": 0, "name": "your head", "hint": "Lift your chin into frame"},
		{"idx": 15, "name": "your left wrist", "hint": "Raise your left arm into view"},
		{"idx": 16, "name": "your right wrist", "hint": "Raise your right arm into view"},
		{"idx": 27, "name": "your left ankle", "hint": "Step back so your left foot is visible"},
		{"idx": 28, "name": "your right ankle", "hint": "Step back so your right foot is visible"},
	]

	if game == "flappy":
		# Flappy only needs the arms (wrists) and head for orientation
		key_points = [
			{"idx": 0, "name": "your head", "hint": "Keep your head visible"},
			{"idx": 15, "name": "your left wrist", "hint": "Raise your left arm into view"},
			{"idx": 16, "name": "your right wrist", "hint": "Raise your right arm into view"},
		]
	elif game == "dino":
		# Dino (jumping) needs feet and maybe head
		key_points = [
			{"idx": 0, "name": "your head", "hint": "Keep your head visible"},
			{"idx": 27, "name": "your left ankle", "hint": "Step back so your left foot is visible"},
			{"idx": 28, "name": "your right ankle", "hint": "Step back so your right foot is visible"},
		]
	elif game == "switcher":
		# Switcher (lunges) now only needs knees instead of ankles
		key_points = [
			{"idx": 0, "name": "your head", "hint": "Keep your head visible"},
			{"idx": 25, "name": "your left knee", "hint": "Step back so your knees are visible"},
			{"idx": 26, "name": "your right knee", "hint": "Step back so your knees are visible"},
		]

	for point in key_points:
		var pt = landmarks[point.idx]
		var x_ok = true
		var y_ok = true

		# By default allow a small off-screen margin
		var x_min = -0.1
		var x_max = 1.1
		var y_min = -0.1
		var y_max = 1.1

		# Relax horizontal bounds for wrists if they are raised upward (y small)
		if point.name.find("wrist") != -1:
			if pt.y < 0.18:
				x_min = -0.25
				x_max = 1.25

		if pt.x < x_min or pt.x > x_max:
			x_ok = false
		if pt.y < y_min or pt.y > y_max:
			y_ok = false

		if not (x_ok and y_ok):
			missing_parts.append(point.name)
			result.missing.append(point.name)

	if missing_parts.is_empty():
		result.ready = true
		result.message = "Good framing"
		result.detail = "Hold steady and keep your full body in frame for a moment."
	else:
		result.message = "Adjust your framing"
		result.detail = _build_missing_detail(missing_parts, key_points)

	return result

func _build_missing_detail(missing_parts: Array[String], key_points: Array) -> String:
	if missing_parts.is_empty():
		return "Hold steady and keep your full body in frame."

	var hints: Array[String] = []
	for part_name in missing_parts:
		for point in key_points:
			if point.name == part_name:
				hints.append(point.hint)
				break

	if hints.size() == 1:
		return hints[0]

	if hints.size() == 2:
		return "%s and %s" % [hints[0], hints[1]]

	return "%s, %s, and %s" % [hints[0], hints[1], hints[2]]

func compute_and_save_thresholds(pose_landmarks):
	if pose_landmarks:
		var landmarks = pose_landmarks.get_landmarks()
		if landmarks.size() >= 33:
			# Check if key points are within the screen bounds [0.0, 1.0]
			var key_indices = [0, 15, 16, 27, 28] # Nose, Wrists, Ankles
			var all_visible = true
			
			for idx in key_indices:
				var pt = landmarks[idx]
				if pt.x < -0.1 or pt.x > 1.1 or pt.y < -0.1 or pt.y > 1.1:
					all_visible = false
					break
					
			if all_visible:
				is_calibrated = true
				baseline_posture = {"landmarks_detected": true}
				return true
	return false

func reset_calibration():
	is_calibrated = false
	baseline_posture.clear()
