# GrabvoPrintPing

A tiny transport bridge. It contains **no** receipt/KOT/ticket
formatting, layout, or business logic — that all stays in the
Grabvo-Qz web app, exactly as it works today. This agent only
forwards an already-built print job to QZ Tray..

```
Phone / Browser -> Grabvo-Qz web app -> GrabvoPrintPing -> QZ Tray -> Printer
```

Direct QZ Tray printing (Grabvo-Qz talking straight to QZ Tray in the
same browser) is untouched and keeps working exactly as before. This
agent is only needed for the new "Print Agent" connection mode, which
exists so a phone (no local QZ Tray) can print through a Windows PC or
print box on the same network that does have QZ Tray running.

## How it talks to QZ Tray

Uses the official `qz-tray` npm package (the Node-usable build of the
same client library the browser loads from a CDN) with QZ's documented
Node overrides (`qz.io/docs/api-overrides`):

- `qz.api.setWebSocketType(require('ws'))` — Node has no built-in WebSocket
- `qz.api.setPromiseType(...)` — native Promises
- `qz.api.setSha256Type(...)` — Node's `crypto` module

For certificate + signing, it calls the **same** two endpoints the
Grabvo-Qz browser app already calls — `/digital-certificate.txt` and
`/sign-message` on `SIGNING_BASE_URL` (defaults to
`https://qz.grabvo.app`) — same SHA512 algorithm. The private key never
leaves that server; this agent never has it, on disk or otherwise.

## API

| Method | Path        | Purpose |
|---|---|---|
| GET  | `/status`   | `{ agent, version, status, qzTray }` |
| GET  | `/printers` | `{ printers: string[] }` — asks QZ Tray, returns names |
| POST | `/print`    | `{ printerName, configOptions?, data }` — forwarded to `qz.print()` unmodified |

`configOptions` is whatever was passed as the second argument to the
browser's `qz.configs.create(printerName, configOptions)` — this agent
reconstructs the identical call on its own `qz-tray` client (a browser
`Config` object instance can't survive JSON over HTTP, so the options
it was built from travel instead, and the same construction happens on
this side).

No filesystem endpoints, no command execution. `/print` only prints.

## One-click install (fresh PC, any OS)

`bootstrap/` holds two link-friendly installers — download Node.js if
it's missing, download+build GrabvoPrintPing, and register it as a
background service, with nothing typed by hand:

- **Windows**: `bootstrap/GrabvoPrintPing-Setup.cmd` — self-elevating
  (same pattern as this repo's own `Qz-Grabvo.cmd`), installs Node via
  `winget` (or the official MSI as a fallback), downloads and builds
  the agent, opens the firewall port, downloads NSSM, and registers +
  starts the Windows Service.
- **macOS/Linux**: `bootstrap/install.sh` — installs Node via
  `apt`/`dnf`/`yum` (Linux) or Homebrew (macOS), downloads and builds
  the agent, then runs `scripts/install-linux.sh` or
  `scripts/install-macos.sh`.

Both download the agent from `GRABVO_DOWNLOAD_URL`, which defaults to
`https://qz.grabvo.app/downloads/GrabvoPrintPing.zip`. **For the "just
click a link" experience to work, that zip (and, for macOS/Linux, the
`install.sh` script itself) needs to be hosted there** — same as this
project's `Qz-Grabvo.cmd` is already served from Grabvo-Qz's own
`public/` folder. To wire that up:

1. Zip this project (excluding `node_modules`/`dist`) and upload it to
   Grabvo-Qz's `public/downloads/GrabvoPrintPing.zip`.
2. Upload `bootstrap/GrabvoPrintPing-Setup.cmd` to
   `public/GrabvoPrintPing-Setup.cmd` and `bootstrap/install.sh` to
   `public/install-grabvoprintping.sh` in that same repo.
3. Link to them from the web app the same way `WindowsSetup` in
   `SetupPanel.tsx` links to `Qz-Grabvo.cmd` (download button ->
   `./GrabvoPrintPing-Setup.cmd`); for macOS/Linux, the install command
   is `curl -fsSL https://qz.grabvo.app/install-grabvoprintping.sh | bash`.

Once that's live, installing on a fresh PC is one download + one run —
no manual Node install, no manual `npm install`/`build`, no manually
running the platform install script.

## Development

```bash
npm install
cp .env.example .env      # adjust PORT / SIGNING_BASE_URL if needed
npm run dev                # tsx watch — restarts on save
```

