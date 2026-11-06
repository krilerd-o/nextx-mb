# Mobile User Journey (MOAI NEXT)

เอกสารนี้สรุป Journey และสถานะจริงในโค้ด **nextx-mb** (อัปเดตหลัง Flutter 3.47.9)

---

## UX / UI หลัก

- Mobile-first: การ์ดเป็นหลัก, full-page / bottom sheet
- Adaptive: `NavigationBar` / `NavigationRail`

---

## Phase 1 — Onboarding & Authentication

| หัวข้อ | สถานะ |
|--------|--------|
| Email/Password login | ใช้จริง (`POST /api/auth/login`) |
| Forgot password | ใช้จริง |
| LINE Login | **ยังไม่รองรับบนมือถือ** (ระบุบนหน้า Login) |
| Hub / Getting Started | ใช้จริง + businesses จาก API |
| Demo session | เฉพาะ debug ตามที่โค้ดกำหนด |

---

## Phase 2 — Dashboard & Search & Notifications

| หัวข้อ | สถานะ |
|--------|--------|
| Dashboard | ใช้จริง (health/KPI ตามที่มี) |
| Global Search | ใช้จริง + ประวัติ local |
| Notification Center | ใช้ API + deep link ในแอป |
| FCM | โค้ดพร้อม — ต้องวาง `google-services.json` / plist (ดู [PUSH_AND_RELEASE.md](PUSH_AND_RELEASE.md)) |
| Foreground banner | local notifications |
| OS App Links | ตั้ง intent-filter / URL scheme แล้ว — ต้อง verify โดเมนบนเซิร์ฟเวอร์ |

---

## Phase 3 — HR

| หัวข้อ | สถานะ |
|--------|--------|
| Clock in/out + GPS | ใช้จริง |
| Leave balance / request / approve | ใช้จริง |

---

## Phase 4 — CRM

| หัวข้อ | สถานะ |
|--------|--------|
| Lead / Contact / Account / Case | entity list/detail/create |
| Quotation lines / PDF / convert / approval | ใช้จริง + แชร์ PDF |
| Call log | ใช้จริง (`CallLogScreen`) + โทร `tel:` / คัดลอกเบอร์ |

---

## Phase 5 — Workspace

| หัวข้อ | สถานะ |
|--------|--------|
| Kanban / boards / tasks | ใช้จริง |
| สร้างงาน | title + description |
| Worklog | ใช้ API จริง |

---

## Phase 6 — Communication & AI

| หัวข้อ | สถานะ |
|--------|--------|
| Chat rooms / messages / upload / DM | ใช้จริง; DM เลือกจากรายชื่อผู้ใช้ |
| Realtime Socket.IO | client พร้อม (พึ่ง web API) |
| AI chat | `POST /api/ai/chat` + ล้างประวัติในเครื่อง |
| Mail | **อ่านอย่างเดียว** + ปุ่มเปิดเว็บสำหรับเขียน/ตอบ |
| Files / Calendar / Jobs / FSM | ใช้จริงตาม ApiClient |

---

## Phase 7 — Profile & Settings

| หัวข้อ | สถานะ |
|--------|--------|
| โปรไฟล์ / ธีม / accent / ภาษา | ใช้จริง |
| เปลี่ยนรหัสผ่าน | ฟอร์ม current + new + confirm → `PUT /api/me/password` |
| 2FA | ยังไม่มี endpoint — แสดงสถานะชัดเจน |
| Release signing | เอกสาร + `key.properties.example` |

---

## สิ่งที่ยังขาด / นอกเครื่องนี้

- LINE OAuth / 2FA endpoint จากเซิร์ฟเวอร์
- Mail compose API
- Firebase/keystore จริง (ไม่ commit)
- iOS build บน Mac
- Built-in Kotlin เมื่อปลั๊กอินอัปครบ
