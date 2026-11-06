# Mobile User Journey (MOAI NEXT)

เอกสารนี้สรุป Journey ทั้งหมด (Phase 1–7) และสิ่งที่แอป **nextx-mb** รองรับในปัจจุบัน

---

## UX / UI หลัก (ทุก Phase)

- **Mobile-first & hybrid:** ข้อมูลหนาแน่นแบบตาราง → ใช้ **การ์ด (card list)** เป็นหลัก  
- **Navigation:** ลด overlay/drawer ซ้อนหลายชั้น → เน้น **full-page transition** หรือ **bottom sheet** สำหรับการกระทำสั้นๆ  
- **Adaptive:** รองรับแนวตั้ง/แนวนอน (`NavigationBar` / `NavigationRail` ตามความกว้างจอ)

---

## Phase 1 — Onboarding & Authentication

| หัวข้อ | รายละเอียด | สถานะในแอป (nextx-mb) |
|--------|------------|------------------------|
| **Login & OAuth** | Email/Password, LINE Login | มีหน้า Login + LINE stub + Demo session |
| **Hub** | สลับ Business, เลือกแพ็กเกจย่อย NEXT **T/S/C/O/H** | มี `BusinessHubScreen` (แช่น + mock ธุรกิจ) |
| **Getting Started** | Checklist (โปรไฟล์, รูป, ธีม ฯลฯ) | มี `GettingStartedScreen` |

Flow ปัจจุบัน: Splash → Login → Hub → Getting Started → AppShell (หลัก)  
เส้นทางเต็มหน้าจาก Shell: `AppRoutes` + `MaterialApp.routes` ใน `lib/app.dart` (แจ้งเตือน, ลงเวลา, การลา, CRM, Workspace, Chat, AI, Profile)

---

## Phase 2 — Dashboard & Global Search

| หัวข้อ | รายละเอียด | สถานะในแอป |
|--------|------------|------------|
| **Mobile Dashboard** | KPI สรุป, กราฟย่อ (Donut/Bar), layout มือถือ | KPI + chart placeholder + health/API |
| **Global Search** | ค้นหา Lead/Contact/งาน/บอร์ด + ประวัติล่าสุด | ช่องค้นหา + ประวัติ local |
| **Notification Center** | รายการแจ้งเตือน, deep-link ไปหน้าเป้าหมาย | รายการ stub + นำทางแบบ snackbar |

---

## Phase 3 — HR & Attendance (NEXT H)

| หัวข้อ | รายละเอียด | สถานะในแอป |
|--------|------------|------------|
| **Clock In/Out** | ลงเวลา + GPS (lat/lng) + ที่อยู่ | หน้า attendance + ฟิลด์ตำแหน่ง |
| **Leave** | ยอดลาคงเหลือ, ยื่นคำขอ, หัวหน้าอนุมัติ/ปฏิเสธ | หน้า leave แบบ stub / flow พื้นฐาน |

---

## Phase 4 — CRM & Sales (NEXT S/O)

| หัวข้อ | สถานะในแอป |
|--------|------------|
| **แท็บธุรกิจ + Module hub** | `ModuleHubScreen` — ลิงก์ไป CRM / Workspace / Chat / AI / Profile |
| **Lead / Contact** | `CrmHomeScreen` → `EntityListScreen` + `EntityDetailScreen` — เชื่อม `GET /api/entity/leads` และ `contacts` ผ่าน `CrmApiService`; ถ้า error หรือรายการว่างใช้ **mock**; **Note/Tag แบบ local** (`EntityLocalMetadataService` + กรองรายการ) |
| **Account / Case** | แสดงข้อความรอ module ใน registry |
| **Quotation / Call log** | `QuotationStubScreen`, `CallLogStubScreen` — PDF / Convert / บันทึกสายเป็น SnackBar (รอ backend) |

---

## Phase 5 — Workspace & Tasks (NEXT T)

| หัวข้อ | สถานะในแอป |
|--------|------------|
| **Task list** | `WorkspaceHomeScreen` + `WorkspaceKanbanBoard` — บอร์ดเลื่อนแนวนอนตาม `status` (UX แบบ Kanban ได้แรงบันดาลใจทั่วไป **ไม่ใช่** โค้ดจาก [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)); `GET /api/entity/tasks`; ลากการ์ดหรือเมนูเปลี่ยนสถานะ → `PUT /api/entity/tasks/:id` |
| **รายละเอียด + Worklog** | `TaskDetailScreen` — แท็บรายละเอียด + worklog demo (บันทึกในเครื่อง) |

---

## Phase 6 — Communication & AI

| หัวข้อ | สถานะในแอป |
|--------|------------|
| **Chat** | `ChatHomeScreen` — รายการ channel/DM แบบ mock |
| **AI** | `AiChatScreen` — ปุ่ม Summarize/Translate/Suggest (stub) + ปุ่ม Health เรียก `GET /health` |

---

## Phase 7 — Profile & Settings

| หัวข้อ | สถานะในแอป |
|--------|------------|
| **โปรไฟล์** | `ProfileScreen` — เลือกรูปด้วย `image_picker` เก็บ **base64 ใน prefs** (C1), ภาษา UI / รูปแบบวันที่, accent |
| **ความปลอดภัย** | เปลี่ยนรหัสผ่าน / 2FA — placeholder + SnackBar (รอ API) |
| **Settings** | ลิงก์ไป Profile + ธีม/API/logout เดิม |

---

## การเชื่อมต่อ Backend

- รูปแบบ response **S/E** — ดู [API_ALIGNMENT.md](API_ALIGNMENT.md)  
- Auth / scope / transition — ดู [SECURITY_STANDARD.md](SECURITY_STANDARD.md)  
- Entity list: `GET /api/entity/:module` — `ApiClient.getEntityList`, `CrmApiService`, `WorkspaceApiService` ใน `lib/services/`

---

## สรุปขอบเขตโค้ดปัจจุบัน

- **ทำแล้ว:** Shell (รวมแท็บ **ธุรกิจ**), Auth/Hub/Getting Started, Dashboard, Search, Notifications stub, HR attendance/leave stub, Settings + Profile placeholder  
- **Phase 4–7 (shell + API ที่พร้อม):** CRM lists/detail (leads, contacts), Workspace tasks + worklog demo, Chat/AI stubs, Quotation/Call log stubs — ส่วน PDF, realtime chat, WebRTC, Ollama จริงยังไม่ผูก
