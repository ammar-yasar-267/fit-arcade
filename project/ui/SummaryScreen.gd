class_name SummaryScreen
extends Control

## Workout Summary Screen for FitArcade.
## Visual source of truth: references/07-summary.png.
## Spec from design-spec.md Section D4 and Summary.tsx.

# Sub-component: Play Again Button with Volt fill sweep animation
class PlayAgainButton extends Button:
	var sweep_pct: float = 0.0:
		set(v):
			sweep_pct = clampf(v, 0.0, 1.0)
			queue_redraw()
	var button_label: String = "PLAY AGAIN · 10":
		set(v):
			button_label = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 56)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		# 1. Base white background
		draw_rect(Rect2(Vector2.ZERO, size), Tokens.WHITE, true)

		# 2. Volt fill sweeping in from left
		if sweep_pct > 0.001:
			var fill_rect := Rect2(Vector2.ZERO, Vector2(size.x * sweep_pct, size.y))
			draw_rect(fill_rect, Tokens.VOLT, true)

		# 3. Text in Anton Display, optically centered: draw_string takes the baseline,
		# and caps sit DISPLAY_CAP_HEIGHT above it, so the baseline goes half a cap
		# below the button's centre line.
		var font: Font = Tokens.FONT_DISPLAY
		var font_sz := 28
		var str_sz := font.get_string_size(button_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz)
		var baseline := size.y * 0.5 + font_sz * Tokens.DISPLAY_CAP_HEIGHT * 0.5
		draw_string(font, Vector2((size.x - str_sz.x) * 0.5, baseline), button_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, Tokens.INK)


const TouchScrollClass = preload("res://ui/components/TouchScroll.gd")
const SkeletonBarClass = preload("res://ui/components/SkeletonBar.gd")

## Leaderboard rows fetched to work out the player's rank (matches the Hub)
const RANK_BOARD_LIMIT := 50

# Data bundle
var _mode_id: String = "dino"
var _mode_title: String = "Dino Runner"
var _mode_code: String = "01"
var _mode_color: Color = Tokens.VOLT
var _exercise_title: String = "JUMPING JACKS"
var _score: int = 0
var _reps: int = 0
var _active_time: float = 0.0
var _latency_ms: float = 0.0
var _is_pb: bool = false
var _previous_best: int = 0

## The stat cells that wait on the server are built with a skeleton and filled in later
var _rank_value_box: HBoxContainer
var _banner_icon: Label
var _banner_title: Label
var _banner_sub: Label
var _banner_sub_skeleton: Control

# Auto-countdown state
var _auto_timer: float = 10.0
var _auto_active: bool = true

# UI Node references
var _play_again_btn: PlayAgainButton
var _cancel_auto_btn: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	_load_result_data()
	_build_ui()
	_fetch_rank()
	if Backend.submit_state == "pending" and not Backend.score_submit_finished.is_connected(_on_score_submit_finished):
		Backend.score_submit_finished.connect(_on_score_submit_finished)

func _process(delta: float) -> void:
	if not _auto_active:
		return

	_auto_timer -= delta
	if _play_again_btn:
		_play_again_btn.sweep_pct = (10.0 - _auto_timer) / 10.0
		var sec := int(ceilf(_auto_timer))
		_play_again_btn.button_label = "PLAY AGAIN · %d" % max(0, sec)

	if _auto_timer <= 0.0:
		_auto_active = false
		_on_play_again_pressed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		_on_return_to_hub_pressed()
		get_viewport().set_input_as_handled()

func _load_result_data() -> void:
	var res: Dictionary = SessionManager.last_workout_result
	_mode_id = res.get("game_mode", "")
	if _mode_id == "":
		_mode_id = GameManager.selected_game_name
	if _mode_id == "":
		_mode_id = "dino"

	match _mode_id:
		"dino":
			_mode_title = "DINO RUNNER"
			_mode_code = "01"
			_mode_color = Tokens.VOLT
			_exercise_title = "JUMPING JACKS"
		"lane", "switcher":
			_mode_id = "lane"
			_mode_title = "LANE SWITCHER"
			_mode_code = "02"
			_mode_color = Tokens.CYAN
			_exercise_title = "SIDE LUNGES"
		"flappy":
			_mode_title = "FLAPPY FLIGHT"
			_mode_code = "03"
			_mode_color = Tokens.FLAME
			_exercise_title = "ARM RAISES"

	_score = res.get("score", 0)
	_reps = res.get("reps", 0)
	_active_time = res.get("active_time", 0.0)
	# 0 means nothing was measured (no inference ran): shown as "—", not a made-up figure
	_latency_ms = res.get("latency_ms", 0.0)
	_is_pb = res.get("is_pb", false)
	_previous_best = res.get("previous_best", 0)

