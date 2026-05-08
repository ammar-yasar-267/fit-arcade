extends GameBase

var player: ColorRect
var hud: CanvasLayer
var ground: ColorRect
var obstacle_container: Node2D

var speed = 200.0
var jump_velocity = -900.0
var gravity = 1500.0
var spawn_timer = 2.0
var velocity_y = 0.0
var has_started = false

func _ready():
	game_name = "Chrome Dino"
	ExerciseRecognizer.set_active_exercise("Jumping Jacks")
	
	player = $Player
	hud = $HUD
	ground = $Ground
	obstacle_container = $Obstacles

func start_game():
	super.start_game()
	player.position = Vector2(100, 500)
	velocity_y = 0.0
	spawn_timer = 2.0
	has_started = false
	for obs in obstacle_container.get_children():
		obs.queue_free()

func _process(delta):
	if not is_running: return
	
	if not has_started:
		return
	
	velocity_y += gravity * delta
	player.position.y += velocity_y * delta
	
	if player.position.y >= 500:
		player.position.y = 500
		if velocity_y > 0:
			velocity_y = 0
	
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_obstacle()
		spawn_timer = randf_range(1.2, 2.2)
		
	for obs in obstacle_container.get_children():
		obs.position.x -= speed * delta
		if obs.position.x < -100:
			obs.queue_free()
			add_score(1)
			hud.update_score(score)
		
		# Collision
		if abs(obs.position.x - player.position.x) < 40 and abs(obs.position.y - player.position.y) < 40:
			end_game()

func on_rep_completed(rep_count: int) -> void:
	if not has_started:
		has_started = true
	if player.position.y >= 490:
		velocity_y = jump_velocity

func _spawn_obstacle():
	var obs = ColorRect.new()
	obs.color = Color("#EF4444")
	obs.size = Vector2(40, 60)
	obs.position = Vector2(600, 480)
	obstacle_container.add_child(obs)
