@echo off
REM Run this before opening project (works in Command Prompt)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-before-open.ps1"
pause
