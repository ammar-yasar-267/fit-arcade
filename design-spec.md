# FitArcade — Godot Implementation Handoff Spec

## Context
The React/Tailwind prototype in `src/` is approved and is the source of truth. This document records it exactly, so another agent can rebuild it natively in Godot 4 without redesigning anything. Every value here comes from the current code:
- `src/index.css`
- `src/data.ts`
- `src/App.tsx`
- `src/components/*.tsx`

**On approval:** save this document to `docs/GODOT_HANDOFF.md`. No UI code changes.

**Units:**
- 1 Tailwind spacing unit = 4 px. All px values are CSS px at a 390 px-wide viewport; treat them as Godot units at a 390-wide base.
- `em` letter spacing = font size × value.
- Colors are `#RRGGBB`, followed by `@α` for opacity (e.g. `#FFFFFF@0.6`).

---

## A. SCREEN MAP

```
            ┌──────────── onNav('leaderboard') ───────────┐
            │                                              ▼
  [HUB] ────┼── onNav('settings') ──► [SETTINGS]      [LEADERBOARD]
   ▲  │     │                            │ back             │ back
   │  │     └────────────────────────────┴──────────────────┴──► HUB
   │  │ Start (game row) / Daily challenge tap (→ mode 'lane')
   │  ▼
   │ [CALIBRATE] ──(auto, ~5.15 s)──► [PLAY] ──(timer 32 s OR "End workout")──► [SUMMARY]
   │   │ back → HUB                     │ tap anywhere → PAUSED overlay        │
   │                                    │   Resume → PLAY  /  End workout → SUMMARY
   │                                                                           │
   └────────────── "Return to hub" ◄───────────────────────────────────────────┤
                   "Play again" / auto-countdown 10 s ──► CALIBRATE (same mode, fresh run)
```

**Screens:** `hub | calibrate | play | summary | leaderboard | settings`. This is a flat state machine held in `App`, with no history stack.

**Back behaviour:**
- Every back control returns to HUB directly.
- Hardware/OS back is not handled in the prototype. The recommended mapping is the same target as the on-screen back: Leaderboard/Settings/Calibrate → Hub. In Play, OS back should behave the same as tap-to-pause (behavioural equivalent, not a new pattern).

**Overlays and expandables:**
1. **Play › Primed overlay:** shown until the first rep, non-interactive.
2. **Play › Rep flash:** transient overlay.
3. **Play › Paused overlay:** a modal covering the full screen.
4. **Hub › Game-row accordion:** exactly one row is expanded at a time.

There are no dialogs, sheets or popups.

**Fresh run:** entering CALIBRATE via Start / Daily / Play again increments `run`. That remounts Calibrate and Play, so their state resets.

---

## B. DESIGN TOKENS

### B1. Colours
| Token | Value | Use |
|---|---|---|
| `page_bg` | `#050506` | Outside the phone frame (desktop only) |
| `ink` | `#0B0B0C` | Screen background, dark text on accent fills |
| `panel` | `#151517` | Card surface (Week strip, Daily card, leaderboard badge) |
| `line` | `#2A2A2E` | Hairlines, 1 px borders, locked-button fill `#2A2A2E` |
| `dim` | `#8A8A92` | Secondary/label text, inactive tab text |
| `text` | `#F4F4F0` | Default foreground ("white" in the prototype = this for body; see note below) |
| `volt` | `#D4FF3A` | Primary accent, Dino mode, "ready", success |
| `signal` | `#FF3B2F` | Errors, locked/maintenance, "too close", obstacles, CAM LIVE dot |
| `cyan` | `#3AE0FF` | Lane mode |
| `flame` | `#FF8A1F` | Flappy mode, "missing limb" stage |
| `bar_idle` | `#3A3A3E` | Week bars with reps>0 (not today) |
| `bar_zero` | `#1F1F22` | Week bars with 0 reps |
| `podium_2` | `#E8E8E8` | 2nd-place block |
| `podium_3` | `#8A8A92` | 3rd-place block |
| `skel_locked` | `#555555` | Skeleton colour on locked mode |
| `cam_grad_inner` | `#2A2D33` | Radial gradient centre (Calibrate, Hub preview) |
| `pip_grad_inner` / `pip_grad_outer` | `#33363D` / `#111111` | Play PIP camera |
| `frame_bezel` | `#1C1C1F` | Desktop phone border |
| Game backgrounds | Dino `#0B0B0C→#1A1C10` vertical; Lane `#07141A`; Flappy `#1A0E05→#0B0B0C` vertical; Ground `#111214`, ticks `#2A2A2E` | |

**White vs text:** Tailwind `text-white` / `bg-white` is pure `#FFFFFF`. Inherited body text is `#F4F4F0`. Use `#FFFFFF` wherever the spec says *white*.

**White opacities used:**

| Opacity | Where |
|---|---|
| @0.05 | stripes, "me" row, hover |
| @0.07 | *(unused now)* |
| @0.08 | ring track |
| @0.10 | progress tracks |
| @0.15 | *(none)* |
| @0.20 | separator dot |
| @0.25 | breadcrumb slash |
| @0.30 | locked title |
| @0.40 | pause hint; End-workout border |
| @0.50 | inactive stats, hint text, daily subline |
| @0.60 | inactive titles, "7H LEFT", body copy |
| @0.70 | action line |
| @0.80 | calibrate subline; PIP border |

**Mode palette:** `dino → volt`, `lane → cyan`, `flappy → flame`. Referenced below as `mode.color`.

### B2. Typography
| Token | Family | Weight | Notes |
|---|---|---|---|
| `display` | **Anton** (fallback Impact) | 400 (only weight) | All headings/numerals, usually UPPERCASE |
| `sans` | **Barlow** | 400/600 (semibold)/700 (bold) loaded 400–800 | Body |
| `mono` | **JetBrains Mono** | 400 (default), 700 for `RANK` pill label | Labels, tags |

**Numerals:** `tabular-nums` applies to all numeric displays. Anton digits are close to fixed-width. In JetBrains Mono they are already tabular.

**Size scale:**

| Name | Size / line-height |
|---|---|
| xs | 12 / 16 |
| sm | 14 / 20 |
| base | 16 / 24 |
| lg | 18 / 28 |
| xl | 20 / 28 |
| 2xl | 24 / 32 |
| 3xl | 30 / 36 |
| 4xl | 36 / 40 |
| 5xl | 48 / 48 |

