/// Plain-language lines for the record history tab (ประวัติ).
///
/// `GET /api/entity/:module/:id/timeline` merges several server logs:
///  - `audit` rows from `aicrm_audit_log` (`action` like `activity.photo_upload`,
///    written by `logAudit` all over the backend),
///  - `field_change` rows from the picklist / field value log,
///  - `status_event` rows of cases and jobs (`action` accept / forward / …),
///  - `tag` rows of cases, `engagement` rows of leads,
///  - `activity` / `call` / `comment` / `deal` rows of the account / contact
///    360 timeline.
///
/// [kHistoryEvents] lists every action key the backend writes for a record
/// (labels reused from the web's `quotationAuditFormat.js`,
/// `JobWorkflowActions.jsx`, `CaseDetailProgressTab.jsx` and
/// `CrmEntityTimelineTab.jsx` where it has them). Unknown keys are humanised —
/// a raw dotted key is never shown — and logged in debug builds.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../widgets/nx_icons.dart';
import 'activity_guests.dart' show activityTypeLabel;
import 'i18n.dart';
import 'i18n_en.dart';
import 'status_labels.dart';
import 'thai_time.dart';

/// What kind of event a line is (icon + colour).
enum HistoryKind { create, edit, status, assign, delete, approve, reject, photo, location, email, comment, sign, link, file, export, tag, call, other }

const kHistoryKindStyle = <HistoryKind, (IconData, Color)>{
  HistoryKind.create: (NxI.plus, Color(0xFF16A34A)),
  HistoryKind.edit: (NxI.pencilSimple, Color(0xFF2563EB)),
  HistoryKind.status: (NxI.flag, Color(0xFF7C3AED)),
  HistoryKind.assign: (NxI.userCheck, Color(0xFFD97706)),
  HistoryKind.delete: (NxI.trash, Color(0xFFDC2626)),
  HistoryKind.approve: (NxI.checkCircle, Color(0xFF16A34A)),
  HistoryKind.reject: (NxI.xCircle, Color(0xFFDC2626)),
  HistoryKind.photo: (NxI.camera, Color(0xFF0D9488)),
  HistoryKind.location: (NxI.mapPin, Color(0xFFEA580C)),
  HistoryKind.email: (NxI.envelope, Color(0xFF0284C7)),
  HistoryKind.comment: (NxI.chatCircle, Color(0xFF4F46E5)),
  HistoryKind.sign: (NxI.penLine, Color(0xFF0F766E)),
  HistoryKind.link: (NxI.link, Color(0xFF64748B)),
  HistoryKind.file: (NxI.fileText, Color(0xFF0891B2)),
  HistoryKind.export: (NxI.downloadSimple, Color(0xFF0891B2)),
  HistoryKind.tag: (NxI.tag, Color(0xFFDB2777)),
  HistoryKind.call: (NxI.phone, Color(0xFF059669)),
  HistoryKind.other: (NxI.clockCounterClockwise, Color(0xFF64748B)),
};

/// One rendered history line.
class HistoryLine {
  const HistoryLine({required this.kind, required this.title, this.detail});
  final HistoryKind kind;

  /// Current-language sentence (`อัปโหลดรูป 3 รูป`).
  final String title;

  /// Second line (`จาก วางแผน เป็น กำลังดำเนินการ`, `A → B`), or null.
  final String? detail;

  IconData get icon => kHistoryKindStyle[kind]!.$1;
  Color get color => kHistoryKindStyle[kind]!.$2;

  @override
  String toString() => detail == null ? title : '$title · $detail';
}

