# เว็บ (NEXTX) กับแอปมือถือ (nextx-mb)

- ใช้ **backend ตัวเดียวกัน**: แอปเรียก NEXTX web API (`/api/...`) — ไม่มี API แยกสำหรับมือถือ
- บัญชี / ธุรกิจ / สิทธิ์เมนู / ข้อมูล ตรงกับเว็บทุกอย่าง
- ฟีเจอร์ที่ต้องเพิ่มฝั่ง backend เพื่อมือถือ ทำใน repo NEXTX (branch `claude/mobile-app-support`):
  ยกเลิกคำขอลา, บันทึก `source=app` ตอนลงเวลา, ตรวจ `current_password`
- เวลาพัฒนาด้วย Flutter web ให้รัน `node tool/moainext_web_proxy.mjs` เพื่อเลี่ยง CORS

รายการสิ่งที่ backend ยังต้องทำเพื่อมือถือ ดู [MOBILE_JOURNEY.md](MOBILE_JOURNEY.md) หัวข้อ "สิ่งที่ยังขาด"
