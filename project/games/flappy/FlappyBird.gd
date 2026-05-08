extends GameBase

var player: ColorRect
var hud: CanvasLayer
var obstacle_container: Node2D

var scroll_speed = 120.0
var jump_velocity = -300.0
var gravity = 400.0
var spawn_timer = 4.0
var velocity_y = 0.0
var pipe_width = 80.0
var gap_size = 350.0
var has_started = false

func _ready():
	game_name = "Flappy Bird"
	ExerciseRecognizer.set_active_exercise("Arm Raises")
	
	player = $Player
	hud = $HUD
	obstacle_container = $Obstacles

func start_game():
	super.start_game()
	player.position = Vector2(100, 400)
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
	
	if player.position.y > 960 or player.position.y < 0:
		end_game()
	
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_pipe()
		spawn_timer = 4.0
		
	for obs in obstacle_container.get_children():
		obs.position.x -= scroll_speed * delta
		if obs.position.x < -100:
			obs.queue_free()
		
		# Score check
		if not obs.get_meta("scored") and obs.position.x < player.position.x:
			obs.set_meta("scored", true)
			add_score(1)
			hud.update_score(score)
			
		# Collision
		var top_rect = Rect2(obs.position.x, 0, pipe_width, obs.get_meta("gap_y") - gap_size/2)
		var bottom_rect = Rect2(obs.position.x, obs.get_meta("gap_y") + gap_size/2, pipe_width, 960)
		var player_rect = Rect2(player.position.x, player.position.y, 40, 40)
		
		if player_rect.intersects(top_rect) or player_rect.intersects(bottom_rect):
			end_game()

func on_rep_completed(rep_count: int) -> void:
	if not has_started:
		has_started = true
	velocity_y = jump_velocity

func _spawn_pipe():
	var gap_y = randf_range(300, 700)
	
	var top_pipe = ColorRect.new()
	top_pipe.color = Color("#22C55E")
	top_pipe.size = Vector2(pipe_width, gap_y - gap_size/2)
	top_pipe.position = Vector2(0, 0)
	
	var bottom_pipe = ColorRect.new()
	bottom_pipe.color = Color("#22C55E")
	bottom_pipe.size = Vector2(pipe_width, 960 - (gap_y + gap_size/2))
	bottom_pipe.position = Vector2(0, gap_y + gap_size/2)
	
	var pipe_parent = Node2D.new()
	pipe_parent.position = Vector2(600, 0)
	pipe_parent.set_meta("scored", false)
	pipe_parent.set_meta("gap_y", gap_y)
	
	pipe_parent.add_child(top_pipe)
	pipe_parent.add_child(bottom_pipe)
	obstacle_container.add_child(pipe_parent)