/// Every event key the backend writes to a record's history, with its Thai
/// label (English in `i18n_en.dart`). Keys are `module.action` (audit log,
/// also used for case / job `status_event` rows) or a plain action.
const kHistoryEvents = <String, (String, HistoryKind)>{
  // Activity — activityPhotoService / activityCheckinService / activityGuestService /
  // activityApprovalService / routes/entity.js export / routes/approvals.js
  'activity.photo_upload': ('อัปโหลดรูป', HistoryKind.photo),
  'activity.photo_delete': ('ลบรูป', HistoryKind.photo),
  'activity.checkin': ('เช็คอิน', HistoryKind.location),
  'activity.checkout': ('เช็คเอาท์', HistoryKind.location),
  'activity.rsvp': ('ตอบรับคำเชิญ', HistoryKind.comment),
  'activity.export': ('ส่งออกเอกสารกิจกรรม', HistoryKind.export),
  'activity.approval_approve': ('อนุมัติกิจกรรม', HistoryKind.approve),
  'activity.approval_reject': ('ไม่อนุมัติกิจกรรม', HistoryKind.reject),
  'activity.approval_email_resend': ('ส่งลิงก์อนุมัติทางอีเมลอีกครั้ง', HistoryKind.email),
  // Quotation — routes/quotation.js, quotationExtras, quotationOutcomeService,
  // entityWriteService, routes/entity.js duplicate (web: quotationAuditFormat.js)
  'quotation.status_change': ('เปลี่ยนสถานะใบเสนอราคา', HistoryKind.status),
  'quotation.revise': ('สร้างใบแก้ไข (Revise)', HistoryKind.create),
  'quotation.duplicate_child': ('ทำซ้ำใบ (จากใบนี้)', HistoryKind.create),
  'quotation.duplicate_from': ('สร้างใบจากทำซ้ำ', HistoryKind.create),
  'quotation.approval_submit': ('ส่งขออนุมัติ', HistoryKind.approve),
  'quotation.approval_vote': ('อนุมัติ (ในระดับ)', HistoryKind.approve),
  'quotation.approval_advance': ('อนุมัติขั้นกลาง', HistoryKind.approve),
  'quotation.approval_approve': ('อนุมัติเอกสาร', HistoryKind.approve),
  'quotation.approval_reject': ('ไม่อนุมัติ', HistoryKind.reject),
  'quotation.approval_email_resend': ('ส่งลิงก์อนุมัติทางอีเมลอีกครั้ง', HistoryKind.email),
  'quotation.email_sent': ('ส่งอีเมลใบเสนอราคา', HistoryKind.email),
  'quotation.lines_updated': ('อัปเดตรายการสินค้า/บริการ', HistoryKind.edit),
  'quotation.outcome': ('บันทึกผล Win/Lost', HistoryKind.status),
  'quotation.offer_status': ('เปลี่ยนสถานะข้อเสนอ', HistoryKind.status),
  'quotation.saved': ('บันทึกใบเสนอราคา', HistoryKind.edit),
  'quotation.from_cart': ('สร้างใบเสนอราคาจากตะกร้า', HistoryKind.create),
  'quotation.create_job': ('สร้างใบสั่งงานจากใบเสนอราคา', HistoryKind.create),
  'quotation.convert_to_contract': ('แปลงเป็นสัญญาบริการ', HistoryKind.create),
  'quotation.convert_to_order': ('แปลงเป็นใบสั่งขาย', HistoryKind.create),
  'quotation.template_create': ('บันทึกเป็นเทมเพลต', HistoryKind.file),
  // Job — jobWorkflowService (`job.${act}` + status events), jobLifecycleService,
  // routes/jobDocument.js, routes/entity.js duplicate (web: JobWorkflowActions.jsx)
  'job.create': ('สร้างงาน', HistoryKind.create),
  'job.accept': ('รับงาน', HistoryKind.assign),
  'job.forward': ('ส่งต่องาน', HistoryKind.assign),
  'job.wait': ('รอการตอบรับ', HistoryKind.status),
  'job.resume': ('ดำเนินการต่อ', HistoryKind.status),
  'job.close': ('ปิดงาน', HistoryKind.approve),
  'job.cancel': ('ยกเลิกงาน', HistoryKind.reject),
  'job.reopen': ('เปิดงานกลับ', HistoryKind.status),
  'job.set': ('เปลี่ยนสถานะ', HistoryKind.status),
  'job.admin_set': ('ผู้ดูแลเปลี่ยนสถานะ', HistoryKind.status),
  'job.signature_sign': ('ลงลายเซ็น', HistoryKind.sign),
  'job.signature_clear': ('ล้างลายเซ็น', HistoryKind.sign),
  'job.email_sent': ('ส่งอีเมลใบสั่งงาน', HistoryKind.email),
  'job.duplicate_from': ('สร้างจากการทำซ้ำ', HistoryKind.create),
  'job.template_create': ('บันทึกเป็นเทมเพลต', HistoryKind.file),
  // Case — caseWorkflowService (`case.${act}` + status events), mailToCaseService
  // (web: CaseDetailProgressTab.jsx)
  'case.create': ('เปิดเคส', HistoryKind.create),
  'case.accept': ('รับเคส', HistoryKind.assign),
  'case.forward': ('ส่งต่อเคส', HistoryKind.assign),
  'case.wait': ('พักเคส', HistoryKind.status),
  'case.resume': ('ทำต่อ', HistoryKind.status),
  'case.cancel': ('ยกเลิกเคส', HistoryKind.reject),
  'case.close': ('ปิดเคส', HistoryKind.approve),
  'mail.case.created': ('สร้างเคสจากอีเมล', HistoryKind.email),
  'mail.case.commented': ('เพิ่มคอมเมนต์จากอีเมล', HistoryKind.comment),
  // Service contract — contractWorkflowService (`service_contract.${act}`),
  // serviceContractService / entityWriteService renew, import, sheet sync
  'service_contract.submit_approval': ('ส่งขออนุมัติสัญญา', HistoryKind.approve),
  'service_contract.start_implement': ('เริ่มติดตั้ง (Implement)', HistoryKind.status),
  'service_contract.ready_for_ma': ('พร้อมเข้า MA', HistoryKind.status),
  'service_contract.approve': ('อนุมัติสัญญา', HistoryKind.approve),
  'service_contract.reject': ('ไม่อนุมัติสัญญา', HistoryKind.reject),
  'service_contract.mark_signed': ('บันทึกวันที่ลูกค้าเซ็น', HistoryKind.sign),
  'service_contract.activate': ('เปิดใช้สัญญา', HistoryKind.approve),
  'service_contract.reactivate': ('เปิดสัญญาอีกครั้ง', HistoryKind.status),
  'service_contract.transfer': ('โอนสัญญา', HistoryKind.assign),
  'service_contract.cancel': ('ยกเลิกสัญญา', HistoryKind.reject),
  'service_contract.renew': ('ต่ออายุสัญญา', HistoryKind.create),
  'service_contract.import': ('นำเข้าสัญญา', HistoryKind.file),
  'service_contract.sheet_sync': ('ซิงก์จาก Google Sheet', HistoryKind.file),
  // Deal / account — dealExtras, dealWorkspaceService, entityWriteService, accountExtras
  'deal.stage_change': ('เปลี่ยนขั้นของดีล', HistoryKind.status),
  'deal.contacts_updated': ('อัปเดตผู้ติดต่อของดีล', HistoryKind.edit),
  'deal.lines_updated': ('อัปเดตรายการสินค้า/บริการ', HistoryKind.edit),
  'deal.primary_quotation': ('ตั้งใบเสนอราคาหลัก', HistoryKind.link),
  'deal.workspace_create': ('สร้าง Workspace ของดีล', HistoryKind.create),
  'deal.workspace_link': ('ผูก Workspace', HistoryKind.link),
  'deal.workspace_unlink': ('ยกเลิกการผูก Workspace', HistoryKind.link),
  'account.contacts_updated': ('อัปเดตผู้ติดต่อของบัญชี', HistoryKind.edit),
  // Any record — routes/entity.js share, identityHub, salesJobLinks
  'entity_share.add': ('แชร์รายการ', HistoryKind.link),
  'entity_share.remove': ('ยกเลิกการแชร์', HistoryKind.link),
  'entity_share.replace': ('ปรับการแชร์', HistoryKind.link),
  'identity_hub.unlink': ('ยกเลิกการเชื่อมช่องทางติดต่อ', HistoryKind.link),
  'identity_hub.set_primary': ('ตั้งช่องทางติดต่อหลัก', HistoryKind.link),
  'link.create': ('ผูกเอกสาร', HistoryKind.link),
  'link.delete': ('ยกเลิกการผูกเอกสาร', HistoryKind.link),
  'commercial_return.status_change': ('เปลี่ยนสถานะคำขอคืนสินค้า', HistoryKind.status),
  // Workspace soft delete — workspaceSoftDelete (`workspace.${kind}.delete|restore|purge`)
  'workspace.task.delete': ('ย้ายงานไปถังขยะ', HistoryKind.delete),
  'workspace.task.restore': ('กู้คืนงานจากถังขยะ', HistoryKind.create),
  'workspace.task.purge': ('ลบงานถาวร', HistoryKind.delete),
  'workspace.epic.delete': ('ย้าย Epic ไปถังขยะ', HistoryKind.delete),
  'workspace.epic.restore': ('กู้คืน Epic จากถังขยะ', HistoryKind.create),
  'workspace.epic.purge': ('ลบ Epic ถาวร', HistoryKind.delete),
  // Files — routes/files.js
  'file.upload': ('อัปโหลดไฟล์', HistoryKind.file),
  'file.replace': ('แทนที่ไฟล์', HistoryKind.file),
  'file.update': ('แก้ไขไฟล์', HistoryKind.file),
  'file.delete': ('ลบไฟล์', HistoryKind.delete),
  // Plain actions (older rows / generic writers)
  'create': ('สร้างรายการ', HistoryKind.create),
  'created': ('สร้างรายการ', HistoryKind.create),
  'update': ('แก้ไขรายการ', HistoryKind.edit),
  'updated': ('แก้ไขรายการ', HistoryKind.edit),
  'edit': ('แก้ไขรายการ', HistoryKind.edit),
  'delete': ('ลบรายการ', HistoryKind.delete),
  'deleted': ('ลบรายการ', HistoryKind.delete),
  'restore': ('กู้คืนรายการ', HistoryKind.create),
  'duplicate': ('ทำซ้ำรายการ', HistoryKind.create),
  'convert': ('แปลงรายการ', HistoryKind.create),
  'assign': ('มอบหมายงาน', HistoryKind.assign),
  'comment': ('เพิ่มคอมเมนต์', HistoryKind.comment),
  'status_change': ('เปลี่ยนสถานะ', HistoryKind.status),
};

