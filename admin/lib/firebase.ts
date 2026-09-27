import { initializeApp, getApps, getApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

// Public client identifiers — safe to ship in the bundle. Access is
// enforced by firestore.rules (only uids listed in the `admins`
// collection can write app_config), not by hiding this config.
const firebaseConfig = {
  apiKey: "AIzaSyD_kM-u7mFiOEPDXJ4FFNGMXI2xNc6SnaE",
  authDomain: "fitarcade-app.firebaseapp.com",
  projectId: "fitarcade-app",
  storageBucket: "fitarcade-app.firebasestorage.app",
  messagingSenderId: "1062625300261",
  appId: "1:1062625300261:web:1f062890c0de07a175d4cc",
};

export const app = getApps().length ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
