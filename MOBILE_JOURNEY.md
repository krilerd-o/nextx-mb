# Mobile User Journey (MOAI NEXT)

สถานะจริงในโค้ด **nextx-mb** (เรียก NEXTX web API โดยตรง — ดู `lib/services/api_client.dart`)

---

## Phase 1 — Onboarding & Authentication

| หัวข้อ | สถานะ |
|--------|--------|
| Email/Password login | ใช้จริง (`POST /api/auth/login`) + แสดง/ซ่อนรหัสผ่าน |
| OTP ทางอีเมล | ใช้จริง (`/api/auth/otp/email/request|verify`) |
| Forgot password | ใช้จริง |
| LINE / Google Login | **รอ backend** — callback ของเว็บยัง redirect กลับหน้าเว็บเท่านั้น |
| Hub / Getting Started | ใช้จริง |

## Phase 2 — Dashboard, Search, Notifications

| หัวข้อ | สถานะ |
|--------|--------|
| Dashboard | ลงเวลาวันนี้, ปุ่มลัดตามสิทธิ์, งานของฉัน (เลยกำหนด/วันนี้/กำลังมา), กิจกรรมถัดไป, ตัวเลขภาพรวม (`/api/dashboard/home-summary`, `/api/home/work`) |
| Global Search | ค้นทุกโมดูลที่มีสิทธิ์พร้อมกัน + ประวัติในเครื่อง |
| Notification Center | แบ่งหน้า (cursor), กรองหมวด/ยังไม่อ่าน, ปัดลบ, อัปเดตสด |
| Badge แจ้งเตือน | ตัวนับเดียวทั้งแอป (`UnreadNotifications`) อัปเดตจาก socket |
| FCM | พร้อม — ต้องวาง `google-services.json` / plist; token ที่เปลี่ยนจะลงทะเบียนใหม่อัตโนมัติ |
| App Links | `/modules/...`, `/workspace/...`, `/calendar/...` → หน้าในแอป + ตรวจสิทธิ์เมนู; ต้องวาง `assetlinks.json` / AASA บนเว็บ |

## Phase 3 — HR

| หัวข้อ | สถานะ |
|--------|--------|
| ลงเวลาเข้า-ออก + GPS | ใช้จริง (ส่ง `source=app`) |
| การลา | สิทธิ์คงเหลือ (แถบ), ยื่นลา, ของฉัน (สถานะสี, ยกเลิกได้), อนุมัติพร้อมเหตุผล |

## Phase 4 — CRM / FSM / Commerce

| หัวข้อ | สถานะ |
|--------|--------|
| Lead / Contact / Account / Deal / Case / Quotation | list/detail/create/edit/delete, comments, tags, related |
| ใบเสนอราคา | lines, PDF, convert, อนุมัติ, ส่งอีเมล |
| FSM | jobs, inspection, parts, skills, manday |
| รออนุมัติ | หน้ารวม: ใบเสนอราคาที่ถึงคิวเรา, การลา, คำขอเข้าร่วมธุรกิจ |
| ร้านค้า | ออเดอร์ตามคิว + รับชำระ, สต็อก รับเข้า/จ่ายออก/ปรับยอด |

## Phase 5 — Workspace

| หัวข้อ | สถานะ |
|--------|--------|
| Kanban / boards | ใช้จริง |
| งาน | แก้ชื่อ/คำอธิบาย, ผู้รับผิดชอบ, กำหนดส่ง, ความสำคัญ, เสร็จแล้ว, ลบ, ความคิดเห็น, worklog |

## Phase 6 — Communication & AI

| หัวข้อ | สถานะ |
|--------|--------|
| Chat | บับเบิล, realtime ทีละข้อความ, กำลังพิมพ์, แก้/ลบ/รีแอคชั่น, แนบรูป/ไฟล์, unread badge |
| Mail (ภายใน) | เขียน/ตอบ/ส่งต่อ/ฉบับร่าง, กล่องเข้า/ส่งแล้ว/ร่าง/ถังขยะ, ลบ/กู้คืน |
| Mail (Gmail/Outlook) | ยังเปิดผ่านเว็บ |
| Files | โฟลเดอร์, อัปโหลดหลายไฟล์, เปิด/แชร์/เปลี่ยนชื่อ/ลบ |
| Calendar | ตารางรายเดือนพร้อมจุดกิจกรรม, ใกล้ถึง/ค้าง, เช็คอิน GPS |
| AI | ส่งประวัติบทสนทนา, จำแชทในเครื่อง, คำถามแนะนำ |

## Phase 7 — Profile, Settings, Quality

| หัวข้อ | สถานะ |
|--------|--------|
| โปรไฟล์ | แก้ข้อมูลส่วนตัว, รูป, ธีม, ภาษาปฏิทิน |
| เปลี่ยนรหัสผ่าน | ส่ง `current_password` — backend ตรวจเมื่อส่งมา |
| Release | release build ล้มถ้าไม่มี `key.properties`; ล็อก Base URL บน release |
| Error handling | `ErrorReporting.runGuarded` จับ error ทั้งแอป (ต่อ Crashlytics/Sentry ได้ที่ `ErrorReporting.sink`) |
| Offline | check-in กิจกรรมเข้าคิว + แบนเนอร์ "รอส่ง" |
| CI | `.github/workflows/flutter-ci.yml` (analyze, test, debug APK) |

---

## สิ่งที่ยังขาด (ต้องทำนอกแอปหรือรอ backend)

- Refresh token, 2FA/TOTP, LINE/Google login สำหรับมือถือ (backend NEXTX)
- OT / เบิกค่าใช้จ่าย / สลิปเงินเดือน / ประกาศบริษัท (ยังไม่มีโมดูลใน NEXTX)
- `assetlinks.json` + `apple-app-site-association` บนโดเมนเว็บ
- Firebase config จริง, keystore, iOS signing บน Mac
- แปลข้อความทั้งแอปเป็นภาษาอังกฤษ (ตอนนี้ข้อความเป็นไทย; ภาษาเปลี่ยนได้เฉพาะส่วนของระบบ)
- ลงเวลาแบบออฟไลน์ — ต้องให้ backend รับเวลาจากเครื่อง (ตอนนี้ใช้เวลาฝั่ง server)
