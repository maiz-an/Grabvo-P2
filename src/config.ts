/**
 * config.ts — all environment-driven settings in one place.
 * No print/business logic lives here; just transport configuration.
 */
import fs from "node:fs";
import path from "node:path";

function loadDotEnvIfPresent(): void {
  const file = path.join(process.cwd(), ".env");
  if (!fs.existsSync(file)) return;
  try {
    const lines = fs.readFileSync(file, "utf8").split("\n");
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx === -1) continue;
      const key = trimmed.slice(0, idx).trim();
      const val = trimmed.slice(idx + 1).trim();
      if (!(key in process.env)) process.env[key] = val;
    }
  } catch {
    /* .env is optional — ignore read errors and fall back to defaults */
  }
}

loadDotEnvIfPresent();

function bool(v: string | undefined, fallback: boolean): boolean {
  if (v === undefined) return fallback;
  return v.toLowerCase() === "true" || v === "1";
}

export const config = {
  port: Number(process.env.PORT) || 8765,
  host: process.env.HOST || "0.0.0.0",

  signingBaseUrl: (process.env.SIGNING_BASE_URL || "https://qz.grabvo.app").replace(/\/+$/, ""),

  allowedOrigin: process.env.ALLOWED_ORIGIN || "*",

  updateRepoOwner: process.env.UPDATE_REPO_OWNER || "maiz-an",
  updateRepoName: process.env.UPDATE_REPO_NAME || "Grabvo-P2",
  updateBranch: process.env.UPDATE_BRANCH || "main",
  autoUpdate: bool(process.env.AUTO_UPDATE, true),
  updateCheckIntervalMinutes: Number(process.env.UPDATE_CHECK_INTERVAL_MINUTES) || 360,
};
