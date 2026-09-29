$ErrorActionPreference = "Stop"
$ServiceName = "GrabvoPrintPing"

$onPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
$nssm = if ($onPath) { $onPath.Source } else { Join-Path $PSScriptRoot "nssm.exe" }

if (-not (Test-Path $nssm) -and -not $onPath) {
    Write-Error "nssm.exe not found — can't remove the service automatically. Remove it manually via services.msc."
    exit 1
}

& $nssm stop $ServiceName
& $nssm remove $ServiceName confirm

Write-Host "GrabvoPrintPing service removed. Files on disk were left untouched."
