extends Control

## First-run onboarding: asks the player for a display name.
## Shown by Main whenever there is no local profile (first launch, or after the
## account was deleted from Settings).
##
## The design spec has no onboarding screen ("not present in the prototype"), so
## this is built strictly from its tokens and components: ink background and
## stripe texture, 64/20/20/20 screen padding, Anton headings, mono labels, 0
## radius, 1px `line` borders, `volt` for focus/primary, `signal` for errors.

signal completed
## Only emitted in replay mode (see below), where the player can back out.
signal cancelled

const TouchScrollClass = preload("res://ui/components/TouchScroll.gd")
const StripedBackdropClass = preload("res://ui/components/StripedBackdrop.gd")
const HexBadgeClass = preload("res://ui/components/HexBadge.gd")
const IconButtonClass = preload("res://ui/components/IconButton.gd")

## Set before adding to the tree. Replay mode is the Settings > "Replay onboarding"
## test tool: the existing profile is left untouched until a new name is saved
## (which updates the same profile under the same login, so it never creates
## another account), the field starts prefilled, and a back button cancels.
var replay_mode: bool = false

const DEFAULT_HINT := "3–16 CHARACTERS  ·  LETTERS, NUMBERS, SPACES"
const ALLOWED_HINT := "LETTERS, NUMBERS, SPACE, _ - . ONLY"

var _margin: MarginContainer
var _input: LineEdit
var _counter_lbl: Label
var _hint_lbl: Label
var _preview_badge: Control
var _preview_name_lbl: Label
var _continue_btn: Button
var _google_btn: Button

var _busy: bool = false
var _last_keyboard_px: int = 0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	if replay_mode:
		_input.text = Backend.profile.get("display_name", "")
		_input.caret_column = _input.text.length()
	_refresh()
	# Straight into typing: the name is the only thing on this screen.
	_input.grab_focus.call_deferred()

