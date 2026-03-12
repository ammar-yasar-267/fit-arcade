extends Control

## FitArcade Main Menu
## Flow: Title → Exercise Selection → Game Selection → Session (camera + game)

enum Screen {TITLE, EXERCISES, GAMES, SESSION, SETTINGS}

var current_screen: Screen = Screen.TITLE
var selected_exercise: String = ""
var selected_game: String = ""

@onready var title_panel: VBoxContainer = $VBoxContainer/TitlePanel
@onready var exercise_panel: VBoxContainer = $VBoxContainer/ExercisePanel
@onready var game_panel: VBoxContainer = $VBoxContainer/GamePanel
@onready var session_info: Label = $VBoxContainer/SessionInfo
@onready var btn_back: Button = $VBoxContainer/TopBar/BackButton
@onready var title_label: Label = $VBoxContainer/TopBar/TitleLabel
@onready var subtitle_label: Label = $VBoxContainer/TitlePanel/Subtitle
@onready var exercise_label: Label = $VBoxContainer/ExercisePanel/ExerciseLabel
@onready var game_label: Label = $VBoxContainer/GamePanel/GameLabel
@onready var right_spacer: Control = $VBoxContainer/TopBar/RightSpacer
@onready var exercise_list: VBoxContainer = $VBoxContainer/ExercisePanel/ScrollContainer/ExerciseList
@onready var game_list: VBoxContainer = $VBoxContainer/GamePanel/ScrollContainer/GameList

func _ready() -> void:
	btn_back.pressed.connect(_go_back)
	var start_btn: Button = $VBoxContainer/TitlePanel/StartButton
	start_btn.pressed.connect(_on_start_pressed)
	var settings_btn: Button = $VBoxContainer/TitlePanel/SettingsButton
	settings_btn.pressed.connect(_on_settings_pressed)
	_apply_ui_theme()
	_show_screen(Screen.TITLE)
	# Offline-first: rely on bundled model files unless explicitly enabled.
	Global.enable_download_files = false

func _apply_ui_theme() -> void:
	subtitle_label.text = "Move better. Play longer."
	_style_secondary_button(btn_back)
	var start_btn: Button = $VBoxContainer/TitlePanel/StartButton
	start_btn.text = "Start Session"
	_style_primary_button(start_btn)
	var settings_btn: Button = $VBoxContainer/TitlePanel/SettingsButton
	settings_btn.text = "Settings"
	_style_secondary_button(settings_btn)

func _style_primary_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(0, 72)
	btn.add_theme_font_size_override("font_size", 30)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.44, 0.33, 1.0)
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.52, 0.39, 1.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)

func _style_secondary_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(92, 52)
	btn.add_theme_font_size_override("font_size", 24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.14, 0.18, 0.92)
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = Color(0.17, 0.18, 0.24, 0.98)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)

func _on_start_pressed() -> void:
	_show_screen(Screen.EXERCISES)

func _on_settings_pressed() -> void:
	_show_screen(Screen.SETTINGS)

func _show_screen(screen: Screen) -> void:
	current_screen = screen
	title_panel.hide()
	exercise_panel.hide()
	game_panel.hide()
	session_info.hide()
	btn_back.hide()
	right_spacer.hide()

	match screen:
		Screen.TITLE:
			title_label.text = "FitArcade"
			title_panel.show()
		Screen.EXERCISES:
			title_label.text = "Select Exercise"
			btn_back.show()
			right_spacer.show()
			_populate_exercises()
			exercise_panel.show()
		Screen.GAMES:
			title_label.text = "Select Game"
			btn_back.show()
			right_spacer.show()
			_populate_games()
			game_panel.show()
		Screen.SESSION:
			title_label.text = selected_exercise + " → " + selected_game
			btn_back.show()
			right_spacer.show()
			_start_session()
		Screen.SETTINGS:
			get_tree().change_scene_to_file("res://SettingsMenu.tscn")

func _go_back() -> void:
	match current_screen:
		Screen.EXERCISES:
			_show_screen(Screen.TITLE)
		Screen.GAMES:
			_show_screen(Screen.EXERCISES)
		Screen.SESSION:
			_end_session()
			_show_screen(Screen.GAMES)

func _populate_exercises() -> void:
	for child in exercise_list.get_children():
		child.queue_free()

	for exercise_name in ExerciseManager.get_exercise_names():
		var btn := Button.new()
		btn.text = exercise_name
		_style_primary_button(btn)
		btn.pressed.connect(_on_exercise_selected.bind(exercise_name))
		exercise_list.add_child(btn)

func _populate_games() -> void:
	for child in game_list.get_children():
		child.queue_free()

	for game_name in GameManager.get_game_names():
		var btn := Button.new()
		btn.text = game_name
		_style_primary_button(btn)
		btn.pressed.connect(_on_game_selected.bind(game_name))
		game_list.add_child(btn)

func _on_exercise_selected(exercise_name: String) -> void:
	selected_exercise = exercise_name
	ExerciseManager.set_active_exercise(exercise_name)
	_show_screen(Screen.GAMES)

func _on_game_selected(game_name: String) -> void:
	selected_game = game_name
	GameManager.selected_game_name = game_name
	_show_screen(Screen.SESSION)

func _start_session() -> void:
	# Change to the pose landmarker scene which handles camera + game
	var scene_path := "res://vision/pose_landmarker/PoseLandmarker.tscn"
	get_tree().change_scene_to_file(scene_path)

func _end_session() -> void:
	ExerciseManager.stop_exercise()
	GameManager.clear_active_game()
