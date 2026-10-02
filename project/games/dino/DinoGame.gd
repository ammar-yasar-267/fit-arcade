extends GameBase

## FitArcade — Dino Runner (Enhanced Cyber-Arcade Edition)
## Mode: "dino" | Exercise: "Jumping Jacks" | Theme: VOLT (#D4FF3A)
## Designed for athletic exergaming with high-octane visual feedback,
## dynamic ground and sky parallax layers, procedural audio, combos, shields, and particle FX.

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Dino.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Dino-Neon-Cactus.svg")

signal shields_changed(current: int, max_val: int)
signal combo_changed(combo_val: int)

# --- Scene Node References ---
var hud: CanvasLayer
var world_root: Node2D
var player: Sprite2D
var ground_node: Node2D
var obstacle_container: Node2D
var collectible_container: Node2D
var fx_container: Node2D
var popup_container: Node2D
var background_root: Node2D

# --- Player & Physics Constants (Tuned for Jumping Jacks) ---
const INITIAL_SPEED := 180.0
const MAX_SPEED := 260.0
const GROUND_Y := 700.0         # Top surface of the running ground
const PLAYER_BASE_Y := 660.0    # Standing Y position on the ground (feet rest on Y=700)
const JUMP_VELOCITY := -740.0   # Generous upward impulse
const GRAVITY := 1340.0         # Gives ~1.1s total airtime (ideal for jumping jack rep cadence)
const PLAYER_HITBOX_W := 44.0
const PLAYER_HITBOX_H := 58.0

# --- State Variables ---
var current_speed := INITIAL_SPEED
var velocity_y := 0.0
var is_on_ground := true
var has_started := false
var game_time := 0.0
var run_t := 0.0
var spawn_timer := 2.2
var distance_acc := 0.0
var _ghost_timer := 0.0

# --- Health, Shields & Combos ---
const MAX_SHIELDS := 3
var shields := MAX_SHIELDS
var invulnerable_timer := 0.0
var combo := 1
var max_combo := 1
var perfect_clears := 0

# --- Screen Shake & Juice ---
var shake_duration := 0.0
var shake_magnitude := 0.0
var _player_tween: Tween

# --- In-Game Visual Elements ---
var _shield_aura: Node2D
var _dust_emitter: CPUParticles2D
var _jump_burst: CPUParticles2D
var _spark_burst: CPUParticles2D

# --- Procedural SFX Audio Players ---
var _sfx_jump: AudioStreamPlayer
var _sfx_land: AudioStreamPlayer
var _sfx_score: AudioStreamPlayer
var _sfx_shard: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_combo: AudioStreamPlayer

# --- Ground Mark Generation ---
var ground_ticks: Array[Dictionary] = []
var grid_scroll_x := 0.0

func _ready() -> void:
	game_name = "Chrome Dino"
	ExerciseRecognizer.set_active_exercise("Jumping Jacks")

	hud = get_node_or_null("HUD")
	player = get_node_or_null("Player")
	obstacle_container = get_node_or_null("Obstacles")

	# World wrapper for screen shake
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	# Background layer
	background_root = Node2D.new()
	background_root.name = "BackgroundLayers"
	background_root.z_index = -20
	world_root.add_child(background_root)

	# Ground runway
	ground_node = Node2D.new()
	ground_node.name = "GroundRunway"
	ground_node.z_index = -4
	world_root.add_child(ground_node)

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
	fx_container.z_index = 6
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
	player.scale = Vector2(0.88, 0.88)
	player.z_index = 10
	player.position = Vector2(110, PLAYER_BASE_Y)

	# Add in-game shield aura around player
	_shield_aura = DinoShieldRing.new()
	player.add_child(_shield_aura)

	popup_container = Node2D.new()
	popup_container.name = "FloatingPopups"
	popup_container.z_index = 25
	world_root.add_child(popup_container)

	_setup_background()
	_setup_particles()
	_setup_sfx()
	_setup_ground()

	_update_shield_display()
	_update_combo_badge()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

