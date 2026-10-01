extends ColorRect

## Pulsing placeholder block for any value that's still loading.
##
## Every SkeletonBar derives its opacity from the clock rather than from its own
## tween, so all the skeletons on screen pulse in lockstep without needing a
## shared driver. Motion is the spec's `pulse`: 2 s loop, opacity 1 -> 0.5 -> 1.

const BLOCK_COLOR := Color(1, 1, 1, 0.09)
const PULSE_SECONDS := 2.0
const PULSE_LOW := 0.5

func _init(width: float = 0.0, height: float = 0.0, fill: Color = BLOCK_COLOR) -> void:
	color = fill
	custom_minimum_size = Vector2(width, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	modulate.a = pulse_alpha()

func _process(_delta: float) -> void:
	modulate.a = pulse_alpha()

static func pulse_alpha() -> float:
	var seconds := float(Time.get_ticks_msec()) / 1000.0
	return lerpf(PULSE_LOW, 1.0, 0.5 + 0.5 * cos(seconds * TAU / PULSE_SECONDS))

## A bar of `width` x `height` centred vertically in a slot `slot_height` tall, so a
## skeleton can occupy exactly the space of the value it stands in for.
## `align_right` pins it to the right edge (for right-aligned numbers). `fill` is for
## backgrounds where the default white@0.09 wouldn't show (e.g. a volt banner).
static func slot(width: float, height: float, slot_height: float, align_right: bool = false, fill: Color = BLOCK_COLOR) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, slot_height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := new(width, height, fill)
	holder.add_child(bar)
	bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT if align_right else Control.PRESET_CENTER_LEFT)
	bar.offset_left = -width if align_right else 0.0
	bar.offset_right = 0.0 if align_right else width
	bar.offset_top = -height * 0.5
	bar.offset_bottom = height * 0.5
	return holder
