# MOAI NEXT Mobile - เตรียมทุกอย่าง (Setup)
แอป Flutter เรียก **NEXTX web API** โดยตรง ไม่ใช้โฟลเดอร์ `api/` (พอร์ต 4000) เป็น runtime อีกต่อไป


## สคริปต์ที่รันก่อนเปิดโปรเจค

**รันสคริปต์นี้ก่อนเปิดโปรเจค (ครั้งแรกหรือหลัง clone):**

```powershell
.\run-before-open.ps1
```

สคริปต์จะ: สร้าง `api\.env`, ติดตั้ง API dependencies, รัน Docker ถ้ามี, สร้าง android/ios + `flutter pub get` ถ้ามี Flutter

---

## ดูหน้าจอแอปในเบราว์เซอร์ (ลิงค์)

รัน `run-web.cmd` หรือ `.\run-web.ps1` จากโฟลเดอร์โปรเจกต์ แล้วเปิดในเบราว์เซอร์:

**http://localhost:8081**

---

## สิ่งที่พร้อมแล้ว

- **API (Node.js)** รันได้แล้วที่ `http://localhost:4000`
  - ไม่ต้องมี PostgreSQL/MongoDB ก็รันได้ (ใช้ `/health` ได้ทันที)
  - มีไฟล์ `api/.env` แล้ว
- **Flutter** โค้ดพร้อม (`lib/`, `pubspec.yaml`) แต่ยังไม่มีโฟลเดอร์ `android/` และ `ios/`

---

## ขั้นตอนที่คุณต้องทำ (ครั้งแรก)

### 1. ติดตั้ง Flutter SDK

- ดาวน์โหลด: https://docs.flutter.dev/get-started/install/windows  
- แตกไฟล์แล้วเพิ่ม path ของโฟลเดอร์ `flutter\bin` ในตัวแปร PATH  
- เปิด Terminal ใหม่ แล้วรัน:
  ```powershell
  flutter doctor
  ```
  แก้ไขตามที่ doctor แนะนำ (Android Studio / เครื่องมืออื่นถ้าต้องการ)

### 2. สร้างโฟลเดอร์ Android และ iOS

ในโฟลเดอร์โปรเจกต์ (`D:\NEXTX Kit\Git\nextx-mb`):

```powershell
cd "D:\NEXTX Kit\Git\nextx-mb"
flutter create . --platforms android,ios --org com.nextx --project-name nextx_mobile
```

คำสั่งนี้จะเพิ่มโฟลเดอร์ `android/` และ `ios/` โดยไม่เขียนทับไฟล์ที่มีอยู่

### 3. ดึง dependencies ของ Flutter

```powershell
flutter pub get
```

### 4. รันแอป

- **Android:** ต่อเครื่องหรือเปิด Android Emulator แล้วรัน:
  ```powershell
  flutter run
  ```
- **iOS:** ใช้ได้บน Mac กับ Xcode เท่านั้น

---

## รัน API (ถ้ายังไม่รัน)

```powershell
.\run-api.ps1
```

หรือ:

```powershell
cd api
node src/index.js
```

API จะอยู่ที่ `http://localhost:4000`  
ทดสอบ: เปิดเบราว์เซอร์ไปที่ http://localhost:4000/health

---

## ใช้ Docker (PostgreSQL + MongoDB + API)

ถ้าต้องการรัน DB และ API ใน Docker:

1. ติดตั้ง Docker Desktop แล้วเปิดใช้งาน  
2. ในโฟลเดอร์โปรเจกต์:
   ```powershell
   docker compose up -d
   ```
3. รอให้ทุก service ขึ้น (PostgreSQL สร้าง DB ชื่อ `nextx` ให้อัตโนมัติ)  
4. API จะอยู่ที่ `http://localhost:4000` เหมือนเดิม  

หยุด Docker:

```powershell
docker compose down
```

---

## สรุปคำสั่งที่ใช้บ่อย

| งาน | คำสั่ง |
|-----|--------|
| ติดตั้ง/เตรียมครั้งแรก | `.\setup.ps1` |
| รัน API | `.\run-api.ps1` |
| รันแอป Flutter | `.\run-app.ps1` หรือ `flutter run` |
| หยุด Docker | `docker compose down` |

---

## หมายเหตุ

- แอป Flutter ตั้งค่าเรียก API ที่ `http://localhost:4000` (หรือใช้ `--dart-define=API_BASE_URL=...` ถ้าเปลี่ยน URL)  
- ถ้าใช้เครื่องจริง/เอมิวเลเตอร์ ให้ใช้ IP ของเครื่องที่รัน API แทน `localhost`
