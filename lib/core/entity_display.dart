import 'html_display.dart';
import 'status_labels.dart';
import 'thai_time.dart';

String _plain(dynamic v) {
  if (v == null) return '';
  final s = stripHtmlPreview(v.toString(), maxLen: 240).trim();
  if (s.isEmpty || s == '-' || s == 'null') return '';
  return s;
}

String? _firstPlain(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final s = _plain(row[k]);
    if (s.isNotEmpty) return s;
  }
  return null;
}

String _joinName(Map<String, dynamic> row, List<List<String>> pairs) {
  for (final pair in pairs) {
    final parts = [for (final k in pair) _plain(row[k])].where((e) => e.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
  }
  return '';
}

List<String> _titleKeysFor(String? module) {
  switch (module) {
    case 'product':
      return const ['product_name_th', 'product_name_en', 'product_no', 'productname', 'product_name', 'name'];
    case 'service':
      return const ['service_name_th', 'service_name_en', 'service_no', 'servicename', 'service_name', 'name'];
    case 'job':
      return const ['job_name', 'job_no', 'subject', 'name'];
    case 'inspection':
      return const ['inspection_name', 'inspection_no', 'name'];
    case 'service_location':
      return const ['location_name', 'location_no', 'name'];
    case 'asset':
      return const ['asset_name', 'serial_no', 'asset_no', 'name'];
    case 'skill':
      return const ['skill_name', 'skill_code', 'name'];
    case 'case':
      return const ['case_name', 'casename', 'case_no', 'customer_name', 'subject', 'name'];
    case 'quotation':
      return const ['quotation_no', 'customer_name', 'title_th', 'title_en', 'subject', 'name'];
    case 'service_contract':
      return const ['contract_name', 'contract_no', 'name', 'subject'];
    case 'deal':
      return const ['deal_name', 'deal_no', 'dealname', 'name'];
    case 'account':
      return const ['account_name', 'accountname', 'account_no', 'name', 'contact_name_1st'];
    case 'contact':
      return const ['contact_name', 'email_1st', 'email1', 'name'];
    case 'lead':
      return const ['lead_name', 'company_name', 'name', 'subject'];
    default:
      return const [
        'subject',
        'title',
        'name',
        'accountname',
        'account_name',
        'dealname',
        'deal_name',
        'lastname',
        'last_name',
        'firstname',
        'first_name',
        'quotation_no',
        'casename',
        'case_name',
        'case_no',
        'customer_name',
        'job_name',
        'job_no',
        'item_no',
        'product_name_th',
        'product_name_en',
        'product_no',
        'productname',
        'product_name',
        'service_name_th',
        'service_name_en',
        'service_no',
        'servicename',
        'service_name',
        'inspection_name',
        'inspection_no',
        'contract_no',
        'contract_name',
        'location_name',
        'location_no',
        'asset_name',
        'serial_no',
        'asset_no',
        'skill_name',
        'skill_code',
      ];
  }
}

String entityTitle(Map<String, dynamic> row, {String? module}) {
  switch (module) {
    case 'quotation':
      final no = _plain(row['quotation_no']);
      final name = _firstPlain(row, const ['customer_name', 'title_th', 'title_en', 'subject', 'name']);
      if (no.isNotEmpty && name != null) return '$no · $name';
      if (no.isNotEmpty) return no;
      if (name != null) return name;
      break;
    case 'deal':
      final no = _plain(row['deal_no']);
      final name = _firstPlain(row, const ['deal_name', 'dealname', 'name']);
      if (no.isNotEmpty && name != null) return '$no · $name';
      if (name != null) return name;
      if (no.isNotEmpty) return no;
      break;
    case 'contact':
      final full = _joinName(row, const [
        ['contact_firstname', 'contact_lastname'],
        ['firstname', 'lastname'],
        ['first_name', 'last_name'],
      ]);
      if (full.isNotEmpty) return full;
      break;
    case 'lead':
      final named = _firstPlain(row, const ['lead_name']);
      if (named != null) return named;
      final full = _joinName(row, const [
        ['lead_firstname', 'lead_lastname'],
        ['firstname', 'lastname'],
        ['first_name', 'last_name'],
      ]);
      if (full.isNotEmpty) return full;
      break;
    case 'account':
      final name = _firstPlain(row, const ['account_name', 'accountname', 'name', 'account_no']);
      if (name != null) return name;
      break;
  }
  final keys = _titleKeysFor(module);
  final hit = _firstPlain(row, keys);
  if (hit != null) return hit;
  final combined = _joinName(row, const [
    ['firstname', 'lastname'],
    ['first_name', 'last_name'],
  ]);
  if (combined.isNotEmpty) return combined;
  // Unnamed record → its running number (e.g. L26110700001) before a raw id.
  final no = module == null ? '' : _plain(row['${module}_no']);
  if (no.isNotEmpty) return no;
  if (module != null && row['id'] != null) return '$module #${row['id']}';
  return row['id'] != null ? 'ID ${row['id']}' : 'รายการ';
}

String? entitySubtitle(Map<String, dynamic> row, {String? module}) {
  switch (module) {
    case 'quotation':
      final parts = [
        statusValueLabel(_plain(row['quotation_status'] ?? row['status']), module: 'quotation'),
        _plain(row['grand_total']),
      ].where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join(' · ');
      break;
    case 'deal':
      final parts = [
        _plain(row['amount']),
        _plain(row['expected_close_date']).length >= 10
            ? _plain(row['expected_close_date']).substring(0, 10)
            : _plain(row['expected_close_date']),
      ].where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join(' · ');
      break;
    case 'contact':
      final a = _firstPlain(row, const ['account_name_1st', 'account_name']);
      if (a != null) return a;
      break;
    case 'account':
      final a = _firstPlain(row, const ['website', 'email1', 'email', 'account_email']);
      if (a != null) return a;
      break;
  }
  final parts = <String>[];
  for (final k in ['email', 'email1', 'status', 'phone', 'mobile', 'phone_mobile', 'company', 'accountname']) {
    // Stored status words read in the current language ("Planned" → "วางแผน").
    final v = k == 'status' ? statusValueLabel(_plain(row[k]), module: module) : _plain(row[k]);
    if (v.isNotEmpty) parts.add(v);
  }
  if (parts.isEmpty) return null;
  return parts.take(3).join(' · ');
}

String strId(dynamic id) => id == null ? '' : id.toString();

String lookupRecordId(dynamic value) {
  if (value == null) return '';
  if (value is Map) {
    final nested = value['id'] ?? value['value'] ?? value['record_id'];
    return strId(nested);
  }
  return strId(value);
}

String pickRecordId(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final v = data[key];
    if (v is Map) {
      final id = strId(v['id'] ?? v['value']);
      if (id.isNotEmpty) return id;
    }
    final id = strId(v);
    if (id.isNotEmpty && id != 'null') return id;
  }
  return strId(data['id']);
}

