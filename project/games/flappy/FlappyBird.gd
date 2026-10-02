extends GameBase

## FitArcade — Flappy Flight (Enhanced Cyber-Arcade Edition)
## Mode: "flappy" | Exercise: "Arm Raises" | Theme: FLAME (#FF8A1F)
## Designed for athletic exergaming with high-octane visual feedback,
## dynamic parallax layers, procedural audio, combos, shields, and particle FX.

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Player-Character_Neon-Runner-Orb.svg")
const PIPE_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Obstacle_Pipe.svg")
const CLOUD_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Cloud-Neon.svg")

signal shields_changed(current: int, max_val: int)
signal combo_changed(combo_val: int)

# --- Scene Node References ---
var hud: CanvasLayer
var world_root: Node2D
var player: Sprite2D
var obstacle_container: Node2D
var cloud_container: Node2D
var collectible_container: Node2D
var fx_container: Node2D
var popup_container: Node2D
var background_root: Node2D

# --- Player & Physics Constants (Tuned for Arm Raises) ---
const INITIAL_SCROLL_SPEED := 120.0
const MAX_SCROLL_SPEED := 165.0
const JUMP_VELOCITY := -335.0
const GRAVITY := 410.0
const PIPE_WIDTH := 80.0
const GAP_SIZE := 300.0
const PLAYER_HITBOX_RADIUS := 28.0

# --- State Variables ---
var scroll_speed := INITIAL_SCROLL_SPEED
var velocity_y := 0.0
var has_started := false
var game_time := 0.0
var idle_time := 0.0
var spawn_timer := 2.2
var cloud_timer := 0.0
var distance_acc := 0.0

# --- Health, Shields & Combos ---
const MAX_SHIELDS := 3
var shields := MAX_SHIELDS
var invulnerable_timer := 0.0
var combo := 1
var max_combo := 1
var perfect_gaps := 0

# --- Screen Shake & Juice ---
var shake_duration := 0.0
var shake_magnitude := 0.0
var _player_tween: Tween

# --- In-Game Visual Elements ---
var _shield_aura: Node2D

# --- Procedural SFX Audio Players ---
var _sfx_jump: AudioStreamPlayer
var _sfx_score: AudioStreamPlayer
var _sfx_shard: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_combo: AudioStreamPlayer

# --- Particles ---
var _thruster_particles: CPUParticles2D
var _spark_burst: CPUParticles2D

# --- Trail Effect ---
var _trail_timer := 0.0

func _ready() -> void:
	game_name = "Flappy Bird"
	ExerciseRecognizer.set_active_exercise("Arm Raises")

	# Find existing nodes or prepare tree
	hud = get_node_or_null("HUD")
	player = get_node_or_null("Player")
	obstacle_container = get_node_or_null("Obstacles")

	# Wrap all gameplay nodes under world_root for screen shake
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	# Setup background layers inside world_root
	background_root = Node2D.new()
	background_root.name = "BackgroundLayers"
	background_root.z_index = -20
	world_root.add_child(background_root)

	# Container hierarchy inside world_root
	cloud_container = Node2D.new()
	cloud_container.name = "Clouds"
	cloud_container.z_index = -12
	world_root.add_child(cloud_container)

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

	# Setup Player
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
	player.position = Vector2(120, 430)

	_shield_aura = PlayerShieldRing.new()
	player.add_child(_shield_aura)

	popup_container = Node2D.new()
	popup_container.name = "FloatingPopups"
	popup_container.z_index = 25
	world_root.add_child(popup_container)

	_setup_background()
	_setup_particles()
	_setup_sfx()
	_update_shield_display()
	_update_combo_badge()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

