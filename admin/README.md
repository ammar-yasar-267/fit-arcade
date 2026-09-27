# FitArcade Admin

Control panel for [FitArcade](../README.md) — game mode switches, maintenance mode, gameplay settings, leaderboards, and player profiles. Talks directly to Firebase (Firestore + Auth); there's no separate backend server.

Live at **https://fitarcade-app.web.app**. See the root [README's Backend & Admin Panel section](../README.md#️-backend--admin-panel) for the full data model and architecture.

## Local development

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Firebase config (project ID, API key) lives in `lib/firebase.ts` — same public client identifiers used everywhere else, not secrets; access is enforced by `../firestore.rules`.

## Deploying

This app is statically exported (`next.config.ts` sets `output: "export"`) since Firebase Hosting on the Spark plan serves static files only — no Cloud Functions/Cloud Run.

```bash
npm run build        # → admin/out
cd ..
firebase deploy --only hosting
```

## Structure

- `app/login` — email/password sign-in.
- `app/dashboard` — game mode + maintenance + settings switches.
- `app/leaderboards` — top scores per game mode.
- `app/profiles` — player search (name/tag or exact uid).
- `components/AdminShell.tsx` — auth + admin-membership gate, nav shell wrapping every authenticated page.
- `lib/useAdminAuth.ts` — reads `admins/{uid}` to decide whether a signed-in user sees the dashboard or a "not an admin" screen.
