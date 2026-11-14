import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/card_layout.dart' show formatMoney;
import '../../core/doc_form/doc_form_draft.dart';
import '../../core/doc_form/doc_form_rules.dart';
import '../../core/doc_form/doc_pick_rules.dart';
import '../../core/doc_form/quotation_math.dart';
import '../../core/entity_modules.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../core/menu_access.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/field_validate.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../docs/doc_email_sheet.dart';
import '../docs/document_tab.dart';
import '../journey/journey_controller.dart';
import '../journey/quotation_journey.dart' show showSubmitApprovalSheet;
import 'barcode_scan_sheet.dart';
import 'doc_form_shell.dart';
import 'doc_pickers.dart';

const _steps = [
  DocStepInfo('ลูกค้า', NxI.buildings),
  DocStepInfo('รายการสินค้า', NxI.package),
  DocStepInfo('เงื่อนไข', NxI.clipboardText),
  DocStepInfo('ตรวจและสร้าง', NxI.checkCircle),
];

/// Quotation create / edit / duplicate (ทำซ้ำ) / Revise in 4 steps:
/// ลูกค้า → รายการสินค้า → เงื่อนไข → ตรวจและสร้าง, with the live total in a
/// sticky bar. Saves like the web (`POST /api/quotation/save` header + lines
/// in one go; Revise: `POST /api/quotation/:id/revise`).
class QuotationStepForm extends StatefulWidget {
  const QuotationStepForm({
    super.key,
    this.mode = DocFormMode.create,
    this.recordId,
    this.initialValues,
    this.initialLines,
    this.embedded = false,
    this.onFinished,
    this.initialStep,
  });

  final DocFormMode mode;

  /// Edit: the quotation; duplicate / revise: the source quotation.
  final String? recordId;

  /// New quotation pre-filled by the caller (e.g. account / deal page).
  final Map<String, dynamic>? initialValues;
  final List<Map<String, dynamic>>? initialLines;
  final bool embedded;

  /// `{id, quotation_no}` when saved, null when closed without saving.
  final ValueChanged<Map<String, dynamic>?>? onFinished;
  final int? initialStep;

  @override
  State<QuotationStepForm> createState() => QuotationStepFormState();
}

class QuotationStepFormState extends State<QuotationStepForm> {
  bool _loading = true;
  Object? _loadError;
  DocFormSchema _schema = DocFormSchema(module: 'quotation', fields: const []);
  Map<String, dynamic> _ctx = const {};
  final Map<String, dynamic> _values = {};
  final List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic> _source = const {};
  List<Map<String, dynamic>> _sourceLines = const [];
  int _step = 0;
  int _maxStep = 0;
  final Set<int> _shownErrors = {};
  String? _savedId;
  Map<String, dynamic>? _savedRow;
  bool _dirtySinceSave = false;
  String? _busy;
  String? _templateNotice;
  int _revNo = 1;
  bool _locked = false;
  String? _lockReason;
  final _anchors = DocFieldAnchors();
  late final NxFieldHost _host;
  String? _draftKey;
  String _baseline = '';
  Timer? _draftTimer;
  List<Map<String, dynamic>> _accountContacts = const [];
  String _customerKind = '';
  bool _detailsOpen = false;
  bool _manualCustomer = false;

  ApiClient get _api => context.read<AppConfig>().apiClient;
  DocFormMode get _mode => widget.mode;
  bool get _isRevise => _mode == DocFormMode.revise;
  String? get _id => _savedId;

