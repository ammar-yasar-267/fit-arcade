"use client";

import { useEffect, useState } from "react";
import { doc, getDoc, setDoc, serverTimestamp } from "firebase/firestore";
import { db } from "@/lib/firebase";
import { useAdminAuth } from "@/lib/useAdminAuth";
import AdminShell from "@/components/AdminShell";

type GameModes = { dino: boolean; switcher: boolean; flappy: boolean };
type Settings = {
  arm_raise_start_max: number;
  arm_raise_end_min: number;
  calibration_timeout_s: number;
};

const GAMES: { id: keyof GameModes; name: string; exercise: string; icon: string; accent: string }[] = [
  { id: "dino", name: "Chrome Dino", exercise: "Jumping Jacks", icon: "🦖", accent: "#F59E0B" },
  { id: "switcher", name: "Lane Switcher", exercise: "Lunges", icon: "🏃", accent: "#22C55E" },
  { id: "flappy", name: "Flappy Bird", exercise: "Arm Raises", icon: "🐤", accent: "#06B6D4" },
];

const DEFAULT_GAME_MODES: GameModes = { dino: true, switcher: true, flappy: true };
const DEFAULT_SETTINGS: Settings = {
  arm_raise_start_max: 48,
  arm_raise_end_min: 130,
  calibration_timeout_s: 1.5,
};