func _process(_delta: float) -> void:
	# Lift the layout above the on-screen keyboard (no-op on desktop, height 0).
	var kb_px := DisplayServer.virtual_keyboard_get_height()
	if kb_px == _last_keyboard_px:
		return
	_last_keyboard_px = kb_px
	var to_viewport := get_viewport_rect().size.y / maxf(1.0, float(DisplayServer.window_get_size().y))
	_margin.add_theme_constant_override("margin_bottom", maxi(Tokens.SCREEN_PADDING_BOTTOM, int(kb_px * to_viewport) + 8))

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	add_child(StripedBackdropClass.new(1.0, false))

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_top", Tokens.SAFE_TOP_OFFSET)
	_margin.add_theme_constant_override("margin_left", Tokens.SCREEN_PADDING_LEFT)
	_margin.add_theme_constant_override("margin_right", Tokens.SCREEN_PADDING_RIGHT)
	_margin.add_theme_constant_override("margin_bottom", Tokens.SCREEN_PADDING_BOTTOM)
	add_child(_margin)

	# Scrolls when the on-screen keyboard leaves too little room
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_margin.add_child(scroll)
	TouchScrollClass.apply(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)

	# --- Wordmark + hairline ---
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 12)
	vbox.add_child(brand)
	if replay_mode:
		var back_btn := IconButtonClass.new()
		back_btn.icon_type = "back"
		back_btn.is_back_button = true
		back_btn.pressed.connect(func(): cancelled.emit())
		brand.add_child(back_btn)
	# "FIT" + "ARCADE" read as one word, so they sit in their own zero-gap group; the
	# 12px row spacing only separates the wordmark from the back button and the hairline.
	var wordmark := HBoxContainer.new()
	wordmark.add_theme_constant_override("separation", 0)
	wordmark.add_child(_label("FIT", Tokens.FONT_DISPLAY, 20, Tokens.WHITE))
	wordmark.add_child(_label("ARCADE", Tokens.FONT_DISPLAY, 20, Tokens.VOLT))
	brand.add_child(wordmark)
	var rule := ColorRect.new()
	rule.color = Tokens.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(rule)

	vbox.add_child(_spacer(32))

	# --- Kicker + headline (same pattern as the Summary screen) ---
	vbox.add_child(_label("REPLAY  /  PLAYER SETUP" if replay_mode else "WELCOME  /  PLAYER SETUP", Tokens.FONT_MONO, 10, Tokens.VOLT))
	vbox.add_child(_spacer(6))
	vbox.add_child(Tokens.tight_display_label("WHO'S", 56, Tokens.WHITE).get_parent())
	vbox.add_child(_spacer(4))
	vbox.add_child(Tokens.tight_display_label("PLAYING?", 56, Tokens.VOLT).get_parent())

	vbox.add_child(_spacer(16))

	var intro := _label("Pick the name other players see on the leaderboard. No email, no password — just a name.", Tokens.FONT_SANS, 14, Color(1, 1, 1, 0.6))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	vbox.add_child(_spacer(28))

	# --- Field: caption row, input, hint ---
	var caption_row := HBoxContainer.new()
	vbox.add_child(caption_row)
	var caption := _label("DISPLAY NAME", Tokens.FONT_MONO, 10, Tokens.DIM)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_row.add_child(caption)
	_counter_lbl = _label("0/%d" % Backend.DISPLAY_NAME_MAX, Tokens.FONT_MONO, 10, Tokens.DIM)
	_counter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption_row.add_child(_counter_lbl)

	vbox.add_child(_spacer(8))

	_input = _build_input()
	vbox.add_child(_input)

	vbox.add_child(_spacer(8))

	# Fixed height (two lines) so showing an error doesn't shove the layout down
	_hint_lbl = _label(DEFAULT_HINT, Tokens.FONT_MONO, 10, Tokens.DIM)
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(_hint_lbl)

	vbox.add_child(_spacer(12))

	# --- Preview: how the name will look on the leaderboard (Banner "else" variant) ---
	vbox.add_child(_build_preview())

	# Expanding spacer pins the action block to the bottom
	var expand := Control.new()
	expand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expand.custom_minimum_size = Vector2(0, 20)
	expand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(expand)

	# --- Primary action ---
	_continue_btn = _build_primary_button()
	vbox.add_child(_continue_btn)

	if not replay_mode:
		vbox.add_child(_spacer(10))

		var or_row := HBoxContainer.new()
		or_row.add_theme_constant_override("separation", 10)

		var line_l := ColorRect.new()
		line_l.color = Color(Tokens.LINE.r, Tokens.LINE.g, Tokens.LINE.b, 0.5)
		line_l.custom_minimum_size = Vector2(0, 1)
		line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		or_row.add_child(line_l)

		var or_lbl := _label("OR", Tokens.FONT_MONO, 10, Tokens.DIM)
		or_row.add_child(or_lbl)

		var line_r := ColorRect.new()
		line_r.color = Color(Tokens.LINE.r, Tokens.LINE.g, Tokens.LINE.b, 0.5)
		line_r.custom_minimum_size = Vector2(0, 1)
		line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		or_row.add_child(line_r)

		vbox.add_child(or_row)
		vbox.add_child(_spacer(10))

		_google_btn = _build_secondary_button("SIGN IN WITH GOOGLE")
		_google_btn.pressed.connect(_on_google_sign_in_pressed)
		vbox.add_child(_google_btn)

	vbox.add_child(_spacer(12))

	var footnote := _label("ANONYMOUS ACCOUNT  ·  DELETE IT ANYTIME IN SETTINGS", Tokens.FONT_MONO, 9, Tokens.DIM)
	footnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(footnote)

	vbox.add_child(_spacer(6))

	var link_hint := _label("You can optionally link a Google account in Settings later to preserve your account across different devices.", Tokens.FONT_SANS, 11, Color(1, 1, 1, 0.45))
	link_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	link_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(link_hint)

