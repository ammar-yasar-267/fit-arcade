extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Runner-Pod.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Laser-Barricade.svg")

var player: Sprite2D
var hud: CanvasLayer
var obstacle_container: Node2D

var speed = 210.0        # pixels/sec obstacle drop speed
var spawn_timer = 2.2
var current_lane = 1     # 0 = left, 1 = centre, 2 = right
var lane_x = [120.0, 270.0, 420.0]  # screen X position for each lane
var target_x = 270.0     # player smoothly lerps toward this X each frame
var last_lunge_side = -1
var has_started = false  # first rep starts the game

var speed_lines: Array = []
var speed_line_timer: float = 0.0

func _ready():
	game_name = "Lane Switcher"
	ExerciseRecognizer.set_active_exercise("Lunges")

	player = $Player
	player.texture = PLAYER_TEXTURE
	player.centered = true
	player.scale = Vector2(0.8, 0.8)
	hud = $HUD
	obstacle_container = $Obstacles

	_setup_background()

func _setup_background() -> void:
	# Push the scene background behind all dynamic elements
	var bg = get_node_or_null("Background")
	if bg: bg.z_index = -10

	# Pre-seed speed lines spread across the screen
	for i in range(14):
		_spawn_speed_line(randf_range(0, 960))

func start_game():
	super.start_game()
	current_lane = 1
	target_x = lane_x[1]
	player.position = Vector2(target_x, 700)
	spawn_timer = 2.2
	has_started = false
	for obs in obstacle_container.get_children():
		obs.queue_free()

func _process(delta):
	if not is_running: return

	_update_speed_lines(delta)

	if not has_started: return

	# Smooth slide between lanes rather than instant teleport
	player.position.x = lerp(player.position.x, target_x, 10.0 * delta)

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_obstacle()
		spawn_timer = randf_range(2.2, 3.5)

	for obs in obstacle_container.get_children():
		obs.position.y += speed * delta
		if obs.position.y > 1000:
			obs.queue_free()
			add_score(1)
			hud.update_score(score)

		var player_w = 56.0
		var player_h = 56.0
		var obs_w = 56.0
		var obs_h = 56.0
		var player_rect = Rect2(player.position.x - player_w / 2.0, player.position.y - player_h / 2.0, player_w, player_h)
		var obs_rect = Rect2(obs.position.x - obs_w / 2.0, obs.position.y - obs_h / 2.0, obs_w, obs_h)
		if player_rect.intersects(obs_rect):
			end_game()

func on_rep_completed(_rep_count: int) -> void:
	if not has_started:
		has_started = true
	var exercise = ExerciseRecognizer.current_exercise
	# lunge_side: 0 = left lunge → move left, 1 = right lunge → move right
	var side = exercise.lunge_side if exercise and exercise.get("lunge_side") != null else -1
	if side == 0 and current_lane > 0:
		current_lane -= 1
	elif side == 1 and current_lane < 2:
		current_lane += 1
	target_x = lane_x[current_lane]

func _spawn_obstacle():
	var obs = Sprite2D.new()
	obs.texture = OBSTACLE_TEXTURE
	obs.centered = true
	obs.scale = Vector2(1.0, 1.0)
	var lane: int
	if randf() < 0.75:
		# Target the player's current lane
		lane = current_lane
	else:
		# Pick a different lane for breathing room
		var other_lanes = [0, 1, 2]
		other_lanes.erase(current_lane)
		lane = other_lanes[randi() % 2]
	obs.position = Vector2(lane_x[lane], -40)
	obstacle_container.add_child(obs)

func _update_speed_lines(delta: float) -> void:
	speed_line_timer -= delta
	if speed_line_timer <= 0:
		_spawn_speed_line(randf_range(-120, -20))
		speed_line_timer = randf_range(0.12, 0.35)

	for line_rect in speed_lines.duplicate():
		line_rect.position.y += speed * 0.55 * delta
		if line_rect.position.y > 1020:
			line_rect.queue_free()
			speed_lines.erase(line_rect)

func _spawn_speed_line(start_y: float) -> void:
	var line_rect = ColorRect.new()
	var alpha = randf_range(0.07, 0.22)
	line_rect.color = Color(0.49, 0.23, 0.93, alpha)
	var h = randf_range(50, 160)
	line_rect.size = Vector2(randf_range(1.5, 3.0), h)
	line_rect.position = Vector2(randf_range(16, 524), start_y)
	line_rect.z_index = -3
	add_child(line_rect)
	speed_lines.append(line_rect)
