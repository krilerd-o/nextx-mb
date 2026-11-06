# สถานะการรัน: อะไรอยู่บน Docker / อะไรรันบนเครื่อง

**สถาปัตยกรรม:** แอปสื่อสารกับ Database **ผ่าน API เท่านั้น** (ทั้งโปรเจค) — รองรับผู้ใช้หลักพันคน ดู [SCALING.md](SCALING.md)

## แนะนำ

- **ตอนพัฒนา (dev):** ใช้ **run-web.cmd** รัน Flutter บนเครื่อง — ได้ **hot reload** แก้โค้ดแล้วเห็นผลทันที
- **รันแบบทั้งหมดใน Docker:** ใช้ `docker compose up -d` ได้ รวม **Flutter web** (build แล้ว serve ด้วย nginx ที่พอร์ต 8080) — เหมาะสำหรับทดสอบแบบ production หรือไม่ต้องการติดตั้ง Flutter บนเครื่อง

---

## สรุป

| ส่วน | อยู่บน Docker หรือไม่ | หมายเหตุ |
|------|------------------------|----------|
| **Flutter (แอป)** | ได้ทั้งคู่ | **Docker:** service `web` (build แล้ว serve ด้วย nginx, พอร์ต 8080) / **บนเครื่อง:** `run-web.cmd` (เหมาะกับพัฒนา — hot reload) |
| **API (Node.js)** | ได้ทั้งคู่ | รันบนเครื่อง: `run-api.cmd` หรือรันใน Docker: `docker compose up api` |
| **PostgreSQL** | ได้ทั้งคู่ | ใช้จาก Docker ของโปรเจค Web หรือรันใน Docker ของโปรเจคนี้ |
| **MongoDB** | ได้ทั้งคู่ | ใช้จาก Docker ของโปรเจค Web หรือรันใน Docker ของโปรเจคนี้ |

---

## รายละเอียด

### Flutter
- **รันบน Docker ได้:** service ชื่อ `web` ใน docker-compose — build Flutter web แล้ว serve ด้วย nginx, เปิด **http://localhost:8080**
- **รันบนเครื่อง:** `run-web.cmd` หรือ `flutter run -d web-server` (เหมาะกับพัฒนา เพราะ hot reload ได้)
- **แนะนำ:** ตอนพัฒนาใช้ `run-web.cmd` บนเครื่อง; ใช้ Docker เมื่ออยากรันแบบ “ทั้งหมดใน container” หรือทดสอบ build จริง

### API (Node.js)
- **มี Dockerfile** ที่ `api/Dockerfile`
- **ใน docker-compose.yml** มี service ชื่อ `api` — รันได้ด้วย `docker compose up api` (หรือ `docker compose up` เพื่อรันทุก service)
- **รันบนเครื่อง:** `run-api.cmd` หรือ `cd api && node src/index.js`
- ถ้ารันใน Docker, API จะเชื่อม Postgres/Mongo ผ่านชื่อ service (`postgres`, `mongodb`) ไม่ใช่ localhost

### PostgreSQL
- **ใน docker-compose.yml** มี service ชื่อ `postgres`
- รันได้ด้วย `docker compose up postgres` หรือ `run-db.cmd` (รัน postgres + mongodb)
- ถ้าใช้ Postgres จาก **โปรเจค Web** ที่รัน Docker อยู่แล้ว — ไม่ต้องรัน postgres ของโปรเจคนี้ แค่ตั้ง **api/.env** ให้ชี้ไปที่ localhost:5432 และใช้ชื่อ DB ตรงกับ Web (เช่น `db_moai_next`)

### MongoDB
- **ใน docker-compose.yml** มี service ชื่อ `mongodb`
- รันได้ด้วย `docker compose up mongodb`
- ถ้าใช้จากโปรเจค Web — ตั้ง **api/.env** ให้ `MONGO_URI=mongodb://localhost:27017` และ `MONGO_DB` ตรงกับ Web

---

## วิธีรันแบบ “ให้ครบและชัด”

### แบบที่ 1: ใช้ DB จากโปรเจค Web (แนะนำถ้ามี Web รันอยู่แล้ว)
1. ให้ Docker ของโปรเจค Web รัน Postgres (และ Mongo) อยู่
2. ตั้ง **api/.env** ให้ `PG_DATABASE=db_moai_next` และค่าอื่นตรงกับ Web
3. รัน API บนเครื่อง: **run-api.cmd**
4. รัน Flutter บนเครื่อง: **run-web.cmd** แล้วเปิด http://localhost:8081

### แบบที่ 2: รันทุกอย่างใน Docker (รวม Flutter web)
1. จากโฟลเดอร์ nextx-mb: **run-all-docker.cmd** หรือ `docker compose up -d`
2. จะได้ Postgres, MongoDB, API, **Web (Flutter)** รันใน Docker — **ไม่ต้องรันแอปแยก**
3. เปิดเบราว์เซอร์ที่ **http://localhost:8080**

**ถ้า port 5432 ถูกใช้ (มี Postgres จาก Web):** รันเฉพาะแอปใน Docker แล้วรัน API บนเครื่อง: **run-docker-web.cmd** จากนั้นรัน **run-api.cmd** ในอีกหน้าต่าง

**หมายเหตุ:** Build ครั้งแรกของ image `web` อาจใช้เวลานาน (ต้อง build Flutter ใน Docker)

### แบบที่ 3: รัน API + DB บนเครื่อง (ไม่ใช้ Docker)
1. ติดตั้ง Postgres และ Mongo บนเครื่อง แล้วสร้าง DB ตามที่กำหนด
2. ตั้ง **api/.env** ให้ชี้ไปที่ localhost
3. รัน **run-api.cmd** แล้ว **run-web.cmd**

---

แก้ **api/.env** แล้วต้องรัน API ใหม่ (หรือ restart container api ถ้ารันใน Docker) ทุกครั้ง