# -----------------------------------------------------------------------------
# ENVIRONMENT & BACKGROUND SETUP
# -----------------------------------------------------------------------------
func _setup_background() -> void:
	# Hide legacy flat Background ColorRect if present
	var legacy_bg = get_node_or_null("Background")
	if legacy_bg:
		legacy_bg.visible = false

	# 1. Sky Gradient Texture: Deep Cosmic Obsidian to Warm Cyber Sunset
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 0.95, 1.0])
	grad.colors = PackedColorArray([
		Color("#05030A"), # Deep space midnight
		Color("#140718"), # Dark violet dusk
		Color("#2D0F08"), # Burning horizon ember
		Color("#4A1A06"), # Flame glow at horizon line
		Color("#0D0604")  # Dark base below horizon
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

	# 2. Procedural Distant Cyber Towers (Parallax Layer)
	var skyline := CyberSkyline.new()
	skyline.z_index = -15
	background_root.add_child(skyline)

	# 3. Ambient Drifting Flame Embers
	var embers := EmberField.new()
	embers.z_index = -14
	background_root.add_child(embers)

	# 4. Pre-seed Cloud Nebula Formations
	for i in range(5):
		_spawn_cloud(randf_range(20, 540))

	# 5. Floor Hazard Barrier (Y = 900 to 960)
	var floor_barrier := HazardBarrier.new(Vector2(0, 900), Vector2(540, 60), false)
	floor_barrier.z_index = 8
	world_root.add_child(floor_barrier)

	# 6. Ceiling Hazard Barrier (Y = 0 to 16)
	var ceiling_barrier := HazardBarrier.new(Vector2(0, 0), Vector2(540, 16), true)
	ceiling_barrier.z_index = 8
	world_root.add_child(ceiling_barrier)

# -----------------------------------------------------------------------------
# PARTICLES & FX SETUP
# -----------------------------------------------------------------------------
func _setup_particles() -> void:
	# Continuous/Burst Thruster Exhaust Particles
	_thruster_particles = CPUParticles2D.new()
	_thruster_particles.emitting = true
	_thruster_particles.amount = 24
	_thruster_particles.lifetime = 0.4
	_thruster_particles.preprocess = 0.1
	_thruster_particles.speed_scale = 1.2
	_thruster_particles.explosiveness = 0.0
	_thruster_particles.direction = Vector2(-1, 0.4)
	_thruster_particles.spread = 25.0
	_thruster_particles.gravity = Vector2(0, 90)
	_thruster_particles.initial_velocity_min = 60.0
	_thruster_particles.initial_velocity_max = 140.0
	_thruster_particles.scale_amount_min = 2.5
	_thruster_particles.scale_amount_max = 5.0
	_thruster_particles.color = Tokens.FLAME

	var color_ramp := Gradient.new()
	color_ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	color_ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.95),
		Tokens.VOLT,
		Tokens.FLAME,
		Color(0.9, 0.15, 0.0, 0.0)
	])
	_thruster_particles.color_ramp = color_ramp
	_thruster_particles.position = Vector2(-28, 4)
	player.add_child(_thruster_particles)

	# Dynamic FX Spark Burst (Triggered on gates, collisions, pickups)
	_spark_burst = CPUParticles2D.new()
	_spark_burst.emitting = false
	_spark_burst.one_shot = true
	_spark_burst.amount = 32
	_spark_burst.lifetime = 0.55
	_spark_burst.explosiveness = 0.92
	_spark_burst.spread = 180.0
	_spark_burst.gravity = Vector2(0, 140)
	_spark_burst.initial_velocity_min = 80.0
	_spark_burst.initial_velocity_max = 220.0
	_spark_burst.scale_amount_min = 3.0
	_spark_burst.scale_amount_max = 6.0
	_spark_burst.color_ramp = color_ramp
	fx_container.add_child(_spark_burst)

# -----------------------------------------------------------------------------
# PROCEDURAL RETRO-ARCADE SFX
# -----------------------------------------------------------------------------
func _setup_sfx() -> void:
	_sfx_jump = AudioStreamPlayer.new()
	_sfx_jump.stream = _create_procedural_tone(190.0, 390.0, 0.11, 0.35, "sine")
	add_child(_sfx_jump)

	_sfx_score = AudioStreamPlayer.new()
	_sfx_score.stream = _create_procedural_tone(780.0, 1180.0, 0.13, 0.40, "sine")
	add_child(_sfx_score)

	_sfx_shard = AudioStreamPlayer.new()
	_sfx_shard.stream = _create_procedural_tone(940.0, 1480.0, 0.16, 0.45, "triangle")
	add_child(_sfx_shard)

	_sfx_hit = AudioStreamPlayer.new()
	_sfx_hit.stream = _create_procedural_tone(140.0, 55.0, 0.28, 0.50, "noise")
	add_child(_sfx_hit)

	_sfx_combo = AudioStreamPlayer.new()
	_sfx_combo.stream = _create_procedural_tone(520.0, 880.0, 0.18, 0.40, "square")
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

		# Smooth attack & decay envelope
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
	player.position = Vector2(120, 430)
	player.rotation_degrees = 0.0
	player.scale = Vector2(0.85, 0.85)
	player.visible = true
	velocity_y = 0.0
	scroll_speed = INITIAL_SCROLL_SPEED
	spawn_timer = 2.0
	game_time = 0.0
	idle_time = 0.0
	has_started = false
	shields = MAX_SHIELDS
	invulnerable_timer = 0.0
	combo = 1
	max_combo = 1
	perfect_gaps = 0
	distance_acc = 0.0
	_update_shield_display()
	_update_combo_badge()

	for obs in obstacle_container.get_children():
		obs.queue_free()
	for shard in collectible_container.get_children():
		shard.queue_free()

