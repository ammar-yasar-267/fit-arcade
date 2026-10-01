@tool
class_name MovePreview
extends Control

## Move preview box (72x88) with radial gradient camera background and skeleton figure.
## Spec from Figma C7.

const SkeletonClass = preload("res://ui/components/Skeleton.gd")

@export var mode: String = "dino":
	set(v):
		mode = v
		if _skeleton:
			_skeleton.mode = v

@export var is_locked: bool = false:
	set(v):
		is_locked = v
		_update_skeleton()

@export var phase: float = 0.0:
	set(v):
		phase = v
		if _skeleton and not is_locked:
			_skeleton.phase = v

@export var mode_color: Color = Color("#D4FF3A"):
	set(v):
		mode_color = v
		_update_skeleton()

var _skeleton: Control
var _bg_texture: GradientTexture2D

func _init() -> void:
	custom_minimum_size = Vector2(72, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_gradient()

func _init_gradient() -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Tokens.CAM_GRAD_INNER, Tokens.INK])
	grad.offsets = PackedFloat32Array([0.0, 0.85])

	_bg_texture = GradientTexture2D.new()
	_bg_texture.gradient = grad
	_bg_texture.fill = GradientTexture2D.FILL_RADIAL
	_bg_texture.fill_from = Vector2(0.5, 0.3)
	_bg_texture.fill_to = Vector2(0.5, 1.0)
	_bg_texture.width = 72
	_bg_texture.height = 88

func _ready() -> void:
	for c in get_children():
		c.queue_free()

	_skeleton = SkeletonClass.new()
	_skeleton.name = "Skeleton"
	_skeleton.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 6px padding inside 72x88
	_skeleton.offset_left = 6
	_skeleton.offset_top = 6
	_skeleton.offset_right = -6
	_skeleton.offset_bottom = -6
	_skeleton.mode = mode
	add_child(_skeleton)
	_update_skeleton()

func _update_skeleton() -> void:
	if not _skeleton:
		return
	if is_locked:
		_skeleton.pose_color = Tokens.SKEL_LOCKED
		_skeleton.phase = 0.0
	else:
		_skeleton.pose_color = mode_color
		_skeleton.phase = phase

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _bg_texture:
		draw_texture_rect(_bg_texture, rect, false)
	# 1px line border
	draw_rect(rect, Tokens.LINE, false, 1.0)
