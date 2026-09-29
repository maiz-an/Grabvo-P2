@echo off
setlocal EnableExtensions EnableDelayedExpansion
title GrabvoPrintPing Setup

:: =========================================================================
::   GrabvoPrintPing Auto-Installer
::   ------------------------------------------------------------------------
::   Installs Node.js (if missing), downloads + builds GrabvoPrintPing,
::   opens the firewall, and registers it as an auto-starting Windows
::   Service with an auto-trusted HTTPS certificate.
::   Same UI conventions as Qz-Grabvo.cmd: colored banners, step headers,
::   retry-with-verification downloads, ok/warn/fail badges.
:: =========================================================================

:: -------------------------------------------------------------------------
:: 1. Enable VT escape sequences
:: -------------------------------------------------------------------------
reg add "HKCU\Console" /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

:: -------------------------------------------------------------------------
:: 2. Self-elevate
:: -------------------------------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    exit /b
)

:: -------------------------------------------------------------------------
:: 3. Colors
:: -------------------------------------------------------------------------
for /f "delims=" %%a in ('powershell -NoProfile -Command "[char]27" 2^>nul') do set "ESC=%%a"
if not defined ESC (
    set "R="  & set "B="  & set "PU=" & set "GR="
    set "RD=" & set "AM=" & set "SL=" & set "WH=" & set "DGR="
) else (
    set "R=!ESC![0m"
    set "B=!ESC![1m"
    set "PU=!ESC![38;5;141m"
    set "GR=!ESC![38;5;78m"
    set "RD=!ESC![38;5;203m"
    set "AM=!ESC![38;5;214m"
    set "SL=!ESC![38;5;245m"
    set "WH=!ESC![38;5;231m"
    set "DGR=!ESC![38;5;240m"
)

:: -------------------------------------------------------------------------
:: 4. Config
:: -------------------------------------------------------------------------
if "%GRABVO_DOWNLOAD_URL%"=="" set "GRABVO_DOWNLOAD_URL=https://qz.grabvo.app/downloads/GrabvoPrintPing.zip"
if "%GRABVO_INSTALL_DIR%"=="" set "GRABVO_INSTALL_DIR=%ProgramFiles%\GrabvoPrintPing"
set "NSSM_URL=https://nssm.cc/release/nssm-2.24.zip"
set "NODE_MSI_URL=https://nodejs.org/dist/v20.17.0/node-v20.17.0-x64.msi"
set "TEMP_DIR=%TEMP%\grabvoprintping_setup"
set "MAX_RETRIES=3"
set "RETRY_DELAY=4"
set "FINAL_STATE=WARN"

cls
call :banner

call :step1
call :step2
call :step3
call :step4
call :step5
call :step6
call :step7

goto :complete

:: =========================================================================
::   STEP 1 - Workspace + Node.js
:: =========================================================================
:step1
call :header "1/7" "Preparing workspace and checking Node.js"
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%" >nul 2>&1
mkdir "%TEMP_DIR%" >nul 2>&1
if not exist "%TEMP_DIR%" (
    call :fail "Could not create temp folder: %TEMP_DIR%"
    goto :complete
)
call :ok "Workspace ready"

where node >nul 2>&1
if !errorLevel! equ 0 (
    call :ok "Node.js already installed"
    exit /b 0
)

echo   !SL!Node.js not found - installing...!R!
where winget >nul 2>&1
if !errorLevel! equ 0 (
    winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent >nul 2>&1
) else (
    call :download "!NODE_MSI_URL!" "!TEMP_DIR!\node-setup.msi"
    if exist "!TEMP_DIR!\node-setup.msi" (
        msiexec /i "!TEMP_DIR!\node-setup.msi" /quiet /norestart
    )
)
set "PATH=%PATH%;%ProgramFiles%\nodejs"
where node >nul 2>&1
if !errorLevel! neq 0 (
    call :fail "Could not install Node.js automatically - install it from https://nodejs.org, then re-run this script"
    goto :complete
)
call :ok "Node.js installed"
exit /b 0

:: =========================================================================
::   STEP 2 - Download GrabvoPrintPing
:: =========================================================================
:step2
call :header "2/7" "Downloading GrabvoPrintPing"

set "ZIP_FILE=%TEMP_DIR%\GrabvoPrintPing.zip"
call :download "!GRABVO_DOWNLOAD_URL!" "!ZIP_FILE!"

if not exist "!ZIP_FILE!" (
    call :fail "Download failed after all retries: !GRABVO_DOWNLOAD_URL!"
    goto :complete
)

