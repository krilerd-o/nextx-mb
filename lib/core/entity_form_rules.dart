import 'package:flutter/material.dart';

import '../widgets/nx_icons.dart';
import 'thai_time.dart';

/// Create / edit form rules ported from the NEXTX web
/// (`crmModernCreateLayout.js`, `crmEntityFormLayout.js`, `entityFormField.js`)
/// so the app groups fields, marks required ones and pre-fills the same way.

/// Fields the web always requires per module (on top of schema flags).
const Map<String, List<String>> kModuleRequiredFields = {
  'lead': ['lead_status', 'lead_firstname'],
  'contact': ['contact_status', 'contact_firstname'],
  'account': ['account_status', 'account_name', 'smownerid'],
  'case': ['case_status', 'case_type', 'case_priority', 'case_name', 'smownerid'],
  'activity': ['subject', 'date_start', 'smownerid'],
  'deal': ['deal_name', 'deal_stage', 'smownerid'],
  'quotation': ['quotation_status', 'smownerid'],
  'service_contract': ['contract_name', 'smownerid'],
};

/// System columns never shown on create / edit.
const Set<String> kSkipCreateColumns = {
  'id', 'crmid', 'created_at', 'updated_at', 'date_entered', 'date_modified', 'smcreatorid', 'createdtime',
  'modifiedby', 'modifiedtime', 'open_deal_value', 'closed_revenue', 'active_contact_count', 'rollup_updated_at',
};

bool moduleRequiresField(String module, String field) =>
    (kModuleRequiredFields[module] ?? const []).contains(field);

/// Form section a field belongs to (same buckets as the web's modern form).
String formSectionOf(String module, String field) {
  final c = field.toLowerCase();
  if (field == 'smownerid' || field == 'assign_to') return 'ownership';
  final addr = RegExp(
      r'(^|_)address|street|city|state|province|district|postal|zip|country|billing|shipping|alley|road|region|village|locationmap');
  final contact = RegExp(r'email|e_mail|phone|mobile|fax|website|url');
  switch (module) {
    case 'lead':
      if (addr.hasMatch(c)) return 'address';
      if (contact.hasMatch(c) && !c.contains('company')) return 'contact';
      return 'general';
    case 'product':
    case 'service':
      if (RegExp(r'default_pm|default_warranty|pm_frequency|warranty_month').hasMatch(c)) return 'entitlement';
      if (addr.hasMatch(c) || RegExp(r'warehouse|location').hasMatch(c)) return 'address';
      if (contact.hasMatch(c)) return 'contact';
      return 'general';
    case 'deal':
      if (RegExp(r'related_account|related_contact|related_lead').hasMatch(c)) return 'contact';
      return 'general';
    case 'quotation':
      if (addr.hasMatch(c)) return 'address';
      if (contact.hasMatch(c)) return 'contact';
      if (RegExp(r'^customer_|^contact_|^client_').hasMatch(c)) return 'contact';
      return 'general';
    case 'service_contract':
      if (addr.hasMatch(c)) return 'address';
      if (contact.hasMatch(c) || RegExp(r'related_account|related_contact|customer_name').hasMatch(c)) return 'contact';
      return 'general';
    default:
      if (addr.hasMatch(c)) return 'address';
      if (contact.hasMatch(c)) return 'contact';
      return 'general';
  }
}

/// Section title (Thai; translated by tr()), icon and tint.
const Map<String, ({String title, IconData icon, Color color})> kFormSections = {
  'general': (title: 'ข้อมูลทั่วไป', icon: NxI.briefcase, color: Color(0xFF3B82F6)),
  'entitlement': (title: 'รอบบริการและประกัน', icon: NxI.clock, color: Color(0xFF8B5CF6)),
  'contact': (title: 'ช่องทางติดต่อ', icon: NxI.envelope, color: Color(0xFF10B981)),
  'address': (title: 'ที่อยู่', icon: NxI.mapPin, color: Color(0xFF8B5CF6)),
  'ownership': (title: 'มอบหมาย', icon: NxI.user, color: Color(0xFFF97316)),
};

