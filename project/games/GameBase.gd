class_name GameBase
extends Node2D

## Base class for mini-games. Receives exercise signals and
## translates them to in-game actions.
## Subclasses override the signal handler methods.

signal game_over(score: int)
signal score_changed(score: int)

var game_name: String = "Base Game"
var score: int = 0
var is_running: bool = false

func start_game() -> void:
	score = 0
	is_running = true
	score_changed.emit(score)

func end_game() -> void:
	is_running = false
	game_over.emit(score)

func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)

## Called when a rep is completed — override in subclass
func on_rep_completed(_rep_count: int) -> void:
	pass

## Called when form is invalid — override in subclass
func on_form_invalid(_message: String) -> void:
	pass
