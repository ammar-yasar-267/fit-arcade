class_name SettingsScreen
extends Control

## Settings screen for FitArcade.
## Features collapsible sections:
## 1. Gameplay & Workout (Open by default: Skip Calibration, Audio, Skeleton, Haptics)
## 2. Display & Diagnostics (Collapsed by default: Debug Info, Mirror Camera, High Contrast HUD)
## 3. Account (Collapsed by default: identity card, Delete Account)
## 4. Advanced & Developer Options (Collapsed by default: Hardware Accel)

const TouchScrollClass = preload("res://ui/components/TouchScroll.gd")
const PageHeaderClass = preload("res://ui/components/PageHeader.gd")
const HexBadgeClass = preload("res://ui/components/HexBadge.gd")
const DeleteAccountOverlayClass = preload("res://ui/components/DeleteAccountOverlay.gd")
const SignOutOverlayClass = preload("res://ui/components/SignOutOverlay.gd")

## A tap is a press and release WITHOUT the finger travelling. Rows react to taps only, so a swipe
## that starts on a row scrolls the list instead of flipping the switch under the finger (they used
## to flip on touch-down). Feed it every mouse event the control gets; it returns true once, when
## a tap completes. Travel is measured in screen space, so the list scrolling under a still finger
## doesn't matter.
class TapTracker:
	const MAX_TRAVEL := 10.0
	var _down := false
	var _moved := false
	var _down_at := Vector2.ZERO

	func tapped(event: InputEvent) -> bool:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_moved = false
				_down_at = event.global_position
				return false
			var was_tap := _down and not _moved
			_down = false
			return was_tap
		if event is InputEventMouseMotion and _down:
			if event.global_position.distance_to(_down_at) > MAX_TRAVEL:
				_moved = true
		return false


# Custom Pill Toggle Switch Control
class ToggleSwitch extends Control:
	signal toggled_state(is_on: bool)

	var is_on: bool = false:
		set(v):
			is_on = v
			queue_redraw()

	func _init(initial: bool = false) -> void:
		is_on = initial
		custom_minimum_size = Vector2(46, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	## Taps are handled by the row that contains the switch (see _build_toggle_row), so the
	## switch itself is transparent to input.

	func _draw() -> void:
		var w := 46.0
		var h := 26.0
		var r := 13.0
		var thumb_r := 8.5

		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = int(r)
		sb.corner_radius_top_right = int(r)
		sb.corner_radius_bottom_left = int(r)
		sb.corner_radius_bottom_right = int(r)

		if is_on:
			sb.bg_color = Tokens.VOLT
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Tokens.VOLT
		else:
			sb.bg_color = Color("#1C1C20")
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Tokens.LINE

		sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, Vector2(w, h)))

		var thumb_center_x := w - 4.5 - thumb_r if is_on else 4.5 + thumb_r
		var thumb_center_y := h / 2.0
		var thumb_color := Tokens.INK if is_on else Color("#8E8E96")
		draw_circle(Vector2(thumb_center_x, thumb_center_y), thumb_r, thumb_color)


var _scroll_container: ScrollContainer
var _toast_label: Label
var _delete_overlay: Control
var _sign_out_overlay: Control
var _account_vbox: VBoxContainer
var _toast_tween: Tween

# Toggles dictionary to allow bulk-updating upon reset
var _toggles: Dictionary = {}

# Hardware acceleration buttons
var _accel_cpu_btn: Button
var _accel_gpu_btn: Button
var _accel_helper_lbl: Label