Arbitrary sizes used: 8, 9, 10, 11, 13, 22, 26, 28, 44, 52, 56, 64, 80, 92, 112 px.

**Line-height overrides:**

| Value | Meaning |
|---|---|
| `leading-none` | 1.0 |
| `leading-tight` | 1.25 |
| 0.9 | Titles |
| 0.95 | Calibrate big text |
| 0.85 | Play reps |
| 0.8 | Summary reps |

**Letter spacing:**

| Value | Name |
|---|---|
| 0.025em | wide |
| 0.05em | wider |
| 0.1em | widest |
| 0.3em | Calibrate/Play "READY" line |

**Recurring text styles:**

| Style | Spec |
|---|---|
| `label` | mono 10, tracking 0.1em, `dim` (e.g. "THIS WEEK" is 11) |
| `micro` | mono 9, tracking 0.1em, `dim` (RANK/BEST captions) |
| `h_page` | display 56, lh 0.9, uppercase |
| `stat_num` | display 18 (lg) / 20 (xl) / 36 (4xl), lh 1, tabular |

### B3. Shape, borders, shadows
**Radius:** 0 everywhere; everything is hard-edged. The exceptions:
- Desktop phone frame: 36 px.
- Circles: CAM LIVE dot, lane coin, flappy bird and eye, PIP "in frame" dot, progress ring.
- Clip polygons: hexagon badge; triangle player in Lane.

**Borders:**
- 1 px `line`: the default for buttons, cards, rows and the tab bar.
- 2 px: Leaderboard podium badge (mode.color), Calibrate frame (stage color), PIP (white@0.8).
- 4 px: Dino ground top (volt), Flappy bird (ink).
- 6 px: Calibrate corner brackets.
- 10 px: phone bezel.

**Ring vs border:** `ring-1` is a 1 px outer outline that doesn't affect layout. Treat it as a 1 px border, drawn inside or outside; the visual difference is negligible.

**Shadows and glows:**
- Desktop frame: `0 40 120 -20 volt@0.15`.
- Calibrate frame inner glow: `inset 0 0 60 stageColor@0.2` (`33` hex = 0.2).
- Rep-flash inner border: `inset 0 0 0 10px` volt/signal.
- No other shadows.

### B4. Spacing
| Token | Value |
|---|---|
| Screen padding | L/R 20, bottom 20 |
| Safe top offset | 64 (`pt-16`) on Hub, Settings, Leaderboard, Summary, and the Calibrate top bar. Play HUD top = 56 (`pt-14`); pause hint at top 36. |
| Common gaps | 4, 6, 8, 12, 16, 20 |

### B5. Motion
| Name | Spec |
|---|---|
| Default transition | 150 ms, cubic-bezier(0.4, 0, 0.2, 1) (colour/opacity/transform) |
| `press` | scale 0.95 (icon buttons, daily play block), 0.98 (Start), 0.99 (daily card), 0.90 is unused |
| `pop` | 0.9 s ease-out, one-shot: scale 0.6/α0 → 30%: 1.1/α1 → 100%: 1.0/α0 |
| `bob` | 1.2 s ease-in-out loop, translateY 0 → −6 → 0 |
| `pulse` | 2 s cubic-bezier(0.4, 0, 0.6, 1) loop, opacity 1 → 0.5 → 1 |
| Accordion | 300 ms (height 0 ↔ content), default easing |
| Calibrate colour change | 300 ms |
| Skeleton zoom | 700 ms |

---

## C. COMPONENTS

### C1. `IconButton` (BackButton, Leaderboard, Settings)
**Size and shape:**
- 40×40, 1 px `line` border, no radius.
- BackButton background is `ink@0.6` (used over the camera). Hub icon buttons have a transparent background.

**Icon:**
- 20×20, drawn in a 24-unit viewBox.
- Stroke `#FFFFFF`, square caps, no fill.
- Stroke width 2.5 on the back button, 2.2 on the Hub icons.

**States:**
- Hover/focus: border and fill become `volt`, icon becomes `ink`.
- Pressed: scale 0.95.

**Glyph paths** (use these exactly, as vector data or recreated with `Line2D`/`draw_polyline`):
- **Back chevron:** `M14.5 5.5 L8 12 L14.5 18.5`
- **Leaderboard podium:** `M9 20V8h6v12` · `M3 20v-7h6` · `M15 20v-9h6v9` · `M2 20h20`
- **Settings sliders:**
  - Lines: `M4 7h9` · `M17 7h3` · `M4 17h3` · `M11 17h9`
  - Plus two 4×4 stroked squares at (13, 5) and (7, 15).

### C2. `PageHeader` (Settings, Leaderboard)
**Row 1:** HBox with gap 12, vertically centred.
- Left: `IconButton(back)`.
- Right: breadcrumb in mono 11, tracking 0.1em.
  - "HUB" in `dim`.
  - " / " in white@0.25.
  - `TITLE` (uppercase) in `#FFFFFF`.

**Title:** 20 px below row 1, display 56, lh 0.9, uppercase.

**Dynamic:** `title`.

### C3. `IdentityBar` (Hub header)
HBox with gap 12, items centred. It contains, left to right:
1. **HexBadge:**
   - 44×44 volt fill, clipped to the hexagon (50,0) (100,25) (100,75) (50,100) (0,75) (0,25) in %.
   - Text "KV" in display 18, `ink`, centred.
2. **Name block** (expands, truncates):
   - Name "KAI VEGA": display 20, lh 1, tracking 0.025em.
   - 4 px below it: "#0423 · LVL 17" in mono 10 `dim`.
3. **Two icon buttons:** `IconButton(leaderboard)`, then `IconButton(settings)`.

### C4. `WeekStrip` card
**Container:**
- `panel` fill with a 1 px `line` outline.
- Padding: horizontal 16, vertical 14.
- HBox with gap 20, items bottom-aligned.

**Left column (shrink):**
- "THIS WEEK": mono 11, tracking 0.1em, `dim`.
- "612": display 48, lh 1. Immediately followed (4 px left margin) by "REPS" in display 18, `dim`, sharing the same baseline.

**Right: bar chart**
- Fixed height 64. Expands horizontally.
- HBox with gap 8, bottom-aligned. 7 equal-width columns.
- Each column is a VBox with gap 4, centred:
  - Bar: full column width. Height `max(3, reps/max*46)` px.
  - Day letter below: mono 10.
