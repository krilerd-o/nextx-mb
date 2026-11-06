# ============================================================
# รันสคริปต์นี้ก่อนเปิดโปรเจค (Run this before opening project)
# Usage: .\run-before-open.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

Write-Host ""
Write-Host "  MOAI NEXT Mobile - Run before opening project" -ForegroundColor Cyan
Write-Host ""

# 1. API .env
if (-not (Test-Path "$ProjectRoot\api\.env")) {
  Copy-Item "$ProjectRoot\api\.env.example" "$ProjectRoot\api\.env"
  Write-Host "  [OK] api\.env created" -ForegroundColor Green
} else {
  Write-Host "  [--] api\.env exists" -ForegroundColor Gray
}

# 2. API dependencies
Write-Host "  [...] API: npm install..." -ForegroundColor Yellow
Push-Location "$ProjectRoot\api"
npm install --silent 2>$null; if ($LASTEXITCODE -ne 0) { npm install }
Pop-Location
Write-Host "  [OK] API ready" -ForegroundColor Green

# 3. Docker (optional)
if (Get-Command docker -ErrorAction SilentlyContinue) {
  Write-Host "  [...] Docker: starting..." -ForegroundColor Yellow
  Push-Location $ProjectRoot
  docker compose up -d 2>$null
  Pop-Location
  if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] Docker running" -ForegroundColor Green }
  else { Write-Host "  [--] Docker skip (run API with .\run-api.ps1)" -ForegroundColor Gray }
} else {
  Write-Host "  [--] Docker not found (run API with .\run-api.ps1)" -ForegroundColor Gray
}

# 4. Flutter
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  Push-Location $ProjectRoot
  if (-not (Test-Path "android")) {
    Write-Host "  [...] Flutter: creating android/ios..." -ForegroundColor Yellow
    flutter create . --platforms android,ios --org com.nextx --project-name nextx_mobile 2>$null
  }
  Write-Host "  [...] Flutter: pub get..." -ForegroundColor Yellow
  flutter pub get 2>$null
  Pop-Location
  Write-Host "  [OK] Flutter ready" -ForegroundColor Green
} else {
  Write-Host "  [!!] Flutter not in PATH - install then run:" -ForegroundColor Yellow
  Write-Host "       flutter create . --platforms android,ios" -ForegroundColor Gray
  Write-Host "       flutter pub get" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Done. You can open the project now." -ForegroundColor Green
Write-Host "  Run API: .\run-api.ps1  |  Run app: .\run-app.ps1" -ForegroundColor White
Write-Host ""
