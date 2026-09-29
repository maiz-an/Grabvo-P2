/**
 * certs.ts — self-signed TLS cert for this agent's HTTPS listener.
 *
 * Not related to QZ Tray's own certificate/signing (src/qz.ts still
 * calls the same /digital-certificate.txt + /sign-message endpoints
 * for that, untouched). This is a *separate*, self-signed cert whose
 * only job is to let the agent's own HTTP API run over HTTPS, so a
 * phone on an HTTPS page (the Grabvo-Qz web app) isn't blocked from
 * reaching it by mixed-content / Private Network Access rules.
 *
 * Generated once on first run, covering "localhost", "127.0.0.1", and
 * every non-internal IPv4 address this machine currently has (so it's
 * valid for whatever LAN IP the agent gets reached at). Regenerated
 * automatically if the machine's IPs change (e.g. after a DHCP lease
 * renewal) or the existing cert has expired.
 */
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import selfsigned from "selfsigned";
import { config } from "./config";
import { logger } from "./logger";

const CERT_FILE = () => path.join(config.certDir, "agent-cert.pem");
const KEY_FILE = () => path.join(config.certDir, "agent-key.pem");
const META_FILE = () => path.join(config.certDir, "agent-cert.meta.json");

function currentLanIps(): string[] {
  const ips: string[] = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name] || []) {
      if (iface.family === "IPv4" && !iface.internal) ips.push(iface.address);
    }
  }
  return ips.sort();
}

function generate(): { cert: string; key: string } {
  const ips = currentLanIps();
  const altNames = [
    { type: 2, value: "localhost" }, // DNS
    { type: 7, ip: "127.0.0.1" }, // IP
    ...ips.map((ip) => ({ type: 7, ip })),
  ];

  const pems = selfsigned.generate(
    [{ name: "commonName", value: "GrabvoPrintPing" }],
    {
      days: 3650,
      keySize: 2048,
      algorithm: "sha256",
      extensions: [
        { name: "basicConstraints", cA: false },
        { name: "keyUsage", keyEncipherment: true, digitalSignature: true },
        { name: "extKeyUsage", serverAuth: true },
        { name: "subjectAltName", altNames },
      ],
    }
  );

  fs.mkdirSync(config.certDir, { recursive: true });
  fs.writeFileSync(CERT_FILE(), pems.cert);
  fs.writeFileSync(KEY_FILE(), pems.private);
  fs.writeFileSync(META_FILE(), JSON.stringify({ ips, generatedAt: new Date().toISOString() }, null, 2));

  logger.info(`Generated a self-signed HTTPS certificate for: localhost, 127.0.0.1${ips.length ? ", " + ips.join(", ") : ""}`);
  return { cert: pems.cert, key: pems.private };
}

function needsRegeneration(): boolean {
  if (!fs.existsSync(CERT_FILE()) || !fs.existsSync(KEY_FILE())) return true;
  try {
    const meta = JSON.parse(fs.readFileSync(META_FILE(), "utf8")) as { ips: string[] };
    const known = new Set(meta.ips || []);
    const current = currentLanIps();
    // Regenerate if the machine picked up an IP the cert doesn't cover
    // (e.g. new network, DHCP renewal). Losing an old IP isn't a reason
    // to regenerate — it just means that address is unused now.
    return current.some((ip) => !known.has(ip));
  } catch {
    return true;
  }
}

/** Loads (generating if needed/stale) the cert+key for the HTTPS server. */
export function getOrCreateCert(): { cert: string; key: string } {
  if (needsRegeneration()) return generate();
  return {
    cert: fs.readFileSync(CERT_FILE(), "utf8"),
    key: fs.readFileSync(KEY_FILE(), "utf8"),
  };
}
