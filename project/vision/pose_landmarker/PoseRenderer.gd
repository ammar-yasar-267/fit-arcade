class_name MediaPipePoseRenderer
extends MediaPipeLandmarksRenderer

## COCO-17 skeleton edges (as output by MoveNet). See PoseKeypoints for index names.
static var POSE_CONNECTIONS: PackedInt32Array = [
	0, 1, 0, 2, 1, 3, 2, 4,
	0, 5, 0, 6, 5, 6,
	5, 7, 7, 9, 6, 8, 8, 10,
	5, 11, 6, 12, 11, 12,
	11, 13, 13, 15, 12, 14, 14, 16,
]

## Odd COCO indices are left-side keypoints, even (non-zero) are right-side.
## Each pair is a single-element [begin, end) range picking out one keypoint.
var SPLIT_LEFT := [
	[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16]
]

var SPLIT_RIGHT := [
	[2, 3], [4, 5], [6, 7], [8, 9], [10, 11], [12, 13], [14, 15], [16, 17]
]

## MoveNet's confidence scores read on a different scale than BlazePose's did —
## real detections cluster ~0.6-0.95 for upper body, phantom/no-person "guesses"
## top out around ~0.3, so 0.3 is the cutoff that separates them (measured live).
const VISIBILITY_THRESHOLD := 0.3

static func pose_landmarks_to_render_data(builder: MediaPipeGraphBuilder) -> MediaPipeGraphNode:
	return landmarks_to_render_data(
		builder, POSE_CONNECTIONS,
		Color.WHITE, Color.WHITE,
		3.0, false, true, VISIBILITY_THRESHOLD,
	)

static func split_landmarks(builder: MediaPipeGraphBuilder, splits: Array) -> MediaPipeGraphNode:
	var node := builder.add_node("SplitNormalizedLandmarkListCalculator")
	var options := MediaPipeProto.new()
	options.initialize("mediapipe.SplitVectorCalculatorOptions")
	var ranges: Array[MediaPipeProto] = []
	for range: Array in splits:
		var proto := MediaPipeProto.new()
		proto.initialize("mediapipe.Range")
		proto.set_field("begin", range[0])
		proto.set_field("end", range[1])
		ranges.push_back(proto)
	options.set_field("ranges", ranges)
	options.set_field("combine_outputs", true)
	node.set_options(options)
	return node

static func left_landmarks_to_render_data(builder: MediaPipeGraphBuilder) -> MediaPipeGraphNode:
	return landmarks_to_render_data(
		builder, [],
		Color.from_rgba8(255, 138, 0), Color.from_rgba8(255, 138, 0),
		3.0, false, true, VISIBILITY_THRESHOLD
	)

static func right_landmarks_to_render_data(builder: MediaPipeGraphBuilder) -> MediaPipeGraphNode:
	return landmarks_to_render_data(
		builder, [],
		Color.from_rgba8(0, 217, 231), Color.from_rgba8(0, 217, 231),
		3.0, false, true, VISIBILITY_THRESHOLD
	)

func _init() -> void:
	var builder := MediaPipeGraphBuilder.new()
	var loop_begin := builder.add_node("BeginLoopNormalizedLandmarkListVectorCalculator")
	var pose_render := pose_landmarks_to_render_data(builder)
	var left_split := split_landmarks(builder, SPLIT_LEFT)
	var left_render := left_landmarks_to_render_data(builder)
	var right_split := split_landmarks(builder, SPLIT_RIGHT)
	var right_render := right_landmarks_to_render_data(builder)
	var loop_end := builder.add_node("EndLoopRenderDataCalculator")
	var loop_end_left := builder.add_node("EndLoopRenderDataCalculator")
	var loop_end_right := builder.add_node("EndLoopRenderDataCalculator")
	var annotation := builder.add_node("AnnotationOverlayCalculator")
	# Begin Loop
	builder.get_input_tag("LANDMARKS").connect_to(loop_begin.get_input_tag("ITERABLE"), "multi_pose_landmarks")
	# Pose
	loop_begin.get_output_tag("ITEM").connect_to(pose_render.get_input_tag("NORM_LANDMARKS"), "pose_landmarks")
	# Left
	loop_begin.get_output_tag("ITEM").connect_to(left_split.get_input_index(0), "pose_landmarks")
	left_split.get_output_index(0).connect_to(left_render.get_input_tag("NORM_LANDMARKS"), "landmarks_left_side")
	# Right
	loop_begin.get_output_tag("ITEM").connect_to(right_split.get_input_index(0), "pose_landmarks")
	right_split.get_output_index(0).connect_to(right_render.get_input_tag("NORM_LANDMARKS"), "landmarks_right_side")
	# End Loop
	pose_render.get_output_tag("RENDER_DATA").connect_to(loop_end.get_input_tag("ITEM"), "landmarks_render_data")
	loop_begin.get_output_tag("BATCH_END").connect_to(loop_end.get_input_tag("BATCH_END"), "landmark_timestamp")
	left_render.get_output_tag("RENDER_DATA").connect_to(loop_end_left.get_input_tag("ITEM"), "landmarks_left_joints_render_data")
	loop_begin.get_output_tag("BATCH_END").connect_to(loop_end_left.get_input_tag("BATCH_END"), "landmark_timestamp")
	right_render.get_output_tag("RENDER_DATA").connect_to(loop_end_right.get_input_tag("ITEM"), "landmarks_right_joints_render_data")
	loop_begin.get_output_tag("BATCH_END").connect_to(loop_end_right.get_input_tag("BATCH_END"), "landmark_timestamp")
	# Annotation
	builder.get_input_tag("IMAGE").connect_to(annotation.get_input_tag("IMAGE"), "input_image")
	loop_end.get_output_tag("ITERABLE").connect_to(annotation.get_input_tag("VECTOR:0"), "multi_landmarks_render_data")
	loop_end_left.get_output_tag("ITERABLE").connect_to(annotation.get_input_tag("VECTOR:1"), "multi_landmarks_left_joints_render_data")
	loop_end_right.get_output_tag("ITERABLE").connect_to(annotation.get_input_tag("VECTOR:2"), "multi_landmarks_right_joints_render_data")
	annotation.get_output_tag("IMAGE").connect_to(builder.get_output_tag("IMAGE"), "output_image")
	var config := builder.get_config()
	initialize(config)

func render(image: MediaPipeImage, multi_pose_landmarks: Array[MediaPipeNormalizedLandmarks]) -> MediaPipeImage:
	var packets := {
		"input_image": image.get_image_frame_packet(),
		"multi_pose_landmarks": MediaPipeNormalizedLandmarks.make_vector_proto_packet(multi_pose_landmarks),
	}
	var outputs := process(packets)
	if outputs.has("output_image"):
		var packet := outputs.get("output_image") as MediaPipePacket
		var output_image := packet.get() as MediaPipeImage
		return output_image
	return image
