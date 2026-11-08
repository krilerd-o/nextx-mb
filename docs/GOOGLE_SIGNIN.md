# เข้าสู่ระบบด้วย Google บนแอปมือถือ

## อาการ

กดปุ่ม Google แล้วหน้าต่าง "เลือกบัญชี" ขึ้นทุกบัญชีพร้อมข้อความสีแดง **"บัญชีผู้ใช้งานผิดปกติ"** และเข้าสู่ระบบไม่ได้

## สาเหตุ

แอปใช้ Google Sign-In ผ่าน Credential Manager ของ Android โดยส่ง Web client ID ของเซิร์ฟเวอร์
(จาก `GET /api/auth/google/one-tap-config`) เป็น `serverClientId` เพื่อให้ได้ ID token ที่เซิร์ฟเวอร์ตรวจได้

Google จะยอมให้แอปขอ token ได้ก็ต่อเมื่อ **โปรเจกต์ Google Cloud เดียวกับ Web client นั้น**
มี **OAuth client ชนิด Android** ที่ตรงกับ

- package name: `com.moai.nextt.mobile`
- SHA-1 ของกุญแจที่ใช้เซ็น APK

ถ้าไม่ตรง ทุกบัญชีจะขึ้น "ผิดปกติ" แบบในภาพ

เดิม APK สำหรับทดสอบจาก CI เซ็นด้วย debug key ที่สร้างใหม่ทุกครั้งที่ build
SHA-1 จึงเปลี่ยนทุกเวอร์ชัน และลงทะเบียนไว้ล่วงหน้าไม่ได้

## สิ่งที่แก้ในแอปแล้ว

- APK debug และ APK ทดสอบจะเซ็นด้วย **กุญแจทดสอบคงที่** ถ้ามีไฟล์กุญแจ
  - SHA-1 จะไม่เปลี่ยนในแต่ละ build อีก
  - ไฟล์กุญแจไม่อยู่ใน git: CI สร้างจาก secret
- CI พิมพ์ SHA-1 ที่ต้องลงทะเบียนไว้ใน log ของขั้น "Signing keys"
- ถ้า Google ปฏิเสธเพราะตั้งค่าไม่ครบ แอปจะแจ้งเป็นข้อความที่อ่านเข้าใจ

## ขั้นที่ 1: สร้างกุญแจทดสอบ (ครั้งเดียว ในเครื่องของคุณ)

```bash
keytool -genkeypair -keystore tester.keystore -storetype PKCS12 -alias tester -keyalg RSA -keysize 2048 -validity 20000 -dname "CN=MOAI NEXT Tester, O=AI System, C=TH"
```

ตั้งรหัสผ่านเอง (ใช้รหัสเดียวกันทั้ง store และ key) แล้วดู SHA-1

```bash
keytool -list -v -keystore tester.keystore -alias tester | grep SHA1
```

## ขั้นที่ 2: ใส่ใน GitHub (Settings → Secrets and variables → Actions)

- `ANDROID_TESTER_KEYSTORE_BASE64` = ผลของ `base64 -w0 tester.keystore`
- `ANDROID_TESTER_KEYSTORE_PASSWORD` = รหัสผ่านที่ตั้งไว้
- ถ้ามีกุญแจ release เพิ่ม `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

ถ้าจะ build ในเครื่องของคุณเอง วาง `tester.keystore` ไว้ที่ `android/app/` แล้วสร้าง `android/tester.properties`
(ทั้งสองไฟล์ถูก git-ignore ไว้แล้ว)

```
storePassword=รหัสผ่าน
keyAlias=tester
keyPassword=รหัสผ่าน
```

## ขั้นที่ 3: ลงทะเบียนใน Google Cloud Console (ครั้งเดียว)

1. เปิดโปรเจกต์ที่มี Web client ID ซึ่งเซิร์ฟเวอร์ใช้ (ค่า `client_id` จาก `/api/auth/google/one-tap-config`)
2. APIs & Services → Credentials → Create credentials → OAuth client ID → **Android**
3. ใส่ Package name `com.moai.nextt.mobile` และ SHA-1 ของกุญแจทดสอบจากขั้นที่ 1
4. ถ้ามีกุญแจ release หรือส่งขึ้น Google Play ให้สร้าง Android client เพิ่มด้วย SHA-1 ของกุญแจนั้น
   - ถ้าใช้ Play App Signing ใช้ SHA-1 จาก Play Console → App integrity
5. OAuth consent screen ต้องอยู่สถานะ In production
   - ถ้ายังเป็น Testing ต้องเพิ่มอีเมลที่จะใช้ใน Test users

ไม่ต้องแก้เซิร์ฟเวอร์ NEXTX การตั้งค่าใน Google มีผลภายในไม่กี่นาที
จากนั้นติดตั้ง APK ที่ build ใหม่ แล้วลองเข้าสู่ระบบด้วย Google อีกครั้ง
