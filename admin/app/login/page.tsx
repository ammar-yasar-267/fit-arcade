"use client";

import { useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { signInWithEmailAndPassword } from "firebase/auth";
import { auth } from "@/lib/firebase";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setSubmitting(true);
    try {
      await signInWithEmailAndPassword(auth, email, password);
      router.replace("/dashboard");
    } catch {
      setError("Couldn't sign in — check the email and password.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex flex-1 items-center justify-center px-6">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm rounded-3xl border border-border-soft bg-surface p-8 shadow-[0_0_60px_-15px_rgba(6,182,212,0.25)]"
      >
        <div className="mb-8 flex flex-col items-center text-center">
          <span className="text-3xl">🕹️</span>
          <h1 className="font-display mt-2 text-2xl font-bold tracking-tight text-cyan">
            FitArcade
          </h1>
          <p className="mt-1 text-sm text-text-secondary">Admin control panel</p>
        </div>

        <label className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-text-secondary">
          Email
        </label>
        <input
          type="email"
          required
          autoFocus
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="mb-4 w-full rounded-xl border border-border-soft bg-void px-3.5 py-2.5 text-sm text-text-primary placeholder:text-text-secondary/50 focus:border-cyan"
        />

        <label className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-text-secondary">
          Password
        </label>
        <input
          type="password"
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="mb-6 w-full rounded-xl border border-border-soft bg-void px-3.5 py-2.5 text-sm text-text-primary focus:border-cyan"
        />

        {error && (
          <p className="mb-4 rounded-lg border border-red/30 bg-red/10 px-3 py-2 text-sm text-red">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded-xl bg-cyan px-4 py-2.5 text-sm font-semibold text-[#04101a] transition-colors hover:bg-cyan-hover disabled:opacity-50"
        >
          {submitting ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}