/// Plain status-event actions (case / job rows carry no module prefix).
const _kStatusEventActions = {'create', 'accept', 'forward', 'wait', 'resume', 'close', 'cancel', 'reopen', 'set', 'admin_set'};

/// Engagement (`lead_engagement_event.event_type`, `LEAD_ENGAGEMENT_TYPES`) —
/// web `engagementLabel`, plus older names.
const kEngagementLabels = <String, (String, HistoryKind)>{
  'email_open': ('ลูกค้าเปิดอีเมล', HistoryKind.email),
  'email_click': ('ลูกค้าคลิกลิงก์ในอีเมล', HistoryKind.email),
  'link_click': ('ลูกค้าคลิกลิงก์', HistoryKind.link),
  'page_view': ('ลูกค้าเข้าชมหน้าเว็บ', HistoryKind.other),
  'web_visit': ('ลูกค้าเข้าชมหน้าเว็บ', HistoryKind.other),
  'form_submit': ('ลูกค้าส่งฟอร์ม', HistoryKind.file),
  'email_sent': ('ส่งอีเมล', HistoryKind.email),
  'mail': ('รับ-ส่งอีเมล', HistoryKind.email),
  'call': ('โทร', HistoryKind.call),
  'meeting': ('นัดประชุม', HistoryKind.location),
  'activity': ('บันทึกกิจกรรม', HistoryKind.location),
  'comment': ('เพิ่มคอมเมนต์', HistoryKind.comment),
  'camp_message': ('ส่งข้อความแคมเปญ', HistoryKind.email),
};

