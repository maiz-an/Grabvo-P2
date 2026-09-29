import fs from "node:fs";
import path from "node:path";

/**
 * Local version comes from version.txt sitting next to this project's
 * root (same file the GitHub repo's version.txt is compared against),
 * NOT from package.json — per spec, version.txt is the single source
 * of truth for update checks.
 */
export function getLocalVersion(): string {
  const candidates = [
    path.join(__dirname, "..", "version.txt"), // dist/../version.txt (built)
    path.join(process.cwd(), "version.txt"),
  ];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return fs.readFileSync(p, "utf8").trim();
    } catch {
      /* try next candidate */
    }
  }
  return "0.0.0";
}
