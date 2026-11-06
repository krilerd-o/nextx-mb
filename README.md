# MOAI NEXT Mobile App

แอปมือถือ Native (Flutter) สำหรับ MOAI NEXT ใช้ชุดข้อมูลและ Database เดียวกับโปรเจคเว็บ (MOAI NEXT Web)

แอปเรียก **NEXTX web API** โดยตรง (`https://moainext.moai-crm.com` หรือ `--dart-define=API_BASE_URL`). โฟลเดอร์ `api/` ใน repo นี้ไม่ใช่ runtime ของแอปมือถือแล้ว

- **App Store / Play Store** พร้อม Publish
- **Flutter:** 3.47.9+ (stable) / Dart 3.13+ — ดู [FLUTTER_SETUP.md](FLUTTER_SETUP.md)
- **FCM / Release:** ดู [PUSH_AND_RELEASE.md](PUSH_AND_RELEASE.md)
- **Tech stack:** Flutter, Docker, PostgreSQL, MongoDB, Node.js
- **สถาปัตยกรรม:** แอปสื่อสารกับ Database **ผ่าน API เท่านั้น** (ทั้งโปรเจค) — ไม่เชื่อม DB โดยตรง
- **Scale:** ออกแบบให้รองรับผู้ใช้จำนวนมาก (หลักพันคน) — ดู [SCALING.md](SCALING.md)
- **API มาตรฐานอิงเว็บ:** ดู [API_ALIGNMENT.md](API_ALIGNMENT.md)
- **Security มาตรฐาน (OAuth2):** ดู [SECURITY_STANDARD.md](SECURITY_STANDARD.md)
- **User Journey (MVP Phase 1–3):** Login → Hub → Getting Started → Dashboard/Search/HR — ดู [MOBILE_JOURNEY.md](MOBILE_JOURNEY.md)

**สถานะการรัน:** Flutter รันบน Docker ได้ (service `web` ใน docker-compose) หรือรันบนเครื่องด้วย `run-web.cmd` — **แนะนำตอนพัฒนาใช้ run-web.cmd** (hot reload สะดวก)  
API กับ DB รันบน Docker ได้ — ดู [ARCHITECTURE.md](ARCHITECTURE.md)

---

## วิธีรัน (ทุกครั้งที่เปิดโปรเจค)

เปิด **2 หน้าต่าง Command Prompt** (หรือ 1 หน้าต่าง + ดับเบิลคลิก)

| ลำดับ | งาน | คำสั่ง / ไฟล์ |
|-------|-----|----------------|
| 1 | เข้าโฟลเดอร์โปรเจกต์ | `cd /d "D:\NEXTX Kit\Git\nextx-mb"` |
| 2 | รัน API (หน้าต่างที่ 1) | `run-api.cmd` หรือดับเบิลคลิก `run-api.cmd` |
| 3 | รันแอป (หน้าต่างที่ 2) | **ดูในเบราว์เซอร์:** `run-web.cmd` → เปิด **http://localhost:8081** |
|  |  | **รันบนมือถือ/เอมิวเลเตอร์:** `run-app.cmd` |

- แอปจะเรียก **web API** (ค่าเริ่มต้น debug `http://10.0.2.2:8080` / release `https://moainext.moai-crm.com`) — ไม่ใช้ `api/` พอร์ต 4000
- ถ้า **PostgreSQL / MongoDB** ยังไม่รัน จะแสดง ✗ ใน API Status — รัน DB ก่อน: **run-db.cmd** (หรือ `docker compose up -d postgres mongodb`) จากโฟลเดอร์โปรเจกต์ แล้วรัน **run-api.cmd** ใหม่
- **ให้ PostgreSQL เขียว:** **api/.env** ต้องชี้พอร์ตเดียวกับ Docker — โปรเจคนี้แมป Postgres ไปที่พอร์ตโฮสต์ **15433** (ดู [DATABASE.md](DATABASE.md), ไฟล์ **env.docker.example**)

**ครั้งแรกเท่านั้น:** รัน `run-before-open.cmd` ก่อน (หรือ `install-flutter.cmd` ถ้ายังไม่มี Flutter)

---

## รัน Web และ Mobile พร้อมกัน + รองรับหลายคน