/// Case tag events (`CASE_TAG_ACTIONS`) — web `tagActionLabel`.
const kTagActionLabels = <String, String>{
  'create': 'ติดแท็กตอนสร้าง',
  'edit': 'ติดแท็กตอนแก้ไข',
  'duplicate': 'ติดแท็กตอนทำซ้ำ',
  'attach': 'ติดแท็ก',
  'detach': 'ถอนแท็ก',
};

const _kModuleNames = <String, String>{
  'quotation': 'ใบเสนอราคา',
  'job': 'ใบสั่งงาน',
  'deal': 'ดีล',
  'case': 'เคส',
  'activity': 'กิจกรรม',
  'account': 'บัญชี',
  'contact': 'ผู้ติดต่อ',
  'lead': 'ผู้มุ่งหวัง',
  'service_contract': 'สัญญาบริการ',
  'inspection': 'ใบตรวจรับ',
};

/// Thai template → current language, holes filled in order (English in
/// `enHistory` of `i18n_en.dart`; past tense, unlike the button words).
String historyText(String th, [List<Object?> args = const []]) {
  final tpl = L10n.isEn ? (enHistory[th] ?? enPatterns[th] ?? enStrings[th] ?? th) : th;
  var i = 0;
  return tpl.replaceAllMapped('{}', (_) => i < args.length ? '${args[i++] ?? ''}' : '');
}

final Set<String> _loggedUnknown = {};

void _logUnknown(String what, String key) {
  if (!kDebugMode || !_loggedUnknown.add('$what:$key')) return;
  debugPrint('[history] unknown $what "$key" — add it to kHistoryEvents (lib/core/history_events.dart)');
}

/// Verb words found in unknown keys → a readable title.
const _kVerbs = <String, (String, HistoryKind)>{
  'create': ('สร้างรายการ', HistoryKind.create),
  'created': ('สร้างรายการ', HistoryKind.create),
  'add': ('เพิ่มรายการ', HistoryKind.create),
  'update': ('แก้ไขรายการ', HistoryKind.edit),
  'updated': ('แก้ไขรายการ', HistoryKind.edit),
  'edit': ('แก้ไขรายการ', HistoryKind.edit),
  'save': ('แก้ไขรายการ', HistoryKind.edit),
  'saved': ('แก้ไขรายการ', HistoryKind.edit),
  'delete': ('ลบรายการ', HistoryKind.delete),
  'deleted': ('ลบรายการ', HistoryKind.delete),
  'remove': ('ลบรายการ', HistoryKind.delete),
  'purge': ('ลบรายการ', HistoryKind.delete),
  'restore': ('กู้คืนรายการ', HistoryKind.create),
  'duplicate': ('ทำซ้ำรายการ', HistoryKind.create),
  'copy': ('ทำซ้ำรายการ', HistoryKind.create),
  'convert': ('แปลงรายการ', HistoryKind.create),
  'approve': ('อนุมัติ', HistoryKind.approve),
  'reject': ('ไม่อนุมัติ', HistoryKind.reject),
  'cancel': ('ยกเลิก', HistoryKind.reject),
  'close': ('ปิดรายการ', HistoryKind.approve),
  'reopen': ('เปิดรายการกลับ', HistoryKind.status),
  'status': ('เปลี่ยนสถานะ', HistoryKind.status),
  'stage': ('เปลี่ยนสถานะ', HistoryKind.status),
  'assign': ('มอบหมายงาน', HistoryKind.assign),
  'forward': ('ส่งต่อ', HistoryKind.assign),
  'share': ('แชร์รายการ', HistoryKind.link),
  'link': ('ผูกเอกสาร', HistoryKind.link),
  'unlink': ('ยกเลิกการผูกเอกสาร', HistoryKind.link),
  'email': ('ส่งอีเมล', HistoryKind.email),
  'sent': ('ส่งอีเมล', HistoryKind.email),
  'send': ('ส่งอีเมล', HistoryKind.email),
  'upload': ('อัปโหลดไฟล์', HistoryKind.file),
  'photo': ('อัปเดตรูป', HistoryKind.photo),
  'export': ('ส่งออกเอกสาร', HistoryKind.export),
  'import': ('นำเข้าข้อมูล', HistoryKind.file),
  'sync': ('ซิงก์ข้อมูล', HistoryKind.file),
  'sign': ('ลงลายเซ็น', HistoryKind.sign),
  'signature': ('ลงลายเซ็น', HistoryKind.sign),
  'comment': ('เพิ่มคอมเมนต์', HistoryKind.comment),
  'commented': ('เพิ่มคอมเมนต์', HistoryKind.comment),
  'checkin': ('เช็คอิน', HistoryKind.location),
  'checkout': ('เช็คเอาท์', HistoryKind.location),
  'tag': ('ติดแท็ก', HistoryKind.tag),
};

