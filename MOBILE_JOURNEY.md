# Mobile User Journey (MOAI NEXT)

สถานะจริงในโค้ด **nextx-mb** (เรียก NEXTX web API โดยตรง — ดู `lib/services/api_client.dart`)

---

## Phase 1 — Onboarding & Authentication

ลำดับ: **Welcome → เลือกเซิร์ฟเวอร์ → เข้าสู่ระบบ → เลือกธุรกิจ → เลือก Package → บทบาท → เมนูของคุณ → แอป**

| หัวข้อ | สถานะ |
|--------|--------|
| เซิร์ฟเวอร์ | ใช้ได้ทุกเซิร์ฟเวอร์ MOAI NEXT — ตรวจ `GET /api/health` (`app: 'MOAI NEXT API'`, `signature: 'aisystem'`), จำเซิร์ฟเวอร์ล่าสุด, เปลี่ยนได้จากหน้า login / ตั้งค่า |
| อีเมล/ชื่อผู้ใช้ + รหัสผ่าน | ใช้จริง (`POST /api/auth/login`) |
| OTP อีเมล / SMS | ใช้จริง พร้อมยืนยันเชื่อมบัญชี (`needLinkConfirm` → `/api/auth/link/*`) |
| LINE | เซิร์ฟเวอร์ใหม่ (feature `line_app`): เปิดเบราว์เซอร์ระบบ `/api/auth/line?app=1` แล้วกลับเข้าแอปทาง `moainext://app/login?token=`; เซิร์ฟเวอร์เดิม: WebView ในแอปดัก `…/login?token=` (บัญชีต้องผูก LINE แล้ว) — แสดงปุ่มเมื่อ `/api/auth/line/check` มี `channel_id` |
| Google | Google Sign-In แบบ native → `POST /api/auth/google/one-tap` (+ merge บัญชี) — ต้องตั้งค่า OAuth client ใน GCP (ดู PUSH_AND_RELEASE.md) |
| สมัครสมาชิก | มีรหัสเชิญ/ซีเรียล หรือสมัครรออนุมัติ (`POST /api/auth/register`) |
| ลิงก์เชิญเข้าธุรกิจ | `…/register?invite=` หรือ `moainext://app/register?invite=` — ยังไม่มีบัญชี: สมัครด้วย `invite_token` เข้าธุรกิจทันที; มีบัญชีแล้ว: เข้าสู่ระบบแล้วถามเข้าร่วม (`POST /api/me/request-join`) |
| บัญชีที่เคยใช้ | เติมอีเมลล่าสุด + ชิปบัญชีของเซิร์ฟเวอร์นี้ (ไม่เก็บรหัสผ่าน) |
| ล็อกแอป | ลายนิ้วมือ/ใบหน้า (`local_auth`) เปิดในตั้งค่า — ขอสแกนตอนเปิดแอปหรือกลับมาหลังพัก 5 นาที |
| ลืมรหัสผ่าน | ใช้จริง |
| ล็อกอินด้วยรหัสธุรกิจ | **ไม่ใส่โดยตั้งใจ** (`/api/auth/access` เข้าเป็นเจ้าของธุรกิจได้โดยไม่มีรหัสผ่าน) |
| ธุรกิจ | กรองยกเลิก/sandbox เหมือนเว็บ, เลือกอัตโนมัติถ้ามีธุรกิจเดียว |
| Package | `GET /api/businesses/:id/packages` — เลือกอัตโนมัติ (ล่าสุด → ค่าเริ่มต้นผู้ใช้ → ค่าเริ่มต้นธุรกิจ → มีอันเดียว), ตั้งค่าเริ่มต้นได้, ส่ง `X-Package-Code` ทุก request, เมนูจาก `/api/me/menus?package=` |
| บทบาท | 9 บทบาท (ขาย, บริการ, ช่าง, การตลาด, ร้านค้าออนไลน์, บัญชี, HR, ผู้บริหาร, ทั่วไป) เลือกได้หลายข้อ |
| เมนูล่าง | แนะนำจากบทบาท ∩ สิทธิ์ ปรับเอง/เรียงลำดับได้ (สูงสุด 4 + แท็บ "เมนู") เก็บแยกตามเซิร์ฟเวอร์+ผู้ใช้ในเครื่อง, จำแท็บล่าสุด |
| สลับธุรกิจ/Package | ชิปบนหัวหน้าหลัก → เลือก Package อื่นหรือเปลี่ยนธุรกิจ; บทบาทติ๊กให้ตาม Package |
| สิทธิ์เมนูใหม่ | กลับเข้าแอปโหลด `/api/me` + เมนูใหม่ (ไม่เกิน 1 ครั้ง/5 นาที) |
| เซสชันหมดอายุ | แจ้ง "เซสชันหมดอายุ" บนหน้า login; เซิร์ฟเวอร์ใหม่ (feature `refresh`) ต่ออายุ token อัตโนมัติเมื่ออายุเกิน 1 วัน (`POST /api/auth/refresh`) |
| ความสามารถเซิร์ฟเวอร์ | อ่าน `GET /api/health` → `mobile` (เวอร์ชันต่ำสุด/ล่าสุด, ลิงก์สโตร์, features) ทุกครั้งที่เปิดแอป/กลับเข้าแอป (ไม่เกิน 30 นาที/ครั้ง) — เซิร์ฟเวอร์เดิมไม่มีค่านี้ แอปทำงานแบบเดิม |
| บังคับอัปเดต | ต่ำกว่า `min_version` → หน้า "กรุณาอัปเดตแอป"; ต่ำกว่า `latest_version` → แถบในตั้งค่า |
| ซิงค์เมนูล่าง | เซิร์ฟเวอร์ใหม่ (feature `prefs_mobile`) เก็บบทบาท/แท็บใน `user_preferences.mobile_shell` — ล็อกอินเครื่องใหม่ได้เมนูเดิม |

