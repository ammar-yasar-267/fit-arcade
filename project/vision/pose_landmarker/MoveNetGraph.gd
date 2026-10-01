class_name MoveNetGraph
extends MediaPipeTaskRunner

## Hand-built MediaPipe graph that runs MoveNet Lightning (single-pose) instead of
## the prepackaged Pose Landmarker task. Input: IMAGE (mediapipe::Image). Output:
## LANDMARKS (NormalizedLandmarkList, 17 COCO-order keypoints).
##
## MoveNet's raw output tensor is laid out per-keypoint as (y, x, score), while
## TensorsToLandmarksCalculator assumes (x, y, z). We let it decode as-is and swap
## x/y back when reading results (see PoseLandmarker.gd) rather than fight the
## calculator's fixed field order.

const MODEL_INPUT_SIZE := 192

## GDMP's generic MediaPipeProto.set_field() only supports bool/float/int32/int64/
## string/bytes/message (see MediaPipeProto doc) — uint32/uint64 proto fields hit
## "Unsupported type". MediaPipeProto.parse_from_buffer() does native protobuf wire
## parsing instead, so it isn't limited that way. We use it to hand-build the tiny
## submessages GDMP's reflection can't construct directly.
static func _append_varint(buffer: PackedByteArray, value: int) -> void:
	var v := value
	while true:
		var byte := v & 0x7F
		v = v >> 7
		if v != 0:
			buffer.append(byte | 0x80)
		else:
			buffer.append(byte)
			return

static func _make_proto(type_name: String, fields: Array = []) -> MediaPipeProto:
	var buffer := PackedByteArray()
	for field in fields:
		var field_number: int = field[0]
		var value: int = field[1]
		_append_varint(buffer, field_number << 3) # wire type 0 = varint
		_append_varint(buffer, value)
	var proto := MediaPipeProto.new()
	proto.initialize(type_name)
	if not buffer.is_empty():
		proto.parse_from_buffer(buffer)
	return proto

## PoseLandmarker.gd's _fix_landmark_order() needs to build a whole repeated-message
## field (17 NormalizedLandmark submessages) from scratch. MediaPipeProto.set_repeated_field()
## only sets an *existing* index (it doesn't grow the list — confirmed by "Index out
## of bounds (size = 0)" when tried), so that has to go through raw bytes too.
static func _append_tag(buffer: PackedByteArray, field_number: int, wire_type: int) -> void:
	_append_varint(buffer, (field_number << 3) | wire_type)

static func _append_float_field(buffer: PackedByteArray, field_number: int, value: float) -> void:
	_append_tag(buffer, field_number, 5) # wire type 5 = 32-bit (float/fixed32)
	var f := PackedByteArray()
	f.resize(4)
	f.encode_float(0, value)
	buffer.append_array(f)

static func _append_message_field(buffer: PackedByteArray, field_number: int, message_bytes: PackedByteArray) -> void:
	_append_tag(buffer, field_number, 2) # wire type 2 = length-delimited
	_append_varint(buffer, message_bytes.size())
	buffer.append_array(message_bytes)

## Which InferenceCalculator delegate to build. "nnapi" (hardware acceleration) exists
## only on Android; everything else, and anyone who picked CPU in Settings, gets the
## plain "tflite" CPU delegate.
static func delegate_kind(os_name: String, use_hw_accel: bool) -> String:
	return "nnapi" if (use_hw_accel and os_name == "Android") else "tflite"

