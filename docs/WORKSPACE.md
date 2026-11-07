# Workspace บนแอป (รอบ 14)

แอปใช้ API ของ NEXTX ทั้งหมดและไม่ได้แก้ backend ส่วนการตั้งค่าบอร์ด สถานะ และสมาชิก ยังทำบนเว็บ

## ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `lib/core/workspace_models.dart` | สถานะ, ประเภท, ความสำคัญ, รหัส `CODE-12`, `parseDuration` / `formatMinutes` (หน่วยเหมือนเว็บ: 1d = 24h, 1w = 7d) |
| `lib/screens/workspace/workspace_home_screen.dart` | หน้าแรก: งานของฉันข้ามบอร์ด, การ์ดบอร์ด, ทำซ้ำบอร์ด |
| `lib/screens/workspace/workspace_board_screen.dart` | หน้าบอร์ด: Kanban / รายการ / Epic, ตัวกรอง, แก้หลายรายการ |
| `lib/screens/workspace/ws_kanban.dart` | Kanban ลากวาง (การ์ดติดนิ้ว, เลื่อนเองชิดขอบ, แถบชิปสถานะ) |
| `lib/screens/workspace/workspace_item_form.dart` | ฟอร์มสร้าง / แก้ไข / ทำซ้ำ ทุกประเภท |
| `lib/screens/workspace/task_detail_screen.dart` | หน้ารายละเอียดงาน / Epic |
| `lib/screens/workspace/ws_detail_parts.dart` | stepper สถานะ, การ์ดเวลา, จับเวลา, แผ่นลงเวลา |
| `lib/screens/workspace/ws_activity_panel.dart` | ความคิดเห็น / ลงเวลา / ประวัติการแก้ไข |
| `lib/screens/workspace/workspace_trash_screen.dart` | ถังขยะ: กู้คืน / ลบถาวร |

## ฟีเจอร์ → API

| ฟีเจอร์ | API |
|---|---|
| รายการงาน (ข้อมูลเบา) | `GET /api/boards/:id/tasks?fields=lite`, `/epics`, `/statuses` |
| งานของฉันทุกบอร์ด | `GET /api/workspace/items?assignee_id=&exclude_done=1` |
| สร้าง | `POST /api/boards/:id/tasks` หรือ `/epics` |
| แก้ไข / เปลี่ยนสถานะ | `PUT /api/boards/:b/tasks/:t` (`status_id`, ฟิลด์อื่นๆ) |
| เรียงในคอลัมน์ | `PUT /api/boards/:b/tasks/reorder` (`ordered_ids`) |
| แก้หลายรายการ / ลบหลายรายการ | `PUT /:b/bulk-update`, `POST /:b/bulk-delete` |
| ทำซ้ำงาน | เหมือนเว็บ: เปิดฟอร์มที่กรอกค่าเดิมไว้ แล้วกดสร้าง (เลือกคัดลอกงานย่อยและเช็คลิสต์ได้) |
| ย้ายบอร์ด | `POST /:b/tasks/:t/move` (`target_board_id`) |
| ลบ (เลิกทำได้ 5 วินาที) | `DELETE /:b/tasks/:t` → ถังขยะ |
| ถังขยะ | `GET /api/workspace/trash`, `POST /trash/:id/restore`, `DELETE /trash/:id` |
| ลงเวลา | `GET/POST/PUT/DELETE /:b/tasks/:t/worklogs[/:id]` (`time_spent_minutes`, `work_description`, `time_remaining_minutes`, `started_at`) |
| ความคิดเห็น | `GET/POST/PUT/DELETE /:b/tasks/:t/comments[/:id]`, ถูกใจ `POST .../:id/like` |
| ประวัติการแก้ไข | `GET /api/boards/:id/activity?task_id=|epic_id=&fields=lite` |
| ผู้ติดตาม | `GET/POST/DELETE /:b/items/:kind/:id/watchers` |
| ลิงก์งาน | `GET/POST /:b/items/:kind/:id/links`, `DELETE /:b/item-links/:id` |
| ทำซ้ำบอร์ด | `POST /api/boards/:id/duplicate` |

## Kanban ลากวาง

- **หยิบการ์ด:** กดค้าง 260 ms การ์ดจะยกขึ้นติดนิ้ว (ขยาย 1.04, มีเงา, เอียงตามทิศที่ลาก)
- **เลื่อนเอง:** ลากเข้าใกล้ขอบซ้าย/ขวา 72 px แล้วบอร์ดเลื่อนเอง ความเร็วเพิ่มตามความใกล้ขอบ ในคอลัมน์ยาวก็ทำแบบเดียวกันที่ขอบบน/ล่าง
- **ระหว่างบอร์ดเลื่อน:** ระบบคำนวณคอลัมน์ใต้นิ้วใหม่ทุกเฟรม ทำให้วางลงคอลัมน์ที่เห็นอยู่จริง
- **ไปคอลัมน์ไกล:** ระหว่างลากมีแถบชิปสถานะด้านบน ค้างบนชิปเพื่อเลื่อนบอร์ดไปคอลัมน์นั้น หรือปล่อยบนชิปเพื่อวางท้ายคอลัมน์ (To do → Done ได้ในจังหวะเดียว)
- **หลังวาง:** หน้าจอขยับทันทีโดยไม่รอเซิร์ฟเวอร์ ถ้าเซิร์ฟเวอร์ปฏิเสธ การ์ดจะกลับที่เดิมและแจ้งเตือน
- **เลือกหลายรายการ:** กดค้างโดยไม่ลาก

## เทสต์

- `test/w1_workspace_models_test.dart`: model และการแปลงเวลา
- `test/w2_kanban_test.dart`: เลื่อนเองที่ขอบ, วางข้ามคอลัมน์, rollback เมื่อเซิร์ฟเวอร์ปฏิเสธ
- `test/w3_workspace_form_test.dart`: body ที่ส่งตอนสร้าง / ทำซ้ำ, หน้าบอร์ดโหลดการ์ด
- `test/w4_task_detail_test.dart`: เปลี่ยนสถานะ, ลงเวลา "1h 30m" = 90, คอมเมนต์ / ถูกใจ, ประวัติแปลง id เป็นชื่อ
- `test/w5_workspace_home_test.dart`: งานของฉันตามวันครบกำหนด, กู้คืนจากถังขยะ
