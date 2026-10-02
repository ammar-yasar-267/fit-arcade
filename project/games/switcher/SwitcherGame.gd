extends GameBase

## FitArcade — Lane Switcher (Enhanced Cyber-Arcade Edition)
## Mode: "lane" / "switcher" | Exercise: "Side Lunges" | Theme: CYAN (#3AE0FF)
## Featuring intelligent knee-balance wave generation to ensure equal left/right loading,
## 3D perspective cyber-tunnel, banking pod animations, energy shields, and procedural audio.

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Runner-Pod.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Laser-Barricade.svg")

signal shields_changed(current: int, max_val: int)
signal combo_changed(combo_val: int)
signal balance_changed(left: int, right: int, symmetry_pct: int)

# --- Scene Node References ---
var hud: CanvasLayer
var world_root: Node2D
var player: Sprite2D
var tunnel_drawer: Node2D
var obstacle_container: Node2D
var collectible_container: Node2D
var fx_container: Node2D
var popup_container: Node2D
var guide_container: Node2D

# --- Lane Coordinates (Nominal width 540, height 960) ---
const LANE_X: Array[float] = [110.0, 270.0, 430.0]
const PLAYER_Y := 740.0
const INITIAL_SPEED := 240.0
const MAX_SPEED := 360.0

# --- State Variables ---
var current_lane: int = 1         # 0 = Left, 1 = Center, 2 = Right
var target_x: float = 270.0
var current_speed: float = INITIAL_SPEED
var has_started: bool = false
var game_time: float = 0.0
var spawn_timer: float = 2.0
var distance_acc: float = 0.0
var bank_angle: float = 0.0
var _ghost_timer: float = 0.0

# --- Knee Balance System ---
var left_lunges: int = 0
var right_lunges: int = 0
var last_lunge_side: int = -1     # 0 = Left, 1 = Right
var consecutive_same_side: int = 0
var perfect_alternations: int = 0
var next_required_side: int = -1  # 0 = Left, 1 = Right, -1 = Neutral
var _guide_pill: PanelContainer
var _guide_label: Label
var _guide_style: StyleBoxFlat
var _guide_tween: Tween

# --- Health, Shields & Combos ---
const MAX_SHIELDS := 3
var shields := MAX_SHIELDS
var invulnerable_timer := 0.0
var combo := 1
var max_combo := 1

# --- Screen Shake & Tween Juice ---
var shake_duration := 0.0
var shake_magnitude := 0.0
var _player_tween: Tween

# --- In-Game Visual Elements ---
var _shield_aura: Node2D
var _thruster_left: CPUParticles2D
var _thruster_right: CPUParticles2D
var _spark_burst: CPUParticles2D

# --- Procedural SFX Audio Players ---
var _sfx_switch: AudioStreamPlayer
var _sfx_score: AudioStreamPlayer
var _sfx_core: AudioStreamPlayer
var _sfx_balance: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_combo: AudioStreamPlayer

func _ready() -> void:
	game_name = "Lane Switcher"
	ExerciseRecognizer.set_active_exercise("Lunges")

	hud = get_node_or_null("HUD")
	player = get_node_or_null("Player")
	obstacle_container = get_node_or_null("Obstacles")

	# Hide any legacy prototype background or lane ColorRects
	for child in get_children():
		if child is ColorRect:
			child.visible = false

	# World wrapper for screen shake
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	# Procedural 3D perspective tunnel
	tunnel_drawer = HighwayTunnelDrawer.new()
	tunnel_drawer.z_index = -10
	world_root.add_child(tunnel_drawer)

	if obstacle_container:
		remove_child(obstacle_container)
		world_root.add_child(obstacle_container)
	else:
		obstacle_container = Node2D.new()
		obstacle_container.name = "Obstacles"
		world_root.add_child(obstacle_container)
	obstacle_container.z_index = 0

	collectible_container = Node2D.new()
	collectible_container.name = "Collectibles"
	collectible_container.z_index = 2
	world_root.add_child(collectible_container)

	fx_container = Node2D.new()
	fx_container.name = "Effects"
	fx_container.z_index = 5
	world_root.add_child(fx_container)

	# Player Setup
	if not player:
		player = Sprite2D.new()
		player.name = "Player"
	else:
		remove_child(player)
	world_root.add_child(player)
	player.texture = PLAYER_TEXTURE
	player.centered = true
	player.scale = Vector2(0.85, 0.85)
	player.z_index = 10
	player.position = Vector2(LANE_X[1], PLAYER_Y)

	# Protective shield aura
	_shield_aura = SwitcherShieldRing.new()
	player.add_child(_shield_aura)

	popup_container = Node2D.new()
	popup_container.name = "FloatingPopups"
	popup_container.z_index = 25
	world_root.add_child(popup_container)

	guide_container = Node2D.new()
	guide_container.name = "NavGuides"
	guide_container.z_index = 8
	world_root.add_child(guide_container)

	_setup_particles()
	_setup_sfx()
	_setup_balance_ui()

	_update_shield_display()
	_update_combo_badge()
	_update_balance_display()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