const List<String> kFormSectionOrder = ['general', 'entitlement', 'contact', 'address', 'ownership'];

/// One-line tip shown at the top of each module's create form (web copy).
const Map<String, String> kFormInsight = {
  'lead': 'ลีดจากช่องทางออนไลน์มักมีอัตราแปลงที่ดีขึ้นเมื่อติดตามภายใน 24 ชม.',
  'contact': 'ผู้ติดต่อที่ผูกกับบัญชีลูกค้ามักช่วยให้ทีมขายเห็นบริบทครบขึ้น',
  'account': 'ข้อมูลบัญชีที่อัปเดตสม่ำเสมอช่วยรายงานและการมอบหมายงานแม่นยำขึ้น',
  'case': 'อัปเดตสถานะเคสให้ชัดช่วยทีมบริการและลูกค้าเห็นความคืบหน้าเดียวกัน',
  'activity': 'ผูกลูกค้า ใส่วันเวลาและจุดนัดให้ชัด เพื่อให้ทีมเช็คอินและเห็นนัดในปฏิทิน',
  'product': 'รายละเอียดสินค้าและราคาที่ตรงกันทุกช่องทางลดความสับสนในการเสนอราคา',
  'service': 'นิยามบริการและราคามาตรฐานช่วยให้ทีมขายและปฏิบัติการสอดคล้องกัน',
  'quotation': 'ตรวจสอบบรรทัดและส่วนลดก่อนส่งใบเสนอราคาเพื่อลดการแก้ไขรอบสอง',
  'service_contract': 'ตั้งวันสิ้นสุดและผู้รับผิดชอบให้ชัด เพื่อให้ระบบแจ้งเตือนก่อนสัญญาหมดอายุ',
};

// ── picklist helpers (same semantics as the web)

bool _present(Map o) => o['presence'] == null || '${o['presence']}' != '0';
String? _val(Map? o) {
  if (o == null) return null;
  final v = o['value'] ?? o['value_th'];
  return v == null || '$v'.isEmpty ? null : '$v';
}

/// First visible option (status-like fields start at level one).
String? pickFirstOption(List<Map<String, dynamic>>? options, String? fallback) {
  for (final o in options ?? const <Map<String, dynamic>>[]) {
    if (!_present(o)) continue;
    final v = _val(o);
    if (v != null) return v;
  }
  return fallback;
}

/// The option flagged `is_default`, else the first one.
String? pickDefaultOption(List<Map<String, dynamic>>? options, String? fallback) {
  final list = (options ?? const <Map<String, dynamic>>[]).where(_present).toList();
  if (list.isEmpty) return fallback;
  final def = list.where((o) => '${o['is_default']}' == '1' || o['is_default'] == true).firstOrNull;
  return _val(def) ?? _val(list.first) ?? fallback;
}

/// The first option matching one of [preferred] (value / th / en), else default.
String? pickPreferredOption(List<Map<String, dynamic>>? options, List<String> preferred, String? fallback) {
  final prefs = preferred.map((p) => p.trim().toLowerCase()).where((p) => p.isNotEmpty);
  for (final p in prefs) {
    for (final o in options ?? const <Map<String, dynamic>>[]) {
      if (!_present(o)) continue;
      final hit = [o['value'], o['value_th'], o['label_th'], o['value_en'], o['label_en']]
          .any((x) => '${x ?? ''}'.trim().toLowerCase() == p);
      if (hit) return _val(o);
    }
  }
  return pickDefaultOption(options, fallback);
}

String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _ymdhm(DateTime d) => '${_ymd(d)} ${_two(d.hour)}:${_two(d.minute)}:00';

