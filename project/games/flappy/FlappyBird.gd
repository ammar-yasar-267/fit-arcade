extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Player-Character_Neon-Runner-Orb.svg")
const PIPE_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Obstacle_Pipe.svg")
const CLOUD_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Cloud-Neon.svg")

var player: Sprite2D
var hud: CanvasLayer
var obstacle_container: Node2D
var cloud_container: Node2D

var scroll_speed = 120.0
var jump_velocity = -310.0
var gravity = 350.0
var spawn_timer = 2.0
var velocity_y = 0.0
var pipe_width = 80.0
var gap_size = 310.0
var player_hitbox_size = 60.0
var player_visual_scale = 1.0
var pipe_spawn_min_y = 220.0
var pipe_spawn_max_y = 600.0
var pipe_spawn_min_interval = 2.8
var pipe_spawn_max_interval = 4.0
var has_started = false
var cloud_timer = 0.0

func _ready():
	game_name = "Flappy Bird"
	ExerciseRecognizer.set_active_exercise("Arm Raises")

	player = $Player
	player.texture = PLAYER_TEXTURE
	player.centered = false
	player.scale = Vector2(player_visual_scale, player_visual_scale)
	hud = $HUD
	obstacle_container = $Obstacles

	_setup_environment()

func _setup_environment() -> void:
	# Push the scene background behind all dynamic elements
	var bg = get_node_or_null("Background")
	if bg: bg.z_index = -10

	# Cloud container — between background and gameplay elements
	cloud_container = Node2D.new()
	cloud_container.z_index = -5
	add_child(cloud_container)

	# Pre-seed clouds across the screen
	for i in range(5):
		_spawn_cloud(randf_range(0, 540))

	# Danger strip at the floor (always on top)
	var gnd = ColorRect.new()
	gnd.color = Color(0.10, 0.05, 0.24, 1.0)
	gnd.size = Vector2(540, 44)
	gnd.position = Vector2(0, 916)
	gnd.z_index = 5
	add_child(gnd)

	var gnd_line = ColorRect.new()
	gnd_line.color = Color(0.94, 0.27, 0.27, 0.65)
	gnd_line.size = Vector2(540, 3)
	gnd_line.position = Vector2(0, 916)
	gnd_line.z_index = 6
	add_child(gnd_line)

	# Danger strip at the ceiling (always on top)
	var ceil_line = ColorRect.new()
	ceil_line.color = Color(0.94, 0.27, 0.27, 0.40)
	ceil_line.size = Vector2(540, 3)
	ceil_line.position = Vector2(0, 0)
	ceil_line.z_index = 6
	add_child(ceil_line)

func start_game():
	super.start_game()
	player.position = Vector2(100, 400)
	velocity_y = 0.0
	spawn_timer = 1.8
	has_started = false
	for obs in obstacle_container.get_children():
		obs.queue_free()

func _process(delta):
	if not is_running: return

	_update_clouds(delta)

	if not has_started: return

	velocity_y += gravity * delta
	player.position.y += velocity_y * delta

	if player.position.y > 960 - player_hitbox_size or player.position.y < 0:
		end_game()

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_pipe()
		spawn_timer = randf_range(pipe_spawn_min_interval, pipe_spawn_max_interval)

	for obs in obstacle_container.get_children():
		obs.position.x -= scroll_speed * delta
		if obs.position.x < -pipe_width - 40:
			obs.queue_free()

		# Score check
		if not obs.get_meta("scored") and obs.position.x < player.position.x:
			obs.set_meta("scored", true)
			add_score(1)
			hud.update_score(score)

		# Collision
		var top_rect = Rect2(obs.position.x, 0, pipe_width, obs.get_meta("gap_y") - gap_size / 2)
		var bottom_rect = Rect2(obs.position.x, obs.get_meta("gap_y") + gap_size / 2, pipe_width, 960)
		var player_rect = Rect2(player.position.x, player.position.y, player_hitbox_size, player_hitbox_size)

		if player_rect.intersects(top_rect) or player_rect.intersects(bottom_rect):
			end_game()

func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true
	velocity_y = jump_velocity

func _spawn_pipe():
	var gap_y = randf_range(pipe_spawn_min_y, pipe_spawn_max_y)

	var top_pipe = _create_pipe_sprite(gap_y - gap_size / 2, false)
	top_pipe.position = Vector2(0, 0)

	var bottom_pipe = _create_pipe_sprite(960 - (gap_y + gap_size / 2), true)
	bottom_pipe.position = Vector2(0, gap_y + gap_size / 2)

	var pipe_parent = Node2D.new()
	pipe_parent.position = Vector2(600, 0)
	pipe_parent.set_meta("scored", false)
	pipe_parent.set_meta("gap_y", gap_y)

	pipe_parent.add_child(top_pipe)
	pipe_parent.add_child(bottom_pipe)
	obstacle_container.add_child(pipe_parent)

func _create_pipe_sprite(height: float, flipped: bool) -> Sprite2D:
	var pipe_sprite := Sprite2D.new()
	pipe_sprite.texture = PIPE_TEXTURE
	pipe_sprite.centered = false
	pipe_sprite.flip_v = flipped
	pipe_sprite.scale = Vector2(pipe_width / PIPE_TEXTURE.get_width(), max(height, 1.0) / PIPE_TEXTURE.get_height())
	return pipe_sprite

func _update_clouds(delta: float) -> void:
	cloud_timer -= delta
	if cloud_timer <= 0:
		_spawn_cloud(610)
		cloud_timer = randf_range(2.5, 5.0)

	for cloud in cloud_container.get_children():
		cloud.position.x -= scroll_speed * 0.35 * delta
		if cloud.position.x < -220:
			cloud.queue_free()

func _spawn_cloud(start_x: float) -> void:
	var cloud = Sprite2D.new()
	cloud.texture = CLOUD_TEXTURE
	cloud.centered = true
	cloud.position = Vector2(start_x, randf_range(80, 830))
	cloud.modulate = Color(1, 1, 1, randf_range(0.22, 0.52))
	var s = randf_range(0.7, 1.4)
	cloud.scale = Vector2(s, s * 0.8)
	cloud_container.add_child(cloud)