# Sections array to allow external inspection or test toggling
var _sections: Array = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_update_accel_ui()
	Backend.google_linked_state_changed.connect(func(_is_linked: bool): _rebuild_account_section())

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

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "ScrollContainer"
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(_scroll_container)
	TouchScrollClass.apply(_scroll_container)

	# Hide scrollbar per Figma spec
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

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 0)
	_scroll_container.add_child(root_vbox)

	_sections.clear()

	# 1. PageHeader ("SETTINGS" + breadcrumb "HUB / SETTINGS")
	var header := PageHeaderClass.new()
	header.title = "SETTINGS"
	header.breadcrumb_parent = "HUB"
	header.back_pressed.connect(_on_back_pressed)
	root_vbox.add_child(header)

	root_vbox.add_child(_make_spacer(24))

	# Toast notification label (for reset feedback)
	_toast_label = Label.new()
	_toast_label.visible = false
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_override("font", Tokens.FONT_MONO)
	_toast_label.add_theme_font_size_override("font_size", 11)
	_toast_label.add_theme_color_override("font_color", Tokens.VOLT)
	root_vbox.add_child(_toast_label)

	# ---------------------------------------------------------
	# SECTION 1: GAMEPLAY & WORKOUT (OPEN by default)
	# ---------------------------------------------------------
	var sec1 = _build_collapsible_section("GAMEPLAY & WORKOUT", "4 OPTIONS", true, false)
	_sections.append(sec1)
	root_vbox.add_child(sec1["header"])
	root_vbox.add_child(sec1["wrapper"])

	var sec1_vbox: VBoxContainer = sec1["content"]
	sec1_vbox.add_child(_build_toggle_row(
		"skip_calibration",
		"SKIP CALIBRATION",
		"Jump straight into games without running pose calibration check.",
		Settings.skip_calibration,
		func(val: bool):
			Settings.skip_calibration = val
			Settings.save_settings(),
		false
	))
	sec1_vbox.add_child(_build_toggle_row(
		"sound_enabled",
		"SOUND & AUDIO CUES",
		"Play rep confirmation chimes, countdown audio, and game sound effects.",
		Settings.sound_enabled,
		func(val: bool):
			Settings.sound_enabled = val
			Settings.save_settings(),
		false
	))
	sec1_vbox.add_child(_build_toggle_row(
		"show_skeleton",
		"POSE SKELETON OVERLAY",
		"Display visual joint landmarks and tracking skeleton on camera feed.",
		Settings.show_skeleton,
		func(val: bool):
			Settings.show_skeleton = val
			Settings.save_settings(),
		false
	))
	sec1_vbox.add_child(_build_toggle_row(
		"haptics_enabled",
		"HAPTIC FEEDBACK",
		"Tactile vibration feedback when reps and workout milestones are counted.",
		Settings.haptics_enabled,
		func(val: bool):
			Settings.haptics_enabled = val
			Settings.save_settings(),
		true
	))

	root_vbox.add_child(_make_spacer(14))

	# ---------------------------------------------------------
	# SECTION 2: DISPLAY & DIAGNOSTICS (COLLAPSED by default)
	# ---------------------------------------------------------
	var sec2 = _build_collapsible_section("DISPLAY & DIAGNOSTICS", "3 OPTIONS", false, false)
	_sections.append(sec2)
	root_vbox.add_child(sec2["header"])
	root_vbox.add_child(sec2["wrapper"])

	var sec2_vbox: VBoxContainer = sec2["content"]
	sec2_vbox.add_child(_build_toggle_row(
		"show_debug_info",
		"ENABLE DEBUG INFO",
		"Show real-time FPS counter, inference latency & memory diagnostics.",
		Settings.show_debug_info,
		func(val: bool):
			Settings.show_debug_info = val
			Settings.save_settings(),
		false
	))
	sec2_vbox.add_child(_build_toggle_row(
		"mirror_camera",
		"MIRROR CAMERA FEED",
		"Flip front camera preview horizontally so it behaves like a mirror.",
		Settings.mirror_camera,
		func(val: bool):
			Settings.mirror_camera = val
			Settings.save_settings(),
		false
	))
	sec2_vbox.add_child(_build_toggle_row(
		"high_contrast_hud",
		"HIGH CONTRAST HUD",
		"Enhance score, rep counter, and timer contrast for high-glare environments.",
		Settings.high_contrast_hud,
		func(val: bool):
			Settings.high_contrast_hud = val
			Settings.save_settings(),
		true
	))

	root_vbox.add_child(_make_spacer(14))

	# ---------------------------------------------------------
	# SECTION 3: ACCOUNT (COLLAPSED by default): who you are + delete account
	# ---------------------------------------------------------
	var sec_account = _build_collapsible_section("ACCOUNT", "PROFILE", false, false)
	_sections.append(sec_account)
	root_vbox.add_child(sec_account["header"])
	root_vbox.add_child(sec_account["wrapper"])

	_account_vbox = sec_account["content"]
	_rebuild_account_section()

	root_vbox.add_child(_make_spacer(14))

	# ---------------------------------------------------------
	# SECTION 4: ADVANCED & DEVELOPER OPTIONS (COLLAPSED by default)
	# ---------------------------------------------------------
	var sec3 = _build_collapsible_section("ADVANCED & DEVELOPER OPTIONS", "DEV ONLY", false, true)
	_sections.append(sec3)
	root_vbox.add_child(sec3["header"])
	root_vbox.add_child(sec3["wrapper"])

	var sec3_vbox: VBoxContainer = sec3["content"]

	# Subtle intro note
	var dev_note := Label.new()
	dev_note.text = "Pose inference backend and hardware acceleration."
	dev_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev_note.add_theme_font_override("font", Tokens.FONT_SANS)
	dev_note.add_theme_font_size_override("font_size", 12)
	dev_note.add_theme_color_override("font_color", Tokens.DIM)
	sec3_vbox.add_child(dev_note)

	sec3_vbox.add_child(_make_spacer(16))

	# 3A. Hardware Acceleration
	var accel_lbl := _make_section_label("HARDWARE ACCELERATION")
	sec3_vbox.add_child(accel_lbl)

	sec3_vbox.add_child(_make_spacer(8))

	var toggle_panel := PanelContainer.new()
	toggle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toggle_sb := StyleBoxFlat.new()
	toggle_sb.bg_color = Color("#121215")
	toggle_sb.border_width_left = 1
	toggle_sb.border_width_top = 1
	toggle_sb.border_width_right = 1
	toggle_sb.border_width_bottom = 1
	toggle_sb.border_color = Tokens.LINE
	toggle_sb.corner_radius_top_left = 8
	toggle_sb.corner_radius_top_right = 8
	toggle_sb.corner_radius_bottom_left = 8
	toggle_sb.corner_radius_bottom_right = 8
	toggle_sb.content_margin_left = 4
	toggle_sb.content_margin_right = 4
	toggle_sb.content_margin_top = 4
	toggle_sb.content_margin_bottom = 4
	toggle_panel.add_theme_stylebox_override("panel", toggle_sb)
	sec3_vbox.add_child(toggle_panel)

	var toggle_hbox := HBoxContainer.new()
	toggle_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_hbox.add_theme_constant_override("separation", 4)
	toggle_panel.add_child(toggle_hbox)

	_accel_cpu_btn = Button.new()
	_accel_cpu_btn.text = "CPU"
	_accel_cpu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accel_cpu_btn.custom_minimum_size = Vector2(0, 44)
	_accel_cpu_btn.focus_mode = Control.FOCUS_NONE
	_accel_cpu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_accel_cpu_btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_accel_cpu_btn.add_theme_font_size_override("font_size", 22)
	_accel_cpu_btn.pressed.connect(_on_accel_selected.bind("CPU"))
	toggle_hbox.add_child(_accel_cpu_btn)

	_accel_gpu_btn = Button.new()
	_accel_gpu_btn.text = "GPU"
	_accel_gpu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accel_gpu_btn.custom_minimum_size = Vector2(0, 44)
	_accel_gpu_btn.focus_mode = Control.FOCUS_NONE
	_accel_gpu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_accel_gpu_btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	_accel_gpu_btn.add_theme_font_size_override("font_size", 22)
	_accel_gpu_btn.pressed.connect(_on_accel_selected.bind("GPU"))
	toggle_hbox.add_child(_accel_gpu_btn)

	sec3_vbox.add_child(_make_spacer(8))

	_accel_helper_lbl = Label.new()
	_accel_helper_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accel_helper_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accel_helper_lbl.add_theme_font_override("font", Tokens.FONT_SANS)
	_accel_helper_lbl.add_theme_font_size_override("font_size", 13)
	_accel_helper_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	sec3_vbox.add_child(_accel_helper_lbl)

	sec3_vbox.add_child(_make_spacer(12))

	root_vbox.add_child(_make_spacer(24))

	# Reset settings to default (outside of all collapsible sections)
	var reset_container := VBoxContainer.new()
	reset_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_container.add_theme_constant_override("separation", 6)

	var reset_btn := _make_outline_button("RESET ALL SETTINGS TO DEFAULT")
	reset_btn.pressed.connect(_on_reset_all_pressed)
	reset_container.add_child(reset_btn)

	var reset_hint := Label.new()
	reset_hint.text = "Restores gameplay, display, and camera preferences to defaults. Your profile, stats, and cloud data are not affected."
	reset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_hint.add_theme_font_override("font", Tokens.FONT_SANS)
	reset_hint.add_theme_font_size_override("font_size", 11)
	reset_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	reset_container.add_child(reset_hint)

	root_vbox.add_child(reset_container)

	# Bottom spacing for comfortable scrolling
	root_vbox.add_child(_make_spacer(48))

