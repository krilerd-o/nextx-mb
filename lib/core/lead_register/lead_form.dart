/// Lead Register — form model shared by the native builder, the native fill
/// screen and kiosk. Mirrors NEXTX `backend/src/services/leadRegister/leadFormModel.js`
/// (same question JSON, same `uitype` values: the 52 CRM UI types + `Form*`).
library;

/// The 52 CRM UI types (`kUitypeOptionValues`) plus the form-only types.
const kLeadFormOnlyTypes = ['FormLinearScale', 'FormRating', 'FormChoiceGrid', 'FormCheckboxGrid', 'FormConsent', 'FormTitle', 'FormMedia'];

const kLeadChoiceTypes = {'Enum', 'Picklist', 'RadioGroup', 'MultiSelect', 'Tag'};
const kLeadMultiTypes = {'MultiSelect', 'Tag', 'MultiPicklistUser', 'FormCheckboxGrid'};
const kLeadDisplayOnly = {'FormTitle', 'FormMedia', 'Post'};
const kLeadFileTypes = {'File', 'Image', 'Video', 'Drawing'};
const kLeadSnapshotSelect = {'ProductSelect', 'ServiceSelect', 'LocationSelect'};
const kLeadStaffOnly = {
  'PicklistUser', 'MultiPicklistUser', 'LeadSelect', 'AccountSelect', 'ContactSelect', 'QuotationSelect',
  'AssetSelect', 'JobSelect', 'CaseSelect', 'ContractSelect', 'App',
};
const kLeadFlowSteps = ['lead', 'email', 'deal', 'activity'];

/// Lead fields a question can be saved to.
const kLeadMapTargets = <String, String>{
  '': 'ไม่บันทึกลง Lead',
  'lead_name': 'ชื่อ-นามสกุล',
  'lead_firstname': 'ชื่อ',
  'lead_lastname': 'นามสกุล',
  'company_name': 'บริษัท',
  'position': 'ตำแหน่ง',
  'email_1st': 'อีเมล',
  'mobile_1st': 'มือถือ',
  'company_industry': 'อุตสาหกรรม',
  'company_size': 'ขนาดบริษัท',
  'lead_interest': 'ความสนใจ',
  'address_line1': 'ที่อยู่',
  'description': 'รายละเอียด',
};

/// Question type groups for the native builder's type picker.
const kLeadTypeGroups = <String, List<(String, String)>>{
  'ข้อความ & ติดต่อ': [
    ('Text', 'คำตอบสั้น'), ('LongText', 'ย่อหน้า'), ('RichText', 'ข้อความจัดรูปแบบ'), ('Email', 'อีเมล'), ('Phone', 'เบอร์โทร'),
    ('Link', 'ลิงก์'), ('Address', 'ที่อยู่'), ('AddressMap', 'ที่อยู่ + แผนที่'),
  ],
  'ตัวเลือก': [
    ('RadioGroup', 'ตัวเลือกเดียว'), ('MultiSelect', 'ช่องทำเครื่องหมาย'), ('Picklist', 'ดรอปดาวน์'), ('Enum', 'ดรอปดาวน์ (Enum)'),
    ('Tag', 'แท็ก'), ('YesNo', 'ใช่ / ไม่ใช่'), ('FormChoiceGrid', 'ตารางตัวเลือกเดียว'), ('FormCheckboxGrid', 'ตารางหลายตัวเลือก'),
  ],
  'คะแนน & ตัวเลข': [
    ('FormLinearScale', 'สเกลเชิงเส้น'), ('FormRating', 'ให้ดาว'), ('EmotionalEmoji', 'อีโมจิความรู้สึก'), ('Number', 'ตัวเลข'),
    ('Currency', 'จำนวนเงิน'), ('Percent', 'เปอร์เซ็นต์'), ('Counter', 'ตัวนับ'), ('Progress', 'ความคืบหน้า'), ('Duration', 'ระยะเวลา'),
  ],
  'วันที่ & เวลา': [
    ('Date', 'วันที่'), ('Time', 'เวลา'), ('DateTime', 'วันที่และเวลา'), ('DateRange', 'ช่วงวันที่'), ('MonthPicker', 'เดือน'),
    ('MonthRange', 'ช่วงเดือน'), ('YearPicker', 'ปี'), ('YearRange', 'ช่วงปี'),
  ],
  'ไฟล์ & สื่อ': [
    ('File', 'อัปโหลดไฟล์'), ('Image', 'รูปภาพ'), ('Video', 'วิดีโอ'), ('Drawing', 'ลายเซ็น / วาด'), ('Color', 'สี'),
    ('LatLong', 'พิกัด GPS'), ('XY', 'จุดบนภาพ'), ('LicenseArea', 'พื้นที่ใบอนุญาต'), ('Post', 'โพสต์'),
  ],
  'ข้อมูล CRM (พนักงาน)': [
    ('ProductSelect', 'สินค้า'), ('ServiceSelect', 'บริการ'), ('LocationSelect', 'สถานที่'), ('PicklistUser', 'ผู้ใช้'),
    ('MultiPicklistUser', 'ผู้ใช้หลายคน'), ('LeadSelect', 'Lead'), ('AccountSelect', 'บริษัท'), ('ContactSelect', 'ผู้ติดต่อ'),
    ('QuotationSelect', 'ใบเสนอราคา'), ('AssetSelect', 'ทรัพย์สิน'), ('JobSelect', 'ใบงาน'), ('CaseSelect', 'เคส'),
    ('ContractSelect', 'สัญญา'), ('App', 'แอป'),
  ],
  'จัดหน้า & ยินยอม': [('FormTitle', 'หัวข้อ & คำอธิบาย'), ('FormMedia', 'บล็อกรูป / วิดีโอ'), ('FormConsent', 'ยินยอม PDPA')],
};