# -----------------------------------------------------------------------------
# PARTICLES & SFX SETUP
# -----------------------------------------------------------------------------
func _setup_particles() -> void:
	var thruster_ramp := Gradient.new()
	thruster_ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.8, 1.0])
	thruster_ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.95),
		Tokens.CYAN,
		Color(0.0, 0.45, 0.8, 0.4),
		Color(0.05, 0.05, 0.1, 0.0)
	])

	# Left Ion Thruster
	_thruster_left = CPUParticles2D.new()
	_thruster_left.amount = 14
	_thruster_left.lifetime = 0.28
	_thruster_left.direction = Vector2(0, 1)
	_thruster_left.spread = 12.0
	_thruster_left.gravity = Vector2(0, 40)
	_thruster_left.initial_velocity_min = 60.0
	_thruster_left.initial_velocity_max = 110.0
	_thruster_left.scale_amount_min = 2.0
	_thruster_left.scale_amount_max = 4.0
	_thruster_left.color_ramp = thruster_ramp
	_thruster_left.position = Vector2(-16, 32)
	player.add_child(_thruster_left)

	# Right Ion Thruster
	_thruster_right = CPUParticles2D.new()
	_thruster_right.amount = 14
	_thruster_right.lifetime = 0.28
	_thruster_right.direction = Vector2(0, 1)
	_thruster_right.spread = 12.0
	_thruster_right.gravity = Vector2(0, 40)
	_thruster_right.initial_velocity_min = 60.0
	_thruster_right.initial_velocity_max = 110.0
	_thruster_right.scale_amount_min = 2.0
	_thruster_right.scale_amount_max = 4.0
	_thruster_right.color_ramp = thruster_ramp
	_thruster_right.position = Vector2(16, 32)
	player.add_child(_thruster_right)

	# Impact / Clearance Spark Burst
	_spark_burst = CPUParticles2D.new()
	_spark_burst.emitting = false
	_spark_burst.one_shot = true
	_spark_burst.amount = 26
	_spark_burst.lifetime = 0.45
	_spark_burst.explosiveness = 0.92
	_spark_burst.spread = 180.0
	_spark_burst.gravity = Vector2(0, 100)
	_spark_burst.initial_velocity_min = 80.0
	_spark_burst.initial_velocity_max = 210.0
	_spark_burst.scale_amount_min = 2.5
	_spark_burst.scale_amount_max = 5.0
	_spark_burst.color_ramp = thruster_ramp
	fx_container.add_child(_spark_burst)

func _setup_sfx() -> void:
	_sfx_switch = AudioStreamPlayer.new()
	_sfx_switch.stream = _create_procedural_tone(240.0, 520.0, 0.14, 0.40, "sine")
	add_child(_sfx_switch)

	_sfx_score = AudioStreamPlayer.new()
	_sfx_score.stream = _create_procedural_tone(640.0, 960.0, 0.12, 0.35, "sine")
	add_child(_sfx_score)

	_sfx_core = AudioStreamPlayer.new()
	_sfx_core.stream = _create_procedural_tone(980.0, 1440.0, 0.16, 0.45, "triangle")
	add_child(_sfx_core)

	_sfx_balance = AudioStreamPlayer.new()
	_sfx_balance.stream = _create_procedural_tone(523.0, 1046.0, 0.22, 0.45, "triangle")
	add_child(_sfx_balance)

	_sfx_hit = AudioStreamPlayer.new()
	_sfx_hit.stream = _create_procedural_tone(180.0, 45.0, 0.28, 0.50, "noise")
	add_child(_sfx_hit)

	_sfx_combo = AudioStreamPlayer.new()
	_sfx_combo.stream = _create_procedural_tone(480.0, 880.0, 0.18, 0.40, "square")
	add_child(_sfx_combo)

