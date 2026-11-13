import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/card_layout.dart' show formatMoney;
import '../../core/doc_form/doc_form_draft.dart';
import '../../core/doc_form/doc_form_rules.dart';
import '../../core/doc_form/quotation_math.dart';
import '../../core/entity_display.dart';
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
import '../../widgets/nx_icons.dart';
import '../docs/doc_email_sheet.dart';
import '../docs/document_tab.dart';
import '../journey/journey_controller.dart';
import '../journey/quotation_journey.dart' show showSubmitApprovalSheet;
import 'barcode_scan_sheet.dart';
import 'doc_form_shell.dart';

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
  bool _editCustomer = false;

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

  String _snapshot() => jsonEncode(DocFormDraft(values: _values, lines: _lines).toJson()..remove('saved_at')..remove('step'));

  Future<void> _offerDraft() async {
    final key = _draftKey;
    if (key == null) return;
    final d = await DocFormDraftStore.read(key);
    if (d == null || !mounted) return;
    final same = jsonEncode(DocFormDraft(values: d.values, lines: d.lines).toJson()..remove('saved_at')..remove('step')) == _baseline;
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
      DocFormDraft(values: _values, lines: _lines, step: _step, extra: {'customer_kind': _customerKind}),
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
        final levels = await showSubmitApprovalSheet(context, ctrl: ctrl, row: _savedRow);
        if (levels != null) {
          await api.submitQuotationApprovalLevels(id, levels);
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
        missing: [for (final m in missing) m.length],
        canOpen: _canOpen,
        onStep: (i) => setState(() => _go(i)),
        loading: _loading,
        embedded: widget.embedded,
        onClose: _leave,
        banners: _loading ? const [] : _banners(),
        body: _loading ? const SizedBox.shrink() : _loadError != null ? _errorBody() : _body(missing),
        bottom: _loading || _loadError != null ? const SizedBox.shrink() : _bottom(missing),
        side: _loading || _loadError != null ? null : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _summaryCards(compact: true)),
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

  Widget _field(String name, FieldUiType type, String label, {String? hint, List<NxPickOption> options = const [], bool required = false, ValueChanged<dynamic>? onChanged, Map<String, String>? miss}) {
    if (_schema.hides(name)) return const SizedBox.shrink();
    return _anchors.wrap(
      name,
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NxFormField(
          uiType: type,
          label: _schema.labelOf(name, label),
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

  bool get _hasCustomer => !isBlankValue(_values['customer_name']) || !isBlankValue(_values['related_account_id']);

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
    setState(() => _editCustomer = false);
  }

  Future<void> _loadAccountContacts(String accountId) async {
    try {
      final rows = await _api.getAccountContacts(accountId);
      if (mounted) setState(() => _accountContacts = rows);
    } catch (_) {}
  }

  List<Widget> _customerStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final err = _err('customer', miss);
    return [
      DocSectionCard(
        title: 'ลูกค้า',
        subtitle: 'ค้นหาบัญชีลูกค้า ผู้ติดต่อ หรือผู้มุ่งหวังในช่องเดียว',
        icon: NxI.buildings,
        child: _anchors.wrap(
          'customer',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_hasCustomer && !_editCustomer)
              _CustomerCard(
                values: _values,
                kind: _customerKind,
                locked: _locked || _schema.locks('related_account_id'),
                onChange: () => setState(() => _editCustomer = true),
                onClear: () {
                  _patch(Map<String, dynamic>.from(kQuotationClearCustomer));
                  setState(() {
                    _customerKind = '';
                    _accountContacts = const [];
                  });
                },
              )
            else if (!_locked)
              CustomerSearchBox(
                modules: _customerModules,
                api: _api,
                onPick: _pickCustomer,
                onCancel: _hasCustomer ? () => setState(() => _editCustomer = false) : null,
              ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr(err), key: const ValueKey('docform-customer-error'), style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      if (_customerKind == 'account' && _accountContacts.isNotEmpty && !_locked)
        DocSectionCard(
          title: 'ผู้ติดต่อของลูกค้า',
          icon: NxI.addressBook,
          color: const Color(0xFF10B981),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _accountContacts.take(12))
              ChoiceChip(
                key: ValueKey('qt-contact-${c['id']}'),
                label: Text(entityTitle(c, module: 'contact')),
                selected: '${unwrapFieldValue(_values['related_contact_id']) ?? ''}' == '${c['id']}',
                onSelected: (_) => _pickCustomer('contact', c),
              ),
          ]),
        ),
      DocSectionCard(
        title: 'รายละเอียดลูกค้าบนเอกสาร',
        subtitle: 'เติมให้จากลูกค้าที่เลือก — แก้ไขได้',
        icon: NxI.idCard,
        color: const Color(0xFF8B5CF6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('customer_name', FieldUiType.text, 'ชื่อลูกค้า', miss: miss),
          _field('contact_name', FieldUiType.text, 'ผู้ติดต่อ', miss: miss),
          _field('customer_address', FieldUiType.longText, 'ที่อยู่', miss: miss),
          _field('customer_taxid', FieldUiType.taxId, 'เลขผู้เสียภาษี', miss: miss),
          _field('customer_phone', FieldUiType.phone, 'โทรศัพท์', miss: miss),
          _field('customer_mobile', FieldUiType.phone, 'มือถือ', miss: miss),
          _field('customer_email', FieldUiType.email, 'อีเมล', miss: miss),
        ]),
      ),
      DocSectionCard(
        title: 'ใบเสนอราคา',
        icon: NxI.receipt,
        color: const Color(0xFFF97316),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('title_th', FieldUiType.text, 'ชื่อเรื่อง', hint: 'เช่น ติดตั้งระบบกล้อง อาคาร A', miss: miss),
          _field('smownerid', FieldUiType.owner, 'ผู้รับผิดชอบ', miss: miss),
        ]),
      ),
    ];
  }

  // Step 2: lines --------------------------------------------------------------

  Future<void> _addCatalog(String module, Map<String, dynamic> hit) async {
    var row = hit;
    try {
      final full = await _api.getEntity(module, '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _lines.add(lineFromCatalog(row, module, taxRate: _values['tax_rate'], th: !L10n.isEn)));
    _touched();
  }

  void _setLine(int i, Map<String, dynamic> patch) {
    setState(() => _lines[i] = {..._lines[i], ...patch});
    _touched();
  }

  List<Widget> _linesStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final diff = _isRevise ? diffRevisionLines(_sourceLines, _lines) : null;
    final err = _err('lines', miss);
    return [
      if (!_locked)
        DocSectionCard(
          title: 'เพิ่มสินค้า / บริการ',
          icon: NxI.magnifyingGlass,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CatalogSearchBox(api: _api, onPick: _addCatalog),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('qt-add-text-line'),
                onPressed: () {
                  setState(() => _lines.add(blankQuotationLine(taxRate: _values['tax_rate'])));
                  _touched();
                },
                icon: const Icon(NxI.plus, size: 18),
                label: Text(tr('เพิ่มบรรทัดพิมพ์เอง')),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('ยังไม่มีรายการ — ค้นหาหรือสแกนสินค้าด้านบน'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          for (var i = 0; i < _lines.length; i++) _lineCard(i, diff?.changes[i], miss),
          if (diff != null && diff.removed.isNotEmpty)
            DocBanner(
              key: const ValueKey('qt-removed-lines'),
              icon: NxI.trash,
              color: cs.error,
              text: 'เอาออกจากฉบับเดิม ${diff.removed.length} รายการ: ${diff.removed.map((l) => '${l['description'] ?? ''}').join(', ')}',
            ),
        ]),
      ),
      DocSectionCard(
        title: 'ส่วนลดท้ายบิล',
        icon: NxI.tag,
        color: const Color(0xFFDB2777),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _field('header_discount_value', FieldUiType.number, 'ส่วนลด', miss: miss, onChanged: (v) {
              final t = '${_values['header_discount_type'] ?? 'none'}';
              _patch({'header_discount_value': v, if (t != 'percent' && t != 'amount') 'header_discount_type': 'amount'});
            }),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: NxDiscountTypeToggle(
              key: const ValueKey('header-discount-type'),
              percent: _values['header_discount_type'] == 'percent',
              onChanged: _locked || !_schema.editable('header_discount_type') ? null : (p) => _set('header_discount_type', p ? 'percent' : 'amount'),
            ),
          ),
        ]),
      ),
    ];
  }

  Widget _lineCard(int i, RevisionLineChange? change, Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = _lines[i];
    final percent = lineDiscountType(l) == 'percent';
    final amount = lineAmount(l, discountMode: _discountMode);
    final tint = switch (change) {
      RevisionLineChange.added => const Color(0xFF16A34A),
      RevisionLineChange.changed => const Color(0xFFD97706),
      _ => null,
    };
    final kind = '${l['line_type'] ?? 'text'}';
    Widget num(String key, String label, String field, {FieldUiType type = FieldUiType.number}) => Expanded(
          child: NxFormField(
            uiType: type,
            label: label,
            name: 'qline-$i-$key',
            value: l[field],
            readOnly: _locked,
            onChanged: (v) => _setLine(i, {field: v}),
          ),
        );
    return _anchors.wrap(
      'qline-$i-desc',
      Container(
        key: ValueKey('qline-$i'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
        decoration: BoxDecoration(
          color: tint?.withValues(alpha: 0.07) ?? (theme.brightness == Brightness.dark ? cs.surfaceContainerHigh : cs.surface),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tint ?? cs.outlineVariant.withValues(alpha: 0.5), width: tint == null ? 1 : 1.6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${i + 1} · ${tr(kind == 'product' ? 'สินค้า' : kind == 'service' ? 'บริการ' : 'ข้อความ')}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
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
                  child: Text('฿${formatMoney(amount)}', key: ValueKey('qline-$i-amount'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            if (!_locked)
              IconButton(
                key: ValueKey('qline-$i-remove'),
                tooltip: tr('ลบรายการ'),
                icon: Icon(NxI.trash, size: 18, color: cs.error),
                onPressed: () {
                  setState(() => _lines.removeAt(i));
                  _touched();
                },
              ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              NxFormField(
                uiType: FieldUiType.text,
                label: 'รายการ',
                name: 'qline-$i-desc',
                value: l['description'],
                required: true,
                readOnly: _locked,
                errorText: trn(_err('qline-$i-desc', miss)),
                onChanged: (v) => _setLine(i, {'description': v}),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                num('qty', 'จำนวน', 'quantity'),
                const SizedBox(width: 8),
                num('price', 'ราคา/หน่วย', 'unit_price', type: FieldUiType.currency),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: NxFormField(
                    uiType: FieldUiType.number,
                    label: percent ? 'ส่วนลด %' : (_discountMode == 'per_line' ? 'ส่วนลด ฿ (ทั้งรายการ)' : 'ส่วนลด ฿/หน่วย'),
                    name: 'qline-$i-disc',
                    value: percent ? l['discount_pct'] : l['discount_amount'],
                    readOnly: _locked,
                    onChanged: (v) => _setLine(i, percent ? {'discount_pct': v, 'discount_type': 'percent'} : {'discount_amount': v, 'discount_type': 'amount'}),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: NxDiscountTypeToggle(
                    key: ValueKey('qline-$i-disc-type'),
                    percent: percent,
                    onChanged: _locked
                        ? null
                        : (p) {
                            final cur = percent ? l['discount_pct'] : l['discount_amount'];
                            _setLine(i, p
                                ? {'discount_type': 'percent', 'discount_pct': cur, 'discount_amount': 0}
                                : {'discount_type': 'amount', 'discount_amount': cur, 'discount_pct': 0});
                          },
                  ),
                ),
              ]),
              if ('${l['unit'] ?? ''}'.isNotEmpty || '${l['line_comment'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    [if ('${l['unit'] ?? ''}'.isNotEmpty) '${tr('หน่วย')}: ${l['unit']}', if ('${l['line_comment'] ?? ''}'.isNotEmpty) '${l['line_comment']}'].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  // Step 3: terms --------------------------------------------------------------

  List<Widget> _termsStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final quote = parseYmd(_values['quote_date']) ?? thaiNow();
    final until = parseYmd(_values['valid_until']);
    final templates = templatesOf(_ctx);
    final layouts = layoutChoices(allowedLayoutsOf(_ctx), _values['template_key'], _mode);
    final layout = normLayout(_values['template_key']);
    final tplOptions = [
      for (final t in templatesOfLayout(templates, layout)) NxPickOption(value: '${t['id']}', label: '${t['name'] ?? t['code'] ?? t['id']}'),
    ];
    final tplHidden = _schema.hides('template_key') || _schema.hides('template_id');
    return [
      DocSectionCard(
        title: 'วันที่และการยืนราคา',
        icon: NxI.calendarBlank,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('quote_date', FieldUiType.date, 'วันที่เอกสาร', miss: miss),
          _field('valid_until', FieldUiType.date, 'ยืนราคาถึง', miss: miss),
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
          _field('delivery_date', FieldUiType.date, 'วันส่งมอบ', miss: miss),
        ]),
      ),
      DocSectionCard(
        title: 'ภาษีมูลค่าเพิ่ม',
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
                  ButtonSegment(value: 'exclude', label: Text(tr('แยก VAT'))),
                  ButtonSegment(value: 'include', label: Text(tr('รวม VAT แล้ว'))),
                ],
                selected: {'${_values['tax_type'] ?? 'exclude'}' == 'include' ? 'include' : 'exclude'},
                onSelectionChanged: _locked || _schema.locks('tax_type') ? null : (s) => _set('tax_type', s.first),
              ),
            ),
          _field('tax_rate', FieldUiType.number, 'อัตรา VAT (%)', hint: '7', miss: miss),
          Text(
            tr('${_values['tax_type'] == 'include' ? 'ราคาที่ใส่รวม VAT แล้ว — ระบบแยก VAT ออกให้' : 'VAT คิดเพิ่มจากยอดหลังส่วนลด'} · ${tr('ใส่ 0 = ไม่มี VAT')}'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  label: Text(tr(k == 'template2' ? 'เทมเพลต 2' : 'เทมเพลต 1')),
                  selected: layout == k,
                  onSelected: _locked || layouts.length < 2
                      ? null
                      : (_) => _patch({'template_key': k, 'template_id': defaultTemplateOfLayout(templates, k)}),
                ),
            ]),
            if (tplOptions.isNotEmpty) ...[
              const SizedBox(height: 14),
              _field('template_id', FieldUiType.picklist, 'เทมเพลต (โลโก้ / หัวกระดาษ)', options: tplOptions, miss: miss, onChanged: (v) => _set('template_id', unwrapFieldValue(v))),
            ],
          ]),
        ),
      DocSectionCard(
        title: 'เงื่อนไขและหมายเหตุ',
        icon: NxI.note,
        color: const Color(0xFFF59E0B),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('terms_conditions', FieldUiType.richText, 'เงื่อนไขและหมายเหตุ', miss: miss),
          _field('quote_termcondition', FieldUiType.richText, 'หมายเหตุท้ายเอกสาร', miss: miss),
        ]),
      ),
    ];
  }

  // Step 4: review --------------------------------------------------------------

  List<Widget> _reviewStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = _id;
    final previewable = id != null && !_isRevise;
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
            _field('revision_note', FieldUiType.longText, 'สิ่งที่เปลี่ยนแปลงในฉบับนี้', required: true, hint: 'เช่น ลูกค้าขอลดราคารายการ A และเพิ่มค่าขนส่ง', miss: miss),
          ]),
        ),
      _summaryCards(),
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
                          ? 'ต้องบันทึกเป็นร่างก่อนจึงจะดูเอกสารจริงได้ — ยังส่งให้ลูกค้าไม่ได้จนกว่าคุณจะส่ง'
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

  Widget _summaryCards({bool compact = false}) {
    final t = _totals;
    final real = _lines.where((l) => !isBlankQuotationLine(l)).toList();
    final templates = templatesOf(_ctx);
    final tpl = templates.where((x) => '${x['id']}' == '${_values['template_id'] ?? ''}').firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DocSectionCard(
        title: 'สรุป',
        icon: NxI.listChecks,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('ลูกค้า', '${_values['customer_name'] ?? ''}', valueKey: const ValueKey('qt-sum-customer')),
          if ('${_values['contact_name'] ?? ''}'.isNotEmpty) DocKeyValue('ผู้ติดต่อ', '${_values['contact_name']}'),
          if ('${_values['title_th'] ?? ''}'.isNotEmpty) DocKeyValue('ชื่อเรื่อง', '${_values['title_th']}'),
          DocKeyValue('ยืนราคาถึง', _dateText(_values['valid_until'])),
          DocKeyValue('VAT', _values['tax_type'] == 'include' ? tr('รวม VAT ${_rateText()}%') : tr('แยก VAT ${_rateText()}%')),
          DocKeyValue('รูปแบบเอกสาร', [tr(normLayout(_values['template_key']) == 'template2' ? 'เทมเพลต 2' : 'เทมเพลต 1'), if (tpl != null) '${tpl['name'] ?? ''}'].join(' · ')),
          const Divider(height: 18),
          DocKeyValue('รายการ', tr('${real.length} รายการ')),
          if (!compact)
            for (final l in real.take(6))
              DocKeyValue('· ${l['description'] ?? ''}', '฿${formatMoney(lineAmount(l, discountMode: _discountMode))}'),
          const Divider(height: 18),
          DocKeyValue('รวมเป็นเงิน', '฿${formatMoney(t.subtotal)}', valueKey: const ValueKey('qt-total-subtotal')),
          DocKeyValue('ส่วนลด', '฿${formatMoney(t.discountTotal)}', valueKey: const ValueKey('qt-total-discount')),
          DocKeyValue('ยอดก่อน VAT', '฿${formatMoney(t.priceBeforeVat)}', valueKey: const ValueKey('qt-total-before-vat')),
          DocKeyValue('VAT', '฿${formatMoney(t.taxTotal)}', valueKey: const ValueKey('qt-total-vat')),
          DocKeyValue('ยอดสุทธิ', '฿${formatMoney(t.grandTotal)}', strong: true, valueKey: const ValueKey('qt-total-grand')),
        ]),
      ),
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
    final summary = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${tr('$count รายการ')} · ${tr('ส่วนลด')} ฿${formatMoney(t.discountTotal)} · VAT ฿${formatMoney(t.taxTotal)}',
            key: const ValueKey('docform-bar-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Text(
            '${_values['customer_name'] ?? ''}'.trim().isEmpty ? tr('ยังไม่ได้เลือกลูกค้า') : '${_values['customer_name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('ยอดสุทธิ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text('฿${formatMoney(t.grandTotal)}', key: const ValueKey('docform-bar-total'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
      ]),
    ]);
    Widget spin() => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    final back = _step == 0
        ? null
        : SizedBox(
            height: 50,
            child: OutlinedButton(
              key: const ValueKey('docform-back'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
              onPressed: busy ? null : () => setState(() => _go(_step - 1)),
              child: const Icon(NxI.arrowLeft, size: 18),
            ),
          );
    if (!last) {
      return DocBottomBar(summary: summary, actions: [
        ?back,
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            key: const ValueKey('docform-next'),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: busy ? null : _next,
            icon: const Icon(NxI.arrowRight, size: 18),
            label: Text(tr('ถัดไป · ${_steps[_step + 1].title}')),
          ),
        ),
      ]);
    }
    final saveLabel = switch (_mode) {
      DocFormMode.edit => 'บันทึก',
      DocFormMode.revise => 'สร้างฉบับแก้ไข',
      _ => 'บันทึกร่าง',
    };
    Widget fit(String label) => FittedBox(fit: BoxFit.scaleDown, child: Text(tr(label), maxLines: 1));
    final off = busy || _locked;
    return DocBottomBar(summary: summary, actions: [
      Expanded(
        child: SizedBox(
          height: 50,
          child: OutlinedButton(
            key: const ValueKey('docform-save'),
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: off ? null : () => _finish(),
            child: _busy == 'save' ? spin() : fit(saveLabel),
          ),
        ),
      ),
      Expanded(
        child: SizedBox(
          height: 50,
          child: FilledButton.tonal(
            key: const ValueKey('docform-approval'),
            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: off ? null : () => _finish(then: 'approval'),
            child: _busy == 'approval' ? spin() : fit('ส่งขออนุมัติ'),
          ),
        ),
      ),
      SizedBox(
        height: 50,
        child: FilledButton(
          key: const ValueKey('docform-email'),
          style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: off ? null : () => _finish(then: 'email'),
          child: _busy == 'email' ? spin() : fit(_mode == DocFormMode.edit ? 'บันทึกและส่งอีเมล' : 'สร้างและส่งอีเมล'),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────── customer card

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.values, required this.kind, required this.onChange, required this.onClear, this.locked = false});
  final Map<String, dynamic> values;
  final String kind;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badge = switch (kind) {
      'account' => 'บัญชีลูกค้า',
      'contact' => 'ผู้ติดต่อ',
      'lead' => 'ผู้มุ่งหวัง',
      _ => 'พิมพ์เอง',
    };
    final lines = [
      if ('${values['contact_name'] ?? ''}'.isNotEmpty) '${tr('ผู้ติดต่อ')}: ${values['contact_name']}',
      if ('${values['customer_address'] ?? ''}'.isNotEmpty) '${values['customer_address']}',
      [values['customer_phone'], values['customer_mobile'], values['customer_email']].where((x) => '${x ?? ''}'.trim().isNotEmpty).join(' · '),
    ].where((x) => x.trim().isNotEmpty).toList();
    return Container(
      key: const ValueKey('qt-customer-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.primary.withValues(alpha: 0.25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 20, backgroundColor: cs.primary.withValues(alpha: 0.15), child: Icon(kind == 'lead' ? NxI.userPlus : kind == 'contact' ? NxI.user : NxI.buildings, color: cs.primary, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text('${values['customer_name'] ?? ''}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(tr(badge), key: const ValueKey('qt-customer-kind'), style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
            for (final l in lines) Text(l, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        if (!locked)
          Column(children: [
            TextButton(key: const ValueKey('qt-customer-change'), onPressed: onChange, child: Text(tr('เปลี่ยน'))),
            IconButton(key: const ValueKey('qt-customer-clear'), tooltip: tr('ล้างลูกค้า'), onPressed: onClear, icon: Icon(NxI.x, size: 18, color: cs.onSurfaceVariant)),
          ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────── one search for many modules

typedef PickHit = Future<void> Function(String module, Map<String, dynamic> row);

/// Type once, results from several modules (accounts + contacts + leads, or
/// products + services) grouped under their name.
class _MultiSearchBox extends StatefulWidget {
  const _MultiSearchBox({
    super.key,
    required this.modules,
    required this.api,
    required this.onPick,
    required this.hint,
    required this.keyPrefix,
    this.trailing,
    this.subtitleOf,
    this.controller,
    this.onCancel,
  });
  final List<String> modules;
  final ApiClient api;
  final PickHit onPick;
  final String hint;
  final String keyPrefix;
  final Widget? trailing;
  final String? Function(String module, Map<String, dynamic> row)? subtitleOf;
  final TextEditingController? controller;
  final VoidCallback? onCancel;

  @override
  State<_MultiSearchBox> createState() => _MultiSearchBoxState();
}

class _MultiSearchBoxState extends State<_MultiSearchBox> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  Timer? _t;
  int _token = 0;
  bool _loading = false;
  Map<String, List<Map<String, dynamic>>> _hits = const {};

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  String _last = '';
  void _changed() {
    if (_c.text == _last) return;
    _last = _c.text;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), run);
  }

  Future<void> run() async {
    final q = _c.text.trim();
    final token = ++_token;
    if (q.isEmpty) {
      setState(() {
        _hits = const {};
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final out = <String, List<Map<String, dynamic>>>{};
    await Future.wait([
      for (final m in widget.modules)
        widget.api.getEntityList(m, q: q, limit: 8).then((p) => out[m] = p.items).catchError((_) => out[m] = const <Map<String, dynamic>>[]),
    ]);
    if (!mounted || token != _token) return;
    setState(() {
      _hits = out;
      _loading = false;
    });
  }

  static const _titles = {'account': 'บัญชีลูกค้า', 'contact': 'ผู้ติดต่อ', 'lead': 'ผู้มุ่งหวัง', 'product': 'สินค้า', 'service': 'บริการ'};
  static const _icons = {'account': NxI.buildings, 'contact': NxI.user, 'lead': NxI.userPlus, 'product': NxI.package, 'service': NxI.wrench};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final any = _hits.values.any((l) => l.isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: ValueKey('${widget.keyPrefix}-search'),
        controller: _c,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          _t?.cancel();
          run();
        },
        decoration: InputDecoration(
          hintText: tr(widget.hint),
          prefixIcon: const Icon(NxI.magnifyingGlass),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_loading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ?widget.trailing,
            if (widget.onCancel != null) IconButton(tooltip: tr('ยกเลิก'), onPressed: widget.onCancel, icon: const Icon(NxI.x, size: 18)),
          ]),
        ),
      ),
      if (_c.text.trim().isNotEmpty && !_loading && !any)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(tr('ไม่พบรายการที่ตรงกับ "${_c.text.trim()}"'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      for (final m in widget.modules)
        if ((_hits[m] ?? const []).isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(tr(_titles[m] ?? m), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ),
          for (final r in _hits[m]!)
            ListTile(
              key: ValueKey('${widget.keyPrefix}-hit-$m-${r['id']}'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(_icons[m] ?? NxI.note, size: 20, color: cs.primary),
              title: Text(entityTitle(r, module: m), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: () {
                final s = widget.subtitleOf?.call(m, r) ?? entitySubtitle(r, module: m);
                return s == null || s.isEmpty ? null : Text(s, maxLines: 1, overflow: TextOverflow.ellipsis);
              }(),
              trailing: Icon(NxI.plus, size: 18, color: cs.primary),
              onTap: () async {
                await widget.onPick(m, r);
                if (mounted && widget.keyPrefix == 'catalog') {
                  _c.clear();
                  setState(() => _hits = const {});
                }
              },
            ),
        ],
    ]);
  }
}

/// Accounts + contacts + leads in one search box (quotation step 1).
class CustomerSearchBox extends StatelessWidget {
  const CustomerSearchBox({super.key, required this.modules, required this.api, required this.onPick, this.onCancel});
  final List<String> modules;
  final ApiClient api;
  final PickHit onPick;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => _MultiSearchBox(
        modules: modules,
        api: api,
        onPick: onPick,
        onCancel: onCancel,
        keyPrefix: 'customer',
        hint: 'ค้นหาชื่อลูกค้า ผู้ติดต่อ ผู้มุ่งหวัง เบอร์ หรืออีเมล',
      );
}

/// Products + services in one search box, with the barcode scanner (step 2).
class CatalogSearchBox extends StatefulWidget {
  const CatalogSearchBox({super.key, required this.api, required this.onPick});
  final ApiClient api;
  final PickHit onPick;

  @override
  State<CatalogSearchBox> createState() => _CatalogSearchBoxState();
}

class _CatalogSearchBoxState extends State<CatalogSearchBox> {
  final _c = TextEditingController();
  final _box = GlobalKey<_MultiSearchBoxState>();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanProductBarcode(context);
    if (code == null || code.trim().isEmpty || !mounted) return;
    // One exact product → add it straight away; else show the matches.
    try {
      final page = await widget.api.getEntityList('product', q: code.trim(), limit: 5);
      if (!mounted) return;
      if (page.items.length == 1) {
        await widget.onPick('product', page.items.first);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    _c.text = code.trim();
    _box.currentState?.run();
  }

  @override
  Widget build(BuildContext context) => _MultiSearchBox(
        key: _box,
        controller: _c,
        modules: const ['product', 'service'],
        api: widget.api,
        onPick: widget.onPick,
        keyPrefix: 'catalog',
        hint: 'ค้นหาสินค้า / บริการ หรือรหัส',
        subtitleOf: (m, r) {
          final p = m == 'service' ? 'service' : 'product';
          final price = r['${p}_selling_price'] ?? r['${p}_initial_price'];
          final code = r['${p}_code'] ?? r['${p}_no'];
          return [if (code != null && '$code'.isNotEmpty) '$code', if (price != null && '$price'.isNotEmpty) '฿${formatMoney(qNum(price))}'].join(' · ');
        },
        trailing: IconButton(
          key: const ValueKey('catalog-scan'),
          tooltip: tr('สแกนบาร์โค้ด'),
          onPressed: _scan,
          icon: const Icon(NxI.scanLine, size: 20),
        ),
      );
}
