extends Node

## Settings autoload — manages persisted user preferences

# Performance tuning
var delegate: int = MediaPipeTaskBaseOptions.DELEGATE_CPU
var inference_timeout_ms: int = 300
var frame_interval_ms: int = 50
var infer_max_dim: int = 280

# Rep detection thresholds
var arm_raise_start_max: float = 48.0
var arm_raise_end_min: float = 130.0

const SETTINGS_FILE := "user://fitarcade_settings.cfg"
const DEFAULTS := {
	"delegate": MediaPipeTaskBaseOptions.DELEGATE_CPU,
	"inference_timeout_ms": 300,
	"frame_interval_ms": 50,
	"infer_max_dim": 280,
	"arm_raise_start_max": 48.0,
	"arm_raise_end_min": 130.0,
}

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		delegate = config.get_value("performance", "delegate", DEFAULTS["delegate"])
		inference_timeout_ms = config.get_value("performance", "inference_timeout_ms", DEFAULTS["inference_timeout_ms"])
		frame_interval_ms = config.get_value("performance", "frame_interval_ms", DEFAULTS["frame_interval_ms"])
		infer_max_dim = config.get_value("performance", "infer_max_dim", DEFAULTS["infer_max_dim"])
		arm_raise_start_max = config.get_value("detection", "arm_raise_start_max", DEFAULTS["arm_raise_start_max"])
		arm_raise_end_min = config.get_value("detection", "arm_raise_end_min", DEFAULTS["arm_raise_end_min"])

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("performance", "delegate", delegate)
	config.set_value("performance", "inference_timeout_ms", inference_timeout_ms)
	config.set_value("performance", "frame_interval_ms", frame_interval_ms)
	config.set_value("performance", "infer_max_dim", infer_max_dim)
	config.set_value("detection", "arm_raise_start_max", arm_raise_start_max)
	config.set_value("detection", "arm_raise_end_min", arm_raise_end_min)
	config.save(SETTINGS_FILE)

func reset_to_defaults() -> void:
	delegate = DEFAULTS["delegate"]
	inference_timeout_ms = DEFAULTS["inference_timeout_ms"]
	frame_interval_ms = DEFAULTS["frame_interval_ms"]
	infer_max_dim = DEFAULTS["infer_max_dim"]
	arm_raise_start_max = DEFAULTS["arm_raise_start_max"]
	arm_raise_end_min = DEFAULTS["arm_raise_end_min"]
	save_settings()
