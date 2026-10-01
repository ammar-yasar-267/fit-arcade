# FitArcade — Implementation TODO & Production Architecture Roadmap

This document outlines the missing infrastructure, backend schemas, and logic required to transition all placeholder metrics and prototype systems into full production-grade implementations.

---

## 1. User Profile & Identity Infrastructure

### Current Status
- Anonymous Firebase Authentication is implemented in `Backend.gd`.
- Local profile cache exists in `user://fitarcade_profile.cfg` (`display_name`, `display_tag`, `tag_number`, `badge`).
- Hub identity bar automatically binds to `Backend.profile` or generates a deterministic tag from the anonymous UID.

### Tasks
- [ ] **Player Profile Setup & Edit UI**:
  - Implement a dedicated Profile Screen or modal (accessible from Settings or by tapping the HexBadge).
  - Add `LineEdit` for display name customization with profanity filtering and length validation (3–16 characters).
  - Allow players to pick badge style (initials, avatar icon, or unlocked hex color accents).
- [ ] **Google Account Link (Authentication Upgrade)**:
  - Add a "LINK GOOGLE ACCOUNT" action to Settings > Account, so an anonymous player can attach a Google identity and keep their profile, scores and history if they reinstall or switch devices.
  - Implement `linkWithCredential` in `Backend.gd` to attach the Google credential to the existing anonymous account, keeping the same `uid` so nothing has to be migrated.
  - Handle the "Google account already linked to another FitArcade profile" case: offer to switch to that profile, and warn about what happens to the current anonymous profile's local data.
  - Show the linked Google account in Settings > Account (email, unlink / sign-out), and make Delete Account also remove the link.
  - Later, other providers (Google Play Games, Apple Game Center) can reuse the same linking flow.

---

## 2. XP, Leveling & Progression System

### Current Status
- Implemented a baseline lifetime rep counter in `SessionManager.gd` (`get_all_time_reps()`).
- Level is dynamically calculated as `1 + int(all_time_reps / 50)` (1 level per 50 reps).

### Tasks
- [ ] **XP Economy Specification**:
  - Design formal XP earning rules:
    - **Rep XP**: 10 XP per valid exercise repetition.
    - **Session Completion**: 50 XP bonus for completing a full 30-second game session.
    - **Daily Challenge Bounty**: +500 XP upon completing the daily challenge.
    - **Streak Multipliers**: 1.1x at 3-day streak, 1.25x at 7-day streak, 1.5x at 14-day streak.
- [ ] **Level Progression Curve**:
  - Implement a non-linear XP curve instead of flat rep thresholds:
    $$\text{XP to Next Level} = 100 \times (\text{Level})^{1.4}$$
  - Store `total_xp` and `current_level` in `Backend.profile` and persist to Firestore `profiles/{uid}`.
- [ ] **Level-Up UI & Celebration**:
  - Implement an animated level-up overlay when crossing an XP threshold.
  - Trigger audio fanfare and celebratory particle burst.
- [ ] **Progression Unlocks**:
  - Gate game modes or cosmetic skins behind level milestones (e.g. Flappy Flight unlock at Level 5, custom skeleton neon colors at Level 10).

---

## 3. Daily Challenge & Streak Engine

### Current Status
- `SessionManager.gd` provides a deterministic daily challenge based on system date:
  - Rotates exercise mode by day of week (Mon/Thu = Jumping Jacks, Tue/Fri/Sun = Side Lunges, Wed/Sat = Arm Raises).
  - Binds live challenge progress to real reps recorded for that exercise today.
  - Computes remaining countdown hours until local midnight.

### Tasks
- [ ] **Cloud-Configured Daily Challenges**:
  - Add a Firestore collection/document `app_config/daily_challenges` allowing designers to remotely push custom daily challenges without app updates.
  - Schema:
    ```json
    {
      "date": "2026-10-01",
      "mode_id": "lane",
      "exercise": "Side Lunges",
      "target_reps": 40,
      "time_limit_sec": 120,
      "xp_reward": 500,
      "modifier": "double_score"
    }
    ```
