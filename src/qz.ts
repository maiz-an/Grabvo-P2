/**
 * qz.ts — the bridge's only connection to QZ Tray.
 *
 * Uses the SAME npm package (`qz-tray`, the Node-usable build of the
 * same library the browser loads from a CDN) and the officially
 * documented Node overrides (qz.io/docs/api-overrides):
 *   - qz.api.setWebSocketType(ws)      — Node has no native WebSocket
 *   - qz.api.setPromiseType(...)       — use native Promise
 *   - qz.api.setSha256Type(...)        — Node's crypto instead of a
 *                                         browser hashing shim
 *
 * Certificate + signing: this agent points at the SAME
 * /digital-certificate.txt and /sign-message endpoints the Grabvo-Qz
 * browser app already calls (src/lib/qz.ts → setupQzSecurity()),
 * same SHA512 algorithm. The private key stays exactly where it was
 * — on that server — and never touches this agent or its filesystem.
 *
 * Nothing about print content lives in this file: it only ever
 * forwards a printerName + configOptions + data it did not build.
 */
import WebSocket from "ws";
import crypto from "node:crypto";
import qz = require("qz-tray");
import { config } from "./config";
import { logger } from "./logger";

let securityConfigured = false;

function configureOnce(): void {
  if (securityConfigured) return;
  securityConfigured = true;

  qz.api.setWebSocketType(WebSocket);
  qz.api.setPromiseType((resolver: (resolve: (v: unknown) => void, reject: (e: unknown) => void) => void) => new Promise(resolver));
  qz.api.setSha256Type((data: string) => crypto.createHash("sha256").update(data).digest("hex"));

  qz.security.setCertificatePromise((resolve: (v: string) => void, reject: (e: unknown) => void) => {
    fetch(`${config.signingBaseUrl}/digital-certificate.txt`, { headers: { "Cache-Control": "no-store" } })
      .then((r) => {
        if (!r.ok) throw new Error(`certificate fetch failed (HTTP ${r.status})`);
        return r.text();
      })
      .then(resolve)
      .catch(reject);
  });

  qz.security.setSignaturePromise(
    (toSign: string) => (resolve: (v: string) => void, reject: (e: unknown) => void) => {
      fetch(`${config.signingBaseUrl}/sign-message?request=${encodeURIComponent(toSign)}`, {
        headers: { "Cache-Control": "no-store" },
      })
        .then((r) => {
          if (!r.ok) throw new Error(`sign request failed (HTTP ${r.status})`);
          return r.text();
        })
        .then(resolve)
        .catch(reject);
    }
  );

  qz.security.setSignatureAlgorithm("SHA512");
}

export function isQzConnected(): boolean {
  try {
    return Boolean(qz.websocket.isActive());
  } catch {
    return false;
  }
}

/**
 * Lazy connect-on-demand — no background polling loop. Every /print
 * and /printers request calls this first; if QZ Tray is already
 * connected it's a no-op, if it dropped this reconnects, and if QZ
 * Tray is simply unavailable right now the caller gets a clear error
 * without the agent having spent the interim polling the network.
 */
export async function ensureQzConnected(): Promise<void> {
  configureOnce();
  if (isQzConnected()) return;
  try {
    await qz.websocket.connect();
    logger.info("Connected to QZ Tray");
  } catch (err) {
    throw new Error(`Could not connect to QZ Tray on this machine: ${(err as Error)?.message || err}`);
  }
}

export async function listQzPrinters(): Promise<string[]> {
  await ensureQzConnected();
  const printers = await qz.printers.find();
  return Array.isArray(printers) ? printers : [printers];
}

/**
 * Rebuilds the exact `qz.configs.create(printerName, configOptions)`
 * call the browser would have made itself in Direct mode, then prints
 * the exact same `data` array the browser prepared. No formatting,
 * layout, or business logic is applied here — configOptions and data
 * arrive already-built from Grabvo-Qz and are forwarded as-is.
 */
export async function printViaQz(
  printerName: string,
  configOptions: Record<string, unknown> | undefined,
  data: unknown[]
): Promise<void> {
  await ensureQzConnected();
  const qzConfig = qz.configs.create(printerName, configOptions || {});
  await qz.print(qzConfig, data);
}
