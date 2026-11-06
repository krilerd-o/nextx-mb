@echo off
cd /d "%~dp0"
echo MOAI NEXT Mobile - Flutter SDK Installer
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-flutter.ps1"
pause