/// Values a new record starts with (owner = me, first status, today …).
/// Times are Thailand wall time, as the web sends them.
Map<String, dynamic> createDefaults(
  String module, {
  String? userId,
  Map<String, List<Map<String, dynamic>>> picklists = const {},
  DateTime? now,
}) {
  final t = now ?? thaiNow();
  final p = picklists;
  final base = <String, dynamic>{
    if (userId != null && userId.isNotEmpty) 'smownerid': int.tryParse(userId) ?? userId,
  };
  switch (module) {
    case 'lead':
      return {
        ...base,
        'lead_status': pickFirstOption(p['lead_status'], 'New'),
        'lead_rating': pickDefaultOption(p['lead_rating'], 'Warm'),
        'lead_datetime': _ymdhm(t),
      };
    case 'contact':
      return {
        ...base,
        'contact_status': pickFirstOption(p['contact_status'], 'Customer'),
        'contact_rating': pickDefaultOption(p['contact_rating'], 'Warm'),
        'contact_datetime': _ymdhm(t),
      };
    case 'account':
      return {
        ...base,
        'account_status': pickFirstOption(p['account_status'], 'Customer'),
        'account_rating': pickDefaultOption(p['account_rating'], 'Warm'),
        'account_grade': pickDefaultOption(p['account_grade'], 'No Grade'),
        'account_datetime': _ymdhm(t),
      };
    case 'case':
      return {
        ...base,
        'case_status': pickFirstOption(p['case_status'], 'เปิดเคส'),
        'case_priority': pickPreferredOption(p['case_priority'], const ['Medium', 'ปานกลาง', 'Normal'], 'Medium'),
        'case_type': pickDefaultOption(p['case_type'], null),
        'case_category': pickPreferredOption(p['case_category'], const ['External', 'external'], 'External'),
        'case_received_on': pickDefaultOption(p['case_received_on'], null),
        'open_datetime': _ymdhm(t),
        'plan_datetime': _ymdhm(t),
        'due_datetime': _ymdhm(t),
      };
    case 'activity':
      return {
        ...base,
        'activitytype': pickDefaultOption(p['activitytype'], 'Meeting'),
        'status': pickFirstOption(p['status'], 'Planned'),
        'date_start': _ymdhm(t),
        'date_end': _ymdhm(t.add(const Duration(hours: 1))),
      };
    case 'deal':
      return {
        ...base,
        'deal_stage': pickFirstOption(p['deal_stage'], null),
        'deal_type': pickDefaultOption(p['deal_type'], 'New Business'),
        'currency': 'THB',
      };
    case 'quotation':
      return {
        ...base,
        'quotation_status': pickFirstOption(p['quotation_status'], 'Draft'),
        'header_discount_type': pickDefaultOption(p['header_discount_type'], 'none'),
        'quote_date': _ymd(t),
        'currency': 'THB',
        'tax_type': pickDefaultOption(p['tax_type'], 'exclude'),
        'tax_rate': 7,
      };
    case 'job':
      return {
        ...base,
        'job_status': pickFirstOption(p['job_status'], 'Draft'),
        'job_type': pickDefaultOption(p['job_type'], null),
        'job_priority': pickDefaultOption(p['job_priority'], 'Normal'),
      };
    case 'service_contract':
      return {
        ...base,
        'contract_status': pickFirstOption(p['contract_status'], 'Draft'),
        'contract_type': pickDefaultOption(p['contract_type'], null),
        'currency': 'THB',
        'alert_days': 30,
        'contract_datetime': _ymdhm(t),
        'start_date': _ymd(t),
      };
    default:
      return base;
  }
}