func _process(delta: float) -> void:
	if not is_running:
		return

	# Handle screen shake offset
	if shake_duration > 0.0:
		shake_duration -= delta
		var offset_x = randf_range(-shake_magnitude, shake_magnitude)
		var offset_y = randf_range(-shake_magnitude, shake_magnitude)
		world_root.position = Vector2(offset_x, offset_y)
		shake_magnitude = lerpf(shake_magnitude, 0.0, 10.0 * delta)
		if shake_duration <= 0.0:
			world_root.position = Vector2.ZERO

	_update_clouds(delta)

	# Pre-game gentle hovering sway
	if not has_started:
		idle_time += delta
		player.position.y = 430.0 + sin(idle_time * 3.5) * 8.0
		player.rotation_degrees = sin(idle_time * 2.0) * 4.0
		return

	# Active Gameplay Progression
	game_time += delta
	scroll_speed = minf(INITIAL_SCROLL_SPEED + game_time * 1.4, MAX_SCROLL_SPEED)

	# Distance micro-score: +6 points per second for continuous survival
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

	# Vertical Physics
	velocity_y += GRAVITY * delta
	player.position.y += velocity_y * delta

	# Rotational Pitch Animation (Tilt up when rising, dive when falling)
	var target_rot = clampf(velocity_y * 0.13, -28.0, 65.0)
	player.rotation_degrees = lerpf(player.rotation_degrees, target_rot, 9.0 * delta)

	# Spawn Ghost Motion Trail
	_trail_timer += delta
	if _trail_timer >= 0.06:
		_trail_timer = 0.0
		_spawn_ghost_trail()

	# Boundary Hazard Collisions (Floor Y=900, Ceiling Y=16)
	if player.position.y > 900.0 - PLAYER_HITBOX_RADIUS:
		player.position.y = 900.0 - PLAYER_HITBOX_RADIUS
		velocity_y = JUMP_VELOCITY * 0.6
		_on_hazard_hit("HAZARD FLOOR")
	elif player.position.y < 16.0 + PLAYER_HITBOX_RADIUS:
		player.position.y = 16.0 + PLAYER_HITBOX_RADIUS
		velocity_y = 60.0
		_on_hazard_hit("HAZARD CEILING")

	# Pipe Spawning Loop
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_pipe_gate()
		# Dynamic spacing adjusts gracefully as speed increases
		var interval_min = 2.6 - (scroll_speed - INITIAL_SCROLL_SPEED) * 0.015
		var interval_max = 3.6 - (scroll_speed - INITIAL_SCROLL_SPEED) * 0.015
		spawn_timer = randf_range(max(interval_min, 1.9), max(interval_max, 2.7))

	# Move & Process Obstacles
	for obs in obstacle_container.get_children():
		if obs.is_queued_for_deletion():
			continue
		obs.position.x -= scroll_speed * delta

		# Dynamic gate oscillation for higher intensity
		if obs.has_meta("bob_speed"):
			var b_spd: float = obs.get_meta("bob_speed")
			var b_amp: float = obs.get_meta("bob_amp")
			var b_t: float = obs.get_meta("bob_t") + delta * b_spd
			obs.set_meta("bob_t", b_t)
			var cur_gap_y: float = obs.get_meta("orig_gap_y") + sin(b_t) * b_amp
			obs.set_meta("gap_y", cur_gap_y)
			# Update pipe positions to follow gap_y
			var top_p = obs.get_node_or_null("TopPipe")
			var bot_p = obs.get_node_or_null("BottomPipe")
			if top_p and bot_p:
				top_p.scale.y = max(cur_gap_y - GAP_SIZE / 2.0, 1.0) / PIPE_TEXTURE.get_height()
				bot_p.position.y = cur_gap_y + GAP_SIZE / 2.0
				bot_p.scale.y = max(960.0 - (cur_gap_y + GAP_SIZE / 2.0), 1.0) / PIPE_TEXTURE.get_height()

		# Cull offscreen pipes
		if obs.position.x < -PIPE_WIDTH - 60:
			obs.queue_free()
			continue

		# Scoring when crossing pipe center
		if not obs.get_meta("scored") and obs.position.x + PIPE_WIDTH * 0.5 < player.position.x:
			obs.set_meta("scored", true)
			_on_gate_cleared(obs)

		# Collision Detection (Circular player vs Rectangular pipes)
		if invulnerable_timer <= 0.0:
			var gap_y: float = obs.get_meta("gap_y")
			var top_box = Rect2(obs.position.x, 0, PIPE_WIDTH, gap_y - GAP_SIZE / 2.0)
			var bot_box = Rect2(obs.position.x, gap_y + GAP_SIZE / 2.0, PIPE_WIDTH, 960.0)
			var player_box = Rect2(player.position.x - PLAYER_HITBOX_RADIUS, player.position.y - PLAYER_HITBOX_RADIUS, PLAYER_HITBOX_RADIUS * 2.0, PLAYER_HITBOX_RADIUS * 2.0)

			if player_box.intersects(top_box) or player_box.intersects(bot_box):
				_on_hazard_hit("ENERGY CONDUIT")

	# Move & Process Collectible Shards
	for shard in collectible_container.get_children():
		if shard.is_queued_for_deletion():
			continue
		shard.position.x -= scroll_speed * delta
		# Bobbing animation
		var st: float = shard.get_meta("t", 0.0) + delta * 5.0
		shard.set_meta("t", st)
		shard.position.y = shard.get_meta("base_y") + sin(st) * 8.0

		if shard.position.x < -40:
			shard.queue_free()
			continue

		# Collection Check
		if player.position.distance_to(shard.position) < PLAYER_HITBOX_RADIUS + 22.0:
			_collect_shard(shard)

