@echo off
cd /d "%~dp0"
echo MOAI NEXT Mobile - Run on web (view in browser)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-web.ps1"
pause
