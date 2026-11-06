# MOAI NEXT Mobile App (nextx-mb)

แอปมือถือ Flutter สำหรับ MOAI NEXT (Android / iOS / ดูบนเว็บตอนพัฒนา)

- แอปเรียก **NEXTX web API โดยตรง** — ค่าเริ่มต้น `https://moainext.moai-crm.com`
  (เปลี่ยนได้ด้วย `--dart-define=API_BASE_URL=...`)
- ใช้บัญชี ข้อมูล และสิทธิ์เมนูชุดเดียวกับเว็บ (`/api/me`, `/api/me/menus`)
- โฟลเดอร์ `api/` เป็น **legacy** (Node API ทดลองพอร์ต 4000) — แอปไม่ได้ใช้แล้ว เก็บไว้อ้างอิงเท่านั้น
- Flutter **3.47.9+** / Dart 3.13+ — ติดตั้งดู [FLUTTER_SETUP.md](FLUTTER_SETUP.md)

| เอกสาร | เนื้อหา |
|---|---|
| [MOBILE_JOURNEY.md](MOBILE_JOURNEY.md) | ฟีเจอร์ทั้งหมด สถานะ และสิ่งที่ยังขาด |
| [PUSH_AND_RELEASE.md](PUSH_AND_RELEASE.md) | Firebase/FCM, deep link, signing, ออก release |
| [SETUP.md](SETUP.md) | เตรียมเครื่องครั้งแรก |
| [ARCHITECTURE.md](ARCHITECTURE.md) | โครงสร้างโค้ด และการไหลของข้อมูล |
| [API_ALIGNMENT.md](API_ALIGNMENT.md) | รูปแบบ API ของ NEXTX (S/E envelope) |

---

## รันทุกวัน

```bat
cd /d "D:\NEXTX Kit\Git\nextx-mb"
flutter pub get
```

| ต้องการ | คำสั่ง |
|---|---|
| รันบนมือถือ / เอมิวเลเตอร์ | `run-app.cmd` (หรือ `flutter run`) |
| ดูในเบราว์เซอร์ | หน้าต่างที่ 1: `node tool/moainext_web_proxy.mjs` (แก้ CORS ไป production) · หน้าต่างที่ 2: `run-web.cmd` → http://localhost:8081 |
| ชี้ไปเซิร์ฟเวอร์อื่น | `flutter run --dart-define=API_BASE_URL=https://your-host` |
| ตรวจโค้ด | `flutter analyze` |
| รันเทสต์ | `flutter test` |

> บน Flutter web โหมด debug แอปจะเรียกผ่าน proxy `http://127.0.0.1:8787` อัตโนมัติเมื่อชี้ production (ดู `resolveApiBaseUrl`)

## Build

| เป้าหมาย | คำสั่ง | หมายเหตุ |
|---|---|---|
| APK ทดสอบภายใน | `build-apk.cmd` | ถ้าไม่มี `android/key.properties` จะ sign ด้วย debug key พร้อมคำเตือน |
| Play Store | `flutter build appbundle --release` | **ต้องมี** `android/key.properties` ไม่เช่นนั้น build จะล้ม |
| App Store | `flutter build ipa` | ต้องใช้ Mac + Xcode signing |

ตัวเลือกตอน build: `API_BASE_URL`, `ALLOW_API_URL_EDIT=true` (เปิดแก้ Base URL บน release), `APP_VERSION`, `DEBUG_API=true`, `ENABLE_ALICE=true`

## CI

`.github/workflows/flutter-ci.yml` รันทุก push/PR: `flutter analyze` → `flutter test` → build debug APK (เก็บเป็น artifact 7 วัน)

## โครงสร้างโปรเจค

```
lib/
  core/          ตั้งค่า, session, สิทธิ์เมนู, router, deep link, error reporting
  services/      ApiClient (ทุก endpoint), realtime (Socket.IO), push, offline queue, unread
  screens/       หน้าจอแยกตามโมดูล (crm, fsm, hr, chat, mail, files, calendar, workspace,
                 approvals, commerce, notifications, ai, dashboard, ...)
  widgets/       UI กลาง (header, การ์ด, ฟอร์มตาม field schema ของ NEXTX)
test/            unit + widget tests (test/support/fake_api.dart จำลอง API)
android/ ios/    โปรเจค native
api/             legacy — ไม่ได้ใช้
```

## ข้อตกลงการ commit

ขึ้นต้นด้วย `[NEXTX-MB]` ตามด้วยคำอธิบายภาษาไทยที่อ่านเข้าใจง่าย