:: Verify it's actually a zip (starts with the "PK" signature) before we
:: try to extract it - a 404/error page saved as .zip fails Expand-Archive
:: with a confusing "End of Central Directory record" error otherwise.
set "ZIP_OK=0"
for /f "usebackq delims=" %%z in (`powershell -NoProfile -Command ^
  "try { $b = [System.IO.File]::ReadAllBytes('!ZIP_FILE!')[0..1]; if ($b[0] -eq 80 -and $b[1] -eq 75) { 'YES' } else { 'NO' } } catch { 'NO' }"`) do set "ZIP_OK_TXT=%%z"
if "!ZIP_OK_TXT!"=="YES" set "ZIP_OK=1"

if "!ZIP_OK!"=="0" (
    call :fail "The downloaded file isn't a valid zip - GrabvoPrintPing.zip likely isn't hosted at !GRABVO_DOWNLOAD_URL! yet"
    goto :complete
)
call :ok "Downloaded and verified GrabvoPrintPing.zip"
exit /b 0

:: =========================================================================
::   STEP 3 - Extract + install files
:: =========================================================================
:step3
call :header "3/7" "Installing files"

if exist "%TEMP_DIR%\extract" rd /s /q "%TEMP_DIR%\extract" >nul 2>&1
powershell -NoProfile -Command "Expand-Archive -Path '%TEMP_DIR%\GrabvoPrintPing.zip' -DestinationPath '%TEMP_DIR%\extract' -Force" >nul 2>&1

if not exist "%TEMP_DIR%\extract" (
    call :fail "Extraction failed"
    goto :complete
)

set "SRC_DIR=%TEMP_DIR%\extract"
if exist "%TEMP_DIR%\extract\GrabvoPrintPing" set "SRC_DIR=%TEMP_DIR%\extract\GrabvoPrintPing"

if not exist "!SRC_DIR!\package.json" (
    call :fail "Extracted files don't look like GrabvoPrintPing (no package.json found)"
    goto :complete
)

if not exist "%GRABVO_INSTALL_DIR%" mkdir "%GRABVO_INSTALL_DIR%" >nul 2>&1
robocopy "!SRC_DIR!" "%GRABVO_INSTALL_DIR%" /E /NFL /NDL /NJH /NJS >nul

if not exist "%GRABVO_INSTALL_DIR%\package.json" (
    call :fail "Copy to %GRABVO_INSTALL_DIR% failed"
    goto :complete
)
call :ok "Installed to %GRABVO_INSTALL_DIR%"
exit /b 0

:: =========================================================================
::   STEP 4 - npm install + build
:: =========================================================================
:step4
call :header "4/7" "Installing dependencies and building"

pushd "%GRABVO_INSTALL_DIR%"
if not exist ".env" if exist ".env.example" copy /y ".env.example" ".env" >nul

echo   !SL!Running npm install... this may take a minute!R!
call npm install --omit=dev >nul 2>"%TEMP_DIR%\npm-install.log"
if !errorLevel! neq 0 (
    popd
    call :fail "npm install failed - see %TEMP_DIR%\npm-install.log"
    goto :complete
)

echo   !SL!Running npm run build...!R!
call npm run build >nul 2>"%TEMP_DIR%\npm-build.log"
if !errorLevel! neq 0 (
    popd
    call :fail "Build failed - see %TEMP_DIR%\npm-build.log"
    goto :complete
)
popd
call :ok "Dependencies installed and build complete"
exit /b 0

:: =========================================================================
::   STEP 5 - Firewall
:: =========================================================================
:step5
call :header "5/7" "Opening firewall ports"

netsh advfirewall firewall show rule name="GrabvoPrintPing" >nul 2>&1
if !errorLevel! neq 0 (
    netsh advfirewall firewall add rule name="GrabvoPrintPing" dir=in action=allow protocol=TCP localport=8765,8766 >nul 2>&1
)
call :ok "Ports 8765 (API) and 8766 (cert download) open"
exit /b 0

:: =========================================================================
::   STEP 6 - NSSM + register the Windows Service
:: =========================================================================
:step6
call :header "6/7" "Registering the Windows Service"

set "ServiceName=GrabvoPrintPing"

