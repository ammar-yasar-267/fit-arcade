extends GameBase

## Flappy Bird-style POC game.
## Each rep_completed signal = 1 flap (upward impulse).
## Pipes scroll from right to left. Score = pipes passed.

@onready var bird: CharacterBody2D = $Bird
@onready var pipe_timer: Timer = $PipeTimer
@onready var score_label: Label = $UI/ScoreLabel
@onready var rep_label: Label = $UI/RepLabel
@onready var feedback_label: Label = $UI/FeedbackLabel
@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_score: Label = $UI/GameOverPanel/VBoxContainer/ScoreValue
@onready var restart_btn: Button = $UI/GameOverPanel/VBoxContainer/RestartButton

const GRAVITY := 200.0         # Slight fall urgency — arm raises ~2-3s between flaps
const FLAP_VELOCITY := -300.0  # Strong flap for satisfying lift
const PIPE_SPEED := 82.0       # Gentle scroll pace
const PIPE_GAP := 440.0        # Wide gap — forgiving for imprecise flaps
const PIPE_WIDTH := 80.0

var bird_velocity := 0.0
var pipe_container: Node2D
var game_area_size := Vector2(540, 960)
var feedback_timer := 0.0

enum GameState {COUNTDOWN, PLAYING, GAME_OVER}
var current_state := GameState.COUNTDOWN
var countdown_timer := 3.99

func _init() -> void:
	game_name = "Flappy Bird"

func _ready() -> void:
	pipe_container = Node2D.new()
	pipe_container.name = "Pipes"
	add_child(pipe_container)

	pipe_timer.timeout.connect(_spawn_pipe)
	restart_btn.pressed.connect(_restart)
	game_over_panel.hide()
	feedback_label.text = ""

	# Adapt to actual viewport size
	game_area_size = get_viewport_rect().size

	start_game()

func start_game() -> void:
	super ()
	bird.position = Vector2(game_area_size.x * 0.2, game_area_size.y * 0.5)
	bird_velocity = 0.0
	score_label.text = "Score: 0"
	rep_label.text = "Reps: 0"
	game_over_panel.hide()
	feedback_label.text = ""

	# Clear old pipes
	for child in pipe_container.get_children():
		child.queue_free()

	current_state = GameState.COUNTDOWN
	countdown_timer = 3.99
	feedback_label.add_theme_color_override("font_color", Color.WHITE)
	feedback_label.text = "3"

func _restart() -> void:
	ExerciseManager.start_exercise()
	start_game()

func _process(delta: float) -> void:
	if not is_running:
		return

	if current_state == GameState.COUNTDOWN:
		var old_sec := int(countdown_timer)
		countdown_timer -= delta
		var new_sec := int(countdown_timer)
		
		if countdown_timer <= 0:
			current_state = GameState.PLAYING
			feedback_label.add_theme_color_override("font_color", Color.GREEN)
			feedback_label.text = "GO!"
			feedback_timer = 1.0
			pipe_timer.start(5.0)  # One pipe per arm raise cycle (~2-3s down + 2s up)
		elif new_sec != old_sec:
			feedback_label.text = str(new_sec)
		return

	if current_state != GameState.PLAYING:
		return

	# Gravity
	bird_velocity += GRAVITY * delta
	bird.position.y += bird_velocity * delta

	# Floor and ceiling collision
	if bird.position.y > game_area_size.y - 30 or bird.position.y < 10:
		_game_over()
		return

	# Move pipes and check collisions
	for pipe in pipe_container.get_children():
		pipe.position.x -= PIPE_SPEED * delta

		# Score when pipe passes bird
		if not pipe.get_meta("scored", false) and pipe.position.x + PIPE_WIDTH < bird.position.x:
			pipe.set_meta("scored", true)
			add_score(1)
			score_label.text = "Score: %d" % score

		# Collision check
		if _check_pipe_collision(pipe):
			_game_over()
			return

		# Remove off-screen pipes
		if pipe.position.x < -PIPE_WIDTH:
			pipe.queue_free()

	# Feedback fade
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_label.text = ""

func on_rep_completed(rep_count: int) -> void:
	if not is_running or current_state != GameState.PLAYING:
		return
	# Flap!
	bird_velocity = FLAP_VELOCITY
	rep_label.text = "Reps: %d" % rep_count
	feedback_label.text = "Good rep!"
	feedback_label.add_theme_color_override("font_color", Color.GREEN)
	feedback_timer = 1.0

func on_form_invalid(message: String) -> void:
	if not is_running or current_state != GameState.PLAYING:
		return
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", Color.RED)
	feedback_timer = 2.0

func _spawn_pipe() -> void:
	if not is_running:
		return

	var gap_y := randf_range(game_area_size.y * 0.25, game_area_size.y * 0.75)
	var pipe := Node2D.new()
	pipe.position = Vector2(game_area_size.x + 10, 0)
	pipe.set_meta("scored", false)
	pipe.set_meta("gap_y", gap_y)

	# Top pipe (visual)
	var top_rect := ColorRect.new()
	top_rect.color = Color(0.2, 0.7, 0.3)
	top_rect.position = Vector2(0, 0)
	top_rect.size = Vector2(PIPE_WIDTH, gap_y - PIPE_GAP / 2.0)
	pipe.add_child(top_rect)

	# Bottom pipe (visual)
	var bottom_rect := ColorRect.new()
	bottom_rect.color = Color(0.2, 0.7, 0.3)
	var bottom_y := gap_y + PIPE_GAP / 2.0
	bottom_rect.position = Vector2(0, bottom_y)
	bottom_rect.size = Vector2(PIPE_WIDTH, game_area_size.y - bottom_y)
	pipe.add_child(bottom_rect)

	pipe_container.add_child(pipe)

func _check_pipe_collision(pipe: Node2D) -> bool:
	var pipe_x := pipe.position.x
	var bird_x := bird.position.x
	var bird_y := bird.position.y
	var bird_radius := 15.0

	# Only check if pipe overlaps bird horizontally
	if bird_x + bird_radius < pipe_x or bird_x - bird_radius > pipe_x + PIPE_WIDTH:
		return false

	var gap_y: float = pipe.get_meta("gap_y", 0.0)
	var top_bottom := gap_y - PIPE_GAP / 2.0
	var bottom_top := gap_y + PIPE_GAP / 2.0

	# Collision if bird is in the top or bottom pipe area
	if bird_y - bird_radius < top_bottom or bird_y + bird_radius > bottom_top:
		return true

	return false

func _game_over() -> void:
	end_game()
	current_state = GameState.GAME_OVER
	pipe_timer.stop()
	game_over_panel.show()
	game_over_score.text = "Score: %d" % score
	ExerciseManager.stop_exercise()
