extends Node

signal game_started(game_name: String)
signal game_ended(game_name: String, score: int)

var _games: Dictionary = {}
var _active_game = null
var selected_game_name: String = ""
var pending_game_name: String = ""

func _ready() -> void:
	_register_default_games()

func _register_default_games() -> void:
	register_game("dino", "res://games/dino/DinoGame.tscn")
	register_game("switcher", "res://games/switcher/SwitcherGame.tscn")
	register_game("flappy", "res://games/flappy/FlappyBird.tscn")

func register_game(game_name: String, scene_path: String) -> void:
	_games[game_name] = scene_path

func get_game_scene_path(game_name: String) -> String:
	if _games.has(game_name):
		return _games[game_name]
	return ""

func get_active_game():
	return _active_game

func set_active_game(game) -> void:
	_active_game = game
	if not ExerciseRecognizer.rep_completed.is_connected(_on_rep_completed):
		ExerciseRecognizer.rep_completed.connect(_on_rep_completed)
	if not ExerciseRecognizer.form_feedback.is_connected(_on_form_feedback):
		ExerciseRecognizer.form_feedback.connect(_on_form_feedback)

func clear_active_game() -> void:
	if ExerciseRecognizer.rep_completed.is_connected(_on_rep_completed):
		ExerciseRecognizer.rep_completed.disconnect(_on_rep_completed)
	if ExerciseRecognizer.form_feedback.is_connected(_on_form_feedback):
		ExerciseRecognizer.form_feedback.disconnect(_on_form_feedback)
	_active_game = null

func _on_rep_completed() -> void:
	if _active_game and _active_game.has_method("on_rep_completed"):
		_active_game.on_rep_completed(SessionManager.current_reps)

func _on_form_feedback(message: String, is_good: bool) -> void:
	if _active_game and _active_game.has_method("on_form_feedback"):
		_active_game.on_form_feedback(message, is_good)
