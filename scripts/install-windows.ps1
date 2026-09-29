<#
  Installs GrabvoPrintPing as a real Windows Service using NSSM
  (Non-Sucking Service Manager) — the standard, widely-used way to run
  a plain Node.js process as a Windows Service with auto-restart on
  crash. NSSM is a small, well-known standalone tool, not a dependency
  of the agent itself.

  Usage (elevated PowerShell — right-click -> Run as administrator):
    .\scripts\install-windows.ps1

  If nssm.exe isn't already on PATH, download it from
  https://nssm.cc/download, extract nssm.exe (win64 build) next to
  this script or anywhere on PATH, then re-run.
#>

$ErrorActionPreference = "Stop"

$InstallDir = Split-Path -Parent $PSScriptRoot
$ServiceName = "GrabvoPrintPing"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Error "Run this from an elevated (Administrator) PowerShell window."
        exit 1
    }
}

function Find-Nssm {
    $onPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $local = Join-Path $PSScriptRoot "nssm.exe"
    if (Test-Path $local) { return $local }
    return $null
}

Assert-Admin

$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Error "Node.js 18+ is required and wasn't found on PATH."
    exit 1
}

$nssm = Find-Nssm
if (-not $nssm) {
    Write-Error "nssm.exe not found. Download it from https://nssm.cc/download, put nssm.exe in $PSScriptRoot, then re-run this script."
    exit 1
}

Write-Host "Installing dependencies and building..."
Push-Location $InstallDir
npm install --omit=dev
npm run build

$envExample = Join-Path $InstallDir ".env.example"
$envFile = Join-Path $InstallDir ".env"
if ((Test-Path $envExample) -and (-not (Test-Path $envFile))) {
    Copy-Item $envExample $envFile
    Write-Host "Created .env from .env.example — edit it (PORT, SIGNING_BASE_URL) before relying on this."
}
Pop-Location

$distEntry = Join-Path $InstallDir "dist\index.js"

& $nssm install $ServiceName $node.Source $distEntry
& $nssm set $ServiceName AppDirectory $InstallDir
& $nssm set $ServiceName DisplayName "GrabvoPrintPing"
& $nssm set $ServiceName Description "Grabvo print agent - bridges the Grabvo-Qz web app to QZ Tray"
& $nssm set $ServiceName Start SERVICE_AUTO_START
& $nssm set $ServiceName AppExit Default Restart
& $nssm set $ServiceName AppRestartDelay 5000
& $nssm set $ServiceName AppStdout (Join-Path $InstallDir "grabvoprintping.log")
& $nssm set $ServiceName AppStderr (Join-Path $InstallDir "grabvoprintping.log")

& $nssm start $ServiceName

Write-Host ""
Write-Host "Opening firewall ports (8765 API, 8766 cert download)..."
if (-not (Get-NetFirewallRule -DisplayName "GrabvoPrintPing" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "GrabvoPrintPing" -Direction Inbound -Protocol TCP -LocalPort 8765,8766 -Action Allow | Out-Null
}

Write-Host ""
Write-Host "Trusting the agent's self-signed certificate on THIS PC (so Chrome/Edge here never shows a warning for it)..."
$certPath = Join-Path $InstallDir "certs\agent-cert.pem"
$waited = 0
while (-not (Test-Path $certPath) -and $waited -lt 15) {
    Start-Sleep -Seconds 1
    $waited++
}
if (Test-Path $certPath) {
    certutil -addstore -f "ROOT" $certPath | Out-Null
    Write-Host "Certificate trusted system-wide on this PC. https://localhost:8765 (and this PC's own LAN IP) will show no warning here."
} else {
    Write-Host "Certificate wasn't generated yet (service may still be starting) — trust it manually later:"
    Write-Host "  certutil -addstore -f `"ROOT`" `"$certPath`""
}

Write-Host ""
Write-Host "GrabvoPrintPing installed and started as a Windows Service ('$ServiceName')."
Write-Host "Status:  Get-Service $ServiceName"
Write-Host "Logs:    Get-Content '$InstallDir\grabvoprintping.log' -Wait"
Write-Host "Stop:    nssm stop $ServiceName"
Write-Host ""
Write-Host "Other devices (phones) still need to install the certificate once -"
Write-Host "point their browser at http://THIS-PC-IP:8766/cert to download it,"
Write-Host "then install it as a trusted certificate (see README.md)."
