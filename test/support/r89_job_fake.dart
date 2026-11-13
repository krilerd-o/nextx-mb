import 'package:dio/dio.dart';

import 'fake_api.dart';
import 'r86_quote_fake.dart';

/// A small NEXTX for the R89 job form tests / screenshots: the job field
/// schema as `GET /api/fields/job` really answers (labels such as
/// "ประเภทงาน (เอกสาร)", "ที่อยู่ไซต์ (snapshot)", `in_warranty` typed Text),
/// and entity lists answered the way `routes/entity.js` does: `q` over the
/// server's search floor, `filter[col]=a,b` as IN, `filter[contract_due]`,
/// `calendar_from` / `calendar_to` for appointments.

Map<String, dynamic> _f(String name, String type, String label, {bool readonly = false, String section = 'main', bool required = false}) =>
    {'name': name, 'type': type, 'label': label, 'label_th': label, 'section': section, 'access': 'editable', 'presence': 1, 'readonly': readonly, 'required': required};

/// `GET /api/fields/job` of a business (order and labels as on the server).
final realJobFields = <Map<String, dynamic>>[
  _f('job_no', 'Counter', 'เลขที่ใบสั่งงาน', readonly: true),
  _f('job_code', 'Text', 'รหัสใบสั่งงาน'),
  _f('job_name', 'Text', 'ชื่องาน'),
  _f('job_type', 'Enum', 'ประเภทงาน'),
  _f('job_status', 'Enum', 'สถานะ'),
  _f('job_priority', 'Enum', 'ความสำคัญ'),
  _f('source', 'Enum', 'แหล่งที่มา'),
  _f('related_case_id', 'CaseSelect', 'เคส'),
  _f('related_contract_id', 'ContractSelect', 'สัญญา'),
  _f('related_asset_id', 'AssetSelect', 'สินทรัพย์'),
  _f('related_location_id', 'LocationSelect', 'พื้นที่'),
  _f('related_quotation_id', 'Number', 'ใบเสนอราคา'),
  _f('related_account_id', 'AccountSelect', 'บัญชีลูกค้า'),
  _f('related_contact_id', 'ContactSelect', 'ผู้ติดต่อ'),
  _f('related_activity_id', 'Text', 'นัดหมาย'),
  _f('customer_name', 'Text', 'ชื่อลูกค้า'),
  _f('plan_start', 'DateTime', 'แผนเริ่ม'),
  _f('plan_end', 'DateTime', 'แผนสิ้นสุด'),
  _f('due_datetime', 'DateTime', 'กำหนดเสร็จ'),
  _f('actual_start', 'DateTime', 'เริ่มจริง'),
  _f('actual_end', 'DateTime', 'สิ้นสุดจริง'),
  _f('deliverable_template', 'Enum', 'แม่แบบส่งมอบ'),
  _f('cycle_index', 'Number', 'ลำดับรอบ'),
  _f('cycle_kind', 'Text', 'ชนิดรอบ'),
  _f('description', 'LongText', 'รายละเอียด'),
  _f('smownerid', 'PicklistUser', 'ผู้รับผิดชอบ'),
  _f('assign_group', 'Text', 'กลุ่มมอบหมาย'),
  _f('customer_signature', 'LicenseArea', 'ลายเซ็นลูกค้า'),
  _f('customer_signed_at', 'DateTime', 'เวลาเซ็นลูกค้า'),
  _f('customer_signed_by_name', 'Text', 'ชื่อผู้เซ็น (ลูกค้า)'),
  _f('technician_signature', 'LicenseArea', 'ลายเซ็นช่าง'),
  _f('technician_signed_at', 'DateTime', 'เวลาเซ็นช่าง'),
  _f('site_address_snapshot', 'Text', 'ที่อยู่ไซต์ (snapshot)'),
  _f('evidence_photos', 'Text', 'รูปหลักฐาน'),
  _f('location_name_snapshot', 'Text', 'ชื่อสถานที่ (snapshot)'),
  _f('salesperson_user_id', 'PicklistUser', 'เซลล์ / Sales Area'),
  _f('salesperson_name', 'Text', 'ชื่อเซลล์'),
  _f('salesperson_phone', 'Phone', 'เบอร์เซลล์'),
  _f('engineer_user_id', 'PicklistUser', 'วิศวกรบริการ'),
  _f('engineer_name', 'Text', 'ชื่อวิศวกรบริการ'),
  _f('engineer_phone', 'Phone', 'เบอร์วิศวกรบริการ'),
  _f('customer_contact_name', 'Text', 'ชื่อผู้ติดต่อ'),
  _f('customer_department', 'Text', 'แผนก/ฝ่าย'),
  _f('customer_mobile', 'Phone', 'มือถือลูกค้า'),
  _f('customer_email', 'Email', 'อีเมลลูกค้า'),
  _f('job_category', 'Enum', 'ประเภทงาน (เอกสาร)'),
  _f('job_category_other', 'Text', 'ประเภทงาน อื่นๆ'),
  _f('job_process', 'Text', 'กระบวนการทำงาน'),
  _f('job_process_other', 'Text', 'กระบวนการ อื่นๆ'),
  _f('problem_found', 'Text', 'ปัญหาที่พบ'),
  _f('work_performed', 'Text', 'วิธีการแก้ไข'),
  _f('customer_suggestion', 'Text', 'ข้อเสนอแนะให้ลูกค้า'),
  _f('additional_remark', 'LongText', 'หมายเหตุเพิ่มเติม'),
  _f('in_warranty', 'Text', 'อยู่ในระยะรับประกัน'),
  _f('acknowledgement_flags', 'Text', 'การรับทราบ'),
  _f('acknowledgement_other', 'Text', 'การรับทราบ อื่นๆ'),
  _f('acknowledgement_note', 'LongText', 'หมายเหตุรับทราบ'),
  _f('warranty_cycle_index', 'Number', 'ตรวจประกันครั้งที่'),
  _f('contract_cycle_index', 'Number', 'ตรวจตามสัญญาครั้งที่'),
  _f('technician_signed_by_name', 'Text', 'ชื่อผู้เซ็น (ช่าง)'),
  _f('template_key', 'Text', 'รูปแบบเอกสาร'),
  _f('job_template_id', 'Number', 'เทมเพลตเอกสาร'),
  _f('header_json', 'Text', 'หัวเอกสาร (ปรับเฉพาะใบ)'),
  _f('contract_po_no', 'Text', 'เลขที่สัญญา / PO'),
  _f('work_types', 'Text', 'ประเภทงาน (Work Type)'),
  _f('work_type_other', 'Text', 'ประเภทงาน อื่นๆ'),
  _f('system_types', 'Text', 'ระบบ (System)'),
  _f('system_other', 'Text', 'ระบบ อื่นๆ'),
  _f('service_results', 'Text', 'ภายหลังบริษัทฯ ได้'),
  _f('system_status', 'Text', 'ระบบทำงาน'),
  _f('accepted_at', 'DateTime', 'เวลารับงาน'),
  _f('cancelled_at', 'DateTime', 'เวลายกเลิก'),
  _f('cancel_reason', 'Text', 'เหตุผลที่ยกเลิก'),
  _f('close_note', 'LongText', 'สรุปผลการปิดงาน'),
  _f('accept_alert_at', 'DateTime', 'เตือนยังไม่มีผู้รับงานเมื่อ'),
  // A business field of its own.
  _f('cf_gate_code', 'Text', 'รหัสประตู / บัตรผ่าน', section: 'สถานที่หน้างาน', required: true),
];

