extends Node

var baseline_posture: Dictionary = {}
var is_calibrated: bool = false

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