- Colours:
  - Index 6 (today): bar `volt`, letter `volt`.
  - Other days: bar `bar_idle` if reps > 0, else `bar_zero`; letter `dim`.
- Data: M 84, T 120, W 0, T 96, F 142, S 60, S 110 (max 142).

**Static:** total and data are static in the prototype.

### C5. `DailyChallengeCard` (button)
**Container:**
- `panel` fill with a 1 px `line` outline.
- Padding: top/bottom 12, right 12, left 16.
- HBox with gap 12, items centred.

**Text column** (expands):
1. Line 1, mono 10, tracking 0.1em:
   - "DAILY CHALLENGE · " in `dim`.
   - "7H LEFT" in white@0.6.
2. 4 px gap, then "40 SIDE LUNGES": display 22, lh 1, uppercase.
3. 6 px gap, then line 3 in sans 12 semibold, lh 1:
   - "Under 2:00" in white@0.5.
   - "·" in white@0.2 with 4 px padding each side.
   - "+500 XP" in `volt`.

**ProgressRing:**
- 56×56. Circle r = 28 in a 64 viewBox, stroke 4.
- Track: white@0.08.
- Arc: `volt`, 35% of the circle (14/40), starting at 12 o'clock, clockwise, butt caps.
- Centre text on one line, both on the same baseline:
  - "14": display 18, lh 1.
  - "/40": display 12, `dim`.

**PlayBlock:**
- 36 wide × 56 tall, `volt` fill.
- Filled play triangle, 16×16, in `ink`. Path `M7 4.5 v15 L19.5 12 z` (24 viewBox), nudged +1 px on x.

**States:**
- Hover: the outline becomes `volt@0.6`; PlayBlock brightness 110%.
- Pressed: card scales to 0.99; PlayBlock scales to 0.95.
- Tap: if `lane` is not locked, select mode `lane` and start a fresh run → CALIBRATE. If it is locked, nothing happens.

### C6. `SectionHeading` ("GAMES")
HBox with gap 12, centred:
- "GAMES": display 24, lh 1, uppercase.
- 1 px `line` rule that expands to fill the space.
- "PICK ONE · 3 MODES": mono 10, tracking 0.1em, `dim`.

### C7. `GameRow` (accordion item)
Container: VBox with a 1 px `line` bottom border only.

**Header (button):**
- HBox with gap 12, padding top/bottom 14, items centred.
- **Colour bar:**
  - 6 px wide, stretched to the full row height.
  - Colour: `signal` if locked, else `mode.color`.
  - Opacity 1 when active, 0.35 otherwise.
- **Text column** (expands):
  - **Exercise name:** display 28, lh 1, uppercase, truncated. Colour: white@0.3 if locked; `#FFFFFF` if active; white@0.6 if inactive.
  - 4 px gap, then **subline** in mono 10, tracking 0.05em.
    - Locked: "BACK SOON" in `signal`.
    - Otherwise: the game name uppercased (e.g. "DINO RUNNER"), in `mode.color` if active, else `dim`.
- **Stats** (hidden when locked):
  - HBox with gap 16, right-aligned, lh 1.
  - Two cells, each with a caption in mono 9, tracking 0.1em, `dim`, and a value below in display 18, tabular. Value colour: `#FFFFFF` when active, white@0.5 when inactive.
  - Cell 1: "RANK" / `#N`.
  - Cell 2: "BEST" / score formatted with thousands separators (e.g. "41,300").
  - Rank and best come from the player's row in `LEADERBOARD[mode]`. If the player isn't found, show "—".

**Expandable body:**
- Height animates 0 ↔ content over 300 ms, clipped. Bottom padding is 16 when open.
- HBox with gap 12, left inset 18 (so it lines up after the colour bar and gap).
- **MovePreview:**
  - 72×88 box, 1 px `line` border.
  - Background: radial gradient `#2A2D33` (centre at 50%, 30%) → `#0B0B0C`.
  - Contains the `Skeleton` with 6 px padding, animated by the Hub phase.
  - Locked: colour `#555`, phase 0.
- **Right column** (VBox, expands):
  - Action text, e.g. "Jack = Jump": sans 14 semibold, white@0.7.
  - **StartButton**, pushed to the bottom of the column:
    - Full width, padding 12 horizontal × 10 vertical.
    - HBox centred with gap 8.
    - Fill `mode.color`, content `ink`.
    - Play triangle 14×14, followed by "START" in display 20, lh 1, tracking 0.025em.
    - Hover: brightness 110%. Pressed: scale 0.98.
    - **Locked:** fill `#2A2A2E`, text `#8A8A92`, label "UNDER MAINTENANCE", no icon, disabled.

**Behaviour:**
- Tapping the header selects that row. Exactly one row is active; tapping the active row keeps it open.
- Initial selection: the first unlocked mode (Dino by default).

### C8. `Wordmark` footer
- HBox with gap 12, centred. Padding: top 32, bottom 4.
- Pinned to the bottom of the scroll content (the spacer pushes it down when content is short).
- Contents: a 1 px `line` rule (expands), "FIT" + "ARCADE", then another 1 px `line` rule (expands).
  - "FIT": display 20, lh 1, tracking 0.05em, uppercase, `#FFFFFF`.
  - "ARCADE": same style, `volt`.

### C9. `Skeleton` (procedural pose figure)
**Canvas:** viewBox 100×130, scaled uniformly (preserve aspect ratio, centred).

**Inputs:**
- `mode`
- `phase` 0..1; `t = sin(phase·π)`
- `color` (default volt)
- `missing` limb: `ARMS | KNEES | FEET | null`

**Defaults:**

| Point | Value |
|---|---|
| Left hand `lh` | (30, 62) |
| Right hand `rh` | (70, 62) |
| Left foot `lf` | (42, 118) |
| Right foot `rf` | (58, 118) |
| Left knee `lk` | (44, 100) |
| Right knee `rk` | (56, 100) |
| `hipX` | 50 |

**Per-mode motion:**
- **dino:**
  - `lh = (30−6t, 62−44t)`, `rh = (70+6t, 62−44t)`
  - `lf = (42−12t, 118)`, `rf = (58+12t, 118)`
  - `lk = (44−6t, 100)`, `rk = (56+6t, 100)`
