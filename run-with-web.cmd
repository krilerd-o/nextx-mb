@echo off
cd /d "%~dp0"
echo ========================================
echo  Run Web + Mobile together
echo ========================================
echo.
echo 1. Start Web project: run Docker + Web app (in Web project folder)
echo 2. In this folder, run: run-api.cmd  (window 1)
echo 3. In this folder, run: run-web.cmd  (window 2)
echo 4. Open: http://localhost:8081 (or 8080) for Mobile app
echo.
echo See WEB_AND_MOBILE.md for details and multi-user setup.
echo.
pause