# -----------------------------------------------------------------------------
# ENVIRONMENT & BACKGROUND SETUP
# -----------------------------------------------------------------------------
func _setup_background() -> void:
	var legacy_bg = get_node_or_null("Background")
	if legacy_bg: legacy_bg.visible = false
	var legacy_gnd = get_node_or_null("Ground")
	if legacy_gnd: legacy_gnd.visible = false

	# 1. Sky Gradient: Deep space dark ink to subtle electric cyber twilight
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.85, 1.0])
	grad.colors = PackedColorArray([
		Color("#030406"), # Deep midnight void
		Color("#070E0A"), # Dark cyber moss
		Color("#111A12"), # Glowing horizon haze
		Color("#0A0F0B")  # Horizon line
	])

	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.5, 0.0)
	grad_tex.fill_to = Vector2(0.5, 1.0)
	grad_tex.width = 16
	grad_tex.height = 960

	var sky_rect := TextureRect.new()
	sky_rect.texture = grad_tex
	sky_rect.size = Vector2(540, 960)
	sky_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_rect.stretch_mode = TextureRect.STRETCH_SCALE
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_root.add_child(sky_rect)

	# 2. Glowing Wireframe Cyber Sun (Spec D3: 64px volt circle at top 40%, right 40)
	var sun := CyberSun.new()
	sun.position = Vector2(440, 340)
	sun.z_index = -18
	background_root.add_child(sun)

	# 3. Procedural Distant Low-Poly Digital Mountains (Parallax Layer)
	var mountains := DigitalMountains.new()
	mountains.z_index = -15
	background_root.add_child(mountains)

	# 4. Ambient Cyber Dust & Data Streaks
	var stars := StarField.new()
	stars.z_index = -14
	background_root.add_child(stars)

# -----------------------------------------------------------------------------
# GROUND & RUNWAY SETUP
# -----------------------------------------------------------------------------
func _setup_ground() -> void:
	# Ground runway node draws surface laser line, depth gradient, and scrolling dash marks
	var runway := GroundRunwayDrawer.new()
	runway.z_index = -3
	ground_node.add_child(runway)

# -----------------------------------------------------------------------------
# PARTICLES & FX SETUP
# -----------------------------------------------------------------------------
func _setup_particles() -> void:
	# Continuous Running Foot Dust / Sparks
	_dust_emitter = CPUParticles2D.new()
	_dust_emitter.emitting = false
	_dust_emitter.amount = 18
	_dust_emitter.lifetime = 0.35
	_dust_emitter.direction = Vector2(-1, -0.2)
	_dust_emitter.spread = 20.0
	_dust_emitter.gravity = Vector2(0, 120)
	_dust_emitter.initial_velocity_min = 40.0
	_dust_emitter.initial_velocity_max = 90.0
	_dust_emitter.scale_amount_min = 2.0
	_dust_emitter.scale_amount_max = 4.0

	var dust_ramp := Gradient.new()
	dust_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.8, 1.0])
	dust_ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.9),
		Tokens.VOLT,
		Color(0.6, 0.8, 0.1, 0.4),
		Color(0.2, 0.2, 0.2, 0.0)
	])
	_dust_emitter.color_ramp = dust_ramp
	_dust_emitter.position = Vector2(90, GROUND_Y - 4)
	fx_container.add_child(_dust_emitter)

	# Jump Launch Energy Blast
	_jump_burst = CPUParticles2D.new()
	_jump_burst.emitting = false
	_jump_burst.one_shot = true
	_jump_burst.amount = 22
	_jump_burst.lifetime = 0.45
	_jump_burst.explosiveness = 0.95
	_jump_burst.direction = Vector2(0, 1)
	_jump_burst.spread = 70.0
	_jump_burst.gravity = Vector2(0, 80)
	_jump_burst.initial_velocity_min = 60.0
	_jump_burst.initial_velocity_max = 160.0
	_jump_burst.scale_amount_min = 2.5
	_jump_burst.scale_amount_max = 5.0
	_jump_burst.color_ramp = dust_ramp
	fx_container.add_child(_jump_burst)

	# FX Spark Burst for hurdle clearance, pickups, and hits
	_spark_burst = CPUParticles2D.new()
	_spark_burst.emitting = false
	_spark_burst.one_shot = true
	_spark_burst.amount = 28
	_spark_burst.lifetime = 0.5
	_spark_burst.explosiveness = 0.92
	_spark_burst.spread = 180.0
	_spark_burst.gravity = Vector2(0, 160)
	_spark_burst.initial_velocity_min = 70.0
	_spark_burst.initial_velocity_max = 200.0
	_spark_burst.scale_amount_min = 3.0
	_spark_burst.scale_amount_max = 5.5
	_spark_burst.color_ramp = dust_ramp
	fx_container.add_child(_spark_burst)

