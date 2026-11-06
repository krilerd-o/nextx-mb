@echo off
cd /d "%~dp0"
echo MOAI NEXT Mobile - Flutter app
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-app.ps1"
