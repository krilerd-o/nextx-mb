@echo off
setlocal EnableDelayedExpansion
REM Build release APK — ต้องติดตั้ง Android SDK และตั้ง ANDROID_HOME ก่อน
REM ผลลัพธ์: build\app\outputs\flutter-apk\app-release.apk
REM
REM ลำดับการหา API_BASE_URL ที่ฝังในแอป:
REM   1) ตัวแปรสภาพแวดล้อม API_BASE_URL
REM   2) บรรทัดแรกใน api_release_url.txt (ข้ามบรรทัดที่ขึ้นต้นด้วย #)
REM   3) ค่าเริ่มต้น https://moainext.moai-crm.com
REM
REM ติดตั้งบนมือถือ: ห้ามเปิด APK จากแอป RAR/ZIP โดยตรง — แตกไฟล์ออกมาก่อน แล้วแตะ app-release.apk จากโฟลเดอร์
REM (ไม่งั้นมักขึ้น "เกิดข้อผิดพลาดขณะกำลังแยกวิเคราะห์แพคเกจ")
REM
REM ดูล็อกรับส่ง API บน release APK: set DEBUG_API=1 ก่อนรัน build-apk.cmd แล้วดู logcat กรองคำว่า [API]
REM เปิด Alice (Inspector) ใน release APK: set ENABLE_ALICE=1 ก่อนรัน build-apk.cmd — เขย่าเครื่องหรือแตะการแจ้งเตือน

cd /d "%~dp0"

if "%ANDROID_HOME%"=="" (
  if exist "%LOCALAPPDATA%\Android\Sdk" set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
)

if "%ANDROID_HOME%"=="" (
  echo [ERROR] ไม่พบ Android SDK
  echo ติดตั้ง Android Studio หรือ Android SDK Command-line Tools แล้วตั้ง:
  echo   setx ANDROID_HOME "C:\Users\YOU\AppData\Local\Android\Sdk"
  echo จากนั้นเปิด CMD ใหม่ แล้วรัน build-apk.cmd อีกครั้ง
  exit /b 1
)

set "URL="
if not "%API_BASE_URL%"=="" set "URL=%API_BASE_URL%"

if "!URL!"=="" if exist "%~dp0api_release_url.txt" (
  for /f "usebackq tokens=* delims=" %%a in ("%~dp0api_release_url.txt") do (
    set "LINE=%%a"
    goto :first_url_line
  )
)
:first_url_line
if defined LINE (
  for /f "tokens=* delims= " %%a in ("!LINE!") do set "LINE=%%a"
  if not "!LINE!"=="" if not "!LINE:~0,1!"=="#" set "URL=!LINE!"
  set "LINE="
)

if "!URL!"=="" (
  set "URL=https://moainext.moai-crm.com"
  echo [INFO] ใช้ค่าเริ่มต้น production: !URL!
  echo.
)

echo ANDROID_HOME=%ANDROID_HOME%
echo API_BASE_URL=!URL!
set "DART_DEFINES=--dart-define=API_BASE_URL=!URL!"
if /i "%DEBUG_API%"=="1" (
  set "DART_DEFINES=!DART_DEFINES! --dart-define=DEBUG_API=true"
  echo DEBUG_API=true  ^(ล็อก HTTP ใน logcat — กรอง [API]^)
)
if /i "%ENABLE_ALICE%"=="1" (
  set "DART_DEFINES=!DART_DEFINES! --dart-define=ENABLE_ALICE=true"
  echo ENABLE_ALICE=true  ^(Alice HTTP Inspector ใน APK นี้^)
)
if not exist "%~dp0android\key.properties" (
  echo WARNING: android\key.properties not found - APK will be signed with the DEBUG key ^(internal testing only, not for Play Store^)
  set "NX_ALLOW_DEBUG_SIGNING=1"
)
echo.
call flutter build apk --release !DART_DEFINES!
if errorlevel 1 exit /b 1

echo.
echo APK: %cd%\build\app\outputs\flutter-apk\app-release.apk
echo.
echo --- ติดตั้งบน Android ---
echo อย่าเปิดจาก RAR/Zip ให้คัดลอก APK ไป Downloads แล้วแตะไฟล์จากแอป Files
echo ถ้าโหลดมา ตรวจขนาดไฟล์ ~20 MB ขึ้นไป ไม่ใช่ 0 KB
exit /b 0