func _build_collapsible_section(title_text: String, tag_text: String, is_open: bool, is_dev: bool) -> Dictionary:
	var header_btn := Button.new()
	header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_btn.custom_minimum_size = Vector2(0, 50)
	header_btn.focus_mode = Control.FOCUS_NONE
	header_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var h_sb := StyleBoxFlat.new()
	h_sb.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	h_sb.border_width_left = 1
	h_sb.border_width_top = 1
	h_sb.border_width_right = 1
	h_sb.border_width_bottom = 1
	h_sb.border_color = Color(Tokens.FLAME.r, Tokens.FLAME.g, Tokens.FLAME.b, 0.4) if is_dev else Tokens.LINE
	h_sb.corner_radius_top_left = 8
	h_sb.corner_radius_top_right = 8
	h_sb.corner_radius_bottom_left = 8
	h_sb.corner_radius_bottom_right = 8

	var h_hover_sb := h_sb.duplicate() as StyleBoxFlat
	h_hover_sb.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	h_hover_sb.border_color = Tokens.FLAME if is_dev else Tokens.VOLT

	header_btn.add_theme_stylebox_override("normal", h_sb)
	header_btn.add_theme_stylebox_override("hover", h_hover_sb)
	header_btn.add_theme_stylebox_override("pressed", h_hover_sb)
	header_btn.add_theme_stylebox_override("focus", h_sb)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	header_btn.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var chevron_lbl := Label.new()
	chevron_lbl.text = "▼" if is_open else "▶"
	chevron_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	chevron_lbl.add_theme_font_size_override("font_size", 12)
	var accent_color: Color = Tokens.FLAME if is_dev else Tokens.VOLT
	chevron_lbl.add_theme_color_override("font_color", accent_color if is_open else Tokens.DIM)
	hbox.add_child(chevron_lbl)

	var title_lbl := Label.new()
	title_lbl.text = title_text.to_upper()
	title_lbl.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var tag_lbl := Label.new()
	tag_lbl.text = tag_text.to_upper()
	tag_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Tokens.FLAME if is_dev else Tokens.DIM)
	hbox.add_child(tag_lbl)

	# Content wrapper with padding
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_top", 10)
	content_margin.add_theme_constant_override("margin_bottom", 6)
	content_margin.add_theme_constant_override("margin_left", 2)
	content_margin.add_theme_constant_override("margin_right", 2)
	content_margin.visible = is_open

	# Content container
	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 6)
	content_margin.add_child(content_vbox)

	# Toggle handler
	var toggle_fn = func():
		content_margin.visible = not content_margin.visible
		chevron_lbl.text = "▼" if content_margin.visible else "▶"
		chevron_lbl.add_theme_color_override("font_color", accent_color if content_margin.visible else Tokens.DIM)

	header_btn.pressed.connect(toggle_fn)

	return {
		"header": header_btn,
		"content": content_vbox,
		"wrapper": content_margin,
		"toggle_func": toggle_fn
	}

