"use client";

import { useEffect, useState } from "react";
import {
  collection,
  query,
  where,
  orderBy,
  limit,
  getDocs,
} from "firebase/firestore";
import { db } from "@/lib/firebase";
import AdminShell from "@/components/AdminShell";

type BestScoreRow = {
  id: string;
  display_name: string;
  display_tag: string;
  score: number;
  uid: string;
};

const GAME_MODES = [
  { id: "dino", label: "Chrome Dino", icon: "🦖", accent: "#F59E0B" },
  { id: "switcher", label: "Lane Switcher", icon: "🏃", accent: "#22C55E" },
  { id: "flappy", label: "Flappy Bird", icon: "🐤", accent: "#06B6D4" },
];

const MEDALS = ["🥇", "🥈", "🥉"];

function LeaderboardsContent() {
  const [gameMode, setGameMode] = useState("dino");
  const [rows, setRows] = useState<BestScoreRow[]>([]);
  const [loading, setLoading] = useState(true);
  const activeGame = GAME_MODES.find((m) => m.id === gameMode)!;

  useEffect(() => {
    setLoading(true);
    (async () => {
      const q = query(
        collection(db, "best_scores"),
        where("game_mode", "==", gameMode),
        orderBy("score", "desc"),
        limit(50)
      );
      const snap = await getDocs(q);
      setRows(
        snap.docs.map((d) => ({
          id: d.id,
          display_name: d.data().display_name ?? "",
          display_tag: d.data().display_tag ?? "",
          score: d.data().score ?? 0,
          uid: d.data().uid ?? "",
        }))
      );
      setLoading(false);
    })();
  }, [gameMode]);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight">Leaderboards</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Top scores per game mode, one row per player.
        </p>
      </div>

      <div className="flex gap-2">
        {GAME_MODES.map((mode) => (
          <button
            key={mode.id}
            onClick={() => setGameMode(mode.id)}
            className={`flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium transition-colors ${
              gameMode === mode.id
                ? "bg-cyan/15 text-cyan"
                : "border border-border-soft text-text-secondary hover:bg-surface"
            }`}
          >
            <span>{mode.icon}</span>
            {mode.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex items-center gap-3 py-10 text-text-secondary">
          <span className="h-2 w-2 animate-ping rounded-full bg-cyan" />
          Loading…
        </div>
      ) : rows.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-border-soft py-16 text-center">
          <span className="text-3xl">{activeGame.icon}</span>
          <p className="text-text-secondary">No scores yet for {activeGame.label}.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {rows.map((row, i) => {
            const tag = row.display_tag.split("#")[1] ?? "";
            const isTop3 = i < 3;
            return (
              <div
                key={row.id}
                className={`flex items-center gap-4 rounded-xl border px-4 py-3 ${
                  isTop3
                    ? "border-yellow/30 bg-yellow/5"
                    : "border-border-soft bg-surface"
                }`}
              >
                <span className="w-8 text-center text-lg">
                  {MEDALS[i] ?? (
                    <span className="text-sm text-text-secondary">#{i + 1}</span>
                  )}
                </span>
                <div className="flex-1">
                  <span className="font-medium">{row.display_name}</span>{" "}
                  <span className="text-text-secondary">#{tag}</span>
                </div>
                <span
                  className="font-display text-lg font-bold"
                  style={{ color: isTop3 ? "#FCCB15" : "#ffffff" }}
                >
                  {row.score.toLocaleString()}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function LeaderboardsPage() {
  return (
    <AdminShell>
      <LeaderboardsContent />
    </AdminShell>
  );
}