- **lane:**
  - `hipX = 50−10t`
  - `lf = (30−6t, 118)`, `rf = (64, 118)`
  - `lk = (34−6t, 98+4t)`, `rk = (58, 100)`
- **flappy:**
  - `lh = (30−4t, 62−48t)`, `rh = (70+4t, 62−48t)`

**Drawing** (round caps):
- Head: circle at (hipX, 20), r = 8, stroke 2.
- Spine: (hipX, 30) → (hipX, 76), stroke 2.4.
- Shoulders: (hipX−12, 40) → (hipX+12, 40).
- Hips: (hipX−8, 76) → (hipX+8, 76).
- Arms: polyline shoulder → mid → hand, where mid = ((sx+hx)/2, (40+hy)/2 + 4).
- Thighs: hip end → knee.
- Shins: knee → foot.
- Joints: circle r = 2.6, fill `ink`, stroke 1.6, at hands, knees, feet and both shoulders.

**Missing limb:** that limb's segments and joints are drawn in `signal`, dashed 3 on / 3 off.

### C10. `ModeTabs` (Leaderboard)
**Container:** 3-column equal grid with a 1 px `line` outer border, no gaps.

**Cells:**
- Padding vertical 10.
- Label: sans 12 bold, uppercase, tracking 0.025em, the exercise name ("JUMPING JACKS", "SIDE LUNGES", "ARM RAISES").

**States:**
- Active: fill `mode.color`, text `ink`.
- Inactive: transparent, text `dim`.
- Instant switch.

### C11. `Podium` (Leaderboard)
**Layout:** 3-column grid, gap 8, bottom-aligned. Order: 2nd, 1st, 3rd.

**Each column** is a centred VBox:
1. **Badge:** 48×48, 2 px border in `mode.color`, initials in display 18.
2. 4 px gap, then **name:** sans 12 bold, centred, truncated.
3. **Score:** mono 10 `dim`, thousands separators.
4. 8 px gap, then **block:**
   - Full width. Height 70 (2nd), 100 (1st), 50 (3rd).
   - Fill: 1st `mode.color`, 2nd `#E8E8E8`, 3rd `#8A8A92`.
   - Place number top-left: 8 px padding left, 4 px padding top, display 36, `ink`.

### C12. `LeaderboardTable`
**Column template:** `36 px | 1fr | auto`.

**Header row:**
- Mono 10, tracking 0.1em, `dim`.
- Labels "# / PLAYER / SCORE / DATE".
- 4 px bottom padding and a 1 px `line` bottom border.

**Rows:**
- Padding vertical 10, 1 px `line` bottom border.
- The player's own row has a white@0.05 fill.

**Cells:**
- **Rank:** display 24. Coloured `mode.color` for ranks 1–3; otherwise `#F4F4F0`.
- **Player:** HBox with gap 8.
  - Badge: 32×32, `panel` fill, initials in mono 10 bold.
  - Name block, lh 1.25:
    - Name: sans 14 bold. The player's own row adds a "YOU" chip: 4 px left margin, `volt` fill, `ink` text, sans 9, 4 px horizontal padding.
    - Tag below: mono 10, `dim`.
- **Score/date:** right-aligned, lh 1.25.
  - Score: display 20, tabular.
  - Date below: mono 10, `dim`.

**Scrolling:** the whole table scrolls (the header row scrolls with it). Scrollbar hidden.

### C13. `SegmentedToggle` (CPU/GPU)
**Container:** 2-column grid, 1 px `line` border, 4 px inner padding.

**Segments:**
- Padding vertical 12. Label in display 24.
- Active: `volt` fill, `ink` text.
- Inactive: `dim` text; hover `#FFFFFF`.

**Helper text** (4 px… actually 8 px below): sans 14, white@0.6.
- GPU: "Faster pose inference (~40 ms). Uses more battery."
- CPU: "Most compatible. Expect ~70 ms latency on older phones."

### C14. `SensitivitySlider`
**Container:** 16 px top margin, 1 px `line` top border, 12 px top padding.

**Row:** space-between, bottom-aligned.
- Left:
  - Label: sans 16 bold, uppercase.
  - Hint: sans 12, white@0.5.
- Right: value `N°` in display 36, in the slider colour.

**Slider:**
- 8 px below the row, full width.
- Native range input tinted with `accent-color`: a thin track plus a round thumb, both in the slider colour.
- Recreate with `HSlider`, using the same accent for grabber and fill.

**Scale labels:** a row below the slider, mono 9 `dim`, space-between: `EASIER · {min}°` and `{max}° · STRICTER`.

**Instances:**

| Key | Label | Hint | Range | Default | Colour |
|---|---|---|---|---|---|
| jack | "Jack arm spread" | "Hands-over-head angle to count a jack" | 120–180 | 150 | volt |
| lunge | "Lunge knee depth" | "Knee bend required for a side lunge" | 60–140 | 100 | cyan |
| arm | "Arm raise reach" | "Shoulder angle required for a raise" | 70–170 | 120 | flame |

Step 1. Updates live.

### C15. `LockRow` (Settings)
- Full-width button, 8 px top margin, 1 px `line` border, padding 12 horizontal × 10 vertical, space-between.
- Left: game name in sans bold, uppercase, 16.
- Right, mono 10:
  - Locked: "● MAINTENANCE" in `signal`.
  - Live: "● LIVE" in `volt`.
- Tap toggles `locked[mode]`.

### C16. `StatCell` (Summary)
- 1 px `line` top border, 8 px top padding.
- Label: mono 10, tracking 0.1em, `dim`.
- Value: display 36, lh 1, tabular. Optional unit after it: 4 px left margin, display 20, `dim`.

### C17. `ProgressBar` (flat)
- Track: white@0.10. Fill: solid colour. No radius.
- Heights:
  - Calibrate: 12 (volt).
  - Play: 6 (mode.color).

### C18. Primary / secondary action buttons
**Primary** (Summary "Play again"):
- Full width, `#FFFFFF` fill, padding vertical 16, display 30, `ink`, uppercase.
- A `volt` fill sweeps in from the left as the countdown progresses (linear, 1 s per step).

**Secondary** ("Return to hub"):
- Expands, 1 px `line` border, padding vertical 12, display 18, uppercase. Hover: white@0.05 fill.

**Tertiary** ("CANCEL AUTO"):
- 1 px `line` border, 16 px horizontal padding, mono 10, `dim`. Hover: `#FFFFFF`.

