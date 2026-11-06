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

## Android release signing

1. สร้าง keystore (อย่า commit)
2. คัดลอก `android/key.properties.example` → `android/key.properties` แล้วใส่ค่าจริง
3. `flutter build appbundle --release` หรือ `flutter build apk --release`

## iOS (ต้องมี Mac)

1. เปิด `ios/Runner.xcworkspace` ใน Xcode
2. ตั้ง `DEVELOPMENT_TEAM` และ signing
3. วาง `GoogleService-Info.plist`
4. `flutter build ipa`

## หมายเหตุ Built-in Kotlin

Flutter 3.47 แนะนำ Built-in Kotlin แต่ปลั๊กอินบางตัว (เช่น ที่มากับ `alice` / `package_info_plus`) ยัง apply KGP อยู่ — โปรเจกต์นี้ใช้ `android.builtInKotlin=false` ชั่วคราวจนกว่าจะอัปปลั๊กอินได้