/// `photo_rotate` → `Photo rotate` (never the raw key).
String humanizeHistoryKey(String key) {
  // Drop the leading namespace (`activity.photo_rotate` → photo rotate).
  final dot = key.indexOf('.');
  final rest = dot > 0 && dot < key.length - 1 ? key.substring(dot + 1) : key;
  final parts = rest.split(RegExp(r'[._\-\s]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return historyText('มีการเปลี่ยนแปลง');
  final s = parts.join(' ').toLowerCase();
  return s[0].toUpperCase() + s.substring(1);
}

/// Label of a known key, or a readable title for an unknown one.
({String title, HistoryKind kind, bool known}) historyActionTitle(String key) {
  final k = key.trim();
  final hit = kHistoryEvents[k] ?? kHistoryEvents[k.toLowerCase()];
  if (hit != null) return (title: historyText(hit.$1), kind: hit.$2, known: true);
  final words = k.toLowerCase().split(RegExp(r'[._\-\s]+'));
  for (final w in words.reversed) {
    final v = _kVerbs[w];
    if (v != null) return (title: historyText(v.$1), kind: v.$2, known: false);
  }
  return (title: humanizeHistoryKey(k), kind: HistoryKind.other, known: false);
}

Map<String, dynamic> _details(Object? d) {
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.trim().startsWith('{')) {
    try {
      final v = jsonDecode(d);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {
      // Plain text details.
    }
  }
  return const {};
}

String _s(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

String _clip(String s, [int max = 120]) => s.length > max ? '${s.substring(0, max - 1)}…' : s;

final _tags = RegExp(r'<[^>]*>');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}.*)?$');

String _plain(String s) => s.replaceAll(_tags, ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// "จาก A เป็น B" / "เป็น B" / "จาก A".
String? historyFromTo(String from, String to) {
  if (from.isEmpty && to.isEmpty) return null;
  if (from.isEmpty) return historyText('เป็น {}', [to]);
  if (to.isEmpty) return historyText('จาก {}', [from]);
  return historyText('จาก {} เป็น {}', [from, to]);
}

bool _isStatusField(String field, String label) {
  final f = field.toLowerCase();
  if (RegExp(r'(^|_)(status|stage)$').hasMatch(f) || f == 'leadstatus' || f == 'eventstatus' || f == 'sales_stage') return true;
  return field.isEmpty && (label == 'สถานะ' || label.toLowerCase() == 'status');
}

const _kOwnerFields = {'smownerid', 'assigned_user_id', 'assigned_to', 'owner_id', 'assignee_id', 'assignee'};

/// Field label: server label in the current language → the module's field
/// metadata → the field name made readable.
String _fieldLabel(Map<String, dynamic> e, String Function(String field)? fieldLabel) {
  final name = _s(e['field_name']);
  bool raw(String l) => l.isEmpty || l.toLowerCase() == name.toLowerCase();
  final en = _s(e['field_label_en']);
  final th = _s(e['field_label_th']);
  if (L10n.isEn && !raw(en)) return en;
  if (!raw(th)) return tr(th);
  final meta = name.isEmpty || fieldLabel == null ? '' : fieldLabel(name);
  if (!raw(meta)) return tr(meta);
  if (name.isEmpty) return historyText('ฟิลด์');
  if (_kOwnerFields.contains(name.toLowerCase())) return historyText('ผู้รับผิดชอบ');
  return humanizeHistoryKey(name.replaceAll(RegExp(r'_id$'), ''));
}

/// A field value for display: tags stripped, picklist / status labels, dates
/// in Thai time, long text clipped.
String _value(Object? v, {required String field, String? module, String Function(String field, String value)? valueLabel, bool status = false}) {
  final s = _plain(_s(v));
  if (s.isEmpty) return '';
  var out = valueLabel == null || field.isEmpty ? s : valueLabel(field, s);
  if (out == s && (status || _isStatusField(field, ''))) out = statusValueLabel(s, module: module, field: field);
  if (out == s && _isoDate.hasMatch(s)) out = formatThaiField(s, field, module: module, year: uiYear);
  return _clip(out, 80);
}

/// Plain-language line for one history event (see the library doc).
HistoryLine describeHistoryEvent(
  Map<String, dynamic> e, {
  String? module,
  String Function(String field, String value)? valueLabel,
  String Function(String field)? fieldLabel,
}) {
  final type = _s(e['type']);
  switch (type) {
    case 'field_change':
      return _fieldChange(e, module: module, valueLabel: valueLabel, fieldLabel: fieldLabel);
    case 'audit':
      return _audit(_s(e['action']), e['details'], module: module);
    case 'status_event':
      return _statusEvent(e, module: module);
    case 'status' || 'status_change':
      return HistoryLine(
        kind: HistoryKind.status,
        title: historyText('เปลี่ยนสถานะ'),
        detail: historyFromTo(
          _value(e['from_status'] ?? e['old_value'], field: _s(e['field_name']), module: module, valueLabel: valueLabel, status: true),
          _value(e['to_status'] ?? e['new_value'], field: _s(e['field_name']), module: module, valueLabel: valueLabel, status: true),
        ),
      );
    case 'tag':
      final action = _s(e['action']);
      final label = kTagActionLabels[action];
      if (label == null) _logUnknown('tag action', action);
      final name = L10n.isEn ? (_s(e['tag_name_en']).isEmpty ? _s(e['tag_name']) : _s(e['tag_name_en'])) : (_s(e['tag_name']).isEmpty ? _s(e['tag_name_en']) : _s(e['tag_name']));
      return HistoryLine(kind: HistoryKind.tag, title: historyText(label ?? 'ติดแท็ก'), detail: name.isEmpty ? null : name);
    case 'engagement':
      final kind = _s(e['event_type']).isEmpty ? _s(e['source']) : _s(e['event_type']);
      final hit = kEngagementLabels[kind];
      if (hit == null) _logUnknown('engagement', kind);
      final d = _details(e['details']);
      final subject = _s(d['subject']).isEmpty ? _s(d['title']) : _s(d['subject']);
      return HistoryLine(
        kind: hit?.$2 ?? HistoryKind.other,
        title: hit == null ? (kind.isEmpty ? historyText('การมีส่วนร่วม') : humanizeHistoryKey(kind)) : historyText(hit.$1),
        detail: subject.isEmpty ? null : _clip(_plain(subject)),
      );
    case 'activity' || 'call' || 'comment' || 'deal':
      return _related(e, type);
  }
  if (_s(e['action']).isNotEmpty) return _audit(_s(e['action']), e['details'], module: module);
  _logUnknown('type', type);
  final title = _s(e['title']).isNotEmpty ? _s(e['title']) : _s(e['label']);
  final detail = _s(e['description']).isNotEmpty ? _s(e['description']) : _s(e['summary']);
  return HistoryLine(
    kind: HistoryKind.other,
    title: title.isNotEmpty ? _clip(_plain(title)) : (type.isEmpty ? historyText('มีการเปลี่ยนแปลง') : humanizeHistoryKey(type)),
    detail: detail.isEmpty ? null : _clip(_plain(detail), 160),
  );
}

HistoryLine _fieldChange(
  Map<String, dynamic> e, {
  String? module,
  String Function(String field, String value)? valueLabel,
  String Function(String field)? fieldLabel,
}) {
  final field = _s(e['field_name']);
  final label = _fieldLabel(e, fieldLabel);
  final rawLabel = _s(e['field_label_th']);
  final status = _isStatusField(field, rawLabel.isEmpty ? label : rawLabel);
  String v(Object? x) => _value(x, field: field, module: module, valueLabel: valueLabel, status: status);
  final from = v(e['old_value']);
  final to = v(e['new_value']);
  if (status) {
    final generic = label == historyText('สถานะ') || label.toLowerCase() == 'status';
    return HistoryLine(
      kind: HistoryKind.status,
      title: generic ? historyText('เปลี่ยนสถานะ') : historyText('เปลี่ยน{}', [label]),
      detail: historyFromTo(from, to),
    );
  }
  if (_kOwnerFields.contains(field.toLowerCase())) {
    if (to.isEmpty) return HistoryLine(kind: HistoryKind.assign, title: historyText('ยกเลิกผู้รับผิดชอบ'), detail: from.isEmpty ? null : historyText('จาก {}', [from]));
    return HistoryLine(kind: HistoryKind.assign, title: historyText('มอบหมายให้ {}', [to]), detail: from.isEmpty ? null : historyText('จาก {}', [from]));
  }
  return HistoryLine(
    kind: HistoryKind.edit,
    title: historyText('แก้ไข {}', [label]),
    detail: from.isEmpty && to.isEmpty ? null : '${from.isEmpty ? '—' : from} → ${to.isEmpty ? '—' : to}',
  );
}

String _moduleOf(String key, String? module) {
  final i = key.indexOf('.');
  return i > 0 ? key.substring(0, i) : (module ?? '');
}

HistoryLine _statusEvent(Map<String, dynamic> e, {String? module}) {
  final action = _s(e['action']);
  final m = (module ?? '').isEmpty ? (e['source'] != null ? 'job' : 'case') : module!;
  final key = '$m.$action';
  final known = kHistoryEvents[key];
  if (known == null) _logUnknown('status action', key);
  final d = _details(e['details']);
  final title = known != null ? historyText(known.$1) : (_kStatusEventActions.contains(action) || action.isEmpty ? historyText('เปลี่ยนสถานะ') : historyActionTitle(action).title);
  final parts = <String>[
    ?historyFromTo(statusValueLabel(e['from_status'], module: m), statusValueLabel(e['to_status'], module: m)),
    ..._extraDetails(key, d, module: m),
  ];
  return HistoryLine(kind: known?.$2 ?? HistoryKind.status, title: title, detail: parts.isEmpty ? null : parts.join(' · '));
}

HistoryLine _audit(String action, Object? rawDetails, {String? module}) {
  final key = action.trim();
  if (key.isEmpty) return HistoryLine(kind: HistoryKind.other, title: historyText('มีการเปลี่ยนแปลง'));
  final d = _details(rawDetails);
  final t = historyActionTitle(key);
  if (!t.known) _logUnknown('event key', key);
  final m = _moduleOf(key, module);
  var title = t.title;
  final parts = <String>[];

  int? count(Object? v) => v is List ? v.length : (v is num ? v.toInt() : int.tryParse(_s(v)));
  switch (key) {
    case 'activity.photo_upload':
      final n = count(d['count']) ?? count(d['names']);
      if (n != null && n > 0) title = historyText('อัปโหลดรูป {} รูป', [n]);
    case 'activity.checkin' || 'activity.checkout':
      final loc = _s(d['location']);
      if (loc.isNotEmpty) title = historyText(key == 'activity.checkin' ? 'เช็คอินที่ {}' : 'เช็คเอาท์ที่ {}', [loc]);
      final dist = num.tryParse(_s(d['distance']));
      if (dist != null) parts.add(historyText('ห่างจุดนัดหมาย {} ม.', [dist.round()]));
      if (_s(d['time_tracking']).isNotEmpty) parts.add(historyText('ใช้เวลา {}', [_s(d['time_tracking'])]));
    case 'quotation.saved':
      if (d['created'] == true) title = historyText('สร้างใบเสนอราคา');
    case 'quotation.create_job':
      if (d['created'] == false) title = historyText('ผูกใบสั่งงานที่มีอยู่');
  }
  // `to` of an email is the address, not a status.
  final email = key.contains('email');
  final from = email ? d['from_status'] : d['from'] ?? d['from_status'];
  final to = email ? d['to_status'] : d['to'] ?? d['to_status'];
  if (from != null || to != null) {
    final field = switch (key) {
      'quotation.status_change' || 'quotation.outcome' => 'quotation_status',
      'quotation.offer_status' => 'offer_status',
      'deal.stage_change' => 'deal_stage',
      _ => null,
    };
    final ft = historyFromTo(statusValueLabel(from, module: m, field: field), statusValueLabel(to, module: m, field: field));
    if (ft != null && key != 'quotation.outcome') parts.add(ft);
  }
  parts.addAll(_extraDetails(key, d, module: m));
  if (parts.isEmpty && rawDetails is String && !rawDetails.trim().startsWith('{') && rawDetails.trim().length < 160) parts.add(_plain(rawDetails));
  return HistoryLine(kind: t.kind, title: title, detail: parts.isEmpty ? null : parts.join(' · '));
}

/// Readable bits of an event's `details` (never raw JSON).
List<String> _extraDetails(String key, Map<String, dynamic> d, {String? module}) {
  final out = <String>[];
  String s(String k) => _s(d[k]);
  int? n(String k) {
    final v = d[k];
    if (v is List) return v.length;
    if (v is num) return v.toInt();
    return int.tryParse(_s(v));
  }

  final action = key.contains('.') ? key.substring(key.lastIndexOf('.') + 1) : key;
  switch (key) {
    case 'activity.rsvp':
      final r = s('response');
      final label = switch (r) {
        'accepted' => 'เข้าร่วม',
        'declined' => 'ไม่เข้าร่วม',
        'tentative' => 'อาจเข้าร่วม',
        'needsAction' => 'ยังไม่ตอบ',
        _ => '',
      };
      if (label.isNotEmpty) out.add(historyText(label));
    case 'activity.export':
      if (s('format').isNotEmpty) out.add(s('format').toUpperCase());
    case 'activity.approval_email_resend' || 'quotation.approval_email_resend':
      if (d['sent'] == false) out.add(historyText('ส่งไม่สำเร็จ'));
    case 'quotation.revise':
      if (s('new_quotation_id').isNotEmpty) {
        out.add(historyText('ฉบับใหม่ #{}', [s('new_quotation_id')]) + (s('revision_no').isEmpty ? '' : ' (R${s('revision_no')})'));
      }
    case 'quotation.duplicate_child':
      if (s('new_quotation_id').isNotEmpty) out.add(historyText('ใบใหม่ #{}', [s('new_quotation_id')]));
    case 'quotation.duplicate_from':
      if (s('source_quotation_id').isNotEmpty) {
        out.add(historyText(s('via') == 'revise' ? 'ฉบับแก้ไขจากใบ #{}' : 'จากใบ #{}', [s('source_quotation_id')]));
      }
    case 'job.duplicate_from':
      if (s('source_job_id').isNotEmpty) out.add(historyText('จากใบสั่งงาน #{}', [s('source_job_id')]));
    case 'quotation.approval_submit':
      final steps = n('levels') ?? n('approver_user_ids');
      if (steps != null && steps > 0) out.add(historyText('ผู้อนุมัติ {} ขั้น', [steps]));
    case 'quotation.approval_vote':
      out.add(historyText('อนุมัติแล้ว (รอคนอื่นในระดับเดียวกัน)'));
    case 'quotation.approval_advance':
      if (s('from_level').isNotEmpty) out.add(historyText('ขั้น {} → {}', [s('from_level'), s('to_level')]));
    case 'quotation.approval_approve':
      out.add(historyText('อนุมัติขั้นสุดท้าย'));
    case 'quotation.outcome':
      final r = s('result').isNotEmpty ? s('result') : s('status');
      if (r.isNotEmpty) out.add(statusValueLabel(r));
      if (s('po_reference').isNotEmpty) out.add('PO ${s('po_reference')}');
    case 'quotation.lines_updated' || 'deal.lines_updated' || 'quotation.saved':
      if (n('line_count') != null) out.add(historyText('{} บรรทัด', [n('line_count')]));
    case 'deal.contacts_updated' || 'account.contacts_updated':
      if (n('count') != null) out.add(historyText('{} คน', [n('count')]));
    case 'mail.case.commented':
      if ((n('count') ?? 0) > 1) out.add(historyText('{} ข้อความ', [n('count')]));
    case 'quotation.convert_to_order':
      if (s('order_number').isNotEmpty) out.add(historyText('เลขที่ {}', [s('order_number')]));
    case 'quotation.convert_to_contract':
      if (s('contract_no').isNotEmpty) out.add(historyText('เลขที่ {}', [s('contract_no')]));
    case 'quotation.create_job':
      if (s('job_id').isNotEmpty) out.add(historyText('ใบสั่งงาน #{}', [s('job_id')]));
    case 'job.signature_sign':
      if (s('signer_name').isNotEmpty) out.add(historyText('ผู้เซ็น: {}', [s('signer_name')]));
    case 'job.close':
      if ((n('closed_activities') ?? 0) > 0) out.add(historyText('ปิดกิจกรรม {} รายการ', [n('closed_activities')]));
    case 'job.reopen':
      if ((n('reopened_activities') ?? 0) > 0) out.add(historyText('เปิดกิจกรรมกลับ {} รายการ', [n('reopened_activities')]));
    case 'service_contract.renew':
      if (s('child_id').isNotEmpty) out.add(historyText('ฉบับต่ออายุ #{}', [s('child_id')]));
      if (s('parent_id').isNotEmpty) out.add(historyText('ต่ออายุจากสัญญา #{}', [s('parent_id')]));
    case 'link.create' || 'link.delete':
      final mod = _kModuleNames[s('to_module')];
      if (s('to_id').isNotEmpty) out.add('${mod == null ? humanizeHistoryKey(s('to_module')) : historyText(mod)} #${s('to_id')}');
    case 'entity_share.replace':
      final a = n('added') ?? 0, u = n('updated') ?? 0, r = n('removed') ?? 0;
      if (a > 0) out.add(historyText('เพิ่ม {} คน', [a]));
      if (u > 0) out.add(historyText('แก้สิทธิ์ {} คน', [u]));
      if (r > 0) out.add(historyText('เอาออก {} คน', [r]));
  }
  // Common keys.
  if (s('to_owner_name').isNotEmpty) out.add(historyText('ส่งต่อให้ {}', [s('to_owner_name')]));
  if (key.endsWith('email_sent') || key.endsWith('.email')) {
    final to = s('to').isNotEmpty ? s('to') : s('email_to');
    if (to.isNotEmpty) out.add(historyText('ถึง {}', [to]));
    final cc = s('cc').isNotEmpty ? s('cc') : s('email_cc');
    if (cc.isNotEmpty) out.add('CC $cc');
  } else if (s('email_to').isNotEmpty) {
    out.add(historyText('ส่งอีเมลถึง {}', [s('email_to')]));
  }
  if (d['via'] == 'email' && action.startsWith('approval')) out.add(historyText('(ผ่านอีเมล)'));
  final note = s('reason').isNotEmpty ? s('reason') : s('note');
  if (note.isNotEmpty) out.add('“${_clip(_plain(note), 160)}”');
  return out;
}

/// Account / contact 360 rows: the related record's own title.
HistoryLine _related(Map<String, dynamic> e, String type) {
  final (label, kind) = switch (type) {
    'activity' => ('กิจกรรม', HistoryKind.location),
    'call' => ('โทร', HistoryKind.call),
    'comment' => ('เพิ่มคอมเมนต์', HistoryKind.comment),
    _ => ('ดีล', HistoryKind.link),
  };
  final title = _clip(_plain(_s(e['title']).isEmpty ? _s(e['subject']) : _s(e['title'])));
  final summary = [
    for (final p in _s(e['summary']).split(' · '))
      if (p.trim().isNotEmpty) type == 'activity' ? statusValueLabel(tr(activityTypeLabel(p.trim())), module: 'activity') : statusValueLabel(p.trim()),
    if (_s(e['related_label']).isNotEmpty) _s(e['related_label']),
  ];
  return HistoryLine(
    kind: kind,
    title: title.isEmpty ? historyText(label) : '${historyText(label)}: $title',
    detail: summary.isEmpty ? null : summary.join(' · '),
  );
}
