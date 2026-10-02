class_name HubScreen
extends Control

## Hub / Home screen for FitArcade.
## Visual source of truth: references/01-hub.png
## Spec from design-spec.md Section D1 and Hub.tsx.

const TouchScrollClass = preload("res://ui/components/TouchScroll.gd")
const IdentityBarClass = preload("res://ui/components/IdentityBar.gd")
const WeekStripClass = preload("res://ui/components/WeekStrip.gd")
const DailyChallengeCardClass = preload("res://ui/components/DailyChallengeCard.gd")
const SectionHeadingClass = preload("res://ui/components/SectionHeading.gd")
const GameRowClass = preload("res://ui/components/GameRow.gd")

signal mode_picked(mode_id: String)
signal nav_requested(screen_name: String)

@export var locked_modes: Dictionary = {"dino": false, "lane": false, "flappy": false}:
	set(v):
		locked_modes = v
		_update_rows()

var _selected_mode: String = "dino"
var _phase: float = 0.0

var _identity_bar: Control
var _week_strip: Control
var _daily_card: Control
var _game_rows: Dictionary = {}

## Leaderboard rows requested per game when working out the player's rank
const BOARD_LIMIT := 50
## Per-mode request counter: a newer fetch supersedes an older one still in flight
var _stats_serial: Dictionary = {}
## Modes whose RANK/BEST have loaded at least once. Refreshes after that keep the
## numbers on screen (no flicker back to a skeleton) and just update them.
var _stats_loaded: Dictionary = {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	# Select the game you last played (or default to first unlocked mode)
	var target_mode := "dino"
	if get_tree().root.has_node("SessionManager"):
		target_mode = SessionManager.get_last_played_mode()

	if not locked_modes.get(target_mode, false):
		_selected_mode = target_mode
	else:
		for m in Tokens.MODES:
			if not locked_modes.get(m["id"], false):
				_selected_mode = m["id"]
				break

	_build_ui()

	# Connect reactive listeners for live updates
	if get_tree().root.has_node("SessionManager"):
		SessionManager.workout_logged.connect(_on_workout_logged)
	if get_tree().root.has_node("Backend"):
		Backend.auth_ready.connect(_on_backend_auth_ready)

	# Fetch live cloud scores asynchronously
	_fetch_live_scores()

func _draw() -> void:
	# Screen background: #0B0B0C (ink)
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.INK, true)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Root margin container (safe top offset 64, left/right 20, bottom 20)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", Tokens.SAFE_TOP_OFFSET)
	margin.add_theme_constant_override("margin_left", Tokens.SCREEN_PADDING_LEFT)
	margin.add_theme_constant_override("margin_right", Tokens.SCREEN_PADDING_RIGHT)
	margin.add_theme_constant_override("margin_bottom", Tokens.SCREEN_PADDING_BOTTOM)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 0)
	margin.add_child(root_vbox)

	# 1. IdentityBar (pinned at top)
	_identity_bar = IdentityBarClass.new()
	root_vbox.add_child(_identity_bar)
	_update_identity_bar()
	_identity_bar.leaderboard_pressed.connect(func(): nav_requested.emit("leaderboard"))
	_identity_bar.settings_pressed.connect(func(): nav_requested.emit("settings"))

	# 23px gap below header so WeekStrip top border snaps cleanly to pixel grid
	var gap23 := Control.new()
	gap23.custom_minimum_size = Vector2(0, 23)
	root_vbox.add_child(gap23)

	# 2. ScrollContainer for all content below header
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = false
	scroll.scroll_vertical = 0

	# Hide scrollbar visually and eliminate its width reservation
	var v_bar := scroll.get_v_scroll_bar()
	if v_bar:
		var empty_sb := StyleBoxEmpty.new()
		v_bar.add_theme_stylebox_override("scroll", empty_sb)
		v_bar.add_theme_stylebox_override("scroll_focus", empty_sb)
		v_bar.add_theme_stylebox_override("grabber", empty_sb)
		v_bar.add_theme_stylebox_override("grabber_highlight", empty_sb)
		v_bar.add_theme_stylebox_override("grabber_pressed", empty_sb)
		v_bar.custom_minimum_size = Vector2.ZERO
		v_bar.modulate = Color(1, 1, 1, 0)

	root_vbox.add_child(scroll)
	TouchScrollClass.apply(scroll)

	var scroll_content := VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll_content.add_theme_constant_override("separation", 0)
	scroll.add_child(scroll_content)

	# WeekStrip (bound to real weekly workout metrics)
	_week_strip = WeekStripClass.new()
	scroll_content.add_child(_week_strip)
	_update_week_strip()

	# 12px gap
	var gap12 := Control.new()
	gap12.custom_minimum_size = Vector2(0, 12)
	scroll_content.add_child(gap12)

	# DailyChallengeCard (bound to real daily progress & countdown)
	_daily_card = DailyChallengeCardClass.new()
	scroll_content.add_child(_daily_card)
	_update_daily_card()
	_daily_card.challenge_pressed.connect(_on_mode_start)

	# 40px gap
	var gap40 := Control.new()
	gap40.custom_minimum_size = Vector2(0, 40)
	scroll_content.add_child(gap40)

	# SectionHeading "GAMES"
	var heading = SectionHeadingClass.new()
	heading.title = "GAMES"
	heading.subtitle = "PICK ONE · 3 MODES"
	scroll_content.add_child(heading)

	# 8px gap below GAMES heading
	var gap_heading := Control.new()
	gap_heading.custom_minimum_size = Vector2(0, 8)
	scroll_content.add_child(gap_heading)

	# Game rows
	_game_rows.clear()
	for mode_info in Tokens.MODES:
		var m_id: String = mode_info["id"]
		var is_lk: bool = locked_modes.get(m_id, false)
		var is_act: bool = (m_id == _selected_mode)

		# Local real best score
		var local_best := 0
		if get_tree().root.has_node("SessionManager"):
			local_best = SessionManager.get_best_score(m_id)

		var rank_str := "—"
		var best_str := Tokens.format_thousands(local_best) if local_best > 0 else "—"
		var cloud_available := _cloud_available()

		var row = GameRowClass.new()
		row.name = "GameRow_" + m_id
		row.mode_id = m_id
		row.exercise_name = mode_info["exercise"]
		row.game_name = mode_info["game"]
		row.action_text = mode_info["action"]
		row.mode_color = mode_info["color"]
		row.is_locked = is_lk
		row.is_active = is_act
		row.rank_text = rank_str
		row.best_score_text = best_str
		# RANK always needs the cloud; BEST shows the on-device score right away and
		# only waits on the cloud when there isn't one (e.g. after a reinstall).
		row.rank_loading = cloud_available
		row.best_loading = cloud_available and local_best <= 0
		row.row_selected.connect(_on_row_selected)
		row.start_pressed.connect(_on_mode_start)

		scroll_content.add_child(row)
		_game_rows[m_id] = row

	# 32px bottom padding after the last game card (footer removed per user request)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 32)
	scroll_content.add_child(bottom_pad)