## Red-outlined button for destructive actions (reset settings, delete account).
func _make_danger_button(text: String) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.text = text
	btn.add_theme_font_override("font", Tokens.FONT_MONO)
	btn.add_theme_font_size_override("font_size", 11)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.05, 0.05, 0.6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 0.5)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8

	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(Tokens.SIGNAL.r, Tokens.SIGNAL.g, Tokens.SIGNAL.b, 0.2)
	hover_sb.border_color = Tokens.SIGNAL

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	btn.add_theme_color_override("font_hover_color", Tokens.WHITE)
	return btn

## Neutral outlined button (same shape as the danger button, without the red).
func _make_outline_button(text: String) -> Button:
	var btn := _make_danger_button(text)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Tokens.LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.08)
	hover_sb.border_color = Tokens.VOLT
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", Tokens.WHITE)
	btn.add_theme_color_override("font_hover_color", Tokens.VOLT)
	return btn


## Current identity: hex badge, name and tag. Only built when a profile exists.
func _build_account_card() -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.04, 0.04, 0.06, 0.5)
	card_sb.border_width_left = 1
	card_sb.border_width_top = 1
	card_sb.border_width_right = 1
	card_sb.border_width_bottom = 1
	card_sb.border_color = Tokens.LINE
	card_sb.corner_radius_top_left = 8
	card_sb.corner_radius_top_right = 8
	card_sb.corner_radius_bottom_left = 8
	card_sb.corner_radius_bottom_right = 8
	card_sb.content_margin_top = 12
	card_sb.content_margin_bottom = 12
	card_sb.content_margin_left = 14
	card_sb.content_margin_right = 14
	card.add_theme_stylebox_override("panel", card_sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var player_name: String = Backend.profile.get("display_name", "")
	var badge = HexBadgeClass.new()
	badge.text = Tokens.initials(player_name)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = player_name.to_upper()
	name_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	col.add_child(name_lbl)

	var is_linked := Backend.is_google_linked()
	var tag_lbl := Label.new()
	tag_lbl.text = "#%s  ·  %s" % [
		Backend.profile.get("tag_number", "0000"),
		"GOOGLE LINKED" if is_linked else "ANONYMOUS ACCOUNT"
	]
	tag_lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Tokens.VOLT if is_linked else Tokens.DIM)
	col.add_child(tag_lbl)
	return card