String entityInitials(String title) {
  final parts = title
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.first;
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String? entityStatus(Map<String, dynamic> row) {
  for (final k in [
    'status',
    'leadstatus',
    'deal_stage',
    'sales_stage',
    'case_status',
    'quotation_status',
    'job_status',
    'inspection_status',
  ]) {
    final v = _plain(row[k]);
    if (v.isNotEmpty) return v;
  }
  return null;
}

String? entityWhen(Map<String, dynamic> row) {
  for (final k in [
    'modifiedtime',
    'updated_at',
    'createdtime',
    'created_at',
    'date_start',
    'closingdate',
  ]) {
    final v = row[k]?.toString();
    if (v == null || v.isEmpty) continue;
    final local = parseThaiField(v, k);
    if (local == null) return v.length > 16 ? v.substring(0, 16) : v;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return null;
}

String? entityPeopleLine(Map<String, dynamic> row) {
  final parts = <String>[];
  for (final k in ['assigned_user_name', 'email', 'email1', 'phone', 'mobile']) {
    final v = _plain(row[k]);
    if (v.isNotEmpty) parts.add(v);
  }
  if (parts.isEmpty) return entitySubtitle(row);
  return parts.take(2).join(' · ');
}

String lookupFallbackLabel(String module, String id) {
  final title = _plain(module);
  if (id.isEmpty) return title.isEmpty ? 'รายการ' : title;
  return '${title.isEmpty ? 'รายการ' : title} #$id';
}

/// Display name for a NEXTX user row (`/api/users`, `/api/mail/users`, task assignee…).
String userDisplayName(Map<String, dynamic> u) {
  for (final key in const ['display', 'name', 'full_name', 'display_name']) {
    final v = u[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final joined = [u['first_name'], u['last_name']]
      .map((e) => e?.toString().trim() ?? '')
      .where((e) => e.isNotEmpty)
      .join(' ');
  if (joined.isNotEmpty) return joined;
  for (final key in const ['email1', 'email', 'user_name']) {
    final v = u[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final id = u['id']?.toString() ?? '';
  return id.isEmpty ? 'ผู้ใช้' : 'User #$id';
}

/// Email for a NEXTX user row, if any.
String? userEmail(Map<String, dynamic> u) {
  final v = (u['email1'] ?? u['email'])?.toString().trim() ?? '';
  return v.isEmpty ? null : v;
}
