extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Dino.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Dino-Neon-Cactus.svg")

var player: Sprite2D
var hud: CanvasLayer
var ground: ColorRect
var obstacle_container: Node2D

var speed = 260.0
var jump_velocity = -950.0
var gravity = 1700.0
var spawn_timer = 2.0
var velocity_y = 0.0
var has_started = false

var ground_marks: Array = []
var ground_mark_timer: float = 0.0

func _ready():
	game_name = "Chrome Dino"
	ExerciseRecognizer.set_active_exercise("Jumping Jacks")

	player = $Player
	player.texture = PLAYER_TEXTURE
	player.centered = false
	player.scale = Vector2(0.9, 0.9)
	player.z_index = 10

	hud = $HUD
	ground = $Ground
	obstacle_container = $Obstacles

	var bg = get_node_or_null("Background")
	if bg: bg.z_index = -10
	if ground: ground.z_index = -5

	_setup_background()

func _setup_background() -> void:
	# Starfield in the sky area
	var star_root = Node2D.new()
	star_root.z_index = -9
	add_child(star_root)

	for i in range(70):
		var star = ColorRect.new()
		var b = randf_range(0.3, 0.85)
		star.color = Color(b, b, b + 0.15, 1.0)
		var sz = randf_range(1.5, 3.2)
		star.size = Vector2(sz, sz)
		star.position = Vector2(randf_range(0, 540), randf_range(10, 500))
		star_root.add_child(star)

	# Neon ground line sitting on top of the ground rect
	var gnd_line = ColorRect.new()
	gnd_line.color = Color(0.49, 0.23, 0.93, 0.55)
	gnd_line.size = Vector2(540, 3)
	gnd_line.position = Vector2(0, 537)
	gnd_line.z_index = -4
	add_child(gnd_line)

func start_game():
	super.start_game()
	player.position = Vector2(100, 500)
	velocity_y = 0.0
	spawn_timer = 2.0
	has_started = false
	for obs in obstacle_container.get_children():
		obs.queue_free()
	for mark in ground_marks:
		mark.queue_free()
	ground_marks.clear()
	ground_mark_timer = 0.0

func _process(delta):
	if not is_running: return
	if not has_started: return

	velocity_y += gravity * delta
	player.position.y += velocity_y * delta

	if player.position.y >= 500:
		player.position.y = 500
		if velocity_y > 0:
			velocity_y = 0

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_obstacle()
		spawn_timer = randf_range(1.0, 1.8)

	for obs in obstacle_container.get_children():
		obs.position.x -= speed * delta
		if obs.position.x < -100:
			obs.queue_free()
			add_score(1)
			if hud and hud.has_method("update_score"):
				hud.update_score(score)

		# Collision
		var player_rect = Rect2(player.position.x, player.position.y, 60, 60)
		var obs_rect = Rect2(obs.position.x, obs.position.y, 60, 80)
		if player_rect.intersects(obs_rect):
			end_game()

	# Scrolling ground dashes
	ground_mark_timer -= delta
	if ground_mark_timer <= 0:
		_spawn_ground_mark()
		ground_mark_timer = 0.42

	for mark in ground_marks.duplicate():
		mark.position.x -= speed * delta
		if mark.position.x < -100:
			mark.queue_free()
			ground_marks.erase(mark)

func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true
	if player.position.y >= 490:
		velocity_y = jump_velocity

func _spawn_obstacle():
	var obs = Sprite2D.new()
	obs.texture = OBSTACLE_TEXTURE
	obs.centered = false
	obs.z_index = 10
	obs.scale = Vector2(0.9, 0.9)
	obs.position = Vector2(600, 500)
	obstacle_container.add_child(obs)

func _spawn_ground_mark() -> void:
	var mark = ColorRect.new()
	mark.color = Color(0.35, 0.28, 0.58, 0.55)
	mark.size = Vector2(55, 4)
	mark.position = Vector2(580, 537)
	mark.z_index = -4
	add_child(mark)
	ground_marks.append(mark)