func _rebuild_account_section() -> void:
	if not _account_vbox or not is_instance_valid(_account_vbox):
		return
	for c in _account_vbox.get_children():
		c.queue_free()

	if Backend.has_local_profile():
		_account_vbox.add_child(_build_account_card())
		_account_vbox.add_child(_make_spacer(12))

	# Google Account linking & status
	_account_vbox.add_child(_build_google_account_block())
	_account_vbox.add_child(_make_spacer(16))

	# Separator before Danger Zone
	var sep := ColorRect.new()
	sep.color = Color(Tokens.LINE.r, Tokens.LINE.g, Tokens.LINE.b, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	_account_vbox.add_child(sep)
	_account_vbox.add_child(_make_spacer(14))

	var account_note := Label.new()
	account_note.text = "Deleting your account permanently removes your profile, leaderboard scores and workout history. This can't be undone."
	account_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	account_note.add_theme_font_override("font", Tokens.FONT_SANS)
	account_note.add_theme_font_size_override("font_size", 12)
	account_note.add_theme_color_override("font_color", Tokens.DIM)
	_account_vbox.add_child(account_note)

	_account_vbox.add_child(_make_spacer(12))

	var delete_btn := _make_danger_button("DELETE ACCOUNT")
	delete_btn.pressed.connect(_on_delete_account_pressed)
	_account_vbox.add_child(delete_btn)


func _build_google_account_block() -> Control:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 8)

	var is_linked := Backend.is_google_linked()

	if is_linked:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.05, 0.6)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.4)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)
		panel.add_child(card_vbox)

		var status_tag := Label.new()
		status_tag.text = "GOOGLE ACCOUNT CONNECTED"
		status_tag.add_theme_font_override("font", Tokens.FONT_MONO)
		status_tag.add_theme_font_size_override("font_size", 10)
		status_tag.add_theme_color_override("font_color", Tokens.VOLT)
		card_vbox.add_child(status_tag)

		var email := Backend.get_linked_email()
		if email != "":
			var email_lbl := Label.new()
			email_lbl.text = email
			email_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
			email_lbl.add_theme_font_size_override("font_size", 13)
			email_lbl.add_theme_color_override("font_color", Tokens.WHITE)
			card_vbox.add_child(email_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = "Your profile and scores are preserved and synced across devices."
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_override("font", Tokens.FONT_SANS)
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		card_vbox.add_child(desc_lbl)

		container.add_child(panel)

		var unlink_btn := _make_outline_button("DISCONNECT GOOGLE ACCOUNT")
		unlink_btn.pressed.connect(_on_disconnect_google_pressed)
		container.add_child(unlink_btn)

		container.add_child(_make_spacer(4))

		var sign_out_btn := _make_outline_button("SIGN OUT")
		sign_out_btn.pressed.connect(_on_sign_out_pressed)
		container.add_child(sign_out_btn)

	else:
		var title_lbl := _make_section_label("GOOGLE ACCOUNT SYNC")
		container.add_child(title_lbl)

		var note_lbl := Label.new()
		note_lbl.text = "Connect a Google account to preserve your profile and sync leaderboard high scores across different devices."
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_lbl.add_theme_font_override("font", Tokens.FONT_SANS)
		note_lbl.add_theme_font_size_override("font_size", 12)
		note_lbl.add_theme_color_override("font_color", Tokens.DIM)
		container.add_child(note_lbl)

		container.add_child(_make_spacer(4))

		var connect_btn := _make_primary_outlined_button("CONNECT GOOGLE ACCOUNT")
		connect_btn.pressed.connect(_on_connect_google_pressed.bind(connect_btn))
		container.add_child(connect_btn)

		container.add_child(_make_spacer(4))

		var restore_btn := _make_outline_button("SIGN IN TO RESTORE EXISTING ACCOUNT")
		restore_btn.pressed.connect(_on_restore_account_pressed.bind(restore_btn))
		container.add_child(restore_btn)

		container.add_child(_make_spacer(4))

		var sign_out_btn := _make_outline_button("SIGN OUT")
		sign_out_btn.pressed.connect(_on_sign_out_pressed)
		container.add_child(sign_out_btn)

	return container


func _make_primary_outlined_button(text: String) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.text = text
	btn.add_theme_font_override("font", Tokens.FONT_MONO)
	btn.add_theme_font_size_override("font_size", 11)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.08)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Tokens.VOLT
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8

	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.18)

	var disabled_sb := sb.duplicate() as StyleBoxFlat
	disabled_sb.border_color = Tokens.LINE
	disabled_sb.bg_color = Color(0, 0, 0, 0)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_color_override("font_color", Tokens.WHITE)
	btn.add_theme_color_override("font_hover_color", Tokens.VOLT)
	btn.add_theme_color_override("font_disabled_color", Tokens.DIM)
	return btn


