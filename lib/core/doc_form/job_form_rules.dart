/// Rules of the job (ใบสั่งงาน) step form: the fixed field labels, job type /
/// category / priority choices, the scheduler (Bangkok wall clock), the
/// case / contract link cards and patches, technician availability and the
/// site address. Pure Dart, so the tests pin them without widgets.
library;

import '../../widgets/fields/field_validate.dart' show unwrapFieldValue;
import 'doc_form_rules.dart';

String _s(Object? v) {
  final u = unwrapFieldValue(v);
  if (u == null) return '';
  final t = '$u'.trim();
  return t == 'null' ? '' : t;
}

String _two(int n) => n.toString().padLeft(2, '0');

// ───────────────────────────────────────────────────────────── labels

/// What the form calls the core fields. The column labels are storage notes
/// ("ที่อยู่ไซต์ (snapshot)", "มือถือลูกค้า", "ประเภทงาน (เอกสาร)") — never shown.
const Map<String, String> kJobFieldLabels = {
  'job_type': 'ประเภทงาน',
  'job_name': 'ชื่องาน',
  'job_priority': 'ความสำคัญ',
  'job_category': 'ลักษณะงาน',
  'job_category_other': 'ระบุลักษณะงาน',
  'job_code': 'รหัสอ้างอิงงาน',
  'related_case_id': 'เคส',
  'related_contract_id': 'สัญญาบริการ',
  'related_account_id': 'ลูกค้า',
  'related_contact_id': 'ผู้ติดต่อ',
  'customer_name': 'ชื่อลูกค้า',
  'customer_contact_name': 'ชื่อผู้ติดต่อบนใบงาน',
  'customer_department': 'แผนก / ฝ่าย',
  'customer_mobile': 'เบอร์โทรผู้ติดต่อหน้างาน',
  'customer_email': 'อีเมลผู้ติดต่อ',
  'contract_po_no': 'เลขที่สัญญา / PO ของลูกค้า',
  'location_name_snapshot': 'ชื่อสถานที่',
  'site_address_snapshot': 'ที่อยู่หน้างาน',
  'related_location_id': 'พื้นที่บริการ',
  'related_asset_id': 'สินทรัพย์ / เครื่องของลูกค้า',
  'in_warranty': 'อยู่ในระยะรับประกัน',
  'plan_start': 'เริ่ม (แผน)',
  'plan_end': 'สิ้นสุด (แผน)',
  'due_datetime': 'กำหนดเสร็จ',
  'smownerid': 'ผู้รับผิดชอบ (ช่าง)',
  'engineer_user_id': 'วิศวกรบริการ',
  'salesperson_user_id': 'ฝ่ายขาย',
  'assign_group': 'ทีม / กลุ่มงาน',
  'description': 'รายละเอียด / สิ่งที่ต้องทำ',
  'deliverable_template': 'แบบรายงานส่งมอบ',
  'template_key': 'รูปแบบเอกสาร',
  'job_template_id': 'เทมเพลตเอกสาร',
};

String jobFieldLabel(String name) => kJobFieldLabels[name] ?? name;

// ─────────────────────────────────────────────────────────── choices

/// One choice of a job picklist (value + current-language label + help).
class JobChoice {
  const JobChoice(this.value, this.label, {this.help});
  final String value;
  final String label;
  final String? help;
}

/// `job_type` is the FSM flow (web "ประเภทงาน (FSM)"): Service / Request.
const Map<String, String> kJobTypeHelp = {
  'service': 'งานบริการตามแผน สัญญา หรือ PM — ออกรายงานบริการ',
  'request': 'งานตามคำขอ / แจ้งซ่อมของลูกค้า หรือจากเคส',
};

/// `job_category` is NOT a second job type: it is the work category ticked on
/// the Template-1 service report (ติดตั้ง / PM / ตรวจสอบ / ซ่อม / ปรับเทียบ).
const List<(String, String)> kJobCategoryFallback = [
  ('installation', 'ติดตั้ง'),
  ('pm', 'ตรวจเช็คสภาพ (PM)'),
  ('check', 'ตรวจสอบ'),
  ('repair', 'ซ่อมแซม'),
  ('calibration', 'การปรับเทียบ'),
  ('other', 'อื่นๆ'),
];

const List<(String, String)> kJobTypeFallback = [('service', 'Service Job'), ('request', 'Request Job')];
const List<(String, String)> kJobPriorityFallback = [('Urgent', 'เร่งด่วน'), ('High', 'สูง'), ('Normal', 'ปกติ'), ('Low', 'ต่ำ')];
const List<(String, String)> kDeliverableFallback = [('service_report', 'ใบบริการ / PM'), ('request_report', 'ใบซ่อม / Request'), ('inspection', 'ใบตรวจรับ')];

