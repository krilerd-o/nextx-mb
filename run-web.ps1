# MOAI NEXT Mobile - รันแอปบนเว็บ (ดูหน้าจอในเบราว์เซอร์)
Set-Location $PSScriptRoot

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
  $paths = @(
    "C:\flutter\bin",
    "C:\src\flutter\bin",
    "$env:LOCALAPPDATA\flutter\bin",
    "$env:USERPROFILE\flutter\bin",
    "$env:USERPROFILE\development\flutter\bin"
  )
  foreach ($p in $paths) {
    if (Test-Path "$p\flutter.bat") {
      $env:PATH = "$p;$env:PATH"
      $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
      if ($flutterCmd) { break }
    }
  }
}
if (-not $flutterCmd) {
  Write-Host "Flutter not found. Install Flutter SDK and add to PATH." -ForegroundColor Yellow
  Write-Host "  Download: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Gray
  Write-Host "  Or extract to C:\flutter and add C:\flutter\bin to PATH." -ForegroundColor Gray
  exit 1
}
if (-not (Test-Path "web")) {
  Write-Host "Adding web platform..."
  flutter create . --platforms web 2>$null
}
flutter pub get
Write-Host ""
$webPort = 8081
Write-Host "URL: http://localhost:$webPort (ถ้า 8080 ถูกใช้อยู่จะใช้พอร์ตนี้)" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""
flutter run -d web-server --web-port=$webPort