**Pause-overlay buttons:** both 224 wide.
- "Resume": `volt` fill, padding vertical 16, display 24, `ink`, uppercase.
- "End workout": 1 px white@0.4 border, padding vertical 12, display 20, uppercase.

### C19. `Banner` (Summary PB / submitted)
- HBox with gap 12, padding 16 horizontal × 12 vertical.
- **PB variant:** `volt` fill, `ink` text.
  - Glyph "★" in display 24.
  - Title "NEW PERSONAL BEST!": display 20, uppercase.
  - Subline: mono 10, `ink@0.7`, "BEAT {best} · POSTED TO LEADERBOARD".
- **Else variant:** 1 px `line` border.
  - Glyph "✓".
  - Title "SCORE SUBMITTED".
  - Subline in `dim`: "PB {best} · POSTED TO LEADERBOARD".

---

## D. SCREEN-BY-SCREEN

**Screen root:** fills the phone viewport, background `ink`. **Desktop presentation** (not needed in Godot):
- A 390×min(844, vh−48) frame with a 10 px bezel and 36 px radius, so content is 370 wide.
- On viewports ≥ 1024 px, a left aside shows the FitArcade logo (display 60), a description line and "SCREEN · X".

### D1. HUB (`Hub.tsx`)
The root is a full-height VBox with padding 64 top, 20 left/right, 20 bottom. Children in order:
1. **IdentityBar** (C3). Fixed height.
2. 24 px gap, then **WeekStrip** (C4).
3. 12 px gap, then **DailyChallengeCard** (C5).
4. 40 px gap, then **SectionHeading "GAMES"** (C6).
5. **ScrollArea:** expands to fill the remaining height, scrollbar hidden, vertical only. Its content is a VBox:
   - Three GameRows (C7), in the order dino, lane, flappy.
   - An expanding spacer.
   - The Wordmark (C8).

**Hub animation state:**
- `phase` advances by 0.04 every 40 ms, wrapping at 1, so one full cycle = 1 s.
- It drives the active row's skeleton. All rows use the same phase, but only the expanded row is visible.

**Default data state:**
- flappy is locked, so its row shows "BACK SOON", has no stats and has a red bar.
- Dino is expanded initially.

### D2. CALIBRATE (`Calibrate.tsx`)
The root is a full-screen layered Control.

**Layers, back to front:**
1. **Background:** radial gradient ellipse centred at (50%, 30%): `#2A2D33` → `#0B0B0C` at 70%.
2. **Stripes overlay:** full size at opacity 0.4. The pattern is diagonal −45°, repeating every 12 px: 2 px white@0.05, then 10 px transparent.
3. **Frame guide:**
   - Anchored at left 32, right 32, top 128, bottom 260.
   - 2 px border in the stage colour, with inner glow `inset 0 0 60 stageColor@0.2`. Colour transitions over 300 ms.
   - **Corner brackets:** 24×24 L-shapes with 6 px arms in the stage colour, one in each corner (TL; TR rotated 90°; BR 180°; BL −90°).
   - **Skeleton inside:**
     - Centred, height 88% of the frame.
     - Phase 0, so it's static.
     - Colour: `volt` on ready, `#FFFFFF` otherwise.
     - `missing = mode.limb` during the "missing" stage.
   - **Zoom:** a wrapper transform `scale(1.9) translateY(12%)` during "close", `scale(1)` otherwise, animated over 700 ms. The frame clips it only via the screen's overflow; the frame itself doesn't clip.
4. **Top bar:** anchored top, padding 64 top, 20 left/right, 16 bottom, space-between, centred.
   - Left: `IconButton(back)` → HUB.
   - Right: an 8×8 `signal` circle (pulse animation), 8 px gap, then "CAM LIVE · {GAME}" in mono 10, tracking 0.1em.
5. **Bottom panel:** anchored bottom, 20 px padding.
   - "FRAMING n/3": mono 11, tracking 0.1em, stage colour.
   - Big text: display 52, lh 0.95, uppercase, stage colour.
   - 4 px gap, then subline: sans 18 semibold, white@0.8.
   - 16 px gap, then ProgressBar (12 px, volt), fill = lock progress.
   - 8 px gap, then "HANDS-FREE · AUTO-STARTS WHEN FRAMED FOR 1s": mono 10, `dim`.

**Stages:**

| Stage | Colour | Big text | Subline |
|---|---|---|---|
| close (0–1.8 s) | `signal` | "STEP BACK" | "Body cut off — move 2–3 m away" |
| missing (1.8–3.8 s) | `flame` | "SHOW {limb lower}" | "{Exercise} needs your {limb lower} in frame" |
| ready (3.8 s+) | `volt` | "HOLD STILL" | "Locking in…" |

On ready, the lock bar fills linearly 0 → 1 over 1000 ms. When it is full, wait 350 ms, then go to PLAY.

### D3. PLAY (`Play.tsx`)
The root is a full-screen layered Control; tapping anywhere pauses.

**Layers, back to front:**
1. **Game canvas:** full screen, per mode (see F4).
2. **HUD:**
   - Anchored top, full width.
   - Background: vertical gradient ink (0%) → ink@0.8 (50%) → transparent (100%).
   - Padding: top 56, left/right 20, bottom 40.
   - **Row** (space-between, top-aligned):
     - **Left:** "REPS" label (mono 10, tracking 0.1em, `dim`), then the rep count in display 92, lh 0.85, `mode.color`.
     - **Right** (right-aligned):
       - "TIME" label, then time "m:ss" in display 48, lh 1.
       - 12 px gap, then "SCORE" label, then the score in display 36, lh 1, thousands separators.
   - 8 px gap, then the session ProgressBar: 6 px, fill = t/32 in `mode.color`.
3. **Rep flash:** full-screen, input-transparent. Re-created on every rep attempt, so each one re-triggers the animation.
   - Inner 10 px border in `volt` (ok) or `signal` (bad), with the `pop` animation.
   - Badge centred horizontally with its top at 44% of the height:
     - Padding 20 horizontal × 8 vertical, display 48, uppercase, `ink` text.
     - Fill `volt`/`signal`. Text "+1 REP" / "GO DEEPER". `pop` animation.