  @override
  void initState() {
    super.initState();
    _host = nxFieldHostFor(context.read<AppConfig>().apiClient, module: 'quotation');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────── loading

  String get _recordKey => switch (_mode) {
        DocFormMode.create => 'new',
        DocFormMode.edit => widget.recordId ?? 'new',
        DocFormMode.duplicate => 'dup:${widget.recordId}',
        DocFormMode.revise => 'rev:${widget.recordId}',
      };

  Future<void> _load() async {
    final config = context.read<AppConfig>();
    final session = config.session;
    final api = config.apiClient;
    try {
      final schemaF = api.getFieldSchema('quotation').then<ModuleFieldSchema?>((s) => s).catchError((_) => null);
      final ctxF = api.getQuotationContext().catchError((_) => <String, dynamic>{});
      final srcId = widget.recordId;
      Future<Map<String, dynamic>>? rowF;
      Future<List<Map<String, dynamic>>>? linesF;
      Future<List<Map<String, dynamic>>>? chainF;
      if (_mode != DocFormMode.create && srcId != null) {
        rowF = api.getEntity('quotation', srcId);
        linesF = api.getQuotationLines(srcId).catchError((_) => <Map<String, dynamic>>[]);
        if (_isRevise) chainF = api.getQuotationRevisions(srcId).catchError((_) => <Map<String, dynamic>>[]);
      }
      final schema = await schemaF;
      final ctx = await ctxF;
      final row = rowF == null ? <String, dynamic>{} : await rowF;
      final srcLines = linesF == null ? <Map<String, dynamic>>[] : await linesF;
      final chain = chainF == null ? <Map<String, dynamic>>[] : await chainF;
      final today = thaiNow();
      final picklists = schema?.picklists ?? const <String, List<Map<String, dynamic>>>{};
      Map<String, dynamic> values;
      var lines = <Map<String, dynamic>>[];
      switch (_mode) {
        case DocFormMode.create:
          values = quotationCreateValues(userId: session.userId, today: today, ctx: ctx, picklists: picklists, prefill: widget.initialValues ?? const {});
          await _applyTextDefaults(api, values);
          lines = [for (final l in widget.initialLines ?? const <Map<String, dynamic>>[]) {...blankQuotationLine(taxRate: values['tax_rate']), ...l}..remove('id')];
        case DocFormMode.edit:
          values = hydrateSalesText({...?widget.initialValues, ...row});
          values['template_key'] = normLayout(values['template_key']);
          values['document_options'] = documentOptionsOf(values['document_options']);
          lines = [for (final l in srcLines) Map<String, dynamic>.from(l)];
          _savedId = srcId;
          _savedRow = row;
          if (!isQuotationEditable(row)) {
            _locked = true;
            _lockReason = 'ใบเสนอราคาสถานะ "${canonicalQuotationStatus(row['quotation_status'])}" แก้ไขไม่ได้ — สร้างฉบับแก้ไข (Revise) หรือทำสำเนาเป็นใบใหม่';
          }
        case DocFormMode.duplicate:
          values = quotationDuplicateValues(row, userId: session.userId, today: today, ctx: ctx);
          lines = copyQuotationLines(srcLines);
          _templateNotice = _noticeFor(row, values);
        case DocFormMode.revise:
          values = quotationReviseValues(row, ctx: ctx);
          lines = copyQuotationLines(srcLines);
          _revNo = nextRevisionNo(row, chain);
          _templateNotice = _noticeFor(row, values);
      }
      if ('${row['_shared_permission'] ?? ''}' == 'read_only') {
        _locked = true;
        _lockReason = 'คุณมีสิทธิ์ดูอย่างเดียวสำหรับใบเสนอราคานี้';
      }
      for (final k in const ['quote_date', 'valid_until', 'delivery_date']) {
        final d = parseThaiDate(values[k]);
        if (d != null) values[k] = ymd(d);
      }
      if (schema != null) normalizeFormDates(schema.fields, values, module: 'quotation');
      _ownerLabel(values, ctx, session.userId, session.displayName ?? session.email);
      _customerKind = !isBlankValue(values['related_account_id'])
          ? 'account'
          : !isBlankValue(values['related_contact_id'])
              ? 'contact'
              : !isBlankValue(values['related_lead_id'])
                  ? 'lead'
                  : '';
      if (!mounted) return;
      setState(() {
        _schema = DocFormSchema(module: 'quotation', fields: schema?.fields ?? const [], picklists: picklists);
        _ctx = ctx;
        _source = row;
        _sourceLines = srcLines;
        _values
          ..clear()
          ..addAll(values);
        _lines
          ..clear()
          ..addAll(lines);
        _keyLines();
        _step = (widget.initialStep ?? 0).clamp(0, _steps.length - 1);
        _maxStep = _mode == DocFormMode.create ? _step : _steps.length - 1;
        _loading = false;
      });
      final acc = '${unwrapFieldValue(values['related_account_id']) ?? ''}';
      if (acc.isNotEmpty && acc != 'null') _loadAccountContacts(acc);
      if (_mode == DocFormMode.create && isBlankValue(values['customer_name'])) await _autofillPrefill(values);
      _baseline = _snapshot();
      _draftKey = DocFormDraftStore.key(businessId: session.businessId, module: 'quotation', record: _recordKey);
      await _offerDraft();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  /// Opened from an account / contact / lead page: fill the customer like a pick.
  Future<void> _autofillPrefill(Map<String, dynamic> values) async {
    for (final (key, module) in const [('related_account_id', 'account'), ('related_contact_id', 'contact'), ('related_lead_id', 'lead')]) {
      final id = '${unwrapFieldValue(values[key]) ?? ''}';
      if (id.isEmpty || id == 'null') continue;
      await _pickCustomer(module, {'id': id});
      return;
    }
  }

  String? _noticeFor(Map<String, dynamic> src, Map<String, dynamic> v) {
    if (normLayout(src['template_key']) != v['template_key']) return 'รูปแบบเอกสารของใบต้นทางปิดใช้แล้ว — ใช้รูปแบบเริ่มต้นแทน';
    if ('${src['template_id'] ?? ''}' != '${v['template_id'] ?? ''}' && '${src['template_id'] ?? ''}'.isNotEmpty) {
      return 'เทมเพลตเอกสารของใบต้นทางปิดใช้แล้ว — ใช้เทมเพลตเริ่มต้นแทน';
    }
    return null;
  }

  /// My default text blocks (web: resolveTextTemplateDefaults on a new quotation).
  Future<void> _applyTextDefaults(ApiClient api, Map<String, dynamic> values) async {
    try {
      final r = await api.resolveQuotationTextDefaults(locale: L10n.isEn ? 'en' : 'th');
      const map = {
        'intro': 'sample_text',
        'terms': 'terms_conditions',
        'footer': 'quote_termcondition',
        'qline_before': 'qline_remark_before',
        'qline_after': 'qline_remark_after',
      };
      map.forEach((cat, field) {
        final b = r[cat];
        final html = b is Map ? '${b['html'] ?? ''}' : '';
        if (html.trim().isNotEmpty && isBlankValue(values[field])) values[field] = html;
      });
    } catch (_) {}
  }

  void _ownerLabel(Map<String, dynamic> v, Map<String, dynamic> ctx, String? me, String? myName) {
    final o = v['smownerid'];
    if (o == null || o is Map || '$o'.isEmpty) return;
    String? label;
    final users = ctx['users'];
    if (users is List) {
      for (final u in users) {
        if (u is Map && '${u['id']}' == '$o') label = '${u['label'] ?? ''}';
      }
    }
    if ((label == null || label.isEmpty) && '$o' == me) label = myName;
    label ??= '${v['smownerid_name'] ?? v['owner_name'] ?? v['assigned_user_name'] ?? ''}';
    if (label.isNotEmpty) v['smownerid'] = {'id': '$o', 'label': label};
  }

  // ─────────────────────────────────────────────────────────────── drafts

  static List<Map<String, dynamic>> _plainLines(List<Map<String, dynamic>> lines) => [for (final l in lines) Map<String, dynamic>.from(l)..remove('_k')];

  String _snapshot() => jsonEncode(DocFormDraft(values: _values, lines: _plainLines(_lines)).toJson()..remove('saved_at')..remove('step'));

  Future<void> _offerDraft() async {
    final key = _draftKey;
    if (key == null) return;
    final d = await DocFormDraftStore.read(key);
    if (d == null || !mounted) return;
    final same = jsonEncode(DocFormDraft(values: d.values, lines: _plainLines(d.lines)).toJson()..remove('saved_at')..remove('step')) == _baseline;
    if (same) return;
    final resume = await askResumeDraft(context, savedAt: d.savedAt, what: tr('ใบเสนอราคานี้'));
    if (!mounted) return;
    if (resume == true) {
      setState(() {
        _values
          ..clear()
          ..addAll(d.values);
        _lines
          ..clear()
          ..addAll(d.lines);
        _keyLines();
        _step = d.step.clamp(0, _steps.length - 1);
        _maxStep = _maxStep < _step ? _step : _maxStep;
        final note = d.extra['revision_note'];
        if (note != null) _values['revision_note'] = note;
        _customerKind = '${d.extra['customer_kind'] ?? _customerKind}';
      });
    } else if (resume == false) {
      await DocFormDraftStore.clear(key);
    }
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _writeDraft);
  }

  Future<void> _writeDraft() async {
    final key = _draftKey;
    if (key == null || _locked) return;
    if (_snapshot() == _baseline) {
      await DocFormDraftStore.clear(key);
      return;
    }
    await DocFormDraftStore.write(
      key,
      DocFormDraft(values: _values, lines: _plainLines(_lines), step: _step, extra: {'customer_kind': _customerKind}),
    );
  }

  /// Flush the draft now (leaving the screen).
  Future<void> flushDraft() async {
    _draftTimer?.cancel();
    await _writeDraft();
  }

  // ─────────────────────────────────────────────────────────────── values

  void _set(String name, dynamic v) {
    setState(() {
      _values[name] = v;
      if (name == 'tax_rate') {
        final rate = resolveTaxRate(v);
        for (final l in _lines) {
          if (l['line_type'] == 'product' || l['line_type'] == 'service' || l['line_type'] == 'text') l['tax_pct'] = rate;
        }
      }
      if (name == 'quote_date') {
        final days = qNum(_values['validity_days']).toInt();
        if (days > 0) _values['valid_until'] = addDaysYmd(v, days);
      }
      if (name == 'valid_until' && _values.containsKey('validity_days')) {
        final a = parseYmd(_values['quote_date']), b = parseYmd(v);
        if (a != null && b != null) _values['validity_days'] = b.difference(a).inDays;
      }
    });
    _touched();
  }

  void _touched() {
    _dirtySinceSave = true;
    _scheduleDraft();
  }

  void _patch(Map<String, dynamic> p) {
    setState(() => _values.addAll(p));
    _touched();
  }

  String get _discountMode {
    final d = _values['document_options'];
    final m = d is Map ? d['line_discount_mode'] : null;
    if (m == 'per_line' || m == 'per_unit') return '$m';
    final l = _ctx['layouts'];
    return l is Map && l['line_discount_mode'] == 'per_line' ? 'per_line' : 'per_unit';
  }

  QuotationTotals get _totals => aggregateHeaderTotals(
        _lines,
        headerType: '${_values['header_discount_type'] ?? ''}',
        headerValue: _values['header_discount_value'],
        taxType: '${_values['tax_type'] ?? 'exclude'}',
        taxRate: _values['tax_rate'],
        discountMode: _discountMode,
      );

  // ─────────────────────────────────────────────────────────── validation

  int _stepOf(String name) => kCoreFieldStep['quotation']?[name] ?? _schema.extra.where((e) => fieldName(e.field) == name).map((e) => e.step).firstOrNull ?? 3;

  /// Missing / invalid per step: name → message (counts on the step chips).
  List<Map<String, String>> get _missing {
    final out = List.generate(_steps.length, (_) => <String, String>{});
    final core = kCoreFieldStep['quotation']!;
    for (final e in core.entries) {
      final name = e.key;
      if (!_schema.editable(name)) continue;
      if (_schema.requires(name) && isBlankValue(_values[name])) out[e.value][name] = 'จำเป็นต้องกรอก';
    }
    if (isBlankValue(_values['customer_name']) && isBlankValue(_values['related_account_id']) && isBlankValue(_values['title_th'])) {
      out[0]['customer'] = 'เลือกลูกค้าหรือใส่ชื่อเรื่องใบเสนอราคา';
    }
    final email = '${_values['customer_email'] ?? ''}'.trim();
    if (email.isNotEmpty) {
      final err = validateFieldValue(FieldUiType.email, email, required: false);
      if (err != null) out[0]['customer_email'] = err;
    }
    if (!_lines.any((l) => !isBlankQuotationLine(l))) out[1]['lines'] = 'เพิ่มสินค้า / บริการอย่างน้อย 1 รายการ';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (isBlankQuotationLine(l)) continue;
      if ('${l['description'] ?? ''}'.trim().isEmpty && isBlankValue(l['product_id']) && isBlankValue(l['service_id'])) {
        out[1]['qline-$i-desc'] = 'ใส่ชื่อรายการ';
      }
    }
    final q = parseYmd(_values['quote_date']), v = parseYmd(_values['valid_until']);
    if (q != null && v != null && v.isBefore(q)) out[2]['valid_until'] = 'วันยืนราคาต้องไม่ก่อนวันที่เอกสาร';
    if (_isRevise && '${_values['revision_note'] ?? ''}'.trim().isEmpty) out[3]['revision_note'] = 'ระบุเหตุผลที่แก้ไขฉบับนี้';
    for (var s = 0; s < _steps.length; s++) {
      out[s].addAll(validateExtraFields(_schema.extraFor(s), _values));
    }
    return out;
  }

  String? _err(String name, [Map<String, String>? m]) {
    final step = name == 'customer' ? 0 : name.startsWith('qline-') || name == 'lines' ? 1 : name == 'revision_note' ? 3 : _stepOf(name);
    if (!_shownErrors.contains(step)) return null;
    return (m ?? _missing[step])[name];
  }

  Future<void> _revealStep(int step, Map<String, String> miss) async {
    setState(() {
      _shownErrors.add(step);
      if (_step != step) _go(step, validate: false);
    });
    HapticFeedback.heavyImpact();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || miss.isEmpty) return;
    await _anchors.reveal(miss.keys.first, miss.keys);
  }

  void _go(int step, {bool validate = true}) {
    _step = step;
    if (step > _maxStep) _maxStep = step;
    _scheduleDraft();
  }

  Future<void> _next() async {
    final miss = _missing[_step];
    if (miss.isNotEmpty) {
      await _revealStep(_step, miss);
      return;
    }
    setState(() => _go(_step + 1));
  }

  /// True when every step is complete; else jumps to the first gap.
  Future<bool> _validateAll() async {
    final m = _missing;
    for (var s = 0; s < m.length; s++) {
      if (m[s].isNotEmpty) {
        await _revealStep(s, m[s]);
        return false;
      }
    }
    return true;
  }

