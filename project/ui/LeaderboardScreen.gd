class_name LeaderboardScreen
extends Control

## Leaderboard screen for FitArcade.
## Visual source of truth: references/02-leaderboard.png
## Spec from design-spec.md Section C10, C11, C12, D5 and Leaderboard.tsx.

const TouchScrollClass = preload("res://ui/components/TouchScroll.gd")
const PageHeaderClass = preload("res://ui/components/PageHeader.gd")
const LeaderboardSkeletonClass = preload("res://ui/components/LeaderboardSkeleton.gd")

## Placeholder rows shown while loading (matches the table's top-10 cutoff)
const SKELETON_ROWS := 10

var _load_serial: int = 0
var _skeleton_tween: Tween
var _active_mode_id: String = "dino"
var _tab_buttons: Dictionary = {}
var _tabs_container: HBoxContainer
var _podium_container: HBoxContainer
var _table_content_vbox: VBoxContainer
var _scroll_container: ScrollContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_load_mode_data(_active_mode_id)

func _draw() -> void:
	# Screen background: #0B0B0C (ink)
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.INK, true)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Safe mobile margin container: Top 64, Left 20, Right 20, Bottom 20
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 0)
	margin.add_child(root_vbox)

	# 1. PageHeader ("Leaderboard" + breadcrumb "HUB / LEADERBOARD")
	var header := PageHeaderClass.new()
	header.title = "LEADERBOARD"
	header.breadcrumb_parent = "HUB"
	header.back_pressed.connect(_on_back_pressed)
	root_vbox.add_child(header)

	# 16px gap below PageHeader
	var gap16 := Control.new()
	gap16.custom_minimum_size = Vector2(0, 16)
	root_vbox.add_child(gap16)

	# 2. ModeTabs (flexible container supporting 3 or more exercises)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_scroll.custom_minimum_size = Vector2(0, 40)
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_vbox.add_child(tabs_scroll)
	TouchScrollClass.apply(tabs_scroll)

	# 1px line border around tab strip
	var tabs_wrapper := PanelContainer.new()
	tabs_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_wrap_sb := StyleBoxFlat.new()
	tab_wrap_sb.bg_color = Color(0, 0, 0, 0)
	tab_wrap_sb.border_width_left = 1
	tab_wrap_sb.border_width_top = 1
	tab_wrap_sb.border_width_right = 1
	tab_wrap_sb.border_width_bottom = 1
	tab_wrap_sb.border_color = Tokens.LINE
	tabs_wrapper.add_theme_stylebox_override("panel", tab_wrap_sb)
	tabs_scroll.add_child(tabs_wrapper)

	_tabs_container = HBoxContainer.new()
	_tabs_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs_container.add_theme_constant_override("separation", 0)
	tabs_wrapper.add_child(_tabs_container)

	_tab_buttons.clear()
	for m in Tokens.MODES:
		var m_id: String = m["id"]
		var btn := Button.new()
		btn.name = "Tab_" + m_id
		btn.text = m["exercise"].to_upper()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(114, 38)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_tab_selected.bind(m_id))
		_tabs_container.add_child(btn)
		_tab_buttons[m_id] = btn

	# 24px gap below tabs
	var gap24 := Control.new()
	gap24.custom_minimum_size = Vector2(0, 24)
	root_vbox.add_child(gap24)

	# 3. Podium (Top 3 ranks 2, 1, 3)
	_podium_container = HBoxContainer.new()
	_podium_container.name = "Podium"
	_podium_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_podium_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium_container.add_theme_constant_override("separation", 8)
	root_vbox.add_child(_podium_container)

	# 20px gap below Podium
	var gap20 := Control.new()
	gap20.custom_minimum_size = Vector2(0, 20)
	root_vbox.add_child(gap20)

	# 4. LeaderboardTable Header Row ("#", "PLAYER", "SCORE / DATE")
	var th_panel := PanelContainer.new()
	th_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var th_sb := StyleBoxFlat.new()
	th_sb.bg_color = Color(0, 0, 0, 0)
	th_sb.border_width_bottom = 1
	th_sb.border_color = Tokens.LINE
	th_sb.content_margin_left = 10
	th_sb.content_margin_right = 10
	th_sb.content_margin_bottom = 4
	th_panel.add_theme_stylebox_override("panel", th_sb)
	root_vbox.add_child(th_panel)

	var th_hbox := HBoxContainer.new()
	th_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th_hbox.add_theme_constant_override("separation", 12)
	th_panel.add_child(th_hbox)

	var th_rank := Label.new()
	th_rank.text = "#"
	th_rank.custom_minimum_size = Vector2(36, 0)
	th_rank.add_theme_font_override("font", Tokens.FONT_MONO)
	th_rank.add_theme_font_size_override("font_size", 10)
	th_rank.add_theme_color_override("font_color", Tokens.DIM)
	th_hbox.add_child(th_rank)

	var th_player := Label.new()
	th_player.text = "PLAYER"
	th_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th_player.add_theme_font_override("font", Tokens.FONT_MONO)
	th_player.add_theme_font_size_override("font_size", 10)
	th_player.add_theme_color_override("font_color", Tokens.DIM)
	th_hbox.add_child(th_player)

	var th_score := Label.new()
	th_score.text = "SCORE  /  DATE"
	th_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	th_score.add_theme_font_override("font", Tokens.FONT_MONO)
	th_score.add_theme_font_size_override("font_size", 10)
	th_score.add_theme_color_override("font_color", Tokens.DIM)
	th_hbox.add_child(th_score)

	# 5. LeaderboardTable Scroll Area
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "TableScroll"
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_vbox.add_child(_scroll_container)
	TouchScrollClass.apply(_scroll_container)

	# Hide scrollbar completely as per Figma spec
	var v_bar := _scroll_container.get_v_scroll_bar()
	var empty_sb := StyleBoxEmpty.new()
	v_bar.custom_minimum_size = Vector2.ZERO
	v_bar.scale = Vector2.ZERO
	v_bar.modulate = Color(0, 0, 0, 0)
	v_bar.add_theme_stylebox_override("scroll", empty_sb)
	v_bar.add_theme_stylebox_override("scroll_focus", empty_sb)
	v_bar.add_theme_stylebox_override("grabber", empty_sb)
	v_bar.add_theme_stylebox_override("grabber_highlight", empty_sb)
	v_bar.add_theme_stylebox_override("grabber_pressed", empty_sb)

	var h_bar := tabs_scroll.get_h_scroll_bar()
	h_bar.custom_minimum_size = Vector2.ZERO
	h_bar.scale = Vector2.ZERO
	h_bar.modulate = Color(0, 0, 0, 0)
	h_bar.add_theme_stylebox_override("scroll", empty_sb)

	_table_content_vbox = VBoxContainer.new()
	_table_content_vbox.name = "TableRows"
	_table_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_content_vbox.add_theme_constant_override("separation", 0)
	_scroll_container.add_child(_table_content_vbox)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_tab_selected(mode_id: String) -> void:
	if mode_id == _active_mode_id:
		return
	_active_mode_id = mode_id
	_load_mode_data(_active_mode_id)