func _draw() -> void:
	# Solid dark ink background
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.INK, true)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Solid dark ink background rect
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Tokens.INK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	TouchScrollClass.apply(scroll)

	# Main Margin Container (390 x 844)
	var root_margin := MarginContainer.new()
	root_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_margin.add_theme_constant_override("margin_top", Tokens.SAFE_TOP_OFFSET)
	root_margin.add_theme_constant_override("margin_left", 20)
	root_margin.add_theme_constant_override("margin_right", 20)
	root_margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(root_margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 0)
	root_margin.add_child(main_vbox)

	# 1. Kicker: "{code} / {GAME} · SESSION COMPLETE"
	var kicker := Label.new()
	kicker.text = "%s  /  %s  ·  SESSION COMPLETE" % [_mode_code, _mode_title]
	kicker.add_theme_font_override("font", Tokens.FONT_MONO)
	kicker.add_theme_font_size_override("font_size", 10)
	kicker.add_theme_color_override("font_color", _mode_color)
	main_vbox.add_child(kicker)

	main_vbox.add_child(_make_spacer(6))

	# 2. Headline: "WORK" / "DONE." as two tight lines (spec lh 0.9)
	var headline_1 := Tokens.tight_display_label("WORK", 44, Tokens.WHITE)
	main_vbox.add_child(headline_1.get_parent())
	main_vbox.add_child(_make_spacer(3))
	var headline_2 := Tokens.tight_display_label("DONE.", 44, Tokens.WHITE)
	main_vbox.add_child(headline_2.get_parent())

	main_vbox.add_child(_make_spacer(16))

	# 3. Giant Reps Hero Block: number + "VALID / EXERCISE", bottom-aligned
	var reps_hero := HBoxContainer.new()
	reps_hero.alignment = BoxContainer.ALIGNMENT_BEGIN
	reps_hero.add_theme_constant_override("separation", 12)
	main_vbox.add_child(reps_hero)

	var reps_num := Tokens.tight_display_label(str(_reps), 112, _mode_color, HORIZONTAL_ALIGNMENT_LEFT, _display_width(str(_reps), 112))
	reps_hero.add_child(reps_num.get_parent())

	var reps_meta := VBoxContainer.new()
	reps_meta.size_flags_vertical = Control.SIZE_SHRINK_END
	reps_meta.add_theme_constant_override("separation", 3)
	reps_hero.add_child(reps_meta)

	var valid_lbl := Tokens.tight_display_label("VALID", 24, Tokens.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _display_width("VALID", 24))
	reps_meta.add_child(valid_lbl.get_parent())

	var ex_lbl := Tokens.tight_display_label(_exercise_title, 24, Tokens.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _display_width(_exercise_title, 24))
	reps_meta.add_child(ex_lbl.get_parent())

	# 8px bottom padding inside hero, so the text sits just above the number's baseline
	reps_meta.add_child(_make_spacer(8))

	main_vbox.add_child(_make_spacer(20))

	# 4. 2×2 Stat Grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	main_vbox.add_child(grid)

	# Cell 1: ACTIVE TIME
	grid.add_child(_make_stat_cell("ACTIVE TIME", _format_time(_active_time)))

	# Cell 2: SCORE
	grid.add_child(_make_stat_cell("SCORE", _format_number(_score)))

	# Cell 3: TRACKING LATENCY (measured on this device)
	if _latency_ms > 0.0:
		grid.add_child(_make_stat_cell("TRACKING LATENCY", "%.0f" % _latency_ms, "ms"))
	else:
		grid.add_child(_make_stat_cell("TRACKING LATENCY", "—"))

	# Cell 4: GLOBAL RANK (needs the leaderboard: skeleton until it arrives)
	var rank_cell := _make_stat_cell("GLOBAL RANK", "", "", true)
	_rank_value_box = rank_cell.get_meta("value_box")
	grid.add_child(rank_cell)

	main_vbox.add_child(_make_spacer(20))

	# 5. Status Banner (C19)
	var banner := PanelContainer.new()
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b_style := StyleBoxFlat.new()
	b_style.corner_radius_top_left = 2
	b_style.corner_radius_top_right = 2
	b_style.corner_radius_bottom_left = 2
	b_style.corner_radius_bottom_right = 2
	b_style.content_margin_left = 16
	b_style.content_margin_right = 16
	b_style.content_margin_top = 14
	b_style.content_margin_bottom = 14

	if _is_pb:
		b_style.bg_color = Tokens.VOLT
		banner.add_theme_stylebox_override("panel", b_style)
	else:
		b_style.bg_color = Color(1, 1, 1, 0.03)
		b_style.border_width_left = 1
		b_style.border_width_top = 1
		b_style.border_width_right = 1
		b_style.border_width_bottom = 1
		b_style.border_color = Tokens.LINE
		banner.add_theme_stylebox_override("panel", b_style)

	main_vbox.add_child(banner)

	var b_hbox := HBoxContainer.new()
	b_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	b_hbox.add_theme_constant_override("separation", 14)
	banner.add_child(b_hbox)

	# Icon, title and subline all depend on whether the score upload has finished,
	# so they're built once and re-skinned by _refresh_banner().
	_banner_icon = Label.new()
	_banner_icon.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_banner_icon.add_theme_font_size_override("font_size", 24)
	_banner_icon.add_theme_color_override("font_color", Tokens.INK if _is_pb else Tokens.WHITE)
	_banner_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b_hbox.add_child(_banner_icon)

	var b_text_col := VBoxContainer.new()
	b_text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b_text_col.add_theme_constant_override("separation", 5)
	b_hbox.add_child(b_text_col)

	# Box sized for the longest title so swapping text never shifts the layout
	_banner_title = Tokens.tight_display_label("", 20, Tokens.INK if _is_pb else Tokens.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _display_width("NEW PERSONAL BEST!", 20))
	b_text_col.add_child(_banner_title.get_parent())

	_banner_sub = Label.new()
	_banner_sub.add_theme_font_override("font", Tokens.FONT_MONO)
	_banner_sub.add_theme_font_size_override("font_size", 10)
	_banner_sub.add_theme_color_override("font_color", Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.7) if _is_pb else Tokens.DIM)
	b_text_col.add_child(_banner_sub)

	# Same footprint as the subline (one 10px mono line), shown while posting
	var skeleton_fill := Color(Tokens.INK.r, Tokens.INK.g, Tokens.INK.b, 0.18) if _is_pb else SkeletonBarClass.BLOCK_COLOR
	_banner_sub_skeleton = SkeletonBarClass.slot(210, 8, 14, false, skeleton_fill)
	b_text_col.add_child(_banner_sub_skeleton)
	_refresh_banner()

	# 6. Expanding spacer pushing Action Block to bottom (at least 20px above it)
	var expand_spacer := Control.new()
	expand_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expand_spacer.custom_minimum_size = Vector2(0, 20)
	expand_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(expand_spacer)

	# 7. Action Block (Primary "PLAY AGAIN" with sweep, Secondary "RETURN TO HUB", Tertiary "CANCEL AUTO")
	var action_vbox := VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(action_vbox)

	_play_again_btn = PlayAgainButton.new()
	_play_again_btn.pressed.connect(_on_play_again_pressed)
	action_vbox.add_child(_play_again_btn)

	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 12)
	action_vbox.add_child(sec_row)

	var hub_btn := Button.new()
	hub_btn.text = "RETURN TO HUB"
	hub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_btn.custom_minimum_size = Vector2(0, 48)
	hub_btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	hub_btn.add_theme_font_size_override("font_size", 18)
	hub_btn.add_theme_color_override("font_color", Tokens.WHITE)
	hub_btn.add_theme_color_override("font_hover_color", Tokens.WHITE)

	var hub_sb := StyleBoxFlat.new()
	hub_sb.bg_color = Color(0, 0, 0, 0)
	hub_sb.border_width_left = 1
	hub_sb.border_width_top = 1
	hub_sb.border_width_right = 1
	hub_sb.border_width_bottom = 1
	hub_sb.border_color = Tokens.LINE
	hub_sb.corner_radius_top_left = 2
	hub_sb.corner_radius_top_right = 2
	hub_sb.corner_radius_bottom_left = 2
	hub_sb.corner_radius_bottom_right = 2
	hub_btn.add_theme_stylebox_override("normal", hub_sb)

	var hub_hover := hub_sb.duplicate() as StyleBoxFlat
	hub_hover.bg_color = Color(1, 1, 1, 0.05)
	hub_btn.add_theme_stylebox_override("hover", hub_hover)
	hub_btn.add_theme_stylebox_override("pressed", hub_hover)
	hub_btn.pressed.connect(_on_return_to_hub_pressed)
	sec_row.add_child(hub_btn)

	_cancel_auto_btn = Button.new()
	_cancel_auto_btn.text = "CANCEL AUTO"
	_cancel_auto_btn.custom_minimum_size = Vector2(100, 48)
	_cancel_auto_btn.add_theme_font_override("font", Tokens.FONT_MONO)
	_cancel_auto_btn.add_theme_font_size_override("font_size", 10)
	_cancel_auto_btn.add_theme_color_override("font_color", Tokens.DIM)
	_cancel_auto_btn.add_theme_color_override("font_hover_color", Tokens.WHITE)

	var cancel_sb := StyleBoxFlat.new()
	cancel_sb.bg_color = Color(0, 0, 0, 0)
	cancel_sb.border_width_left = 1
	cancel_sb.border_width_top = 1
	cancel_sb.border_width_right = 1
	cancel_sb.border_width_bottom = 1
	cancel_sb.border_color = Tokens.LINE
	cancel_sb.corner_radius_top_left = 2
	cancel_sb.corner_radius_top_right = 2
	cancel_sb.corner_radius_bottom_left = 2
	cancel_sb.corner_radius_bottom_right = 2
	cancel_sb.content_margin_left = 14
	cancel_sb.content_margin_right = 14
	_cancel_auto_btn.add_theme_stylebox_override("normal", cancel_sb)

	var cancel_hover := cancel_sb.duplicate() as StyleBoxFlat
	cancel_hover.bg_color = Color(1, 1, 1, 0.05)
	_cancel_auto_btn.add_theme_stylebox_override("hover", cancel_hover)
	_cancel_auto_btn.add_theme_stylebox_override("pressed", cancel_hover)
	_cancel_auto_btn.pressed.connect(_on_cancel_auto_pressed)
	sec_row.add_child(_cancel_auto_btn)

