extends Control

## Full-screen confirmation for deleting the account (Settings > Account).
##
## The design spec has no dialogs ("There are no dialogs, sheets or popups"), so
## this follows the pattern of the Paused overlay instead: a full-screen modal
## over the striped ink backdrop that swallows taps, big Anton title, and a
## stacked primary/secondary button pair. `signal` marks the destructive state.

signal confirmed
signal cancelled

const StripedBackdropClass = preload("res://ui/components/StripedBackdrop.gd")

const ERROR_TEXT := {
	"network": "COULDN'T REACH THE SERVER. CHECK YOUR CONNECTION AND TRY AGAIN — IT'S SAFE TO RETRY.",
	"permission": "THE SERVER REFUSED THE REQUEST. IF THIS KEEPS HAPPENING, CONTACT SUPPORT.",
	"auth": "COULDN'T VERIFY YOUR ACCOUNT. TRY AGAIN.",
	"server": "SOMETHING WENT WRONG ON OUR END. TRY AGAIN.",
}

var _error_lbl: Label
var _delete_btn: Button
var _keep_btn: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Above the settings content, and swallow every tap behind it
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not _delete_btn.disabled:
		cancelled.emit()
		get_viewport().set_input_as_handled()

## Locks the buttons while the deletion request is in flight.
func set_busy(busy: bool) -> void:
	_delete_btn.disabled = busy
	_keep_btn.disabled = busy
	_delete_btn.text = "DELETING…" if busy else "DELETE FOREVER"
	if busy:
		_error_lbl.text = ""

func show_error(code: String) -> void:
	_error_lbl.text = ERROR_TEXT.get(code, ERROR_TEXT["server"])

func _build_ui() -> void:
	# Fully opaque: this is a text-heavy warning, and the Settings content behind it
	# would otherwise ghost through the copy.
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

	vbox.add_child(_label("● DANGER ZONE", Tokens.FONT_MONO, 10, Tokens.SIGNAL))
	vbox.add_child(_spacer(6))
	vbox.add_child(Tokens.tight_display_label("DELETE", 56, Tokens.WHITE).get_parent())
	vbox.add_child(_spacer(4))
	vbox.add_child(Tokens.tight_display_label("ACCOUNT?", 56, Tokens.SIGNAL).get_parent())

	vbox.add_child(_spacer(16))

	var lead := _label("This permanently removes:", Tokens.FONT_SANS, 14, Color(1, 1, 1, 0.6))
	vbox.add_child(lead)
	vbox.add_child(_spacer(8))

	# Each row is a StatCell-style 1px `line` top border + content
	vbox.add_child(_loss_row("Your profile and display name"))
	vbox.add_child(_loss_row("Your leaderboard scores and score history"))
	vbox.add_child(_loss_row("Workout history stored on this device"))

	vbox.add_child(_spacer(16))
	vbox.add_child(_label("This can't be undone.", Tokens.FONT_SANS_BOLD, 14, Tokens.WHITE))

	var expand := Control.new()
	expand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expand.custom_minimum_size = Vector2(0, 20)
	expand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(expand)

	# Reserved two-line slot so an error doesn't shift the buttons
	_error_lbl = _label("", Tokens.FONT_MONO, 10, Tokens.SIGNAL)
	_error_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_lbl.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(_error_lbl)

	vbox.add_child(_spacer(8))

	# Primary (destructive): `signal` fill, white display text
	_delete_btn = _make_button("DELETE FOREVER", 24, 56, Tokens.SIGNAL, Tokens.SIGNAL, Tokens.WHITE)
	_delete_btn.pressed.connect(func(): confirmed.emit())
	vbox.add_child(_delete_btn)

	vbox.add_child(_spacer(12))

	# Secondary: 1px white@0.4 border (same as the Paused "End workout" button)
	_keep_btn = _make_button("KEEP MY ACCOUNT", 20, 48, Color(0, 0, 0, 0), Color(1, 1, 1, 0.4), Tokens.WHITE)
	_keep_btn.pressed.connect(func(): cancelled.emit())
	vbox.add_child(_keep_btn)

func _loss_row(text: String) -> Control:
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
	row.add_child(_label("✕", Tokens.FONT_MONO, 12, Tokens.SIGNAL))
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