func _update_tab_buttons(active_color: Color) -> void:
	for m_id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[m_id]
		var is_act: bool = (m_id == _active_mode_id)

		var sb := StyleBoxFlat.new()
		if is_act:
			sb.bg_color = active_color
			btn.add_theme_color_override("font_color", Tokens.INK)
			btn.add_theme_color_override("font_hover_color", Tokens.INK)
			btn.add_theme_color_override("font_pressed_color", Tokens.INK)
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			btn.add_theme_color_override("font_color", Tokens.DIM)
			btn.add_theme_color_override("font_hover_color", Tokens.WHITE)
			btn.add_theme_color_override("font_pressed_color", Tokens.WHITE)

		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)

func _load_mode_data(mode_id: String) -> void:
	var mode_info := Tokens.get_mode(mode_id)
	var active_color: Color = mode_info["color"]
	_update_tab_buttons(active_color)

	_fetch_cloud_scores(mode_id, active_color)

## Shows the loading skeleton, fetches the live board, then swaps in the result:
## rows, an empty-board message, or a failure message with retry. There is no
## placeholder data: what's on screen is either real or visibly loading.
func _fetch_cloud_scores(mode_id: String, active_color: Color) -> void:
	# Each call supersedes earlier ones, so a slow response for a tab the player has
	# already left (or a retry that raced the first request) can't overwrite the board.
	_load_serial += 1
	var serial := _load_serial
	_show_skeleton()

	if not get_tree().root.has_node("Backend") or not FirebaseConfig.is_configured():
		_show_error(active_color)
		return

	var backend_key: String = "switcher" if mode_id == "lane" else mode_id
	var result: Dictionary = await Backend.fetch_leaderboard(backend_key, 50)
	if not is_instance_valid(self) or serial != _load_serial:
		return
	if not result.ok:
		_show_error(active_color)
		return
	_show_rows(_format_cloud_rows(result.rows), active_color)