# -----------------------------------------------------------------------------
# PROCEDURAL RETRO-ARCADE SFX
# -----------------------------------------------------------------------------
func _setup_sfx() -> void:
	_sfx_jump = AudioStreamPlayer.new()
	_sfx_jump.stream = _create_procedural_tone(240.0, 560.0, 0.12, 0.35, "sine")
	add_child(_sfx_jump)

	_sfx_land = AudioStreamPlayer.new()
	_sfx_land.stream = _create_procedural_tone(110.0, 45.0, 0.14, 0.30, "triangle")
	add_child(_sfx_land)

	_sfx_score = AudioStreamPlayer.new()
	_sfx_score.stream = _create_procedural_tone(820.0, 1280.0, 0.13, 0.40, "sine")
	add_child(_sfx_score)

	_sfx_shard = AudioStreamPlayer.new()
	_sfx_shard.stream = _create_procedural_tone(980.0, 1520.0, 0.15, 0.45, "triangle")
	add_child(_sfx_shard)

	_sfx_hit = AudioStreamPlayer.new()
	_sfx_hit.stream = _create_procedural_tone(160.0, 50.0, 0.28, 0.50, "noise")
	add_child(_sfx_hit)

	_sfx_combo = AudioStreamPlayer.new()
	_sfx_combo.stream = _create_procedural_tone(540.0, 920.0, 0.18, 0.40, "square")
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
# GAME START & LOOP
# -----------------------------------------------------------------------------
func start_game() -> void:
	super.start_game()
	player.position = Vector2(110, PLAYER_BASE_Y)
	player.rotation_degrees = 0.0
	player.scale = Vector2(0.88, 0.88)
	player.visible = true
	velocity_y = 0.0
	is_on_ground = true
	current_speed = INITIAL_SPEED
	spawn_timer = 2.0
	game_time = 0.0
	run_t = 0.0
	has_started = false
	shields = MAX_SHIELDS
	invulnerable_timer = 0.0
	combo = 1
	max_combo = 1
	perfect_clears = 0
	distance_acc = 0.0
	_dust_emitter.emitting = false

	_update_shield_display()
	_update_combo_badge()

	for obs in obstacle_container.get_children():
		obs.queue_free()
	for shard in collectible_container.get_children():
		shard.queue_free()

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
		# Idle resting stance on ground
		run_t += delta * 3.0
		player.position.y = PLAYER_BASE_Y + sin(run_t) * 2.0
		return

	# Active Gameplay Progression
	game_time += delta
	current_speed = minf(INITIAL_SPEED + game_time * 2.4, MAX_SPEED)
	grid_scroll_x -= current_speed * delta

	# Continuous Survival Distance Points (+6 points/sec)
	distance_acc += delta * 6.0
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

	# Vertical Physics & Jump Arc
	velocity_y += GRAVITY * delta
	player.position.y += velocity_y * delta

	# Ground Collision Check
	if player.position.y >= PLAYER_BASE_Y:
		player.position.y = PLAYER_BASE_Y
		if not is_on_ground:
			# Landed!
			is_on_ground = true
			velocity_y = 0.0
			_on_player_landed()
	else:
		is_on_ground = false

	# Running vs Airborne Animations
	if is_on_ground:
		run_t += delta * (current_speed * 0.09)
		# Rhythmic athletic run stride bob & lean
		var bob := sin(run_t * 2.0) * 3.0
		player.position.y = PLAYER_BASE_Y + bob
		player.rotation_degrees = sin(run_t) * 3.5
		# Athletic stride squash & stretch
		if not _player_tween or not _player_tween.is_running():
			var stride_squash := sin(run_t * 2.0) * 0.035
			player.scale = Vector2(0.88 + stride_squash, 0.88 - stride_squash)
		_dust_emitter.emitting = true
		_dust_emitter.position = Vector2(player.position.x - 20, GROUND_Y - 4)
	else:
		_dust_emitter.emitting = false
		# Dynamic pitch tilt along jump arc (nose up rising, nose down diving)
		var target_rot = clampf(velocity_y * 0.04, -16.0, 18.0)
		player.rotation_degrees = lerpf(player.rotation_degrees, target_rot, 10.0 * delta)

	# Dynamic cyber after-image speed trail when sprinting fast or airborne
	if not is_on_ground or current_speed > 210.0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = 0.075
			_spawn_afterimage()

	# Obstacle Spawning Loop
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_obstacle_cluster()
		# Dynamic interval scales with speed to match jumping jack physical cadence
		var interval_min = 2.4 - (current_speed - INITIAL_SPEED) * 0.008
		var interval_max = 3.6 - (current_speed - INITIAL_SPEED) * 0.008
		spawn_timer = randf_range(max(interval_min, 1.8), max(interval_max, 2.7))

	# Move & Process Obstacles
	for obs in obstacle_container.get_children():
		if obs.is_queued_for_deletion():
			continue
		obs.position.x -= current_speed * delta

		# Scoring when player successfully vaults over obstacle
		if not obs.get_meta("scored") and obs.position.x + 30.0 < player.position.x:
			obs.set_meta("scored", true)
			_on_obstacle_cleared(obs)

		# Cull offscreen obstacles
		if obs.position.x < -120:
			obs.queue_free()
			continue

		# Collision Detection (Forgiving Athletic Bounding Box)
		if invulnerable_timer <= 0.0:
			var obs_w: float = obs.get_meta("w", 50.0)
			var obs_h: float = obs.get_meta("h", 80.0)
			# Obstacle hitbox: tightly hugging the laser core
			var obs_rect := Rect2(obs.position.x - obs_w * 0.42, GROUND_Y - obs_h + 4.0, obs_w * 0.84, obs_h - 4.0)
			# Player hitbox: tightly hugging torso and legs (forgiving on tail and tip of snout)
			var player_rect := Rect2(player.position.x - 20.0, player.position.y - 26.0, 40.0, 56.0)

			if player_rect.intersects(obs_rect):
				_on_hazard_hit("LASER BARRICADE")

	# Move & Process Collectible Shards
	for shard in collectible_container.get_children():
		if shard.is_queued_for_deletion():
			continue
		shard.position.x -= current_speed * delta
		var st: float = shard.get_meta("t", 0.0) + delta * 5.0
		shard.set_meta("t", st)
		shard.position.y = shard.get_meta("base_y") + sin(st) * 8.0

		if shard.position.x < -40:
			shard.queue_free()
			continue

		if player.position.distance_to(shard.position) < 42.0:
			_collect_shard(shard)