4. **PIP camera:**
   - Anchored bottom-right with 12 px insets. Size 96×144.
   - 2 px white@0.8 border. Background: radial gradient `#33363D` → `#111111` at (50%, 30%).
   - Skeleton with 8 px padding, colour `mode.color`, animated by `repPhase`.
   - Top-left at inset 4: a 6×6 volt dot, 4 px gap, "IN FRAME" in mono 8.
5. **Primed overlay** (shown while not started):
   - Full screen, ink@0.7, content centred.
   - "READY · STEP BACK": mono 12, tracking 0.3em, `dim`.
   - 8 px gap, then "FIRST REP" / "STARTS IT" on two lines: display 64, lh 0.9, uppercase. The second line is in `mode.color`.
   - 16 px gap, then "DO 1 {exercise minus trailing 's'}": sans 20 bold, uppercase, `bob` animation.
6. **Pause hint** (shown when started and not paused):
   - Anchored top 36, centred.
   - "TAP ANYWHERE TO PAUSE": mono 9, white@0.4.
7. **Paused overlay:**
   - Full screen, z on top, ink@0.9 plus the stripes pattern. It swallows taps.
   - VBox centred, gap 16:
     - "PAUSED": display 80, lh 1.
     - "TIMERS FROZEN · {reps} REPS · {m:ss}": mono 12, `dim`.
     - 16 px extra gap, then the Resume button.
     - The End workout button (C18).

**Lane labels:**
- Anchored bottom 12, left 0, right 112 (clear of the PIP), padding 16 horizontal, space-between.
- Display 16, uppercase, cyan@0.6: "◀ LUNGE L" and "LUNGE R ▶".

**Flappy hint:** bottom 40, left 16. "▲ RAISE ARMS TO RISE" in display 16, flame@0.7, uppercase.

### D4. SUMMARY (`Summary.tsx`)
The root is a scrollable VBox with padding 64 top, 20 left/right, 20 bottom. Children in order:
1. **Kicker:** "{code} / {GAME} · SESSION COMPLETE" in mono 10, tracking 0.1em, `mode.color`.
2. 4 px gap, then **"WORK" / "DONE."** on two lines: display 44, lh 0.9, uppercase.
3. 16 px gap, then an **HBox** with gap 12, bottom-aligned:
   - Reps: display 112, lh 0.8, `mode.color`.
   - "VALID" / "{EXERCISE}" on two lines: display 24, lh 1, uppercase, 8 px bottom padding.
