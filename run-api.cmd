@echo off
cd /d "%~dp0"
echo Starting MOAI NEXT Mobile API...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-api.ps1"
