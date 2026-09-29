@echo off
setlocal enabledelayedexpansion
set PORT=8765

echo Killing process(es) listening on port %PORT% ...

set FOUND=0
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%" ^| findstr "LISTENING"') do (
    echo   Found PID %%a - killing...
    taskkill /F /PID %%a >nul 2>&1
    if !errorlevel!==0 (
        echo     OK
        set FOUND=1
    ) else (
        echo     Failed (may need admin, or already gone)
    )
)

if "!FOUND!"=="0" (
    echo No process found listening on port %PORT%.
) else (
    echo Done.
)

timeout /t 2 >nul
exit /b 0