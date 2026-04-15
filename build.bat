@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "OUT=%ROOT%\releases"
set "STAGE=%TEMP%\vr_mod_build"
set "BUILD=%ROOT%\build"

if not exist "%OUT%" mkdir "%OUT%"
if exist "%STAGE%" rmdir /s /q "%STAGE%"

rem ── Stage VMZ contents ───────────────────────────────────────────────────────
echo Staging VMZ...

mkdir "%STAGE%\vmz\resources\hands"

copy "%ROOT%\mod.txt"                                    "%STAGE%\vmz\mod.txt"                                >nul || goto :error
copy "%ROOT%\resources\override.cfg"                     "%STAGE%\vmz\resources\override.cfg"                >nul || goto :error
copy "%ROOT%\resources\vr_mod_init.gd"                   "%STAGE%\vmz\resources\vr_mod_init.gd"              >nul || goto :error
copy "%ROOT%\resources\hands\Hand_Nails_low_L.gltf"      "%STAGE%\vmz\resources\hands\Hand_Nails_low_L.gltf" >nul || goto :error
copy "%ROOT%\resources\hands\Hand_Nails_low_R.gltf"      "%STAGE%\vmz\resources\hands\Hand_Nails_low_R.gltf" >nul || goto :error
copy "%ROOT%\resources\hands\hand_col.png"               "%STAGE%\vmz\resources\hands\hand_col.png"          >nul || goto :error

rem Build VMZ into a temp location
rem NOTE: Must use ZipArchive (not Compress-Archive) to ensure forward-slash entry paths.
rem       Metro Mod Loader rejects zips with Windows backslash paths.
if exist "%STAGE%\vr-mod.vmz" del "%STAGE%\vr-mod.vmz"
powershell -NoProfile -Command ^
  "Add-Type -AssemblyName System.IO.Compression;" ^
  "$vmz='%STAGE%\vr-mod.vmz';" ^
  "$src='%STAGE%\vmz';" ^
  "$fs=[System.IO.File]::Create($vmz);" ^
  "$zip=[System.IO.Compression.ZipArchive]::new($fs,[System.IO.Compression.ZipArchiveMode]::Create);" ^
  "Get-ChildItem -Recurse -File $src | ForEach-Object {" ^
    "$rel=$_.FullName.Substring($src.Length+1).Replace('\','/');" ^
    "$e=$zip.CreateEntry($rel,[System.IO.Compression.CompressionLevel]::Optimal);" ^
    "$es=$e.Open(); $b=[System.IO.File]::ReadAllBytes($_.FullName); $es.Write($b,0,$b.Length); $es.Close();" ^
  "};" ^
  "$zip.Dispose(); $fs.Close();"
if errorlevel 1 goto :error

rem ── Stage full release (native + VMZ) ────────────────────────────────────────
echo Staging full release...

mkdir "%STAGE%\full\mods"
mkdir "%STAGE%\full\VR Mod\bin"
mkdir "%STAGE%\full\VR Mod\resources"

copy "%ROOT%\README.md"                                                  "%STAGE%\full\README.md"                                       >nul || goto :error
copy "%ROOT%\LICENSE"                                                    "%STAGE%\full\LICENSE"                                         >nul || goto :error
copy "%ROOT%\THIRD_PARTY.md"                                             "%STAGE%\full\THIRD_PARTY.md"                                  >nul || goto :error
copy "%ROOT%\launch_vr.bat"                                              "%STAGE%\full\launch_vr.bat"                                   >nul || goto :error
copy "%BUILD%\src\bootstrap\Release\rtv_vr_bootstrap.dll"                "%STAGE%\full\rtv_vr_bootstrap.dll"                            >nul || goto :error
copy "%BUILD%\src\gdextension\Release\librtv_vr_mod.windows.x86_64.dll"  "%STAGE%\full\librtv_vr_mod.windows.x86_64.dll"               >nul || goto :error
copy "%BUILD%\src\injector\Release\rtv_vr_injector.exe"                  "%STAGE%\full\VR Mod\bin\rtv_vr_injector.exe"                  >nul || goto :error
copy "%ROOT%\resources\override.cfg"                                     "%STAGE%\full\VR Mod\resources\override.cfg"                   >nul || goto :error
copy "%ROOT%\resources\vr_mod_init.gd"                                   "%STAGE%\full\VR Mod\resources\vr_mod_init.gd"                 >nul || goto :error
copy "%ROOT%\resources\rtv_vr_mod.gdextension"                           "%STAGE%\full\VR Mod\resources\rtv_vr_mod.gdextension"         >nul || goto :error
copy "%STAGE%\vr-mod.vmz"                                                "%STAGE%\full\mods\vr-mod.vmz"                                >nul || goto :error

rem ── Pack full release ─────────────────────────────────────────────────────────
echo Building vr-mod-full.zip...

if exist "%OUT%\vr-mod-full.zip" del "%OUT%\vr-mod-full.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%\full\*' -DestinationPath '%OUT%\vr-mod-full.zip'"
if errorlevel 1 goto :error

rem Also copy VMZ separately for Metro-only updates
if exist "%OUT%\vr-mod.vmz" del "%OUT%\vr-mod.vmz"
copy "%STAGE%\vr-mod.vmz" "%OUT%\vr-mod.vmz" >nul

rem ── Done ─────────────────────────────────────────────────────────────────────
rmdir /s /q "%STAGE%"
echo.
echo Done. Output in: %OUT%
echo   vr-mod-full.zip  ^(extract into game root — full install^)
echo   vr-mod.vmz       ^(Metro-only update, no native changes^)
goto :end

:error
echo.
echo ERROR: build failed.
if exist "%STAGE%" rmdir /s /q "%STAGE%"
exit /b 1

:end
endlocal