  void _snack(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(text))));
  }

  // ────────────────────────────────────────────────────────────── payload

  static const _textCols = ['sample_text', 'terms_conditions', 'quote_termcondition', 'qline_remark_before', 'qline_remark_after'];
  static const _idCols = {'related_account_id', 'related_contact_id', 'related_lead_id', 'smownerid', 'template_id', 'related_deal_id'};

  Object? _wire(String name, Object? v) {
    var u = unwrapFieldValue(v);
    if (u is String && u.trim().isEmpty) return null;
    if (_idCols.contains(name) && u != null) u = int.tryParse('$u') ?? u;
    return u;
  }

  /// Header fields for `/quotation/save` (`fields`) — same keys as the web form.
  Map<String, dynamic> buildFieldsPayload() {
    final out = <String, dynamic>{};
    // Duplicate / revise / prefilled create: carry the copied columns the form does not show (web sends the whole copy).
    if (_mode != DocFormMode.edit) {
      for (final e in _values.entries) {
        if (e.key.startsWith('_') || e.key == 'revision_note') continue;
        if (isNotAskedField('quotation', e.key) && !const {'related_deal_id', 'notes', 'terms', 'description', 'currency', 'sample_text', 'qline_remark_before', 'qline_remark_after'}.contains(e.key)) continue;
        if (_schema.hides(e.key) || _schema.locks(e.key)) continue;
        final w = _wire(e.key, e.value);
        if (w == null || w is Map || w is List) continue;
        out[e.key] = w;
      }
    }
    for (final name in kCoreFieldStep['quotation']!.keys) {
      if (!_schema.editable(name) || !_values.containsKey(name)) continue;
      final w = _wire(name, _values[name]);
      if (w == null && _mode != DocFormMode.edit) continue;
      out[name] = w;
    }
    for (final c in _textCols) {
      if (_values.containsKey(c) && _schema.editable(c)) out[c] = _values[c] ?? '';
    }
    out.addAll(collectEntityPayload([for (final e in _schema.extra) e.field], _values, currentRow: _source, module: 'quotation'));
    final ht = '${_values['header_discount_type'] ?? 'none'}';
    final hv = qNum(_values['header_discount_value']);
    out['header_discount_type'] = hv > 0 && (ht == 'percent' || ht == 'amount') ? ht : 'none';
    out['header_discount_value'] = hv > 0 ? hv : 0;
    out['tax_type'] = '${_values['tax_type'] ?? ''}'.isEmpty ? 'exclude' : _values['tax_type'];
    final rate = _values['tax_rate'];
    out['tax_rate'] = rate == null || '$rate'.trim().isEmpty ? 7 : qNum(rate);
    out['template_key'] = normLayout(_values['template_key']);
    out['template_id'] = _wire('template_id', _values['template_id']);
    final opts = _values['document_options'];
    out['document_options'] = opts is Map ? Map<String, dynamic>.from(opts) : <String, dynamic>{};
    dualWriteSalesText(out);
    for (final k in const ['subtotal', 'discount_total', 'tax_total', 'grand_total', 'quotation_status', 'offer_status', 'quotation_no']) {
      out.remove(k);
    }
    return out;
  }

  List<Map<String, dynamic>> buildLinesPayload() => quotationLinesPayload(_lines);

  /// Save (create / update / revise). The record id, or null on failure.
  Future<String?> _persist() async {
    final api = _api;
    final businessId = context.read<AppConfig>().session.businessId;
    try {
      final fields = buildFieldsPayload();
      final lines = buildLinesPayload();
      Map<String, dynamic> r;
      if (_isRevise) {
        if (_savedId != null) return _savedId;
        r = await api.reviseQuotationWith(widget.recordId!, fields: fields, lines: lines, note: '${_values['revision_note'] ?? ''}');
      } else {
        r = await api.saveQuotation(id: _savedId, fields: fields, lines: lines);
      }
      final id = '${r['id'] ?? (r['quotation'] is Map ? r['quotation']['id'] : '') ?? ''}';
      if (id.isEmpty || id == 'null') throw StateError(tr('บันทึกไม่สำเร็จ'));
      final row = r['quotation'] is Map ? Map<String, dynamic>.from(r['quotation']) : <String, dynamic>{'id': id, ...?_savedRow, 'quotation_no': r['quotation_no'] ?? _savedRow?['quotation_no']};
      final firstSave = _savedId == null;
      if (!mounted) return id;
      setState(() {
        _savedId = id;
        _savedRow = {...row, 'id': id, 'modifiedtime': row['modifiedtime'] ?? DateTime.now().toIso8601String()};
        _dirtySinceSave = false;
      });
      if (firstSave) {
        // The work now lives on the server: the "new" draft is done; later edits are drafts of this record.
        final old = _draftKey;
        if (old != null) await DocFormDraftStore.clear(old);
        _draftKey = _isRevise ? null : DocFormDraftStore.key(businessId: businessId, module: 'quotation', record: id);
      }
      _baseline = _snapshot();
      if (_draftKey != null) await DocFormDraftStore.clear(_draftKey!);
      return id;
    } catch (e) {
      if (mounted) _snack(_errorText(e));
      return null;
    }
  }

  String _errorText(Object e) => e is StateError ? e.message : tr(formatApiError(e));

  Future<void> _savePreview() async {
    if (!await _validateAll()) return;
    setState(() => _busy = 'preview');
    await _persist();
    if (mounted) setState(() => _busy = null);
  }

  /// [then]: 'approval' | 'email' | null.
  Future<void> _finish({String? then}) async {
    if (_locked) return;
    if (!await _validateAll()) return;
    setState(() => _busy = then ?? 'save');
    final id = (_savedId != null && !_dirtySinceSave && !_isRevise) ? _savedId : await _persist();
    if (!mounted) return;
    if (id == null) {
      setState(() => _busy = null);
      return;
    }
    final api = _api;
    final no = '${_savedRow?['quotation_no'] ?? ''}';
    try {
      if (then == 'approval') {
        final ctrl = JourneyController(api: api, module: 'quotation', id: id);
        try {
          ctrl.qtSettings = await api.getQuotationSettings();
        } catch (_) {}
        if (!mounted) return;
        final levels = await showSubmitApprovalSheet(context, ctrl: ctrl, row: _savedRow, onSubmit: (l) => api.submitQuotationApprovalLevels(id, l));
        if (levels != null) {
          HapticFeedback.mediumImpact();
          _snack('บันทึกและส่งขออนุมัติแล้ว');
        }
      } else if (then == 'email') {
        if (mounted) await showDocEmailSheet(context, kind: 'quotation', id: id, docNo: no.isEmpty ? null : no);
      }
    } catch (e) {
      _snack(_errorText(e));
    }
    if (!mounted) return;
    setState(() => _busy = null);
    _close({'id': id, 'quotation_no': no, if (_isRevise) 'revision_no': _revNo});
  }

  void _close(Map<String, dynamic>? result) {
    _draftTimer?.cancel();
    _closing = true;
    if (widget.onFinished != null) {
      widget.onFinished!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  bool _closing = false;

  void _popped() {
    if (_closing) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final kept = _snapshot() != _baseline && !_locked;
    flushDraft();
    if (kept) messenger?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('เก็บร่างไว้ในเครื่องแล้ว — เปิดฟอร์มนี้อีกครั้งเพื่อทำต่อ'))));
  }

  Future<void> _leave() async {
    await flushDraft();
    if (!mounted) return;
    if (_snapshot() != _baseline && !_locked) _snack('เก็บร่างไว้ในเครื่องแล้ว — เปิดฟอร์มนี้อีกครั้งเพื่อทำต่อ');
    _close(_savedId != null && _mode != DocFormMode.edit ? {'id': _savedId, 'quotation_no': _savedRow?['quotation_no'], 'draft': true} : null);
  }

  // ───────────────────────────────────────────────────────────────── build

  String get _title => switch (_mode) {
        DocFormMode.create => _savedId == null ? 'สร้างใบเสนอราคา' : 'ใบเสนอราคา (ร่าง)',
        DocFormMode.edit => 'แก้ไขใบเสนอราคา',
        DocFormMode.duplicate => 'ทำซ้ำใบเสนอราคา',
        DocFormMode.revise => 'ฉบับแก้ไข R$_revNo',
      };

  bool _canOpen(int i) => _mode != DocFormMode.create || i <= _maxStep || _savedId != null;

  @override
  Widget build(BuildContext context) {
    final missing = _loading ? const <Map<String, String>>[] : _missing;
    // Warn on a step only once it matters: left behind, checked, or (edit /
    // copy / revise) a prefilled step other than the current one.
    bool flag(int i) => i < _maxStep || _shownErrors.contains(i) || (_mode != DocFormMode.create && i != _step);
    return PopScope(
      // Back / swipe leaves at once; unsaved work stays as a local draft.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _popped();
      },
      child: DocStepShell(
        title: _title,
        subtitle: _subtitle,
        steps: _steps,
        current: _step,
        missing: [for (var i = 0; i < missing.length; i++) flag(i) ? missing[i].length : 0],
        complete: [
          for (var i = 0; i < missing.length; i++) missing[i].isEmpty && (i < _maxStep || _mode != DocFormMode.create) && (i < _steps.length - 1 || _isRevise),
        ],
        canOpen: _canOpen,
        onStep: (i) => setState(() => _go(i)),
        loading: _loading,
        embedded: widget.embedded,
        onClose: _leave,
        banners: _loading ? const [] : _banners(),
        body: _loading ? const SizedBox.shrink() : _loadError != null ? _errorBody() : _body(missing),
        bottom: _loading || _loadError != null ? const SizedBox.shrink() : _bottom(missing),
        side: _loading || _loadError != null ? null : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _summaryCards()),
      ),
    );
  }

  String? get _subtitle {
    if (_mode == DocFormMode.edit || _savedId != null) return '${_savedRow?['quotation_no'] ?? _source['quotation_no'] ?? ''}';
    if (_mode == DocFormMode.duplicate) return '${tr('จาก')} ${_source['quotation_no'] ?? ''}';
    if (_isRevise) return revisionNumberPreview(_source, _revNo);
    return null;
  }

  Widget _errorBody() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(formatApiError(_loadError!)), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _close(null), child: Text(tr('กลับ'))),
          ]),
        ),
      );

  List<Widget> _banners() {
    final cs = Theme.of(context).colorScheme;
    return [
      if (_isRevise)
        DocBanner(
          key: const ValueKey('docform-revise-banner'),
          icon: NxI.pencilSimple,
          color: const Color(0xFFD97706),
          title: 'ฉบับแก้ไข R$_revNo',
          text: 'ของ ${_source['quotation_no'] ?? ''} — บันทึกแล้วได้เลข ${revisionNumberPreview(_source, _revNo)} สถานะ "เปิดใบเสนอราคา" ฉบับเดิมเป็น "เปลี่ยนแปลงใบเสนอราคา" และต้องขออนุมัติใหม่',
        ),
      if (_mode == DocFormMode.duplicate)
        DocBanner(
          key: const ValueKey('docform-duplicate-banner'),
          icon: NxI.copySimple,
          title: 'สำเนาจาก ${_source['quotation_no'] ?? ''}',
          text: 'ใบใหม่ เลขใหม่ ลงวันที่วันนี้ — ลูกค้า รายการ และเงื่อนไขคัดลอกมาให้แล้ว แก้ได้ทุกขั้น',
        ),
      if (_mode == DocFormMode.edit && !_locked)
        DocBanner(
          key: const ValueKey('docform-edit-banner'),
          icon: NxI.pencilSimple,
          title: 'แก้ไข ${_source['quotation_no'] ?? ''}',
          text: 'บันทึกทับใบเดิม (เลขเดิม) — ถ้าส่งให้ลูกค้าแล้วและต้องการเก็บประวัติ ใช้ "ฉบับแก้ไข (Revise)"',
        ),
      if (_locked && _lockReason != null)
        DocBanner(key: const ValueKey('docform-locked'), icon: NxI.lock, color: cs.error, text: _lockReason!),
    ];
  }

  Widget _body(List<Map<String, String>> missing) {
    const pad = 16.0;
    final children = switch (_step) {
      0 => _customerStep(missing[0]),
      1 => _linesStep(missing[1]),
      2 => _termsStep(missing[2]),
      _ => _reviewStep(missing[3]),
    };
    // One scroll view with a plain column: fields keep their state (and GlobalKeys) when rows above them come and go.
    return SingleChildScrollView(
      key: ValueKey('docform-body-$_step'),
      padding: const EdgeInsets.fromLTRB(pad, 4, pad, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // What is still missing on this step (no snackbar over the buttons).
        if (_shownErrors.contains(_step) && missing[_step].isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              key: const ValueKey('docform-missing-banner'),
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _anchors.reveal(missing[_step].keys.first, missing[_step].keys),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(NxI.warningCircle, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('ยังขาด ${missing[_step].length} ช่องในขั้นนี้ — แตะเพื่อไปช่องแรก'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ...children,
        ..._extraGroups(_step, missing[_step]),
      ]),
    );
  }

  // Shared field helpers ------------------------------------------------------

  /// [fixedLabel]: the form's own wording (the schema label may be a column
  /// note such as "ค่าส่วนลดหัวบิล" or "เงื่อนไข (HTML)").
  Widget _field(
    String name,
    FieldUiType type,
    String label, {
    String? hint,
    List<NxPickOption> options = const [],
    bool required = false,
    ValueChanged<dynamic>? onChanged,
    Map<String, String>? miss,
    bool fixedLabel = false,
    double gap = 16,
  }) {
    if (_schema.hides(name)) return const SizedBox.shrink();
    return _anchors.wrap(
      name,
      Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: NxFormField(
          uiType: type,
          label: fixedLabel ? label : cleanFieldLabel(_schema.labelOf(name, label)),
          name: name,
          value: _values[name],
          options: options,
          hint: hint,
          required: required || _schema.requires(name),
          readOnly: _locked || _schema.locks(name),
          errorText: trn(_err(name, miss)),
          host: _host,
          onChanged: onChanged ?? (v) => _set(name, v),
        ),
      ),
    );
  }

  List<Widget> _extraGroups(int step, Map<String, String> miss) {
    return [
      for (final g in _schema.groupsFor(step))
        DocSectionCard(
          key: ValueKey('docform-extra-$step-$g'),
          title: g,
          icon: NxI.note,
          color: const Color(0xFF64748B),
          child: NxEntityForm(
            key: _anchors.formKey('$step:$g'),
            fields: _schema.extraFor(step, group: g),
            values: _values,
            picklists: _schema.picklists,
            api: _api,
            module: 'quotation',
            enabled: !_locked,
            errors: _shownErrors.contains(step) ? miss : const {},
            onChanged: _set,
          ),
        ),
    ];
  }

  // Step 1: customer ------------------------------------------------------------

  List<String> get _customerModules {
    final s = context.read<AppConfig>().session;
    final m = [for (final x in const ['account', 'contact', 'lead']) if (MenuAccess.allow(s, EntityModules.menuKeyOf(x))) x];
    return m.isEmpty ? const ['account', 'contact'] : m;
  }

  bool get _hasCustomer =>
      !isBlankValue(_values['related_account_id']) ||
      !isBlankValue(_values['related_contact_id']) ||
      !isBlankValue(_values['related_lead_id']) ||
      !isBlankValue(_values['customer_name']);

  Future<void> _openCustomerPicker() async {
    final s = context.read<AppConfig>().session;
    final picked = await showCustomerPicker(context, api: _api, modules: _customerModules, userId: s.userId, businessId: s.businessId);
    if (picked == null || !mounted) return;
    await _pickCustomer(picked.module, picked.row);
  }

  Future<void> _openContactPicker() async {
    final acc = '${unwrapFieldValue(_values['related_account_id']) ?? ''}';
    final picked = await showContactPicker(
      context,
      api: _api,
      accountId: acc.isEmpty || acc == 'null' ? null : acc,
      accountName: '${_values['customer_name'] ?? ''}'.trim().isEmpty ? null : '${_values['customer_name']}',
      selectedId: isBlankValue(_values['related_contact_id']) ? null : '${unwrapFieldValue(_values['related_contact_id'])}',
    );
    if (picked == null || !mounted) return;
    if (picked.isNone) {
      _patch({'related_contact_id': null, 'contact_name': ''});
      return;
    }
    await _pickCustomer('contact', picked.row);
  }

  Future<void> _pickCustomer(String module, Map<String, dynamic> hit) async {
    final api = _api;
    var row = hit;
    try {
      final full = await api.getEntity(module, '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    HapticFeedback.selectionClick();
    switch (module) {
      case 'account':
        _patch({...quotationAccountPatch(row, _values), 'related_lead_id': null});
        _customerKind = 'account';
        _loadAccountContacts('${row['id']}');
      case 'contact':
        _patch(quotationContactPatch(row, _values));
        if (_customerKind.isEmpty || _customerKind == 'lead') _customerKind = 'contact';
        final acc = contactAccountId(row);
        if (isBlankValue(_values['related_account_id']) && acc != null) {
          try {
            final a = await api.getEntity('account', acc);
            if (mounted && isBlankValue(_values['related_account_id']) && a.isNotEmpty) {
              _patch(quotationAccountPatch({...a, 'id': a['id'] ?? acc}, _values));
              _customerKind = 'account';
              _loadAccountContacts(acc);
            }
          } catch (_) {}
        }
        if (isBlankValue(_values['customer_name'])) _patch({'customer_name': _values['contact_name']});
      case 'lead':
        _patch({...quotationLeadPatch(row, _values), 'related_account_id': null, 'related_contact_id': null});
        _customerKind = 'lead';
    }
    if (!mounted) return;
    setState(() {
      _detailsOpen = false;
      _manualCustomer = false;
    });
  }

  Future<void> _loadAccountContacts(String accountId) async {
    try {
      final rows = await _api.getAccountContacts(accountId);
      if (mounted) setState(() => _accountContacts = rows);
    } catch (_) {}
  }

  static const _detailFields = ['customer_name', 'contact_name', 'customer_address', 'customer_taxid', 'customer_phone', 'customer_mobile', 'customer_email'];

  List<Widget> _customerStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final err = _err('customer', miss);
    final lockedCustomer = _locked || _schema.locks('related_account_id');
    final showDetails = _hasCustomer || _manualCustomer;
    final detailErr = _shownErrors.contains(0) && _detailFields.any(miss.containsKey);
    final open = _detailsOpen || (_manualCustomer && !_hasCustomer) || detailErr;
    final contactAllowed = _customerModules.contains('contact') && !_schema.hides('related_contact_id');
    final contactName = '${_values['contact_name'] ?? ''}'.trim();
    return [
      DocSectionCard(
        title: 'ลูกค้า',
        icon: NxI.buildings,
        child: _anchors.wrap(
          'customer',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_hasCustomer)
              _CustomerCard(
                values: _values,
                kind: _customerKind,
                locked: lockedCustomer,
                onChange: _openCustomerPicker,
                onEditDetails: () => setState(() => _detailsOpen = !open),
                detailsOpen: open,
                onClear: () {
                  _patch(Map<String, dynamic>.from(kQuotationClearCustomer));
                  setState(() {
                    _customerKind = '';
                    _accountContacts = const [];
                    _detailsOpen = false;
                    _manualCustomer = false;
                  });
                },
              )
            else ...[
              _PickTile(
                key: const ValueKey('qt-customer-pick'),
                icon: NxI.magnifyingGlass,
                title: 'เลือกลูกค้า',
                subtitle: 'ค้นหาบัญชีลูกค้า ผู้ติดต่อ หรือผู้มุ่งหวัง',
                error: err != null,
                onTap: lockedCustomer ? null : _openCustomerPicker,
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(tr(err), key: const ValueKey('docform-customer-error'), style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              if (!lockedCustomer && !_manualCustomer)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('qt-customer-manual'),
                    onPressed: () => setState(() => _manualCustomer = true),
                    icon: const Icon(NxI.pencilSimple, size: 16),
                    label: Text(tr('ไม่มีในระบบ? พิมพ์ชื่อลูกค้าเอง')),
                  ),
                ),
            ],
            if (_hasCustomer && contactAllowed) ...[
              const SizedBox(height: 10),
              _PickRow(
                key: const ValueKey('qt-contact-pick'),
                icon: NxI.addressBook,
                label: 'ผู้ติดต่อ',
                value: contactName.isEmpty ? tr('ไม่ระบุ') : contactName,
                valueKey: const ValueKey('qt-contact-value'),
                muted: contactName.isEmpty,
                hint: _customerKind == 'account' && _accountContacts.isNotEmpty ? tr('เลือกจาก ${_accountContacts.length} คนของลูกค้านี้') : null,
                onTap: _locked || _schema.locks('related_contact_id') ? null : _openContactPicker,
              ),
            ],
          ]),
        ),
      ),
      if (showDetails)
        _Collapsible(
          key: const ValueKey('qt-details'),
          toggleKey: const ValueKey('qt-details-toggle'),
          title: 'รายละเอียดลูกค้าบนเอกสาร',
          icon: NxI.idCard,
          color: const Color(0xFF8B5CF6),
          summary: _manualCustomer && !_hasCustomer ? 'ชื่อและที่อยู่ที่จะแสดงบนใบเสนอราคา' : 'เติมจากลูกค้าที่เลือกแล้ว — แตะเพื่อแก้เฉพาะใบนี้',
          open: open,
          onToggle: () => setState(() => _detailsOpen = !open),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('customer_name', FieldUiType.text, 'ชื่อลูกค้า', miss: miss, fixedLabel: true),
            _field('contact_name', FieldUiType.text, 'ชื่อผู้ติดต่อ', miss: miss, fixedLabel: true),
            _field('customer_address', FieldUiType.address, 'ที่อยู่', miss: miss, fixedLabel: true),
            _field('customer_taxid', FieldUiType.taxId, 'เลขประจำตัวผู้เสียภาษี', miss: miss, fixedLabel: true),
            _field('customer_phone', FieldUiType.phone, 'โทรศัพท์', miss: miss, fixedLabel: true),
            _field('customer_mobile', FieldUiType.phone, 'มือถือ', miss: miss, fixedLabel: true),
            _field('customer_email', FieldUiType.email, 'อีเมล', miss: miss, fixedLabel: true),
          ]),
        ),
      DocSectionCard(
        title: 'ใบเสนอราคา',
        icon: NxI.receipt,
        color: const Color(0xFFF97316),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('title_th', FieldUiType.text, 'ชื่อเรื่อง', hint: 'เช่น ติดตั้งระบบกล้อง อาคาร A', miss: miss, fixedLabel: true),
          _field('smownerid', FieldUiType.owner, 'ผู้รับผิดชอบ / ผู้เสนอราคา', miss: miss, fixedLabel: true, gap: 0),
        ]),
      ),
    ];
  }

  // Step 2: lines --------------------------------------------------------------

  int _lineSeq = 0;

  /// Catalog lines whose name is being edited (by line key).
  final Set<Object?> _editingNames = {};

  /// A stable key per line (cards keep their fields while lines move).
  void _keyLines() {
    for (final l in _lines) {
      if (l['_k'] == null) l['_k'] = ++_lineSeq;
    }
  }

  Map<String, dynamic> _newLine(Map<String, dynamic> l) => {...l, '_k': ++_lineSeq};

  List<String> get _catalogModules {
    final s = context.read<AppConfig>().session;
    final m = [for (final x in const ['product', 'service']) if (MenuAccess.allow(s, EntityModules.menuKeyOf(x))) x];
    return m.isEmpty ? const ['product', 'service'] : m;
  }

  Future<void> _openCatalog({String initialQuery = ''}) async {
    final r = await showCatalogPicker(context, api: _api, modules: _catalogModules, initialQuery: initialQuery, th: !L10n.isEn);
    if (r == null || !mounted) return;
    if (r.freeLine) {
      _addFreeLine();
      return;
    }
    if (r.items.isEmpty) return;
    final rows = await Future.wait([
      for (final it in r.items)
        _api.getEntity(it.module, '${it.row['id']}').then((full) => full.isEmpty ? it.row : {...it.row, ...full}).catchError((_) => it.row),
    ]);
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      for (var i = 0; i < r.items.length; i++) {
        final it = r.items[i];
        _lines.add(_newLine({...lineFromCatalog(rows[i], it.module, taxRate: _values['tax_rate'], th: !L10n.isEn), 'quantity': _trimNum(it.qty)}));
      }
    });
    _touched();
  }

  Future<void> _addCatalog(String module, Map<String, dynamic> hit) async {
    var row = hit;
    try {
      final full = await _api.getEntity(module, '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _lines.add(_newLine(lineFromCatalog(row, module, taxRate: _values['tax_rate'], th: !L10n.isEn))));
    _touched();
  }

  /// Scan on the step itself: one exact product → added; else the picker with the code.
  Future<void> _scanToLine() async {
    final code = await scanProductBarcode(context);
    if (code == null || code.trim().isEmpty || !mounted) return;
    try {
      final page = await _api.searchPicker('product', q: code.trim(), limit: 5);
      if (!mounted) return;
      if (page.items.length == 1) {
        await _addCatalog('product', page.items.first);
        return;
      }
    } catch (_) {}
    if (mounted) await _openCatalog(initialQuery: code.trim());
  }

  void _addFreeLine() {
    setState(() => _lines.add(_newLine(blankQuotationLine(taxRate: _values['tax_rate']))));
    _touched();
  }

  void _setLine(int i, Map<String, dynamic> patch) {
    setState(() => _lines[i] = {..._lines[i], ...patch});
    _touched();
  }

  String _lineName(Map<String, dynamic> l) {
    final d = '${l['description'] ?? ''}'.trim();
    return d.isEmpty ? tr('รายการไม่มีชื่อ') : d;
  }

  Future<bool> _confirmRemove(int i) => showDeleteConfirm(
        context,
        name: _lineName(_lines[i]),
        title: tr('เอารายการนี้ออก?'),
        loses: ['${_lineName(_lines[i])} · ฿${formatMoney(lineAmount(_lines[i], discountMode: _discountMode))}'],
        note: null,
        confirmLabel: 'เอาออก',
      );

  void _removeLine(int i) {
    setState(() => _lines.removeAt(i));
    _touched();
  }

  void _moveLine(int from, int to) {
    if (to < 0 || to >= _lines.length || from == to) return;
    setState(() {
      final l = _lines.removeAt(from);
      _lines.insert(to, l);
    });
    _touched();
  }

  Future<void> _lineMenu(int i) async {
    HapticFeedback.mediumImpact();
    final a = await showAppBottomSheet<String>(
      context: context,
      title: _lineName(_lines[i]),
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          if (i > 0) ListTile(key: const ValueKey('qline-menu-up'), leading: const Icon(NxI.caretUp), title: Text(tr('ย้ายขึ้น')), onTap: () => Navigator.pop(ctx, 'up')),
          if (i < _lines.length - 1)
            ListTile(key: const ValueKey('qline-menu-down'), leading: const Icon(NxI.caretDown), title: Text(tr('ย้ายลง')), onTap: () => Navigator.pop(ctx, 'down')),
          ListTile(key: const ValueKey('qline-menu-copy'), leading: const Icon(NxI.copySimple), title: Text(tr('ทำซ้ำรายการนี้')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(
            key: const ValueKey('qline-menu-remove'),
            leading: const Icon(NxI.trash, color: kNxDangerRed),
            title: Text(tr('เอาออก'), style: const TextStyle(color: kNxDangerRed, fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'up':
        _moveLine(i, i - 1);
      case 'down':
        _moveLine(i, i + 1);
      case 'copy':
        setState(() => _lines.insert(i + 1, _newLine(Map<String, dynamic>.from(_lines[i])..remove('id'))));
        _touched();
      case 'remove':
        if (await _confirmRemove(i) && mounted) _removeLine(i);
    }
  }

  List<Widget> _linesStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final diff = _isRevise ? diffRevisionLines(_sourceLines, _lines) : null;
    final err = _err('lines', miss);
    final t = _totals;
    final percent = _values['header_discount_type'] == 'percent';
    final count = _lines.where((l) => !isBlankQuotationLine(l)).length;
    _keyLines();
    return [
      if (!_locked)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: FilledButton.icon(
                  key: const ValueKey('qt-add-catalog'),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () => _openCatalog(),
                  icon: const Icon(NxI.magnifyingGlass, size: 20),
                  label: Text(tr('ค้นหาสินค้า / บริการ'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              width: 52,
              child: IconButton.filledTonal(
                key: const ValueKey('qt-scan'),
                tooltip: tr('สแกนบาร์โค้ด'),
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: _scanToLine,
                icon: const Icon(NxI.scanLine),
              ),
            ),
          ]),
        ),
      _anchors.wrap(
        'lines',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(tr(err), key: const ValueKey('docform-lines-error'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w700)),
            ),
          if (_lines.isEmpty)
            Container(
              key: const ValueKey('qt-lines-empty'),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: (err != null ? cs.error : cs.outlineVariant).withValues(alpha: 0.6)),
              ),
              child: Column(children: [
                Icon(NxI.package, size: 32, color: cs.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(tr('ยังไม่มีรายการ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tr('ค้นหาหรือสแกนสินค้า เลือกได้หลายรายการพร้อมจำนวน'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            )
          else ...[
            if (!_locked)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  tr('ปัดซ้ายเพื่อเอาออก · กดค้างเพื่อย้าย / ทำซ้ำ'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ReorderableListView(
              key: const ValueKey('qt-lines'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 6, borderRadius: BorderRadius.circular(20), child: child),
              onReorderItem: _moveLine,
              children: [for (var i = 0; i < _lines.length; i++) _lineCard(i, diff?.changes[i], miss)],
            ),
          ],
          if (!_locked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('qt-add-text-line'),
                onPressed: _addFreeLine,
                icon: const Icon(NxI.plus, size: 18),
                label: Text(tr('เพิ่มบรรทัดพิมพ์เอง')),
              ),
            ),
          if (diff != null && diff.removed.isNotEmpty)
            DocBanner(
              key: const ValueKey('qt-removed-lines'),
              icon: NxI.trash,
              color: cs.error,
              text: 'เอาออกจากฉบับเดิม ${diff.removed.length} รายการ: ${diff.removed.map((l) => '${l['description'] ?? ''}').join(', ')}',
            ),
        ]),
      ),
      const SizedBox(height: 8),
      DocSectionCard(
        title: 'ส่วนลดท้ายบิล',
        subtitle: 'หักจากยอดรวมทุกรายการ ก่อนคิด VAT',
        icon: NxI.tag,
        color: const Color(0xFFDB2777),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: _field('header_discount_value', FieldUiType.number, percent ? 'ส่วนลดท้ายบิล (%)' : 'ส่วนลดท้ายบิล (บาท)', miss: miss, fixedLabel: true, gap: 0, onChanged: (v) {
                final ty = '${_values['header_discount_type'] ?? 'none'}';
                _patch({'header_discount_value': v, if (ty != 'percent' && ty != 'amount') 'header_discount_type': 'amount'});
              }),
            ),
            const SizedBox(width: 8),
            NxDiscountTypeToggle(
              key: const ValueKey('header-discount-type'),
              percent: percent,
              onChanged: _locked || !_schema.editable('header_discount_type') ? null : (p) => _set('header_discount_type', p ? 'percent' : 'amount'),
            ),
          ]),
          if (t.billDiscountAmount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                tr('หักท้ายบิล −฿${formatMoney(t.billDiscountAmount)}'),
                key: const ValueKey('qt-bill-discount-amount'),
                style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFDB2777), fontWeight: FontWeight.w700),
              ),
            ),
        ]),
      ),
      if (count > 0) _TotalsCard(totals: t, count: count, keyPrefix: 'qt-lines-total'),
    ];
  }

  Widget _lineCard(int i, RevisionLineChange? change, Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = _lines[i];
    final percent = lineDiscountType(l) == 'percent';
    final amounts = computeLineAmounts(l, discountMode: _discountMode);
    final tint = switch (change) {
      RevisionLineChange.added => const Color(0xFF16A34A),
      RevisionLineChange.changed => const Color(0xFFD97706),
      _ => null,
    };
    final kind = '${l['line_type'] ?? 'text'}';
    final fromCatalog = !isBlankValue(l['product_id']) || !isBlankValue(l['service_id']);
    final kindColor = kind == 'product' ? const Color(0xFF6366F1) : kind == 'service' ? const Color(0xFFDB2777) : cs.onSurfaceVariant;
    final qty = qNum(l['quantity']);
    final meta = [
      if ('${l['unit'] ?? ''}'.isNotEmpty) '${tr('หน่วย')}: ${l['unit']}',
      if ('${l['line_comment'] ?? ''}'.isNotEmpty) '${l['line_comment']}',
    ].join(' · ');
    final card = Container(
      key: ValueKey('qline-$i'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 14),
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.07) ?? (theme.brightness == Brightness.dark ? cs.surfaceContainerHigh : cs.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint ?? cs.outlineVariant.withValues(alpha: 0.5), width: tint == null ? 1 : 1.6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (!_locked)
            ReorderableDragStartListener(
              index: i,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 6, 6),
                child: Icon(NxI.grip, key: ValueKey('qline-$i-drag'), size: 18, color: cs.onSurfaceVariant),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: kindColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(
              '${i + 1} · ${tr(kind == 'product' ? 'สินค้า' : kind == 'service' ? 'บริการ' : 'พิมพ์เอง')}',
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: kind == 'text' ? null : kindColor),
            ),
          ),
          if (tint != null) ...[
            const SizedBox(width: 6),
            Container(
              key: ValueKey('qline-$i-change'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(tr(change == RevisionLineChange.added ? 'ใหม่' : 'แก้ไข'), style: theme.textTheme.labelSmall?.copyWith(color: tint, fontWeight: FontWeight.w800)),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('฿${formatMoney(amounts.afterDisc)}', key: ValueKey('qline-$i-amount'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          if (!_locked)
            IconButton(
              key: ValueKey('qline-$i-menu'),
              tooltip: tr('ตัวเลือกรายการ'),
              visualDensity: VisualDensity.compact,
              icon: Icon(NxI.dotsThreeVertical, size: 18, color: cs.onSurfaceVariant),
              onPressed: () => _lineMenu(i),
            )
          else
            const SizedBox(width: 6),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (fromCatalog && !_locked && !_editingNames.contains(l['_k']) && _err('qline-$i-desc', miss) == null)
              _anchors.wrap(
                'qline-$i-desc',
                InkWell(
                  key: ValueKey('qline-$i-name'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _editingNames.add(l['_k'])),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(
                          _lineName(l),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: Icon(NxI.pencilSimple, size: 16, color: cs.onSurfaceVariant, semanticLabel: tr('แก้ชื่อรายการ')),
                      ),
                    ]),
                  ),
                ),
              )
            else
            _anchors.wrap(
              'qline-$i-desc',
              NxFormField(
                uiType: FieldUiType.text,
                label: 'ชื่อรายการ',
                name: 'qline-$i-desc',
                value: l['description'],
                required: true,
                readOnly: _locked,
                errorText: trn(_err('qline-$i-desc', miss)),
                onChanged: (v) => _setLine(i, {'description': v}),
              ),
            ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                flex: 11,
                child: Row(children: [
                  _stepBtn(ValueKey('qline-$i-minus'), NxI.minus, 'ลดจำนวน', _locked || qty <= 1 ? null : () => _setLine(i, {'quantity': _trimNum(qty - 1)})),
                  const SizedBox(width: 4),
                  Expanded(
                    child: NxFormField(
                      uiType: FieldUiType.number,
                      label: 'จำนวน',
                      name: 'qline-$i-qty',
                      value: _numText(l['quantity']),
                      readOnly: _locked,
                      onChanged: (v) => _setLine(i, {'quantity': v}),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _stepBtn(ValueKey('qline-$i-plus'), NxI.plus, 'เพิ่มจำนวน', _locked ? null : () => _setLine(i, {'quantity': _trimNum(qty + 1)})),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: NxFormField(
                  uiType: FieldUiType.currency,
                  label: 'ราคา/หน่วย',
                  name: 'qline-$i-price',
                  value: _numText(l['unit_price']),
                  readOnly: _locked,
                  onChanged: (v) => _setLine(i, {'unit_price': v}),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: NxFormField(
                  uiType: FieldUiType.number,
                  label: percent ? 'ส่วนลด %' : (_discountMode == 'per_line' ? 'ส่วนลด ฿ ทั้งรายการ' : 'ส่วนลด ฿/หน่วย'),
                  name: 'qline-$i-disc',
                  value: _numText(percent ? l['discount_pct'] : l['discount_amount']),
                  readOnly: _locked,
                  onChanged: (v) => _setLine(i, percent ? {'discount_pct': v, 'discount_type': 'percent'} : {'discount_amount': v, 'discount_type': 'amount'}),
                ),
              ),
              const SizedBox(width: 8),
              NxDiscountTypeToggle(
                key: ValueKey('qline-$i-disc-type'),
                percent: percent,
                onChanged: _locked
                    ? null
                    : (p) {
                        final cur = percent ? l['discount_pct'] : l['discount_amount'];
                        _setLine(i, p ? {'discount_type': 'percent', 'discount_pct': cur, 'discount_amount': 0} : {'discount_type': 'amount', 'discount_amount': cur, 'discount_pct': 0});
                      },
              ),
            ]),
            if (amounts.gross != amounts.afterDisc)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  '${docQtyText(l['quantity'])} × ฿${formatMoney(qNum(l['unit_price']))} = ฿${formatMoney(amounts.gross)} · ${tr('ลด')} ฿${formatMoney(amounts.gross - amounts.afterDisc)}',
                  key: ValueKey('qline-$i-math'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ]),
        ),
      ]),
    );
    final key = ValueKey('qline-k-${l['_k']}');
    if (_locked) return KeyedSubtree(key: key, child: card);
    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(i),
      onDismissed: (_) => _removeLine(i),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(color: kNxDangerRed, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(NxI.trash, color: Colors.white),
          const SizedBox(width: 6),
          Text(tr('เอาออก'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      ),
      child: GestureDetector(onLongPress: () => _lineMenu(i), child: card),
    );
  }

  Object _trimNum(double v) => v == v.roundToDouble() ? v.toInt() : v;

  /// A stored number as the user would type it (`1290`, not `1290.0`).
  Object? _numText(Object? v) => v is num ? '${_trimNum(v.toDouble())}' : v;

  Widget _stepBtn(Key key, IconData icon, String tip, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      key: key,
      tooltip: tr(tip),
      onPressed: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: cs.primary.withValues(alpha: 0.12),
        foregroundColor: cs.primary,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.05),
      ),
      icon: Icon(icon, size: 18),
    );
  }

  // Step 3: terms --------------------------------------------------------------

  String _templateLabel(Object? id) {
    final s = '${unwrapFieldValue(id) ?? ''}';
    if (s.isEmpty || s == 'null') return tr(kQuotationNoTemplateLabel);
    final t = templatesOf(_ctx).where((x) => '${x['id']}' == s).firstOrNull;
    return t == null ? '#$s ${tr('(ปิดใช้งานแล้ว)')}' : quotationTemplateLabel(t, th: !L10n.isEn);
  }

  Future<void> _openTemplatePicker() async {
    final layout = normLayout(_values['template_key']);
    final cur = '${unwrapFieldValue(_values['template_id']) ?? ''}';
    final list = templatesOfLayout(templatesOf(_ctx), layout);
    final v = await showDocOptionPicker(
      context,
      title: 'หัวกระดาษ / เทมเพลต',
      keyPrefix: 'qt-template',
      selected: cur == 'null' ? '' : cur,
      options: [
        const DocOption('', kQuotationNoTemplateLabel, icon: NxI.buildings),
        for (final t in list) DocOption('${t['id']}', quotationTemplateLabel(t, th: !L10n.isEn), icon: NxI.fileText),
        if (cur.isNotEmpty && cur != 'null' && !list.any((t) => '${t['id']}' == cur)) DocOption(cur, _templateLabel(cur), icon: NxI.fileText),
      ],
    );
    if (v == null || !mounted) return;
    _set('template_id', v.isEmpty ? null : (int.tryParse(v) ?? v));
  }

  List<Widget> _termsStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final quote = parseYmd(_values['quote_date']) ?? thaiNow();
    final until = parseYmd(_values['valid_until']);
    final templates = templatesOf(_ctx);
    final layouts = layoutChoices(allowedLayoutsOf(_ctx), _values['template_key'], _mode);
    final layout = normLayout(_values['template_key']);
    final tplHidden = _schema.hides('template_key') || _schema.hides('template_id');
    final include = '${_values['tax_type'] ?? 'exclude'}' == 'include';
    final rate = resolveTaxRate(_values['tax_rate']);
    return [
      DocSectionCard(
        title: 'วันที่และการยืนราคา',
        icon: NxI.calendarBlank,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('quote_date', FieldUiType.date, 'วันที่เอกสาร', miss: miss, fixedLabel: true),
          _field('valid_until', FieldUiType.date, 'ยืนราคาถึง', miss: miss, fixedLabel: true, gap: 8),
          if (!_locked && _schema.editable('valid_until'))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in const [7, 15, 30, 60, 90])
                  ChoiceChip(
                    key: ValueKey('qt-valid-$d'),
                    label: Text(tr('$d วัน')),
                    selected: until != null && until.difference(DateTime(quote.year, quote.month, quote.day)).inDays == d,
                    onSelected: (_) {
                      _set('valid_until', addDaysYmd(ymd(quote), d));
                      if (_values.containsKey('validity_days') || _schema.has('validity_days')) _set('validity_days', d);
                    },
                  ),
              ]),
            ),
          _field('delivery_date', FieldUiType.date, 'วันส่งมอบ', miss: miss, fixedLabel: true, gap: 0),
        ]),
      ),
      DocSectionCard(
        title: 'ภาษีมูลค่าเพิ่ม (VAT)',
        icon: NxI.currencyCircleDollar,
        color: const Color(0xFF10B981),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_schema.hides('tax_type'))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SegmentedButton<String>(
                key: const ValueKey('qt-vat-mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'exclude', label: Text(tr('ราคายังไม่รวม VAT'), textAlign: TextAlign.center)),
                  ButtonSegment(value: 'include', label: Text(tr('ราคารวม VAT แล้ว'), textAlign: TextAlign.center)),
                ],
                selected: {include ? 'include' : 'exclude'},
                onSelectionChanged: _locked || _schema.locks('tax_type') ? null : (s) => _set('tax_type', s.first),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: _field('tax_rate', FieldUiType.number, 'อัตรา VAT (%)', hint: '7', miss: miss, fixedLabel: true, gap: 0)),
            if (!_locked && _schema.editable('tax_rate')) ...[
              const SizedBox(width: 8),
              for (final r in const [7, 0]) ...[
                ChoiceChip(
                  key: ValueKey('qt-vat-rate-$r'),
                  label: Text(r == 0 ? tr('ไม่มี VAT') : '$r%'),
                  selected: rate == r,
                  onSelected: (_) => _set('tax_rate', r),
                ),
                if (r != 0) const SizedBox(width: 6),
              ],
            ],
          ]),
          const SizedBox(height: 8),
          Text(
            tr(rate == 0 ? 'ใบนี้ไม่คิด VAT' : (include ? 'ราคาที่ใส่รวม VAT แล้ว — ระบบแยก VAT ออกให้' : 'VAT คิดเพิ่มจากยอดหลังส่วนลด')),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
      if (!tplHidden)
        DocSectionCard(
          title: 'รูปแบบเอกสาร',
          subtitle: 'เฉพาะที่ธุรกิจ / แพ็กเกจของคุณเปิดให้ใช้',
          icon: NxI.fileText,
          color: const Color(0xFF6366F1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_templateNotice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(tr(_templateNotice!), key: const ValueKey('qt-template-notice'), style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD97706), fontWeight: FontWeight.w600)),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in layouts)
                ChoiceChip(
                  key: ValueKey('qt-layout-$k'),
                  label: Text(quotationLayoutLabel(k, th: !L10n.isEn)),
                  selected: layout == k,
                  onSelected: _locked || layouts.length < 2 ? null : (_) => _patch({'template_key': k, 'template_id': defaultTemplateOfLayout(templates, k)}),
                ),
            ]),
            const SizedBox(height: 12),
            _PickRow(
              key: const ValueKey('qt-template-pick'),
              icon: NxI.fileText,
              label: 'หัวกระดาษ / เทมเพลต',
              value: _templateLabel(_values['template_id']),
              valueKey: const ValueKey('qt-template-value'),
              onTap: _locked || _schema.locks('template_id') ? null : _openTemplatePicker,
            ),
          ]),
        ),
      DocSectionCard(
        title: 'เงื่อนไขและท้ายเอกสาร',
        subtitle: 'แสดงบนใบเสนอราคา — จัดตัวหนา / รายการได้',
        icon: NxI.note,
        color: const Color(0xFFF59E0B),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('terms_conditions', FieldUiType.richText, 'เงื่อนไข', hint: 'เช่น ยืนราคา 30 วัน · ชำระภายใน 30 วันหลังส่งของ', miss: miss, fixedLabel: true),
          _field('quote_termcondition', FieldUiType.richText, 'ท้ายเอกสาร', hint: 'ข้อความท้ายใบเสนอราคา เช่น ขอบคุณที่ไว้วางใจ', miss: miss, fixedLabel: true, gap: 0),
        ]),
      ),
    ];
  }

  // Step 4: review --------------------------------------------------------------

  Widget _editLink(int step) => TextButton.icon(
        key: ValueKey('qt-review-edit-$step'),
        onPressed: () => setState(() => _go(step)),
        icon: const Icon(NxI.pencilSimple, size: 16),
        label: Text(tr('แก้ไข')),
      );

  String _plainText(Object? html) => '${html ?? ''}'
      .replaceAll(RegExp(r'<\s*(br|/p|/li|/div)\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n')
      .trim();

  List<Widget> _reviewStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = _id;
    final previewable = id != null && !_isRevise;
    final real = [for (final l in _lines) if (!isBlankQuotationLine(l)) l];
    final t = _totals;
    final owner = _values['smownerid'];
    final ownerName = owner is Map ? '${owner['label'] ?? ''}' : '';
    final terms = _plainText(_values['terms_conditions']);
    final footer = _plainText(_values['quote_termcondition']);
    final name = '${_values['customer_name'] ?? ''}'.trim();
    final kindLabel = kCustomerKindLabel[_customerKind] ?? 'พิมพ์เอง';
    final hd = qNum(_values['header_discount_value']);
    return [
      if (_isRevise)
        DocSectionCard(
          title: 'เหตุผลที่แก้ไข',
          icon: NxI.pencilSimple,
          color: const Color(0xFFD97706),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            () {
              final d = diffRevisionLines(_sourceLines, _lines);
              final changed = d.changes.where((c) => c == RevisionLineChange.changed).length;
              final added = d.changes.where((c) => c == RevisionLineChange.added).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  tr('เทียบกับฉบับเดิม: แก้ไข $changed · เพิ่ม $added · เอาออก ${d.removed.length} รายการ'),
                  key: const ValueKey('qt-revise-diff'),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              );
            }(),
            _field('revision_note', FieldUiType.longText, 'สิ่งที่เปลี่ยนแปลงในฉบับนี้', required: true, hint: 'เช่น ลูกค้าขอลดราคารายการ A และเพิ่มค่าขนส่ง', miss: miss, fixedLabel: true, gap: 0),
          ]),
        ),
      DocSectionCard(
        key: const ValueKey('qt-review-customer'),
        title: 'ลูกค้า',
        icon: NxI.buildings,
        trailing: _editLink(0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('ลูกค้า', name, valueKey: const ValueKey('qt-sum-customer')),
          if (name.isNotEmpty) DocKeyValue('ประเภท', tr(kindLabel)),
          if ('${_values['contact_name'] ?? ''}'.trim().isNotEmpty) DocKeyValue('ผู้ติดต่อ', '${_values['contact_name']}'),
          if ('${_values['customer_address'] ?? ''}'.trim().isNotEmpty) DocKeyValue('ที่อยู่', '${_values['customer_address']}'),
          if ('${_values['customer_taxid'] ?? ''}'.trim().isNotEmpty) DocKeyValue('เลขผู้เสียภาษี', '${_values['customer_taxid']}'),
          if ('${_values['title_th'] ?? ''}'.trim().isNotEmpty) DocKeyValue('ชื่อเรื่อง', '${_values['title_th']}'),
          if (ownerName.isNotEmpty) DocKeyValue('ผู้รับผิดชอบ', ownerName),
        ]),
      ),
      DocSectionCard(
        key: const ValueKey('qt-review-lines'),
        title: 'รายการสินค้า / บริการ',
        icon: NxI.package,
        color: const Color(0xFF6366F1),
        trailing: _editLink(1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (real.isEmpty) Text(tr('ยังไม่มีรายการ'), style: TextStyle(color: cs.error)),
          for (final l in real)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_lineName(l), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      () {
                        final a = computeLineAmounts(l, discountMode: _discountMode);
                        return [
                          '${docQtyText(l['quantity'])}${'${l['unit'] ?? ''}'.isEmpty ? '' : ' ${l['unit']}'} × ฿${formatMoney(qNum(l['unit_price']))}',
                          if (a.gross != a.afterDisc) '${tr('ลด')} ฿${formatMoney(a.gross - a.afterDisc)}',
                        ].join(' · ');
                      }(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Text('฿${formatMoney(lineAmount(l, discountMode: _discountMode))}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
          if (hd > 0) ...[
            const Divider(height: 18),
            DocKeyValue(
              'ส่วนลดท้ายบิล',
              _values['header_discount_type'] == 'percent' ? '${docQtyText(hd)}% (−฿${formatMoney(t.billDiscountAmount)})' : '−฿${formatMoney(t.billDiscountAmount)}',
            ),
          ],
        ]),
      ),
      DocSectionCard(
        key: const ValueKey('qt-review-terms'),
        title: 'เงื่อนไข',
        icon: NxI.clipboardText,
        color: const Color(0xFFF59E0B),
        trailing: _editLink(2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('วันที่เอกสาร', _dateText(_values['quote_date'])),
          DocKeyValue('ยืนราคาถึง', _dateText(_values['valid_until'])),
          if (!isBlankValue(_values['delivery_date'])) DocKeyValue('วันส่งมอบ', _dateText(_values['delivery_date'])),
          DocKeyValue(
            'VAT',
            resolveTaxRate(_values['tax_rate']) == 0 ? tr('ไม่มี VAT') : (_values['tax_type'] == 'include' ? tr('รวม VAT ${_rateText()}%') : tr('แยก VAT ${_rateText()}%')),
          ),
          DocKeyValue('รูปแบบเอกสาร', quotationLayoutLabel(normLayout(_values['template_key']), th: !L10n.isEn)),
          DocKeyValue('หัวกระดาษ', _templateLabel(_values['template_id']), valueKey: const ValueKey('qt-review-template')),
          if (terms.isNotEmpty) _reviewText('เงื่อนไข', terms),
          if (footer.isNotEmpty) _reviewText('ท้ายเอกสาร', footer),
        ]),
      ),
      _TotalsCard(totals: t, count: real.length, keyPrefix: 'qt-total'),
      DocSectionCard(
        title: 'เอกสารจริง',
        subtitle: 'แบบเดียวกับที่ลูกค้าได้รับ (ตามเทมเพลตของใบ)',
        icon: NxI.filePdf,
        color: const Color(0xFFDC2626),
        child: previewable && !_dirtySinceSave
            ? KeyedSubtree(
                key: ValueKey('qt-doc-${_savedRow?['modifiedtime']}'),
                child: RecordDocumentTab(module: 'quotation', row: _savedRow ?? {'id': id}),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  tr(_isRevise
                      ? 'เอกสารฉบับแก้ไขจะแสดงหลังกด "สร้างฉบับแก้ไข" (ฉบับเดิมจะถูกแทนที่)'
                      : id == null
                          ? 'บันทึกเป็นร่างก่อนเพื่อดูเอกสารจริง — ลูกค้ายังไม่ได้รับจนกว่าคุณจะส่ง'
                          : 'มีการแก้ไขหลังบันทึก — บันทึกเพื่อดูเอกสารล่าสุด'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (!_isRevise && !_locked) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('docform-preview-save'),
                    onPressed: _busy != null ? null : _savePreview,
                    icon: _busy == 'preview' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.eye, size: 18),
                    label: Text(tr(id == null ? 'บันทึกร่างและดูเอกสาร' : 'บันทึกและดูเอกสารล่าสุด')),
                  ),
                ],
              ]),
      ),
    ];
  }

  Widget _reviewText(String label, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(label), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ]),
    );
  }

  /// Tablet side panel: customer + totals at a glance.
  Widget _summaryCards() {
    final real = _lines.where((l) => !isBlankQuotationLine(l)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DocSectionCard(
        title: 'สรุป',
        icon: NxI.listChecks,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('ลูกค้า', '${_values['customer_name'] ?? ''}'),
          if ('${_values['contact_name'] ?? ''}'.isNotEmpty) DocKeyValue('ผู้ติดต่อ', '${_values['contact_name']}'),
          if ('${_values['title_th'] ?? ''}'.isNotEmpty) DocKeyValue('ชื่อเรื่อง', '${_values['title_th']}'),
          DocKeyValue('ยืนราคาถึง', _dateText(_values['valid_until'])),
          for (final l in real.take(6)) DocKeyValue('· ${_lineName(l)}', '฿${formatMoney(lineAmount(l, discountMode: _discountMode))}'),
        ]),
      ),
      _TotalsCard(totals: _totals, count: real.length, keyPrefix: 'qt-side-total'),
    ]);
  }

  String _rateText() {
    final r = resolveTaxRate(_values['tax_rate']);
    return r == r.roundToDouble() ? '${r.toInt()}' : '$r';
  }

  String _dateText(Object? v) {
    final d = parseYmd(v);
    return d == null ? '' : '${d.day}/${d.month}/${uiYear(d.year)}';
  }

  Widget _bottom(List<Map<String, String>> missing) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = _totals;
    final last = _step == _steps.length - 1;
    final busy = _busy != null;
    final count = _lines.where((l) => !isBlankQuotationLine(l)).length;
    final customer = '${_values['customer_name'] ?? ''}'.trim();
    final detail = count == 0
        ? tr('ยังไม่มีรายการ')
        : [
            tr('$count รายการ'),
            if (t.discountTotal > 0) '${tr('ลด')} ฿${formatMoney(t.discountTotal)}',
            if (t.taxTotal > 0) 'VAT ฿${formatMoney(t.taxTotal)}',
          ].join(' · ');
    final summary = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            customer.isEmpty ? tr('ยังไม่ได้เลือกลูกค้า') : customer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: customer.isEmpty ? cs.onSurfaceVariant : null),
          ),
          Text(detail, key: const ValueKey('docform-bar-detail'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('ยอดสุทธิ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(
          '฿${formatMoney(t.grandTotal)}',
          key: const ValueKey('docform-bar-total'),
          style: (count == 0 ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w900, color: count == 0 ? cs.onSurfaceVariant : cs.primary),
        ),
      ]),
    ]);
    Widget spin() => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    final back = _step == 0
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: OutlinedButton(
              key: const ValueKey('docform-back'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
              onPressed: busy ? null : () => setState(() => _go(_step - 1)),
              child: Icon(NxI.arrowLeft, size: 18, semanticLabel: tr('ย้อนกลับ')),
            ),
          );
    if (!last) {
      return DocBottomBar(summary: summary, actions: [
        ?back,
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: FilledButton.icon(
            key: const ValueKey('docform-next'),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: busy ? null : _next,
            icon: const Icon(NxI.arrowRight, size: 18),
            label: Text(tr('ถัดไป · ${_steps[_step + 1].title}'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ]);
    }
    final saveLabel = switch (_mode) {
      DocFormMode.edit => 'บันทึกการแก้ไข',
      DocFormMode.revise => 'สร้างฉบับแก้ไข R$_revNo',
      DocFormMode.duplicate => 'สร้างใบใหม่จากสำเนา',
      _ => _savedId == null ? 'สร้างใบเสนอราคา' : 'บันทึก',
    };
    Widget fit(String label) => FittedBox(fit: BoxFit.scaleDown, child: Text(tr(label), maxLines: 1));
    final off = busy || _locked;
    final verb = _mode == DocFormMode.edit ? 'บันทึก' : 'สร้าง';
    return DocBottomBar(
      summary: summary,
      secondary: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: OutlinedButton.icon(
              key: const ValueKey('docform-approval'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: off ? null : () => _finish(then: 'approval'),
              icon: _busy == 'approval' ? spin() : const Icon(NxI.shieldCheck, size: 16),
              label: fit('$verb + ขออนุมัติ'),
            ),
          ),
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: OutlinedButton.icon(
              key: const ValueKey('docform-email'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: off ? null : () => _finish(then: 'email'),
              icon: _busy == 'email' ? spin() : const Icon(NxI.paperPlaneTilt, size: 16),
              label: fit('$verb + ส่งอีเมล'),
            ),
          ),
        ),
      ],
      actions: [
        ?back,
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: FilledButton.icon(
            key: const ValueKey('docform-save'),
            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: off ? null : () => _finish(),
            icon: _busy == 'save' ? spin() : const Icon(NxI.checkCircle, size: 18),
            label: fit(saveLabel),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── small widgets

/// Selected customer: name + type, address, tax id, phone / e-mail, with
/// "เปลี่ยน" and "แก้รายละเอียดบนเอกสาร".
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.values,
    required this.kind,
    required this.onChange,
    required this.onClear,
    required this.onEditDetails,
    this.detailsOpen = false,
    this.locked = false,
  });
  final Map<String, dynamic> values;
  final String kind;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final VoidCallback onEditDetails;
  final bool detailsOpen;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badge = kCustomerKindLabel[kind] ?? 'พิมพ์เอง';
    String v(String k) => '${values[k] ?? ''}'.trim();
    final name = v('customer_name');
    final contacts = [v('customer_phone'), v('customer_mobile'), v('customer_email')].where((x) => x.isNotEmpty).toList();
    final lines = <(IconData, String)>[
      if (v('customer_address').isNotEmpty) (NxI.mapPin, v('customer_address')),
      if (v('customer_taxid').isNotEmpty) (NxI.idCard, '${tr('เลขผู้เสียภาษี')} ${v('customer_taxid')}'),
      if (contacts.isNotEmpty) (NxI.phone, contacts.join(' · ')),
    ];
    return Container(
      key: const ValueKey('qt-customer-card'),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.primary.withValues(alpha: 0.28))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
            child: Icon(kind == 'lead' ? NxI.userPlus : kind == 'contact' ? NxI.user : NxI.buildings, color: cs.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? tr('(ยังไม่มีชื่อบนเอกสาร)') : name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                child: Text(tr(badge), key: const ValueKey('qt-customer-kind'), style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (!locked)
            IconButton(
              key: const ValueKey('qt-customer-clear'),
              tooltip: tr('ล้างลูกค้า'),
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: Icon(NxI.x, size: 18, color: cs.onSurfaceVariant),
            ),
        ]),
        if (lines.isNotEmpty) const SizedBox(height: 8),
        for (final (icon, text) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, right: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: cs.onSurfaceVariant)),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ),
        if (!locked)
          Wrap(children: [
            TextButton.icon(key: const ValueKey('qt-customer-change'), onPressed: onChange, icon: const Icon(NxI.arrowsLeftRight, size: 16), label: Text(tr('เปลี่ยน'))),
            TextButton.icon(
              key: const ValueKey('qt-customer-edit-details'),
              onPressed: onEditDetails,
              icon: Icon(detailsOpen ? NxI.caretUp : NxI.pencilSimple, size: 16),
              label: Text(tr(detailsOpen ? 'ซ่อนรายละเอียดบนเอกสาร' : 'แก้รายละเอียดบนเอกสาร')),
            ),
          ])
        else
          const SizedBox(height: 8),
      ]),
    );
  }
}

