@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo  [1/3] Running npm i ...
echo ============================================
call npm i
if errorlevel 1 (
    echo.
    echo *** npm i FAILED ***
    pause
    exit /b 1
)

echo.
echo ============================================
echo  [2/3] Running npm run build ...
echo ============================================
call npm run build
if errorlevel 1 (
    echo.
    echo *** npm run build FAILED ***
    pause
    exit /b 1
)

echo.
echo ============================================
echo  [3/3] Starting server hidden on port 8765 ...
echo ============================================
powershell -NoProfile -WindowStyle Hidden -Command ^
  "Start-Process -FilePath 'npm.cmd' -ArgumentList 'start' -WorkingDirectory '%CD%' -WindowStyle Hidden"

echo.
echo All done. Server is running hidden on port 8765.
echo.
echo Press ENTER to hide this window...
set /p dummy=

rem --- Hide this window using PowerShell ---
powershell -NoProfile -Command ^
  "$w = (Get-Process -Id $PID).MainWindowHandle; ^
   Add-Type -Namespace W -Name U -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h, int n);'; ^
   [W.U]::ShowWindow($w, 0)" >nul 2>&1

exit /b 0