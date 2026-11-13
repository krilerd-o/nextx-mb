import 'activity_guests.dart' show kActivityStatuses;
import 'i18n.dart';
import 'journey_rules.dart';

/// Stored status / stage values the server writes in English, with their Thai
/// and English labels (activities, jobs, contracts, leads, deals, approvals…).
/// Same wording as the web where it has one.
const kStatusValueLabels = <String, (String, String)>{
  // Activity (`ACTIVITY_STATUSES`)
  'planned': ('วางแผน', 'Planned'),
  'in progress': ('กำลังดำเนินการ', 'In progress'),
  'in_progress': ('กำลังดำเนินการ', 'In progress'),
  'completed': ('เสร็จสิ้น', 'Completed'),
  'cancelled': ('ยกเลิก', 'Cancelled'),
  'canceled': ('ยกเลิก', 'Cancelled'),
  'held': ('เสร็จสิ้น', 'Held'),
  'not held': ('ไม่ได้จัด', 'Not held'),
  'not started': ('ยังไม่เริ่ม', 'Not started'),
  'pending approval': ('รออนุมัติ', 'Pending approval'),
  'pending_approval': ('รออนุมัติ', 'Pending approval'),
  // Job
  'open': ('เปิดงาน', 'Open'),
  'waiting': ('รอการตอบรับ', 'Waiting'),
  'on hold': ('พักงาน', 'On hold'),
  'scheduled': ('นัดหมายแล้ว', 'Scheduled'),
  'draft': ('ร่าง', 'Draft'),
  'closed': ('ปิดแล้ว', 'Closed'),
  'done': ('เสร็จสิ้น', 'Done'),
  'accepted': ('รับแล้ว', 'Accepted'),
  // Service contract
  'implement': ('กำลังดำเนินการ', 'Implementing'),
  'pending_sign': ('รอเซ็น', 'Waiting for signature'),
  'wait_start': ('รอเริ่ม', 'Waiting to start'),
  'active': ('มีผล', 'Active'),
  'inactive': ('ไม่ใช้งาน', 'Inactive'),
  'expired': ('หมดอายุ', 'Expired'),
  'renewed': ('ต่ออายุแล้ว', 'Renewed'),
  // Approvals
  'pending': ('รอดำเนินการ', 'Pending'),
  'approved': ('อนุมัติแล้ว', 'Approved'),
  'rejected': ('ไม่อนุมัติ', 'Rejected'),
  'none': ('ไม่ต้องอนุมัติ', 'No approval'),
  // Lead (`salesDash.lead.status.*` on the web)
  'new': ('ใหม่', 'New'),
  'contacted': ('ติดต่อแล้ว', 'Contacted'),
  'qualified': ('มีคุณสมบัติ', 'Qualified'),
  'unqualified': ('ไม่มีคุณสมบัติ', 'Unqualified'),
  'converted': ('แปลงแล้ว', 'Converted'),
  // Deal stages
  'qualification': ('คัดกรอง', 'Qualification'),
  'value proposition': ('นำเสนอคุณค่า', 'Value proposition'),
  'proposal sent': ('ส่งข้อเสนอแล้ว', 'Proposal sent'),
  'negotiation': ('เจรจาต่อรอง', 'Negotiation'),
  'closed won': ('ปิดการขาย (ชนะ)', 'Closed won'),
  'closed lost': ('ปิดการขาย (แพ้)', 'Closed lost'),
  'won': ('ชนะ', 'Won'),
  'lost': ('แพ้', 'Lost'),
  // Misc
  'sent': ('ส่งแล้ว', 'Sent'),
  'signed': ('เซ็นแล้ว', 'Signed'),
  'paid': ('ชำระแล้ว', 'Paid'),
};

final _thai = RegExp(r'[฀-๿]');

/// Label of a stored status / stage value in the current language
/// (`Planned` → `วางแผน`, `In Progress` → `กำลังดำเนินการ`). Thai values
/// (case / quotation statuses) go through [tr]; unknown values pass through.
/// [module] / [field] pick the module's own wording (a job "Completed" is
/// "ปิดงาน", an activity "Completed" is "เสร็จสิ้น").
String statusValueLabel(Object? value, {String? module, String? field}) {
  final raw = '${value ?? ''}'.trim();
  if (raw.isEmpty || raw == 'null') return '';
  final m = (module ?? '').toLowerCase();
  final f = (field ?? '').toLowerCase();
  if (m == 'job' && (f.isEmpty || f == 'job_status')) {
    final c = canonicalJobStatus(raw);
    if (kJobStatusLabels.containsKey(c)) return jobStatusLabel(raw);
  }
  if (f == 'quotation_status' || (m == 'quotation' && f.isEmpty)) {
    final c = canonicalQuotationStatus(raw);
    if (QS.all.contains(c)) return tr(c);
  }
  if (f == 'offer_status') {
    final c = canonicalOfferStatus(raw);
    if (Offer.all.contains(c)) return tr(c);
  }
  if (_thai.hasMatch(raw)) return tr(raw);
  if (m == 'activity' || m == 'calendar') {
    for (final e in kActivityStatuses.entries) {
      if (e.key.toLowerCase() == raw.toLowerCase()) return L10n.isEn ? e.value.$2 : e.value.$1;
    }
  }
  final hit = kStatusValueLabels[raw.toLowerCase()] ?? kStatusValueLabels[raw.toLowerCase().replaceAll('_', ' ')];
  if (hit == null) return raw;
  return L10n.isEn ? hit.$2 : hit.$1;
}