# -----------------------------------------------------------------------------
# REP / INPUT HANDLING
# -----------------------------------------------------------------------------
func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true

	# Only allow launch if on or very close to the ground (prevents infinite air jumps)
	if player.position.y >= PLAYER_BASE_Y - 25.0:
		velocity_y = JUMP_VELOCITY
		is_on_ground = false

		# Snappy Squash & Stretch Jump Launch
		if _player_tween and _player_tween.is_valid():
			_player_tween.kill()
		player.scale = Vector2(0.72, 1.25)
		_player_tween = create_tween()
		_player_tween.tween_property(player, "scale", Vector2(0.88, 0.88), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

		# Jump Launch Energy Blast
		_jump_burst.position = Vector2(player.position.x, GROUND_Y - 4)
		_jump_burst.restart()

		if _sfx_jump:
			_sfx_jump.pitch_scale = randf_range(0.96, 1.06)
			_sfx_jump.play()

## Desktop / Keyboard fallback for instant testing without webcam
func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_SPACE, KEY_UP, KEY_W, KEY_ENTER])):
		ExerciseRecognizer.trigger_debug_rep()

# -----------------------------------------------------------------------------
# LANDING & VAULTING
# -----------------------------------------------------------------------------
func _on_player_landed() -> void:
	# Landing squash bounce
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	player.scale = Vector2(1.15, 0.75)
	_player_tween = create_tween()
	_player_tween.tween_property(player, "scale", Vector2(0.88, 0.88), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Ground landing puff
	_jump_burst.position = Vector2(player.position.x, GROUND_Y - 4)
	_jump_burst.restart()

	if _sfx_land:
		_sfx_land.play()

func _on_obstacle_cleared(obs: Node2D) -> void:
	var obs_h: float = obs.get_meta("h", 80.0)
	var foot_y: float = player.position.y + 38.7
	var clearance_margin: float = (GROUND_Y - obs_h) - foot_y
	var is_perfect: bool = clearance_margin >= 35.0

	var base_pts := 100 * combo
	var bonus_pts := 0

	if is_perfect:
		bonus_pts = 50 * combo
		perfect_clears += 1
		_spawn_floating_text("PERFECT! +%d" % (base_pts + bonus_pts), Vector2(obs.position.x, GROUND_Y - obs_h - 30), Tokens.VOLT)
	else:
		_spawn_floating_text("+%d" % base_pts, Vector2(obs.position.x, GROUND_Y - obs_h - 20), Tokens.VOLT)

	add_score(base_pts + bonus_pts)
	if hud: hud.update_score(score)

	combo = mini(combo + 1, 5)
	max_combo = maxi(max_combo, combo)
	_update_combo_badge()

	if combo >= 3 and _sfx_combo:
		_sfx_combo.play()
	elif _sfx_score:
		_sfx_score.pitch_scale = 1.0 + (combo - 1) * 0.08
		_sfx_score.play()

	_trigger_spark_burst(Vector2(obs.position.x, GROUND_Y - obs_h), 16)
	_add_screen_shake(0.10, 3.5)

func _collect_shard(shard: Node2D) -> void:
	var shard_pts := 50 * combo
	add_score(shard_pts)
	if hud: hud.update_score(score)

	_spawn_floating_text("+%d CORE" % shard_pts, shard.position, Tokens.CYAN)
	_trigger_spark_burst(shard.position, 22)

	if _sfx_shard:
		_sfx_shard.pitch_scale = randf_range(0.98, 1.1)
		_sfx_shard.play()

	shard.queue_free()

# -----------------------------------------------------------------------------
# HAZARD DAMAGE & SHIELDS
# -----------------------------------------------------------------------------
func _on_hazard_hit(hazard_name: String) -> void:
	shields -= 1
	_update_shield_display()
	combo = 1
	_update_combo_badge()

	_add_screen_shake(0.35, 14.0)
	if _sfx_hit:
		_sfx_hit.play()

	_trigger_spark_burst(player.position, 26)

	if shields > 0:
		invulnerable_timer = 1.6
		velocity_y = JUMP_VELOCITY * 0.45 # Small rebound hop
		_spawn_floating_text("-1 SHIELD!", player.position + Vector2(0, -45), Tokens.SIGNAL)
	else:
		_spawn_floating_text("SYSTEM BREACH", player.position + Vector2(0, -45), Tokens.SIGNAL)
		_trigger_death_sequence()

func _trigger_death_sequence() -> void:
	is_running = false
	player.visible = false
	_dust_emitter.emitting = false
	_add_screen_shake(0.55, 22.0)
	_trigger_spark_burst(player.position, 45)

	# Dramatic slow-motion shatter
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

# -----------------------------------------------------------------------------
# OBSTACLE & SHARD GENERATION
# -----------------------------------------------------------------------------
func _spawn_obstacle_cluster() -> void:
	var pattern_type := randi() % 3

	var obs := Node2D.new()
	obs.position = Vector2(590, GROUND_Y)
	obs.set_meta("scored", false)

	var cactus_spr := Sprite2D.new()
	cactus_spr.texture = OBSTACLE_TEXTURE
	cactus_spr.centered = false

	var obs_h := 80.0
	var obs_w := 48.0

	match pattern_type:
		0:
			# Single Standard Tall Laser Cactus
			obs_h = 85.0
			obs_w = 44.0
			cactus_spr.scale = Vector2(0.85, 0.85)
			cactus_spr.position = Vector2(-22, -85)
			obs.add_child(cactus_spr)
		1:
			# Twin Cluster (Two cactuses close together)
			obs_h = 75.0
			obs_w = 78.0
			cactus_spr.scale = Vector2(0.75, 0.75)
			cactus_spr.position = Vector2(-39, -75)
			obs.add_child(cactus_spr)

			var c2 := Sprite2D.new()
			c2.texture = OBSTACLE_TEXTURE
			c2.centered = false
			c2.scale = Vector2(0.75, 0.75)
			c2.position = Vector2(-5, -75)
			obs.add_child(c2)
		2:
			# Reinforced High-Voltage Tower
			obs_h = 92.0
			obs_w = 52.0
			cactus_spr.scale = Vector2(0.92, 0.92)
			cactus_spr.position = Vector2(-26, -92)
			obs.add_child(cactus_spr)

	obs.set_meta("w", obs_w)
	obs.set_meta("h", obs_h)

	# Danger Base Aura
	var glow := DangerBaseGlow.new(obs_w)
	obs.add_child(glow)

	obstacle_container.add_child(obs)

	# 55% Chance to spawn a floating Energy Core at jump apex height (~Y = 440)
	if randf() < 0.55:
		_spawn_shard(Vector2(590, randf_range(430.0, 480.0)))

func _spawn_shard(pos: Vector2) -> void:
	var shard := VoltCollectibleShard.new()
	shard.position = pos
	shard.set_meta("base_y", pos.y)
	shard.set_meta("t", randf_range(0.0, TAU))
	collectible_container.add_child(shard)

func _trigger_spark_burst(pos: Vector2, count: int) -> void:
	_spark_burst.position = pos
	_spark_burst.amount = count
	_spark_burst.restart()

func _spawn_floating_text(text: String, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	Tokens.make_legible(lbl, 2, 0.9)
	lbl.position = pos - Vector2(40, 10)
	popup_container.add_child(lbl)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y - 48.0, 0.65).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)

