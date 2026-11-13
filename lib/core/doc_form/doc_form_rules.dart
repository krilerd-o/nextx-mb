/// Rules shared by the quotation / job step forms: which fields each step
/// owns, where business-defined (custom) fields go, the web's autofill
/// rules when a customer is picked, duplicate / revise copies and the
/// document template choice. Pure Dart — unit tested without widgets.
library;

import 'dart:convert';

import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/field_validate.dart';
import '../entity_form_rules.dart';
import 'quotation_math.dart';

/// Modules that open the step forms instead of the generic entity form.
const Set<String> kStepFormModules = {'quotation', 'job'};

enum DocFormMode { create, edit, duplicate, revise }

DocFormMode docFormModeOf(String? s) => switch (s) {
      'edit' => DocFormMode.edit,
      'duplicate' => DocFormMode.duplicate,
      'revise' => DocFormMode.revise,
      _ => DocFormMode.create,
    };

String _s(Object? v) => v == null ? '' : '$v'.trim();
bool _blank(Object? v) {
  final u = unwrapFieldValue(v);
  if (u == null) return true;
  if (u is String) return u.trim().isEmpty || u == 'null';
  if (u is List) return u.isEmpty;
  return false;
}

String _two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime? parseYmd(Object? v) {
  final s = _s(unwrapFieldValue(v));
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

String addDaysYmd(Object? base, int days) {
  final d = parseYmd(base) ?? DateTime.now();
  return ymd(DateTime(d.year, d.month, d.day + days));
}

// ───────────────────────────────────────────────────────── field placement

/// Steps of each form (index = position).
const List<({String key, String title})> kQuotationSteps = [
  (key: 'customer', title: 'ลูกค้า'),
  (key: 'lines', title: 'รายการสินค้า'),
  (key: 'terms', title: 'เงื่อนไข'),
  (key: 'review', title: 'ตรวจและสร้าง'),
];

const List<({String key, String title})> kJobSteps = [
  (key: 'what', title: 'งานอะไร'),
  (key: 'customer', title: 'ลูกค้าและสถานที่'),
  (key: 'when', title: 'เมื่อไร / ใคร'),
  (key: 'details', title: 'รายละเอียดและตรวจสร้าง'),
];

/// Fields the step screens draw themselves (not through the generic field list).
const Map<String, Map<String, int>> kCoreFieldStep = {
  'quotation': {
    'related_account_id': 0, 'related_contact_id': 0, 'related_lead_id': 0, 'customer_name': 0, 'customer_address': 0,
    'customer_taxid': 0, 'customer_phone': 0, 'customer_mobile': 0, 'customer_email': 0, 'contact_name': 0, 'title_th': 0,
    'smownerid': 0,
    'header_discount_type': 1, 'header_discount_value': 1,
    'quote_date': 2, 'valid_until': 2, 'validity_days': 2, 'delivery_date': 2, 'tax_type': 2, 'tax_rate': 2,
    'template_key': 2, 'template_id': 2, 'terms_conditions': 2, 'quote_termcondition': 2,
  },
  'job': {
    'job_type': 0, 'job_name': 0, 'job_priority': 0, 'related_case_id': 0, 'related_contract_id': 0, 'related_quotation_id': 0,
    'related_account_id': 1, 'related_contact_id': 1, 'customer_name': 1, 'customer_contact_name': 1, 'customer_mobile': 1,
    'customer_email': 1, 'customer_department': 1, 'related_location_id': 1, 'location_name_snapshot': 1, 'site_address_snapshot': 1,
    'related_asset_id': 1,
    'plan_start': 2, 'plan_end': 2, 'due_datetime': 2, 'smownerid': 2, 'engineer_user_id': 2, 'engineer_name': 2, 'engineer_phone': 2,
    'description': 3, 'template_key': 3, 'job_template_id': 3,
  },
};

/// Never asked in the form: running numbers, workflow status, approval,
/// outcome reasons, server-computed totals, signatures, check-in times.
const Map<String, Set<String>> kNotAskedFields = {
  'quotation': {
    'quotation_no', 'quotation_status', 'offer_status', 'subtotal', 'discount_total', 'tax_total', 'grand_total', 'po_reference',
    'document_options', 'header_json', 'related_deal_id', 'business_id', 'deleted', 'crmid', 'sample_text', 'qline_remark_before',
    'qline_remark_after', 'notes', 'terms', 'description', 'currency', 'closed_reason', 'template_extra',
  },
  'job': {
    'job_no', 'job_status', 'actual_start', 'actual_end', 'accepted_at', 'cancelled_at', 'cancel_reason', 'close_note', 'accept_alert_at',
    'customer_signature', 'customer_signed_at', 'customer_signed_by_name', 'technician_signature', 'technician_signed_at',
    'technician_signed_by_name', 'evidence_photos', 'customer_ack_status', 'header_json', 'cycle_index', 'cycle_kind', 'source',
    'related_activity_id', 'business_id', 'deleted', 'crmid', 'acknowledgement_flags', 'job_process',
    // Template-2 tick lists (JSON) are ticked on the service report itself, not typed here.
    'work_types', 'work_type_other', 'system_types', 'system_other', 'service_results', 'system_status',
  },
};

final RegExp _systemRe = RegExp(
    r'^(outcome_|approval_|approver_|public_token|revision_|cancelled_|closed_|win_|lost_|loss_|customer_(viewed|view_count|accepted|signer|signature|signed))');

bool isNotAskedField(String module, String name) {
  if (kSkipCreateColumns.contains(name) || kRunningNumberFields.contains(name)) return true;
  if ((kNotAskedFields[module] ?? const {}).contains(name)) return true;
  return _systemRe.hasMatch(name);
}

/// The web's form sections (crmEntityFormLayout.js SECTION_FIELDS) → step.
const Map<String, Map<String, int>> _sectionStep = {
  'quotation': {'identity': 0, 'customer': 0, 'assignment': 0, 'commercial': 1, 'lines': 1, 'dates': 2, 'terms': 2, 'channel': 2},
  'job': {'statusRating': 0, 'identity': 0, 'links': 0, 'customer': 1, 'schedule': 2, 'assignment': 2, 'deliverable': 3, 'signatures': 3},
};

const Map<String, Map<String, String>> _webSectionOf = {
  'quotation': {
    'title_en': 'identity', 'quotation_ref': 'identity', 'currency': 'dates', 'channel': 'channel', 'branch_label': 'channel',
    'notes': 'terms', 'terms': 'terms', 'payment_details': 'terms', 'delivery_terms': 'terms', 'warranty_months': 'terms',
    'include_installation': 'terms', 'authorized_user_id': 'assignment', 'assign_to': 'assignment', 'project_name': 'identity',
  },
  'job': {
    'job_code': 'identity', 'job_category': 'statusRating', 'job_category_other': 'statusRating', 'deliverable_template': 'deliverable',
    'assign_group': 'deliverable', 'job_process_other': 'deliverable', 'problem_found': 'deliverable', 'work_performed': 'deliverable',
    'customer_suggestion': 'deliverable', 'additional_remark': 'deliverable', 'work_types': 'deliverable', 'work_type_other': 'deliverable',
    'system_types': 'deliverable', 'system_other': 'deliverable', 'service_results': 'deliverable', 'system_status': 'deliverable',
    'in_warranty': 'signatures', 'acknowledgement_other': 'signatures', 'acknowledgement_note': 'signatures',
    'warranty_cycle_index': 'signatures', 'contract_cycle_index': 'signatures', 'contract_po_no': 'customer',
    'salesperson_user_id': 'assignment', 'salesperson_name': 'assignment', 'salesperson_phone': 'assignment',
  },
};

/// Step a business section / block name belongs to (Thai or English words).
int? _stepOfSectionName(String module, String section) {
  final s = section.toLowerCase();
  if (s.isEmpty || s == 'main' || s == 'default' || s == 'general' || s == 'custom') return null;
  final customer = RegExp(r'customer|contact|address|client|site|location|ลูกค้า|ผู้ติดต่อ|ที่อยู่|สถานที่|หน้างาน');
  final lines = RegExp(r'line|item|product|price|pricing|commercial|discount|รายการ|สินค้า|ราคา|ส่วนลด');
  final when = RegExp(r'schedule|plan|date|time|assign|owner|team|technician|กำหนด|วันที่|เวลา|นัด|มอบหมาย|ช่าง|ทีม');
  final terms = RegExp(r'term|condition|payment|delivery|warranty|note|remark|เงื่อนไข|ชำระ|ส่งของ|รับประกัน|หมายเหตุ');
  final what = RegExp(r'identity|type|status|work|job|งาน|ประเภท');
  if (module == 'quotation') {
    if (customer.hasMatch(s)) return 0;
    if (lines.hasMatch(s)) return 1;
    if (terms.hasMatch(s) || when.hasMatch(s)) return 2;
    return null;
  }
  if (customer.hasMatch(s)) return 1;
  if (when.hasMatch(s)) return 2;
  if (what.hasMatch(s)) return 0;
  return null;
}

/// The business section of a field, if it is not the default one.
String? fieldSectionLabel(Map<String, dynamic> f) {
  final sec = _s(f['section']);
  if (sec.isNotEmpty && sec.toLowerCase() != 'main') return sec;
  return fieldBlockLabel(f);
}

/// Where a schema field that the step screen does not draw itself goes:
/// known web sections first, then the business section / block name, then
/// the field name; anything else lands in "ข้อมูลเพิ่มเติม" of the default
/// step (quotation: เงื่อนไข · job: รายละเอียด) — never dropped.
({int step, String group}) placeExtraField(String module, Map<String, dynamic> f) {
  final name = fieldName(f);
  final sec = fieldSectionLabel(f);
  final group = sec ?? 'ข้อมูลเพิ่มเติม';
  final web = _webSectionOf[module]?[name];
  if (web != null) {
    final st = _sectionStep[module]?[web];
    if (st != null) return (step: st, group: group);
  }
  if (sec != null) {
    final st = _stepOfSectionName(module, sec);
    if (st != null) return (step: st, group: group);
  }
  final c = name.toLowerCase();
  final addr = RegExp(r'(^|_)address|province|district|postal|zip|locationmap|^customer_|^contact_|^client_');
  final contact = RegExp(r'email|phone|mobile|fax');
  if (module == 'quotation') {
    if (addr.hasMatch(c) || contact.hasMatch(c)) return (step: 0, group: group);
    if (RegExp(r'discount|price|amount').hasMatch(c)) return (step: 1, group: group);
    return (step: 2, group: group);
  }
  if (addr.hasMatch(c) || contact.hasMatch(c)) return (step: 1, group: group);
  final ui = resolveFieldUiType(f);
  if (ui == FieldUiType.dateTime || ui == FieldUiType.date || ui == FieldUiType.time || RegExp(r'_(date|datetime|time)$').hasMatch(c)) {
    return (step: 2, group: group);
  }
  if (ui == FieldUiType.owner || ui == FieldUiType.picklistUser || ui == FieldUiType.assignTo || ui == FieldUiType.multiPicklistUser) {
    return (step: 2, group: group);
  }
  return (step: 3, group: group);
}

bool fieldIsHiddenForUser(Map<String, dynamic> f) {
  final access = _s(f['access']).toLowerCase();
  return access == 'hidden' || _s(f['presence']) == '0';
}

/// Schema split for a step form: the schema entry of each core field (to
/// honour required / readonly / hidden set by the business) and the other
/// editable fields with their step + group.
class DocFormSchema {
  DocFormSchema({required this.module, required List<Map<String, dynamic>> fields, Map<String, List<Map<String, dynamic>>>? picklists})
      : picklists = picklists ?? const {} {
    final core = kCoreFieldStep[module] ?? const {};
    for (final f in fields) {
      final name = fieldName(f);
      if (name.isEmpty || name == 'id') continue;
      all[name] = f;
      if (core.containsKey(name)) continue;
      if (isNotAskedField(module, name) || f['type'] == 'Counter') continue;
      // Same rule as the generic form: read-only / hidden fields are not in the form.
      if (fieldIsReadonly(f) || fieldIsHiddenForUser(f)) continue;
      final p = placeExtraField(module, f);
      final field = moduleRequiresField(module, name) ? {...f, 'required': true} : f;
      extra.add((field: field, step: p.step, group: p.group));
    }
  }

  final String module;
  final Map<String, List<Map<String, dynamic>>> picklists;
  final Map<String, Map<String, dynamic>> all = {};
  final List<({Map<String, dynamic> field, int step, String group})> extra = [];

  /// A core field the user may not see (hidden by field permission).
  bool hides(String name) {
    final f = all[name];
    return f != null && fieldIsHiddenForUser(f);
  }

  /// A core field the user sees but may not change.
  bool locks(String name) {
    final f = all[name];
    return f != null && !fieldIsHiddenForUser(f) && fieldIsReadonly(f);
  }

  bool editable(String name) => !hides(name) && !locks(name);

  /// Business-required core field (schema flag or the web's own rule).
  bool requires(String name) {
    final f = all[name];
    return moduleRequiresField(module, name) || (f != null && fieldIsRequired(f));
  }

  String labelOf(String name, String fallback) {
    final f = all[name];
    final l = f == null ? '' : fieldLabel(f);
    return l.isEmpty || l == name ? fallback : l;
  }

  List<Map<String, dynamic>> extraFor(int step, {String? group}) => [
        for (final e in extra)
          if (e.step == step && (group == null || e.group == group)) e.field,
      ];

  List<String> groupsFor(int step) {
    final out = <String>[];
    for (final e in extra) {
      if (e.step == step && !out.contains(e.group)) out.add(e.group);
    }
    return out;
  }

  bool has(String name) => all.containsKey(name);
}

/// Missing / invalid extra fields per step (same checks as the generic form).
Map<String, String> validateExtraFields(List<Map<String, dynamic>> fields, Map<String, dynamic> values) {
  final out = <String, String>{};
  for (final f in fields) {
    final name = fieldName(f);
    if (name.isEmpty || fieldIsReadonly(f)) continue;
    final err = validateFieldValue(resolveFieldUiType(f), unwrapFieldValue(values[name]), required: fieldIsRequired(f));
    if (err != null) out[name] = err;
  }
  return out;
}

bool isBlankValue(Object? v) => _blank(v);

// ───────────────────────────────────────────────────── quotation autofill

String _contactName(Map<String, dynamic> r, String prefix) {
  final n = _s(r['${prefix}_name']);
  if (n.isNotEmpty) return n;
  return [_s(r['${prefix}_firstname']), _s(r['${prefix}_lastname'])].where((x) => x.isNotEmpty).join(' ');
}

String _joinAddress(Map<String, dynamic> r) =>
    [r['address_line1'], r['address_district'], r['address_province']].map(_s).where((x) => x.isNotEmpty).join(' ');

/// Web `accountPatch` (QuotationFormPage.jsx): account → customer name / tax
/// id / address / phone; e-mail only when still empty.
Map<String, dynamic> quotationAccountPatch(Map<String, dynamic> row, Map<String, dynamic> prev) {
  String or(String v, String key) => v.isNotEmpty ? v : _s(prev[key]);
  final email = _s(prev['customer_email']).isNotEmpty ? _s(prev['customer_email']) : _s(row['email_1st']);
  return {
    'related_account_id': row['id'],
    'customer_name': or(_s(row['account_name']), 'customer_name'),
    'customer_taxid': or(_s(row['account_taxid']), 'customer_taxid'),
    'customer_address': or(_joinAddress(row), 'customer_address'),
    'customer_phone': or(_s(row['mobile_1st']).isNotEmpty ? _s(row['mobile_1st']) : _s(row['phone']), 'customer_phone'),
    'customer_email': email,
  };
}

/// Web contact pick: contact name / mobile / e-mail (the account is fetched
/// separately when none is set yet: [contactAccountId]).
Map<String, dynamic> quotationContactPatch(Map<String, dynamic> row, Map<String, dynamic> prev) {
  final name = _contactName(row, 'contact');
  return {
    'related_contact_id': row['id'],
    'contact_name': name.isNotEmpty ? name : _s(prev['contact_name']),
    'customer_mobile': _s(row['mobile_1st']).isNotEmpty ? _s(row['mobile_1st']) : _s(prev['customer_mobile']),
    'customer_email': _s(row['email_1st']).isNotEmpty ? _s(row['email_1st']) : _s(prev['customer_email']),
  };
}

/// The contact's own account (web: fills the customer when none is picked yet).
String? contactAccountId(Map<String, dynamic> row) {
  for (final k in const ['account_id', 'related_account_id', 'accountid']) {
    final v = _s(row[k]);
    if (v.isNotEmpty && v != '0' && v != 'null') return v;
  }
  return null;
}

/// A lead as the customer (not on the web picker: same columns, lead names).
Map<String, dynamic> quotationLeadPatch(Map<String, dynamic> row, Map<String, dynamic> prev) {
  final person = _contactName(row, 'lead');
  final company = _s(row['company_name']);
  String pick(List<String> keys) {
    for (final k in keys) {
      final v = _s(row[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  return {
    'related_lead_id': row['id'],
    'customer_name': company.isNotEmpty ? company : (person.isNotEmpty ? person : _s(prev['customer_name'])),
    'contact_name': person.isNotEmpty ? person : _s(prev['contact_name']),
    'customer_taxid': pick(const ['company_taxid', 'lead_taxid']).isNotEmpty ? pick(const ['company_taxid', 'lead_taxid']) : _s(prev['customer_taxid']),
    'customer_address': _joinAddress(row).isNotEmpty ? _joinAddress(row) : _s(prev['customer_address']),
    'customer_mobile': _s(row['mobile_1st']).isNotEmpty ? _s(row['mobile_1st']) : _s(prev['customer_mobile']),
    'customer_email': _s(row['email_1st']).isNotEmpty ? _s(row['email_1st']) : _s(prev['customer_email']),
  };
}

/// Web "ล้างลูกค้า".
const Map<String, dynamic> kQuotationClearCustomer = {
  'related_account_id': null, 'customer_name': '', 'customer_address': '', 'customer_taxid': '', 'customer_phone': '',
  'related_contact_id': null, 'contact_name': '', 'related_lead_id': null,
};

// ─────────────────────────────────────────────────────────── catalog lines

String _plain(Object? html) => _s(html)
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .trim();

/// Web `mapProductToLine` / `mapServiceToLine` + `catalogLinePricing`: with a
/// catalog discount and a list price the line carries the discount.
Map<String, dynamic> lineFromCatalog(Map<String, dynamic> row, String module, {Object? taxRate, bool th = true}) {
  final p = module == 'service' ? 'service' : 'product';
  final nameTh = _s(row['${p}_name_th']).isNotEmpty ? _s(row['${p}_name_th']) : _s(row['${p}_name_en']);
  final nameEn = _s(row['${p}_name_en']).isNotEmpty ? _s(row['${p}_name_en']) : nameTh;
  var name = th ? nameTh : nameEn;
  if (name.isEmpty) name = _s(row['${p}_name']).isNotEmpty ? _s(row['${p}_name']) : _s(row['name']);
  final dTh = row['${p}_description_th'], dEn = row['${p}_description_en'];
  final desc = _plain((th ? (_s(dTh).isNotEmpty ? dTh : dEn) : (_s(dEn).isNotEmpty ? dEn : dTh)) ?? row['description']);
  final initial = qNum(row['${p}_initial_price']);
  final dRaw = '${row['${p}_discount_type'] ?? ''}'.toLowerCase();
  final dType = dRaw == 'percent' || dRaw == '%' || dRaw == 'pct' ? 'percent' : 'amount';
  final dVal = qNum(row['${p}_discount']);
  Map<String, dynamic> pricing;
  if (dVal > 0 && initial > 0) {
    pricing = dType == 'percent'
        ? {'unit_price': initial, 'discount_type': 'percent', 'discount_pct': dVal.clamp(0, 100), 'discount_amount': 0}
        : {'unit_price': initial, 'discount_type': 'amount', 'discount_pct': 0, 'discount_amount': dVal < initial ? dVal : initial};
  } else {
    final sell = row['${p}_selling_price'] ?? row['${p}_initial_price'];
    pricing = {'unit_price': qNum(sell), 'discount_type': 'amount', 'discount_pct': 0, 'discount_amount': 0};
  }
  return {
    'line_type': p,
    'product_id': p == 'product' ? row['id'] : null,
    'service_id': p == 'service' ? row['id'] : null,
    'description': name,
    'line_comment': desc,
    'quantity': 1,
    'unit': _s(row['${p}_unit']),
    ...pricing,
    'tax_pct': resolveTaxRate(taxRate),
  };
}

Map<String, dynamic> blankQuotationLine({Object? taxRate}) => {
      'line_type': 'text',
      'product_id': null,
      'service_id': null,
      'description': '',
      'line_comment': '',
      'quantity': 1,
      'unit': '',
      'unit_price': 0,
      'discount_type': 'amount',
      'discount_amount': 0,
      'discount_pct': 0,
      'tax_pct': resolveTaxRate(taxRate),
    };

const _lineKeys = [
  'line_type', 'product_id', 'service_id', 'description', 'line_comment', 'quantity', 'unit', 'unit_price', 'discount_type',
  'discount_pct', 'discount_amount', 'tax_pct', 'item_label', 'model',
];

/// Lines for `POST /quotation/save` / `/revise`: blank rows dropped,
/// renumbered, only the columns the server stores (amounts are computed there).
List<Map<String, dynamic>> quotationLinesPayload(List<Map<String, dynamic>> lines) {
  final out = <Map<String, dynamic>>[];
  for (final l in lines) {
    if (isBlankQuotationLine(l)) continue;
    out.add({
      'line_no': out.length + 1,
      for (final k in _lineKeys)
        if (l.containsKey(k)) k: k == 'quantity' || k == 'unit_price' || k == 'discount_pct' || k == 'discount_amount' || k == 'tax_pct' ? qNum(l[k]) : l[k],
    });
  }
  return out;
}

/// Copy of the source lines for a duplicate / revise (no ids).
List<Map<String, dynamic>> copyQuotationLines(List<Map<String, dynamic>> src) => [
      for (final l in src)
        {
          for (final e in l.entries)
            if (!const {'id', 'quotation_id', 'createdtime', 'modifiedtime', 'created_at', 'updated_at', 'line_amount'}.contains(e.key)) e.key: e.value,
          // Rows saved before discount types existed: keep their meaning explicit.
          'discount_type': lineDiscountType(l),
          if (!l.containsKey('quantity') && l.containsKey('qty')) 'quantity': l['qty'],
          if (!l.containsKey('unit_price') && l.containsKey('price')) 'unit_price': l['price'],
        },
    ];

/// Revise: what changed per new line compared with the previous revision.
enum RevisionLineChange { same, changed, added }

String _lineSig(Map<String, dynamic> l) => [
      _s(l['description']),
      _s(l['product_id']),
      _s(l['service_id']),
      qNum(l['quantity']),
      qNum(l['unit_price']),
      lineDiscountType(l),
      qNum(l['discount_pct']),
      qNum(l['discount_amount']),
      _s(l['unit']),
      _s(l['line_comment']),
    ].join('|');

String _lineKey(Map<String, dynamic> l) {
  final p = _s(l['product_id']), sv = _s(l['service_id']);
  if (p.isNotEmpty) return 'p:$p';
  if (sv.isNotEmpty) return 's:$sv';
  return 't:${_s(l['description']).toLowerCase()}';
}

/// Per current line: same / changed / added; [removed] = previous lines gone.
({List<RevisionLineChange> changes, List<Map<String, dynamic>> removed}) diffRevisionLines(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> current,
) {
  final pool = [...previous];
  final changes = <RevisionLineChange>[];
  for (final l in current) {
    final exact = pool.indexWhere((p) => _lineSig(p) == _lineSig(l));
    if (exact >= 0) {
      pool.removeAt(exact);
      changes.add(RevisionLineChange.same);
      continue;
    }
    final byKey = pool.indexWhere((p) => _lineKey(p) == _lineKey(l));
    if (byKey >= 0) {
      pool.removeAt(byKey);
      changes.add(RevisionLineChange.changed);
      continue;
    }
    changes.add(RevisionLineChange.added);
  }
  return (changes: changes, removed: pool);
}

/// `{n}` of the next revision (`-R{n}`).
int nextRevisionNo(Map<String, dynamic> src, [List<Map<String, dynamic>> chain = const []]) {
  var n = qNum(src['revision_no']).toInt();
  for (final r in chain) {
    final v = qNum(r['revision_no']).toInt();
    if (v > n) n = v;
  }
  return n + 1;
}

String revisionNumberPreview(Map<String, dynamic> src, int n) {
  final root = _s(src['quotation_no']).replaceAll(RegExp(r'-R\d+$', caseSensitive: false), '');
  return root.isEmpty ? 'R$n' : '$root-R$n';
}

// ─────────────────────────────────────────────── document template (web)

String normLayout(Object? v) => _s(v).toLowerCase() == 'template2' ? 'template2' : 'template1';

List<Map<String, dynamic>> templatesOfLayout(List<Map<String, dynamic>> templates, String layout) =>
    [for (final t in templates) if (normLayout(t['layout_key']) == normLayout(layout)) t];

bool _isDefaultTpl(Map<String, dynamic> t) {
  final j = t['layout_json'];
  return j is Map && (j['is_default'] == true || '${j['is_default']}' == '1');
}

Object? defaultTemplateOfLayout(List<Map<String, dynamic>> templates, String layout, {bool firstAsFallback = false}) {
  final same = templatesOfLayout(templates, layout);
  final d = same.where(_isDefaultTpl).firstOrNull ?? (firstAsFallback ? same.firstOrNull : null);
  return d?['id'];
}

/// Port of the web's `resolveDocTemplate` (utils/docTemplateChoice.js):
/// create = the allowed default layout + its default template; edit = as
/// saved; duplicate / revise = the source's when still allowed, else default.
({String layout, Object? templateId, String? changed}) resolveDocTemplate({
  required DocFormMode mode,
  Object? layoutKey,
  Object? templateId,
  List<String>? allowedLayouts,
  Object? defaultLayout,
  List<Map<String, dynamic>> templates = const [],
  bool firstAsFallback = false,
}) {
  final allowed = (allowedLayouts == null || allowedLayouts.isEmpty ? const ['template1'] : allowedLayouts).map(normLayout).toList();
  final defLayout = _s(defaultLayout).isNotEmpty && allowed.contains(normLayout(defaultLayout)) ? normLayout(defaultLayout) : allowed.first;
  Object? pick(String l) => defaultTemplateOfLayout(templates, l, firstAsFallback: firstAsFallback);
  final id = _s(templateId).isEmpty ? null : templateId;
  if (mode == DocFormMode.edit) return (layout: normLayout(layoutKey), templateId: id, changed: null);
  if (mode == DocFormMode.duplicate || mode == DocFormMode.revise) {
    final src = normLayout(layoutKey);
    if (!allowed.contains(src)) return (layout: defLayout, templateId: pick(defLayout), changed: 'layout');
    if (id == null) return (layout: src, templateId: null, changed: null);
    final ok = templatesOfLayout(templates, src).any((t) => _s(t['id']) == _s(id));
    return ok ? (layout: src, templateId: id, changed: null) : (layout: src, templateId: pick(src), changed: 'template');
  }
  return (layout: defLayout, templateId: pick(defLayout), changed: null);
}

/// Layout choices in the form: the allowed ones (+ the saved one on edit).
List<String> layoutChoices(List<String>? allowed, Object? current, DocFormMode mode) {
  final a = (allowed == null || allowed.isEmpty ? const ['template1'] : allowed).map(normLayout).toSet().toList();
  final cur = normLayout(current);
  return mode == DocFormMode.edit && !a.contains(cur) ? [...a, cur] : a;
}

List<String> allowedLayoutsOf(Map<String, dynamic> ctx) {
  final l = ctx['layouts'];
  final raw = l is Map ? l['allowed_layouts'] : null;
  return raw is List ? [for (final x in raw) '$x'] : const ['template1'];
}

Object? defaultLayoutOf(Map<String, dynamic> ctx) {
  final l = ctx['layouts'];
  return l is Map ? l['default_layout'] : null;
}

List<Map<String, dynamic>> templatesOf(Map<String, dynamic> ctx) {
  final t = ctx['templates'];
  return t is List ? [for (final x in t) if (x is Map) Map<String, dynamic>.from(x)] : const [];
}

// ─────────────────────────────────────────── quotation new / copy defaults

/// `document_options` of a row (JSON string or map).
Map<String, dynamic> documentOptionsOf(Object? raw) {
  Object? v = raw;
  if (v is String && v.trim().isNotEmpty) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      v = null;
    }
  }
  return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}

/// Web defaults of a new quotation: today, owner, tax, the business's "new
/// quotation" settings (validity days, delivery / warranty / payment terms),
/// the allowed document layout + its default template.
Map<String, dynamic> quotationCreateValues({
  required String? userId,
  required DateTime today,
  Map<String, dynamic> ctx = const {},
  Map<String, List<Map<String, dynamic>>> picklists = const {},
  Map<String, dynamic> prefill = const {},
}) {
  final v = <String, dynamic>{
    ...createDefaults('quotation', userId: userId, picklists: picklists, now: today),
    'header_discount_value': 0,
    ...prefill,
  };
  v.remove('quotation_status');
  final nd = ctx['new_defaults'] is Map ? Map<String, dynamic>.from(ctx['new_defaults']) : const <String, dynamic>{};
  void setIfBlank(String k, Object? val) {
    if (val == null) return;
    if (_blank(v[k])) v[k] = val;
  }

  setIfBlank('validity_days', nd['validity_days']);
  setIfBlank('delivery_terms', nd['delivery_terms']);
  setIfBlank('warranty_months', nd['warranty_months']);
  setIfBlank('payment_details', nd['payment_details']);
  if (nd['include_installation'] != null) setIfBlank('include_installation', nd['include_installation'] == true || '${nd['include_installation']}' == '1' ? 1 : 0);
  if (_s(nd['tax_type']).isNotEmpty && _blank(prefill['tax_type'])) v['tax_type'] = nd['tax_type'];
  if (nd['tax_rate'] != null && _blank(prefill['tax_rate'])) v['tax_rate'] = nd['tax_rate'];
  setIfBlank('quote_date', ymd(today));
  // Valid until: business validity days, else 30 days (the app's quick default).
  if (_blank(v['valid_until'])) {
    final days = qNum(v['validity_days']).toInt();
    v['valid_until'] = addDaysYmd(v['quote_date'], days > 0 ? days : 30);
  }
  final r = resolveDocTemplate(
    mode: DocFormMode.create,
    allowedLayouts: allowedLayoutsOf(ctx),
    defaultLayout: defaultLayoutOf(ctx),
    templates: templatesOf(ctx),
  );
  v['template_key'] = r.layout;
  v['template_id'] = r.templateId;
  final layouts = ctx['layouts'];
  v['document_options'] = {
    'pdf_th_color': true, 'pdf_th_bw': false, 'pdf_en_color': false, 'pdf_en_bw': false,
    'show_signature': true, 'show_phone': true, 'show_email': true, 'hide_text_template': false,
    'line_discount_mode': layouts is Map && layouts['line_discount_mode'] == 'per_line' ? 'per_line' : 'per_unit',
  };
  // Conditions of a new quotation = the business's default condition set, copied onto the document (web).
  final ct = ctx['condition_templates'];
  if (ct is List && ct.isNotEmpty) {
    final list = [for (final t in ct) if (t is Map) Map<String, dynamic>.from(t)];
    final tpl = list.where((t) => t['is_default'] == true).firstOrNull ?? list.firstOrNull;
    if (tpl != null) {
      (v['document_options'] as Map)['conditions'] = {
        'template_id': tpl['id'],
        'items': jsonDecode(jsonEncode(tpl['conditions'] ?? const [])),
        'payment': jsonDecode(jsonEncode(tpl['payment'] ?? const [])),
      };
    }
  }
  return v;
}

/// Sales text columns (web `hydrateSalesTextFields`): prefer the new columns,
/// fall back to the legacy notes / terms / description.
Map<String, dynamic> hydrateSalesText(Map<String, dynamic> row) {
  final out = {...row};
  if (_blank(out['sample_text'])) out['sample_text'] = out['notes'] ?? '';
  if (_blank(out['terms_conditions'])) out['terms_conditions'] = out['terms'] ?? '';
  if (_blank(out['quote_termcondition'])) out['quote_termcondition'] = out['description'] ?? '';
  return out;
}

/// Web dual write: the sales text columns also go to the legacy ones.
void dualWriteSalesText(Map<String, dynamic> payload) {
  const m = {'sample_text': 'notes', 'terms_conditions': 'terms', 'quote_termcondition': 'description'};
  m.forEach((k, legacy) {
    if (payload[k] != null) payload[legacy] = payload[k];
  });
}

const _qtCopyDrop = {
  'id', 'crmid', 'quotation_no', 'quotation_status', 'offer_status', 'approval_state', 'approval_level', 'approval_chain',
  'approver_1_user_id', 'approver_2_user_id', 'revision_of_id', 'revision_no', 'revision_note', 'outcome_result', 'outcome_reason',
  'outcome_note', 'outcome_at', 'outcome_by', 'outcome_source_module', 'outcome_source_id', 'po_reference', 'public_token',
  'public_token_at', 'createdtime', 'modifiedtime', 'created_at', 'updated_at', 'smcreatorid', 'modifiedby', 'deleted',
  'business_id', 'customer_viewed_at', 'customer_view_count', 'customer_accepted_at', 'customer_signer_name',
  'customer_signature_path', 'customer_signed_at', 'subtotal', 'discount_total', 'tax_total', 'grand_total', 'related_deal_id',
  'closed_reason', '_shared_permission',
};

/// ทำซ้ำ (web `?from=`): the source's customer + terms + lines; number,
/// status and approval cleared; owner = me; dated today; valid until counted
/// again from today; "(Copy)" title; template re-checked.
Map<String, dynamic> quotationDuplicateValues(
  Map<String, dynamic> src, {
  required String? userId,
  required DateTime today,
  Map<String, dynamic> ctx = const {},
}) {
  final v = <String, dynamic>{
    for (final e in hydrateSalesText(src).entries)
      if (!_qtCopyDrop.contains(e.key) && !e.key.startsWith('_')) e.key: e.value,
  };
  if (userId != null && userId.isNotEmpty) v['smownerid'] = int.tryParse(userId) ?? userId;
  final title = _s(v['title_th']);
  if (title.isNotEmpty) v['title_th'] = '$title (Copy)';
  v['quote_date'] = ymd(today);
  final days = qNum(v['validity_days']).toInt();
  v['valid_until'] = addDaysYmd(v['quote_date'], days > 0 ? days : 30);
  final r = resolveDocTemplate(
    mode: DocFormMode.duplicate,
    layoutKey: src['template_key'],
    templateId: src['template_id'],
    allowedLayouts: allowedLayoutsOf(ctx),
    defaultLayout: defaultLayoutOf(ctx),
    templates: templatesOf(ctx),
  );
  v['template_key'] = r.layout;
  v['template_id'] = r.templateId;
  v['document_options'] = documentOptionsOf(src['document_options']);
  return v;
}

/// Revise (web `?revise=`): the whole quotation as it is (title and owner
/// kept); the server assigns `-R{n}` and resets status / approval.
Map<String, dynamic> quotationReviseValues(Map<String, dynamic> src, {Map<String, dynamic> ctx = const {}}) {
  final v = <String, dynamic>{
    for (final e in hydrateSalesText(src).entries)
      if (!_qtCopyDrop.contains(e.key) && !e.key.startsWith('_')) e.key: e.value,
  };
  if (src['smownerid'] != null) v['smownerid'] = src['smownerid'];
  final r = resolveDocTemplate(
    mode: DocFormMode.revise,
    layoutKey: src['template_key'],
    templateId: src['template_id'],
    allowedLayouts: allowedLayoutsOf(ctx),
    defaultLayout: defaultLayoutOf(ctx),
    templates: templatesOf(ctx),
  );
  v['template_key'] = r.layout;
  v['template_id'] = r.templateId;
  v['document_options'] = documentOptionsOf(src['document_options']);
  return v;
}


// ─────────────────────────────────────────────────────────────── job rules

/// Web job account pick (`accountPatch` in JobFormPage.jsx).
Map<String, dynamic> jobAccountPatch(Map<String, dynamic> row, Map<String, dynamic> prev) => {
      'related_account_id': row['id'],
      'customer_name': _s(row['account_name']).isNotEmpty ? _s(row['account_name']) : _s(prev['customer_name']),
      'customer_mobile': _s(prev['customer_mobile']).isNotEmpty ? _s(prev['customer_mobile']) : _s(row['mobile_1st']),
      'customer_email': _s(prev['customer_email']).isNotEmpty ? _s(prev['customer_email']) : _s(row['email_1st']),
    };

/// Web job contact pick.
Map<String, dynamic> jobContactPatch(Map<String, dynamic> row, Map<String, dynamic> prev) {
  final name = _contactName(row, 'contact');
  String first(List<String> keys, String prevKey) {
    for (final k in keys) {
      final v = _s(row[k]);
      if (v.isNotEmpty) return v;
    }
    return _s(prev[prevKey]);
  }

  return {
    'related_contact_id': row['id'],
    'customer_contact_name': name.isNotEmpty ? name : _s(prev['customer_contact_name']),
    'customer_department': first(const ['con_department', 'department'], 'customer_department'),
    'customer_mobile': first(const ['mobile_1st', 'mobile'], 'customer_mobile'),
    'customer_email': first(const ['email_1st', 'email'], 'customer_email'),
  };
}

/// Customer address as one line (account or service location).
String siteAddressOf(Map<String, dynamic> row) =>
    [row['address_line1'], row['address_sub_district'], row['address_district'], row['address_province'], row['address_postal_code']]
        .map(_s)
        .where((x) => x.isNotEmpty)
        .join(' ');

/// Web service-location pick.
Map<String, dynamic> jobLocationPatch(Map<String, dynamic> row, Map<String, dynamic> prev) => {
      'related_location_id': row['id'],
      'location_name_snapshot': _s(row['location_name']).isNotEmpty ? _s(row['location_name']) : _s(prev['location_name_snapshot']),
      'site_address_snapshot': siteAddressOf(row).isNotEmpty ? siteAddressOf(row) : _s(prev['site_address_snapshot']),
    };

/// A new job created from a case / contract / quotation — the same values
/// the server's `createJobFrom*` (fieldServiceService.js) writes, so the user
/// only reviews and fills the rest.
Map<String, dynamic> jobPrefillFrom(String parentModule, Map<String, dynamic> p, {String? userId, String linesSummary = ''}) {
  final id = p['id'];
  switch (parentModule) {
    case 'case':
      return {
        'job_name': 'Request — ${_s(p['case_name']).isNotEmpty ? _s(p['case_name']) : (_s(p['case_no']).isNotEmpty ? _s(p['case_no']) : '$id')}',
        'job_type': 'request',
        'job_priority': _s(p['case_priority']).isNotEmpty ? p['case_priority'] : 'Normal',
        'source': 'case',
        'related_case_id': id,
        if (!_blank(p['related_account_id'])) 'related_account_id': p['related_account_id'],
        if (!_blank(p['related_contact_id'])) 'related_contact_id': p['related_contact_id'],
        'customer_name': _s(p['customer_name']).isNotEmpty ? p['customer_name'] : p['account_name'],
        if (!_blank(p['due_datetime'])) 'due_datetime': p['due_datetime'],
        'deliverable_template': 'request_report',
        if (!_blank(p['smownerid'])) 'smownerid': p['smownerid'],
      };
    case 'service_contract':
      return {
        'job_name': 'Service — ${_s(p['contract_name']).isNotEmpty ? _s(p['contract_name']) : (_s(p['contract_no']).isNotEmpty ? _s(p['contract_no']) : '$id')}',
        'job_type': 'service',
        'job_priority': 'Normal',
        'source': 'contract',
        'related_contract_id': id,
        if (!_blank(p['related_account_id'])) 'related_account_id': p['related_account_id'],
        if (!_blank(p['related_contact_id'])) 'related_contact_id': p['related_contact_id'],
        if (!_blank(p['customer_name'])) 'customer_name': p['customer_name'],
        if (!_blank(p['end_date'])) 'due_datetime': p['end_date'],
        'deliverable_template': 'service_report',
        if (!_blank(p['smownerid'])) 'smownerid': p['smownerid'],
      };
    case 'quotation':
      final no = _s(p['quotation_no']).isNotEmpty ? _s(p['quotation_no']) : 'QT-$id';
      final ref = ['อ้างอิงใบเสนอราคา ${_s(p['quotation_no']).isNotEmpty ? _s(p['quotation_no']) : '#$id'}', if (_s(p['po_reference']).isNotEmpty) 'PO: ${_s(p['po_reference'])}'].join(' · ');
      return {
        'job_name': '$no — ${_s(p['customer_name']).isNotEmpty ? _s(p['customer_name']) : (_s(p['quotation_name']).isNotEmpty ? _s(p['quotation_name']) : 'Job')}',
        'job_type': 'service',
        'job_priority': 'Normal',
        'source': 'quotation',
        'related_quotation_id': id,
        if (!_blank(p['related_account_id'])) 'related_account_id': p['related_account_id'],
        if (!_blank(p['related_contact_id'])) 'related_contact_id': p['related_contact_id'],
        if (!_blank(p['customer_name'])) 'customer_name': p['customer_name'],
        'description': [ref, if (linesSummary.isNotEmpty) linesSummary].join('\n\n'),
        if (!_blank(p['smownerid'])) 'smownerid': p['smownerid'],
      };
  }
  return const {};
}

/// The server's quotation-lines summary for a job description.
String quotationLinesSummary(List<Map<String, dynamic>> lines) => [
      for (final l in lines.take(100))
        if (_plain(l['description']).replaceAll(RegExp(r'\s+'), ' ').isNotEmpty)
          () {
            final text = _plain(l['description']).replaceAll(RegExp(r'\s+'), ' ');
            if (_s(l['line_type']) == 'text' || l['quantity'] == null) return text;
            final q = qNum(l['quantity']);
            final qs = q == q.roundToDouble() ? '${q.toInt()}' : '$q';
            return '• $text × $qs${_s(l['unit']).isNotEmpty ? ' ${_s(l['unit'])}' : ''}';
          }(),
    ].join('\n');

/// Relation the job was opened from (its picker is hidden).
String? jobParentOf(Map<String, dynamic> values) {
  if (!_blank(values['related_case_id']) && values['source'] == 'case') return 'case';
  if (!_blank(values['related_contract_id']) && values['source'] == 'contract') return 'service_contract';
  if (!_blank(values['related_quotation_id'])) return 'quotation';
  if (!_blank(values['related_case_id'])) return 'case';
  if (!_blank(values['related_contract_id'])) return 'service_contract';
  return null;
}

const _jobCopyDrop = {
  'id', 'crmid', 'job_no', 'job_status', 'createdtime', 'modifiedtime', 'created_at', 'updated_at', 'smcreatorid', 'modifiedby',
  'deleted', 'business_id', 'customer_signature', 'customer_signed_at', 'customer_signed_by_name', 'technician_signature',
  'technician_signed_at', 'technician_signed_by_name', 'evidence_photos', 'accepted_at', 'cancelled_at', 'cancel_reason', 'close_note',
  'actual_start', 'actual_end', 'accept_alert_at', 'public_token', 'public_token_at', 'customer_ack_status', '_shared_permission',
  // ทำซ้ำ: dates and technicians start empty.
  'plan_start', 'plan_end', 'due_datetime', 'smownerid', 'engineer_user_id', 'engineer_name', 'engineer_phone', 'related_activity_id',
};

/// ทำซ้ำ a job: customer, place and details copied; dates, technicians,
/// status cleared; "(Copy)" name; template re-checked.
Map<String, dynamic> jobDuplicateValues(Map<String, dynamic> src, {Map<String, dynamic> ctx = const {}}) {
  final v = <String, dynamic>{
    for (final e in src.entries)
      if (!_jobCopyDrop.contains(e.key) && !e.key.startsWith('_') && !e.key.endsWith('_name_display')) e.key: e.value,
  };
  final name = _s(v['job_name']);
  if (name.isNotEmpty) v['job_name'] = '$name (Copy)';
  final r = resolveDocTemplate(
    mode: DocFormMode.duplicate,
    layoutKey: src['template_key'],
    templateId: src['job_template_id'],
    allowedLayouts: allowedLayoutsOf(ctx),
    defaultLayout: defaultLayoutOf(ctx),
    templates: templatesOf(ctx),
    firstAsFallback: true,
  );
  v['template_key'] = r.layout;
  v['job_template_id'] = r.templateId;
  return v;
}

/// New job defaults (web `getCreateDefaults('job')` + job settings' new defaults).
Map<String, dynamic> jobCreateValues({
  required String? userId,
  Map<String, dynamic> ctx = const {},
  Map<String, List<Map<String, dynamic>>> picklists = const {},
  Map<String, dynamic> prefill = const {},
}) {
  final v = <String, dynamic>{
    ...createDefaults('job', userId: userId, picklists: picklists),
    'job_type': pickDefaultOption(picklists['job_type'], 'service'),
    'deliverable_template': pickDefaultOption(picklists['deliverable_template'], 'service_report'),
    ...prefill,
  };
  v.remove('job_status');
  final doc = ctx['document'] is Map ? Map<String, dynamic>.from(ctx['document']) : const <String, dynamic>{};
  final nd = doc['new_defaults'] is Map ? Map<String, dynamic>.from(doc['new_defaults']) : const <String, dynamic>{};
  final allowed = allowedLayoutsOf(ctx);
  final pref = _s(nd['template_key']).isNotEmpty && allowed.map(normLayout).contains(normLayout(nd['template_key'])) ? nd['template_key'] : defaultLayoutOf(ctx);
  final r = resolveDocTemplate(mode: DocFormMode.create, allowedLayouts: allowed, defaultLayout: pref, templates: templatesOf(ctx), firstAsFallback: true);
  v['template_key'] = r.layout;
  v['job_template_id'] = r.templateId;
  if (nd['in_warranty'] is bool && v['in_warranty'] == null) v['in_warranty'] = nd['in_warranty'];
  if (_s(nd['system_status']).isNotEmpty && _blank(v['system_status'])) v['system_status'] = nd['system_status'];
  return v;
}

/// Wall-clock `yyyy-MM-ddTHH:mm:00` (what the date-time pickers produce).
String wallDateTime(DateTime d) => '${ymd(d)}T${_two(d.hour)}:${_two(d.minute)}:00';

/// Quick plan chips: (label, start, end) from Thai "now".
List<({String key, String label, DateTime start, DateTime end})> jobQuickSlots(DateTime now, {Duration length = const Duration(hours: 2)}) {
  DateTime at(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
  final out = <({String key, String label, DateTime start, DateTime end})>[
    (key: 'in1h', label: 'ชั่วโมงหน้า', start: nextHour, end: nextHour.add(length)),
    if (now.hour < 12) (key: 'today_pm', label: 'บ่ายนี้', start: at(now, 13), end: at(now, 13).add(length)),
    (key: 'tomorrow_am', label: 'พรุ่งนี้เช้า', start: at(tomorrow, 9), end: at(tomorrow, 9).add(length)),
    (key: 'tomorrow_pm', label: 'พรุ่งนี้บ่าย', start: at(tomorrow, 13), end: at(tomorrow, 13).add(length)),
  ];
  var monday = DateTime(now.year, now.month, now.day + 1);
  while (monday.weekday != DateTime.monday) {
    monday = DateTime(monday.year, monday.month, monday.day + 1);
  }
  out.add((key: 'next_monday', label: 'จันทร์หน้า', start: at(monday, 9), end: at(monday, 9).add(length)));
  return out;
}