func _create_procedural_tone(f_start: float, f_end: float, duration: float, volume: float, type: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	var sample_count := int(duration * 22050.0)
	var buffer := PackedByteArray()
	buffer.resize(sample_count)
	var phase := 0.0

	for i in range(sample_count):
		var t := float(i) / float(sample_count)
		var freq := lerpf(f_start, f_end, t)
		phase += freq * (TAU / 22050.0)

		var wave := 0.0
		match type:
			"sine":
				wave = sin(phase)
			"triangle":
				wave = (2.0 / PI) * asin(sin(phase))
			"square":
				wave = 1.0 if sin(phase) >= 0.0 else -1.0
			"noise":
				wave = randf_range(-1.0, 1.0)

		var envelope := 1.0 - t
		if t < 0.08:
			envelope = t / 0.08
		var sample_val := int(clampf((wave * envelope * volume * 0.5 + 0.5) * 255.0, 0.0, 255.0))
		buffer[i] = sample_val

	stream.data = buffer
	return stream

# -----------------------------------------------------------------------------
# KNEE BALANCE & DIRECTIONAL NAVIGATION UI
# -----------------------------------------------------------------------------
func _setup_balance_ui() -> void:
	# Holographic Navigation Guide Capsule on Speedway (floating ahead of pod at Y=636)
	_guide_pill = PanelContainer.new()
	_guide_pill.name = "DodgeGuidancePill"
	_guide_pill.custom_minimum_size = Vector2(460, 42)
	_guide_pill.position = Vector2(40, 636)
	_guide_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_pill.pivot_offset = Vector2(230, 21)
	_guide_pill.visible = false

	_guide_style = StyleBoxFlat.new()
	_guide_style.bg_color = Color(0.04, 0.05, 0.08, 0.62)
	_guide_style.border_width_left = 1
	_guide_style.border_width_top = 1
	_guide_style.border_width_right = 1
	_guide_style.border_width_bottom = 1
	_guide_style.border_color = Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.35)
	_guide_style.corner_radius_top_left = 21
	_guide_style.corner_radius_top_right = 21
	_guide_style.corner_radius_bottom_left = 21
	_guide_style.corner_radius_bottom_right = 21
	_guide_style.content_margin_left = 16
	_guide_style.content_margin_right = 16
	_guide_style.content_margin_top = 4
	_guide_style.content_margin_bottom = 4
	_guide_pill.add_theme_stylebox_override("panel", _guide_style)
	guide_container.add_child(_guide_pill)

	_guide_label = Label.new()
	_guide_label.text = "◀   LUNGE LEFT OR RIGHT   ▶"
	_guide_label.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_guide_label.add_theme_font_size_override("font_size", 28)
	_guide_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	Tokens.make_legible(_guide_label, 4, 0.95)
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_guide_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_pill.add_child(_guide_label)

func _update_balance_display() -> void:
	if not _guide_label or not _guide_pill:
		return
	if not has_started or not is_running:
		_guide_pill.visible = false
		return
	else:
		_guide_pill.visible = true

	# Check active oncoming obstacles ahead of the player (between Y = -100 and Y = player.position.y)
	var blocked_ahead: Array[int] = []
	for obs in obstacle_container.get_children():
		if not obs.is_queued_for_deletion() and obs.position.y < player.position.y:
			var l: int = obs.get_meta("lane", -1)
			if l != -1 and not blocked_ahead.has(l):
				blocked_ahead.append(l)

	var target_text := ""
	var target_color := Tokens.WHITE
	var border_col := Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.30)

	if blocked_ahead.is_empty():
		next_required_side = -1
		target_text = "◀   LUNGE LEFT OR RIGHT   ▶"
		target_color = Color(1, 1, 1, 0.85)
		border_col = Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.30)
	elif blocked_ahead.has(current_lane):
		# Player is in direct line of fire — MUST DODGE!
		target_color = Tokens.CYAN
		border_col = Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.85)
		if current_lane == 0:
			next_required_side = 1
			target_text = "LUNGE RIGHT TO DODGE   ▶ ▶ ▶"
		elif current_lane == 2:
			next_required_side = 0
			target_text = "◀ ◀ ◀   LUNGE LEFT TO DODGE"
		else: # Center lane 1
			if blocked_ahead.has(0):
				next_required_side = 1
				target_text = "LUNGE RIGHT TO DODGE   ▶ ▶ ▶"
			else:
				next_required_side = 0
				target_text = "◀ ◀ ◀   LUNGE LEFT TO DODGE"
	else:
		# Hazards ahead, but current lane is clear! Player dodged safely!
		target_text = "✓   LANE CLEAR   ✓"
		target_color = Tokens.CYAN
		border_col = Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.65)

	if _guide_label.text != target_text:
		_guide_label.text = target_text
		_guide_label.add_theme_color_override("font_color", target_color)
		if _guide_style:
			_guide_style.border_color = border_col

		# Subtle micro-pulse when guidance state changes
		if is_running and has_started:
			if _guide_tween and _guide_tween.is_valid():
				_guide_tween.kill()
			_guide_tween = create_tween()
			_guide_tween.tween_property(_guide_pill, "scale", Vector2(1.04, 1.04), 0.08).set_ease(Tween.EASE_OUT)
			_guide_tween.tween_property(_guide_pill, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_IN)

