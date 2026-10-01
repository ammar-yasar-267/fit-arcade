@tool
class_name SkeletonFigure
extends Control

## Procedural stick-figure skeleton pose animator.
## Accurately models human exercise biomechanics:
## - "dino": Jumping Jacks (feet jump wide, arms arc up to overhead clap)
## - "lane": Side Lunges (alternating left/right: knee bends deeply, hips lower, trailing leg stays straight, hands guard chest)
## - "flappy": Arm Raises (arms start resting at sides, arc wide outwards through T-pose up to high overhead 'V')
## Renders 100x130 viewBox uniformly into available rect.

@export var mode: String = "dino":
	set(v):
		mode = v
		queue_redraw()

@export_range(0.0, 1.0) var phase: float = 0.0:
	set(v):
		phase = v
		queue_redraw()

@export var pose_color: Color = Color("#D4FF3A"):
	set(v):
		pose_color = v
		queue_redraw()

@export var missing_limb: String = "": # "ARMS", "KNEES", "FEET", or ""
	set(v):
		missing_limb = v
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s: float = minf(size.x / 100.0, size.y / 130.0)
	var ox: float = (size.x - 100.0 * s) * 0.5
	var oy: float = (size.y - 130.0 * s) * 0.5
	var origin := Vector2(ox, oy)

	var limb_col = func(limb: String) -> Color:
		var is_missing := false
		var ml := missing_limb.to_upper()
		if ml == limb:
			is_missing = true
		elif ml.find("ARMS") != -1 and limb == "ARMS":
			is_missing = true
		elif (ml.find("LEGS") != -1 or ml.find("FEET") != -1 or ml.find("KNEES") != -1) and (limb == "FEET" or limb == "KNEES"):
			is_missing = true
		return Tokens.SIGNAL if is_missing else pose_color

	var pt = func(v: Vector2) -> Vector2:
		return origin + v * s

	# Default baseline skeleton coordinates (neutral standing in 100x130)
	var hip_x: float = 50.0
	var hip_y: float = 76.0
	var head_y: float = 20.0

	var lh := Vector2(32.0, 72.0)
	var rh := Vector2(68.0, 72.0)
	var le := Vector2(34.0, 56.0)
	var re := Vector2(66.0, 56.0)

	var lk := Vector2(45.0, 98.0)
	var rk := Vector2(55.0, 98.0)
	var lf := Vector2(43.0, 118.0)
	var rf := Vector2(57.0, 118.0)

	match mode:
		"flappy":
			# --- ARM RAISES / FLAPPY FLIGHT (Lateral Raises) ---
			# Biomechanics: Arms start resting at sides and raise laterally up to shoulder height
			# (straight out level with shoulders, 90° horizontal T-pose), never going beyond shoulder level.
			var t: float = 0.5 - 0.5 * cos(phase * TAU)
			var angle_rad: float = deg_to_rad(12.0 + t * 78.0) # 12° at sides up to 90° (shoulder level)

			var sh_lx: float = hip_x - 12.0
			var sh_rx: float = hip_x + 12.0
			var sh_y: float = hip_y - 36.0 # 40.0

			var arm_l1: float = 16.5 # upper arm
			var arm_l2: float = 16.5 # forearm

			# Left arm sweeps out laterally up to horizontal shoulder height
			le = Vector2(sh_lx - sin(angle_rad) * arm_l1, sh_y + cos(angle_rad) * arm_l1)
			lh = le + Vector2(-sin(angle_rad) * arm_l2, cos(angle_rad) * arm_l2)

			# Right arm sweeps out laterally up to horizontal shoulder height
			re = Vector2(sh_rx + sin(angle_rad) * arm_l1, sh_y + cos(angle_rad) * arm_l1)
			rh = re + Vector2(sin(angle_rad) * arm_l2, cos(angle_rad) * arm_l2)

		"lane":
			# --- SIDE LUNGES / LANE SWITCHER ---
			# Biomechanics: Alternating left and right side lunges.
			# Phase 0.0..0.5: Lunge to the Left (knee bends deeply, hips shift and drop, right leg stays straight).
			# Phase 0.5..1.0: Lunge to the Right (knee bends deeply, hips shift and drop, left leg stays straight).
			# Feet stay planted in a wide athletic stance.
			lf = Vector2(24.0, 118.0)
			rf = Vector2(76.0, 118.0)

			var dir_sign: float = -1.0 if phase < 0.5 else 1.0
			var sub_p: float = (phase / 0.5) if phase < 0.5 else ((phase - 0.5) / 0.5)
			var k: float = sin(sub_p * PI) # 0.0 at center, 1.0 at peak lunge depth

			# Hips shift in direction of lunge and drop down
			hip_x = 50.0 + dir_sign * 14.0 * k
			hip_y = 76.0 + 13.0 * k
			head_y = hip_y - 55.0

			var cur_hip_l := Vector2(hip_x - 8.0, hip_y)
			var cur_hip_r := Vector2(hip_x + 8.0, hip_y)

			if dir_sign < 0:
				# Lunging to LEFT: Left knee bends deeply, Right leg stays straight
				lk = Vector2(lerp(35.0, 21.0, k), lerp(97.0, 102.0, k))
				rk = cur_hip_r.lerp(rf, 0.5)
			else:
				# Lunging to RIGHT: Right knee bends deeply, Left leg stays straight
				rk = Vector2(lerp(65.0, 79.0, k), lerp(97.0, 102.0, k))
				lk = cur_hip_l.lerp(lf, 0.5)

			# Hands clasped in athletic counter-balance guard in front of chest
			le = Vector2(hip_x - 10.0, hip_y - 20.0)
			re = Vector2(hip_x + 10.0, hip_y - 20.0)
			lh = Vector2(hip_x - 3.0, hip_y - 23.0)
			rh = Vector2(hip_x + 3.0, hip_y - 23.0)

		"dino":
			# --- JUMPING JACKS / DINO RUNNER ---
			# Biomechanics: Jump out wide (feet spread, arms arc overhead) and back together.
			var t: float = 0.5 - 0.5 * cos(phase * TAU)
			hip_y = 76.0 - t * 4.0 # subtle upward jump bounce
			head_y = 20.0 - t * 4.0

			# Feet and knees jump wide
			lf = Vector2(lerp(43.0, 26.0, t), 118.0)
			rf = Vector2(lerp(57.0, 74.0, t), 118.0)
			lk = Vector2(lerp(45.0, 35.0, t), lerp(98.0, 96.0, t))
			rk = Vector2(lerp(55.0, 65.0, t), lerp(98.0, 96.0, t))

			# Arms arc wide outward and meet in high overhead clap
			var jj_angle: float = deg_to_rad(15.0 + t * 150.0)
			var sh_lx: float = hip_x - 12.0
			var sh_rx: float = hip_x + 12.0
			var sh_y: float = hip_y - 36.0

			le = Vector2(sh_lx - sin(jj_angle * 0.95) * 16.5, sh_y + cos(jj_angle * 0.95) * 16.5)
			lh = le + Vector2(-sin(jj_angle) * 16.5, cos(jj_angle) * 16.5)

			re = Vector2(sh_rx + sin(jj_angle * 0.95) * 16.5, sh_y + cos(jj_angle * 0.95) * 16.5)
			rh = re + Vector2(sin(jj_angle) * 16.5, cos(jj_angle) * 16.5)

	# --- Drawing Anatomy ---
	var sh_left := Vector2(hip_x - 12.0, hip_y - 36.0)
	var sh_right := Vector2(hip_x + 12.0, hip_y - 36.0)
	var hip_left := Vector2(hip_x - 8.0, hip_y)
	var hip_right := Vector2(hip_x + 8.0, hip_y)

	var spine_top := Vector2(hip_x, hip_y - 46.0)
	var spine_bot := Vector2(hip_x, hip_y)

	# 1. Head: circle at (hip_x, head_y), r=8
	var head_center = pt.call(Vector2(hip_x, head_y))
	draw_arc(head_center, 8.0 * s, 0, TAU, 32, pose_color, 2.0 * s, true)

	# 2. Spine, Shoulders, Hips
	draw_line(pt.call(spine_top), pt.call(spine_bot), pose_color, 2.4 * s, true)
	draw_line(pt.call(sh_left), pt.call(sh_right), pose_color, 2.4 * s, true)
	draw_line(pt.call(hip_left), pt.call(hip_right), pose_color, 2.4 * s, true)

	# 3. Arms: shoulder -> elbow -> hand
	var col_arms: Color = limb_col.call("ARMS")
	var pt_sh_l = pt.call(sh_left)
	var pt_sh_r = pt.call(sh_right)
	var pt_le = pt.call(le)
	var pt_re = pt.call(re)
	var pt_lh = pt.call(lh)
	var pt_rh = pt.call(rh)

	draw_polyline(PackedVector2Array([pt_sh_l, pt_le, pt_lh]), col_arms, 2.4 * s, true)
	draw_polyline(PackedVector2Array([pt_sh_r, pt_re, pt_rh]), col_arms, 2.4 * s, true)

	# 4. Thighs
	var col_knees: Color = limb_col.call("KNEES")
	var pt_lk = pt.call(lk)
	var pt_rk = pt.call(rk)
	draw_line(pt.call(hip_left), pt_lk, col_knees, 2.4 * s, true)
	draw_line(pt.call(hip_right), pt_rk, col_knees, 2.4 * s, true)

	# 5. Shins
	var col_feet: Color = limb_col.call("FEET")
	var pt_lf = pt.call(lf)
	var pt_rf = pt.call(rf)
	draw_line(pt_lk, pt_lf, col_feet, 2.4 * s, true)
	draw_line(pt_rk, pt_rf, col_feet, 2.4 * s, true)

	# 6. Joints: circle r=2.6, fill ink, stroke 1.6
	var draw_joint = func(p: Vector2, c: Color) -> void:
		draw_circle(p, 2.6 * s, Tokens.INK)
		draw_arc(p, 2.6 * s, 0, TAU, 16, c, 1.6 * s, true)

	draw_joint.call(pt_lh, col_arms)
	draw_joint.call(pt_rh, col_arms)
	draw_joint.call(pt_le, col_arms)
	draw_joint.call(pt_re, col_arms)
	draw_joint.call(pt_lk, col_knees)
	draw_joint.call(pt_rk, col_knees)
	draw_joint.call(pt_lf, col_feet)
	draw_joint.call(pt_rf, col_feet)
	draw_joint.call(pt_sh_l, pose_color)
	draw_joint.call(pt_sh_r, pose_color)