func _make_stat_cell(label_text: String, value_text: String, unit_text: String = "", loading: bool = false) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cell_sb := StyleBoxFlat.new()
	cell_sb.bg_color = Color(0, 0, 0, 0)
	cell_sb.border_width_top = 1
	cell_sb.border_color = Tokens.LINE
	cell_sb.content_margin_top = 8
	cell_sb.content_margin_left = 0
	cell_sb.content_margin_right = 0
	cell_sb.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", cell_sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	cell.add_child(vbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Tokens.DIM)
	vbox.add_child(lbl)

	var val_hbox := HBoxContainer.new()
	val_hbox.add_theme_constant_override("separation", 4)
	val_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(val_hbox)

	cell.set_meta("value_box", val_hbox)
	if loading:
		# Value still on its way: a pulsing bar the size of a typical "#12" at 36px
		val_hbox.add_child(SkeletonBarClass.slot(64, 24, 32))
		return cell

	var val := Tokens.tight_display_label(value_text, 36, Tokens.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _display_width(value_text, 36))
	val_hbox.add_child(val.get_parent())

	if unit_text != "":
		# Same baseline as the value: both boxes end at the baseline, so bottom-align.
		var unit := Tokens.tight_display_label(unit_text, 20, Tokens.DIM, HORIZONTAL_ALIGNMENT_LEFT, _display_width(unit_text, 20))
		unit.get_parent().size_flags_vertical = Control.SIZE_SHRINK_END
		val_hbox.add_child(unit.get_parent())

	return cell