# -----------------------------------------------------------------------------
# REP / INPUT HANDLING
# -----------------------------------------------------------------------------
func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true

	velocity_y = JUMP_VELOCITY

	# Snappy Squash & Stretch Jump Bounce
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	player.scale = Vector2(0.68, 1.28)
	_player_tween = create_tween()
	_player_tween.tween_property(player, "scale", Vector2(0.85, 0.85), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

	# Thruster Spark Ejection
	_thruster_particles.restart()

	# Audio Jump Whoosh
	if _sfx_jump:
		_sfx_jump.pitch_scale = randf_range(0.95, 1.08)
		_sfx_jump.play()

## Desktop / Keyboard debug fallback so the game can be tested directly
func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_SPACE, KEY_UP, KEY_W, KEY_ENTER])):
		ExerciseRecognizer.trigger_debug_rep()

# -----------------------------------------------------------------------------
# SCORING, COMBOS & GATE CLEARANCE
# -----------------------------------------------------------------------------
func _on_gate_cleared(gate: Node2D) -> void:
	var gap_y: float = gate.get_meta("gap_y")
	var dist_from_center := absf(player.position.y - gap_y)
	var is_perfect := dist_from_center <= (GAP_SIZE * 0.18)

	var base_pts := 100 * combo
	var bonus_pts := 0

	if is_perfect:
		bonus_pts = 50 * combo
		perfect_gaps += 1
		_spawn_floating_text("PERFECT! +%d" % (base_pts + bonus_pts), gate.position + Vector2(40, gap_y - 30), Tokens.VOLT)
	else:
		_spawn_floating_text("+%d" % base_pts, gate.position + Vector2(40, gap_y - 20), Tokens.FLAME)

	add_score(base_pts + bonus_pts)
	if hud: hud.update_score(score)

	# Advance Combo
	combo = mini(combo + 1, 5)
	max_combo = maxi(max_combo, combo)
	_update_combo_badge()

	# Audio & Particles
	if combo >= 3 and _sfx_combo:
		_sfx_combo.play()
	elif _sfx_score:
		_sfx_score.pitch_scale = 1.0 + (combo - 1) * 0.08
		_sfx_score.play()

	_trigger_spark_burst(Vector2(gate.position.x + 40, gap_y), 18)
	_add_screen_shake(0.12, 4.0)

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
# HAZARD DAMAGE & SHIELD RECOVERY
# -----------------------------------------------------------------------------
func _on_hazard_hit(hazard_name: String) -> void:
	shields -= 1
	_update_shield_display()
	combo = 1
	_update_combo_badge()

	_add_screen_shake(0.35, 14.0)
	if _sfx_hit:
		_sfx_hit.play()

	_trigger_spark_burst(player.position, 28)

	if shields > 0:
		invulnerable_timer = 1.6
		_spawn_floating_text("-1 SHIELD!", player.position + Vector2(0, -35), Tokens.SIGNAL)
	else:
		_spawn_floating_text("SYSTEM BREACH", player.position + Vector2(0, -35), Tokens.SIGNAL)
		_trigger_death_sequence()

