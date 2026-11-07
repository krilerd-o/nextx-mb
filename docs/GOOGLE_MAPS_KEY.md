# ตั้งค่า Google Maps (หน้าเช็คอิน/เช็คเอาท์)

ถ้ายังไม่ใส่ key แอปยังใช้งานได้ปกติ เพียงแต่จะแสดงการ์ดพิกัด + ปุ่ม "ดูใน Google Maps" แทนแผนที่

## 1. สร้าง key
1. เปิด Google Cloud Console → APIs & Services
2. เปิดใช้ **Maps SDK for Android** และ **Maps SDK for iOS**
3. สร้าง API key แล้วจำกัดสิทธิ์ (Application restrictions) ดังนี้
   - **Android:** package `com.moai.nextt.mobile` + SHA-1 ของ keystore ที่ใช้ sign
   - **iOS:** bundle id ของแอป

## 2. ใส่ key (ห้าม commit key ลง Git)
| ที่ใช้ | วิธีใส่ |
|---|---|
| GitHub Actions (APK ทดสอบ) | Settings → Secrets → Actions → เพิ่ม `MAPS_API_KEY` (CI จะเปิดแผนที่ให้อัตโนมัติเมื่อมี secret นี้) |
| build ในเครื่อง Android | เพิ่มบรรทัด `MAPS_API_KEY=xxxx` ใน `android/local.properties` แล้ว build พร้อม `--dart-define=NX_MAPS=1` |
| iOS | ตั้ง build setting `GMS_API_KEY` ใน Xcode (Info.plist อ่านจาก `$(GMS_API_KEY)`) แล้ว build พร้อม `--dart-define=NX_MAPS=1` |