/// Big "open the picker" tile (empty state of a pick).
class _PickTile extends StatelessWidget {
  const _PickTile({super.key, required this.icon, required this.title, required this.subtitle, this.onTap, this.error = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = error ? cs.error : cs.primary;
    return Material(
      color: c.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.withValues(alpha: 0.45), width: 1.2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle), child: Icon(icon, color: c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c)),
                Text(tr(subtitle), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(NxI.caretRight, color: c),
          ]),
        ),
      ),
    );
  }
}

/// One tappable "label / value ›" row that opens a picker.
class _PickRow extends StatelessWidget {
  const _PickRow({super.key, required this.icon, required this.label, required this.value, this.onTap, this.muted = false, this.hint, this.valueKey});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool muted;
  final String? hint;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: theme.brightness == Brightness.dark ? cs.surfaceContainerHighest.withValues(alpha: 0.45) : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(label), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text(value, key: valueKey, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: muted ? cs.onSurfaceVariant : null)),
                if (hint != null) Text(hint!, style: theme.textTheme.bodySmall?.copyWith(color: cs.primary)),
              ]),
            ),
            if (onTap != null) Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Section card whose body folds away behind a one-line summary.
class _Collapsible extends StatelessWidget {
  const _Collapsible({super.key, required this.title, required this.icon, required this.color, required this.summary, required this.open, required this.onToggle, required this.child, this.toggleKey});
  final String title;
  final IconData icon;
  final Color color;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: dark ? cs.surfaceContainerHigh : cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: toggleKey,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(tr(summary), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(NxI.caretDown, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 0), child: child),
        ]),
      ),
    );
  }
}

