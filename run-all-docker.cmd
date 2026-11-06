@echo off
cd /d "%~dp0"
echo Starting all services (Postgres, Mongo, API, Flutter web)...
docker compose up -d
echo.
echo Done. No need to run the app separately.
echo   App:  http://localhost:8080
echo   API (via nginx proxy):  http://localhost:8080/health
echo   API direct (optional):    http://localhost:4000/health
echo.
pause
