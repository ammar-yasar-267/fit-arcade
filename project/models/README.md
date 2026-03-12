# Offline MediaPipe Models

For fully offline execution, place the pose model file at:

`res://models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task`

Notes:
- The app now checks this bundled path before any network download.
- Android export presets include `*.task` files, so this file will be packaged into the APK.
- Runtime download is disabled by default (`Global.enable_download_files = false`).
