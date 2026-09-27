"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAdminAuth } from "@/lib/useAdminAuth";

export default function Home() {
  const { user, loading } = useAdminAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    router.replace(user ? "/dashboard" : "/login");
  }, [loading, user, router]);

  return (
    <div className="flex flex-1 items-center justify-center gap-3 text-text-secondary">
      <span className="h-2 w-2 animate-ping rounded-full bg-cyan" />
      Loading…
    </div>
  );
}