func _init(model_path: String, use_hw_accel: bool = true) -> void:
	var builder := MediaPipeGraphBuilder.new()

	var image_to_tensor := builder.add_node("ImageToTensorCalculator")
	var i2t_options := MediaPipeProto.new()
	i2t_options.initialize("mediapipe.ImageToTensorCalculatorOptions")
	i2t_options.set_field("output_tensor_width", MODEL_INPUT_SIZE)
	i2t_options.set_field("output_tensor_height", MODEL_INPUT_SIZE)
	i2t_options.set_field("keep_aspect_ratio", true)
	i2t_options.set_field("border_mode", 1) # BORDER_ZERO — matches MoveNet's expected padding
	# MoveNet's TFLite input tensor is uint8 [0, 255] pixel values, not normalized
	# float [0, 1] — using output_tensor_float_range caused a type mismatch
	# ("Input tensor type kFloat32 vs interpreter tensor type UINT8"). The int64
	# output_tensor_int_range is what set_field() can reach, but MediaPipe validates
	# its max <= 127 (it's meant for int8 output), so [0, 255] is rejected there too.
	# output_tensor_uint_range (fields 1=min, 2=max, both uint64) is the only field
	# that actually supports the full [0, 255] uint8 range, so it's built by hand.
	var uint_range := _make_proto(
		"mediapipe.ImageToTensorCalculatorOptions.UIntRange",
		[[1, 0], [2, 255]]
	)
	i2t_options.set_field("output_tensor_uint_range", uint_range)
	image_to_tensor.set_options(i2t_options)

	var inference := builder.add_node("InferenceCalculator")
	var inf_options := MediaPipeProto.new()
	inf_options.initialize("mediapipe.InferenceCalculatorOptions")
	inf_options.set_field("model_path", model_path)
	# delegate.tflite/.nnapi are empty messages (just oneof markers); set_field({})
	# fails with "Unsupported type" since a bare Dictionary isn't a MediaPipeProto.
	# NNAPI ("Android only" per InferenceCalculatorOptions.Delegate.Nnapi) taps
	# whatever hardware NN acceleration the device's NNAPI driver exposes for this
	# quantized (uint8) model; all its fields are optional and auto-select when
	# unset (no cache dir, accelerator chosen by NNAPI itself). Elsewhere (desktop
	# dev builds), NNAPI isn't available, so fall back to the default TFLite CPU
	# delegate used before this change.
	# Settings > Hardware acceleration picks between the two (see delegate_kind()).
	if delegate_kind(OS.get_name(), use_hw_accel) == "nnapi":
		var nnapi_delegate := _make_proto("mediapipe.InferenceCalculatorOptions.Delegate.Nnapi")
		inf_options.set_field("delegate/nnapi", nnapi_delegate)
	else:
		var tflite_delegate := _make_proto("mediapipe.InferenceCalculatorOptions.Delegate.TfLite")
		inf_options.set_field("delegate/tflite", tflite_delegate)
	inference.set_options(inf_options)

	var tensors_to_landmarks := builder.add_node("TensorsToLandmarksCalculator")
	var t2l_options := MediaPipeProto.new()
	t2l_options.initialize("mediapipe.TensorsToLandmarksCalculatorOptions")
	t2l_options.set_field("num_landmarks", PoseKeypoints.NUM_KEYPOINTS)
	# TensorsToLandmarksCalculator assumes raw tensor values are ABSOLUTE pixel
	# coordinates (the BlazePose/MediaPipe convention) and normalizes by dividing
	# by input_image_width/height. MoveNet's raw output is already normalized to
	# [0,1] — dividing an already-normalized ~0.3 by 192 again is exactly what was
	# collapsing every landmark to ~0.001-0.005. Using 1x1 here makes that division
	# a no-op, passing MoveNet's already-correct values straight through.
	t2l_options.set_field("input_image_width", 1)
	t2l_options.set_field("input_image_height", 1)
	t2l_options.set_field("visibility_activation", 2) # NONE — MoveNet has no separate visibility channel
	tensors_to_landmarks.set_options(t2l_options)

	var letterbox_removal := builder.add_node("LandmarkLetterboxRemovalCalculator")

	builder.get_input_tag("IMAGE").connect_to(image_to_tensor.get_input_tag("IMAGE"), "input_image")
	image_to_tensor.get_output_tag("TENSORS").connect_to(inference.get_input_tag("TENSORS"), "image_tensor")
	image_to_tensor.get_output_tag("LETTERBOX_PADDING").connect_to(letterbox_removal.get_input_tag("LETTERBOX_PADDING"), "letterbox_padding")
	inference.get_output_tag("TENSORS").connect_to(tensors_to_landmarks.get_input_tag("TENSORS"), "output_tensor")
	tensors_to_landmarks.get_output_tag("NORM_LANDMARKS").connect_to(letterbox_removal.get_input_tag("LANDMARKS"), "raw_landmarks")
	letterbox_removal.get_output_tag("LANDMARKS").connect_to(builder.get_output_tag("LANDMARKS"), "pose_landmarks")

	var config := builder.get_config()
	initialize(config, true)