func _format_cloud_rows(cloud_docs: Array) -> Array:
	var list: Array = []
	for doc in cloud_docs:
		var name_str: String = doc.get("display_name", "ANONYMOUS")
		var display_tag: String = doc.get("display_tag", "")
		var tag_num: String = display_tag.split("#")[-1] if display_tag.find("#") != -1 else ""
		list.append({
			"name": name_str.to_upper(),
			"tag": "#" + tag_num if tag_num != "" else "",
			"badge": Tokens.initials(name_str, "?"),
			"score": int(doc.get("score", 0)),
			"date": _format_date(doc.get("updated_at", "")),
			"uid": doc.get("uid", ""),
		})
	return list

## "2026-09-30 21:05:00" -> "Sep 30". Anything unparseable shows as an em dash.
func _format_date(stamp: String) -> String:
	var parts := stamp.substr(0, 10).split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "—"
	var month := int(parts[1])
	if month < 1 or month > 12:
		return "—"
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d" % [MONTHS[month - 1], int(parts[2])]

# -----------------------------------------------------------------------------
# Board states: loading / loaded / empty / failed
# -----------------------------------------------------------------------------
func _show_skeleton() -> void:
	_clear_board()
	LeaderboardSkeletonClass.fill_podium(_podium_container)
	LeaderboardSkeletonClass.fill_rows(_table_content_vbox, SKELETON_ROWS)
	_skeleton_tween = LeaderboardSkeletonClass.start_pulse(self, [_podium_container, _table_content_vbox])

func _stop_skeleton() -> void:
	if _skeleton_tween and _skeleton_tween.is_valid():
		_skeleton_tween.kill()
	_skeleton_tween = null
	_podium_container.modulate.a = 1.0
	_table_content_vbox.modulate.a = 1.0

func _clear_board() -> void:
	_stop_skeleton()
	# Detach now (so new content never shares the container with stale nodes), but
	# free at end of frame: the TRY AGAIN button lives inside the error block being
	# cleared and is still mid-`pressed` signal, which Godot won't let us free() directly.
	for container in [_podium_container, _table_content_vbox]:
		for c in container.get_children():
			container.remove_child(c)
			c.queue_free()

func _show_rows(rows: Array, active_color: Color) -> void:
	_clear_board()
	var board := _with_my_local_best(rows)
	if board.is_empty():
		_table_content_vbox.add_child(_make_state_block(
			"NO SCORES YET",
			"Nobody has posted a score in this game yet. Play a round to claim the top spot."))
		return
	_render_podium(board, active_color)
	_render_table(board, active_color)

func _show_error(active_color: Color) -> void:
	_clear_board()
	_table_content_vbox.add_child(_make_state_block(
		"COULDN'T LOAD SCORES",
		"Check your connection and try again.",
		func(): _fetch_cloud_scores(_active_mode_id, active_color)))

## Cloud rows plus the player's own on-device best when the cloud doesn't have it
## (offline, or posted from a run that hasn't synced). Inserted by score so the rank
## is right, and flagged so the table highlights it.
func _with_my_local_best(rows: Array) -> Array:
	var board := rows.duplicate()
	var me := _my_identity()
	if _find_me(board) != -1:
		return board
	var local_best: int = SessionManager.get_best_score(_active_mode_id) if get_tree().root.has_node("SessionManager") else 0
	if local_best <= 0:
		return board
	var pos := 0
	while pos < board.size() and int(board[pos].get("score", 0)) >= local_best:
		pos += 1
	board.insert(pos, {
		"name": me.name, "tag": me.tag, "badge": me.badge, "score": local_best,
		"date": "ON DEVICE", "uid": me.uid, "is_me": true,
	})
	return board

