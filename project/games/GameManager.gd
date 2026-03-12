extends Node

## Autoload singleton. Registry of available games.
## Connects exercise signals to the active game instance.

signal game_started(game_name: String)
signal game_ended(game_name: String, score: int)

var _games: Dictionary = {}
var _active_game: GameBase = null
var selected_game_name: String = ""

func _ready() -> void:
	_register_default_games()

func _register_default_games() -> void:
	register_game("Flappy Bird", "res://games/flappy/FlappyGame.tscn")
	register_game("Rep Tester", "res://games/test/TestGame.tscn")

func register_game(game_name: String, scene_path: String) -> void:
	_games[game_name] = scene_path

func get_game_names() -> Array:
	return _games.keys()

func get_game_scene_path(game_name: String) -> String:
	if _games.has(game_name):
		return _games[game_name]
	return ""

func get_active_game() -> GameBase:
	return _active_game

func set_active_game(game: GameBase) -> void:
	_active_game = game
	# Connect exercise signals
	if not ExerciseManager.rep_completed.is_connected(_on_rep_completed):
		ExerciseManager.rep_completed.connect(_on_rep_completed)
	if not ExerciseManager.form_invalid.is_connected(_on_form_invalid):
		ExerciseManager.form_invalid.connect(_on_form_invalid)

func clear_active_game() -> void:
	if ExerciseManager.rep_completed.is_connected(_on_rep_completed):
		ExerciseManager.rep_completed.disconnect(_on_rep_completed)
	if ExerciseManager.form_invalid.is_connected(_on_form_invalid):
		ExerciseManager.form_invalid.disconnect(_on_form_invalid)
	_active_game = null

func _on_rep_completed(rep_count: int) -> void:
	if _active_game and _active_game.is_running:
		_active_game.on_rep_completed(rep_count)

func _on_form_invalid(message: String) -> void:
	if _active_game and _active_game.is_running:
		_active_game.on_form_invalid(message)
