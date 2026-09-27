# 🏋️ FitArcade

**FitArcade** is a mobile exergaming platform built on **Godot 4.x** and **MediaPipe**. It uses your phone's front-facing camera to detect full-body calisthenics exercises in real time, turning physical movement into game input across three dedicated arcade mini-games.

No controllers. No wearables. Just you, your phone, and a workout.

---

## 🎮 Games & Exercises

| Game | Exercise | How It Works |
|---|---|---|
| **Chrome Dino** | Jumping Jacks | Each completed jack makes the dino jump over obstacles |
| **3-Lane Switcher** | Lunges | Lunge left or right to switch the player's lane |
| **Flappy Bird** | Arm Raises | Each arm raise flaps the bird upward |

---

## 🧠 Architecture

The project is structured into three clear layers:

### Core (`project/core/`)
| File | Role |
|---|---|
| `ExerciseRecognizer.gd` | Central FSM manager. Receives landmark data, drives state transitions, and emits `rep_completed` / `form_feedback` signals |
| `CalibrationManager.gd` | Validates full-body visibility in frame before gameplay unlocks |
| `SessionManager.gd` | Tracks reps, session score, and daily streaks across the session |

### Vision (`project/vision/`)
| File | Role |
|---|---|
| `PoseLandmarker.gd` | Wraps the MediaPipe Pose Landmarker task, processes camera frames, and forwards normalized landmarks to `ExerciseRecognizer` |

### Exercises (`project/exercises/`)
Each exercise is a class extending `ExerciseBase` that implements `process_frame()`:
- `JumpingJacks.gd` — tracks arm angle and ankle spread relative to shoulder width
- `Lunges.gd` — measures knee flexion angle on both legs independently
- `ArmRaiseExercise.gd` — measures hip-shoulder-wrist angle on both arms, uses the dominant arm

### Games (`project/games/`)
Each game extends `GameBase` and implements `on_rep_completed()`:
- `dino/DinoGame.gd`
- `switcher/SwitcherGame.gd`
- `flappy/FlappyBird.gd`

### UI (`project/ui/`)
- `CalibrationScreen.gd/.tscn` — mandatory calibration scene before every game
- `HUD.gd/.tscn` — unified in-game HUD (score, reps, form feedback)
- `theme/FitArcadeTheme.tres` — global design system (see below)

---

## 🏗️ Signal Flow

```
Camera Frame
    │
    ▼
PoseLandmarker.show_result()
    │  emits pose_processed(landmarks)
    ▼
ExerciseRecognizer.process_pose()
    │  runs active exercise FSM
    │  emits rep_completed / form_feedback
    ▼
GameManager._on_rep_completed()
    │
    ▼
ActiveGame.on_rep_completed()  ← jump / flap / switch lane
```

---

## 🎨 Design System — FitArcade Color System v1.0

| Token | Hex | Usage |
|---|---|---|
| Void | `#040410` | App background |
| Surface | `#1A1640` | Cards, panels |
| Arcade Cyan | `#06B6D4` | Primary accent, titles |
| Form Good | `#22C55E` | Positive form feedback |
| Form Break | `#EF4444` | Invalid form feedback |
| Highlight | `#FCCB15` | Scores, streaks |

**Typography:** Space Grotesk (variable weight `.ttf`)

---

## 🔄 Session Flow

```
Home Screen → Select Game
    │
    ▼
Calibration Screen
    │  Camera opens, user frames themselves
    │  CalibrationManager validates key landmarks are in frame
    │  Auto-advances after 1.5 s
    ▼
Game Scene (inside PoseLandmarker)
    │  PIP camera preview in corner
    │  Exercise FSM running every frame
    │  Game reacts to reps in real time
    ▼
Game Over Screen
    │  Final Score + Total Reps
    └──► Return to Menu
```

---

## ☁️ Backend & Admin Panel

FitArcade is backed by a **Firebase** project (`fitarcade-app`, Spark/free plan) providing remote switches, player profiles, and leaderboards. There's no custom server — the Godot client talks to Firebase directly over REST, and admins control the app through a separate web panel.

### Data model (Firestore)

| Collection | Purpose |
|---|---|
| `app_config/global` | Single doc holding `game_modes` (per-mode on/off), `maintenance_mode`, and gameplay `settings` (calibration thresholds etc.) |
| `admins/{uid}` | Whitelist gating admin-panel access and `app_config` writes. Seeded manually — never client-writable |
| `profiles/{uid}` | One per player: `display_name`, `display_tag` (`name#0423` style), `badge`, timestamps |
| `scores/{autoId}` | Full run history — one doc per completed game |
| `best_scores/{uid}_{game_mode}` | One row per player per mode; feeds the leaderboard. Client can only overwrite with a strictly higher score (enforced by `firestore.rules`) |

Rules live in [`firestore.rules`](firestore.rules); composite indexes in [`firestore.indexes.json`](firestore.indexes.json).

### Godot client (`project/backend/`)

- `Backend.gd` — autoload. Plain `HTTPRequest` + JSON against the Identity Toolkit and Firestore REST APIs — no native Firebase SDK, so it exports cleanly alongside the existing GDMP/CameraServerExtension plugins.
- Players get an **anonymous** Firebase Auth identity on first launch (no login screen), then claim a Player Card (display name + auto-generated `#tag` and badge).
- `app_config` is fetched **without auth** (public-read per rules) so the maintenance/game-mode check isn't blocked behind a sign-in round trip.
- The home screen polls `app_config` every 5s while idle so admin-panel changes show up without relaunching. This is polling, not push — a live listener would need the native Firestore SDK, which was deliberately avoided.
- Maintenance mode is a hard lock (full-screen, non-dismissable overlay). A disabled individual game mode stays visible with a "🔧 Under Maintenance" badge instead of disappearing.
- Config: `project/backend/FirebaseConfig.gd` (project ID + Web API key — public client identifiers, not secrets; access is enforced by `firestore.rules`).

### Admin panel (`admin/`)

A statically-exported Next.js app deployed to Firebase Hosting: **https://fitarcade-app.web.app**

- Email/password login, gated by membership in the `admins` Firestore collection.
- **Switches** — toggle each game mode and maintenance mode, edit gameplay settings.
- **Leaderboards** — top scores per game mode.
- **Profiles** — search players by name/tag, or look up an exact uid.

### Deploying

```bash
# Admin panel (after any change under admin/)
cd admin && npm run build && cd ..
firebase deploy --only hosting

# Firestore rules / indexes (after changing firestore.rules or firestore.indexes.json)
firebase deploy --only firestore:rules,firestore:indexes

# Everything at once
firebase deploy
```

---

## 🛠️ Developer Tooling

When running from the Godot Editor (debug build only), keyboard shortcuts are available to test without physical exercise:

| Key | Action |
|---|---|
| **D** | Instantly bypass calibration |
| **Space (press)** | Simulate exercise START position |
| **Space (release)** | Simulate exercise PEAK → triggers rep through the real FSM |

These shortcuts are disabled in release builds via `OS.is_debug_build()`.

---

## 📱 Supported Platforms

- Android (arm64-v8a, x86_64)
- iOS (arm64)
- Windows x86_64 (development / debug)

---

## 📦 Dependencies

- [Godot 4.x](https://godotengine.org/)
- [GDMP (Godot MediaPipe)](https://github.com/j20001970/GDMP) — v744fc80

---

## 🚀 Getting Started

1. Clone the repository
2. Open `project/` in Godot 4.x
3. Ensure GDMP binaries are present under `addons/GDMP/`
4. Run on device or in editor with a working webcam
5. Press **D** in-editor to skip calibration during testing
