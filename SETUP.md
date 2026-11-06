# MOAI NEXT Mobile — เตรียมเครื่องครั้งแรก

1. **ติดตั้ง Flutter 3.47.9+** — ดู [FLUTTER_SETUP.md](FLUTTER_SETUP.md) (หรือรัน `install-flutter.cmd`)
2. **Android:** ติดตั้ง Android Studio + Android SDK, ตั้ง `ANDROID_HOME`, เปิด emulator หรือเสียบมือถือ (เปิด USB debugging)
3. **iOS (ต้องมี Mac):** Xcode + CocoaPods แล้ว `cd ios && pod install`
4. ในโฟลเดอร์โปรเจค:
   ```bat
   flutter pub get
   flutter doctor
   flutter test
   ```
5. **Push notification (ไม่บังคับตอนพัฒนา):** วาง `android/app/google-services.json` และ `ios/Runner/GoogleService-Info.plist` — ดู [PUSH_AND_RELEASE.md](PUSH_AND_RELEASE.md)
6. รัน: `run-app.cmd` (มือถือ) หรือ `run-web.cmd` + `node tool/moainext_web_proxy.mjs` (เบราว์เซอร์)

ไม่ต้องรัน database หรือ Node API ในเครื่อง — แอปใช้ NEXTX web API (`https://moainext.moai-crm.com`)
สคริปต์ `run-api.cmd`, `run-db.cmd`, `docker-compose*.yml` เป็นของโฟลเดอร์ `api/` แบบ legacy
