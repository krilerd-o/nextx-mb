@echo off
cd /d "%~dp0"
echo MOAI NEXT Mobile - shared DB with NEXTX Web (moai-next-pg / moai-next-mongo)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-shared-db.ps1"
if errorlevel 1 (
  echo.
  echo If "network ... declared as external but could not be found":
  echo   1. Start NEXTX Web stack: cd to NEXTX folder, then docker compose up -d
  echo   2. Or set NEXTX_NETWORK in env.shared-db to match: docker network ls
  echo.
  pause
  exit /b 1
)
echo.
echo Done.
echo   Mobile Web:  http://localhost:8080   (WEB_PORT_MB in env.shared-db)
echo   Health/API:    http://localhost:8080/health   (nginx proxy - no browser CORS)
echo   API direct:    http://localhost:4000/health   (PORT_MB - optional curl)
echo.
pause
