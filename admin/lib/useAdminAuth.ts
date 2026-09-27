"use client";

import { useEffect, useState } from "react";
import { onAuthStateChanged, User } from "firebase/auth";
import { doc, getDoc } from "firebase/firestore";
import { auth, db } from "./firebase";

export type AdminAuthState = {
  user: User | null;
  isAdmin: boolean;
  loading: boolean;
};

// Mirrors firestore.rules: only uids present in admins/{uid} may write
// app_config, so that's the same check we use to gate the dashboard UI.
export function useAdminAuth(): AdminAuthState {
  const [state, setState] = useState<AdminAuthState>({
    user: null,
    isAdmin: false,
    loading: true,
  });

  useEffect(() => {
    return onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setState({ user: null, isAdmin: false, loading: false });
        return;
      }
      const adminDoc = await getDoc(doc(db, "admins", user.uid));
      setState({ user, isAdmin: adminDoc.exists(), loading: false });
    });
  }, []);

  return state;
}
