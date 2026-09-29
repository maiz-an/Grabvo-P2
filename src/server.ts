/**
 * server.ts — the entire HTTP surface of GrabvoPrintPing.
 *
 * GET  /status    — agent + QZ Tray connection state
 * GET  /printers  — printer names QZ Tray reports (web app still
 *                    decides which one to assign to what; no
 *                    business-specific printer mapping lives here)
 * POST /print     — { printerName, configOptions, data } exactly as
 *                    built by Grabvo-Qz's printHtml(); forwarded to
 *                    QZ Tray unmodified.
 * GET  /cert      — downloads the agent's self-signed cert (PEM), so a
 *                    device can install it as a trusted certificate
 *                    instead of clicking through a browser warning
 *                    every time. Also served plain HTTP on
 *                    certPort (default mainPort+1) so it can be
 *                    fetched before that device has any reason to
 *                    trust this agent's HTTPS yet.
 *
 * No filesystem endpoints beyond that one read-only cert download, no
 * shell/command execution, nothing beyond these routes.
 */
import https from "node:https";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import express, { type Request, type Response, type NextFunction } from "express";
import { config } from "./config";
import { logger } from "./logger";
import { ensureQzConnected, isQzConnected, listQzPrinters, printViaQz } from "./qz";
import { getLocalVersion } from "./version";
import { beginJob, endJob } from "./jobLock";
import { getOrCreateCert } from "./certs";

const AGENT_NAME = "GrabvoPrintPing";

export function createServer() {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "15mb" })); // raster PNGs can be a few MB base64

  app.use((req: Request, res: Response, next: NextFunction) => {
    if (config.allowedOrigin) {
      res.header("Access-Control-Allow-Origin", config.allowedOrigin);
      res.header("Vary", "Origin");
    }
    res.header("Access-Control-Allow-Headers", "Content-Type");
    res.header("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
    next();
  });

  app.use((req: Request, res: Response, next: NextFunction) => {
    if (req.method === "OPTIONS") return res.sendStatus(204);
    next();
  });

  app.get("/cert", (_req: Request, res: Response) => {
    const certPath = path.join(config.certDir, "agent-cert.pem");
    if (!fs.existsSync(certPath)) return res.status(404).json({ error: "No certificate generated yet" });
    res.setHeader("Content-Type", "application/x-x509-ca-cert");
    res.setHeader("Content-Disposition", 'attachment; filename="grabvoprintping.crt"');
    res.send(fs.readFileSync(certPath));
  });

  app.get("/status", async (_req: Request, res: Response) => {
    res.json({
      agent: AGENT_NAME,
      version: getLocalVersion(),
      status: "online",
      qzTray: isQzConnected() ? "connected" : "disconnected",
    });
  });

  app.get("/printers", async (_req: Request, res: Response) => {
    try {
      const printers = await listQzPrinters();
      res.json({ printers });
    } catch (err) {
      logger.warn("GET /printers failed:", (err as Error)?.message || err);
      res.status(502).json({ error: (err as Error)?.message || "Could not reach QZ Tray" });
    }
  });

  app.post("/print", async (req: Request, res: Response) => {
    const body = req.body ?? {};
    const { printerName, configOptions, data } = body as {
      printerName?: unknown;
      configOptions?: unknown;
      data?: unknown;
    };

    if (typeof printerName !== "string" || printerName.trim() === "") {
      return res.status(400).json({ error: "printerName (string) is required" });
    }
    if (!Array.isArray(data) || data.length === 0) {
      return res.status(400).json({ error: "data (non-empty array) is required" });
    }
    if (configOptions !== undefined && (typeof configOptions !== "object" || configOptions === null || Array.isArray(configOptions))) {
      return res.status(400).json({ error: "configOptions must be an object when present" });
    }

    beginJob();
    try {
      await printViaQz(printerName, configOptions as Record<string, unknown> | undefined, data);
      res.json({ success: true });
    } catch (err) {
      logger.error("POST /print failed:", (err as Error)?.message || err);
      res.status(502).json({ success: false, error: (err as Error)?.message || "Print failed" });
    } finally {
      endJob();
    }
  });

  // Anything else — no filesystem or command-execution endpoints exist.
  app.use((_req: Request, res: Response) => {
    res.status(404).json({ error: "Not found" });
  });

  return app;
}

/**
 * A tiny plain-HTTP-only server whose only route is the cert download.
 * Reachable with zero TLS warnings (it isn't TLS at all), so a brand
 * new device can grab the certificate and install it as trusted
 * *before* it has any reason yet to trust the main HTTPS API. Serves
 * nothing else — no /print, no /printers, nothing that needs trust.
 */
function startCertServer(): void {
  const certApp = express();
  certApp.disable("x-powered-by");
  certApp.get("/cert", (_req: Request, res: Response) => {
    const certPath = path.join(config.certDir, "agent-cert.pem");
    if (!fs.existsSync(certPath)) return res.status(404).send("No certificate generated yet");
    res.setHeader("Content-Type", "application/x-x509-ca-cert");
    res.setHeader("Content-Disposition", 'attachment; filename="grabvoprintping.crt"');
    res.send(fs.readFileSync(certPath));
  });
  certApp.use((_req: Request, res: Response) => res.status(404).send("Not found"));

  http.createServer(certApp).listen(config.certPort, config.host, () => {
    logger.info(`Certificate download available (plain HTTP, no trust needed) at http://${config.host}:${config.certPort}/cert`);
  });
}

export function startServer(): void {
  const app = createServer();

  const onListening = () => {
    const scheme = config.enableHttps ? "https" : "http";
    logger.info(`${AGENT_NAME} v${getLocalVersion()} listening on ${scheme}://${config.host}:${config.port}`);
    if (config.enableHttps) {
      logger.info(
        `Self-signed HTTPS: on each new device, first visit http://${config.host}:${config.certPort}/cert to download+install the certificate as trusted (see README) — or just open https://<this-ip>:${config.port}/status once and click through the browser warning.`
      );
    }
    ensureQzConnected()
      .then(() => logger.info("QZ Tray connected on startup"))
      .catch((err) => logger.warn("QZ Tray not reachable on startup (will retry on next request):", err.message || err));
  };

  if (config.enableHttps) {
    const { cert, key } = getOrCreateCert();
    https.createServer({ cert, key }, app).listen(config.port, config.host, onListening);
    startCertServer();
  } else {
    http.createServer(app).listen(config.port, config.host, onListening);
  }
}