เมื่อรัน **โปรเจค Web (MOAI NEXT Web)** กับ **Mobile (nextx-mb)** พร้อมกัน ให้ใช้ DB ชุดเดียวกัน และจัดพอร์ตไม่ให้ชน (รันแบบ shared DB: Mobile API = **4000**, แอป web = **8080**)

- **คู่มือเต็ม:** [WEB_AND_MOBILE.md](WEB_AND_MOBILE.md) — ลำดับการรัน, การจัดพอร์ต, การตั้งค่า connection pool เพื่อรองรับผู้ใช้หลายคน
- **รองรับหลายคน:** API ใช้ connection pool (PostgreSQL default 50, MongoDB default 100) กำหนดเพิ่มได้ผ่าน `PG_POOL_SIZE` / `MONGO_POOL_SIZE` ใน **api/.env**

### รัน Mobile บน Docker แต่ใช้ DB ชุดเดียวกับเว็บ (แนะนำเวลาทำงานคู่กับ MOAI NEXT Web)

ถ้า stack เว็บ (**โปรเจกต์ NEXTX** — container `moai-next-pg`, `moai-next-mongo`) รันอยู่แล้ว ไม่ควรรัน `postgres` / `mongodb` ของ `nextx-mb` ซ้ำ — จะชน port (**15433**, **27017**)

ให้รันเฉพาะ **API + Web ของ Mobile** แล้ว join **network เดียวกับ stack เว็บ**:

1. สตาร์ทเว็บก่อน (จากโฟลเดอร์ **NEXTX**): `docker compose up -d`  
2. รัน **`run-shared-db.cmd`** — **`run-shared-db.ps1`** จะตั้ง **`NEXTX_NETWORK` อัตโนมัติ** จาก container `moai-next-pg`  
3. ค่าใน **`env.shared-db.example`** ตรงกับ NEXTX แล้ว: `NEXTX_PG_HOST=postgres`, `NEXTX_MONGO_URI=mongodb://mongo:27017` (ชื่อ service ใน compose คือ **`mongo`** ไม่ใช่ `mongodb`)  
4. ได้ **`moai-next-api-mb`** (พอร์ตโฮสต์เริ่มต้น **4000**) และ **`moai-next-web-mb`** (**8080**) — แยกจาก `moai-next-api` / `moai-next-web` ของเว็บ  
   - ถ้าพอร์ต **4000** ถูกใช้ (เช่น `nextx-mb-api-1` ค้าง) — ตั้ง `PORT_MB=4001` ใน `env.shared-db` แล้ว `docker compose ... up -d --build` หรือรัน **`stop-local-db-stack.cmd`**

ไฟล์: `docker-compose.shared-db.yml`, `env.shared-db.example`, `run-shared-db.ps1`, `stop-local-db-stack.cmd`

**หมายเหตุ (Docker web):** `Dockerfile.web` ใช้ **nginx reverse proxy** — แอปเรียก API ที่ **พอร์ตเดียวกับหน้าเว็บ** (เช่น `http://localhost:8080/health`) ไม่ต้องพึ่งพอร์ต 4000 ในเบราว์เซอร์ จึงลดปัญหา CORS และชน port กับ service อื่น  
ตรวจสอบ API: `http://localhost:8080/health` (หรือพอร์ต `WEB_PORT_MB` ที่ตั้ง)

---

## ก่อนเปิดโปรเจค (รันครั้งแรก)

- **Command Prompt (cmd):** ต้องไปที่โฟลเดอร์โปรเจกต์ก่อน (ใช้ `/d` ถ้าอยู่คนละ drive):
  ```cmd
  cd /d "D:\NEXTX Kit\Git\nextx-mb"
  run-before-open.cmd
  ```
  หรือดับเบิลคลิกที่ไฟล์ `run-before-open.cmd` ในโฟลเดอร์ nextx-mb (ใน Explorer)
- **PowerShell:** เปิดโฟลเดอร์โปรเจกต์ก่อน แล้วรัน:
  ```powershell
  cd "D:\NEXTX Kit\Git\nextx-mb"
  .\run-before-open.ps1
  ```

สคริปต์จะ: สร้าง `api\.env`, ติดตั้ง dependencies ของ API, รัน Docker ถ้ามี, สร้างโฟลเดอร์ android/ios และ `flutter pub get` ถ้ามี Flutter

---

## โครงสร้างโปรเจค

