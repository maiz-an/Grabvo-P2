/**
 * qz-tray ships without TypeScript types. This agent only calls a
 * small, well-documented surface (security, websocket, printers,
 * configs, print) — same surface the web app's own src/types/qz.d.ts
 * types for the browser build. Kept intentionally loose (`any`)
 * rather than re-declaring qz-tray's full API.
 */
declare module "qz-tray" {
  const qz: any;
  export = qz;
}
