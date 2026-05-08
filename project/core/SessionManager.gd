extends Node

var current_reps: int = 0
var total_reps_today: int = 0
var session_score: int = 0
var daily_streak: int = 1

func reset_session():
	current_reps = 0
	session_score = 0

func add_rep():
	current_reps += 1
	total_reps_today += 1