func _on_connect_google_pressed(btn: Button) -> void:
	if not FirebaseConfig.is_google_configured():
		_show_toast("GOOGLE CLIENT ID NOT CONFIGURED IN FIREBASECONFIG.GD", true)
		return

	btn.disabled = true
	btn.text = "CONNECTING TO GOOGLE…"

	var auth_res := await GoogleAuth.authenticate(self)
	if not is_instance_valid(btn):
		return

	if not auth_res.get("ok", false):
		btn.disabled = false
		btn.text = "CONNECT GOOGLE ACCOUNT"
		var err_msg: String = auth_res.get("message", "Failed to connect Google account.")
		_show_toast(err_msg.to_upper(), true)
		return

	var id_token: String = auth_res.get("id_token", "")
	var access_token: String = auth_res.get("access_token", "")

	btn.text = "LINKING ACCOUNT…"
	var link_res := await Backend.link_google_account(id_token, access_token)
	if not is_instance_valid(btn):
		return

	if link_res.get("ok", false):
		_show_toast("GOOGLE ACCOUNT LINKED SUCCESSFULLY")
		_rebuild_account_section()
	else:
		btn.disabled = false
		btn.text = "CONNECT GOOGLE ACCOUNT"
		if link_res.get("error", "") == "already_linked_other":
			_prompt_switch_account(id_token, access_token)
		else:
			var link_err: String = link_res.get("message", "Could not link account.")
			_show_toast(link_err.to_upper(), true)


func _prompt_switch_account(id_token: String, access_token: String) -> void:
	if not _account_vbox or not is_instance_valid(_account_vbox):
		return

	var prompt_panel := PanelContainer.new()
	prompt_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.04, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Tokens.FLAME
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	prompt_panel.add_theme_stylebox_override("panel", sb)

	var pvbox := VBoxContainer.new()
	pvbox.add_theme_constant_override("separation", 8)
	prompt_panel.add_child(pvbox)

	var ptitle := Label.new()
	ptitle.text = "EXISTING ACCOUNT FOUND"
	ptitle.add_theme_font_override("font", Tokens.FONT_MONO)
	ptitle.add_theme_font_size_override("font_size", 10)
	ptitle.add_theme_color_override("font_color", Tokens.FLAME)
	pvbox.add_child(ptitle)

	var pnote := Label.new()
	pnote.text = "This Google account already has a saved FitArcade profile. Would you like to switch to that account on this device?"
	pnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pnote.add_theme_font_override("font", Tokens.FONT_SANS)
	pnote.add_theme_font_size_override("font_size", 12)
	pnote.add_theme_color_override("font_color", Tokens.WHITE)
	pvbox.add_child(pnote)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pvbox.add_child(row)

	var switch_btn := _make_primary_outlined_button("SWITCH ACCOUNT")
	switch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switch_btn.pressed.connect(func():
		switch_btn.disabled = true
		switch_btn.text = "SWITCHING…"
		var switch_res = await Backend.sign_in_with_google(id_token, access_token)
		if switch_res.get("ok", false):
			_show_toast("SWITCHED TO EXISTING ACCOUNT")
			get_tree().change_scene_to_file("res://Main.tscn")
		else:
			switch_btn.disabled = false
			switch_btn.text = "SWITCH ACCOUNT"
			_show_toast("FAILED TO SWITCH ACCOUNT", true)
	)
	row.add_child(switch_btn)

	var cancel_btn := _make_outline_button("CANCEL")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_rebuild_account_section)
	row.add_child(cancel_btn)

	_account_vbox.add_child(prompt_panel)
	if _account_vbox.get_child_count() > 2:
		_account_vbox.move_child(prompt_panel, 2)


func _on_restore_account_pressed(btn: Button) -> void:
	if not FirebaseConfig.is_google_configured():
		_show_toast("GOOGLE CLIENT ID NOT CONFIGURED IN FIREBASECONFIG.GD", true)
		return

	btn.disabled = true
	btn.text = "SIGNING IN…"

	var auth_res := await GoogleAuth.authenticate(self)
	if not is_instance_valid(btn):
		return

	if not auth_res.get("ok", false):
		btn.disabled = false
		btn.text = "SIGN IN TO RESTORE EXISTING ACCOUNT"
		var err_msg: String = auth_res.get("message", "Failed to connect Google account.")
		_show_toast(err_msg.to_upper(), true)
		return

	var id_token: String = auth_res.get("id_token", "")
	var access_token: String = auth_res.get("access_token", "")

	btn.text = "RESTORING…"
	var signin_res := await Backend.sign_in_with_google(id_token, access_token)
	if not is_instance_valid(btn):
		return

	if signin_res.get("ok", false):
		_show_toast("ACCOUNT RESTORED SUCCESSFULLY")
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file("res://Main.tscn")
	else:
		btn.disabled = false
		btn.text = "SIGN IN TO RESTORE EXISTING ACCOUNT"
		var err: String = signin_res.get("message", "Failed to restore account.")
		_show_toast(err.to_upper(), true)