/// Choices of [name] from the business picklist (Thai / English label), else [fallback].
List<JobChoice> jobChoices(String name, Map<String, List<Map<String, dynamic>>> picklists, List<(String, String)> fallback, {bool en = false}) {
  final out = <JobChoice>[];
  for (final o in picklists[name] ?? const <Map<String, dynamic>>[]) {
    final v = _s(o['value'] ?? o['id']);
    if (v.isEmpty || '${o['presence'] ?? 1}' == '0') continue;
    final th = _s(o['value_th'] ?? o['label_th'] ?? o['label']);
    final eng = _s(o['value_en'] ?? o['label_en']);
    final label = en ? (eng.isNotEmpty ? eng : (th.isNotEmpty ? th : v)) : (th.isNotEmpty ? th : (eng.isNotEmpty ? eng : v));
    out.add(JobChoice(v, label, help: name == 'job_type' ? kJobTypeHelp[v] : null));
  }
  if (out.isNotEmpty) return out;
  return [for (final (v, l) in fallback) JobChoice(v, l, help: name == 'job_type' ? kJobTypeHelp[v] : null)];
}

String jobChoiceLabel(List<JobChoice> choices, Object? value) {
  final v = _s(value);
  if (v.isEmpty) return '';
  return choices.where((c) => c.value == v).firstOrNull?.label ?? v;
}

// ─────────────────────────────────────────────────────────── scheduler

const _thDays = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
const _enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `ศ. 20 พ.ย. 2569` (Buddhist year) / `Fri 20 Nov 2026`.
String jobDayLabel(DateTime d, {bool en = false, bool year = true}) {
  final day = (en ? _enDays : _thDays)[d.weekday - 1];
  final mon = (en ? _enMonths : _thMonths)[d.month - 1];
  final y = year ? ' ${en ? d.year : d.year + 543}' : '';
  return '$day ${d.day} $mon$y';
}

String jobClock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The plan as one line: `ศ. 20 พ.ย. 2569 · 09:00–12:00`; over several days
/// `ศ. 20 พ.ย. 09:00 – ส. 21 พ.ย. 2569 12:00`. Values are Bangkok wall clock.
String jobWhenSummary(DateTime? start, DateTime? end, {bool en = false}) {
  if (start == null) return '';
  if (end == null || !end.isAfter(start)) return '${jobDayLabel(start, en: en)} · ${jobClock(start)}';
  if (_sameDay(start, end)) return '${jobDayLabel(start, en: en)} · ${jobClock(start)}–${jobClock(end)}';
  return '${jobDayLabel(start, en: en, year: start.year != end.year)} ${jobClock(start)} – ${jobDayLabel(end, en: en)} ${jobClock(end)}';
}

/// `2 ชม.` · `1 ชม. 30 นาที` · `45 นาที` · `1 วัน 2 ชม.`
String jobDurationText(Duration d, {bool en = false}) {
  final mins = d.inMinutes;
  if (mins <= 0) return '';
  final days = mins ~/ (24 * 60);
  final hours = (mins % (24 * 60)) ~/ 60;
  final m = mins % 60;
  final parts = <String>[
    if (days > 0) en ? '${days}d' : '$days วัน',
    if (hours > 0) en ? '${hours}h' : '$hours ชม.',
    if (m > 0) en ? '${m}m' : '$m นาที',
  ];
  return parts.join(' ');
}

/// Length chips of the scheduler (hours).
const List<int> kJobDurationHours = [1, 2, 3, 4, 8];

/// Default length when only a start is picked.
const Duration kJobDefaultLength = Duration(hours: 2);

/// A new start keeps the job's length (or [fallback] when there is none yet).
({DateTime start, DateTime end}) jobMoveStart(DateTime? oldStart, DateTime? oldEnd, DateTime newStart, {Duration fallback = kJobDefaultLength}) {
  final len = oldStart != null && oldEnd != null && oldEnd.isAfter(oldStart) ? oldEnd.difference(oldStart) : fallback;
  return (start: newStart, end: newStart.add(len));
}

/// [base] on the calendar day of [day] (time kept); 09:00 when [base] is null.
DateTime jobOnDay(DateTime? base, DateTime day) => DateTime(day.year, day.month, day.day, base?.hour ?? 9, base?.minute ?? 0);

/// [base]'s day at [hour]:[minute].
DateTime jobAtTime(DateTime base, int hour, int minute) => DateTime(base.year, base.month, base.day, hour, minute);