func _spawn_afterimage() -> void:
	if not player or not is_instance_valid(player):
		return
	var ghost := Sprite2D.new()
	ghost.texture = player.texture
	ghost.position = player.position
	ghost.scale = player.scale
	ghost.rotation = player.rotation
	ghost.centered = true
	ghost.modulate = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.38)
	ghost.z_index = player.z_index - 1
	fx_container.add_child(ghost)

	var tw := create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)


# =============================================================================
# SUB-COMPONENTS (Ground Runway, Cyber Sun, Mountains, Dust & Energy Shards)
# =============================================================================

## Procedural Ground Runway Drawer with Glowing Surface Laser & 3D Perspective Grid
class GroundRunwayDrawer extends Node2D:
	var scroll_x: float = 0.0

	func _process(delta: float) -> void:
		var parent_game = get_parent().get_parent()
		var spd: float = parent_game.current_speed if parent_game and "current_speed" in parent_game else 180.0
		scroll_x -= spd * delta
		if scroll_x <= -40.0:
			scroll_x += 40.0
		queue_redraw()

	func _draw() -> void:
		var g_top := 700.0
		var g_h := 260.0

		# 1. Dark Carbon Base Fill
		draw_rect(Rect2(0, g_top, 540, g_h), Color("#090A0E"), true)

		# 2. Receding 3D Perspective Lines fanning downward into foreground
		var p_lines = [
			Vector2(40, g_top), Vector2(-20, 960),
			Vector2(140, g_top), Vector2(100, 960),
			Vector2(240, g_top), Vector2(230, 960),
			Vector2(340, g_top), Vector2(360, 960),
			Vector2(440, g_top), Vector2(490, 960),
			Vector2(520, g_top), Vector2(600, 960)
		]
		for i in range(0, p_lines.size(), 2):
			draw_line(p_lines[i], p_lines[i+1], Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.06), 1.2)

		# 3. Dynamic Horizontal Perspective Depth Bands
		for band_offset: float in [16.0, 42.0, 80.0, 135.0, 205.0]:
			var y_line: float = g_top + band_offset
			var band_alpha: float = lerpf(0.04, 0.16, band_offset / g_h)
			draw_line(Vector2(0, y_line), Vector2(540, y_line), Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, band_alpha), 1.5)

		# 4. Scrolling surface tick marks (Spec D3: vertical ticks 3px #2A2A2E every 40px)
		var tick_x := scroll_x - 40.0
		while tick_x < 580.0:
			draw_line(Vector2(tick_x, g_top), Vector2(tick_x, g_top + 14), Color("#2A2A2E"), 3.0)
			# Occasional volt glow tick
			if int(tick_x) % 120 == 0:
				draw_line(Vector2(tick_x, g_top), Vector2(tick_x, g_top + 8), Tokens.VOLT, 2.0)
			tick_x += 40.0

		# 5. Glowing Surface Laser Edge (Y = 700)
		var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.007)
		# Ambient bloom spread
		draw_line(Vector2(0, g_top), Vector2(540, g_top), Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.28 * pulse), 8.0)
		# Solid Volt laser edge
		draw_line(Vector2(0, g_top), Vector2(540, g_top), Tokens.VOLT, 3.0)
		# Specular white core
		draw_line(Vector2(0, g_top), Vector2(540, g_top), Color(1, 1, 1, 0.85), 1.2)


