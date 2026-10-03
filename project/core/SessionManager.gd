extends Node

## SessionManager autoload — tracks the active session's reps/score and the local
## persistent workout history, best scores, and weekly aggregations.
## (Pose-pipeline timing lives in PerfStats.)

signal workout_logged(game_mode: String, score: int, reps: int)

var current_reps: int = 0
var total_reps_today: int = 0
var session_score: int = 0
var daily_streak: int = 1
var last_workout_result: Dictionary = {}
var last_played_mode: String = "dino"

const WORKOUTS_FILE := "user://fitarcade_workout_history.json"
const BEST_SCORES_FILE := "user://fitarcade_best_scores.cfg"

var _workout_history: Array = []
var _best_scores: Dictionary = {}

func _ready() -> void:
	_load_history()
	_load_best_scores()
	_update_today_reps()

func reset_session():
	current_reps = 0
	session_score = 0

## Wipes everything stored for this player on the device: workout history, best
## scores and the in-memory session. Used by account deletion.
func clear_local_data() -> void:
	_workout_history.clear()
	_best_scores.clear()
	for file_path in [WORKOUTS_FILE, BEST_SCORES_FILE]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	reset_session()
	last_workout_result = {}
	last_played_mode = "dino"
	total_reps_today = 0
	daily_streak = 1

func add_rep():
	current_reps += 1
	total_reps_today += 1

# --- Local Workout Persistence & Analytics ---

func record_workout(game_mode: String, score: int, reps: int) -> void:
	var now_dict := Time.get_date_dict_from_system()
	var today_str := "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]

	var entry := {
		"date": today_str,
		"timestamp": Time.get_unix_time_from_system(),
		"mode": game_mode,
		"reps": reps,
		"score": score
	}
	_workout_history.append(entry)
	_save_history()

	# Update best score
	var current_best: int = _best_scores.get(game_mode, 0)
	if score > current_best:
		_best_scores[game_mode] = score
		_save_best_scores()

	set_last_played_mode(game_mode)
	_update_today_reps()
	workout_logged.emit(game_mode, score, reps)

func set_last_played_mode(mode_id: String) -> void:
	var canonical := "lane" if mode_id in ["lane", "switcher"] else mode_id
	if canonical in ["dino", "lane", "flappy"]:
		last_played_mode = canonical
		_save_best_scores()

func get_last_played_mode() -> String:
	if last_played_mode != "":
		return "lane" if last_played_mode in ["lane", "switcher"] else last_played_mode
	if _workout_history.size() > 0:
		for i in range(_workout_history.size() - 1, -1, -1):
			var w = _workout_history[i]
			if typeof(w) == TYPE_DICTIONARY and w.has("mode"):
				var m: String = str(w.get("mode", ""))
				if m != "":
					return "lane" if m in ["lane", "switcher"] else m
	return "dino"

func get_best_score(game_mode: String) -> int:
	return _best_scores.get(game_mode, 0)

func get_reps_for_date(date_str: String, filter_mode: String = "") -> int:
	var total := 0
	for w in _workout_history:
		if typeof(w) == TYPE_DICTIONARY and w.get("date", "") == date_str:
			if filter_mode == "" or w.get("mode", "") == filter_mode:
				total += int(w.get("reps", 0))
	return total

func get_all_time_reps() -> int:
	var total := 0
	for w in _workout_history:
		if typeof(w) == TYPE_DICTIONARY:
			total += int(w.get("reps", 0))
	return total

func get_player_level() -> int:
	# Real level formula: starts at LVL 1; every 50 reps progresses 1 level
	return 1 + int(get_all_time_reps() / 50)