func _build_input() -> LineEdit:
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(0, 64)
	le.max_length = Backend.DISPLAY_NAME_MAX
	le.placeholder_text = "KAI VEGA"
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	le.context_menu_enabled = false
	le.caret_blink = true
	le.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	le.add_theme_font_size_override("font_size", 30)
	le.add_theme_color_override("font_color", Tokens.WHITE)
	le.add_theme_color_override("font_placeholder_color", Color(Tokens.DIM.r, Tokens.DIM.g, Tokens.DIM.b, 0.45))
	le.add_theme_color_override("caret_color", Tokens.VOLT)
	le.add_theme_color_override("selection_color", Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.3))
	le.add_theme_color_override("font_uneditable_color", Tokens.DIM)

	# `panel` surface, 1px `line` border, 0 radius; border goes `volt` on focus
	# (same state change as the spec's IconButton hover/focus).
	var normal := Tokens.make_panel_style(Tokens.PANEL, Tokens.LINE, 1)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Tokens.VOLT
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focused)
	le.add_theme_stylebox_override("read_only", normal)

	le.text_changed.connect(_on_text_changed)
	le.text_submitted.connect(func(_t: String): _submit())
	return le

func _build_preview() -> Control:
	var panel := PanelContainer.new()
	var sb := Tokens.make_panel_style(Color(1, 1, 1, 0.03), Tokens.LINE, 1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	_preview_badge = HexBadgeClass.new()
	_preview_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_preview_badge)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)

	_preview_name_lbl = Tokens.tight_display_label("YOUR NAME", 20, Tokens.WHITE)
	col.add_child(_preview_name_lbl.get_parent())
	col.add_child(_label("HOW YOU'LL APPEAR ON THE LEADERBOARD", Tokens.FONT_MONO, 10, Tokens.DIM))
	return panel

func _build_primary_button() -> Button:
	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.custom_minimum_size = Vector2(0, 56)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	btn.add_theme_font_size_override("font_size", 28)

	var active := Tokens.make_panel_style(Tokens.VOLT, Tokens.VOLT, 0)
	var pressed := Tokens.make_panel_style(Tokens.VOLT.darkened(0.15), Tokens.VOLT, 0)
	# Disabled = the spec's "locked" fill (`line`) with `dim` text
	var locked := Tokens.make_panel_style(Tokens.LINE, Tokens.LINE, 0)
	btn.add_theme_stylebox_override("normal", active)
	btn.add_theme_stylebox_override("hover", active)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", locked)
	btn.add_theme_color_override("font_color", Tokens.INK)
	btn.add_theme_color_override("font_hover_color", Tokens.INK)
	btn.add_theme_color_override("font_pressed_color", Tokens.INK)
	btn.add_theme_color_override("font_disabled_color", Tokens.DIM)
	btn.pressed.connect(_submit)
	return btn