## Cyber Sun / Wireframe Moon (Top Right sky feature)
class CyberSun extends Node2D:
	func _draw() -> void:
		var r := 46.0
		var t := Time.get_ticks_msec() * 0.002
		var pulse := 1.0 + 0.05 * sin(t * 1.5)

		# Radiant atmospheric glow
		draw_circle(Vector2.ZERO, (r + 28.0) * pulse, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.05))
		draw_circle(Vector2.ZERO, (r + 14.0) * pulse, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.09))

		# Outer wireframe orbit ring
		draw_arc(Vector2.ZERO, r + 8.0, 0, TAU, 36, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.16), 1.2)
		# Core glow ring
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.35), 2.2)

		# Horizontal synthwave scanline slats
		for y_off in [-28, -14, 0, 14, 28]:
			var half_w := sqrt(maxf(r * r - y_off * y_off, 0.0))
			draw_line(Vector2(-half_w, y_off), Vector2(half_w, y_off), Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.20), 2.0)


## Procedural Digital Mountains (Parallax Horizon Silhouette)
class DigitalMountains extends Node2D:
	var scroll_pos: float = 0.0

	func _process(delta: float) -> void:
		scroll_pos += 24.0 * delta
		queue_redraw()

	func _draw() -> void:
		var g_y := 700.0
		var points: Array[Vector2] = []
		points.append(Vector2(-60, g_y))

		var screen_x := -60.0
		while screen_x <= 600.0:
			var wx := screen_x + scroll_pos
			var peak_h := 105.0 + sin(wx * 0.012) * 45.0 + cos(wx * 0.028) * 25.0 + sin(wx * 0.055) * 12.0
			points.append(Vector2(screen_x, g_y - peak_h))
			screen_x += 35.0

		points.append(Vector2(600, g_y))

		# Mountain body fill
		var poly := PackedVector2Array(points)
		draw_colored_polygon(poly, Color("#070D09"))

		# Mountain ridge neon contour in VOLT
		for i in range(1, points.size() - 2):
			draw_line(points[i], points[i+1], Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.30), 1.6)