func _trigger_death_sequence() -> void:
	is_running = false
	player.visible = false
	_add_screen_shake(0.55, 22.0)
	_trigger_spark_burst(player.position, 48)

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
func _spawn_pipe_gate() -> void:
	var gap_y := randf_range(230.0, 590.0)

	var pipe_parent := Node2D.new()
	pipe_parent.position = Vector2(580, 0)
	pipe_parent.set_meta("scored", false)
	pipe_parent.set_meta("gap_y", gap_y)
	pipe_parent.set_meta("orig_gap_y", gap_y)

	# Gentle sinusoidal oscillation for higher scores
	if score >= 300 and randf() < 0.45:
		pipe_parent.set_meta("bob_speed", randf_range(1.8, 3.2))
		pipe_parent.set_meta("bob_amp", randf_range(18.0, 32.0))
		pipe_parent.set_meta("bob_t", randf_range(0.0, TAU))

	# Top Pipe hangs down from Y=0
	var top_pipe := _create_pipe_sprite(gap_y - GAP_SIZE / 2.0, false)
	top_pipe.name = "TopPipe"
	top_pipe.position = Vector2(0, 0)
	pipe_parent.add_child(top_pipe)

	# Bottom Pipe rises from gap downward
	var bottom_pipe := _create_pipe_sprite(960.0 - (gap_y + GAP_SIZE / 2.0), true)
	bottom_pipe.name = "BottomPipe"
	bottom_pipe.position = Vector2(0, gap_y + GAP_SIZE / 2.0)
	pipe_parent.add_child(bottom_pipe)

	# Faint pulsating energy field between gate emitters
	var gate_field := GateEnergyField.new(GAP_SIZE)
	gate_field.position = Vector2(PIPE_WIDTH * 0.5, gap_y)
	pipe_parent.add_child(gate_field)

	obstacle_container.add_child(pipe_parent)

	# 60% Chance to spawn a floating Energy Shard inside or near the gate gap
	if randf() < 0.60:
		_spawn_shard(Vector2(580 + PIPE_WIDTH * 0.5, gap_y))

func _create_pipe_sprite(height: float, flipped: bool) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = PIPE_TEXTURE
	spr.centered = false
	spr.flip_v = flipped
	spr.scale = Vector2(PIPE_WIDTH / PIPE_TEXTURE.get_width(), max(height, 1.0) / PIPE_TEXTURE.get_height())
	return spr

func _spawn_shard(pos: Vector2) -> void:
	var shard := CollectibleShard.new()
	shard.position = pos
	shard.set_meta("base_y", pos.y)
	shard.set_meta("t", randf_range(0.0, TAU))
	collectible_container.add_child(shard)

# -----------------------------------------------------------------------------
# CLOUDS & MOTION TRAIL
# -----------------------------------------------------------------------------
func _update_clouds(delta: float) -> void:
	cloud_timer -= delta
	if cloud_timer <= 0:
		_spawn_cloud(580)
		cloud_timer = randf_range(3.0, 5.5)

	for cloud in cloud_container.get_children():
		cloud.position.x -= scroll_speed * 0.32 * delta
		if cloud.position.x < -240:
			cloud.queue_free()

func _spawn_cloud(start_x: float) -> void:
	var cloud := Sprite2D.new()
	cloud.texture = CLOUD_TEXTURE
	cloud.centered = true
	cloud.position = Vector2(start_x, randf_range(90, 810))
	cloud.modulate = Color(1, 1, 1, randf_range(0.35, 0.70))
	var s := randf_range(0.75, 1.35)
	cloud.scale = Vector2(s, s * 0.8)
	cloud_container.add_child(cloud)

