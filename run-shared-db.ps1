# MOAI NEXT Mobile — join stack MOAI NEXT Web (NEXTX) ใช้ DB เดียว
# ตรวจจับชื่อ Docker network จาก container moai-next-pg อัตโนมัติ
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$envFile = Join-Path $PSScriptRoot "env.shared-db"
$example = Join-Path $PSScriptRoot "env.shared-db.example"
if (-not (Test-Path $envFile)) {
  Copy-Item $example $envFile
  Write-Host "Created env.shared-db from env.shared-db.example" -ForegroundColor Cyan
}

$detected = $null
$raw = docker inspect moai-next-pg 2>$null
if ($LASTEXITCODE -eq 0 -and $raw) {
  try {
    $j = $raw | ConvertFrom-Json
    if ($j -and $j[0].NetworkSettings.Networks) {
      $names = @($j[0].NetworkSettings.Networks.PSObject.Properties | ForEach-Object { $_.Name })
      if ($names.Count -gt 0) { $detected = $names[0] }
    }
  } catch {
    $detected = $null
  }
}

if ($detected) {
  $env:NEXTX_NETWORK = $detected
  Write-Host "[OK] NEXTX_NETWORK=$detected (auto from container moai-next-pg)" -ForegroundColor Green
  # Persist so plain `docker compose --env-file env.shared-db ...` matches (Compose project = nextx_default)
  $lines = Get-Content -LiteralPath $envFile -Encoding UTF8
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match '^\s*NEXTX_NETWORK=') {
      $found = $true
      "NEXTX_NETWORK=$detected"
    } else {
      $line
    }
  }
  if (-not $found) { $out = @($out) + "NEXTX_NETWORK=$detected" }
  $out | Set-Content -LiteralPath $envFile -Encoding UTF8
  Write-Host "     Saved NEXTX_NETWORK to env.shared-db" -ForegroundColor Gray
} else {
  Write-Host "[!!] Cannot detect network from moai-next-pg. Start Web stack (NEXTX) first, or set NEXTX_NETWORK in env.shared-db" -ForegroundColor Yellow
  Write-Host "     docker network ls   # e.g. nextx_default" -ForegroundColor Gray
}

docker compose --env-file $envFile -f docker-compose.shared-db.yml up -d --build
exit $LASTEXITCODE