## Phase 2 — Dashboard, Search, Notifications

| หัวข้อ | สถานะ |
|--------|--------|
| Dashboard | ลงเวลาวันนี้, ปุ่มลัดตามสิทธิ์, งานของฉัน (เลยกำหนด/วันนี้/กำลังมา), กิจกรรมถัดไป, ตัวเลขภาพรวม (`/api/dashboard/home-summary`, `/api/home/work`), การ์ดยอดขาย/เคสปีนี้ตามทีมที่เห็นได้ (`/api/dashboard/sales`, `/case`) |
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
| รายงานลงเวลา (HR) | ใครเข้า-ออกงานรายวัน, ยังไม่ออก, ลารออนุมัติ, ดูตำแหน่งบนแผนที่ (เมนู `attendance-report`) |

## Phase 4 — CRM / FSM / Commerce

| หัวข้อ | สถานะ |
|--------|--------|
| Lead / Contact / Account / Deal / Case / Quotation | list/detail/create/edit/delete, comments, tags, related |
| ใบเสนอราคา | lines, PDF, convert, อนุมัติ, ส่งอีเมล |
| FSM | jobs, inspection, parts, skills, manday |
| รออนุมัติ | หน้ารวม: ใบเสนอราคาที่ถึงคิวเรา, การลา, คำขอเข้าร่วมธุรกิจ |
| ร้านค้า | ออเดอร์ตามคิว, รายละเอียด + รายการสินค้า + ที่อยู่, ใบเสร็จ/ใบปะหน้า PDF; รับชำระและสต็อกเฉพาะเจ้าของ/แอดมิน |

## Phase 5 — Workspace

| หัวข้อ | สถานะ |
|--------|--------|
| Kanban / boards | ใช้จริง |
| งาน | แก้ชื่อ/คำอธิบาย, ผู้รับผิดชอบ, กำหนดส่ง, ความสำคัญ, เสร็จแล้ว, ลบ, ไฟล์แนบ, เช็คลิสต์ (smart checklist), ความคิดเห็น, worklog; บอร์ดอัปเดตสด |

## Phase 6 — Communication & AI

