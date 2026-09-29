@echo off
setlocal EnableExtensions EnableDelayedExpansion
title GrabvoPrintPing Setup

:: ============================================================
:: One-click installer: downloads Node.js (if missing), downloads
:: GrabvoPrintPing, builds it, opens the firewall port, and
:: registers it as an auto-starting Windows Service.
::
:: Same pattern as the existing Qz-Grabvo.cmd installer used for
:: QZ Tray itself: self-elevating, downloads what it needs from
:: qz.grabvo.app, no manual steps.
:: ============================================================

:: ---- self-elevate ----
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---- config (override by setting these before running, if ever needed) ----
if "%GRABVO_DOWNLOAD_URL%"=="" set "GRABVO_DOWNLOAD_URL=https://qz.grabvo.app/downloads/GrabvoPrintPing.zip"
if "%GRABVO_INSTALL_DIR%"=="" set "GRABVO_INSTALL_DIR=%ProgramFiles%\GrabvoPrintPing"
set "NSSM_URL=https://nssm.cc/release/nssm-2.24.zip"
set "NODE_MSI_URL=https://nodejs.org/dist/v20.17.0/node-v20.17.0-x64.msi"
set "TMP_DIR=%TEMP%\grabvoprintping-setup"

echo ==========================================
echo  GrabvoPrintPing Setup
echo ==========================================
echo.

if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"

:: ---- 1. Node.js ----
where node >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Node.js not found. Installing...
    where winget >nul 2>&1
    if %errorLevel% EQU 0 (
        winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent
    ) else (
        echo winget not available - downloading the Node.js installer directly...
        powershell -NoProfile -Command "Invoke-WebRequest -Uri '%NODE_MSI_URL%' -OutFile '%TMP_DIR%\node-setup.msi'"
        msiexec /i "%TMP_DIR%\node-setup.msi" /quiet /norestart
    )
    set "PATH=%PATH%;%ProgramFiles%\nodejs"
    where node >nul 2>&1
    if !errorLevel! NEQ 0 (
        echo Could not install Node.js automatically. Install it manually from https://nodejs.org, then re-run this script.
        pause
        exit /b 1
    )
    echo Node.js installed.
) else (
    echo Node.js already installed - skipping.
)

:: ---- 2. Download + extract GrabvoPrintPing ----
echo.
echo Downloading GrabvoPrintPing...
powershell -NoProfile -Command "Invoke-WebRequest -Uri '%GRABVO_DOWNLOAD_URL%' -OutFile '%TMP_DIR%\GrabvoPrintPing.zip'"
if not exist "%TMP_DIR%\GrabvoPrintPing.zip" (
    echo Download failed. Check the URL/your connection and try again.
    pause
    exit /b 1
)

if exist "%TMP_DIR%\extract" rmdir /s /q "%TMP_DIR%\extract"
powershell -NoProfile -Command "Expand-Archive -Path '%TMP_DIR%\GrabvoPrintPing.zip' -DestinationPath '%TMP_DIR%\extract' -Force"

:: The zip may contain a single top-level "GrabvoPrintPing" folder -
:: flatten that into the real install dir either way.
set "SRC_DIR=%TMP_DIR%\extract"
if exist "%TMP_DIR%\extract\GrabvoPrintPing" set "SRC_DIR=%TMP_DIR%\extract\GrabvoPrintPing"

if not exist "%GRABVO_INSTALL_DIR%" mkdir "%GRABVO_INSTALL_DIR%"
robocopy "%SRC_DIR%" "%GRABVO_INSTALL_DIR%" /E /NFL /NDL /NJH /NJS >nul

echo Installed to %GRABVO_INSTALL_DIR%

:: ---- 3. Build ----
echo.
echo Installing dependencies and building (this can take a minute)...
pushd "%GRABVO_INSTALL_DIR%"
if not exist ".env" if exist ".env.example" copy /y ".env.example" ".env" >nul

call npm install --omit=dev
if %errorLevel% NEQ 0 (
    echo npm install failed.
    popd
    pause
    exit /b 1
)

call npm run build
if %errorLevel% NEQ 0 (
    echo Build failed.
    popd
    pause
    exit /b 1
)

:: ---- 4. Firewall ----
echo.
echo Opening port 8765 in Windows Firewall...
netsh advfirewall firewall show rule name="GrabvoPrintPing" >nul 2>&1
if %errorLevel% NEQ 0 (
    netsh advfirewall firewall add rule name="GrabvoPrintPing" dir=in action=allow protocol=TCP localport=8765 >nul
)

:: ---- 5. NSSM (for the Windows Service) ----
if not exist "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" (
    echo.
    echo Downloading NSSM (service manager)...
    powershell -NoProfile -Command "Invoke-WebRequest -Uri '%NSSM_URL%' -OutFile '%TMP_DIR%\nssm.zip'"
    powershell -NoProfile -Command "Expand-Archive -Path '%TMP_DIR%\nssm.zip' -DestinationPath '%TMP_DIR%\nssm' -Force"
    for /r "%TMP_DIR%\nssm" %%f in (nssm.exe) do (
        echo %%f | findstr /i "win64" >nul && copy /y "%%f" "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" >nul
    )
    if not exist "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" (
        for /r "%TMP_DIR%\nssm" %%f in (nssm.exe) do copy /y "%%f" "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" >nul
    )
)

:: ---- 6. Register + start the Windows Service ----
echo.
echo Registering the Windows Service...
powershell -NoProfile -ExecutionPolicy Bypass -File "%GRABVO_INSTALL_DIR%\scripts\install-windows.ps1"

popd

echo.
echo ==========================================
echo  SETUP COMPLETE
echo ==========================================
echo GrabvoPrintPing is installed and running as a Windows Service.
echo Check it from another device on this network:  http://THIS-PC-IP:8765/status
echo.
pause
