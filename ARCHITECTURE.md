# สถาปัตยกรรม nextx-mb

```
Flutter app ──HTTPS (Bearer JWT + X-Business-Id)──▶ NEXTX web API (/api/...)
     │                                                   │
     └──Socket.IO (/api/socket.io, auth.token)──────────┘  PostgreSQL / MongoDB (ฝั่งเว็บ)
     └──FCM push ◀── NEXTX services/fcmStaff.js
```

## การไหลของข้อมูล
- **Auth:** `POST /api/auth/login` หรือ OTP อีเมล → เก็บ JWT ใน secure storage (`AppConfig._completeLogin`)
  → `GET /api/me` ได้ user, business, role, `allowed_menu_keys` → `SessionState`
- **สิทธิ์:** ทุก route ผ่าน `accessRedirectFor` (`lib/core/navigation/route_access.dart`) ตรวจเมนู;
  งานเฉพาะ owner/admin ใช้ `SessionState.isBusinessAdmin`
- **API:** ทุก endpoint อยู่ใน `lib/services/api_client.dart`; error แปลงเป็นข้อความผ่าน `formatApiError`;
  401 (ยกเว้น login/OTP) → logout
- **Realtime:** `RealtimeService.events` (stream ทุก event: ข้อความแชท, แจ้งเตือน, ปฏิทิน, เมล)
- **แจ้งเตือน:** `UnreadNotifications` ตัวนับเดียวทั้งแอป; deep link จาก push/App Link ผ่าน `notificationDeepLink`
- **Offline:** `OfflineQueue` เก็บ check-in กิจกรรมตอนไม่มีสัญญาณ แล้วส่งเมื่อกลับมาออนไลน์
- **Error:** `ErrorReporting.runGuarded` (main.dart) — ต่อ Crashlytics/Sentry ที่ `ErrorReporting.sink`

## โฟลเดอร์ `api/` (legacy)
Node API ทดลองที่ต่อ DB เอง — แอปไม่ได้เรียกแล้ว (`AUTH_TRANSITION_MODE` ปิดเป็นค่าเริ่มต้น)
อย่า deploy ขึ้น production
