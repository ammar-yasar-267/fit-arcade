"use client";

import { useRouter, usePathname } from "next/navigation";
import Link from "next/link";
import { useEffect } from "react";
import { signOut } from "firebase/auth";
import { auth } from "@/lib/firebase";
import { useAdminAuth } from "@/lib/useAdminAuth";

const NAV_LINKS = [
  { href: "/dashboard", label: "Switches", icon: "🎛️" },
  { href: "/leaderboards", label: "Leaderboards", icon: "🏆" },
  { href: "/profiles", label: "Profiles", icon: "🪪" },
];

export default function AdminShell({ children }: { children: React.ReactNode }) {
  const { user, isAdmin, loading } = useAdminAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (!loading && !user) router.replace("/login");
  }, [loading, user, router]);

  if (loading) {
    return (
      <div className="flex flex-1 items-center justify-center gap-3 text-text-secondary">
        <span className="h-2 w-2 animate-ping rounded-full bg-cyan" />
        Loading…
      </div>
    );
  }

  if (!user) return null;

  if (!isAdmin) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
        <span className="text-4xl">🚫</span>
        <p className="text-lg font-medium">
          {user.email} is signed in but isn&apos;t an admin.
        </p>
        <p className="max-w-sm text-sm text-text-secondary">
          Ask an existing admin to add your uid to the{" "}
          <code className="rounded bg-surface px-1.5 py-0.5 text-cyan">admins</code>{" "}
          collection in Firestore.
        </p>
        <button
          onClick={() => signOut(auth)}
          className="rounded-full border border-border-soft px-4 py-2 text-sm hover:bg-surface"
        >
          Sign out
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <header className="sticky top-0 z-10 border-b border-border-soft bg-void/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-3.5">
          <div className="flex items-center gap-8">
            <Link href="/dashboard" className="flex items-center gap-2">
              <span className="text-xl">🕹️</span>
              <span className="font-display text-base font-bold tracking-tight text-cyan">
                FitArcade
              </span>
            </Link>
            <nav className="flex gap-1">
              {NAV_LINKS.map((link) => {
                const active = pathname === link.href;
                return (
                  <Link
                    key={link.href}
                    href={link.href}
                    className={`flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors ${
                      active
                        ? "bg-cyan/15 text-cyan"
                        : "text-text-secondary hover:bg-surface hover:text-text-primary"
                    }`}
                  >
                    <span className="text-xs">{link.icon}</span>
                    {link.label}
                  </Link>
                );
              })}
            </nav>
          </div>
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-text-secondary sm:inline">
              {user.email}
            </span>
            <button
              onClick={() => signOut(auth)}
              className="rounded-full border border-border-soft px-3.5 py-1.5 text-sm text-text-secondary transition-colors hover:border-red/40 hover:text-red"
            >
              Sign out
            </button>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-6 py-10">{children}</main>
    </div>
  );
}
