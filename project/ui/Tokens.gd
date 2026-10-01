extends Node

## FitArcade Design Tokens & Global Data
## Central source of truth for colors, typography, layout constants and mock data.

# --- Colors ---
const PAGE_BG = Color("#050506")
const INK = Color("#0B0B0C")
const PANEL = Color("#151517")
const LINE = Color("#2A2A2E")
const DIM = Color("#8A8A92")
const TEXT = Color("#F4F4F0")
const WHITE = Color("#FFFFFF")

const VOLT = Color("#D4FF3A")
const SIGNAL = Color("#FF3B2F")
const CYAN = Color("#3AE0FF")
const FLAME = Color("#FF8A1F")

const BAR_IDLE = Color("#3A3A3E")
const BAR_ZERO = Color("#1F1F22")

const PODIUM_2 = Color("#E8E8E8")
const PODIUM_3 = Color("#8A8A92")
const SKEL_LOCKED = Color("#555555")

const CAM_GRAD_INNER = Color("#2A2D33")
const PIP_GRAD_INNER = Color("#33363D")
const PIP_GRAD_OUTER = Color("#111111")
const FRAME_BEZEL = Color("#1C1C1F")

# --- Fonts ---
const FONT_DISPLAY: FontFile = preload("res://fonts/Anton/Anton-Regular.ttf")
const FONT_SANS: FontFile = preload("res://fonts/Barlow/Barlow-Regular.ttf")
const FONT_SANS_SEMIBOLD: FontFile = preload("res://fonts/Barlow/Barlow-SemiBold.ttf")
const FONT_SANS_BOLD: FontFile = preload("res://fonts/Barlow/Barlow-Bold.ttf")
const FONT_MONO: FontFile = preload("res://fonts/JetBrainsMono/JetBrainsMono-Variable.ttf")

# --- Dimensions & Spacing ---
const SCREEN_PADDING_LEFT = 20
const SCREEN_PADDING_RIGHT = 20
const SCREEN_PADDING_BOTTOM = 20
const SAFE_TOP_OFFSET = 64

# --- Data ---
const MODES: Array[Dictionary] = [
	{
		"id": "dino",
		"game": "Dino Runner",
		"exercise": "Jumping Jacks",
		"muscles": ["Full body", "Cardio", "Coordination"],
		"action": "Jack = Jump",
		"color": Color("#D4FF3A"),
		"limb": "ARMS & LEGS",
		"code": "01",
	},
	{
		"id": "lane",
		"game": "Lane Switcher",
		"exercise": "Side Lunges",
		"muscles": ["Quads", "Glutes", "Balance"],
		"action": "Lunge L/R = Shift lane",
		"color": Color("#3AE0FF"),
		"limb": "KNEES",
		"code": "02",
	},
	{
		"id": "flappy",
		"game": "Flappy Flight",
		"exercise": "Arm Raises",
		"muscles": ["Deltoids", "Lats", "Endurance"],
		"action": "Raise arms = Rise",
		"color": Color("#FF8A1F"),
		"limb": "ARMS",
		"code": "03",
	},
]

const WEEK: Array[Dictionary] = [
	{"d": "M", "reps": 84},
	{"d": "T", "reps": 120},
	{"d": "W", "reps": 0},
	{"d": "T", "reps": 96},
	{"d": "F", "reps": 142},
	{"d": "S", "reps": 60},
	{"d": "S", "reps": 110},
]

# --- Helpers ---

## Anton's line box is ~1.52x the font size, but its caps/digits only span ~0.87x
## above the baseline. This returns a Label wrapped in a Control sized to the
## visible ink, so stacked display text doesn't reserve (and drift apart over) the
## empty leading. Add `label.get_parent()` to the layout, not the label itself.
const DISPLAY_CAP_HEIGHT := 0.87

static func tight_display_label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, min_width: float = 0.0) -> Label:
	var font: Font = FONT_DISPLAY
	var cap_h := ceilf(font_size * DISPLAY_CAP_HEIGHT)
	var line_top := font.get_ascent(font_size) - cap_h

	var box := Control.new()
	box.custom_minimum_size = Vector2(min_width, cap_h)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = align
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = -line_top
	lbl.offset_bottom = -line_top + font.get_height(font_size)
	box.add_child(lbl)
	return lbl

## Badge initials for a display name: first letters of the first two words, or
## the first two letters of a single word. `fallback` when the name is empty.
static func initials(display_name: String, fallback: String = "P1") -> String:
	var parts := display_name.strip_edges().split(" ", false)
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	if parts.size() == 1:
		return parts[0].substr(0, 2).to_upper()
	return fallback

## Dark outline (and optional drop shadow) so HUD text stays readable over any
## game background, not just the dark top gradient.
static func make_legible(lbl: Label, outline_px: int = 3, outline_alpha: float = 0.9) -> Label:
	lbl.add_theme_constant_override("outline_size", outline_px)
	lbl.add_theme_color_override("font_outline_color", Color(INK.r, INK.g, INK.b, outline_alpha))
	return lbl

static func get_mode(mode_id: String) -> Dictionary:
	for m in MODES:
		if m["id"] == mode_id:
			return m
	return MODES[0]

static func format_time(seconds: float) -> String:
	var s := int(seconds)
	var mins := s / 60
	var secs := s % 60
	return "%d:%02d" % [mins, secs]

static func format_thousands(val: int) -> String:
	var s := str(val)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result

static func make_panel_style(bg: Color = PANEL, border_color: Color = LINE, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.anti_aliasing = false
	return sb