func _spawn_ghost_trail() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = PLAYER_TEXTURE
	ghost.centered = true
	ghost.position = player.position
	ghost.rotation = player.rotation
	ghost.scale = player.scale
	ghost.modulate = Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.35)
	fx_container.add_child(ghost)

	var tw := create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(ghost, "scale", player.scale * 0.75, 0.22)
	tw.tween_callback(ghost.queue_free)

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


# =============================================================================
# SUB-COMPONENTS (Parallax City, Embers, Gate Fields & Hazard Barriers)
# =============================================================================

## Procedural Parallax Cyber City Skyline (Scrolling Silhouette)
class CyberSkyline extends Node2D:
	var buildings: Array[Dictionary] = []
	var offset_x: float = 0.0

	func _init() -> void:
		# Generate a seamless sequence of futuristic skyscrapers
		var cur_x := -100.0
		while cur_x < 800.0:
			var w := randf_range(45.0, 85.0)
			var h := randf_range(160.0, 360.0)
			var has_antenna := randf() < 0.6
			buildings.append({
				"x": cur_x,
				"w": w,
				"h": h,
				"antenna": has_antenna,
				"beacon_color": Tokens.FLAME if randf() < 0.7 else Tokens.VOLT
			})
			cur_x += w + randf_range(8.0, 24.0)

	func _process(delta: float) -> void:
		offset_x -= 16.0 * delta
		if offset_x < -300.0:
			offset_x += 300.0
		queue_redraw()

	func _draw() -> void:
		var ground_y := 900.0
		var col_silhouette := Color("#100816")
		var col_window := Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.08)

		for b in buildings:
			var draw_x: float = b["x"] + offset_x
			var w: float = b["w"]
			var h: float = b["h"]
			var top_y := ground_y - h

			# Skyscraper Block
			draw_rect(Rect2(draw_x, top_y, w, h), col_silhouette, true)
			draw_rect(Rect2(draw_x, top_y, 2, h), Color("#241530"), true) # Bezel edge

			# Subtle window lines
			for row in range(3):
				var wy := top_y + 25.0 + row * 28.0
				draw_rect(Rect2(draw_x + 8, wy, w - 16, 2), col_window, true)

			# Rooftop Antenna with blinking beacon
			if b["antenna"]:
				var ax := draw_x + w * 0.5
				draw_line(Vector2(ax, top_y), Vector2(ax, top_y - 20), Color("#241530"), 1.5)
				var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005 + b["x"])
				var b_col: Color = b["beacon_color"]
				b_col.a = blink
				draw_circle(Vector2(ax, top_y - 20), 2.0, b_col)


## Ambient Floating Cyber-Embers
class EmberField extends Node2D:
	var embers: Array[Dictionary] = []

	func _init() -> void:
		for i in range(32):
			embers.append({
				"pos": Vector2(randf_range(0, 540), randf_range(40, 880)),
				"speed_x": randf_range(-18.0, -38.0),
				"speed_y": randf_range(-12.0, -28.0),
				"size": randf_range(1.5, 3.2),
				"phase": randf_range(0.0, TAU),
				"color": Tokens.FLAME if randf() < 0.65 else Tokens.VOLT
			})

	func _process(delta: float) -> void:
		for e in embers:
			e["pos"].x += e["speed_x"] * delta
			e["pos"].y += e["speed_y"] * delta
			e["phase"] += delta * 3.0
			if e["pos"].x < -10.0:
				e["pos"].x = 550.0
				e["pos"].y = randf_range(100, 880)
			if e["pos"].y < 20.0:
				e["pos"].y = 880.0
		queue_redraw()

	func _draw() -> void:
		for e in embers:
			var alpha := 0.35 + 0.45 * (0.5 + 0.5 * sin(e["phase"]))
			var col: Color = e["color"]
			col.a = alpha
			draw_circle(e["pos"], e["size"], col)


## Gate Energy Field (Glowing laser field spanning the pipe gap)
class GateEnergyField extends Node2D:
	var gap_h: float = 300.0

	func _init(h: float) -> void:
		gap_h = h

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var half_h := gap_h * 0.5
		var t := Time.get_ticks_msec() * 0.006
		var alpha := 0.12 + 0.08 * sin(t)

		# Center glowing beam
		draw_line(Vector2(0, -half_h), Vector2(0, half_h), Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, alpha), 3.0)
		draw_line(Vector2(0, -half_h), Vector2(0, half_h), Color(1, 1, 1, alpha * 0.6), 1.0)