## Hazard Warning Base Glow for Obstacle Barricades
class DangerBaseGlow extends Node2D:
	var width: float

	func _init(w: float) -> void:
		width = w

	func _draw() -> void:
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
		# Pulsing red warning aura at ground contact
		draw_circle(Vector2(0, -2), (width * 0.45) * pulse, Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 0.25))


## Ambient Star & Data Particle Field
class StarField extends Node2D:
	var stars: Array[Dictionary] = []

	func _init() -> void:
		for i in range(40):
			stars.append({
				"pos": Vector2(randf_range(0, 540), randf_range(50, 680)),
				"speed_x": randf_range(-15.0, -45.0),
				"size": randf_range(1.5, 3.2),
				"phase": randf_range(0.0, TAU),
				"color": Tokens.VOLT if randf() < 0.6 else Tokens.CYAN
			})

	func _process(delta: float) -> void:
		for s in stars:
			s["pos"].x += s["speed_x"] * delta
			s["phase"] += delta * 3.5
			if s["pos"].x < -10.0:
				s["pos"].x = 550.0
				s["pos"].y = randf_range(60, 680)
		queue_redraw()

	func _draw() -> void:
		for s in stars:
			var alpha := 0.25 + 0.45 * (0.5 + 0.5 * sin(s["phase"]))
			var col: Color = s["color"]
			col.a = alpha
			draw_circle(s["pos"], s["size"], col)


