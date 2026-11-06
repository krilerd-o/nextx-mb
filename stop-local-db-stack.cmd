@echo off
REM หยุด stack เต็มของ nextx-mb (postgres + mongo + api + web) จาก docker-compose.yml
REM ใช้เมื่อต้องการปล่อยพอร์ต 15433/27017/4000 และลบ orphan containers
cd /d "%~dp0"
echo docker compose -f docker-compose.yml down --remove-orphans
docker compose -f docker-compose.yml down --remove-orphans
echo.
echo Done. You can then use run-shared-db.cmd with NEXTX DB only.
pause