/// Suggested case subject from its type, e.g. `[แจ้งซ่อม] : งานซ่อม / บริการหลังการขาย`.
String caseSubjectSuggestion(String caseType) {
  const hints = {
    'Incoming': 'รับเรื่องจากลูกค้า',
    'Outgoing': 'ติดตามลูกค้า',
    'Repair': 'งานซ่อม / บริการหลังการขาย',
    'Complaint': 'ข้อร้องเรียนจากลูกค้า',
    'Inquiry': 'สอบถามข้อมูล',
    'Service request': 'คำขอบริการ',
    'Follow-up': 'ติดตามงานค้าง',
    'ขาเข้า': 'รับเรื่องจากลูกค้า',
    'ขาออก': 'ติดตามลูกค้า',
    'แจ้งซ่อม': 'งานซ่อม / บริการหลังการขาย',
    'ร้องเรียน': 'ข้อร้องเรียนจากลูกค้า',
    'สอบถาม': 'สอบถามข้อมูล',
    'คำขอบริการ': 'คำขอบริการ',
    'ติดตามงาน': 'ติดตามงานค้าง',
  };
  final t = caseType.trim();
  if (t.isEmpty) return '';
  return '[$t] : ${hints[t] ?? 'สรุปประเด็นหลักของเคส'}';
}

/// Modules the web duplicates on the server (lines and links come along).
const Set<String> kServerDuplicateModules = {'quotation', 'job'};

/// Running numbers the server assigns again for a copy.
const Set<String> kRunningNumberFields = {
  'account_no', 'lead_no', 'contact_no', 'case_no', 'product_no', 'service_no', 'quotation_no', 'contract_no',
  'account_number', 'lead_number', 'contact_number', 'deal_no', 'job_no', 'asset_no',
};

/// Form values for "ทำซ้ำ": the source's data, minus ids/numbers/system
/// columns, owner = me, and status/timestamps reset like the web.
Map<String, dynamic> duplicateFormValues(
  String module,
  Map<String, dynamic> source, {
  String? userId,
  Map<String, List<Map<String, dynamic>>> picklists = const {},
  DateTime? now,
}) {
  final t = now ?? thaiNow();
  final copy = <String, dynamic>{
    for (final e in source.entries)
      if (!kSkipCreateColumns.contains(e.key) && !kRunningNumberFields.contains(e.key) && e.value != null) e.key: e.value,
  };
  if (userId != null && userId.isNotEmpty) copy['smownerid'] = int.tryParse(userId) ?? userId;
  final p = picklists;
  void reset(String k, String? v) {
    if (v != null) copy[k] = v;
  }

  switch (module) {
    case 'lead':
      reset('lead_status', pickFirstOption(p['lead_status'], 'New'));
      copy['lead_datetime'] = _ymdhm(t);
    case 'contact':
      reset('contact_status', pickFirstOption(p['contact_status'], 'Customer'));
      copy['contact_datetime'] = _ymdhm(t);
    case 'account':
      reset('account_status', pickFirstOption(p['account_status'], 'Customer'));
      copy['account_datetime'] = _ymdhm(t);
    case 'case':
      reset('case_status', pickFirstOption(p['case_status'], 'เปิดเคส'));
      for (final k in ['open_datetime', 'plan_datetime', 'due_datetime']) {
        copy[k] = _ymdhm(t);
      }
      for (final k in [
        'execution_datetime', 'hold_datetime', 'closed_datetime', 'cancle_datetime', 'acknowledge_datetime',
        'evaluation_score', 'evaluation_datetime', 'case_description_closed', 'case_solution_answer', 'case_description_cancel',
      ]) {
        copy.remove(k);
      }
    case 'activity':
      reset('status', pickFirstOption(p['status'], 'Planned'));
      for (final k in ['date_start', 'date_end']) {
        final d = DateTime.tryParse('${copy[k] ?? ''}'.replaceFirst(' ', 'T'));
        if (d != null) copy[k] = _ymdhm(DateTime(d.year, d.month, d.day + 1, d.hour, d.minute));
      }
      for (final k in ['checkindate', 'checkoutdate', 'checkin_lat', 'checkin_lng', 'location_chkout', 'imagename', 'photos']) {
        copy.remove(k);
      }
    case 'deal':
      reset('deal_stage', pickFirstOption(p['deal_stage'], null));
      copy.remove('closed_at');
      copy.remove('closed_reason');
    default:
      break;
  }
  return copy;
}