## Width of a display-font string, so a tight label's box is as wide as its text.
func _display_width(text: String, font_size: int) -> float:
	return ceilf(Tokens.FONT_DISPLAY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 2.0

## Replaces the GLOBAL RANK skeleton with the real value ("—" when unknown).
func _set_rank(text: String) -> void:
	if not _rank_value_box or not is_instance_valid(_rank_value_box):
		return
	for c in _rank_value_box.get_children():
		_rank_value_box.remove_child(c)
		c.queue_free()
	var val := Tokens.tight_display_label(text, 36, Tokens.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _display_width(text, 36))
	_rank_value_box.add_child(val.get_parent())

func _fetch_rank() -> void:
	if not (get_tree().root.has_node("Backend") and FirebaseConfig.is_configured()):
		_set_rank("—")
		return
	# Rank the player's best (it includes this run: record_workout saved it before we got here)
	var best: int = maxi(_score, SessionManager.get_best_score(_mode_id))
	var backend_key: String = "switcher" if _mode_id == "lane" else _mode_id
	var result: Dictionary = await Backend.fetch_leaderboard(backend_key, RANK_BOARD_LIMIT)
	if not is_instance_valid(self):
		return
	# Offline or failed: "—" rather than a guess
	_set_rank(Backend.rank_label(result.rows, best, RANK_BOARD_LIMIT) if result.ok else "—")

func _on_score_submit_finished(_ok: bool) -> void:
	_refresh_banner()

## Skins the banner for the upload's real state:
##   pending: "…" + skeleton subline (we don't know yet)
##   ok:      the original "submitted / posted" wording
##   failed:  honest "saved on device / not posted" wording
## A personal best is a local fact, so its title stays "NEW PERSONAL BEST!" regardless.
func _refresh_banner() -> void:
	if not _banner_title:
		return
	var state: String = Backend.submit_state
	var pending := state == "pending"
	var posted := state == "ok"
	var best_text := _format_number(_previous_best) if _previous_best > 0 else "—"
	var lead := ("BEAT %s" if _is_pb else "PB %s") % best_text
	if _is_pb and _previous_best <= 0:
		lead = "FIRST SCORE"

	if _is_pb:
		_banner_icon.text = "…" if pending else "★"
		_banner_title.text = "NEW PERSONAL BEST!"
	elif pending:
		_banner_icon.text = "…"
		_banner_title.text = "POSTING SCORE"
	elif posted:
		_banner_icon.text = "✓"
		_banner_title.text = "SCORE SUBMITTED"
	else:
		_banner_icon.text = "!"
		_banner_title.text = "SAVED ON DEVICE"

	_banner_sub.visible = not pending
	_banner_sub_skeleton.visible = pending
	_banner_sub.text = "%s  ·  %s" % [lead, "POSTED TO LEADERBOARD" if posted else "NOT POSTED TO LEADERBOARD"]

func _make_spacer(h: int) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp

func _format_time(s: float) -> String:
	var total_sec := int(s)
	return "%d:%02d" % [total_sec / 60, total_sec % 60]

func _format_number(n: int) -> String:
	if n == 0:
		return "0"
	var is_neg := n < 0
	var s := str(abs(n))
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if is_neg else "") + out

func _on_play_again_pressed() -> void:
	_auto_active = false
	GameManager.pending_game_name = _mode_id
	GameManager.selected_game_name = ""
	get_tree().change_scene_to_file("res://ui/CalibrationScreen.tscn")

func _on_return_to_hub_pressed() -> void:
	_auto_active = false
	GameManager.selected_game_name = ""
	GameManager.pending_game_name = ""
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_cancel_auto_pressed() -> void:
	_auto_active = false
	if _play_again_btn:
		_play_again_btn.sweep_pct = 0.0
		_play_again_btn.button_label = "PLAY AGAIN"
	if _cancel_auto_btn:
		_cancel_auto_btn.visible = false