# -----------------------------------------------------------------------------
# GAME START & LOOP
# -----------------------------------------------------------------------------
func start_game() -> void:
	super.start_game()
	current_lane = 1
	target_x = LANE_X[1]
	player.position = Vector2(target_x, PLAYER_Y)
	player.rotation_degrees = 0.0
	player.scale = Vector2(0.85, 0.85)
	player.visible = true

	current_speed = INITIAL_SPEED
	spawn_timer = 2.0
	game_time = 0.0
	has_started = false
	shields = MAX_SHIELDS
	invulnerable_timer = 0.0
	combo = 1
	max_combo = 1
	distance_acc = 0.0

	left_lunges = 0
	right_lunges = 0
	last_lunge_side = -1
	consecutive_same_side = 0
	perfect_alternations = 0
	next_required_side = -1

	_update_shield_display()
	_update_combo_badge()
	_update_balance_display()

	for obs in obstacle_container.get_children():
		obs.queue_free()
	for core in collectible_container.get_children():
		core.queue_free()

func _process(delta: float) -> void:
	if not is_running:
		return

	# Handle screen shake
	if shake_duration > 0.0:
		shake_duration -= delta
		var offset_x = randf_range(-shake_magnitude, shake_magnitude)
		var offset_y = randf_range(-shake_magnitude, shake_magnitude)
		world_root.position = Vector2(offset_x, offset_y)
		shake_magnitude = lerpf(shake_magnitude, 0.0, 10.0 * delta)
		if shake_duration <= 0.0:
			world_root.position = Vector2.ZERO

	if not has_started:
		# Idle hovering bob
		player.position.y = PLAYER_Y + sin(Time.get_ticks_msec() * 0.005) * 3.5
		return

	# Active progression
	game_time += delta
	current_speed = minf(INITIAL_SPEED + game_time * 2.8, MAX_SPEED)

	# Continuous Survival Distance Points (+8 points/sec)
	distance_acc += delta * 8.0
	if distance_acc >= 1.0:
		var pts = int(distance_acc)
		distance_acc -= pts
		add_score(pts)
		if hud: hud.update_score(score)

	# Invulnerability cooldown & shield flicker
	if invulnerable_timer > 0.0:
		invulnerable_timer -= delta
		player.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(invulnerable_timer * 28.0))
		if invulnerable_timer <= 0.0:
			player.modulate.a = 1.0

	# Smooth kinematic lane gliding & aerodynamic banking
	var dx := target_x - player.position.x
	player.position.x = lerpf(player.position.x, target_x, 12.0 * delta)

	# Aerodynamic roll banking into turns
	var target_bank := clampf(dx * 0.22, -20.0, 20.0)
	bank_angle = lerpf(bank_angle, target_bank, 14.0 * delta)
	player.rotation_degrees = bank_angle

	# Pod hovering bobbing while racing
	player.position.y = PLAYER_Y + sin(Time.get_ticks_msec() * 0.008) * 2.5

	# After-image speed trail during high-speed lane shifts
	if absf(dx) > 15.0 or current_speed > 280.0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = 0.065
			_spawn_afterimage()

	# Obstacle Spawning Loop
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_balanced_hazard_wave()
		var interval_min = 2.4 - (current_speed - INITIAL_SPEED) * 0.005
		var interval_max = 3.4 - (current_speed - INITIAL_SPEED) * 0.005
		spawn_timer = randf_range(max(interval_min, 1.9), max(interval_max, 2.8))

	# Move & Process Obstacles
	for obs in obstacle_container.get_children():
		if obs.is_queued_for_deletion():
			continue
		obs.position.y += current_speed * delta

		# Scoring when player safely passes the barricade
		if not obs.get_meta("scored") and obs.position.y > player.position.y:
			obs.set_meta("scored", true)
			_on_hazard_cleared(obs)

		# Cull offscreen
		if obs.position.y > 1020:
			obs.queue_free()
			continue

		# Collision Detection (Bounding Box)
		if invulnerable_timer <= 0.0:
			var obs_lane: int = obs.get_meta("lane", 1)
			# Collision triggers if player is currently in that lane and Y intersects
			var y_dist := absf(player.position.y - obs.position.y)
			var x_dist := absf(player.position.x - LANE_X[obs_lane])

			if y_dist < 42.0 and x_dist < 45.0:
				_on_hazard_hit(obs)

	# Move & Process Collectible Energy Cores
	for core in collectible_container.get_children():
		if core.is_queued_for_deletion():
			continue
		core.position.y += current_speed * delta

		if core.position.y > 1020:
			core.queue_free()
			continue

		if player.position.distance_to(core.position) < 46.0:
			_collect_energy_core(core)

	# Dynamic guidance update based on current lane vs impending hazards
	_update_balance_display()

