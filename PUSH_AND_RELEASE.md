# Push (FCM) และ Release

## Firebase / FCM

1. สร้างโปรเจกต์ Firebase แล้วเพิ่มแอป Android (`com.moai.nextt.mobile`) และ iOS
2. ดาวน์โหลดไฟล์แล้ววางที่:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
3. ไฟล์เหล่านี้ถูก ignore ใน git — ใช้ตัวอย่าง:
   - `android/app/google-services.json.example`
4. รันบนเครื่องจริง/เอมู แล้วล็อกอิน — แอปจะขอ permission และ `POST /api/notifications/device-token`
5. Deep link:
   - Custom scheme: `moainext://app/...`
   - HTTPS App Links: `https://moainext.moai-crm.com/modules|workspace|calendar/...` (ต้องตั้ง Digital Asset Links บนเซิร์ฟเวอร์)
     - แอปรองรับ `/modules/:module`, `/modules/:module/view/:id`, `/modules/:module/:id` → แปลงเป็นหน้า CRM/FSM ในแอป
     - ทุก route ถูกตรวจสิทธิ์เมนู (`lib/core/navigation/route_access.dart`) ถ้าไม่มีสิทธิ์จะกลับหน้าหลัก
     - **ฝั่งเว็บ NEXTX ต้องเพิ่ม** `frontend/public/.well-known/assetlinks.json` (package `com.moai.nextt.mobile` + SHA-256 ของ release key)
       และ `apple-app-site-association` (`<TEAMID>.com.moai.nextt.mobile`, paths `/modules/*`, `/workspace/*`, `/calendar/*`)
6. Token FCM ที่ถูก rotate จะถูกส่งให้เซิร์ฟเวอร์ใหม่อัตโนมัติ (`DevicePushService.onTokenRefreshed`)

## Android release signing

1. สร้าง keystore (อย่า commit)
2. คัดลอก `android/key.properties.example` → `android/key.properties` แล้วใส่ค่าจริง
3. `flutter build appbundle --release` หรือ `flutter build apk --release`
4. **ถ้าไม่มี `key.properties` release build จะล้มทันที** (กันการเผลออัปโหลด APK/AAB ที่ sign ด้วย debug key)
   - สำหรับ APK ทดสอบภายในเท่านั้น: ตั้ง `NX_ALLOW_DEBUG_SIGNING=1` (`build-apk.cmd` ตั้งให้อัตโนมัติพร้อมคำเตือน)

### dart-define ที่เกี่ยวกับ release

| ค่า | ผล |
|---|---|
| `API_BASE_URL` | URL ของ NEXTX web API |
| `ALLOW_API_URL_EDIT=true` | เปิดให้แก้ Base URL ในหน้า Settings บน release (ปกติล็อกไว้) |
| `APP_VERSION` | ข้อความเวอร์ชันในหน้า Settings (ค่าเริ่มต้นตรงกับ `pubspec.yaml`) |

## iOS (ต้องมี Mac)

1. เปิด `ios/Runner.xcworkspace` ใน Xcode
2. ตั้ง `DEVELOPMENT_TEAM` และ signing — เปิด capability **Push Notifications** และ **Associated Domains**
   (ใช้ไฟล์ `ios/Runner/Runner.entitlements`; minimum iOS = 13.0)
3. วาง `GoogleService-Info.plist`
4. `flutter build ipa`

## หมายเหตุ Built-in Kotlin

Flutter 3.47 แนะนำ Built-in Kotlin แต่ปลั๊กอินบางตัว (เช่น ที่มากับ `alice` / `package_info_plus`) ยัง apply KGP อยู่ — โปรเจกต์นี้ใช้ `android.builtInKotlin=false` ชั่วคราวจนกว่าจะอัปปลั๊กอินได้

## เข้าสู่ระบบด้วย LINE / Google (ไม่ต้องแก้ backend)

### LINE
- แอปเปิด `{server}/api/auth/line` ใน WebView แล้วดัก URL `…/login?token=` ที่ backend redirect กลับมา
- ปุ่ม LINE จะแสดงเมื่อ `GET /api/auth/line/check` ตอบ `channel_id` (ตั้งค่า LINE Login บนเซิร์ฟเวอร์นั้นแล้ว)
- ใช้ได้กับบัญชีที่ผูก LINE แล้วเท่านั้น (บัญชีที่ยังไม่ผูก → ข้อความ "ยังไม่ได้ผูก LINE")

### Google
- แอปใช้ `google_sign_in` แล้วส่ง ID token ไป `POST /api/auth/google/one-tap`
- `serverClientId` มาจาก `GET /api/auth/google/one-tap-config` → `client_id` (web client ของเซิร์ฟเวอร์นั้น)
- **ต้องตั้งค่าใน Google Cloud (โปรเจคเดียวกับ web client ของแต่ละเซิร์ฟเวอร์):**
  - Android: สร้าง OAuth client ชนิด Android — package `com.moai.nextt.mobile` + SHA-1 ของคีย์ที่ sign (debug และ release)
  - iOS: สร้าง OAuth client ชนิด iOS (bundle `com.moai.nextt.mobile`) แล้วใส่ `GIDClientID` และ URL scheme (reversed client id) ใน `ios/Runner/Info.plist`
    ทดสอบบนเครื่องจริง — backend ตรวจ `aud` ของ token เทียบกับ web client
- ถ้ายังไม่ตั้งค่า ปุ่มจะกดแล้วแจ้ง error จาก Google ส่วนวิธีอื่นใช้ได้ตามปกติ
- `google_sign_in` initialize ได้ครั้งเดียวต่อการเปิดแอป — เปลี่ยนเซิร์ฟเวอร์ที่ใช้ Google client อื่น ต้องปิด-เปิดแอปใหม่