```
nextx-mb/
├── lib/                 # Flutter app
│   ├── main.dart
│   ├── app.dart
│   ├── screens/
│   └── services/        # API client เรียก backend
├── api/                 # Node.js API (เชื่อมต่อ DB เดียวกับ Web)
│   ├── src/
│   │   ├── index.js
│   │   └── db/
│   ├── package.json
│   └── Dockerfile
├── docker-compose.yml   # PostgreSQL, MongoDB, API
├── pubspec.yaml
└── README.md
```

---

## 1. ใช้ Database เดียวกับ MOAI NEXT Web

- ตั้งค่าใน `api/.env` (คัดจาก `api/.env.example`) ให้ชี้ไปที่ **PostgreSQL** และ **MongoDB** เดียวกับที่ใช้ในโปรเจคเว็บ
- ไม่ต้องรัน Docker ของ nextx-mb สำหรับ DB ถ้าใช้ DB ของ Web อยู่แล้ว — แค่รัน API โดยชี้ `PG_*` และ `MONGO_*` ไปที่ DB นั้น

---

## 2. รัน Backend (Node.js API)

API รันได้แม้ยังไม่มี PostgreSQL/MongoDB — endpoint `/health` ใช้ได้ทันที

**มาตรฐานที่ยกมาจากเว็บ**
- API response ใช้รูปแบบเดียวกัน:
  - Success: `{ "status":"S", "messagestatus":"Success", "data": { ... } }`
  - Error: `{ "status":"E", "messagestatus":"Error", "error_code":"...", "message":"..." }`
- มี endpoint `GET /api/health` และ `GET /api/me`
- `GET /api/me` ใช้ OAuth2 Bearer token เป็นหลัก (มี transition mode รองรับ legacy header/query ชั่วคราว)
- มี policy middleware: `public`, `authenticated`, `businessScoped`, `admin` และ `requireScope()`
- โครงสร้าง API แยกโมดูล: `src/routes/*`, `src/middleware/*`, `src/validation/*`

**Security env สำคัญ**
- `OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URI`
- `OAUTH_TOKEN_ENDPOINT`, `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET`, `OAUTH_REDIRECT_URI`
- `AUTH_TRANSITION_MODE`, `AUTH_TRANSITION_DEADLINE`
- `ALLOWED_ORIGINS` (CORS allowlist)

**Endpoint หลัก (Mobile-first)**
- `POST /api/auth/login` (token exchange)
- `GET /api/modules`
- `GET /api/fields/:module`
- `GET /api/picklists`
- `GET/POST/PUT/DELETE /api/entity/:module` และ `POST /api/entity/:module/:id/duplicate`
- `GET /ready` (readiness)

- **Command Prompt:** รัน `run-api.cmd` หรือดับเบิลคลิกที่ไฟล์ (จากโฟลเดอร์ nextx-mb)
- **PowerShell:** `.\run-api.ps1`

หรือ:

```bash
cd api
cp .env.example .env   # แก้ .env ให้ตรงกับ DB จริง (หรือใช้ค่าเดียวกับ Web)
npm install
npm run dev
```

API จะรันที่ `http://localhost:4000` (หรือค่า `PORT` ใน `.env`)

---

## 3. รันด้วย Docker (PostgreSQL + MongoDB + API + Flutter web)

### แบบเต็ม (ทุก service ใน Docker)
```cmd
run-all-docker.cmd
```
หรือ `docker compose up -d` — จากนั้นเปิด **http://localhost:8080** (ไม่ต้องรันแอปแยก)

**ถ้าขึ้นว่า port 15433 (Postgres) หรือ 27017 (Mongo) ถูกใช้แล้ว:** แก้พอร์ตใน **`.env`** ที่รากโปรเจกต์ / **api/.env** ให้ตรงกัน หรือถ้ามี Postgres จากโปรเจค Web อยู่แล้ว: รันเฉพาะแอปใน Docker แล้วรัน API บนเครื่อง:
```cmd
run-docker-web.cmd
```
จากนั้นเปิดหน้าต่างใหม่ รัน **run-api.cmd** แล้วเปิด **http://localhost:8080**

