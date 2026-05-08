extends GameBase

var player: ColorRect
var hud: CanvasLayer
var obstacle_container: Node2D

var speed = 300.0
var spawn_timer = 2.0
var current_lane = 1 # 0: left, 1: center, 2: right
var lane_x = [100.0, 250.0, 400.0]
var target_x = 250.0
var last_lunge_side = -1
var has_started = false

func _ready():
	game_name = "3-Lane Switcher"
	ExerciseRecognizer.set_active_exercise("Lunges")
	
	player = $Player
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
		
		if abs(obs.position.x - player.position.x) < 40 and abs(obs.position.y - player.position.y) < 40:
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
	var obs = ColorRect.new()
	obs.color = Color("#EF4444")
	obs.size = Vector2(60, 40)
	var lane = randi() % 3
	obs.position = Vector2(lane_x[lane], -100)
	obstacle_container.add_child(obs)