## Hazard Barrier (Animated scrolling laser & hazard stripes)
class HazardBarrier extends Node2D:
	var origin: Vector2
	var barrier_size: Vector2
	var is_ceiling: bool
	var scroll_offset: float = 0.0

	func _init(pos: Vector2, sz: Vector2, ceiling: bool) -> void:
		origin = pos
		barrier_size = sz
		is_ceiling = ceiling

	func _process(delta: float) -> void:
		scroll_offset -= 90.0 * delta
		if scroll_offset <= -24.0:
			scroll_offset += 24.0
		queue_redraw()

	func _draw() -> void:
		# Dark base box
		draw_rect(Rect2(origin, barrier_size), Tokens.INK, true)

		# Scrolling diagonal caution hazard hash marks
		var stripe_w := 12.0
		var x := origin.x + scroll_offset - stripe_w * 2.0
		var col_stripe := Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.45)

		while x < origin.x + barrier_size.x + stripe_w * 2.0:
			if is_ceiling:
				draw_line(Vector2(x, origin.y), Vector2(x + 10, origin.y + barrier_size.y), col_stripe, 3.0)
			else:
				draw_line(Vector2(x, origin.y + barrier_size.y), Vector2(x + 10, origin.y), col_stripe, 3.0)
			x += stripe_w * 2.0

		# Neon Laser Edge Line
		var laser_y := origin.y if not is_ceiling else origin.y + barrier_size.y
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
		# Glow spread
		draw_line(Vector2(origin.x, laser_y), Vector2(origin.x + barrier_size.x, laser_y), Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.3 * pulse), 6.0)
		# Sharp core laser
		draw_line(Vector2(origin.x, laser_y), Vector2(origin.x + barrier_size.x, laser_y), Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.95), 2.0)
		draw_line(Vector2(origin.x, laser_y), Vector2(origin.x + barrier_size.x, laser_y), Color(1, 1, 1, 0.8), 1.0)


## Procedural Glowing Collectible Energy Shard
class CollectibleShard extends Node2D:
	var rot_angle: float = 0.0
	var pulse_phase: float = 0.0

	func _process(delta: float) -> void:
		rot_angle += 2.8 * delta
		pulse_phase += 5.0 * delta
		queue_redraw()

	func _draw() -> void:
		var scale_pulse := 1.0 + 0.12 * sin(pulse_phase)

		# Radiant Ambient Glow
		draw_circle(Vector2.ZERO, 22.0 * scale_pulse, Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.16))
		draw_circle(Vector2.ZERO, 15.0 * scale_pulse, Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.22))

		# 3D Spinning Diamond Facets
		var s := 13.0 * scale_pulse
		var cos_r := cos(rot_angle)
		var sin_r := sin(rot_angle)
		var top := Vector2(-sin_r * s * 1.3, -cos_r * s * 1.3)
		var bottom := -top
		var right := Vector2(cos_r * s * 0.9, -sin_r * s * 0.9)
		var left := -right

		# 4 Shaded Polygonal Crystal Facets
		draw_colored_polygon(PackedVector2Array([top, right, Vector2.ZERO]), Color("#FFE885"))
		draw_colored_polygon(PackedVector2Array([top, left, Vector2.ZERO]), Color("#FFFFFF"))
		draw_colored_polygon(PackedVector2Array([bottom, right, Vector2.ZERO]), Tokens.FLAME)
		draw_colored_polygon(PackedVector2Array([bottom, left, Vector2.ZERO]), Color("#E65100"))

		# Center Sparkle Core
		draw_circle(Vector2.ZERO, 2.5 * scale_pulse, Color.WHITE)


## Protective Energy Shield Ring around Player
class PlayerShieldRing extends Node2D:
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
		var r := 42.0 + 1.5 * sin(t)
		var col := Tokens.FLAME
		col.a = 0.40 + 0.20 * sin(t * 1.5)
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, col, 1.8)
		# Specular glint arc
		var glint_angle := t * 1.2
		draw_arc(Vector2.ZERO, r, glint_angle - 0.5, glint_angle + 0.5, 12, Color(1, 1, 1, col.a * 0.8), 2.2)