# -----------------------------------------------------------------------------
# SMART KNEE-BALANCE WAVE GENERATION
# -----------------------------------------------------------------------------
func _spawn_balanced_hazard_wave() -> void:
	# Analyze current player position and knee loading history to compute safe path:
	var blocked_lanes: Array[int] = []
	var target_safe_lane: int = 1

	if current_lane == 0:
		# Player is in LEFT lane:
		# Hazard MUST block Lane 0. To survive, player MUST LUNGE RIGHT!
		blocked_lanes.append(0)
		target_safe_lane = 1 if randf() < 0.65 else 2
		next_required_side = 1

	elif current_lane == 2:
		# Player is in RIGHT lane:
		# Hazard MUST block Lane 2. To survive, player MUST LUNGE LEFT!
		blocked_lanes.append(2)
		target_safe_lane = 1 if randf() < 0.65 else 0
		next_required_side = 0

	else:
		# Player is in CENTER lane:
		# Check knee loading balance to choose which side to exercise!
		var lunge_diff := left_lunges - right_lunges

		if lunge_diff > 0:
			# Left knee has done more work! Force RIGHT lunge to balance:
			blocked_lanes.append(1)
			blocked_lanes.append(0)
			target_safe_lane = 2
			next_required_side = 1
		elif lunge_diff < 0:
			# Right knee has done more work! Force LEFT lunge to balance:
			blocked_lanes.append(1)
			blocked_lanes.append(2)
			target_safe_lane = 0
			next_required_side = 0
		else:
			# Balanced! Alternate based on last side:
			if last_lunge_side == 0:
				# Last was Left -> guide Right:
				blocked_lanes.append(1)
				blocked_lanes.append(0)
				target_safe_lane = 2
				next_required_side = 1
			else:
				# Last was Right -> guide Left:
				blocked_lanes.append(1)
				blocked_lanes.append(2)
				target_safe_lane = 0
				next_required_side = 0

	# Spawn the barricades in blocked lanes
	for b_lane in blocked_lanes:
		_create_barricade(b_lane, -60.0)

	# Place a bonus Volt Energy Core in the designated target safe lane!
	_create_energy_core(target_safe_lane, -60.0)

	_update_balance_display()

func _create_barricade(lane_idx: int, start_y: float) -> void:
	var obs := Node2D.new()
	obs.position = Vector2(LANE_X[lane_idx], start_y)
	obs.set_meta("lane", lane_idx)
	obs.set_meta("scored", false)

	var spr := Sprite2D.new()
	spr.texture = OBSTACLE_TEXTURE
	spr.centered = true
	spr.scale = Vector2(0.92, 0.92)
	obs.add_child(spr)

	# Pulsing hazard laser glow
	var aura := BarricadeHazardGlow.new()
	obs.add_child(aura)

	obstacle_container.add_child(obs)