### สรุปสคริปต์รัน
| ไฟล์ | ใช้เมื่อ |
|------|----------|
| **run-all-docker.cmd** | รันทุกอย่างใน Docker (แอปไม่ต้องรันแยก) |
| **run-shared-db.cmd** | รันแค่ **moai-next-api-mb + moai-next-web-mb** โดยใช้ Postgres/Mongo จาก stack เว็บ (DB ชุดเดียว; API โฮสต์เริ่มต้น **4000**) |
| **stop-local-db-stack.cmd** | หยุด stack เต็ม `docker-compose.yml` (postgres/mongo/api/web) + `--remove-orphans` — ปล่อยพอร์ต 4000/15433/27017 |
| **run-docker-web.cmd** | รันเฉพาะแอปใน Docker (ต้องรัน run-api.cmd แยก — ใช้เมื่อพอร์ต DB ของ compose ชนกับเครื่อง) |
| **run-api.cmd** | รัน API บนเครื่อง |
| **run-web.cmd** | รันแอปบนเครื่อง (เหมาะตอนพัฒนา — hot reload) |

**หมายเหตุ:** Build ครั้งแรกของ image Flutter web อาจใช้เวลานาน (หลายนาที)  
**ตอนพัฒนา:** แนะนำใช้ **run-web.cmd** บนเครื่องแทน (hot reload ได้)

---

## ดูหน้าจอแอปในเบราว์เซอร์ (ลิงค์)

รันแอปแบบเว็บ แล้วเปิดลิงค์ในเบราว์เซอร์:

- **Command Prompt:** ต้องเข้าโฟลเดอร์โปรเจกต์ก่อน (ถ้าอยู่คนละ drive ใช้ `/d`):
  ```cmd
  cd /d "D:\NEXTX Kit\Git\nextx-mb"
  run-web.cmd
  ```
  หรือเปิดโฟลเดอร์ `nextx-mb` ใน Explorer แล้วดับเบิลคลิก `run-web.cmd`
- **PowerShell:** `cd "D:\NEXTX Kit\Git\nextx-mb"` แล้ว `.\run-web.ps1`

จากนั้นเปิดในเบราว์เซอร์: **http://localhost:8081**

(ครั้งแรกอาจสร้างโฟลเดอร์ `web` ให้อัตโนมัติ)

ถ้าเห็น **"Flutter not found in PATH"** ให้รัน **install-flutter.cmd** (ติดตั้งอัตโนมัติ) หรือดูวิธีติดตั้งใน [FLUTTER_SETUP.md](FLUTTER_SETUP.md)

---

## 4. รันแอป Flutter (มือถือ/เอมิวเลเตอร์)

ต้องติดตั้ง Flutter SDK และเพิ่มใน PATH ก่อน — ดูขั้นตอนใน [FLUTTER_SETUP.md](FLUTTER_SETUP.md) หรือ [ติดตั้ง Flutter (Windows)](https://docs.flutter.dev/get-started/install/windows)

- **Command Prompt:** รัน `run-app.cmd` หรือดับเบิลคลิก (จากโฟลเดอร์ nextx-mb)
- **PowerShell:** `.\run-app.ps1`

หรือ:

```bash
# สร้างโฟลเดอร์ android/ ios (ถ้ายังไม่มี)
flutter create . --platforms android,ios

flutter pub get
flutter run
```

- **Android:** ต่อเครื่องหรือเอมิวเลเตอร์ แล้ว `flutter run`
- **iOS:** ใช้ Mac + Xcode แล้ว `flutter run` (สำหรับขึ้น App Store)

แอปใช้ธีม Dark โมเดิร์น และออกแบบเน้น Performance (RepaintBoundary, animation แยก layer)

---

## 5. Publish ขึ้น Store

- **Android (Play Store):** สร้าง keystore, ตั้งค่า `android/app/build.gradle` (signingConfigs) แล้ว `flutter build appbundle`
- **iOS (App Store):** ตั้งค่า signing ใน Xcode, แล้ว `flutter build ipa`

---

## สรุป

| ส่วน | โฟลเดอร์/ไฟล์ | หมายเหตุ |
|------|----------------|----------|
| Mobile App | `lib/`, `pubspec.yaml` | Flutter, ลงได้ทั้ง App Store / Play Store |
| API | `api/` | Node.js เชื่อม PostgreSQL + MongoDB (ชุดข้อมูลเดียวกับ Web) |
| DB | ใช้ของ Web หรือรันจาก `docker-compose.yml` | กำหนดใน `api/.env` |
