extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Runner-Pod.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/3 Lane/Laser-Barricade.svg")

var player: Sprite2D
var hud: CanvasLayer
var obstacle_container: Node2D

var speed = 300.0
var spawn_timer = 2.0
var current_lane = 1 # 0: left, 1: center, 2: right
var lane_x = [120.0, 270.0, 420.0]
var target_x = 270.0
var last_lunge_side = -1
var has_started = false

func _ready():
	game_name = "Lane Switcher"
	ExerciseRecognizer.set_active_exercise("Lunges")
	
	player = $Player
	player.texture = PLAYER_TEXTURE
	# center sprites (position refers to center) and reduce scale slightly
	player.centered = true
	player.scale = Vector2(0.8, 0.8)
	hud = $HUD
	obstacle_container = $Obstacles

func start_game():
	super.start_game()
	current_lane = 1
	target_x = lane_x[1]
	player.position = Vector2(target_x, 700)
	spawn_timer = 2.0
	has_started = false
	for obs in obstacle_container.get_children():
		obs.queue_free()

func _process(delta):
	if not is_running: return
	if not has_started: return
	
	player.position.x = lerp(player.position.x, target_x, 10.0 * delta)
	
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_obstacle()
		spawn_timer = randf_range(1.0, 2.0)
		
	for obs in obstacle_container.get_children():
		obs.position.y += speed * delta
		if obs.position.y > 1000:
			obs.queue_free()
			add_score(1)
			hud.update_score(score)
		
		# collision using rectangular overlap suitable for centered sprites
		var player_w = 56
		var player_h = 56
		var obs_w = 56
		var obs_h = 56
		var player_rect = Rect2(player.position.x - player_w/2, player.position.y - player_h/2, player_w, player_h)
		var obs_rect = Rect2(obs.position.x - obs_w/2, obs.position.y - obs_h/2, obs_w, obs_h)
		if player_rect.intersects(obs_rect):
			end_game()

func on_rep_completed(rep_count: int) -> void:
	if not has_started:
		has_started = true
	# Read which side was lunged directly from the exercise object
	var exercise = ExerciseRecognizer.current_exercise
	var side = exercise.lunge_side if exercise and exercise.get("lunge_side") != null else -1
	if side == 0 and current_lane > 0:
		current_lane -= 1
	elif side == 1 and current_lane < 2:
		current_lane += 1
	target_x = lane_x[current_lane]

func _spawn_obstacle():
	var obs = Sprite2D.new()
	obs.texture = OBSTACLE_TEXTURE
	# centered so position aligns with player's x
	obs.centered = true
	obs.scale = Vector2(1.0, 1.0)
	var lane = randi() % 3
	# spawn above the top of the screen
	obs.position = Vector2(lane_x[lane], -40)
	obstacle_container.add_child(obs)
