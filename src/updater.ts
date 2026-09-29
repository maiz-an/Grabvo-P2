/**
 * updater.ts — self-update, source-based (no GitHub Releases, no .exe
 * distribution), per spec section 8.
 *
 * Flow: check version.txt -> download branch tarball -> extract to a
 * staging dir -> validate its version.txt matches -> npm install +
 * build in staging -> wait for any in-flight print job to finish ->
 * atomically swap staging in, old files kept in .update-backup ->
 * exit so the OS service manager restarts into the new build.
 *
 * If anything before the swap fails, the currently-running agent is
 * completely untouched — staging/download artifacts are just deleted.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { config } from "./config";
import { logger } from "./logger";
import { getLocalVersion } from "./version";
import { isBusy } from "./jobLock";

const ROOT = path.resolve(__dirname, "..");
const STAGING_DIR = path.join(ROOT, ".update-staging");
const BACKUP_DIR = path.join(ROOT, ".update-backup");
const DOWNLOAD_FILE = path.join(ROOT, ".update-download.tar.gz");

const KEEP_OUT_OF_BACKUP = new Set([
  ".update-staging",
  ".update-backup",
  ".update-download.tar.gz",
  "node_modules",
  "dist",
  ".git",
]);

function remoteVersionUrl(): string {
  return `https://raw.githubusercontent.com/${config.updateRepoOwner}/${config.updateRepoName}/${config.updateBranch}/version.txt`;
}

function tarballUrl(): string {
  return `https://codeload.github.com/${config.updateRepoOwner}/${config.updateRepoName}/tar.gz/refs/heads/${config.updateBranch}`;
}

export async function fetchRemoteVersion(): Promise<string | null> {
  try {
    const res = await fetch(remoteVersionUrl(), { headers: { "Cache-Control": "no-store" } });
    if (!res.ok) return null;
    return (await res.text()).trim();
  } catch {
    return null;
  }
}

/** Simple dotted-numeric version compare (1.2.10 > 1.2.9). Falls back
 *  to "different string = update" if either side isn't numeric. */
function isNewer(remote: string, local: string): boolean {
  if (remote === local) return false;
  const toParts = (v: string) => v.split(".").map((n) => parseInt(n, 10));
  const r = toParts(remote);
  const l = toParts(local);
  if (r.some(Number.isNaN) || l.some(Number.isNaN)) return remote !== local;
  for (let i = 0; i < Math.max(r.length, l.length); i++) {
    const rv = r[i] || 0;
    const lv = l[i] || 0;
    if (rv !== lv) return rv > lv;
  }
  return false;
}

function rmrf(p: string): void {
  fs.rmSync(p, { recursive: true, force: true });
}

async function downloadTarball(): Promise<void> {
  const res = await fetch(tarballUrl());
  if (!res.ok) throw new Error(`Download failed (HTTP ${res.status})`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(DOWNLOAD_FILE, buf);
}

function extractTarball(): void {
  rmrf(STAGING_DIR);
  fs.mkdirSync(STAGING_DIR, { recursive: true });
  // --strip-components=1 drops the "<repo>-<branch>/" wrapper folder
  // GitHub's tarballs always have. Requires `tar` on PATH — present by
  // default on Linux, macOS, and Windows 10 (build 1803+) / Windows 11.
  execFileSync("tar", ["-xzf", DOWNLOAD_FILE, "-C", STAGING_DIR, "--strip-components=1"]);
}

function validateStaging(expectedVersion: string): void {
  const versionFile = path.join(STAGING_DIR, "version.txt");
  const pkgFile = path.join(STAGING_DIR, "package.json");
  if (!fs.existsSync(versionFile) || !fs.existsSync(pkgFile)) {
    throw new Error("Downloaded update is missing version.txt or package.json");
  }
  const downloadedVersion = fs.readFileSync(versionFile, "utf8").trim();
  if (downloadedVersion !== expectedVersion) {
    throw new Error(
      `Downloaded version.txt (${downloadedVersion}) doesn't match the version.txt this check saw (${expectedVersion}) — GitHub may have moved under us, aborting`
    );
  }
}

function installAndBuild(): void {
  const npmCmd = process.platform === "win32" ? "npm.cmd" : "npm";
  const hasLock = fs.existsSync(path.join(STAGING_DIR, "package-lock.json"));
  const installArgs = hasLock ? ["ci", "--omit=dev"] : ["install", "--omit=dev"];

  const install = spawnSync(npmCmd, installArgs, { cwd: STAGING_DIR, stdio: "inherit" });
  if (install.status !== 0) throw new Error("npm install failed while preparing the update");

  const build = spawnSync(npmCmd, ["run", "build"], { cwd: STAGING_DIR, stdio: "inherit" });
  if (build.status !== 0) throw new Error("Build failed while preparing the update");
}

async function waitUntilIdle(timeoutMs: number): Promise<boolean> {
  const start = Date.now();
  while (isBusy()) {
    if (Date.now() - start > timeoutMs) return false;
    await new Promise((r) => setTimeout(r, 2000));
  }
  return true;
}

function swapIn(): void {
  rmrf(BACKUP_DIR);
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  for (const entry of fs.readdirSync(ROOT)) {
    if (KEEP_OUT_OF_BACKUP.has(entry)) continue;
    fs.renameSync(path.join(ROOT, entry), path.join(BACKUP_DIR, entry));
  }
  for (const entry of fs.readdirSync(STAGING_DIR)) {
    fs.renameSync(path.join(STAGING_DIR, entry), path.join(ROOT, entry));
  }
  rmrf(STAGING_DIR);
  rmrf(DOWNLOAD_FILE);
}

export async function checkAndApplyUpdate(): Promise<void> {
  if (!config.autoUpdate) return;

  const remote = await fetchRemoteVersion();
  const local = getLocalVersion();
  if (!remote) {
    logger.warn("Could not reach GitHub to check for updates this cycle; will retry next interval");
    return;
  }
  if (!isNewer(remote, local)) return;

  logger.info(`Update available: ${local} -> ${remote}. Downloading...`);
  try {
    await downloadTarball();
    extractTarball();
    validateStaging(remote);
    installAndBuild();

    const idle = await waitUntilIdle(5 * 60 * 1000);
    if (!idle) {
      logger.warn("Print jobs kept coming for 5+ minutes — deferring this update to the next check cycle");
      rmrf(STAGING_DIR);
      rmrf(DOWNLOAD_FILE);
      return;
    }

    swapIn();
    logger.info(`Updated to ${remote}. Exiting so the service manager restarts into the new build...`);
    // If the new build fails to start, .update-backup/ still holds the
    // previous working install for manual recovery — nothing here
    // deletes it automatically.
    process.exit(0);
  } catch (err) {
    logger.error("Update failed — leaving the currently running version untouched:", (err as Error)?.message || err);
    rmrf(STAGING_DIR);
    rmrf(DOWNLOAD_FILE);
  }
}

export function scheduleUpdateChecks(): void {
  if (!config.autoUpdate) {
    logger.info("Auto-update disabled (AUTO_UPDATE=false)");
    return;
  }
  const intervalMs = Math.max(5, config.updateCheckIntervalMinutes) * 60 * 1000;
  setInterval(() => {
    checkAndApplyUpdate().catch((err) => logger.error("Update check crashed:", err));
  }, intervalMs);
  // First check happens shortly after startup, not immediately, so it
  // never races the very first print job right as the service comes up.
  setTimeout(() => {
    checkAndApplyUpdate().catch((err) => logger.error("Update check crashed:", err));
  }, 60 * 1000);
}