/// Quick due choices from Thai "now" and the plan.
List<({String key, String label, DateTime at})> jobDueQuick(DateTime now, {DateTime? planEnd}) {
  DateTime at17(DateTime d) => DateTime(d.year, d.month, d.day, 17);
  return [
    if (planEnd != null) (key: 'plan_end', label: 'ตามเวลาสิ้นสุด', at: planEnd),
    if (now.hour < 17) (key: 'today', label: 'วันนี้ 17:00', at: at17(now)),
    (key: 'tomorrow', label: 'พรุ่งนี้ 17:00', at: at17(DateTime(now.year, now.month, now.day + 1))),
    (key: 'd3', label: 'ภายใน 3 วัน', at: at17(DateTime(now.year, now.month, now.day + 3))),
    (key: 'd7', label: 'ภายใน 7 วัน', at: at17(DateTime(now.year, now.month, now.day + 7))),
  ];
}

bool jobOverlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

// ─────────────────────────────────────────────── technicians (who is free)

/// What a technician's calendar looks like for the job's plan.
class TechAvailability {
  const TechAvailability({this.sameDay = 0, this.clashes = 0});

  /// Appointments the same day.
  final int sameDay;

  /// Appointments overlapping the plan.
  final int clashes;
  bool get free => clashes == 0;
}

DateTime? _wall(Object? raw) {
  final s = _s(raw);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?').firstMatch(s);
  if (m == null) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return DateTime(g(1), g(2), g(3), g(4), g(5));
}

bool _cancelled(Map<String, dynamic> a) {
  final st = '${a['activitystatus'] ?? a['eventstatus'] ?? a['status'] ?? ''}'.toLowerCase();
  return st.contains('cancel') || st.contains('ยกเลิก');
}

/// Per user id: appointments (calendar activities, Bangkok wall clock) the
/// same day as [start] and those overlapping [start]–[end].
Map<String, TechAvailability> technicianAvailability(List<Map<String, dynamic>> activities, DateTime start, DateTime end) {
  final day = <String, int>{}, clash = <String, int>{};
  for (final a in activities) {
    if (_cancelled(a)) continue;
    final s = _wall(a['date_start']);
    if (s == null) continue;
    var e = _wall(a['date_end']);
    if (e == null || !e.isAfter(s)) e = s.add(const Duration(hours: 1));
    final who = {_s(a['smownerid']), ..._s(a['assign_to']).split(',').map((x) => x.trim())}..removeWhere((x) => x.isEmpty || x == '0');
    for (final u in who) {
      if (_sameDay(s, start) || jobOverlaps(DateTime(start.year, start.month, start.day), DateTime(start.year, start.month, start.day + 1), s, e)) {
        day[u] = (day[u] ?? 0) + 1;
      }
      if (jobOverlaps(start, end, s, e)) clash[u] = (clash[u] ?? 0) + 1;
    }
  }
  return {
    for (final u in {...day.keys, ...clash.keys}) u: TechAvailability(sameDay: day[u] ?? 0, clashes: clash[u] ?? 0),
  };
}

/// `GET /field-service/jobs/:id/match-users` → `{required, candidates}`;
/// per user id: (matched, required) skills.
Map<String, ({int matched, int required})> technicianSkillMatch(Map<String, dynamic> data) {
  final list = data['candidates'];
  final out = <String, ({int matched, int required})>{};
  if (list is! List) return out;
  for (final c in list) {
    if (c is! Map) continue;
    final id = _s(c['user_id'] ?? c['id']);
    if (id.isEmpty) continue;
    out[id] = (matched: int.tryParse('${c['matched_skills'] ?? 0}') ?? 0, required: int.tryParse('${c['required_skills'] ?? 0}') ?? 0);
  }
  return out;
}

/// A user's display name (`first last` / display_name / user_name).
String jobUserName(Map<String, dynamic> u) {
  final d = _s(u['display_name'] ?? u['name'] ?? u['label']);
  if (d.isNotEmpty) return d;
  final full = [_s(u['first_name']), _s(u['last_name'])].where((x) => x.isNotEmpty).join(' ');
  if (full.isNotEmpty) return full;
  return _s(u['user_name']).isNotEmpty ? _s(u['user_name']) : _s(u['email1'] ?? u['email']);
}

String userPhoneOf(Map<String, dynamic> u) => _s(u['phone_mobile'] ?? u['phone_work'] ?? u['phone'] ?? u['mobile']);

// ─────────────────────────────────────────────── case / contract links