## Procedural Glowing Collectible Volt Energy Shard
class VoltCollectibleShard extends Node2D:
	var rot_angle: float = 0.0
	var pulse_phase: float = 0.0

	func _process(delta: float) -> void:
		rot_angle += 3.2 * delta
		pulse_phase += 5.5 * delta
		queue_redraw()

	func _draw() -> void:
		var scale_pulse := 1.0 + 0.12 * sin(pulse_phase)

		# Radiant Ambient Glow
		draw_circle(Vector2.ZERO, 22.0 * scale_pulse, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.18))
		draw_circle(Vector2.ZERO, 15.0 * scale_pulse, Color(Tokens.CYAN.r, Tokens.CYAN.g, Tokens.CYAN.b, 0.25))

		# 3D Spinning Diamond Facets
		var s := 13.0 * scale_pulse
		var cos_r := cos(rot_angle)
		var sin_r := sin(rot_angle)
		var top := Vector2(-sin_r * s * 1.3, -cos_r * s * 1.3)
		var bottom := -top
		var right := Vector2(cos_r * s * 0.9, -sin_r * s * 0.9)
		var left := -right

		# 4 Shaded Polygonal Crystal Facets
		draw_colored_polygon(PackedVector2Array([top, right, Vector2.ZERO]), Color("#FFFFFF"))
		draw_colored_polygon(PackedVector2Array([top, left, Vector2.ZERO]), Color("#F2FFA6"))
		draw_colored_polygon(PackedVector2Array([bottom, right, Vector2.ZERO]), Tokens.VOLT)
		draw_colored_polygon(PackedVector2Array([bottom, left, Vector2.ZERO]), Color("#86AF00"))

		# Center Sparkle Core
		draw_circle(Vector2.ZERO, 2.5 * scale_pulse, Color.WHITE)


## Protective Energy Shield Ring around Dino
class DinoShieldRing extends Node2D:
	var shields: int = 3
	var t: float = 0.0

	func set_shield_count(cnt: int) -> void:
		shields = cnt
		queue_redraw()

	func _process(delta: float) -> void:
		if shields > 0:
			t += delta * 4.0
			queue_redraw()

	func _draw() -> void:
		if shields <= 0:
			return
		var r := 48.0 + 1.5 * sin(t)
		var col := Tokens.VOLT
		col.a = 0.38 + 0.22 * sin(t * 1.5)
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, col, 1.8)
		# Specular glint arc
		var glint_angle := t * 1.2
		draw_arc(Vector2.ZERO, r, glint_angle - 0.5, glint_angle + 0.5, 12, Color(1, 1, 1, col.a * 0.85), 2.2)
