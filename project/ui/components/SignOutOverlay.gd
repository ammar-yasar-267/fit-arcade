extends Control

## Full-screen confirmation for signing out of the account (Settings > Account).
##
## Over the striped ink backdrop that swallows taps, big Anton title, and a
## stacked primary/secondary button pair. Handles both Google-linked and unlinked accounts.

signal confirmed
signal cancelled
signal connect_google_requested

const StripedBackdropClass = preload("res://ui/components/StripedBackdrop.gd")

var _is_linked: bool = false
var _sign_out_btn: Button
var _cancel_btn: Button
var _connect_btn: Button

func _init(is_linked: bool = false) -> void:
	_is_linked = is_linked
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and is_instance_valid(_sign_out_btn) and not _sign_out_btn.disabled:
		cancelled.emit()
		get_viewport().set_input_as_handled()

func set_busy(busy: bool) -> void:
	if is_instance_valid(_sign_out_btn):
		_sign_out_btn.disabled = busy
		_sign_out_btn.text = "DELETING…" if (busy and not _is_linked) else ("SIGNING OUT…" if busy else ("SIGN OUT" if _is_linked else "DELETE & SIGN OUT"))
	if is_instance_valid(_cancel_btn):
		_cancel_btn.disabled = busy
	if is_instance_valid(_connect_btn):
		_connect_btn.disabled = busy

func _build_ui() -> void:
	add_child(StripedBackdropClass.new(1.0, true))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", Tokens.SAFE_TOP_OFFSET)
	margin.add_theme_constant_override("margin_left", Tokens.SCREEN_PADDING_LEFT)
	margin.add_theme_constant_override("margin_right", Tokens.SCREEN_PADDING_RIGHT)
	margin.add_theme_constant_override("margin_bottom", Tokens.SCREEN_PADDING_BOTTOM)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	margin.add_child(vbox)

	if _is_linked:
		vbox.add_child(_label("● ACCOUNT SESSION", Tokens.FONT_MONO, 10, Tokens.VOLT))
		vbox.add_child(_spacer(6))
		vbox.add_child(Tokens.tight_display_label("SIGN OUT", 56, Tokens.WHITE).get_parent())
		vbox.add_child(_spacer(4))
		vbox.add_child(Tokens.tight_display_label("OF ACCOUNT?", 56, Tokens.VOLT).get_parent())

		vbox.add_child(_spacer(16))
		var lead := _label("Your cloud data stays completely safe:", Tokens.FONT_SANS, 14, Color(1, 1, 1, 0.6))
		vbox.add_child(lead)
		vbox.add_child(_spacer(8))

		vbox.add_child(_info_row("Profile and display name are preserved in the cloud", Tokens.VOLT))
		vbox.add_child(_info_row("Leaderboard high scores and stats remain intact", Tokens.VOLT))
		vbox.add_child(_info_row("Restore anytime by signing in with Google again", Tokens.VOLT))

		vbox.add_child(_spacer(16))
		vbox.add_child(_label("This clears the active session on this device.", Tokens.FONT_SANS_BOLD, 14, Tokens.WHITE))

		var expand := Control.new()
		expand.size_flags_vertical = Control.SIZE_EXPAND_FILL
		expand.custom_minimum_size = Vector2(0, 20)
		expand.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(expand)

		# Primary: Volt fill with ink text
		_sign_out_btn = _make_button("SIGN OUT", 24, 56, Tokens.VOLT, Tokens.VOLT, Tokens.INK)
		_sign_out_btn.pressed.connect(func(): confirmed.emit())
		vbox.add_child(_sign_out_btn)

		vbox.add_child(_spacer(12))

		# Secondary: 1px white@0.4 border
		_cancel_btn = _make_button("STAY SIGNED IN", 20, 48, Color(0, 0, 0, 0), Color(1, 1, 1, 0.4), Tokens.WHITE)
		_cancel_btn.pressed.connect(func(): cancelled.emit())
		vbox.add_child(_cancel_btn)

	else:
		vbox.add_child(_label("● UNLINKED PROFILE", Tokens.FONT_MONO, 10, Tokens.FLAME))
		vbox.add_child(_spacer(6))
		vbox.add_child(Tokens.tight_display_label("WARNING:", 56, Tokens.WHITE).get_parent())
		vbox.add_child(_spacer(4))
		vbox.add_child(Tokens.tight_display_label("WILL DELETE", 56, Tokens.FLAME).get_parent())

		vbox.add_child(_spacer(16))
		var lead := _label("This profile is not connected to a Google account:", Tokens.FONT_SANS, 14, Color(1, 1, 1, 0.6))
		vbox.add_child(lead)
		vbox.add_child(_spacer(8))

		vbox.add_child(_info_row("Unlinked guest profile and scores will be permanently deleted", Tokens.SIGNAL))
		vbox.add_child(_info_row("Connect a Google account first to preserve your progress", Tokens.VOLT))

		vbox.add_child(_spacer(16))
		vbox.add_child(_label("Signing out will delete this unlinked account permanently.", Tokens.FONT_SANS_BOLD, 14, Tokens.WHITE))

		var expand := Control.new()
		expand.size_flags_vertical = Control.SIZE_EXPAND_FILL
		expand.custom_minimum_size = Vector2(0, 20)
		expand.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(expand)

		# Connect Google button
		_connect_btn = _make_button("CONNECT GOOGLE FIRST", 22, 54, Tokens.VOLT, Tokens.VOLT, Tokens.INK)
		_connect_btn.pressed.connect(func(): connect_google_requested.emit())
		vbox.add_child(_connect_btn)

		vbox.add_child(_spacer(10))

		# Delete and sign out (destructive outline)
		_sign_out_btn = _make_button("DELETE & SIGN OUT", 20, 48, Color(0, 0, 0, 0), Tokens.FLAME, Tokens.FLAME)
		_sign_out_btn.pressed.connect(func(): confirmed.emit())
		vbox.add_child(_sign_out_btn)

		vbox.add_child(_spacer(10))

		# Cancel
		_cancel_btn = _make_button("CANCEL", 18, 44, Color(0, 0, 0, 0), Color(1, 1, 1, 0.4), Tokens.WHITE)
		_cancel_btn.pressed.connect(func(): cancelled.emit())
		vbox.add_child(_cancel_btn)

func _info_row(text: String, bullet_color: Color) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_top = 1
	sb.border_color = Tokens.LINE
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(_label("●", Tokens.FONT_MONO, 10, bullet_color))
	var lbl := _label(text, Tokens.FONT_SANS, 14, Tokens.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	return panel

func _make_button(text: String, font_size: int, height: int, fill: Color, border: Color, font_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, height)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	btn.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(key, font_color)
	btn.add_theme_color_override("font_disabled_color", Color(font_color.r, font_color.g, font_color.b, 0.45))

	var normal := Tokens.make_panel_style(fill, border, 1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.1) if fill.a > 0.0 else Color(1, 1, 1, 0.08)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(fill.r, fill.g, fill.b, fill.a * 0.5)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("disabled", disabled)
	return btn

func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _spacer(h: int) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp
