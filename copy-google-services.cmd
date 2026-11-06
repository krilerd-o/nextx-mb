@echo off
setlocal
REM Copies google-services.json from Downloads into android\app for Firebase MOAI NEXTT
set "SRC=%USERPROFILE%\Downloads\google-services.json"
set "DST=%~dp0android\app\google-services.json"
if exist "%SRC%" (
  copy /Y "%SRC%" "%DST%" >nul
  echo Copied to %DST%
  exit /b 0
)
echo [MISSING] %SRC%
echo Add Android app com.moai.nextt.mobile in Firebase, download google-services.json, then run this again.
exit /b 1