func _on_disconnect_google_pressed() -> void:
	var res := await Backend.unlink_google_account()
	if res.get("ok", false):
		_show_toast("GOOGLE ACCOUNT DISCONNECTED", false)
		_rebuild_account_section()
	else:
		_show_toast("COULD NOT DISCONNECT GOOGLE ACCOUNT", true)

func _on_sign_out_pressed() -> void:
	if _sign_out_overlay and is_instance_valid(_sign_out_overlay):
		return
	_sign_out_overlay = SignOutOverlayClass.new(Backend.is_google_linked())
	_sign_out_overlay.confirmed.connect(_on_sign_out_confirmed)
	_sign_out_overlay.cancelled.connect(_close_sign_out_overlay)
	_sign_out_overlay.connect_google_requested.connect(func():
		_close_sign_out_overlay()
		var connect_btn := _find_button_by_text(_account_vbox, "CONNECT GOOGLE ACCOUNT")
		if connect_btn:
			_on_connect_google_pressed(connect_btn)
	)
	add_child(_sign_out_overlay)

func _close_sign_out_overlay() -> void:
	if _sign_out_overlay and is_instance_valid(_sign_out_overlay):
		_sign_out_overlay.queue_free()
	_sign_out_overlay = null

func _on_sign_out_confirmed() -> void:
	if _sign_out_overlay and is_instance_valid(_sign_out_overlay):
		_sign_out_overlay.set_busy(true)
	if not Backend.is_google_linked():
		var del_res: Dictionary = await Backend.delete_account()
		if not del_res.get("ok", false):
			push_warning("Unlinked sign out: remote delete failed (%s), clearing locally" % del_res.get("error", ""))
			Backend.sign_out()
	else:
		Backend.sign_out()
	SessionManager.clear_local_data()
	get_tree().change_scene_to_file("res://Main.tscn")

func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found:
			return found
	return null

func _on_delete_account_pressed() -> void:
	if _delete_overlay and is_instance_valid(_delete_overlay):
		return
	_delete_overlay = DeleteAccountOverlayClass.new()
	_delete_overlay.confirmed.connect(_on_delete_confirmed)
	_delete_overlay.cancelled.connect(_close_delete_overlay)
	add_child(_delete_overlay)

func _close_delete_overlay() -> void:
	if _delete_overlay and is_instance_valid(_delete_overlay):
		_delete_overlay.queue_free()
	_delete_overlay = null

func _on_delete_confirmed() -> void:
	var overlay := _delete_overlay
	overlay.set_busy(true)
	var result: Dictionary = await Backend.delete_account()
	if not is_instance_valid(overlay):
		return
	if result.get("ok", false):
		SessionManager.clear_local_data()
		# No profile left, so Main starts at onboarding again
		get_tree().change_scene_to_file("res://Main.tscn")
	else:
		overlay.set_busy(false)
		overlay.show_error(result.get("error", "server"))

func toggle_section(index: int) -> void:
	if index >= 0 and index < _sections.size():
		_sections[index]["toggle_func"].call()

func _build_toggle_row(key: String, title: String, desc: String, initial_val: bool, on_change: Callable, is_last: bool = false) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var r_sb := StyleBoxFlat.new()
	r_sb.bg_color = Color(0.04, 0.04, 0.06, 0.45)
	if not is_last:
		r_sb.border_width_bottom = 1
		r_sb.border_color = Color(Tokens.LINE.r, Tokens.LINE.g, Tokens.LINE.b, 0.45)
	r_sb.content_margin_top = 12
	r_sb.content_margin_bottom = 12
	r_sb.content_margin_left = 12
	r_sb.content_margin_right = 12
	r_sb.corner_radius_top_left = 6
	r_sb.corner_radius_top_right = 6
	r_sb.corner_radius_bottom_left = 6
	r_sb.corner_radius_bottom_right = 6
	row_panel.add_theme_stylebox_override("panel", r_sb)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 16)
	row_panel.add_child(hbox)

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.add_theme_font_override("font", Tokens.FONT_SANS_BOLD)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Tokens.WHITE)
	text_vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_override("font", Tokens.FONT_SANS)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	text_vbox.add_child(desc_lbl)

	var toggle := ToggleSwitch.new(initial_val)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled_state.connect(on_change)
	hbox.add_child(toggle)

	# Tapping anywhere on the row flips the toggle: on a completed TAP, never on touch-down
	var tap := TapTracker.new()
	row_panel.gui_input.connect(func(event: InputEvent):
		if tap.tapped(event):
			toggle.is_on = not toggle.is_on
			toggle.toggled_state.emit(toggle.is_on)
	)

	_toggles[key] = toggle

	return row_panel

