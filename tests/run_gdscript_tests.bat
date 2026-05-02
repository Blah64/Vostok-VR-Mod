@echo off
setlocal

set "ROOT=%~dp0.."
set "GODOT=C:\Games\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"

if not exist "%GODOT%" (
	echo ERROR: Godot binary not found at %GODOT%
	echo Edit tests\run_gdscript_tests.bat to point at your install.
	exit /b 1
)

"%GODOT%" --headless --path "%ROOT%" --script res://tests/gdscript/run_tests.gd
exit /b %ERRORLEVEL%