Then from the Grabvo-Qz web app: Printers tab -> Connection mode ->
Print Agent -> `http://localhost:8765` (or this machine's LAN IP) ->
Reconnect.

## Production build

```bash
npm install --omit=dev
npm run build      # compiles src/ -> dist/
npm start           # node dist/index.js
```

## Running as a background service

One codebase, small OS-specific installers under `scripts/`.

### Windows

Uses [NSSM](https://nssm.cc/) (a small, standard, widely-used tool for
running a plain process as a real Windows Service with auto-restart —
not a dependency of the agent itself). Download `nssm.exe` (win64
build) and place it in `scripts/`, or put it on `PATH`, then:

```powershell
# From an elevated (Administrator) PowerShell:
.\scripts\install-windows.ps1
```

Installs + builds, registers a service named `GrabvoPrintPing`
(`Start=Automatic`, restarts on crash), and starts it.

Remove it with `.\scripts\uninstall-windows.ps1`.

### Linux (systemd)

```bash
sudo ./scripts/install-linux.sh
```

Installs + builds, writes `/etc/systemd/system/grabvoprintping.service`
(`Restart=always`), enables it at boot, and starts it.

```
systemctl status grabvoprintping
journalctl -u grabvoprintping -f
sudo systemctl stop grabvoprintping
```

Remove it with `sudo ./scripts/uninstall-linux.sh`.

### macOS (launchd)

```bash
./scripts/install-macos.sh
```

Installs + builds, registers a per-user LaunchAgent
(`~/Library/LaunchAgents/app.grabvo.printping.plist`, `KeepAlive`,
runs at login).

Remove it with `./scripts/uninstall-macos.sh`.

## Self-update

No GitHub Releases, no `.exe` distribution. `version.txt` at the repo
root (`https://github.com/maiz-an/Grabvo-P2`) is the single source of
truth for the latest version.

Every `UPDATE_CHECK_INTERVAL_MINUTES` (default 360 = 6h; first check
~1 minute after startup), the running agent:

1. Fetches `version.txt` from the `UPDATE_BRANCH` on GitHub and
   compares it to its own local `version.txt`.
2. If newer: downloads that branch as a tarball, extracts it into
   `.update-staging/`, and verifies the extracted `version.txt` matches
   what it just checked.
3. Runs `npm install --omit=dev` and `npm run build` **inside the
   staging folder only** — the currently running install is untouched
   through this whole step.
4. Waits for any in-flight `/print` request to finish (up to 5
   minutes) before touching any files.
5. Moves the current install into `.update-backup/`, moves the staged
   build into place, then exits.
6. The OS service manager (systemd/launchd/NSSM `AppExit Restart`) —
   all set to auto-restart — starts the new build.

If step 1–4 fails for any reason (network, bad download, build
failure), nothing is touched — staging/download files are deleted and
the running agent keeps going on its current version. `.update-backup/`
is kept after a swap (not auto-deleted) for manual rollback if a new
build somehow doesn't come back up.

Set `AUTO_UPDATE=false` in `.env` to disable this entirely.

## Testing Direct mode (unchanged)

1. In Grabvo-Qz: Printers tab -> Connection mode -> **Direct QZ Tray**.
2. Click Reconnect — same QZ Tray flow as before.
3. Print a receipt/ticket — same as before, byte-for-byte the same
   code path as before this agent existed.

## Testing Print Agent mode

1. Start GrabvoPrintPing (`npm run dev` or the installed service) on a
   machine that also has QZ Tray running.
2. `curl http://<that machine>:8765/status` from another device on the
   same network — should return `"qzTray":"connected"` once QZ Tray is
   reachable (it lazily connects on the first request if not already).
3. In Grabvo-Qz (can be on a phone): Printers tab -> Connection mode ->
   **Print Agent** -> enter `http://<that machine>:8765` -> Reconnect.
   Printer dropdowns should populate from `/printers`.
4. Print a receipt/ticket — the job posts to `/print`; the printer
   should produce byte-identical output to Direct mode, since the web
   app built the exact same `data`/`configOptions` either way.
5. Stop QZ Tray on the agent machine, try printing again — you should
   get a clear error, not a crash; restart QZ Tray and print again to
   confirm it recovers without restarting the agent.

## Known QZ Tray limitations found during implementation

- There's no official Node QZ Tray SDK distinct from the browser
  build — the same `qz-tray` package works in Node, but only once the
  WebSocket/Promise/SHA-256 implementations are swapped in per QZ's
  own docs. This agent does exactly that; nothing unsupported was
  invented.
- A browser's `qz.configs.create(...)` result can't be sent over the
  wire as-is (see the `configOptions` note above) — this is a
  transport detail, not a change to what gets printed.