func _my_identity() -> Dictionary:
	var has_backend := get_tree().root.has_node("Backend")
	var profile: Dictionary = Backend.profile if has_backend else {}
	var display_name: String = str(profile.get("display_name", "YOU")).to_upper()
	var tag_number: String = str(profile.get("tag_number", ""))
	return {
		"uid": Backend.uid if has_backend else "",
		"name": display_name,
		"tag": "#" + tag_number if tag_number != "" else "",
		"badge": Tokens.initials(display_name, "?"),
	}

## Index of the player's row, or -1. Matched by account id only: names and
## 4-digit tags aren't unique, so matching on them could highlight someone else.
func _find_me(rows: Array) -> int:
	var my_uid: String = _my_identity().uid
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r.get("is_me", false) or (my_uid != "" and r.get("uid", "") == my_uid):
			return i
	return -1

## Centered message used for the empty and failed states (the spec's flat, hard-edged
## style: Anton title, sans body, 1px `line` outlined retry button).
func _make_state_block(title: String, body: String, on_retry: Callable = Callable()) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)

	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 40)
	box.add_child(top)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	box.add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_override("font", Tokens.FONT_SANS)
	body_lbl.add_theme_font_size_override("font_size", 14)
	body_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(body_lbl)

	if on_retry.is_valid():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		box.add_child(gap)

		var btn := Button.new()
		btn.text = "TRY AGAIN"
		btn.custom_minimum_size = Vector2(160, 44)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Tokens.WHITE)
		btn.add_theme_color_override("font_hover_color", Tokens.INK)
		btn.add_theme_color_override("font_pressed_color", Tokens.INK)
		var normal := Tokens.make_panel_style(Color(0, 0, 0, 0), Tokens.LINE, 1)
		var hover := Tokens.make_panel_style(Tokens.VOLT, Tokens.VOLT, 1)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.pressed.connect(on_retry)
		box.add_child(btn)
	return box

func _render_podium(rows: Array, active_color: Color) -> void:
	for c in _podium_container.get_children():
		c.queue_free()

	if rows.size() == 0:
		return

	# Podium requires 3 spots in order: 2nd, 1st, 3rd
	var r2 = rows[1] if rows.size() > 1 else {"name": "—", "badge": "—", "score": 0}
	var r1 = rows[0] if rows.size() > 0 else {"name": "—", "badge": "—", "score": 0}
	var r3 = rows[2] if rows.size() > 2 else {"name": "—", "badge": "—", "score": 0}

	var podium_data = [
		{"rank": 2, "height": 70, "color": Color("#E8E8E8"), "data": r2},
		{"rank": 1, "height": 100, "color": active_color, "data": r1},
		{"rank": 3, "height": 50, "color": Color("#8A8A92"), "data": r3}
	]

	for item in podium_data:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_END
		col.add_theme_constant_override("separation", 0)
		_podium_container.add_child(col)

		var p_info: Dictionary = item["data"]

		# 1. Badge: 48x48 with 2px border in active_color
		var badge_box := PanelContainer.new()
		badge_box.custom_minimum_size = Vector2(48, 48)
		badge_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var badge_sb := StyleBoxFlat.new()
		badge_sb.bg_color = Tokens.INK
		badge_sb.border_width_left = 2
		badge_sb.border_width_top = 2
		badge_sb.border_width_right = 2
		badge_sb.border_width_bottom = 2
		badge_sb.border_color = active_color
		badge_box.add_theme_stylebox_override("panel", badge_sb)
		col.add_child(badge_box)

		var badge_lbl := Label.new()
		badge_lbl.text = p_info.get("badge", "—")
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		badge_lbl.add_theme_font_size_override("font_size", 18)
		badge_lbl.add_theme_color_override("font_color", Tokens.WHITE)
		badge_box.add_child(badge_lbl)

		# 4px gap
		var g4 := Control.new()
		g4.custom_minimum_size = Vector2(0, 4)
		col.add_child(g4)

		# 2. Player Name
		var name_lbl := Label.new()
		name_lbl.text = p_info.get("name", "—")
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_lbl.clip_text = false
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		name_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Tokens.WHITE)
		col.add_child(name_lbl)

		# 3. Score
		var sc_val: int = p_info.get("score", 0)
		var sc_lbl := Label.new()
		sc_lbl.text = Tokens.format_thousands(sc_val) if sc_val > 0 else "—"
		sc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sc_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
		sc_lbl.add_theme_font_size_override("font_size", 10)
		sc_lbl.add_theme_color_override("font_color", Tokens.DIM)
		col.add_child(sc_lbl)

		# 8px gap
		var g8 := Control.new()
		g8.custom_minimum_size = Vector2(0, 8)
		col.add_child(g8)

		# 4. Podium Block with big rank number
		var block := PanelContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.custom_minimum_size = Vector2(0, item["height"])
		var b_sb := StyleBoxFlat.new()
		b_sb.bg_color = item["color"]
		b_sb.content_margin_left = 8
		b_sb.content_margin_top = 2
		block.add_theme_stylebox_override("panel", b_sb)
		col.add_child(block)

		var rank_lbl := Label.new()
		rank_lbl.text = str(item["rank"])
		rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		rank_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
		rank_lbl.add_theme_font_size_override("font_size", 36)
		rank_lbl.add_theme_color_override("font_color", Tokens.INK)
		block.add_child(rank_lbl)