if not exist "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" (
    echo   !SL!Downloading NSSM (service manager)...!R!
    call :download "!NSSM_URL!" "!TEMP_DIR!\nssm.zip"
    if exist "!TEMP_DIR!\nssm.zip" (
        powershell -NoProfile -Command "Expand-Archive -Path '!TEMP_DIR!\nssm.zip' -DestinationPath '!TEMP_DIR!\nssm' -Force" >nul 2>&1
        for /r "!TEMP_DIR!\nssm" %%f in (nssm.exe) do (
            echo %%f | findstr /i "win64" >nul && copy /y "%%f" "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" >nul
        )
        if not exist "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" (
            for /r "!TEMP_DIR!\nssm" %%f in (nssm.exe) do copy /y "%%f" "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" >nul
        )
    )
)

if not exist "%GRABVO_INSTALL_DIR%\scripts\nssm.exe" (
    call :fail "Could not obtain nssm.exe - download it manually from https://nssm.cc/download and place it in %GRABVO_INSTALL_DIR%\scripts\"
    goto :complete
)

set "NSSM=%GRABVO_INSTALL_DIR%\scripts\nssm.exe"
set "NODE_EXE="
for /f "delims=" %%n in ('where node') do if not defined NODE_EXE set "NODE_EXE=%%n"
set "DIST_ENTRY=%GRABVO_INSTALL_DIR%\dist\index.js"

"!NSSM!" stop "%ServiceName%" >nul 2>&1
"!NSSM!" remove "%ServiceName%" confirm >nul 2>&1

"!NSSM!" install "%ServiceName%" "!NODE_EXE!" "!DIST_ENTRY!" >nul 2>&1
"!NSSM!" set "%ServiceName%" AppDirectory "%GRABVO_INSTALL_DIR%" >nul 2>&1
"!NSSM!" set "%ServiceName%" DisplayName "GrabvoPrintPing" >nul 2>&1
"!NSSM!" set "%ServiceName%" Description "Grabvo print agent - bridges the Grabvo-Qz web app to QZ Tray" >nul 2>&1
"!NSSM!" set "%ServiceName%" Start SERVICE_AUTO_START >nul 2>&1
"!NSSM!" set "%ServiceName%" AppExit Default Restart >nul 2>&1
"!NSSM!" set "%ServiceName%" AppRestartDelay 5000 >nul 2>&1
"!NSSM!" set "%ServiceName%" AppStdout "%GRABVO_INSTALL_DIR%\grabvoprintping.log" >nul 2>&1
"!NSSM!" set "%ServiceName%" AppStderr "%GRABVO_INSTALL_DIR%\grabvoprintping.log" >nul 2>&1
"!NSSM!" start "%ServiceName%" >nul 2>&1

timeout /t 2 /nobreak >nul 2>&1
sc query "%ServiceName%" | find "RUNNING" >nul 2>&1
if !errorLevel! neq 0 (
    call :warn "Service registered but may not have started yet - check manually with: Get-Service %ServiceName%"
) else (
    call :ok "Windows Service registered and running"
)
exit /b 0

:: =========================================================================
::   STEP 7 - Trust the certificate
:: =========================================================================
:step7
call :header "7/7" "Trusting the HTTPS certificate on this PC"

set "CERT_PATH=%GRABVO_INSTALL_DIR%\certs\agent-cert.pem"
set /a WAITED=0
:wait_cert
if exist "!CERT_PATH!" goto :cert_found
if !WAITED! GEQ 15 goto :cert_timeout
timeout /t 1 /nobreak >nul 2>&1
set /a WAITED+=1
goto :wait_cert

:cert_found
certutil -addstore -f "ROOT" "!CERT_PATH!" >nul 2>&1
if !errorLevel! equ 0 (
    call :ok "Certificate trusted system-wide on this PC"
    set "FINAL_STATE=OK"
) else (
    call :warn "Could not add the certificate automatically - run manually: certutil -addstore -f ROOT ""!CERT_PATH!"""
    set "FINAL_STATE=OK"
)
exit /b 0

:cert_timeout
call :warn "Certificate wasn't generated yet - the service may still be starting. Re-run this script, or trust it manually once !CERT_PATH! exists."
set "FINAL_STATE=OK"
exit /b 0

:: =========================================================================
::   SUBROUTINES
:: =========================================================================

:download
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_ATTEMPT=0"

:download_loop
set /a DL_ATTEMPT+=1
if exist "%DL_OUT%" del /f /q "%DL_OUT%" >nul 2>&1

where curl.exe >nul 2>&1
if !errorLevel! equ 0 (
    curl.exe -L -f -s -S --connect-timeout 20 -o "%DL_OUT%" "%DL_URL%" >nul 2>&1
) else (
    powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_OUT%' -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>&1
)