Map<String, dynamic> _o(String v, String th, String en, {int def = 0}) => {'value': v, 'value_th': th, 'value_en': en, 'presence': 1, 'is_default': def};

final realJobPicklists = <String, Object>{
  'job_type': [_o('service', 'Service Job', 'Service Job'), _o('request', 'Request Job', 'Request Job')],
  'job_priority': [_o('Urgent', 'เร่งด่วน', 'Urgent'), _o('High', 'สูง', 'High'), _o('Normal', 'ปกติ', 'Normal', def: 1), _o('Low', 'ต่ำ', 'Low')],
  'job_category': [
    _o('installation', 'ติดตั้ง', 'Installation'), _o('pm', 'ตรวจเช็คสภาพ (PM)', 'PM'), _o('check', 'ตรวจสอบ', 'Check'),
    _o('repair', 'ซ่อมแซม', 'Repair'), _o('calibration', 'การปรับเทียบ', 'Calibration'), _o('other', 'อื่นๆ', 'Others'),
  ],
  'deliverable_template': [_o('service_report', 'ใบบริการ / PM', 'Service report'), _o('request_report', 'ใบซ่อม / Request', 'Request report'), _o('inspection', 'ใบตรวจรับ', 'Inspection')],
  'job_status': [_o('Open', 'เปิดงาน', 'Open')],
};

