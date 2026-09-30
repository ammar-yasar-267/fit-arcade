# Offline MediaPipe Models

For fully offline execution, the pose model is bundled at:

`res://models/pose_landmarker/movenet_lightning/movenet_singlepose_lightning_f16.tflite`

This is loaded by a hand-built MediaPipe graph (see `vision/pose_landmarker/MoveNetGraph.gd`)
rather than a prepackaged `.task` file, since MoveNet is not a MediaPipe Task. The bundled
bytes are copied to `user://movenet/` at runtime because `InferenceCalculator` needs a real
filesystem path, not a `res://` pck entry.

Notes:
- The app checks this bundled path before any network download.
- Export presets include both `*.task` and `*.tflite` files, so this file is packaged into exported builds.
- Runtime download is disabled by default (`Global.enable_download_files = false`).
- `pose_landmarker/pose_landmarker_lite/` (the previous MediaPipe Pose Landmarker Lite model)
  is kept alongside this for now as a rollback path — remove it once the MoveNet graph has
  been verified end-to-end on-device.
