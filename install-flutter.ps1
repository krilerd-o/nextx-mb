# MOAI NEXT Mobile - ติดตั้ง Flutter SDK อัตโนมัติ (Windows)
# Run as: .\install-flutter.ps1
# Or double-click install-flutter.cmd

$ErrorActionPreference = "Stop"
$InstallDir = "C:\flutter"
$FlutterVersion = "3.47.9"
$MinFlutterVersion = [version]"3.47.9"
$ZipUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"

Write-Host ""
Write-Host "MOAI NEXT Mobile - Flutter SDK Installer" -ForegroundColor Cyan
Write-Host "Target: Flutter $FlutterVersion (stable)" -ForegroundColor Gray
Write-Host ""

function Get-FlutterSemVer {
  param([string]$FlutterBat)
  try {
    $out = & $FlutterBat --version 2>&1 | Out-String
    if ($out -match 'Flutter\s+(\d+\.\d+\.\d+)') {
      return [version]$Matches[1]
    }
  } catch {}
  return $null
}

function Warn-If-Outdated {
  param([string]$FlutterCmd)
  $ver = Get-FlutterSemVer -FlutterBat $FlutterCmd
  if ($null -eq $ver) { return }
  if ($ver -lt $MinFlutterVersion) {
    Write-Host "Found Flutter $ver — this project requires $MinFlutterVersion+" -ForegroundColor Yellow
    Write-Host "Run: flutter channel stable && flutter upgrade" -ForegroundColor White
    Write-Host "Or reinstall with this script after removing the old SDK." -ForegroundColor Gray
    Write-Host ""
  }
}

# Already have Flutter?
$existing = $null
$flutterCmd = $null
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  $existing = "PATH"
  $flutterCmd = "flutter"
} else {
  foreach ($p in @("C:\flutter\bin", "C:\src\flutter\bin", "$env:LOCALAPPDATA\flutter\bin")) {
    if (Test-Path "$p\flutter.bat") {
      $existing = $p
      $flutterCmd = "$p\flutter.bat"
      break
    }
  }
}
if ($existing) {
  Write-Host "Flutter already found: $existing" -ForegroundColor Green
  & $flutterCmd --version
  Write-Host ""
  Warn-If-Outdated -FlutterCmd $flutterCmd
  Write-Host "You can run: run-web.cmd or run-app.cmd" -ForegroundColor White
  exit 0
}

# Check install dir
if (Test-Path $InstallDir) {
  $bin = Join-Path $InstallDir "bin\flutter.bat"
  if (Test-Path $bin) {
    Write-Host "Flutter found at $InstallDir but not in PATH." -ForegroundColor Yellow
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$InstallDir\bin*") {
      [Environment]::SetEnvironmentVariable("Path", "$InstallDir\bin;$currentPath", "User")
      Write-Host "Added $InstallDir\bin to user PATH. Please close and reopen Command Prompt." -ForegroundColor Green
    }
    Warn-If-Outdated -FlutterCmd $bin
    exit 0
  }
}

Write-Host "Flutter not found. Downloading Flutter $FlutterVersion to $InstallDir ..." -ForegroundColor Yellow
Write-Host "This may take a few minutes." -ForegroundColor Gray
Write-Host ""

$tempZip = [System.IO.Path]::GetTempFileName() + ".zip"
try {
  Invoke-WebRequest -Uri $ZipUrl -OutFile $tempZip -UseBasicParsing
} catch {
  Write-Host "Download failed. Try manual install: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Gray
  exit 1
}

if (-not (Test-Path $tempZip) -or (Get-Item $tempZip).Length -lt 1000000) {
  Write-Host "Download failed or file too small. Try manual install." -ForegroundColor Red
  exit 1
}

$parent = Split-Path $InstallDir -Parent
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
Write-Host "Extracting to $InstallDir ..." -ForegroundColor Yellow
Expand-Archive -Path $tempZip -DestinationPath $parent -Force
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue

$flutterBin = Join-Path $InstallDir "bin"
if (-not (Test-Path "$flutterBin\flutter.bat")) {
  Write-Host "Extract may have created a subfolder. Checking..." -ForegroundColor Gray
  $sub = Get-ChildItem $parent -Directory | Where-Object { Test-Path (Join-Path $_.FullName "bin\flutter.bat") } | Select-Object -First 1
  if ($sub) {
    if ($sub.FullName -ne $InstallDir) {
      if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
      Rename-Item $sub.FullName $InstallDir
    }
  }
}

if (-not (Test-Path "$InstallDir\bin\flutter.bat")) {
  Write-Host "Installation failed. Install manually from https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
  exit 1
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$InstallDir\bin*") {
  [Environment]::SetEnvironmentVariable("Path", "$InstallDir\bin;$currentPath", "User")
  $env:PATH = "$InstallDir\bin;$env:PATH"
  Write-Host "Added $InstallDir\bin to user PATH." -ForegroundColor Green
}

Write-Host ""
Write-Host "Flutter installed successfully." -ForegroundColor Green
Write-Host "Close this window and open a NEW Command Prompt, then run:" -ForegroundColor Yellow
Write-Host "  cd /d `"D:\NEXTX Kit\Git\nextx-mb`"" -ForegroundColor White
Write-Host "  run-web.cmd" -ForegroundColor White
Write-Host ""