String leadTypeLabel(String uitype) {
  for (final g in kLeadTypeGroups.values) {
    for (final (t, l) in g) {
      if (t == uitype) return l;
    }
  }
  return uitype;
}

typedef LeadAnswers = Map<String, dynamic>;

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

class LeadQuestion {
  LeadQuestion(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['id']?.toString() ?? '';
  String get uitype => raw['uitype']?.toString() ?? 'Text';
  String get label => raw['label']?.toString() ?? '';
  String get description => raw['description']?.toString() ?? '';
  String get placeholder => raw['placeholder']?.toString() ?? '';
  bool get required => raw['required'] == true;
  bool get allowOther => raw['allow_other'] == true;
  bool get staffOnly => raw['staff_only'] == true || kLeadStaffOnly.contains(uitype);
  bool get hidden => raw['hidden'] == true;
  bool get displayOnly => kLeadDisplayOnly.contains(uitype);
  bool get isMulti => kLeadMultiTypes.contains(uitype);
  String? get mapTo => raw['map_to']?.toString();
  List<Map<String, dynamic>> get options => _maps(raw['options']);
  List<String> get rows => (raw['rows'] as List?)?.map((e) => '$e').toList() ?? const [];
  List<String> get columns => (raw['columns'] as List?)?.map((e) => '$e').toList() ?? const [];
  Map<String, dynamic> get scale => _map(raw['scale']);
  Map<String, dynamic> get validation => _map(raw['validation']);
  Map<String, dynamic>? get showIf => raw['show_if'] is Map ? _map(raw['show_if']) : null;
  String get consentText => raw['consent_text']?.toString() ?? '';
  String get mediaUrl => raw['media_url']?.toString() ?? '';
  String get display => raw['display']?.toString() ?? 'checkbox';

  String optionLabel(String value) {
    if (value == '__other__') return 'อื่นๆ';
    for (final o in options) {
      if (o['value']?.toString() == value) return o['label']?.toString() ?? value;
    }
    return value;
  }
}

class LeadSection {
  LeadSection(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id']?.toString() ?? '';
  String get title => raw['title']?.toString() ?? '';
  String get description => raw['description']?.toString() ?? '';
  String? get goTo => raw['go_to']?.toString();
  Map<String, dynamic>? get showIf => raw['show_if'] is Map ? _map(raw['show_if']) : null;
  List<LeadQuestion> get questions => _maps(raw['questions']).map(LeadQuestion.new).toList();
}

class LeadFormDef {
  LeadFormDef(this.raw);
  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  String get name => raw['name']?.toString() ?? '';
  String get description => raw['description']?.toString() ?? '';
  String get uiType => raw['ui_type']?.toString() ?? 'classic';
  String get status => raw['status']?.toString() ?? 'draft';
  String get token => (raw['public_token'] ?? raw['token'])?.toString() ?? '';
  Map<String, dynamic> get theme => _map(raw['theme']);
  Map<String, dynamic> get settings => _map(raw['settings']);
  Map<String, dynamic> get flow => _map(raw['flow']);