final fakeCases = <Map<String, dynamic>>[
  {
    'id': 12, 'case_no': 'CS-0012', 'case_name': 'แอร์ไม่เย็น ห้องประชุม 3', 'case_status': 'เปิดเคส', 'case_priority': 'High', 'related_account_id': 5,
    'related_contact_id': 71, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'due_datetime': '2026-11-20 17:00:00', 'smownerid': 1,
  },
  {'id': 13, 'case_no': 'CS-0013', 'case_name': 'เครื่องพิมพ์กระดาษติด', 'case_status': 'กำลังดำเนินการ', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'smownerid': 2},
  {'id': 14, 'case_no': 'CS-0014', 'case_name': 'ติดตั้งกล้องเพิ่ม 4 จุด', 'case_status': 'ปิดเคส', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'smownerid': 1},
  {'id': 15, 'case_no': 'CS-0015', 'case_name': 'ไฟดับบางส่วน อาคาร C', 'case_status': 'เปิดเคส', 'related_account_id': 6, 'customer_name': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)', 'smownerid': 1},
];

final fakeContracts = <Map<String, dynamic>>[
  {'id': 4, 'contract_no': 'SC-2026-004', 'contract_name': 'MA ระบบแอร์รายปี 2026', 'contract_status': 'Active', 'related_account_id': 5, 'related_contact_id': 72, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'end_date': '2026-12-05', 'smownerid': 1},
  {'id': 8, 'contract_no': 'SC-2025-008', 'contract_name': 'MA เครือข่าย 2025', 'contract_status': 'Expired', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'end_date': '2025-12-31', 'smownerid': 1},
  {'id': 9, 'contract_no': 'SC-2026-009', 'contract_name': 'PM ระบบไฟฟ้า 2026', 'contract_status': 'Active', 'related_account_id': 6, 'customer_name': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)', 'end_date': '2027-06-30', 'smownerid': 2},
];

final fakeLocations = <Map<String, dynamic>>[
  {
    'id': 21, 'location_name': 'สำนักงานใหญ่ อาคาร A', 'address_line1': '99/9 ถนนพระราม 9', 'address_district': 'ห้วยขวาง', 'address_province': 'กรุงเทพมหานคร',
    'address_postal_code': '10310', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'location_type': 'สำนักงาน',
  },
  {
    'id': 22, 'location_name': 'คลังสินค้าบางนา', 'address_line1': '88 ถนนบางนา-ตราด กม.5', 'address_district': 'บางพลี', 'address_province': 'สมุทรปราการ',
    'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'location_type': 'คลังสินค้า',
  },
  {'id': 23, 'location_name': 'โรงงานระยอง', 'address_province': 'ระยอง', 'address_district': 'ปลวกแดง', 'related_account_id': 6, 'customer_name': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)'},
];

final fakeAssets = <Map<String, dynamic>>[
  {'id': 31, 'asset_name': 'แอร์ Daikin 24,000 BTU ห้องประชุม 3', 'serial_no': 'DK24-88812', 'asset_no': 'AS-0031', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'asset_status': 'Active'},
  {'id': 32, 'asset_name': 'เครื่องพิมพ์ HP LaserJet M404', 'serial_no': 'HP-M404-1123', 'asset_no': 'AS-0032', 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'asset_status': 'Active'},
  {'id': 33, 'asset_name': 'ตู้ไฟ MDB', 'asset_no': 'AS-0033', 'related_account_id': 6, 'customer_name': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)'},
];

final fakeUsers = <Map<String, dynamic>>[
  {'id': 1, 'first_name': 'สมชาย', 'last_name': 'ใจดี', 'display_name': 'สมชาย ใจดี', 'phone_mobile': '0811111111', 'email1': 'somchai@nextx.co.th'},
  {'id': 2, 'first_name': 'วิภา', 'last_name': 'รักงาน', 'display_name': 'วิภา รักงาน', 'phone_mobile': '0822222222'},
  {'id': 3, 'first_name': 'เอก', 'last_name': 'ทองดี', 'display_name': 'ช่างเอก ทองดี', 'phone_mobile': '0833333333'},
  {'id': 4, 'first_name': 'บอย', 'last_name': 'ใจกล้า', 'display_name': 'ช่างบอย ใจกล้า', 'phone_mobile': '0844444444'},
  {'id': 5, 'first_name': 'มานพ', 'last_name': 'ขายเก่ง', 'display_name': 'มานพ ขายเก่ง', 'phone_mobile': '0855555555'},
];