/// Items · subtotal · discount · before VAT · VAT · net.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.count, required this.keyPrefix});
  final QuotationTotals totals;
  final int count;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    return DocSectionCard(
      key: ValueKey(keyPrefix),
      title: 'ยอดรวม',
      icon: NxI.receipt,
      color: const Color(0xFF10B981),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DocKeyValue('จำนวนรายการ', tr('$count รายการ'), valueKey: ValueKey('$keyPrefix-count')),
        DocKeyValue('รวมเป็นเงิน', '฿${formatMoney(t.subtotal)}', valueKey: ValueKey('$keyPrefix-subtotal')),
        DocKeyValue('ส่วนลด', '฿${formatMoney(t.discountTotal)}', valueKey: ValueKey('$keyPrefix-discount')),
        DocKeyValue('ยอดก่อน VAT', '฿${formatMoney(t.priceBeforeVat)}', valueKey: ValueKey('$keyPrefix-before-vat')),
        DocKeyValue('VAT', '฿${formatMoney(t.taxTotal)}', valueKey: ValueKey('$keyPrefix-vat')),
        const Divider(height: 18),
        DocKeyValue('ยอดสุทธิ', '฿${formatMoney(t.grandTotal)}', strong: true, valueKey: ValueKey('$keyPrefix-grand')),
      ]),
    );
  }
}
