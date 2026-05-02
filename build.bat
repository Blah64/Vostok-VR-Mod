@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "OUT=%ROOT%\releases"
set "STAGE=%TEMP%\vr_mod_build"
set "BUILD=%ROOT%\build"

if not exist "%OUT%" mkdir "%OUT%"
if exist "%STAGE%" rmdir /s /q "%STAGE%"

rem -- Rebuild native artifacts so the VMZ + zip never ship stale DLLs --------
rem
rem We don't reconfigure cmake here (that's a one-time setup); we just rerun
rem the build so any edits to src/bootstrap or src/gdextension are picked up.
rem Skipped silently if no build/ tree exists yet (first-time GDScript-only
rem builds are still supported) or if cmake isn't on PATH. The freshness
rem checks in tests/packaging/test_packaging.ps1 catch any stale DLLs that
rem slip through.
rem
rem Note: cmd.exe's IF parser hates unquoted parens inside string literals
rem (Visual Studio's path contains "(x86)"). We use call-into-label to keep
rem the conditional logic outside the affected scope.

call :rebuild_native
if errorlevel 1 goto :error

rem ── Stage VMZ contents ───────────────────────────────────────────────────────
echo Staging VMZ...

mkdir "%STAGE%\vmz\resources\hands"
mkdir "%STAGE%\vmz\resources\vr_mod"

copy "%ROOT%\mod.txt"                                    "%STAGE%\vmz\mod.txt"                                >nul || goto :error
copy "%ROOT%\resources\override.cfg"                     "%STAGE%\vmz\resources\override.cfg"                >nul || goto :error
copy "%ROOT%\resources\vr_mod_init.gd"                   "%STAGE%\vmz\resources\vr_mod_init.gd"              >nul || goto :error
copy "%ROOT%\resources\default_config.json"              "%STAGE%\vmz\resources\default_config.json"         >nul || goto :error
copy "%ROOT%\resources\controls.md"                      "%STAGE%\vmz\resources\controls.md"                 >nul || goto :error
copy "%ROOT%\resources\hands\Hand_Nails_low_L.gltf"      "%STAGE%\vmz\resources\hands\Hand_Nails_low_L.gltf" >nul || goto :error
copy "%ROOT%\resources\hands\Hand_Nails_low_R.gltf"      "%STAGE%\vmz\resources\hands\Hand_Nails_low_R.gltf" >nul || goto :error
copy "%ROOT%\resources\hands\hand_col.png"               "%STAGE%\vmz\resources\hands\hand_col.png"          >nul || goto :error
copy "%ROOT%\resources\vr_mod\*.gd"                      "%STAGE%\vmz\resources\vr_mod\"                      >nul || goto :error

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

copy "%ROOT%\README.md"                                                  "%STAGE%\full\VR Mod\README.md"                                >nul || goto :error
copy "%ROOT%\LICENSE"                                                    "%STAGE%\full\VR Mod\LICENSE"                                  >nul || goto :error
copy "%ROOT%\THIRD_PARTY.md"                                             "%STAGE%\full\VR Mod\THIRD_PARTY.md"                          >nul || goto :error
copy "%ROOT%\launch_vr.bat"                                              "%STAGE%\full\launch_vr.bat"                                   >nul || goto :error
copy "%BUILD%\src\bootstrap\Release\rtv_vr_bootstrap.dll"                "%STAGE%\full\rtv_vr_bootstrap.dll"                            >nul || goto :error
copy "%BUILD%\src\gdextension\Release\librtv_vr_mod.windows.x86_64.dll"  "%STAGE%\full\librtv_vr_mod.windows.x86_64.dll"               >nul || goto :error
copy "%BUILD%\src\injector\Release\rtv_vr_injector.exe"                  "%STAGE%\full\VR Mod\bin\rtv_vr_injector.exe"                  >nul || goto :error
copy "%ROOT%\resources\override.cfg"                                     "%STAGE%\full\VR Mod\resources\override.cfg"                   >nul || goto :error
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

rem -- Subroutine: rebuild native artifacts if cmake + a build/ tree exist ---
rem
rem Returns errorlevel 0 on success or skip; nonzero only if cmake itself
rem fails (which the caller treats as a build error). Isolated in a label
rem so the cmd.exe IF parser doesn't choke on the parens in the VS path.
:rebuild_native
if not exist "%BUILD%\CMakeCache.txt" goto :rebuild_no_tree

set "CMAKE_EXE="
where cmake >nul 2>&1
if not errorlevel 1 set "CMAKE_EXE=cmake"
if defined CMAKE_EXE goto :rebuild_run

set "VS64=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if exist "%VS64%" set "CMAKE_EXE=%VS64%"
if defined CMAKE_EXE goto :rebuild_run

set "VS86=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if exist "%VS86%" set "CMAKE_EXE=%VS86%"
if defined CMAKE_EXE goto :rebuild_run

echo WARNING: cmake not found, skipping native rebuild.
echo          DLLs in %BUILD% may be stale relative to src/.
exit /b 0

:rebuild_no_tree
echo No build/ tree found, skipping native rebuild.
echo Run: cmake -S . -B build
echo to enable auto-rebuild on subsequent build.bat runs.
exit /b 0

:rebuild_run
echo Rebuilding native artifacts...
"%CMAKE_EXE%" --build "%BUILD%" --config Release
exit /b %ERRORLEVEL%

:end
endlocal
