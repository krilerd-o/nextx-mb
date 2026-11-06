# วิธีเชื่อมต่อ Database (PostgreSQL + MongoDB)

แอป MOAI NEXT Mobile เรียก **API (Node.js)** แล้ว API เป็นคนเชื่อมต่อ PostgreSQL และ MongoDB ตามค่าที่ตั้งใน **api/.env**

**ตรวจสอบว่าอะไรรันบน Docker:** ดู [ARCHITECTURE.md](ARCHITECTURE.md)  
**รัน Web และ Mobile พร้อมกัน + รองรับหลายคน:** ดู [WEB_AND_MOBILE.md](WEB_AND_MOBILE.md)

---

## วิธีที่ 1: ใช้ PostgreSQL / MongoDB จากโปรเจค Web (Docker) — แนะนำถ้ามีอยู่แล้ว

ถ้า **โปรเจค MOAI NEXT Web** รัน PostgreSQL (และ MongoDB) บน Docker อยู่แล้ว ให้ใช้ชุดเดียวกันได้เลย **ไม่ต้องรัน run-db.cmd หรือ Docker ของโปรเจค nextx-mb**

1. **ให้แน่ใจว่า Docker ของโปรเจค Web รันอยู่** (มี container PostgreSQL และถ้าใช้ MongoDB ก็รันด้วย)

2. เปิดไฟล์ **api/.env** ในโฟลเดอร์ **nextx-mb** แล้วตั้งค่าให้ตรงกับที่โปรเจค Web ใช้:
   - ถ้า Web ใช้พอร์ตมาตรฐาน (5432, 27017) ที่ **localhost** ให้ใช้แบบนี้ได้:
   ```env
   PG_HOST=localhost
   PG_PORT=5432
   PG_DATABASE=db_moai_next
   PG_USER=postgres
   PG_PASSWORD=postgres

   MONGO_URI=mongodb://localhost:27017
   MONGO_DB=nextx
   ```
   - ถ้า Web ใช้ชื่อ DB / user / password อื่น ให้ copy ค่าจากโปรเจค Web มาใส่ใน **api/.env** ให้ตรงกัน

3. บันทึก **api/.env** แล้วรัน API ของแอปมือถือ:
   ```cmd
   cd /d "D:\NEXTX Kit\Git\nextx-mb"
   run-api.cmd
   ```

4. เปิดแอปที่ http://localhost:8081 กด **Refresh** ที่การ์ด API Status  
   **PostgreSQL** และ **MongoDB** ควรเป็น ✓

**ถ้า PostgreSQL ยังเป็น ✗:**  
1. รัน `cd api` แล้ว `npm run test:db` จะบอกว่าเป็นเรื่อง connection หรือไม่มี database  
2. ถ้าขึ้นว่า **database "db_moai_next" does not exist** = เชื่อม Postgres ได้แล้ว แค่ยังไม่มี DB — ให้สร้างใน Postgres ของ Web:
   - ผ่าน pgAdmin หรือเครื่องมืออื่น: สร้าง database ชื่อ **db_moai_next**
   - หรือผ่าน Docker (ถ้า Postgres อยู่บน Docker ของโปรเจค Web): เปิดโฟลเดอร์โปรเจค Web แล้วรัน (แทนที่ `ชื่อ-container-postgres` ด้วยชื่อจริง):
     ```cmd
     docker exec -it ชื่อ-container-postgres psql -U postgres -c "CREATE DATABASE db_moai_next;"
     ```
     หาชื่อ container ได้จาก `docker ps` (ดูคอลัมน์ NAMES)
3. ค่า `PG_USER` / `PG_PASSWORD` ใน **api/.env** ต้องตรงกับที่โปรเจค Web ใช้

**ถ้ารัน run-db.cmd แล้วขึ้นว่า port 15433 ถูกใช้แล้ว:** แปลว่า Postgres ของโปรเจคนี้ (หรือบริการอื่น) ใช้พอร์ตนั้นอยู่แล้ว — แก้ `PG_PORT` ในไฟล์ **`.env`** ที่รากโปรเจกต์ (หรือแก้ `api/.env` ให้พอร์ตตรงกัน) หรือไม่รัน postgres ซ้ำจาก Docker ของ nextx-mb ถ้าใช้ Postgres จากโปรเจค Web อยู่แล้ว

---

## วิธีที่ 1b: ใช้ Postgres/Mongo จากโปรเจกต์ NEXTX (MOAI NEXT Web) — แนะนำถ้ารันเว็บอยู่แล้ว

