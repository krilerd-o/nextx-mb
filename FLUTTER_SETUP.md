# ติดตั้ง Flutter (Windows)

โปรเจกต์นี้ต้องการ **Flutter 3.47.9+** (stable) และ **Dart 3.13+**

ถ้าเห็นข้อความ **"Flutter not found in PATH"** มี 2 ทางเลือก:

---

## วิธีที่ 1: ติดตั้งอัตโนมัติ (แนะนำ)

จากโฟลเดอร์โปรเจกต์ `nextx-mb` รัน:

```cmd
cd /d "D:\NEXTX Kit\Git\nextx-mb"
install-flutter.cmd
```

หรือดับเบิลคลิกที่ไฟล์ **install-flutter.cmd**

สคริปต์จะดาวน์โหลด Flutter SDK ไปที่ `C:\flutter` และเพิ่มใน PATH ให้  
**หลังติดตั้งเสร็จ ให้ปิด Command Prompt แล้วเปิดใหม่** จากนั้นรัน `run-web.cmd`

---

## วิธีที่ 2: ติดตั้งด้วยตัวเอง

### 1. ดาวน์โหลด Flutter SDK

- ไปที่: **https://docs.flutter.dev/get-started/install/windows**
- ดาวน์โหลดไฟล์ **flutter_windows_xxx.zip** (หรือใช้ git clone ตามในหน้าเว็บ)

---

## 2. แตกไฟล์

- แตก zip ไปที่โฟลเดอร์ที่ไม่มีช่องว่างใน path เช่น:
  - **C:\flutter** (แนะนำ)
  - หรือ **C:\src\flutter**

อย่าใส่ใน **C:\Program Files** (มีช่องว่าง)

---

## 3. เพิ่ม Flutter ใน PATH

1. กด **Win + R** พิมพ์ `sysdm.cpl` แล้วกด Enter  
2. แท็บ **Advanced** → **Environment Variables**  
3. ใต้ **User variables** เลือก **Path** → **Edit**  
4. กด **New** แล้วเพิ่ม path ของโฟลเดอร์ **bin** ของ Flutter เช่น:
   - `C:\flutter\bin`
5. กด **OK** ทุกหน้าต่าง  
6. **ปิด Command Prompt / Terminal แล้วเปิดใหม่** เพื่อให้ PATH อัปเดต

---

## 4. ตรวจสอบ

เปิด Command Prompt ใหม่ แล้วรัน:

```cmd
flutter doctor
```

ถ้าขึ้นรายการและไม่มี error แปลว่าพร้อมใช้ จากนั้นรัน:

```cmd
cd /d "D:\NEXTX Kit\Git\nextx-mb"
run-web.cmd
```

แล้วเปิดเบราว์เซอร์ที่ **http://localhost:8081**

---

## รูปโปรไฟล์ (`image_picker`) และแพลตฟอร์มมือถือ

โปรเจกต์นี้ใช้ **`image_picker`** เลือกรูปจาก gallery — เก็บเป็น **base64 ใน SharedPreferences** (ทุกแพลตฟอร์ม รวม Web)

### Web

- ไม่ต้องตั้ง permission ใน manifest — ใช้ file picker ของเบราว์เซอร์
- รูปถูกบีบขนาดแล้วเก็บใน prefs (จำกัดขนาดไฟล์ดิบก่อน encode)

### Android / iOS (เมื่อเพิ่มโฟลเดอร์แพลตฟอร์มด้วย `flutter create`)

รันจาก root โปรเจกต์ (ชื่อแพ็กเกจใน `pubspec.yaml` คือ `nextx_mobile`):

```cmd
cd /d "D:\NEXTX Kit\Git\nextx-mb"
flutter create . --platforms=android,ios
```

จากนั้น:

- **Android** (`android/app/src/main/AndroidManifest.xml`): ภายใน `<manifest>` เพิ่มถ้าต้องการถ่ายจากกล้อง  
  `android.permission.CAMERA`  
  สำหรับแค่ gallery บน Android 13+ มักใช้ photo picker โดยไม่ต้องขอ storage แบบเต็ม — ทดสอบบนอุปกรณ์จริง
- **iOS** (`ios/Runner/Info.plist`): เพิ่มคำอธิบายการใช้รูป เช่น  
  `NSPhotoLibraryUsageDescription` = ข้อความอธิบายให้ผู้ใช้  
  `NSCameraUsageDescription` = ถ้าเปิดใช้กล้อง

### Build APK (Android)

1. ติดตั้ง [Android Studio](https://developer.android.com/studio) หรืออย่างน้อย **Android SDK** + ยอมรับ license (`sdkmanager --licenses`)
2. ตั้งค่า environment (ตัวอย่าง path บน Windows):

   ```cmd
   setx ANDROID_HOME "%LOCALAPPDATA%\Android\Sdk"
   ```

   เปิด **Command Prompt ใหม่** แล้วตรวจ: `echo %ANDROID_HOME%`
3. จาก root โปรเจกต์:

   ```cmd
   cd /d "D:\NEXTX Kit\Git\nextx-mb"
   build-apk.cmd
   ```

   หรือ: `flutter build apk --release`

4. ไฟล์ APK อยู่ที่: `build\app\outputs\flutter-apk\app-release.apk`  
   Release ปัจจุบันใช้ **debug signing** ใน `android/app/build.gradle` — ก่อนอัปโหลด Play Store ให้ตั้ง signing จริง

### หมายเหตุ

โฟลเดอร์ `android/` ถูกสร้างด้วย `flutter create --platforms=android` — ใช้ร่วมกับขั้นตอน build APK ด้านบน