4. 20 px gap, then a **2×2 grid** of StatCells, column gap 16, row gap 16:
   - ACTIVE TIME (m:ss)
   - SCORE (thousands separators)
   - TRACKING LATENCY ({n} + unit "ms")
   - GLOBAL RANK (#n)
5. 20 px gap, then the **Banner** (C19).
6. **Action block:** pushed to the bottom by an expanding spacer, 20 px top padding. VBox with gap 12:
   - Primary "PLAY AGAIN · {count}". The " · n" suffix only appears while auto is on.
   - HBox with gap 12: "RETURN TO HUB" (expands), plus "CANCEL AUTO" while auto is on.

**Computed values:**
- `rank` = 1 + the number of leaderboard entries for this mode whose score is greater than `result.score`.
- `best` = the player's (#0423) score.
- `pb` = `result.score > best`.

### D5. LEADERBOARD (`Leaderboard.tsx`)
The root is a VBox with padding 64 top, 20 left/right, 20 bottom. Children in order:
1. PageHeader "Leaderboard".
2. 16 px gap, then ModeTabs (default tab: dino).
3. 24 px gap, then the Podium.
4. 20 px gap, then the LeaderboardTable. It expands to fill the remaining height and scrolls.

The accent colour everywhere on this screen = the active tab's `mode.color`.

### D6. SETTINGS / "TRACKING" (`Settings.tsx`)
The root is a scrollable VBox with padding 64 top, 20 left/right, 20 bottom, scrollbar hidden. Children in order:
1. PageHeader "Tracking".
2. 24 px gap, then a section:
   - Label "HARDWARE ACCELERATION".
   - 8 px gap, then SegmentedToggle.
   - 8 px gap, then helper text.
3. 28 px gap, then a section: label "EXERCISE SENSITIVITY", then three SensitivitySliders.
4. 28 px gap, then a section: label "REMOTE GAME LOCKS (DEMO)", then three LockRows, one per mode, showing the game name.

---

## E. ASSET INVENTORY

**Assets rebuilt as vectors or native UI:**

| Asset | Source | Recommendation |
|---|---|---|
| Fonts: Anton, Barlow (400/600/700), JetBrains Mono (400/700) | Google Fonts (OFL) | **B**: bundle the TTF/OTF files as `FontFile` |
| Back chevron, podium icon, sliders icon, play triangle | Inline SVG paths (C1, C5) | **B**: export as SVG using the exact paths, or **D**: draw them |
| Progress ring | SVG circle | **D**: `draw_arc` |
| Hex player badge | CSS clip-path | **D**: `draw_colored_polygon` + Label |
| Skeleton pose figure | Procedural SVG | **D**: `_draw()` using the C9 formulas |
| Calibrate corner brackets, frame, glow | CSS | **D** / **A**: StyleBox, or custom draw; inner glow via shader or gradient |
| Diagonal stripes pattern | CSS gradient | **D**: shader, or a tiling 12×12 texture |
| Radial "camera" gradients | CSS | **D**: `GradientTexture2D` (radial fill) |
| HUD vertical fade, game backgrounds | CSS gradients | **D**: `GradientTexture2D` |
| Week bars, podium blocks, progress bars, dividers | CSS boxes | **A**: `ColorRect` / `Panel` |
| Wordmark "FITARCADE" | Text | **A**: two Labels / `RichTextLabel` (no image logo exists) |
| Game sprites: dino player block with "▲", red obstacles, lane coin "+"/obstacle "✕", cyan triangle player, flame pipes, volt bird with eye, scrolling ground | CSS shapes and Unicode glyphs | **D**: `ColorRect`/`Polygon2D`/draw + Labels |

**Text glyphs:** "★", "✓", "◀", "▶", "▲", "✕", "●", "—", "·". Keep them as font glyphs (**A**). Check that the bundled fonts have them; if one is missing, add a fallback font. Do not substitute icons.

**Not used:** photos, raster images, or third-party icon sets. **C** (replace with a public asset) applies to nothing.

---

## F. BEHAVIOUR / INTERACTION

### F1. Global state (App)
| Field | Initial value |
|---|---|
| `screen` | `'hub'` |
| `modeId` | `'dino'` |
| `result` | `null` |
| `run` | `0` |
| `locked` | `{dino: false, lane: false, flappy: true}` |
| `settings` | `{accel: 'GPU', jack: 150, lunge: 100, arm: 120}` |

- **`again()`:** `run++`, then screen = calibrate.
- **Pick:** set `modeId`, then call `again()`.
- **Persistence:** none, across screens or runs. Settings do not currently affect tracking.

### F2. Hub
- **Row header tap:** set `sel`. The previous row collapses and the new one expands, both over 300 ms.
- **Selection init:** `sel` initialises when Hub mounts, so returning to Hub resets it to the first unlocked mode.
- **Start** (unlocked only): pick that mode.
- **Daily card:** pick `lane` unless it is locked.
- **Icon buttons:** leaderboard / settings.
- **Locking:** toggling a lock in Settings affects Hub rows, including the Start disabled state and the Daily card no-op.

### F3. Calibrate
- The timeline is driven by timers (D2).
- **Back:** cancels all timers, then → Hub.
- **Loading state:** the "Locking in…" bar is the only loading indicator.
- **Error states:** the "close" and "missing" framing stages.

### F4. Play: simulation loop (per frame, dt clamped ≤ 0.05 s)

**Game state:**

| Field | Initial |
|---|---|
| `started` | false |
| `t` | 0 |
| `reps` | 0 |
| `score` | 0 |
| `lastRep` | −9 |
| `lane` | 1 |
| `y` | 50 |
| `vy` | 0 |
| `nextRep` | 2.6 |
| `wall` | 0 |

**Each frame, when not paused:**
1. `wall += dt`.
2. If `started`:
   - `t += dt`
   - `score += dt·(40 + 4t)`
   - Flappy only: `vy += 60·dt`; `y = clamp(y + vy·dt, 8, 88)`.
3. **Rep attempt:** when `wall ≥ nextRep`:
   - `ok = random > 0.15`.
   - The first attempt sets `started = true`. This is the "first rep starts it" mechanic.
   - If `ok`:
     - `reps++`, `score += 120`, `lastRep = t`.
     - Lane: if at 0 → 2, if at 2 → 0, if at 1 → random 0 or 2.
     - Flappy: `vy = −38`.
   - Trigger the rep flash (ok or bad).
   - `nextRep = wall + 0.9 + random·0.6`.
4. **End:** when `t ≥ 32`, call `end({reps, seconds: round(t), score: round(score), latency: 38 + round(random·14)})`.

The real app replaces the random reps with pose detection.

**Derived values:**
- `since = t − lastRep`.
- **PIP `repPhase`:**
  - Started: `max(0, 1 − since/0.6)`.
  - Otherwise (idle sway): `(sin(2·wall) + 1)/6`.

**Pause:**
- Tapping anywhere sets `paused`. The loop keeps rendering but freezes all counters.
- **Resume:** unpause.
- **End workout:** end with `latency = 42`.

**Per-mode game canvas** (percentages are of the screen size):
- **Dino:**
  - `speed = 180 + 6t`.
  - **Ground:** bottom 26% of the height, `#111214`, 4 px volt top border. Vertical ticks 3 px `#2A2A2E` every 40 px, scrolling at x = −t·speed.
  - **Decorative circle:** 64 px, volt@0.15, at top 40%, right 40.
  - **Obstacles:** 3 of them, at offsets [0, 0.45, 0.8].
    - `x = 1.1 − ((t·speed/420 + o) mod 1.4)`, as a fraction of the width.
    - `signal` fill, width 18, height 56 for tall (indices 0 and 2) or 34 otherwise.
    - Each has an 8×16 arm at left −8, top 12.
  - **Player:** 56×64 volt block with "▲" (display 30, `ink`). Left 18%, sitting on the ground line. `translateY(−jump·130)`, where `jump = max(0, sin(min(1, since/0.6)·π))` once started.
- **Lane:**
  - Background `#07141A`. Three equal columns, each with 1 px cyan@0.15 side borders.
  - **Dashes:** vertical repeating 30 px cyan@0.12 then 40 px gap, scrolling at y = t·240.
  - **Items:** 3 of them, at offsets [0, 0.33, 0.66].
    - `y = ((0.45t + o) mod 1.2) − 0.1`.
    - `lane = (2i + floor(0.45t + o)) mod 3`.
    - 48×48, centred in the lane. Item 1 is a coin (volt circle "+"); the others are obstacles (`signal` square "✕"), display 20.
  - **Player:** 64×80 cyan triangle, bottom 14%. Horizontal position animates over 200 ms to the lane centre, (lane + 0.5)·33.33%.
- **Flappy:**
  - Background: vertical `#1A0E05` → `#0B0B0C`.
  - **Pipes:** 2, at offsets [0, 0.55].
    - `x = 1.1 − ((0.22t + o) mod 1.3)`.
    - `gap = 38 + ((23i + 17·floor(0.22t + o)) mod 30)`, as % of the height.
    - 56 px wide, flame fill.
    - Top pipe height = gap%. Bottom pipe starts at (gap + 26)%.
  - **Bird:** 48 px circle, volt fill, 4 px ink border. Left 20%, vertically centred on y%. Eye: 10 px ink dot at top 8, right 8.

There is no collision detection or fail state; the session always ends at 32 s.

### F5. Summary
- **Auto countdown:** starts at 10 and decrements every 1 s. At 0 it calls `again()` (hands-free replay).
- **Countdown fill:** the Play-again volt fill width = `(1 − count/10)`, animated linearly over 1 s per step.
- **CANCEL AUTO:** stops the countdown and hides both itself and the " · n" suffix.
- **Return to hub:** → Hub.

### F6. Leaderboard and Settings
- **Leaderboard tabs:** swap the data and accent instantly. Nothing is editable.
- **Settings:** the toggle, sliders and locks update state instantly.

### F7. Not present in the prototype (do not add)
- Empty states
- Network loading
- Error dialogs
- Onboarding
- Accounts
- Sounds and haptics

---

## G. GODOT ARCHITECTURE (Godot 4)

**Project settings:**
- Base viewport 390×844, portrait.
- `stretch/mode = canvas_items`, `stretch/aspect = expand`, so extra height and width go to the expanding regions.
- One `Theme.tres` holding the tokens:
  - Colours as constants.
  - Font variations: `display`, `sans`, `sans_semibold`, `sans_bold`, `mono`, `mono_bold`.
  - StyleBoxFlat entries: `line_border_1`, `panel_card`, `accent_fill`, `locked_fill`. All with 0 radius.
- `Tokens.gd` autoload: palette, `MODES`, `LEADERBOARD`, `PLAYER`, `WEEK`, `fmt_time()`, and a thousands formatter.

```
Main.tscn (Control, full rect; script: App state machine; signals from screens)
└─ ScreenHost (Control)  — instance one screen at a time (queue_free old; new instance == fresh run)
screens/
  Hub.tscn         MarginContainer(64/20/20/20) → VBoxContainer
                   ├ IdentityBar.tscn (HBox)
                   ├ WeekStrip.tscn (PanelContainer → HBox; bars = HBox of VBox[ColorRect,Label])
                   ├ DailyChallengeCard.tscn (Button w/ flat style → HBox; ProgressRing custom Control)
                   ├ SectionHeading.tscn (HBox: Label, HSeparator-styled ColorRect expand, Label)
                   └ ScrollContainer(expand, scrollbars hidden) → VBox[GameRow×3, spacer(expand), Wordmark]
  Calibrate.tscn   Control layers: TextureRect(radial) · Stripes(ColorRect+shader) · FrameGuide(custom _draw + Skeleton child)
                   · TopBar(MarginContainer→HBox) · BottomPanel(MarginContainer→VBox, ProgressBar)  + Timer/Tween logic
  Play.tscn        Control(gui_input → pause) · GameCanvas(Dino/Lane/Flappy .tscn, Node2D or Control w/ _draw)
                   · HUD(VBox over GradientTexture) · RepFlash(scene instanced per event, AnimationPlayer "pop")
                   · PipCamera(Panel + Skeleton) · PrimedOverlay · PauseHint · PausedOverlay(ColorRect mouse_filter=STOP)
  Summary.tscn     ScrollContainer → VBox (Labels, GridContainer 2 cols of StatCell, Banner, actions) + countdown Timer
  Leaderboard.tscn VBox: PageHeader · ModeTabs(GridContainer 3) · Podium(HBox 3, bottom-aligned) · ScrollContainer→LeaderboardTable
  Settings.tscn    ScrollContainer → VBox: PageHeader · SegmentedToggle · SensitivitySlider×3 (HSlider) · LockRow×3
components/
  IconButton.tscn (Button 40×40, icon TextureRect/_draw, hover/pressed via Tween scale 0.95)
  PageHeader.tscn · HexBadge (custom _draw polygon) · ProgressRing (_draw_arc) · GameRow.tscn (VBox; body Control with
  clip_contents + Tween custom_minimum_size.y 300 ms) · StartButton · Skeleton.gd (Control, _draw, props mode/phase/color/missing)
  StatCell · Banner · ModeTabs · PodiumColumn · LeaderRow · SegmentedToggle · SensitivitySlider · LockRow · Wordmark · FlatProgressBar
shaders/ stripes.gdshader (−45°, 12 px period, 2 px white@0.05), inner_glow.gdshader (Calibrate frame)
```

**Node mapping:**

| Prototype pattern | Godot node |
|---|---|
| Flex column / row | VBoxContainer / HBoxContainer, using `separation` for gaps |
| Grid | GridContainer (for equal columns, set each child's `size_flags_horizontal = EXPAND_FILL`) |
| Absolute overlays | Control with anchors/offsets |
| Scroll | ScrollContainer (scrollbar hidden) |
| Buttons | Button with flat StyleBoxes, or `TextureButton`; press scale via Tween with `pivot_offset` = centre |
| Progress bars | ProgressBar with StyleBoxFlat bg/fill, or ColorRects |
| Ring and pose figure | Custom `_draw()` |
| Pop / bob / pulse animations | AnimationPlayer or Tween |
| Rich coloured inline text | RichTextLabel (bbcode), or an HBox of Labels |

---

## 8. RESPONSIVENESS
**Fixed sizes** (don't scale beyond the global stretch):
- Icon buttons 40.
- Hex badge 44.
- Ring 56, play block 36×56.
- Move preview 72×88.
- PIP 96×144.
- Podium badges 48, table badges 32.
- Bar-chart height 64 (max bar 46).
- Podium block heights.
- All font sizes and paddings.

**Expanding elements:**
- **Width:** name block, WeekStrip chart, daily text column, section rule, game-row text column (truncates), Start button, table middle column, sliders, toggle and tab columns, Return-to-hub button.
- **Height:** Hub game ScrollArea (absorbs spare height; the wordmark sits at its bottom), Leaderboard table scroll, and the Summary/Settings spacer before the bottom actions.

**Anchored elements:**
- **Calibrate:** the frame guide stretches to fill (insets 32 / 128 / 32 / 260); the top bar and bottom panel stay pinned.
- **Play:**
  - Pinned: HUD to the top, PIP to the bottom-right, rep badge at 44% of the height.
  - Proportional: game object positions are % of screen width/height (obstacle x, lane centres at thirds, ground at 26%, bird at 20%/y%).

**Screen sizes:**
- **Short screens** (< 844): Hub, Settings and Summary scroll; Leaderboard's table scrolls.
- **Wide or tablet:** with `expand`, content widens. Optionally cap the content width at 390 and centre it, which mirrors the desktop frame.

**Safe area:** the 64 px top padding is the prototype's camera-bump clearance. In Godot, use `max(64, DisplayServer.get_display_safe_area().top + 16)` for the top and the safe-area bottom for the bottom. Play's HUD uses 56 and the pause hint 36, both relative to the safe area.

---

## Verification (after writing `docs/GODOT_HANDOFF.md`)
1. Cross-check each token and value against `src/index.css` and `src/components/*.tsx`: colours, sizes, the timings 1.8 s / 3.8 s / 1 s / 0.35 s / 32 s / 10 s, the pop, bob and pulse keyframes, and the skeleton formulas.
2. Walk the preview:
   - Hub → Start → Calibrate stages → Play (first rep starts, pause/resume/end) → Summary (countdown, cancel, again).
   - Leaderboard tabs.
   - Settings toggles/sliders/locks, then confirm the effect on the Hub rows and Daily card.
3. Confirm no UI files changed (`git status` shows only `docs/`).
