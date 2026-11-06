# โครงสร้าง: App สื่อสารกับ DB ผ่าน API เท่านั้น + รองรับผู้ใช้หลักพันคน

## 1. โครงสร้างการสื่อสาร (ทั้งโปรเจค)

```
[Flutter App / Mobile]  ←→  [API (Node.js)]  ←→  [PostgreSQL + MongoDB]
         เท่านั้น                    เท่านั้น              Database
```

- **แอป (Flutter)** ไม่เชื่อม Database โดยตรง — สื่อสารกับ **API เท่านั้น** (HTTP/REST)
- **API** เป็นตัวเดียวที่เชื่อม PostgreSQL และ MongoDB — ทุกข้อมูลที่แอปใช้ต้องผ่าน API
- ผลลัพธ์: ควบคุมการเข้าถึงข้อมูลได้ที่เดียว, scale แอปกับ API แยกกันได้, ปลอดภัยกว่า

---

## 2. การตั้งค่าให้รองรับผู้ใช้หลักพันคน

### ที่ทำไว้แล้วใน API

| รายการ | การตั้งค่า | หมายเหตุ |
|--------|------------|----------|
| **Connection pool (PostgreSQL)** | default 50, ปรับได้ด้วย `PG_POOL_SIZE` | แบ่ง connection ใช้ร่วมกัน ไม่เปิดต่อ request |
| **Connection pool (MongoDB)** | default 100, ปรับได้ด้วย `MONGO_POOL_SIZE` | เหมือนกัน |
| **Rate limit** | 300 ครั้ง/นาที ต่อ IP (ปรับได้) | ป้องกัน abuse, กระจาย load |
| **Request timeout** | 30 วินาที (ปรับได้ด้วย `REQUEST_TIMEOUT_MS`) | ไม่ให้ request ค้างถือ connection นาน |
| **Stateless** | ไม่เก็บ session ใน memory | รันหลาย instance ได้ ไม่ต้อง share state |
| **Body size limit** | 1MB | ลดความเสี่ยง request ใหญ่เกินไป |

### ค่าแนะนำสำหรับ ~1,000 คน

ใช้ค่าต่อไปนี้ใน **api/.env** (หรือ copy จาก **api/.env.example.1000**):

| ตัวแปร | ค่าแนะนำ (~1000 คน) | หมายเหตุ |
|--------|----------------------|----------|
| `PG_POOL_SIZE` | 50 | 1 instance พอ; ถ้ารัน 2 instance ใช้ 50 ต่อตัว, รวมไม่เกิน `max_connections` ของ Postgres |
| `MONGO_POOL_SIZE` | 100 | พอสำหรับ ~1000 คน |
| `RATE_LIMIT_MAX_PER_IP` | 300 | ครั้ง/นาที ต่อ IP — ป้องกัน abuse, ผู้ใช้ปกติไม่ติด |
| `RATE_LIMIT_WINDOW_MS` | 60000 | 1 นาที |
| `REQUEST_TIMEOUT_MS` | 30000 | 30 วินาที |

API **1 instance** รองรับ ~1000 คนได้สบาย; ถ้า traffic สูงมากหรือต้องการเผื่อ ให้รัน 2 instance หลัง load balancer

### ตัวแปรใน api/.env (ระดับหลักพันคน)

```env
# Pool — สำหรับ ~1000 คน (default ใน code ใช้ค่าพอดีอยู่แล้ว)
PG_POOL_SIZE=50
MONGO_POOL_SIZE=100

# Rate limit — 300 ครั้ง/นาที ต่อ IP
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_PER_IP=300

# Timeout
REQUEST_TIMEOUT_MS=30000
```

ถ้าผู้ใช้หนึ่งคนสร้าง request ไม่เกิน ~5 ครั้ง/วินาที ต่อ IP แล้ว 300/นาที ต่อ IP จะไม่ติดสำหรับการใช้งานปกติ และรวม ~1000 คนได้เมื่อมีหลาย IP

---

## 3. Scale ระดับหลักพันคนขึ้นไป

### แนวทางที่แนะนำ

1. **รัน API หลาย instance (horizontal scaling)**  
   - รัน process API หลายตัว (หรือหลายเครื่อง) ด้านหลัง **Load Balancer** (เช่น Nginx, AWS ALB)  
   - แต่ละ instance ใช้ pool ขนาดเท่ากัน (เช่น PG 50, Mongo 100)  
   - จำนวน connection รวมที่ Postgres = จำนวน instance × PG_POOL_SIZE — ต้องไม่เกิน `max_connections` ของ PostgreSQL

2. **ตั้งค่า PostgreSQL / MongoDB บน server**  
   - PostgreSQL: เพิ่ม `max_connections` (เช่น 200–500) ตามจำนวน instance × PG_POOL_SIZE  
   - MongoDB: ปรับ `maxPoolSize` ต่อ instance ได้ตามที่ document

3. **Cache (ถ้าต้องการลด load ที่ DB)**  
   - ใส่ Redis (หรือ in-memory cache) หน้า API สำหรับข้อมูลที่อ่านบ่อย/เปลี่ยนไม่บ่อย  
   - ลดการยิงไปที่ Postgres/Mongo โดยตรง เมื่อ user เยอะมาก

4. **ตรวจสอบและติดตาม**  
   - ใช้ endpoint `/health` สำหรับ load balancer (health check)  
   - ติดตาม CPU, memory, connection count ของ API และ DB

### ตัวอย่างการจัด instance (คร่าวๆ)

- ผู้ใช้พร้อมกัน ~1,000 คน, คนละ ~10 request นาที → ~10,000 request/นาที  
- API 1 instance รองรับได้หลายพัน request/นาที  
- ถ้าเกินหรือต้องการเผื่อ: รัน 2–4 instance หลัง load balancer, แต่ละ instance ใช้ pool ตามด้านบน

---

## 4. สรุป

- **ทั้งโปรเจค Mobile:** แอปสื่อสารกับ Database **ผ่าน API เท่านั้น**  
- **รองรับหลักพันคน:** ใช้ connection pool, rate limit, timeout, stateless และรัน API หลาย instance ได้ ตามตัวแปรใน **api/.env** และแนวทางในเอกสารนี้