- [ ] **Challenge Claim Flow & State Machine**:
  - Implement challenge lifecycle states: `Active` $\rightarrow$ `Completed` $\rightarrow$ `Claimed`.
  - When target reps are reached, transform the PlayBlock button into a pulsing "CLAIM +500 XP" button.
  - Persist daily claim state in `user://fitarcade_challenges.json` to prevent duplicate XP rewards.
- [ ] **Streak Tracking & Verification**:
  - Track consecutive active workout days.
  - Store `streak_count`, `last_workout_date`, and `streak_freeze_count`.
  - Implement timezone-aware rollover so working out past midnight doesn't break streaks unfairly.

---

## 4. Cloud Workout History & Analytics

### Current Status
- `SessionManager.gd` logs completed sessions locally to `user://fitarcade_workout_history.json`.
- `WeekStrip.gd` dynamically aggregates real reps across the 7 days of the current week (Monday–Sunday) and highlights today's bar.

### Tasks
- [ ] **Firestore Workouts Collection**:
  - Create a cloud `workouts` collection:
    ```json
    {
      "uid": "user_abc123",
      "timestamp": "2026-09-30 21:05:00",
      "date": "2026-09-30",
      "game_mode": "dino",
      "reps": 35,
      "score": 15200,
      "duration_sec": 32,
      "avg_latency_ms": 14.2,
      "effective_fps": 30.1
    }
    ```
- [ ] **Offline-First Sync Queue**:
  - Implement a local queue (`user://pending_sync_workouts.json`) for workouts recorded without an internet connection.
  - Automatically flush and upload queued sessions when network connectivity is restored.
- [ ] **Cloud Weekly Aggregation**:
  - Implement a Firebase Cloud Function to pre-aggregate user weekly and monthly totals for instant leaderboard and profile rendering.
- [ ] **Historical Navigation UI**:
  - Add swipe/arrow navigation to `WeekStrip` allowing users to view previous weeks' rep totals and trends.

---

## 5. Leaderboard & Competitive Enhancements

### Current Status
- `Backend.get_leaderboard(game_mode, limit)` queries Firestore `best_scores` collection.
- `Hub.gd` asynchronously fetches real leaderboard ranks and displays real best scores.
- Local best scores are stored in `user://fitarcade_best_scores.cfg` for instant offline loading.

### Tasks
- [ ] **Firestore Composite Indexes**:
  - Verify and deploy composite indexes in `firestore.indexes.json` for:
    - Collection: `best_scores`, Fields: `game_mode` ASC, `score` DESC.
- [ ] **Leaderboard Scope Tabs**:
  - Add Daily, Weekly, and All-Time filter tabs to `LeaderboardScreen.gd`.
  - Weekly leaderboards reset every Monday 00:00 UTC.
- [ ] **Friends & Social Leaderboard**:
  - Allow adding friends by their 4-digit player tag (e.g. `Sami#7668`).
  - Add a "Friends" tab filtering `best_scores` to followed UIDs.
- [ ] **Percentile Rank Display**:
  - If a player's rank is outside the top 50, display their percentile (e.g. `TOP 15%`) instead of an empty dash `"—"`.

---

## 6. Sound & Haptic Pipeline

### Current Status
- UI components have vector animations and scale tweens on press.

### Tasks
- [ ] **Sound Manager Autoload (`AudioManager.gd`)**:
  - Implement centralized audio pool for low-latency SFX playback.
  - Sound cues:
    - `rep_counted.wav`: Crisp audio pop on every detected repetition.
    - `level_up.wav`: Triumphant arcade chord.
    - `challenge_complete.wav`: High-energy volt chime.
    - `ui_tap.wav`: Subtle, modern click on button press.
- [ ] **Haptic Feedback Integration**:
  - Add device vibration pulses on Android when reps are recognized (`Input.vibrate_handheld(30)`).
  - Add vibration pulse on game over or obstacle collision.