func _make_spacer(height: int) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	return sp

func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Tokens.FONT_MONO)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Tokens.DIM)
	return lbl

func _on_accel_selected(mode: String) -> void:
	# GPU can't be picked on a device that has no hardware acceleration
	if mode == "GPU" and not Settings.hardware_accel_available():
		return
	Settings.set_accel(mode)
	_update_accel_ui()

## Shows the *effective* choice (preference limited by what the device supports), so the
## toggle can never claim GPU while inference is actually running on the CPU.
func _update_accel_ui() -> void:
	var available := Settings.hardware_accel_available()
	var is_gpu := Settings.use_hardware_accel()

	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Tokens.VOLT
	active_sb.corner_radius_top_left = 6
	active_sb.corner_radius_top_right = 6
	active_sb.corner_radius_bottom_left = 6
	active_sb.corner_radius_bottom_right = 6
	active_sb.content_margin_top = 8
	active_sb.content_margin_bottom = 8

	var inactive_sb := StyleBoxFlat.new()
	inactive_sb.bg_color = Color(0, 0, 0, 0)
	inactive_sb.content_margin_top = 8
	inactive_sb.content_margin_bottom = 8

	_style_accel_button(_accel_gpu_btn, is_gpu, active_sb, inactive_sb)
	_style_accel_button(_accel_cpu_btn, not is_gpu, active_sb, inactive_sb)
	_accel_gpu_btn.disabled = not available
	_accel_gpu_btn.add_theme_color_override("font_disabled_color", Color(Tokens.DIM.r, Tokens.DIM.g, Tokens.DIM.b, 0.35))
	_accel_gpu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW

	if not available:
		_accel_helper_lbl.text = "Hardware acceleration isn't available on this device, so pose inference runs on the CPU."
	elif is_gpu:
		_accel_helper_lbl.text = "Faster pose inference using the phone's neural hardware. Uses more battery."
	else:
		_accel_helper_lbl.text = "Most compatible. Expect higher latency on older phones."

func _style_accel_button(btn: Button, active: bool, active_sb: StyleBoxFlat, inactive_sb: StyleBoxFlat) -> void:
	var sb := active_sb if active else inactive_sb
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	var rest: Color = Tokens.INK if active else Tokens.DIM
	var hover: Color = Tokens.INK if active else Tokens.WHITE
	btn.add_theme_color_override("font_color", rest)
	btn.add_theme_color_override("font_hover_color", hover)
	btn.add_theme_color_override("font_pressed_color", hover)

func _on_reset_all_pressed() -> void:
	Settings.reset_to_defaults()

	# Update all toggle switches
	if _toggles.has("skip_calibration"): _toggles["skip_calibration"].is_on = Settings.skip_calibration
	if _toggles.has("sound_enabled"): _toggles["sound_enabled"].is_on = Settings.sound_enabled
	if _toggles.has("show_skeleton"): _toggles["show_skeleton"].is_on = Settings.show_skeleton
	if _toggles.has("haptics_enabled"): _toggles["haptics_enabled"].is_on = Settings.haptics_enabled
	if _toggles.has("show_debug_info"): _toggles["show_debug_info"].is_on = Settings.show_debug_info
	if _toggles.has("mirror_camera"): _toggles["mirror_camera"].is_on = Settings.mirror_camera
	if _toggles.has("high_contrast_hud"): _toggles["high_contrast_hud"].is_on = Settings.high_contrast_hud

	# Update hardware acceleration
	_update_accel_ui()

	# Show feedback banner
	_show_toast("ALL SETTINGS RESTORED TO FACTORY DEFAULTS")


func _show_toast(msg: String, is_error: bool = false) -> void:
	if not _toast_label or not is_instance_valid(_toast_label):
		return
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", Tokens.SIGNAL if is_error else Tokens.VOLT)
	_toast_label.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.5)
	_toast_tween.tween_callback(func():
		if is_instance_valid(_toast_label):
			_toast_label.visible = false
	)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