func _update_identity_bar() -> void:
	if not _identity_bar:
		return

	var has_backend := get_tree().root.has_node("Backend")
	var profile: Dictionary = Backend.profile if has_backend else {}
	var player_name: String = str(profile.get("display_name", ""))
	var uid: String = Backend.uid if has_backend else ""

	# No profile yet and not signed in either: the data simply hasn't arrived, so
	# show placeholders rather than an invented player. Once signed in with still no
	# profile, fall back to a neutral name so the bar never stays blank.
	if player_name == "" and uid == "":
		_identity_bar.loading = true
		return
	if player_name == "":
		player_name = "PLAYER"

	var tag_number: String = str(profile.get("tag_number", ""))
	if tag_number == "" and uid != "":
		tag_number = Backend.generate_tag(uid)

	var level := 1
	if get_tree().root.has_node("SessionManager"):
		level = SessionManager.get_player_level()

	_identity_bar.loading = false
	_identity_bar.player_name = player_name.to_upper()
	_identity_bar.tag_text = "#%s" % tag_number if tag_number != "" else ""
	_identity_bar.badge_initials = Tokens.initials(player_name)
	_identity_bar.level = level

func _update_week_strip() -> void:
	if not _week_strip:
		return
	if get_tree().root.has_node("SessionManager"):
		var week_info = SessionManager.get_weekly_data()
		_week_strip.update_data(
			week_info.get("total_reps", 0),
			week_info.get("days", []),
			week_info.get("today_index", -1)
		)