func _create_energy_core(lane_idx: int, start_y: float) -> void:
	var core := VoltEnergyCore.new()
	core.position = Vector2(LANE_X[lane_idx], start_y)
	collectible_container.add_child(core)

# -----------------------------------------------------------------------------
# REP / LUNGE INPUT HANDLING
# -----------------------------------------------------------------------------
func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true

	var exercise = ExerciseRecognizer.current_exercise
	# lunge_side: 0 = Left Lunge, 1 = Right Lunge, -1 = Unspecified
	var side: int = -1
	if exercise and exercise.get("lunge_side") != null:
		side = exercise.lunge_side

	# If unspecified (e.g. Space pressed in center), determine side from target guide
	if side == -1:
		side = next_required_side if next_required_side != -1 else (0 if current_lane == 2 else 1)

	# Process knee balance
	var is_balanced_switch: bool = false
	if side == 0:
		left_lunges += 1
		if last_lunge_side == 1:
			is_balanced_switch = true
			perfect_alternations += 1
		last_lunge_side = 0
	elif side == 1:
		right_lunges += 1
		if last_lunge_side == 0:
			is_balanced_switch = true
			perfect_alternations += 1
		last_lunge_side = 1

	# Lane Navigation Logic
	var prev_lane = current_lane
	if side == 0: # Left Lunge
		if current_lane > 0:
			current_lane -= 1
		else:
			# At leftmost lane: bump rebound bounce
			_bump_lane_edge(-1)
	elif side == 1: # Right Lunge
		if current_lane < 2:
			current_lane += 1
		else:
			# At rightmost lane: bump rebound bounce
			_bump_lane_edge(1)

	target_x = LANE_X[current_lane]

	# Juicy Thruster Surge & Audio
	if current_lane != prev_lane:
		_trigger_lane_shift_fx(side)

	# Perfect Symmetry Bonus
	if is_balanced_switch:
		var bonus_pts := 150 * combo
		add_score(bonus_pts)
		if hud: hud.update_score(score)
		combo = mini(combo + 1, 5)
		max_combo = maxi(max_combo, combo)
		_update_combo_badge()
		_spawn_floating_text("PERFECT BALANCE! +%d" % bonus_pts, player.position + Vector2(0, -50), Tokens.CYAN)
		if _sfx_balance:
			_sfx_balance.play()

	_update_balance_display()

func _trigger_lane_shift_fx(side: int) -> void:
	if _sfx_switch:
		_sfx_switch.pitch_scale = randf_range(0.96, 1.08)
		_sfx_switch.play()

	# Boost thruster flares
	_thruster_left.amount = 26
	_thruster_right.amount = 26
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_callback(func():
		_thruster_left.amount = 14
		_thruster_right.amount = 14
	)

func _bump_lane_edge(dir: int) -> void:
	# Subtle spring bounce off edge barrier
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	player.position.x = LANE_X[current_lane] + dir * 16.0
	_player_tween = create_tween()
	_player_tween.tween_property(player, "position:x", LANE_X[current_lane], 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_add_screen_shake(0.12, 4.0)

## Desktop / Keyboard fallback for instant testing without webcam
func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT, KEY_A]:
			ExerciseRecognizer.trigger_debug_rep({"lunge_side": 0})
		elif event.keycode in [KEY_RIGHT, KEY_D]:
			ExerciseRecognizer.trigger_debug_rep({"lunge_side": 1})
		elif event.keycode in [KEY_SPACE, KEY_UP, KEY_ENTER]:
			var next_side := next_required_side if next_required_side != -1 else (0 if current_lane >= 2 else (1 if current_lane <= 0 else (randi() % 2)))
			ExerciseRecognizer.trigger_debug_rep({"lunge_side": next_side})

# -----------------------------------------------------------------------------
# HAZARDS, SHIELDS & SCORING
# -----------------------------------------------------------------------------
func _on_hazard_cleared(obs: Node2D) -> void:
	var pts := 100 * combo
	add_score(pts)
	if hud: hud.update_score(score)

	combo = mini(combo + 1, 5)
	max_combo = maxi(max_combo, combo)
	_update_combo_badge()

	_spawn_floating_text("+%d" % pts, obs.position, Tokens.CYAN)
	_trigger_spark_burst(obs.position, 16)

	if combo >= 3 and _sfx_combo:
		_sfx_combo.play()
	elif _sfx_score:
		_sfx_score.play()

