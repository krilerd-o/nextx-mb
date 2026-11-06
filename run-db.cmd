@echo off
cd /d "%~dp0"
echo Starting PostgreSQL (host port default 15433) and MongoDB (27017)...
echo Optional: copy env.docker.example to .env here to override PG_PORT / MONGO_PORT.
docker compose up -d postgres mongodb
echo.
echo Done. Then run: run-api.cmd
echo Open app: http://localhost:8081 and refresh API Status.
pause