func _update_daily_card() -> void:
	if not _daily_card:
		return
	if get_tree().root.has_node("SessionManager"):
		var ch = SessionManager.get_daily_challenge()
		var m_id: String = ch.get("mode_id", "lane")
		ch["is_locked"] = locked_modes.get(m_id, false)
		_daily_card.update_challenge(ch)
		_daily_card.is_locked = locked_modes.get(m_id, false)

func _cloud_available() -> bool:
	return get_tree().root.has_node("Backend") and FirebaseConfig.is_configured()

## Loads RANK/BEST for every game. The three requests run in parallel (they used to
## run one after another, three round trips in a row).
func _fetch_live_scores() -> void:
	if not _cloud_available():
		for row in _game_rows.values():
			row.rank_loading = false
			row.best_loading = false
		return
	for m_id in _game_rows.keys():
		_fetch_row_stats(m_id)

func _fetch_row_stats(m_id: String) -> void:
	var row = _game_rows.get(m_id, null)
	if not row:
		return
	var serial: int = _stats_serial.get(m_id, 0) + 1
	_stats_serial[m_id] = serial

	var local_best: int = SessionManager.get_best_score(m_id) if get_tree().root.has_node("SessionManager") else 0
	if not _stats_loaded.get(m_id, false):
		row.rank_loading = true
		row.best_loading = local_best <= 0

	var backend_key: String = "switcher" if m_id == "lane" else m_id
	var result: Dictionary = await Backend.fetch_leaderboard(backend_key, BOARD_LIMIT)
	if not is_instance_valid(self) or not is_instance_valid(row) or _stats_serial.get(m_id, 0) != serial:
		return

	row.rank_loading = false
	row.best_loading = false
	if not result.ok:
		# Fallback: keep whatever is already shown (the on-device best, rank "—"),
		# rather than blanking numbers because the network hiccuped.
		return

	var best_score: int = local_best
	for doc in result.rows:
		if doc.get("uid", "") == Backend.uid:
			best_score = maxi(best_score, int(doc.get("score", 0)))
			break
	row.best_score_text = Tokens.format_thousands(best_score) if best_score > 0 else "—"
	row.rank_text = Backend.rank_label(result.rows, best_score, BOARD_LIMIT)
	_stats_loaded[m_id] = true

func _on_workout_logged(_game_mode: String, _score: int, _reps: int) -> void:
	_update_identity_bar()
	_update_week_strip()
	_update_daily_card()
	_fetch_live_scores()

func _on_backend_auth_ready(_new_uid: String) -> void:
	_update_identity_bar()
	_fetch_live_scores()

func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 0.65, 1.0)
	var active_row = _game_rows.get(_selected_mode, null)
	if active_row:
		active_row.phase = _phase

func _on_row_selected(mode_id: String) -> void:
	if _selected_mode == mode_id:
		return
	_selected_mode = mode_id
	if get_tree().root.has_node("SessionManager"):
		SessionManager.set_last_played_mode(mode_id)
	for m_id in _game_rows.keys():
		var row = _game_rows[m_id]
		row.is_active = (m_id == _selected_mode)

func _on_mode_start(mode_id: String) -> void:
	if not locked_modes.get(mode_id, false):
		if get_tree().root.has_node("SessionManager"):
			SessionManager.set_last_played_mode(mode_id)
		mode_picked.emit(mode_id)

func _update_rows() -> void:
	if _daily_card:
		var ch_mode = _daily_card.mode_id
		_daily_card.is_locked = locked_modes.get(ch_mode, false)
	for m_id in _game_rows.keys():
		var row = _game_rows[m_id]
		row.is_locked = locked_modes.get(m_id, false)