func _collect_energy_core(core: Node2D) -> void:
	var core_pts := 50 * combo
	add_score(core_pts)
	if hud: hud.update_score(score)

	_spawn_floating_text("+%d CORE" % core_pts, core.position, Tokens.VOLT)
	_trigger_spark_burst(core.position, 22)

	if _sfx_core:
		_sfx_core.pitch_scale = randf_range(0.98, 1.1)
		_sfx_core.play()

	core.queue_free()

func _on_hazard_hit(obs: Node2D) -> void:
	shields -= 1
	_update_shield_display()
	combo = 1
	_update_combo_badge()

	_add_screen_shake(0.35, 14.0)
	if _sfx_hit:
		_sfx_hit.play()

	_trigger_spark_burst(obs.position, 28)
	obs.queue_free()

	if shields > 0:
		invulnerable_timer = 1.8
		_spawn_floating_text("-1 SHIELD!", player.position + Vector2(0, -45), Tokens.SIGNAL)
	else:
		_spawn_floating_text("SYSTEM BREACH", player.position + Vector2(0, -45), Tokens.SIGNAL)
		_trigger_death_sequence()

func _trigger_death_sequence() -> void:
	is_running = false
	player.visible = false
	if _guide_pill:
		_guide_pill.visible = false
	_add_screen_shake(0.55, 22.0)
	_trigger_spark_burst(player.position, 48)

	Engine.time_scale = 0.35
	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(func():
		Engine.time_scale = 1.0
		end_game()
	)

func _add_screen_shake(duration: float, magnitude: float) -> void:
	shake_duration = duration
	shake_magnitude = magnitude

func _update_shield_display() -> void:
	if _shield_aura and _shield_aura.has_method("set_shield_count"):
		_shield_aura.set_shield_count(shields)
	shields_changed.emit(shields, MAX_SHIELDS)
	if hud and hud.has_method("update_shields"):
		hud.update_shields(shields, MAX_SHIELDS)

func _update_combo_badge() -> void:
	combo_changed.emit(combo)
	if hud and hud.has_method("update_combo"):
		hud.update_combo(combo)

func _trigger_spark_burst(pos: Vector2, count: int) -> void:
	_spark_burst.position = pos
	_spark_burst.amount = count
	_spark_burst.restart()

func _spawn_afterimage() -> void:
	if not player or not is_instance_valid(player):
		return
	var ghost := Sprite2D.new()
	ghost.texture = player.texture
	ghost.position = player.position
	ghost.scale = player.scale
	ghost.rotation = player.rotation
	ghost.centered = true
	ghost.modulate = Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.38)
	ghost.z_index = player.z_index - 1
	fx_container.add_child(ghost)

	var tw := create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)

func _spawn_floating_text(text: String, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	Tokens.make_legible(lbl, 2, 0.9)
	lbl.position = pos - Vector2(50, 10)
	popup_container.add_child(lbl)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y - 48.0, 0.65).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


# =============================================================================
# SUB-COMPONENTS (3D Highway Tunnel, Barricade Hazard Glow, Volt Energy Core)
# =============================================================================

