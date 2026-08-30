extends Control

@onready var delegate_option = %DelegateOption
@onready var inference_timeout_slider = %InferenceTimeoutSlider
@onready var frame_interval_slider = %FrameIntervalSlider
@onready var max_infer_dim_slider = %MaxInferDimSlider
@onready var arm_raise_start_slider = %ArmRaiseStartSlider
@onready var arm_raise_end_slider = %ArmRaiseEndSlider

@onready var inference_timeout_value_label = %InferenceTimeoutValueLabel
@onready var frame_interval_value_label = %FrameIntervalValueLabel
@onready var max_infer_dim_value_label = %MaxInferDimValueLabel
@onready var arm_raise_start_value_label = %ArmRaiseStartValueLabel
@onready var arm_raise_end_value_label = %ArmRaiseEndValueLabel

@onready var reset_button = %ResetButton
@onready var back_button = %BackButton


func _ready() -> void:
	# Initialize delegate option items explicitly
	delegate_option.clear()
	delegate_option.add_item("CPU", MediaPipeTaskBaseOptions.DELEGATE_CPU)
	delegate_option.add_item("GPU", MediaPipeTaskBaseOptions.DELEGATE_GPU)
	
	# Load current settings into UI
	_load_ui_from_settings()
	
	# Connect signals
	delegate_option.item_selected.connect(_on_delegate_changed)
	inference_timeout_slider.value_changed.connect(_on_inference_timeout_changed)
	frame_interval_slider.value_changed.connect(_on_frame_interval_changed)
	max_infer_dim_slider.value_changed.connect(_on_max_infer_dim_changed)
	arm_raise_start_slider.value_changed.connect(_on_arm_raise_start_changed)
	arm_raise_end_slider.value_changed.connect(_on_arm_raise_end_changed)
	
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _load_ui_from_settings() -> void:
	# Delegate (select by index: 0=CPU, 1=GPU)
	delegate_option.select(Settings.delegate)
	
	# Inference timeout
	inference_timeout_slider.value = Settings.inference_timeout_ms
	inference_timeout_value_label.text = "%d ms" % Settings.inference_timeout_ms
	
	# Frame interval
	frame_interval_slider.value = Settings.frame_interval_ms
	frame_interval_value_label.text = "%d ms" % Settings.frame_interval_ms
	
	# Max infer dim
	max_infer_dim_slider.value = Settings.infer_max_dim
	max_infer_dim_value_label.text = "%d px" % Settings.infer_max_dim
	
	# Arm raise start
	arm_raise_start_slider.value = Settings.arm_raise_start_max
	arm_raise_start_value_label.text = "%.0f°" % Settings.arm_raise_start_max
	
	# Arm raise end
	arm_raise_end_slider.value = Settings.arm_raise_end_min
	arm_raise_end_value_label.text = "%.0f°" % Settings.arm_raise_end_min


func _on_delegate_changed(index: int) -> void:
	Settings.delegate = index
	Settings.save_settings()


func _on_inference_timeout_changed(value: float) -> void:
	Settings.inference_timeout_ms = int(value)
	inference_timeout_value_label.text = "%d ms" % int(value)
	Settings.save_settings()


func _on_frame_interval_changed(value: float) -> void:
	Settings.frame_interval_ms = int(value)
	frame_interval_value_label.text = "%d ms" % int(value)
	Settings.save_settings()


func _on_max_infer_dim_changed(value: float) -> void:
	Settings.infer_max_dim = int(value)
	max_infer_dim_value_label.text = "%d px" % int(value)
	Settings.save_settings()


func _on_arm_raise_start_changed(value: float) -> void:
	Settings.arm_raise_start_max = value
	arm_raise_start_value_label.text = "%.0f°" % value
	Settings.save_settings()


func _on_arm_raise_end_changed(value: float) -> void:
	Settings.arm_raise_end_min = value
	arm_raise_end_value_label.text = "%.0f°" % value
	Settings.save_settings()


func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_load_ui_from_settings()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
