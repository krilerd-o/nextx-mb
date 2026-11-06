# MOAI NEXT Mobile - รันแอป Flutter (ต้องติดตั้ง Flutter SDK ก่อน)
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "ไม่พบ Flutter ใน PATH. กรุณาติดตั้ง Flutter SDK แล้วเพิ่มใน PATH" -ForegroundColor Yellow
  exit 1
}
flutter pub get
flutter run