/// Appointments of 20 Nov 2026 (Bangkok wall clock).
final fakeActivities = <Map<String, dynamic>>[
  {'id': 501, 'subject': 'PM ลูกค้า A', 'smownerid': 3, 'date_start': '2026-11-20 09:30:00', 'date_end': '2026-11-20 11:00:00'},
  {'id': 502, 'subject': 'ติดตั้ง', 'smownerid': 4, 'date_start': '2026-11-20 14:00:00', 'date_end': '2026-11-20 15:00:00'},
  {'id': 503, 'subject': 'ยกเลิกแล้ว', 'smownerid': 2, 'date_start': '2026-11-20 09:00:00', 'date_end': '2026-11-20 10:00:00', 'activitystatus': 'Cancelled'},
  {'id': 504, 'subject': 'วันอื่น', 'smownerid': 1, 'date_start': '2026-11-21 09:00:00', 'date_end': '2026-11-21 10:00:00'},
];

final fakeJobContext = <String, Object>{
  'layouts': {'allowed_layouts': ['template1', 'template2'], 'default_layout': 'template1'},
  'templates': [
    {'id': 1, 'name': 'default', 'code': 'default', 'layout_key': 'template1', 'layout_json': {'is_default': true}},
    {'id': 2, 'name': 'Service Report ใหม่', 'layout_key': 'template2', 'layout_json': {'is_default': true}},
    {'id': 3, 'name': 'สาขาชลบุรี', 'layout_key': 'template2', 'layout_json': {}},
  ],
  'document': {'new_defaults': <String, Object>{}},
};

/// An open job of the business (edit / duplicate source).
final fakeJob1 = <String, dynamic>{
  'id': 1, 'job_no': 'JOB26-0001', 'job_status': 'Open', 'job_name': 'ล้างแอร์ประจำไตรมาส อาคาร A', 'job_type': 'service', 'job_priority': 'High',
  'job_category': 'pm', 'job_code': 'PO-SIAM-7781', 'related_contract_id': 4, 'related_account_id': 5, 'related_contact_id': 71,
  'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'customer_contact_name': 'สมศรี ใจงาม', 'customer_mobile': '0899999999',
  'location_name_snapshot': 'สำนักงานใหญ่ อาคาร A', 'site_address_snapshot': '99/9 ถนนพระราม 9 ห้วยขวาง กรุงเทพมหานคร 10310 (13.756331,100.565421)',
  'related_location_id': 21, 'related_asset_id': 31, 'in_warranty': true, 'description': 'ล้างแอร์ 6 เครื่อง ชั้น 2-3', 'cf_gate_code': '#4410',
  'plan_start': '2026-11-20T09:00:00', 'plan_end': '2026-11-20T12:00:00', 'due_datetime': '2026-11-20 17:00:00', 'smownerid': 3,
  'engineer_user_id': 4, 'engineer_name': 'ช่างบอย ใจกล้า', 'assign_group': 'ทีมแอร์ A', 'template_key': 'template2', 'job_template_id': 2,
  'deliverable_template': 'service_report', 'related_activity_id': 400, 'customer_signature': 'sig.png', 'acknowledgement_note': 'ลูกค้ารับทราบ',
  'warranty_cycle_index': 2, 'actual_start': '2026-11-20T09:10:00',
};

