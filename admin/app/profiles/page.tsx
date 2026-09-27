"use client";

import { useEffect, useMemo, useState } from "react";
import {
  collection,
  query,
  orderBy,
  limit,
  getDocs,
  doc,
  getDoc,
} from "firebase/firestore";
import { db } from "@/lib/firebase";
import AdminShell from "@/components/AdminShell";

type Profile = {
  uid: string;
  display_name: string;
  display_tag: string;
  badge?: string;
  created_at: string;
  last_seen_at: string;
};

function ProfileCard({ profile, highlight }: { profile: Profile; highlight?: boolean }) {
  const tag = profile.display_tag?.split("#")[1] ?? "";
  return (
    <div
      className={`flex items-center gap-4 rounded-xl border px-4 py-3 ${
        highlight ? "border-cyan/40 bg-cyan/5" : "border-border-soft bg-surface"
      }`}
    >
      <span className="text-2xl">{profile.badge || "🎮"}</span>
      <div className="flex-1">
        <div>
          <span className="font-medium">{profile.display_name}</span>{" "}
          <span className="text-text-secondary">#{tag}</span>
        </div>
        <div className="mt-0.5 flex flex-wrap gap-x-3 text-xs text-text-secondary">
          <span>Created {profile.created_at}</span>
          <span>Last seen {profile.last_seen_at}</span>
        </div>
      </div>
      <span className="rounded-full bg-white/5 px-2.5 py-1 font-mono text-[11px] text-text-secondary">
        {profile.uid}
      </span>
    </div>
  );
}

function ProfilesContent() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [directHit, setDirectHit] = useState<Profile | null>(null);
  const [directLookupDone, setDirectLookupDone] = useState(false);

  useEffect(() => {
    (async () => {
      const q = query(
        collection(db, "profiles"),
        orderBy("last_seen_at", "desc"),
        limit(200)
      );
      const snap = await getDocs(q);
      setProfiles(
        snap.docs.map((d) => ({ uid: d.id, ...(d.data() as object) }) as Profile)
      );
      setLoading(false);
    })();
  }, []);

  const filtered = useMemo(() => {
    const f = search.trim().toLowerCase();
    if (!f) return profiles;
    return profiles.filter(
      (p) =>
        p.display_name?.toLowerCase().includes(f) ||
        p.display_tag?.toLowerCase().includes(f) ||
        p.uid.toLowerCase().includes(f)
    );
  }, [profiles, search]);

  // If the recent-200 list has nothing, fall back to an exact uid lookup —
  // covers players who claimed a card a while ago and dropped off the list.
  useEffect(() => {
    const term = search.trim();
    setDirectHit(null);
    setDirectLookupDone(false);
    if (!term || filtered.length > 0) return;
    let cancelled = false;
    (async () => {
      const snap = await getDoc(doc(db, "profiles", term));
      if (cancelled) return;
      setDirectHit(snap.exists() ? ({ uid: snap.id, ...(snap.data() as object) } as Profile) : null);
      setDirectLookupDone(true);
    })();
    return () => {
      cancelled = true;
    };
  }, [search, filtered.length]);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight">Profiles</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Search by name, tag, or uid — cherry-pick a specific player.
        </p>
      </div>

      <input
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search name, tag, or paste a uid…"
        autoFocus
        className="w-full rounded-xl border border-border-soft bg-surface px-4 py-3 text-sm focus:border-cyan"
      />

      {loading ? (
        <div className="flex items-center gap-3 py-10 text-text-secondary">
          <span className="h-2 w-2 animate-ping rounded-full bg-cyan" />
          Loading…
        </div>
      ) : filtered.length > 0 ? (
        <div className="flex flex-col gap-2">
          <span className="text-xs font-medium uppercase tracking-wide text-text-secondary">
            {filtered.length} match{filtered.length === 1 ? "" : "es"}
          </span>
          {filtered.map((p) => (
            <ProfileCard key={p.uid} profile={p} />
          ))}
        </div>
      ) : search.trim() && directHit ? (
        <div className="flex flex-col gap-2">
          <span className="text-xs font-medium uppercase tracking-wide text-cyan">
            Found via direct uid lookup
          </span>
          <ProfileCard profile={directHit} highlight />
        </div>
      ) : search.trim() && directLookupDone ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-border-soft py-16 text-center">
          <span className="text-3xl">🕵️</span>
          <p className="text-text-secondary">No player matches &quot;{search}&quot;.</p>
        </div>
      ) : search.trim() ? (
        <div className="py-10 text-center text-text-secondary">Searching…</div>
      ) : (
        <div className="flex flex-col gap-2">
          <span className="text-xs font-medium uppercase tracking-wide text-text-secondary">
            {profiles.length} most recent players
          </span>
          {profiles.map((p) => (
            <ProfileCard key={p.uid} profile={p} />
          ))}
        </div>
      )}
    </div>
  );
}

export default function ProfilesPage() {
  return (
    <AdminShell>
      <ProfilesContent />
    </AdminShell>
  );
}