func get_weekly_data() -> Dictionary:
	var now_unix := Time.get_unix_time_from_system()
	var now_dict := Time.get_datetime_dict_from_system()
	var weekday: int = now_dict["weekday"] # 0 = Sun, 1 = Mon ... 6 = Sat

	# Days since Monday (Monday = 0, Sunday = 6)
	var days_from_monday: int = 6 if weekday == 0 else (weekday - 1)
	var monday_unix: int = now_unix - (days_from_monday * 86400)

	const DAY_LETTERS := ["M", "T", "W", "T", "F", "S", "S"]
	var days: Array[Dictionary] = []
	var total_week_reps := 0

	for i in range(7):
		var day_unix: int = monday_unix + (i * 86400)
		var date_str: String = Time.get_date_string_from_unix_time(day_unix)
		var day_reps := get_reps_for_date(date_str)
		total_week_reps += day_reps

		days.append({
			"d": DAY_LETTERS[i],
			"reps": day_reps,
			"date": date_str,
			"is_today": (i == days_from_monday)
		})

	return {
		"total_reps": total_week_reps,
		"days": days,
		"today_index": days_from_monday
	}

func get_daily_challenge() -> Dictionary:
	var now_dict := Time.get_datetime_dict_from_system()
	var hours_left: int = maxi(1, 24 - now_dict["hour"])
	var weekday: int = now_dict["weekday"]
	var today_str := "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]

	# Rotate challenge mode by day
	var mode_id := "lane"
	var exercise_title := "40 SIDE LUNGES"
	var target_reps := 40
	var time_goal := "Under 2:00"

	if weekday == 1 or weekday == 4: # Mon, Thu
		mode_id = "dino"
		exercise_title = "50 JUMPING JACKS"
		target_reps = 50
		time_goal = "Under 1:30"
	elif weekday == 3 or weekday == 6: # Wed, Sat
		mode_id = "flappy"
		exercise_title = "30 ARM RAISES"
		target_reps = 30
		time_goal = "Under 1:00"
	else: # Tue, Fri, Sun
		mode_id = "lane"
		exercise_title = "40 SIDE LUNGES"
		target_reps = 40
		time_goal = "Under 2:00"

	var current_prog: int = mini(target_reps, get_reps_for_date(today_str, mode_id))

	return {
		"mode_id": mode_id,
		"title": exercise_title,
		"current_progress": current_prog,
		"total_target": target_reps,
		"time_left": "%dH LEFT" % hours_left,
		"reward": "+500 XP",
		"subline": "%s · +500 XP" % time_goal,
	}

func _update_today_reps() -> void:
	var now_dict := Time.get_date_dict_from_system()
	var today_str := "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]
	total_reps_today = get_reps_for_date(today_str)

func _load_history() -> void:
	if not FileAccess.file_exists(WORKOUTS_FILE):
		_workout_history = []
		return
	var file := FileAccess.open(WORKOUTS_FILE, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_ARRAY:
			_workout_history = parsed
		file.close()

func _save_history() -> void:
	var file := FileAccess.open(WORKOUTS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_workout_history))
		file.close()

func _load_best_scores() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_SCORES_FILE) == OK:
		if cfg.has_section("scores"):
			for k in cfg.get_section_keys("scores"):
				_best_scores[k] = cfg.get_value("scores", k, 0)
		var saved_mode: String = str(cfg.get_value("meta", "last_played_mode", ""))
		if saved_mode != "":
			last_played_mode = "lane" if saved_mode in ["lane", "switcher"] else saved_mode
		elif _workout_history.size() > 0:
			for i in range(_workout_history.size() - 1, -1, -1):
				var w = _workout_history[i]
				if typeof(w) == TYPE_DICTIONARY and w.has("mode"):
					var m: String = str(w.get("mode", ""))
					if m != "":
						last_played_mode = "lane" if m in ["lane", "switcher"] else m
						break

func _save_best_scores() -> void:
	var cfg := ConfigFile.new()
	for k in _best_scores.keys():
		cfg.set_value("scores", k, _best_scores[k])
	if last_played_mode != "":
		cfg.set_value("meta", "last_played_mode", last_played_mode)
	cfg.save(BEST_SCORES_FILE)