## Procedural 3D Cyber Highway Tunnel with glowing Cyan lane dividers and speed streaks
class HighwayTunnelDrawer extends Node2D:
	var scroll_y: float = 0.0
	var speed_streaks: Array[Dictionary] = []

	func _init() -> void:
		for i in range(24):
			speed_streaks.append({
				"pos": Vector2(randf_range(24, 516), randf_range(0, 960)),
				"speed_mult": randf_range(0.8, 1.4),
				"len": randf_range(40, 140),
				"width": randf_range(1.5, 2.5),
				"color": Tokens.CYAN if randf() < 0.75 else Tokens.VOLT,
				"alpha": randf_range(0.12, 0.35)
			})

	func _process(delta: float) -> void:
		var parent_game = get_parent().get_parent()
		var spd: float = parent_game.current_speed if parent_game and "current_speed" in parent_game else 240.0
		scroll_y = fmod(scroll_y + spd * delta, 80.0)

		for s in speed_streaks:
			s["pos"].y += spd * s["speed_mult"] * delta
			if s["pos"].y > 980.0:
				s["pos"].y = randf_range(-140, -20)
				s["pos"].x = randf_range(24, 516)

		queue_redraw()

	func _draw() -> void:
		# 1. Deep Cyber Abyss Background Fill
		draw_rect(Rect2(0, 0, 540, 960), Color("#060A10"), true)

		# 2. Outer Sidewall Carbon Rails (X = 24 and X = 516)
		draw_line(Vector2(24, 0), Vector2(24, 960), Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.28), 2.0)
		draw_line(Vector2(516, 0), Vector2(516, 960), Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.28), 2.0)

		# 3. Outer Neon Glow Rails
		draw_line(Vector2(24, 0), Vector2(24, 960), Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.08), 8.0)
		draw_line(Vector2(516, 0), Vector2(516, 960), Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.08), 8.0)

		# 4. Interior Lane Dividers (Lanes at X = 190 and X = 350)
		for div_x in [190.0, 350.0]:
			# Solid faint divider line
			draw_line(Vector2(div_x, 0), Vector2(div_x, 960), Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.09), 1.2)

			# Scrolling glowing dashed markers
			var dash_y := scroll_y - 80.0
			while dash_y < 1000.0:
				draw_line(Vector2(div_x, dash_y), Vector2(div_x, dash_y + 36), Tokens.CYAN, 2.0)
				# Specular white center dash
				draw_line(Vector2(div_x, dash_y + 4), Vector2(div_x, dash_y + 32), Color.WHITE, 1.0)
				dash_y += 80.0

		# 5. Perspective Speed Streaks
		for s in speed_streaks:
			var col: Color = s["color"]
			col.a = s["alpha"]
			draw_line(s["pos"], Vector2(s["pos"].x, s["pos"].y + s["len"]), col, s["width"])

		# 6. Horizon Vanishing Point Haze (Top of speedway)
		draw_rect(Rect2(0, 0, 540, 200), Color(0.02, 0.05, 0.08, 0.45), true)


## Barricade Hazard Warning Red Aura
class BarricadeHazardGlow extends Node2D:
	func _draw() -> void:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.009)
		draw_circle(Vector2.ZERO, 38.0 * pulse, Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 0.16))
		draw_circle(Vector2.ZERO, 22.0 * pulse, Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 0.28))


## Floating Volt Energy Core Diamond
class VoltEnergyCore extends Node2D:
	var rot: float = 0.0
	var pulse: float = 0.0

	func _process(delta: float) -> void:
		rot += 3.4 * delta
		pulse += 5.2 * delta
		queue_redraw()

	func _draw() -> void:
		var sc := 1.0 + 0.12 * sin(pulse)
		# Radiant Halo
		draw_circle(Vector2.ZERO, 20.0 * sc, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.20))
		draw_circle(Vector2.ZERO, 14.0 * sc, Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.28))

		# 3D Rotating Crystal Facets
		var s := 12.0 * sc
		var cos_r := cos(rot)
		var sin_r := sin(rot)
		var top := Vector2(-sin_r * s * 1.3, -cos_r * s * 1.3)
		var bottom := -top
		var right := Vector2(cos_r * s * 0.9, -sin_r * s * 0.9)
		var left := -right

		draw_colored_polygon(PackedVector2Array([top, right, Vector2.ZERO]), Color("#FFFFFF"))
		draw_colored_polygon(PackedVector2Array([top, left, Vector2.ZERO]), Color("#F2FFA6"))
		draw_colored_polygon(PackedVector2Array([bottom, right, Vector2.ZERO]), Tokens.VOLT)
		draw_colored_polygon(PackedVector2Array([bottom, left, Vector2.ZERO]), Color("#86AF00"))

		draw_circle(Vector2.ZERO, 2.2 * sc, Color.WHITE)


## Cyan Plasma Energy Shield Ring around Runner Pod
class SwitcherShieldRing extends Node2D:
	var shields: int = 3
	var t: float = 0.0

	func set_shield_count(cnt: int) -> void:
		shields = cnt
		queue_redraw()

	func _process(delta: float) -> void:
		if shields > 0:
			t += delta * 4.2
			queue_redraw()

	func _draw() -> void:
		if shields <= 0:
			return
		var r := 46.0 + 1.5 * sin(t)
		var col := Tokens.CYAN
		col.a = 0.38 + 0.22 * sin(t * 1.5)
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, col, 1.8)
		# Specular glint arc
		var glint_angle := t * 1.2
		draw_arc(Vector2.ZERO, r, glint_angle - 0.5, glint_angle + 0.5, 12, Color(1, 1, 1, col.a * 0.85), 2.2)