เมื่อ **NEXTX** รัน `docker compose up -d` อยู่แล้ว (มี `moai-next-pg`, `moai-next-mongo`) ให้รัน Mobile API + Web แยกด้วย **`run-shared-db.cmd`** ใน **nextx-mb** — ใช้ DB ชุดเดียวกัน ไม่ต้องรัน Postgres/Mongo ของ nextx-mb (หลีกเลี่ยงชน port)

รายละเอียด: [README.md](README.md) หัวข้อ “รัน Mobile บน Docker แต่ใช้ DB ชุดเดียวกับเว็บ”

---

## วิธีที่ 2: รัน PostgreSQL + MongoDB ในโปรเจค nextx-mb เอง (Docker)

ถ้าติดตั้ง **Docker Desktop** แล้ว:

1. เปิด Command Prompt แล้วเข้าโฟลเดอร์โปรเจกต์:
   ```cmd
   cd /d "D:\NEXTX Kit\Git\nextx-mb"
   ```

2. รันแค่ PostgreSQL และ MongoDB (ไม่รัน API ใน Docker):
   ```cmd
   run-db.cmd
   ```
   หรือ `docker compose up -d postgres mongodb`

3. รอสักครู่ แล้วรัน API แยก (หน้าต่างเดิมหรือเปิดใหม่):
   ```cmd
   run-api.cmd
   ```

4. เปิดแอปที่ http://localhost:8081 แล้วกด Refresh ที่การ์ด API Status  
   - **PostgreSQL** และ **MongoDB** ควรเป็น ✓

ค่าใน **api/.env** ให้ตรงกับ Docker (ค่าเริ่มต้นจาก `api/.env.example`):

- `PG_HOST=127.0.0.1` หรือ `localhost`
- `PG_PORT=15433` — พอร์ตบนเครื่องที่ `docker-compose.yml` แมปจาก Postgres (ค่าเริ่มต้นใน compose คือ **15433** ไม่ใช่ 5432)
- `PG_DATABASE=db_moai_next`
- `PG_USER=postgres`
- `PG_PASSWORD=postgres`

ถ้าต้องการใช้พอร์ตอื่น ให้สร้างไฟล์ **`.env`** ที่รากโปรเจกต์ (ข้าง `docker-compose.yml`) แล้วใส่ `PG_PORT=xxxx` — Docker Compose จะอ่านค่านี้เมื่อรัน `docker compose up`

Docker จะสร้าง DB ตามค่า `PG_DATABASE` ใน .env (โปรเจค Web ใช้ **db_moai_next**)

---

## วิธีที่ 3: ติดตั้ง PostgreSQL เอง (ไม่ใช้ Docker)

1. ติดตั้ง PostgreSQL จาก https://www.postgresql.org/download/windows/

2. สร้างฐานข้อมูลชื่อ **nextx** (ผ่าน pgAdmin หรือ Command Line):
   ```sql
   CREATE DATABASE db_moai_next;
   ```

3. เปิดไฟล์ **api/.env** ให้ตรงกับที่ติดตั้งไว้ เช่น:
   ```env
   PG_HOST=localhost
   PG_PORT=5432
   PG_DATABASE=db_moai_next
   PG_USER=postgres
   PG_PASSWORD=รหัสที่ตั้งไว้
   ```

4. รัน API ใหม่:
   ```cmd
   run-api.cmd
   ```

5. ในแอปกด Refresh ที่ API Status — PostgreSQL ควรเป็น ✓

---

## สรุปตัวแปรใน api/.env

| ตัวแปร | ความหมาย | ค่าเริ่มต้น (Docker) |
|--------|----------|----------------------|
| PG_HOST | โฮสต์ PostgreSQL | localhost |
| PG_PORT | พอร์ต (ต้องตรงกับพอร์ตที่ Docker แมป) | **15433** เมื่อใช้ `docker-compose.yml` ของโปรเจคนี้ (ค่าเริ่มต้น) |
| PG_DATABASE | ชื่อฐานข้อมูล (ตรงกับ Web) | db_moai_next |
| PG_USER | Username | postgres |
| PG_PASSWORD | รหัสผ่าน | postgres |
| MONGO_URI | Connection string MongoDB | mongodb://localhost:27017 |
| MONGO_DB | ชื่อ DB ใน MongoDB | nextx |

แก้ **api/.env** แล้วต้องรัน **run-api.cmd** ใหม่ทุกครั้ง

---

## ทดสอบว่าเชื่อมต่อ DB ได้หรือไม่

จากโฟลเดอร์ **nextx-mb** รัน:

```cmd
cd api
npm run test:db
```

จะแสดง PostgreSQL: OK/FAIL และ MongoDB: OK/FAIL ตาม **api/.env** (ถ้า FAIL ให้ดูข้อความแจ้ง เช่น ไม่มี database ให้ตรวจสอบชื่อใน api/.env (โปรเจค Web ใช้ **db_moai_next**))