if exist "%DL_OUT%" (
    for %%A in ("%DL_OUT%") do set "DL_SIZE=%%~zA"
    if !DL_SIZE! GTR 0 exit /b 0
    del /f /q "%DL_OUT%" >nul 2>&1
)

if !DL_ATTEMPT! lss %MAX_RETRIES% (
    call :warn "Attempt !DL_ATTEMPT!/%MAX_RETRIES% failed - retrying in %RETRY_DELAY%s"
    timeout /t %RETRY_DELAY% /nobreak >nul 2>&1
    goto :download_loop
)

exit /b 1

:: =========================================================================
::   UI (pure ASCII, same conventions as Qz-Grabvo.cmd)
:: =========================================================================

:banner
echo.
echo   %PU%%B%============================================================%R%
echo.
echo   %PU%%B%.d8888b.                    888                        %R%
echo   %PU%%B%d88P  Y88b                  888                        %R%
echo   %PU%%B%888    888                  888                        %R%
echo   %PU%%B%888        888d888  8888b.  88888b.  888  888  .d88b.  %R%
echo   %PU%%B%888  88888 888P"       "88b 888 "88b 888  888 d88""88b %R%
echo   %PU%%B%888    888 888     .d888888 888  888 Y88  88P 888  888 %R%
echo   %PU%%B%Y88b  d88P 888     888  888 888 d88P  Y8bd8P  Y88..88P %R%
echo   %PU%%B% "Y8888P88 888     "Y888888 88888P"    Y88P    "Y88P"  %R%
echo.
echo   %WH%%B%                  GrabvoPrintPing Setup%R%
echo   %SL%          Print Agent bridge - installs Node.js,%R%
echo   %SL%       builds the agent, and runs it as a service%R%
echo.
echo   %PU%%B%============================================================%R%
echo.
exit /b 0

:header
echo.
echo   %PU%%B%[%~1]%R%   %WH%%B%%~2%R%
echo   %DGR%         -------------------------------------------------%R%
exit /b 0

:ok
echo   %GR%%B%[OK]%R%    %WH%%~1%R%
exit /b 0

:warn
setlocal DisableDelayedExpansion
echo   %AM%%B%[!!]%R%    %AM%%~1%R%
endlocal
exit /b 0

:fail
echo   %RD%%B%[XX]%R%    %RD%%B%%~1%R%
exit /b 1

:complete
if "%FINAL_STATE%"=="OK" (
    cls
    echo.
    echo   %GR%%B%============================================================%R%
    echo.
    echo   %PU%%B%.d8888b.                    888                        %R%
    echo   %PU%%B%d88P  Y88b                  888                        %R%
    echo   %PU%%B%888    888                  888                        %R%
    echo   %PU%%B%888        888d888  8888b.  88888b.  888  888  .d88b.  %R%
    echo   %PU%%B%888  88888 888P"       "88b 888 "88b 888  888 d88""88b %R%
    echo   %PU%%B%888    888 888     .d888888 888  888 Y88  88P 888  888 %R%
    echo   %PU%%B%Y88b  d88P 888     888  888 888 d88P  Y8bd8P  Y88..88P %R%
    echo   %PU%%B% "Y8888P88 888     "Y888888 88888P"    Y88P    "Y88P"  %R%
    echo.
    echo   %GR%%B%                 SETUP COMPLETE%R%
    echo   %SL%     GrabvoPrintPing is installed and running%R%
    echo.
    echo   %GR%%B%============================================================%R%
    echo.
    echo   %WH%GrabvoPrintPing is running as a Windows Service and will%R%
    echo   %WH%start automatically on boot.%R%
    echo.
    echo   %SL%Check from another device on this network:%R%
    echo   %SL%  https://THIS-PC-IP:8765/status%R%
    echo.
    echo   %SL%Phones/other devices still need to trust the certificate%R%
    echo   %SL%once - see http://THIS-PC-IP:8766/cert%R%
    echo.
) else (
    cls
    echo.
    echo   %RD%%B%============================================================%R%
    echo.
    echo   %RD%%B%              SETUP DID NOT COMPLETE%R%
    echo.
    echo   %RD%%B%============================================================%R%
    echo.
    echo   %WH%Check the messages above for which step failed, fix that%R%
    echo   %WH%(e.g. host GrabvoPrintPing.zip at the download URL), then%R%
    echo   %WH%run this installer again.%R%
    echo.
)
cd /d "%TEMP%" >nul 2>&1
rd /s /q "%TEMP_DIR%" >nul 2>&1
echo.
pause
endlocal
exit /b 0