func _render_table(rows: Array, active_color: Color) -> void:
	for c in _table_content_vbox.get_children():
		c.queue_free()

	const MAX_TOP := 10

	var me_index := _find_me(rows)

	# 1. Render up to MAX_TOP (first 10) rows
	for i in range(mini(rows.size(), MAX_TOP)):
		_table_content_vbox.add_child(_make_table_row(i + 1, rows[i], i == me_index, active_color, false))

	# 2. Player is beyond the top 10: pin them in the 11th slot, with a gap marker
	#    when ranks were skipped.
	if me_index >= MAX_TOP:
		var my_rank := me_index + 1
		if my_rank > MAX_TOP + 1:
			_table_content_vbox.add_child(_make_rank_gap_row())
		_table_content_vbox.add_child(_make_table_row(my_rank, rows[me_index], true, active_color, true))
	# 3. Full board and the player isn't on it: show them unranked just below it
	elif me_index == -1 and rows.size() >= MAX_TOP:
		var me := _my_identity()
		var unranked := {"name": me.name, "tag": me.tag, "badge": me.badge, "score": 0, "date": "—", "uid": me.uid}
		_table_content_vbox.add_child(_make_rank_gap_row())
		_table_content_vbox.add_child(_make_table_row("—", unranked, true, active_color, true))

func _make_rank_gap_row() -> Control:
	var container := PanelContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	container.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	container.add_child(hbox)

	# Col 1: In the 36px rank column, 3 clean vertical dots
	var dots_col := VBoxContainer.new()
	dots_col.custom_minimum_size = Vector2(36, 0)
	dots_col.alignment = BoxContainer.ALIGNMENT_CENTER
	dots_col.add_theme_constant_override("separation", 3)
	hbox.add_child(dots_col)

	for i in range(3):
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(4, 4)
		d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		d.color = Tokens.DIM
		dots_col.add_child(d)

	# Col 2: Elegant line with centered "· · ·" across player/score area
	var right_box := HBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_CENTER
	right_box.add_theme_constant_override("separation", 8)
	hbox.add_child(right_box)

	var l1 := ColorRect.new()
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l1.custom_minimum_size = Vector2(0, 1)
	l1.color = Color(1, 1, 1, 0.12)
	right_box.add_child(l1)

	var tag_lbl := Label.new()
	tag_lbl.text = "· · ·"
	tag_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", Tokens.DIM)
	right_box.add_child(tag_lbl)

	var l2 := ColorRect.new()
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l2.custom_minimum_size = Vector2(0, 1)
	l2.color = Color(1, 1, 1, 0.12)
	right_box.add_child(l2)

	return container