/// Case statuses that are still open (the "เปิดอยู่" filter of the picker).
const List<String> kOpenCaseStatuses = ['เปิดเคส', 'ส่งต่อเคส', 'รับเคส', 'รอการตอบรับ', 'กำลังดำเนินการ'];

const Map<String, String> kContractStatusLabel = {
  'Active': 'ใช้งาน',
  'Draft': 'ร่าง',
  'Pending_Approval': 'รออนุมัติ',
  'Expired': 'หมดอายุ',
  'Cancelled': 'ยกเลิก',
};

/// How a linked case / contract is shown (picker row and the form's card).
class JobLinkView {
  const JobLinkView({required this.no, required this.title, required this.customer, required this.status, this.extra = '', this.closed = false});
  final String no;
  final String title;
  final String customer;
  final String status;

  /// Due / end date line.
  final String extra;
  final bool closed;

  String get heading => [no, title].where((x) => x.isNotEmpty).join(' · ');
}

String _dmy(Object? raw) {
  final d = _wall(raw);
  return d == null ? '' : '${d.day}/${d.month}/${d.year + 543}';
}

JobLinkView jobLinkView(String module, Map<String, dynamic> r) {
  final customer = _s(r['customer_name']).isNotEmpty ? _s(r['customer_name']) : _s(r['account_name']);
  if (module == 'case') {
    final st = _s(r['case_status']);
    final due = _dmy(r['due_datetime']);
    return JobLinkView(
      no: _s(r['case_no']).isNotEmpty ? _s(r['case_no']) : '#${_s(r['id'])}',
      title: _s(r['case_name']),
      customer: customer,
      status: st,
      extra: due.isEmpty ? '' : 'กำหนด $due',
      closed: st.isNotEmpty && !kOpenCaseStatuses.contains(st),
    );
  }
  final st = _s(r['contract_status']);
  final end = _dmy(r['end_date']);
  return JobLinkView(
    no: _s(r['contract_no']).isNotEmpty ? _s(r['contract_no']) : '#${_s(r['id'])}',
    title: _s(r['contract_name']),
    customer: customer,
    status: kContractStatusLabel[st] ?? st,
    extra: end.isEmpty ? '' : 'สิ้นสุด $end',
    closed: st == 'Expired' || st == 'Cancelled',
  );
}

/// Linking a case / contract inside the form: only the blanks are filled
/// from it (name, customer, contact, due) — what the user typed stays.
Map<String, dynamic> jobLinkPatch(String module, Map<String, dynamic> row, Map<String, dynamic> values) {
  final p = jobPrefillFrom(module, row);
  final key = module == 'case' ? 'related_case_id' : 'related_contract_id';
  final out = <String, dynamic>{key: row['id']};
  bool blank(String k) => isBlankValue(values[k]);
  if (blank('job_name') && _s(p['job_name']).isNotEmpty) out['job_name'] = p['job_name'];
  if (blank('related_account_id') && !isBlankValue(p['related_account_id'])) {
    out['related_account_id'] = p['related_account_id'];
    if (blank('customer_name') && _s(p['customer_name']).isNotEmpty) out['customer_name'] = p['customer_name'];
    if (blank('related_contact_id') && !isBlankValue(p['related_contact_id'])) out['related_contact_id'] = p['related_contact_id'];
  }
  if (blank('due_datetime') && !isBlankValue(p['due_datetime'])) out['due_datetime'] = p['due_datetime'];
  return out;
}

// ─────────────────────────────────────────────────────────── site

/// `… (13.750000,100.500000)` at the end of a site address.
final RegExp _coordTail = RegExp(r'\((-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)\)\s*$');

/// Address text with the pin's coordinates appended (what the web shows and
/// the technician opens in maps).
String siteAddressWithPin(String address, double lat, double lng) {
  final base = address.replaceAll(_coordTail, '').replaceAll('\n', ' ').trim();
  final coord = '(${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)})';
  return base.isEmpty ? coord : '$base $coord';
}

/// The pin in a site address, if any.
({double lat, double lng})? siteCoordsOf(Object? address) {
  final m = _coordTail.firstMatch(_s(address));
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!), lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null) return null;
  return (lat: lat, lng: lng);
}

/// Address without the coordinates (for display).
String siteAddressText(Object? address) => _s(address).replaceAll(_coordTail, '').trim();

/// One line from Thai address parts (บ้านเลขที่ ถนน · ตำบล · อำเภอ · จังหวัด · รหัสไปรษณีย์).
String composeThaiAddress({String line = '', String subdistrict = '', String district = '', String province = '', String postal = ''}) =>
    [line, subdistrict, district, province, postal].map((x) => x.trim()).where((x) => x.isNotEmpty).join(' ');
