# เมนูของแอปตามสิทธิ์ (Package ∩ Role)

แอปใช้กฎเดียวกับเว็บ NEXTX: เมนูที่ใช้ได้ = Package ที่เลือก ∩ สิทธิ์ของ Role (`GET /api/me/menus?package=`)
- `null` = ไม่จำกัด (ธุรกิจไม่มี Package และ Role ไม่จำกัดเมนู)
- รายการว่าง = ไม่มีเมนูใดใช้ได้
- superadmin ใช้ได้ทุกเมนู

## จุดตรวจ
| ที่ | ไฟล์ | ใช้ |
| --- | --- | --- |
| เมนู (แท็บ "เมนู") | `lib/core/menu_groups.dart` (`visibleMenuGroups`) | `MenuItemDef.menuKeys` |
| แท็บล่าง | `lib/core/shell_tabs.dart` (`resolveShellTabs`) | `ShellTabDef.anyMenu` (แท็บหน้าหลัก / ค้นหา / แจ้งเตือน แสดงเสมอ) |
| เปิดหน้าโดยตรง (deep link / push / ลิงก์) | `lib/core/navigation/route_access.dart` (`accessRedirectFor`) | `requiredMenusFor` + กฎ ISAAC |
| ค้นหาคำสั่ง | `lib/screens/search/global_search_screen.dart` | `_Command.menu` |

## เมนู ↔ menu key ↔ route
| เมนู | menu key | route |
| --- | --- | --- |
| ผู้มุ่งหวัง / บัญชี / ผู้ติดต่อ / ดีล / เคส ฯลฯ | key ของโมดูล (`lead`, `account`, `contact`, `deal`, `case`, …) | `/crm/:module…`, `/fsm/:module…`, `/modules/:module…`, `/form/:module` |
| ปฏิทิน | `calendar` / `activity-incoming` / `pending-work` | `/calendar…` |
| ใบสั่งงาน / งานช่าง | `job` | `/jobs…`, `/fsm/job…` |
| เวิร์กสเปซ | `workspace` | `/workspace…` |
| แชททีม | `community-chat` | `/chat…` |
| รออนุมัติ | `quotation` / `leave-management` / `pending-approvals` | `/approvals` |
| กล่องจดหมาย | `mailbox` | `/mail…` |
| บันทึกการโทร | `call-log` | `/call-log` |
| ลงทะเบียน Lead | `lead-register` | `/lead-register`, `/lead-register/:id`, `/lead-register/:id/fill` |
| ISAAC การสื่อสาร | `comm-ai-history`, `comm-ai-insights` | `/comm-ai…` |
| HR | `attendance`, `leave-request`, `leave-management`, `attendance-report`, `hr-dashboard` | `/hr…` |
| จัดการไฟล์ | `file-manager` | `/files` |
| ร้านค้า | `mini-store-orders` หรือ `mini-store-stock` (สต็อก: เฉพาะเจ้าของ / ผู้ดูแลธุรกิจ) | `/commerce` |
| AI Assistant | เปิด `ai_chat` (เมนูและหน้าเดียวกัน) — ก่อนรู้ค่าการตั้งค่า AI ใช้ key `ai-assistant` | `/ai…` |
| AI Notebook / Minute Auto | ตั้งค่า ISAAC plugin (+ key เมื่อ audience = `menu_permission`) | `/notebook…`, `/ai-minute-auto` |
| AI Minute Meeting | `ai-minute-meeting` (ตรวจเสมอ แม้ยังไม่โหลดค่า ISAAC) | `/ai-minutes…`, `/m/:code` (ลิงก์เข้าห้อง) |
| ลิงก์แชร์ผล AI | สาธารณะ (ไม่ตรวจเมนู) | `/share/ai/:token` |

## เมื่อสิทธิ์เปลี่ยน
- NEXTX ส่ง socket `permissions:changed { business_id, reason }` หลังแก้เมนูของ Package, Role, ชุดสิทธิ์, Package ของธุรกิจ หรือ Package ของสมาชิก
- `AppConfig` เรียก `refreshSession()` ทันที (ถ้ามีการเปลี่ยนเข้ามาระหว่างโหลด จะโหลดซ้ำอีกครั้ง)
- router ตรวจหน้าที่เปิดอยู่ใหม่ ถ้าไม่มีสิทธิ์แล้วจะกลับหน้าหลัก
- นอกจากนี้ยังโหลดใหม่ทุกครั้งที่กลับเข้าแอปเมื่อห่างกันเกิน 5 นาที (เหมือนเดิม)
- **ธุรกิจเปลี่ยนจาก "จำกัดเมนู" เป็น "ไม่จำกัด":** ล้างรายการเดิมทั้งในหน่วยความจำและในเครื่อง
- **สลับธุรกิจ:** ลบเมนูของธุรกิจเดิมที่บันทึกในเครื่องทันที
