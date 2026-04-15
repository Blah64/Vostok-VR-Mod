@echo off
setlocal
cd /d "%~dp0"

echo [RTV VR Mod] Launching Road to Vostok in VR mode...

:: Check if injector exists
if not exist "VR Mod\bin\rtv_vr_injector.exe" (
    echo [ERROR] rtv_vr_injector.exe not found. Please build the mod first.
    pause
    exit /b 1
)

:: Check if bootstrap DLL exists
if not exist "rtv_vr_bootstrap.dll" (
    echo [ERROR] rtv_vr_bootstrap.dll not found. Please build and install the mod first.
    pause
    exit /b 1
)

:: Launch with injection
"VR Mod\bin\rtv_vr_injector.exe" --launch "RTV.exe" --inject "rtv_vr_bootstrap.dll"

if errorlevel 1 (
    echo [ERROR] Failed to launch. Check VR Mod\logs\rtv_vr.log for details.
    pause
    exit /b 1
)

echo [RTV VR Mod] Game launched successfully.
endlocal
