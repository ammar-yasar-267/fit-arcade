import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Firebase Hosting (Spark plan, no Cloud Functions/Cloud Run) serves this
  // as static files, so the app is built as a static export.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
