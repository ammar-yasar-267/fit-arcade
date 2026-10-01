extends Node

## Settings autoload — manages persisted user preferences

# Performance tuning
var delegate: int = MediaPipeTaskBaseOptions.DELEGATE_CPU
var inference_timeout_ms: int = 500
var frame_interval_ms: int = 0
var infer_max_dim: int = 280

# Rep detection thresholds
# end_min retuned down from 130.0 (needed exaggerated overhead reach on a phone
# camera's framing/distance vs. the laptop it was originally tuned against — a
# fixed global angle threshold doesn't transfer cleanly across camera setups).
var arm_raise_start_max: float = 45.0
var arm_raise_end_min: float = 80.0

# Hardware acceleration preference: "GPU" (use it when the device can) or "CPU".
# Read the effective choice through use_hardware_accel(), not this string.
var accel: String = "GPU"

# General App Preferences
var skip_calibration: bool = false
var show_debug_info: bool = false
var sound_enabled: bool = true
var show_skeleton: bool = true
var mirror_camera: bool = true
var haptics_enabled: bool = true
var high_contrast_hud: bool = false

const SETTINGS_FILE := "user://fitarcade_settings.cfg"
const DEFAULTS := {
	"delegate": MediaPipeTaskBaseOptions.DELEGATE_GPU,
	"accel": "GPU",
	"inference_timeout_ms": 500,
	"frame_interval_ms": 0,
	"infer_max_dim": 280,
	"arm_raise_start_max": 45.0,
	"arm_raise_end_min": 80.0,
	"skip_calibration": false,
	"show_debug_info": false,
	"sound_enabled": true,
	"show_skeleton": true,
	"mirror_camera": true,
	"haptics_enabled": true,
	"high_contrast_hud": false,
}

func _ready() -> void:
	load_settings()
	_sync_delegate()

## Pose inference can only be hardware-accelerated on Android (NNAPI, see
## MoveNetGraph). Everywhere else the model runs on the CPU whatever was picked.
static func hardware_accel_available(os_name: String = OS.get_name()) -> bool:
	return os_name == "Android"

## What will actually run: the player's preference, limited by what the device supports.
func use_hardware_accel() -> bool:
	return accel == "GPU" and hardware_accel_available()

func set_accel(mode: String) -> void:
	accel = "GPU" if mode == "GPU" else "CPU"
	_sync_delegate()
	save_settings()

## `delegate` is the value the vision code reads. Derive it from the effective choice
## so it can never disagree with the toggle (it used to default to CPU while the UI said GPU).
func _sync_delegate() -> void:
	delegate = MediaPipeTaskBaseOptions.DELEGATE_GPU if use_hardware_accel() else MediaPipeTaskBaseOptions.DELEGATE_CPU

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		accel = config.get_value("performance", "accel", DEFAULTS["accel"])
		inference_timeout_ms = config.get_value("performance", "inference_timeout_ms", DEFAULTS["inference_timeout_ms"])
		frame_interval_ms = config.get_value("performance", "frame_interval_ms", DEFAULTS["frame_interval_ms"])
		infer_max_dim = config.get_value("performance", "infer_max_dim", DEFAULTS["infer_max_dim"])
		arm_raise_start_max = config.get_value("detection", "arm_raise_start_max", DEFAULTS["arm_raise_start_max"])
		arm_raise_end_min = config.get_value("detection", "arm_raise_end_min", DEFAULTS["arm_raise_end_min"])
		skip_calibration = config.get_value("app", "skip_calibration", DEFAULTS["skip_calibration"])
		show_debug_info = config.get_value("app", "show_debug_info", DEFAULTS["show_debug_info"])
		sound_enabled = config.get_value("app", "sound_enabled", DEFAULTS["sound_enabled"])
		show_skeleton = config.get_value("app", "show_skeleton", DEFAULTS["show_skeleton"])
		mirror_camera = config.get_value("app", "mirror_camera", DEFAULTS["mirror_camera"])
		haptics_enabled = config.get_value("app", "haptics_enabled", DEFAULTS["haptics_enabled"])
		high_contrast_hud = config.get_value("app", "high_contrast_hud", DEFAULTS["high_contrast_hud"])

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("performance", "accel", accel)
	config.set_value("performance", "delegate", delegate)
	config.set_value("performance", "inference_timeout_ms", inference_timeout_ms)
	config.set_value("performance", "frame_interval_ms", frame_interval_ms)
	config.set_value("performance", "infer_max_dim", infer_max_dim)
	config.set_value("detection", "arm_raise_start_max", arm_raise_start_max)
	config.set_value("detection", "arm_raise_end_min", arm_raise_end_min)
	config.set_value("app", "skip_calibration", skip_calibration)
	config.set_value("app", "show_debug_info", show_debug_info)
	config.set_value("app", "sound_enabled", sound_enabled)
	config.set_value("app", "show_skeleton", show_skeleton)
	config.set_value("app", "mirror_camera", mirror_camera)
	config.set_value("app", "haptics_enabled", haptics_enabled)
	config.set_value("app", "high_contrast_hud", high_contrast_hud)
	config.save(SETTINGS_FILE)

func reset_to_defaults() -> void:
	accel = DEFAULTS["accel"]
	inference_timeout_ms = DEFAULTS["inference_timeout_ms"]
	frame_interval_ms = DEFAULTS["frame_interval_ms"]
	infer_max_dim = DEFAULTS["infer_max_dim"]
	arm_raise_start_max = DEFAULTS["arm_raise_start_max"]
	arm_raise_end_min = DEFAULTS["arm_raise_end_min"]
	skip_calibration = DEFAULTS["skip_calibration"]
	show_debug_info = DEFAULTS["show_debug_info"]
	sound_enabled = DEFAULTS["sound_enabled"]
	show_skeleton = DEFAULTS["show_skeleton"]
	mirror_camera = DEFAULTS["mirror_camera"]
	haptics_enabled = DEFAULTS["haptics_enabled"]
	high_contrast_hud = DEFAULTS["high_contrast_hud"]
	_sync_delegate()
	save_settings()
