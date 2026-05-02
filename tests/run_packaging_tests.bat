@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\test_packaging.ps1"
exit /b %ERRORLEVEL%