  /// Sections from either the full form (`questions.sections`) or a fill definition (`sections`).
  List<LeadSection> get sections {
    final q = raw['questions'];
    final list = q is Map ? q['sections'] : raw['sections'];
    return _maps(list).map(LeadSection.new).where((s) => s.questions.isNotEmpty || s.title.isNotEmpty).toList();
  }

  int get kioskResetSeconds => (settings['kiosk_reset_seconds'] as num?)?.toInt() ?? 10;
  String get kioskPin => settings['kiosk_exit_pin']?.toString() ?? '';
}

bool _empty(dynamic v) =>
    v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

bool leadEvalCondition(Map<String, dynamic>? cond, LeadAnswers answers) {
  if (cond == null || (cond['question_id']?.toString() ?? '').isEmpty) return true;
  final a = answers[cond['question_id']];
  final vals = a is List ? a.map((e) => '$e').toList() : _empty(a) ? <String>[] : ['$a'];
  final value = cond['value']?.toString() ?? '';
  switch (cond['op']) {
    case 'answered':
      return vals.isNotEmpty;
    case 'not_answered':
      return vals.isEmpty;
    case 'not_eq':
      return !vals.contains(value);
    case 'includes':
      return vals.any((v) => v.toLowerCase().contains(value.toLowerCase()));
    default:
      return vals.contains(value);
  }
}

bool leadQuestionVisible(LeadQuestion q, LeadAnswers answers, {bool staff = true}) {
  if (q.hidden) return false;
  if (!staff && q.staffOnly) return false;
  return leadEvalCondition(q.showIf, answers);
}

List<LeadQuestion> leadVisibleQuestions(LeadSection s, LeadAnswers answers, {bool staff = true}) =>
    leadEvalCondition(s.showIf, answers) ? s.questions.where((q) => leadQuestionVisible(q, answers, staff: staff)).toList() : const [];

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _phone = RegExp(r'^[+()\d\s-]{6,20}$');

/// Error text (Thai, translated with tr() at display) or null.
String? leadValidateQuestion(LeadQuestion q, LeadAnswers answers) {
  if (q.displayOnly) return null;
  final v = answers[q.id];
  final other = answers['${q.id}__other'];
  final custom = q.validation['message']?.toString();
  String msg(String m) => (custom != null && custom.isNotEmpty) ? custom : m;
  if (_empty(v) || (q.uitype == 'FormConsent' && v != true)) {
    if (q.required) return msg(q.uitype == 'FormConsent' ? 'กรุณายอมรับเพื่อดำเนินการต่อ' : 'กรุณาตอบคำถามนี้');
    return null;
  }
  final hasOther = v is List ? v.contains('__other__') : v == '__other__';
  if (hasOther && q.allowOther && _empty(other)) return msg('กรุณาระบุ “อื่นๆ”');
  if (q.uitype == 'Email' && !_email.hasMatch('$v'.trim())) return msg('อีเมลไม่ถูกต้อง');
  if (q.uitype == 'Phone' && !_phone.hasMatch('$v'.trim())) return msg('เบอร์โทรไม่ถูกต้อง');
  final val = q.validation;
  if (const {'Number', 'Currency', 'Percent', 'Counter'}.contains(q.uitype)) {
    final n = num.tryParse('$v');
    if (n == null) return msg('กรุณากรอกตัวเลข');
    final min = val['min'] as num?;
    final max = val['max'] as num?;
    if (min != null && n < min) return msg('ต้องไม่น้อยกว่า $min');
    if (max != null && n > max) return msg('ต้องไม่เกิน $max');
  }
  if (v is String) {
    final minL = (val['min_length'] as num?)?.toInt();
    final maxL = (val['max_length'] as num?)?.toInt();
    if (minL != null && v.length < minL) return msg('อย่างน้อย $minL ตัวอักษร');
    if (maxL != null && v.length > maxL) return msg('ไม่เกิน $maxL ตัวอักษร');
    final pattern = val['pattern']?.toString();
    if (pattern != null && pattern.isNotEmpty) {
      try {
        if (!RegExp(pattern).hasMatch(v)) return msg('รูปแบบไม่ถูกต้อง');
      } catch (_) {}
    }
  }
  if ((q.uitype == 'FormChoiceGrid' || q.uitype == 'FormCheckboxGrid') && q.required) {
    final m = v is Map ? v : const {};
    final filled = m.values.where((x) => !_empty(x)).length;
    if (filled < q.rows.length) return msg('กรุณาตอบให้ครบทุกแถว');
  }
  return null;
}

Map<String, String> leadValidateSection(LeadSection s, LeadAnswers answers, {bool staff = true}) {
  final out = <String, String>{};
  for (final q in leadVisibleQuestions(s, answers, staff: staff)) {
    final e = leadValidateQuestion(q, answers);
    if (e != null) out[q.id] = e;
  }
  return out;
}

/// Next section index after [idx] honouring option `go_to`, section `go_to` and hidden sections.
int leadNextSection(List<LeadSection> sections, int idx, LeadAnswers answers) {
  int target(String goTo) => goTo == '__submit__' ? sections.length : sections.indexWhere((x) => x.id == goTo);
  final s = sections[idx];
  for (final q in s.questions) {
    final v = answers[q.id];
    final vals = v is List ? v.map((e) => '$e').toList() : v == null ? <String>[] : ['$v'];
    for (final o in q.options) {
      final goTo = o['go_to']?.toString();
      if (goTo != null && goTo.isNotEmpty && vals.contains(o['value']?.toString())) {
        final j = target(goTo);
        if (j >= 0) return j;
      }
    }
  }
  if (s.goTo != null && s.goTo!.isNotEmpty) {
    final j = target(s.goTo!);
    if (j >= 0) return j;
  }
  var j = idx + 1;
  while (j < sections.length && !leadEvalCondition(sections[j].showIf, answers)) {
    j++;
  }
  return j;
}

String leadAnswerText(LeadQuestion q, LeadAnswers answers) {
  final v = answers[q.id];
  final other = answers['${q.id}__other'];
  if (v == null || (v is String && v.isEmpty)) return '';
  String label(dynamic x) => x == '__other__' ? 'อื่นๆ: ${other ?? ''}' : q.optionLabel('$x');
  if (v is List) return v.map((x) => x is Map ? (x['name'] ?? x['url'] ?? '').toString() : label(x)).join(', ');
  if (v is bool) return v ? 'ใช่' : 'ไม่ใช่';
  if (v is Map) return v.entries.map((e) => '${e.key}: ${e.value is List ? (e.value as List).join('/') : e.value}').join('; ');
  return label(v);
}

/// A new question of [uitype] with sensible defaults (mirrors web `newQuestion`).
Map<String, dynamic> leadNewQuestion(String uitype) {
  final q = <String, dynamic>{
    'id': 'q_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
    'uitype': uitype,
    'label': leadTypeLabel(uitype),
    'required': false,
  };
  if (kLeadChoiceTypes.contains(uitype) || kLeadSnapshotSelect.contains(uitype)) {
    q['options'] = [
      {'value': 'ตัวเลือก 1', 'label': 'ตัวเลือก 1'},
      {'value': 'ตัวเลือก 2', 'label': 'ตัวเลือก 2'},
    ];
  }
  if (uitype == 'FormLinearScale') q['scale'] = {'min': 1, 'max': 5};
  if (uitype == 'FormRating') q['scale'] = {'min': 1, 'max': 5};
  if (uitype == 'FormChoiceGrid' || uitype == 'FormCheckboxGrid') {
    q['rows'] = ['แถว 1', 'แถว 2'];
    q['columns'] = ['คอลัมน์ 1', 'คอลัมน์ 2', 'คอลัมน์ 3'];
  }
  if (uitype == 'FormConsent') {
    q['label'] = 'ยินยอมให้ใช้ข้อมูลส่วนบุคคล';
    q['required'] = true;
    q['consent_text'] = 'ข้าพเจ้ายินยอมให้เก็บและใช้ข้อมูลส่วนบุคคลเพื่อติดต่อเกี่ยวกับสินค้าและบริการที่เลือก';
  }
  if (uitype == 'Email') q['map_to'] = 'email_1st';
  if (uitype == 'Phone') q['map_to'] = 'mobile_1st';
  return q;
}

/// Business-card scan → answers: server answers win, filled keys returned.
({LeadAnswers answers, Set<String> filled}) leadMergeScan(LeadAnswers current, Map<String, dynamic> scanned) {
  final next = Map<String, dynamic>.from(current);
  final filled = <String>{};
  scanned.forEach((k, v) {
    if (_empty(v)) return;
    next[k] = v;
    filled.add(k);
  });
  return (answers: next, filled: filled);
}

final _cardEmail = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
final _cardPhone = RegExp(r'(?:\+?66[\s\-]?|0)(?:\d[\s\-.]?){8,9}');
final _cardUrl = RegExp(r'(?:https?://)?(?:www\.)[^\s,]+', caseSensitive: false);

/// Offline fallback for the business-card scan: on-device OCR text → answers by
/// question id (email, phone, website and a best-guess name). Uses each question's
/// lead-field mapping first, then its UI type. AI refinement is the online path.
Map<String, dynamic> leadParseCardText(String text, LeadFormDef form) {
  final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final email = _cardEmail.firstMatch(text)?.group(0);
  final phones = _cardPhone.allMatches(text).map((m) => m.group(0)!.replaceAll(RegExp(r'[\s\-.]'), '')).toList();
  final mobile = phones.firstWhere((p) => RegExp(r'^(?:\+?66|0)[689]').hasMatch(p), orElse: () => phones.isEmpty ? '' : phones.first);
  final url = _cardUrl.firstMatch(text)?.group(0);
  final companyMark = RegExp(r'(co\.?,?\s*ltd|limited|inc\b|corp|plc|บริษัท|จำกัด|ห้างหุ้นส่วน|group)', caseSensitive: false);
  final company = lines.where((l) => companyMark.hasMatch(l)).firstOrNull;
  String? name;
  for (final l in lines) {
    if (_cardEmail.hasMatch(l) || _cardPhone.hasMatch(l) || _cardUrl.hasMatch(l) || RegExp(r'[\d,@/]').hasMatch(l) || companyMark.hasMatch(l)) continue;
    final words = l.split(RegExp(r'\s+'));
    if (words.length >= 2 && words.length <= 4 && l.length <= 40) {
      name = l;
      break;
    }
  }
  final nameParts = name?.split(RegExp(r'\s+')) ?? const <String>[];
  final out = <String, dynamic>{};
  final qs = [for (final s in form.sections) ...s.questions];
  void put(bool Function(LeadQuestion q) match, String? value) {
    if (value == null || value.isEmpty) return;
    for (final q in qs) {
      if (!out.containsKey(q.id) && match(q)) {
        out[q.id] = value;
        return;
      }
    }
  }

  put((q) => q.mapTo == 'email_1st' || (q.mapTo == null && q.uitype == 'Email'), email);
  put((q) => q.mapTo == 'mobile_1st' || (q.mapTo == null && q.uitype == 'Phone'), mobile.isEmpty ? null : mobile);
  put((q) => q.mapTo == 'website' || (q.mapTo == null && q.uitype == 'Link'), url);
  put((q) => q.mapTo == 'company_name', company);
  if (nameParts.length >= 2) {
    put((q) => q.mapTo == 'lead_firstname', nameParts.first);
    put((q) => q.mapTo == 'lead_lastname', nameParts.sublist(1).join(' '));
  }
  return out;
}
