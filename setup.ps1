# MOAI NEXT Mobile - Setup (run from project root: .\setup.ps1)
$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

Write-Host "`n=== MOAI NEXT Mobile - Setup ===" -ForegroundColor Cyan
Write-Host ""

# 1. API .env
if (-not (Test-Path "$ProjectRoot\api\.env")) {
  Copy-Item "$ProjectRoot\api\.env.example" "$ProjectRoot\api\.env"
  Write-Host "[OK] Created api\.env" -ForegroundColor Green
} else {
  Write-Host "[--] api\.env exists" -ForegroundColor Gray
}

# 2. API npm install
Write-Host "[...] Installing API dependencies..." -ForegroundColor Yellow
Push-Location "$ProjectRoot\api"
npm install
if ($LASTEXITCODE -ne 0) { exit 1 }
Pop-Location
Write-Host "[OK] API dependencies ready" -ForegroundColor Green

# 3. Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
  Write-Host "[...] Starting Docker (PostgreSQL, MongoDB, API)..." -ForegroundColor Yellow
  Push-Location $ProjectRoot
  docker compose up -d
  Pop-Location
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Docker services running - API at http://localhost:4000" -ForegroundColor Green
  } else {
    Write-Host "[!!] Docker compose failed - you can run API locally" -ForegroundColor Yellow
  }
} else {
  Write-Host "[--] Docker not found - skip. Run API with .\run-api.ps1" -ForegroundColor Gray
}

# 4. Flutter
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  Write-Host "[...] Preparing Flutter (android/ios + pub get)..." -ForegroundColor Yellow
  Push-Location $ProjectRoot
  if (-not (Test-Path "android")) {
    flutter create . --platforms android,ios --org com.nextx --project-name nextx_mobile
  }
  flutter pub get
  Pop-Location
  Write-Host "[OK] Flutter ready - run .\run-app.ps1" -ForegroundColor Green
} else {
  Write-Host "[!!] Flutter not in PATH" -ForegroundColor Yellow
  Write-Host "    Install: https://docs.flutter.dev/get-started/install" -ForegroundColor Gray
  Write-Host "    Then: flutter create . --platforms android,ios" -ForegroundColor Gray
  Write-Host "    Then: flutter pub get ; flutter run" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "  Run API (no Docker): .\run-api.ps1" -ForegroundColor White
Write-Host "  Run Flutter app:     .\run-app.ps1" -ForegroundColor White
Write-Host "  Stop Docker:         docker compose down" -ForegroundColor White
Write-Host ""