function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative h-7 w-12 shrink-0 rounded-full transition-colors ${
        checked ? "bg-green" : "bg-white/10"
      }`}
    >
      <span
        className={`absolute top-0.5 left-0.5 h-6 w-6 rounded-full bg-white shadow transition-transform ${
          checked ? "translate-x-5" : "translate-x-0"
        }`}
      />
    </button>
  );
}

function DashboardContent() {
  const { user } = useAdminAuth();
  const [loading, setLoading] = useState(true);
  const [maintenanceMode, setMaintenanceMode] = useState(false);
  const [gameModes, setGameModes] = useState<GameModes>(DEFAULT_GAME_MODES);
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [saved, setSaved] = useState({ maintenanceMode, gameModes, settings });
  const [saving, setSaving] = useState(false);
  const [justSaved, setJustSaved] = useState(false);
  const [metaLine, setMetaLine] = useState<string | null>(null);

  const isDirty =
    JSON.stringify(saved) !== JSON.stringify({ maintenanceMode, gameModes, settings });

  useEffect(() => {
    (async () => {
      const snap = await getDoc(doc(db, "app_config", "global"));
      if (snap.exists()) {
        const data = snap.data();
        const nextMaintenance = !!data.maintenance_mode;
        const nextModes = { ...DEFAULT_GAME_MODES, ...data.game_modes };
        const nextSettings = { ...DEFAULT_SETTINGS, ...data.settings };
        setMaintenanceMode(nextMaintenance);
        setGameModes(nextModes);
        setSettings(nextSettings);
        setSaved({ maintenanceMode: nextMaintenance, gameModes: nextModes, settings: nextSettings });
        if (data.updated_by) {
          setMetaLine(`Last changed by ${data.updated_by}`);
        }
      }
      setLoading(false);
    })();
  }, []);

  async function handleSave() {
    setSaving(true);
    await setDoc(
      doc(db, "app_config", "global"),
      {
        maintenance_mode: maintenanceMode,
        game_modes: gameModes,
        settings,
        updated_by: user?.email ?? "unknown",
        updated_at: serverTimestamp(),
      },
      { merge: true }
    );
    setSaved({ maintenanceMode, gameModes, settings });
    setMetaLine(`Last changed by ${user?.email ?? "unknown"}`);
    setSaving(false);
    setJustSaved(true);
    setTimeout(() => setJustSaved(false), 2500);
  }

  function handleDiscard() {
    setMaintenanceMode(saved.maintenanceMode);
    setGameModes(saved.gameModes);
    setSettings(saved.settings);
  }

  if (loading) {
    return (
      <div className="flex items-center gap-3 text-text-secondary">
        <span className="h-2 w-2 animate-ping rounded-full bg-cyan" />
        Loading config…
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-10 pb-20">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight">Switches</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Players pick this up within ~8 seconds — the app polls for changes while
          sitting on the home screen.
          {metaLine && <span className="text-text-secondary/70"> · {metaLine}</span>}
        </p>
      </div>

      {/* Maintenance mode gets its own prominent, color-shifting card since it's the "break glass" switch */}
      <section
        className={`rounded-2xl border p-5 transition-colors ${
          maintenanceMode
            ? "border-red/40 bg-red/10"
            : "border-border-soft bg-surface"
        }`}
      >
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <span className="text-2xl">{maintenanceMode ? "🚧" : "✅"}</span>
            <div>
              <p className="font-medium">Maintenance mode</p>
              <p className="text-sm text-text-secondary">
                {maintenanceMode
                  ? "Play is blocked — players see a maintenance banner."
                  : "Everything is running normally."}
              </p>
            </div>
          </div>
          <Toggle checked={maintenanceMode} onChange={setMaintenanceMode} />
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-text-secondary">Game modes</h2>
        <div className="grid gap-3 sm:grid-cols-3">
          {GAMES.map((game) => {
            const enabled = gameModes[game.id];
            return (
              <div
                key={game.id}
                className="flex flex-col gap-3 rounded-2xl border border-border-soft bg-surface p-4"
                style={{ borderTopColor: game.accent, borderTopWidth: 3 }}
              >
                <div className="flex items-start justify-between">
                  <div>
                    <div className="text-2xl">{game.icon}</div>
                    <p className="mt-1.5 font-medium">{game.name}</p>
                    <p className="text-xs text-text-secondary">{game.exercise}</p>
                  </div>
                  <Toggle
                    checked={enabled}
                    onChange={(v) => setGameModes((g) => ({ ...g, [game.id]: v }))}
                  />
                </div>
                <span
                  className={`w-fit rounded-full px-2.5 py-0.5 text-xs font-medium ${
                    enabled ? "bg-green/15 text-green" : "bg-white/5 text-text-secondary"
                  }`}
                >
                  {enabled ? "Live" : "Disabled"}
                </span>
              </div>
            );
          })}
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-text-secondary">Gameplay settings</h2>
        <div className="grid grid-cols-1 gap-4 rounded-2xl border border-border-soft bg-surface p-5 sm:grid-cols-3">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-text-secondary">
              Arm raise start max (°)
            </label>
            <input
              type="number"
              value={settings.arm_raise_start_max}
              onChange={(e) =>
                setSettings((s) => ({ ...s, arm_raise_start_max: Number(e.target.value) }))
              }
              className="w-full rounded-lg border border-border-soft bg-void px-3 py-2 text-sm focus:border-cyan"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-medium text-text-secondary">
              Arm raise end min (°)
            </label>
            <input
              type="number"
              value={settings.arm_raise_end_min}
              onChange={(e) =>
                setSettings((s) => ({ ...s, arm_raise_end_min: Number(e.target.value) }))
              }
              className="w-full rounded-lg border border-border-soft bg-void px-3 py-2 text-sm focus:border-cyan"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-medium text-text-secondary">
              Calibration timeout (s)
            </label>
            <input
              type="number"
              step="0.1"
              value={settings.calibration_timeout_s}
              onChange={(e) =>
                setSettings((s) => ({ ...s, calibration_timeout_s: Number(e.target.value) }))
              }
              className="w-full rounded-lg border border-border-soft bg-void px-3 py-2 text-sm focus:border-cyan"
            />
          </div>
        </div>
      </section>

      {/* Sticky save bar — only appears once something actually changed, so it never nags */}
      {(isDirty || justSaved) && (
        <div className="fixed inset-x-0 bottom-0 z-20 border-t border-border-soft bg-void/95 backdrop-blur-md">
          <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-6 py-4">
            <span className="text-sm text-text-secondary">
              {justSaved ? (
                <span className="text-green">✓ Saved</span>
              ) : (
                "You have unsaved changes"
              )}
            </span>
            {isDirty && (
              <div className="flex gap-3">
                <button
                  onClick={handleDiscard}
                  className="rounded-full px-4 py-2 text-sm text-text-secondary hover:text-text-primary"
                >
                  Discard
                </button>
                <button
                  onClick={handleSave}
                  disabled={saving}
                  className="rounded-full bg-cyan px-5 py-2 text-sm font-semibold text-[#04101a] hover:bg-cyan-hover disabled:opacity-50"
                >
                  {saving ? "Saving…" : "Save changes"}
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function DashboardPage() {
  return (
    <AdminShell>
      <DashboardContent />
    </AdminShell>
  );
}