func _build_secondary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 50)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", Tokens.FONT_DISPLAY)
	btn.add_theme_font_size_override("font_size", 22)

	var normal := Tokens.make_panel_style(Color(Tokens.PANEL.r, Tokens.PANEL.g, Tokens.PANEL.b, 0.7), Tokens.LINE, 1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Tokens.VOLT
	hover.bg_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.08)

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(Tokens.VOLT.r, Tokens.VOLT.g, Tokens.VOLT.b, 0.16)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = Tokens.LINE
	disabled.bg_color = Color(0, 0, 0, 0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", Tokens.WHITE)
	btn.add_theme_color_override("font_hover_color", Tokens.VOLT)
	btn.add_theme_color_override("font_pressed_color", Tokens.VOLT)
	btn.add_theme_color_override("font_disabled_color", Tokens.DIM)
	return btn

# -----------------------------------------------------------------------------
# Behaviour
# -----------------------------------------------------------------------------
func _on_text_changed(new_text: String) -> void:
	var cleaned := _strip_disallowed(new_text)
	if cleaned != new_text:
		# Keep the caret where the player was typing, minus the dropped characters
		var caret := maxi(0, _input.caret_column - (new_text.length() - cleaned.length()))
		_input.text = cleaned
		_input.caret_column = caret
		_set_hint(ALLOWED_HINT, true)
	else:
		_set_hint(DEFAULT_HINT, false)
	_refresh()

static func _strip_disallowed(text: String) -> String:
	var disallowed := RegEx.new()
	disallowed.compile("[^A-Za-z0-9 _.\\-]")
	return disallowed.sub(text, "", true)

func _set_hint(text: String, is_error: bool) -> void:
	_hint_lbl.text = text
	_hint_lbl.add_theme_color_override("font_color", Tokens.SIGNAL if is_error else Tokens.DIM)

## Syncs the counter, preview and button with the current text.
func _refresh() -> void:
	var cleaned: String = Backend.normalize_display_name(_input.text)
	_counter_lbl.text = "%d/%d" % [_input.text.length(), Backend.DISPLAY_NAME_MAX]

	var has_name := cleaned != ""
	_preview_name_lbl.text = cleaned.to_upper() if has_name else "YOUR NAME"
	_preview_name_lbl.add_theme_color_override("font_color", Tokens.WHITE if has_name else Color(1, 1, 1, 0.35))
	_preview_badge.text = Tokens.initials(cleaned, "?")
	_preview_badge.bg_color = Tokens.VOLT if has_name else Tokens.LINE
	_preview_badge.text_color = Tokens.INK if has_name else Tokens.DIM

	_continue_btn.disabled = _busy or Backend.validate_display_name(_input.text) != ""

func _submit() -> void:
	if _busy:
		return
	var error: String = Backend.validate_display_name(_input.text)
	if error != "":
		_set_hint(error, true)
		return

	_busy = true
	_input.editable = false
	_continue_btn.text = "SAVING…"
	_refresh()

	var display_name: String = Backend.normalize_display_name(_input.text)
	var saved: Dictionary = await Backend.ensure_profile(display_name)
	if saved.is_empty():
		# Offline / backend unavailable: keep going on-device, sync later.
		Backend.save_local_profile(display_name)
	completed.emit()

func _on_google_sign_in_pressed() -> void:
	if _busy:
		return

	if not FirebaseConfig.is_google_configured():
		_set_hint("GOOGLE SIGN-IN IS NOT CONFIGURED IN FIREBASECONFIG.GD", true)
		return

	_busy = true
	_continue_btn.disabled = true
	if _google_btn:
		_google_btn.disabled = true
		_google_btn.text = "SIGNING IN…"
	_input.editable = false
	_set_hint("CONNECTING TO GOOGLE…", false)

	var auth_res := await GoogleAuth.authenticate(self)
	if not is_instance_valid(self):
		return

	if not auth_res.get("ok", false):
		_busy = false
		_input.editable = true
		_continue_btn.disabled = false
		if _google_btn:
			_google_btn.disabled = false
			_google_btn.text = "SIGN IN WITH GOOGLE"
		_refresh()
		var err_msg: String = auth_res.get("message", "SIGN-IN CANCELLED")
		_set_hint(err_msg.to_upper(), true)
		return

	_set_hint("SIGNING IN…", false)
	var id_token: String = auth_res.get("id_token", "")
	var access_token: String = auth_res.get("access_token", "")

	var signin_res := await Backend.sign_in_with_google(id_token, access_token)
	if not is_instance_valid(self):
		return

	if not signin_res.get("ok", false):
		_busy = false
		_input.editable = true
		_continue_btn.disabled = false
		if _google_btn:
			_google_btn.disabled = false
			_google_btn.text = "SIGN IN WITH GOOGLE"
		_refresh()
		var err: String = signin_res.get("message", "FAILED TO SIGN IN")
		_set_hint(err.to_upper(), true)
		return

	if signin_res.get("is_existing_player", false):
		_set_hint("ACCOUNT RESTORED. WELCOME BACK!", false)
		await get_tree().create_timer(0.4).timeout
		completed.emit()
	else:
		_busy = false
		_input.editable = true
		if _google_btn:
			_google_btn.visible = false
		var restored_prof: Dictionary = signin_res.get("profile", {})
		var default_name: String = restored_prof.get("display_name", "")
		if default_name != "":
			_input.text = default_name
			_input.caret_column = default_name.length()
		var email: String = signin_res.get("email", "")
		_set_hint("SIGNED IN AS %s. CONFIRM YOUR DISPLAY NAME." % email, false)
		_continue_btn.text = "CONFIRM & PLAY"
		_refresh()

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
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
