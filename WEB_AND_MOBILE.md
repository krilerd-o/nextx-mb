# รัน Web และ Mobile พร้อมกัน + รองรับผู้ใช้หลายคน

## 1. รัน Web และ Mobile พร้อมกัน

โปรเจค **MOAI NEXT Web** กับ **MOAI NEXT Mobile** ใช้ **Database ชุดเดียวกัน** (PostgreSQL `db_moai_next`, MongoDB) จึงรันพร้อมกันได้ โดยจัดพอร์ตไม่ให้ชนกัน

### การจัดพอร์ต (แนะนำ)

| บริการ | พอร์ต | หมายเหตุ |
|--------|-------|----------|
| PostgreSQL | 5432 | ตัวเดียว — รันจากโปรเจค Web (Docker) |
| MongoDB | 27017 | ตัวเดียว — รันจากโปรเจค Web (Docker) |
| โปรเจค Web (Backend/Frontend) | ตามที่ Web ใช้ (เช่น 3000, 5000) | โปรเจค nextx (Web) |
| **Mobile API** (nextx-mb) | **4000** | รันจาก nextx-mb: `run-api.cmd` |
| **Mobile แอป (Flutter web)** | **8080** | รันจาก nextx-mb: `run-web.cmd` หรือ Docker `web` |

ถ้าโปรเจค Web ใช้พอร์ต 8080 อยู่แล้ว ให้เปลี่ยน Mobile แอปเป็นพอร์ตอื่น (เช่น 8081) ใน `run-web.ps1` (ตัวแปร `$webPort`)

### ลำดับการรัน (เมื่อใช้ DB จากโปรเจค Web)

1. **รัน Docker ของโปรเจค Web** (PostgreSQL, MongoDB และบริการของ Web)
2. **รันโปรเจค Web** ตามปกติ (Backend + Frontend ของ Web)
3. **รัน Mobile API:** จากโฟลเดอร์ nextx-mb → `run-api.cmd`
4. **รัน Mobile แอป:** จากโฟลเดอร์ nextx-mb → `run-web.cmd` แล้วเปิด http://localhost:8081 (หรือ 8080)

หรือใช้ Docker เฉพาะแอป Mobile: **run-docker-web.cmd** แล้วรัน **run-api.cmd** แยก

### ไฟล์ตั้งค่า

- **nextx-mb:** ใช้ **api/.env** ให้ชี้ไปที่ DB เดียวกับ Web  
  (`PG_HOST=localhost`, `PG_PORT=5432`, `PG_DATABASE=db_moai_next`, `MONGO_URI=mongodb://localhost:27017`)

---

## 2. รองรับผู้ใช้หลายคน (Concurrent users)

API และ Database ตั้งค่าให้รองรับการใช้งานพร้อมกันหลายคนแล้ว

### API (Node.js)

- **Stateless** — ไม่เก็บ session ใน memory ของ process จึง scale ตามจำนวน process/instance ได้
- **Connection pooling:**
  - **PostgreSQL:** ใช้ `pg.Pool` กำหนด `max` (default 20) ผ่าน env `PG_POOL_SIZE`
  - **MongoDB:** ใช้ `maxPoolSize` (default 50) ผ่าน env `MONGO_POOL_SIZE`
- Express รองรับหลาย request พร้อมกันอยู่แล้ว

### ตัวแปรใน api/.env (ถ้าต้องการปรับ)

| ตัวแปร | ความหมาย | ค่าเริ่มต้น |
|--------|----------|-------------|
| PG_POOL_SIZE | จำนวน connection สูงสุดใน pool (PostgreSQL) | 20 |
| MONGO_POOL_SIZE | จำนวน connection สูงสุดใน pool (MongoDB) | 50 |

ถ้าผู้ใช้พร้อมกันมาก (หลายสิบขึ้นไป) สามารถเพิ่มค่าเหล่านี้ได้ และพิจารณารัน API หลาย instance ด้านหน้าด้วย reverse proxy (เช่น nginx) หรือ process manager (เช่น PM2 หลายตัว)

### Database

- **PostgreSQL / MongoDB** รองรับการเชื่อมต่อพร้อมกันหลาย connection อยู่แล้ว
- ใช้ DB ชุดเดียวทั้ง Web และ Mobile ได้ — ข้อมูลเดียวกัน แยกแพลตฟอร์มได้ที่ layer แอป/API

---

## สรุป

- **รัน Web + Mobile พร้อมกัน:** ใช้ DB ชุดเดียวกัน จัดพอร์ตให้ไม่ชน (Mobile API 4000, Mobile แอป 8080 หรือ 8081)
- **รองรับหลายคน:** ใช้ connection pool ใน API (PG_POOL_SIZE, MONGO_POOL_SIZE) และรัน API/DB ตามที่แนะนำด้านบน
