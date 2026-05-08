extends GameBase

const PLAYER_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Player-Character_Neon-Runner-Orb.svg")
const PIPE_TEXTURE: Texture2D = preload("res://ui/assets/Flappy Bird/Obstacle_Pipe.svg")

var player: Sprite2D
var hud: CanvasLayer
var obstacle_container: Node2D

var scroll_speed = 150.0
var jump_velocity = -340.0
var gravity = 430.0
var spawn_timer = 2.0
var velocity_y = 0.0
var pipe_width = 80.0
var gap_size = 300.0
var player_hitbox_size = 40.0
var player_visual_scale = 0.7
var pipe_spawn_min_y = 220.0
var pipe_spawn_max_y = 600.0
var pipe_spawn_min_interval = 2.4
var pipe_spawn_max_interval = 3.2
var has_started = false

func _ready():
	game_name = "Flappy Bird"
	ExerciseRecognizer.set_active_exercise("Arm Raises")
	
	player = $Player
	player.texture = PLAYER_TEXTURE
	player.centered = false
	player.scale = Vector2(player_visual_scale, player_visual_scale)
	hud = $HUD
	obstacle_container = $Obstacles

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
	
	if not has_started:
		return
	
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
		var top_rect = Rect2(obs.position.x, 0, pipe_width, obs.get_meta("gap_y") - gap_size/2)
		var bottom_rect = Rect2(obs.position.x, obs.get_meta("gap_y") + gap_size/2, pipe_width, 960)
		var player_rect = Rect2(player.position.x, player.position.y, player_hitbox_size, player_hitbox_size)
		
		if player_rect.intersects(top_rect) or player_rect.intersects(bottom_rect):
			end_game()

func on_rep_completed(rep_count: int) -> void:
	if not has_started:
		has_started = true
	velocity_y = jump_velocity

func _spawn_pipe():
	var gap_y = randf_range(pipe_spawn_min_y, pipe_spawn_max_y)
	
	var top_pipe = _create_pipe_sprite(gap_y - gap_size/2, false)
	top_pipe.position = Vector2(0, 0)
	
	var bottom_pipe = _create_pipe_sprite(960 - (gap_y + gap_size/2), true)
	bottom_pipe.position = Vector2(0, gap_y + gap_size/2)
	
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