| หัวข้อ | สถานะ |
|--------|--------|
| Chat | บับเบิล, realtime, กำลังพิมพ์, ส่งแล้ว/อ่านแล้ว, แก้/ลบ/รีแอคชั่น, ปักหมุดข้อความ, แนบรูป/ไฟล์, ค้นหาข้อความ, สร้างห้องกลุ่ม, unread badge |
| Mail (ภายใน) | เขียน/ตอบ/ส่งต่อ/ฉบับร่าง, กล่องเข้า/ส่งแล้ว/ร่าง/ถังขยะ, ลบ/กู้คืน, ค้นหา, อัปเดตสด |
| Mail (Gmail/Outlook) | ยังเปิดผ่านเว็บ |
| Files | โฟลเดอร์, อัปโหลดหลายไฟล์, เปิด/แชร์/เปลี่ยนชื่อ/ลบ |
| Calendar | รายเดือน/รายสัปดาห์พร้อมจำนวนกิจกรรม, ใกล้ถึง/ค้าง, อัปเดตสด, เช็คอิน GPS |
| AI | ส่งประวัติบทสนทนา, จำแชทในเครื่อง, คำถามแนะนำ |

## Phase 7 — Profile, Settings, Quality

| หัวข้อ | สถานะ |
|--------|--------|
| โปรไฟล์ | แก้ข้อมูลส่วนตัว, รูป, ธีม, ภาษาปฏิทิน, ลายเซ็น TH/EN (วาดบนจอหรือเลือกรูป), ยืนยันเบอร์มือถือด้วย OTP |
| บันทึกปัญหา | ตั้งค่า → บันทึกปัญหา: error ล่าสุด 30 รายการ + ข้อมูลเครื่อง แชร์/คัดลอกส่งทีม |
| เปลี่ยนรหัสผ่าน | ส่ง `current_password` — backend ตรวจเมื่อส่งมา |
| Release | release build ล้มถ้าไม่มี `key.properties`; ล็อก Base URL บน release |
| Error handling | `ErrorReporting.runGuarded` จับ error ทั้งแอป (ต่อ Crashlytics/Sentry ได้ที่ `ErrorReporting.sink`) |
| Offline | check-in กิจกรรมเข้าคิว + แบนเนอร์ "รอส่ง" |
| CI | `.github/workflows/flutter-ci.yml` (analyze, test, debug APK, release APK แยก CPU — arm64 สำหรับมือถือทั่วไป) |

---

## สิ่งที่ยังขาด (ต้องทำนอกแอปหรือรอ backend)

- 2FA/TOTP (backend NEXTX)
- refresh token / LINE กลับเข้าแอป / ซิงค์เมนู: เขียนแล้วใน NEXTX branch `feature/mobile-app-support` (จาก `develop`) — รอ merge/deploy (ดู `docs/MOBILE_BACKEND.md` ใน NEXTX)
- OT / เบิกค่าใช้จ่าย / สลิปเงินเดือน / ประกาศบริษัท (ยังไม่มีโมดูลใน NEXTX)
- `assetlinks.json` + `apple-app-site-association` บนโดเมนเว็บ
- Firebase config จริง, keystore, iOS signing บน Mac
- แปลข้อความทั้งแอปเป็นภาษาอังกฤษ (ตอนนี้ข้อความเป็นไทย; ภาษาเปลี่ยนได้เฉพาะส่วนของระบบ)
- ลงเวลาแบบออฟไลน์ — ต้องให้ backend รับเวลาจากเครื่อง (ตอนนี้ใช้เวลาฝั่ง server)
- แนบไฟล์ใบลา (ใบรับรองแพทย์) — ตาราง/endpoint การลาของ NEXTX ยังไม่มีช่องไฟล์แนบ
- **ความปลอดภัย backend (แก้แล้วใน NEXTX branch `claude/mobile-app-support` — รอ merge/deploy):**
  เดิมทุกคนดูลงเวลา/พิกัด/คำขอลาของคนอื่นและอนุมัติลา (รวมของตัวเอง) ได้ — ตอนนี้ต้องเป็นเจ้าของ/แอดมิน
  หรือมีสิทธิ์เมนู `attendance-report` / `hr-dashboard` / `leave-management` (เทสต์: `npm run test:hr-access`)
- สแกนบาร์โค้ด, Crashlytics — ต้องแก้ native config แล้ว build ทดสอบบนเครื่องจริง
- App Link ของลิงก์เชิญ `https://…/register` ใช้ได้กับ moainext.moai-crm.com เท่านั้น (เซิร์ฟเวอร์อื่นใช้ `moainext://app/register?invite=`)