Map<String, Object?> jobFakeReplies({Map<String, Object?> extra = const {}}) => {
      'GET /api/fields/job': {'list': realJobFields, 'picklists': realJobPicklists},
      'GET /api/field-service/job-form-context': fakeJobContext,
      'GET /api/settings/job/activity-templates': [
        {'id': 3, 'name': 'PM แอร์', 'items': [{'subject': 'ล้างแผง'}, {'subject': 'เช็คน้ำยา'}]},
      ],
      'GET /api/users': {'list': fakeUsers},
      for (final r in fakeAccounts) 'GET /api/entity/account/${r['id']}': r,
      for (final r in fakeContacts) 'GET /api/entity/contact/${r['id']}': r,
      for (final r in fakeCases) 'GET /api/entity/case/${r['id']}': r,
      for (final r in fakeContracts) 'GET /api/entity/service_contract/${r['id']}': r,
      for (final r in fakeLocations) 'GET /api/entity/service_location/${r['id']}': r,
      for (final r in fakeAssets) 'GET /api/entity/asset/${r['id']}': r,
      'GET /api/entity/job/1': fakeJob1,
      'PUT /api/entity/job/1': {'id': 1},
      'POST /api/entity/job': {'id': 77, 'job_no': 'JOB26-0077'},
      'GET /api/field-service/jobs/1/match-users': {
        'required': [{'skill_id': 1, 'skill_name': 'แอร์'}, {'skill_id': 2, 'skill_name': 'ไฟฟ้า'}],
        'candidates': [
          {'user_id': 4, 'display_name': 'ช่างบอย ใจกล้า', 'matched_skills': 2, 'required_skills': 2, 'score': 1},
          {'user_id': 3, 'display_name': 'ช่างเอก ทองดี', 'matched_skills': 1, 'required_skills': 2, 'score': 0.5},
        ],
      },
      'POST /api/field-service/jobs/77/generate-activities': {'created': 2},
      'POST /api/field-service/jobs/77/schedule': {'activity_id': 601},
      ...extra,
    };

/// `MODULE_SEARCH_COLUMNS` of the server for the job pickers.
const _floor = {
  'case': ['case_name', 'case_no', 'customer_name'],
  'service_contract': ['contract_no', 'contract_code', 'contract_ref', 'contract_name', 'customer_name', 'contract_status'],
  'service_location': ['location_no', 'location_code', 'location_name', 'customer_name', 'location_type'],
  'asset': ['asset_no', 'asset_name', 'serial_no', 'customer_name', 'asset_status'],
  'activity': ['subject'],
};

/// Rows `GET /api/entity/:module` would answer for [qp].
List<Map<String, dynamic>> jobServerSearch(String module, List<Map<String, dynamic>> rows, Map<String, dynamic> qp) {
  final q = '${qp['q'] ?? ''}'.trim().toLowerCase();
  var out = [
    for (final r in rows)
      if (q.isEmpty || (_floor[module] ?? const <String>[]).any((c) => '${r[c] ?? ''}'.toLowerCase().contains(q))) r,
  ];
  qp.forEach((k, v) {
    final m = RegExp(r'^filter\[(\w+)\]$').firstMatch(k);
    if (m == null) return;
    final col = m[1]!;
    if (col == 'contract_due') {
      // expiring: Active and ending within 30 days of 13 Nov 2026.
      out = [for (final r in out) if (r['contract_status'] == 'Active' && '${r['end_date']}'.compareTo('2026-12-13') <= 0) r];
      return;
    }
    final values = '$v'.split(',').map((x) => x.trim()).toSet();
    out = [for (final r in out) if (values.contains('${r[col]}')) r];
  });
  final from = '${qp['calendar_from'] ?? ''}', to = '${qp['calendar_to'] ?? ''}';
  if (from.isNotEmpty) {
    out = [for (final r in out) if ('${r['date_start']}'.substring(0, 10).compareTo(to) <= 0 && '${r['date_end'] ?? r['date_start']}'.substring(0, 10).compareTo(from) >= 0) r];
  }
  final limit = int.tryParse('${qp['limit'] ?? 30}') ?? 30;
  final page = int.tryParse('${qp['page'] ?? 1}') ?? 1;
  return out.skip((page - 1) * limit).take(limit).toList();
}

/// Answers the entity lists of the job form like the real server.
void installJobFakeServer(FakeNextxAdapter adapter) {
  installQuoteFakeServer(adapter);
  final quote = adapter.onRequest;
  final tables = {'case': fakeCases, 'service_contract': fakeContracts, 'service_location': fakeLocations, 'asset': fakeAssets, 'activity': fakeActivities};
  adapter.onRequest = (RequestOptions o) {
    quote?.call(o);
    final m = RegExp(r'^/api/entity/(\w+)$').firstMatch(o.path);
    if (m == null || o.method.toUpperCase() != 'GET') return;
    final rows = tables[m[1]];
    if (rows == null) return;
    final list = jobServerSearch(m[1]!, rows, o.queryParameters);
    final all = jobServerSearch(m[1]!, rows, {...o.queryParameters, 'limit': '100000', 'page': '1'});
    adapter.replies['GET ${o.path}'] = {'list': list, 'meta': {'total': all.length}};
  };
}