func _make_table_row(rank_num: Variant, r: Dictionary, is_me: bool, active_color: Color, is_11th_slot: bool = false) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_sb := StyleBoxFlat.new()
	r_sb.bg_color = Color(1, 1, 1, 0.06) if is_me else Color(0, 0, 0, 0)
	r_sb.border_width_bottom = 1
	r_sb.border_color = Tokens.LINE
	r_sb.content_margin_left = 10
	r_sb.content_margin_right = 10
	r_sb.content_margin_top = 10
	r_sb.content_margin_bottom = 10
	if is_11th_slot:
		r_sb.border_width_top = 1
		r_sb.border_color = Color(1, 1, 1, 0.15)
	row_panel.add_theme_stylebox_override("panel", r_sb)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	row_panel.add_child(hbox)

	# Col 1: Rank Number (Anton 24px)
	var rank_lbl := Label.new()
	rank_lbl.text = str(rank_num)
	rank_lbl.custom_minimum_size = Vector2(36, 0)
	rank_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	rank_lbl.add_theme_font_size_override("font_size", 24)
	var is_top3: bool = false
	if typeof(rank_num) == TYPE_INT and rank_num <= 3:
		is_top3 = true
	var rank_col: Color = active_color if is_top3 else Color("#F4F4F0")
	rank_lbl.add_theme_color_override("font_color", rank_col)
	hbox.add_child(rank_lbl)

	# Col 2: Player Badge + Name & Tag
	var player_box := HBoxContainer.new()
	player_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_box.add_theme_constant_override("separation", 8)
	hbox.add_child(player_box)

	# 32x32 Monogram Badge
	var badge_panel := CenterContainer.new()
	badge_panel.custom_minimum_size = Vector2(32, 32)
	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = Tokens.PANEL
	b_sb.border_width_left = 1
	b_sb.border_width_top = 1
	b_sb.border_width_right = 1
	b_sb.border_width_bottom = 1
	b_sb.border_color = Tokens.LINE
	badge_panel.add_theme_stylebox_override("panel", b_sb)
	player_box.add_child(badge_panel)

	var b_text := Label.new()
	b_text.text = r.get("badge", "—")
	b_text.add_theme_font_override("font", Tokens.FONT_MONO)
	b_text.add_theme_font_size_override("font_size", 10)
	b_text.add_theme_color_override("font_color", Tokens.WHITE)
	badge_panel.add_child(b_text)

	# Name & Tag Column
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", 2)
	player_box.add_child(name_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_col.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = r.get("name", "—")
	name_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	name_row.add_child(name_lbl)

	if is_me:
		var you_chip := PanelContainer.new()
		var you_sb := StyleBoxFlat.new()
		you_sb.bg_color = Tokens.VOLT
		you_sb.content_margin_left = 4
		you_sb.content_margin_right = 4
		you_sb.content_margin_top = 1
		you_sb.content_margin_bottom = 1
		you_chip.add_theme_stylebox_override("panel", you_sb)
		name_row.add_child(you_chip)

		var you_lbl := Label.new()
		you_lbl.text = "YOU"
		you_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
		you_lbl.add_theme_font_size_override("font_size", 9)
		you_lbl.add_theme_color_override("font_color", Tokens.INK)
		you_chip.add_child(you_lbl)

	var tag_lbl := Label.new()
	tag_lbl.text = r.get("tag", "#0000")
	tag_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Tokens.DIM)
	name_col.add_child(tag_lbl)

	# Col 3: Score & Date Column (Right-aligned)
	var score_col := VBoxContainer.new()
	score_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_col.add_theme_constant_override("separation", 2)
	hbox.add_child(score_col)

	var score_lbl := Label.new()
	var sc_val: int = int(r.get("score", 0))
	score_lbl.text = Tokens.format_thousands(sc_val) if sc_val > 0 else "—"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	score_lbl.add_theme_font_size_override("font_size", 20)
	score_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	score_col.add_child(score_lbl)

	var date_lbl := Label.new()
	date_lbl.text = r.get("date", "—")
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	date_lbl.add_theme_font_size_override("font_size", 10)
	date_lbl.add_theme_color_override("font_color", Tokens.DIM)
	score_col.add_child(date_lbl)

	return row_panel
