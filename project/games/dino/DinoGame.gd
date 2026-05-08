extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/dino/Dino.svg")
const OBSTACLE_TEXTURE: Texture2D = preload("res://ui/assets/dino/Dino-Neon-Cactus.svg")

var player: Sprite2D
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
	player.texture = PLAYER_TEXTURE
	player.centered = false
	# Increase player size to match app visuals
	player.scale = Vector2(0.9, 0.9)
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
		
		# Collision (adjusted for larger sprite dimensions)
		var player_rect = Rect2(player.position.x, player.position.y, 60, 60)
		var obs_rect = Rect2(obs.position.x, obs.position.y, 60, 80)
		if player_rect.intersects(obs_rect):
			end_game()

func on_rep_completed(rep_count: int) -> void:
	if not has_started:
		has_started = true
	if player.position.y >= 490:
		velocity_y = jump_velocity

func _spawn_obstacle():
	var obs = Sprite2D.new()
	obs.texture = OBSTACLE_TEXTURE
	obs.centered = false
	# Make obstacle larger and place it on the ground level
	obs.scale = Vector2(0.9, 0.9)
	# Position aligned roughly to player's baseline (y=500)
	obs.position = Vector2(600, 500)
	obstacle_container.add_child(obs)
