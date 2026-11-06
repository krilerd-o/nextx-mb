@echo off
cd /d "%~dp0"
echo Starting Flutter web (Docker only). API must run separately.
docker compose up -d web --no-deps
echo.
echo App:  http://localhost:8080
echo Run API in another window: run-api.cmd
echo (Use when full docker-compose stack would conflict — e.g. DB ports or you only want the web image)
echo.
pause
