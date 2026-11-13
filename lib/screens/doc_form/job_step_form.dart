import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/doc_form/doc_form_draft.dart';
import '../../core/doc_form/doc_form_rules.dart';
import '../../core/doc_form/doc_pick_rules.dart' show quotationTemplateLabel;
import '../../core/doc_form/job_form_rules.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../services/geo_address.dart';
import '../../widgets/fields/field_format.dart' show isTruthyFieldValue;
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/field_validate.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_pin_picker.dart';
import '../crm/entity_detail_parts.dart' show pickAttachments;
import '../docs/document_tab.dart';
import 'barcode_scan_sheet.dart';
import 'doc_form_shell.dart';
import 'doc_pickers.dart';
import 'job_form_parts.dart';
import 'job_pickers.dart';

const _steps = [
  DocStepInfo('งานอะไร', NxI.wrench),
  // A zero-width space marks where a narrow phone may wrap the title.
  DocStepInfo('ลูกค้าและ\u200Bสถาน\u2060ที่', NxI.mapPin),
  DocStepInfo('เมื่อไร / ใคร', NxI.calendarClock),
  DocStepInfo('รายละเอียด\u200Bและตรวจ', NxI.checkCircle),
];

const _slate = Color(0xFF64748B);

/// Job (ใบสั่งงาน) create / edit / duplicate in 4 steps: งานอะไร → ลูกค้าและ
/// สถานที่ → เมื่อไร / ใคร → รายละเอียดและตรวจ. Every lookup (customer,
/// contact, case, contract, site, asset, technician, job type, template) opens
/// its own search page — nothing is listed inside the form. Saves like the
/// web (`POST /api/entity/job` · `PUT /api/entity/job/:id`); the status always
/// starts at "Open" on the server and actual start / end come from check-in.
class JobStepForm extends StatefulWidget {
  const JobStepForm({super.key, this.mode = DocFormMode.create, this.recordId, this.initialValues, this.parent, this.embedded = false, this.onFinished, this.initialStep});

  final DocFormMode mode;

  /// Edit: the job; duplicate: the source job.
  final String? recordId;

  /// New job pre-filled by the caller (e.g. `related_account_id`).
  final Map<String, dynamic>? initialValues;

  /// Created from a case / contract / quotation: `(module, row)`.
  final ({String module, Map<String, dynamic> row})? parent;
  final bool embedded;
  final ValueChanged<Map<String, dynamic>?>? onFinished;
  final int? initialStep;

  @override
  State<JobStepForm> createState() => JobStepFormState();
}

class JobStepFormState extends State<JobStepForm> {
  bool _loading = true;
  Object? _loadError;
  DocFormSchema _schema = DocFormSchema(module: 'job', fields: const []);
  Map<String, dynamic> _ctx = const {};
  final Map<String, dynamic> _values = {};
  Map<String, dynamic> _source = const {};
  int _step = 0;
  int _maxStep = 0;
  final Set<int> _shownErrors = {};
  String? _busy;
  String? _templateNotice;
  bool _locked = false;
  String? _lockReason;
  String? _parentModule;
  String _parentLabel = '';
  ({String module, Map<String, dynamic> row})? _fetchedParent;
  final _anchors = DocFieldAnchors();
  late final NxFieldHost _host;
  String? _draftKey;
  String _baseline = '';
  Timer? _draftTimer;
  List<Map<String, dynamic>> _accountContacts = const [];
  List<Map<String, dynamic>> _activityTemplates = const [];
  List<Map<String, dynamic>> _users = const [];

  /// Rows of the linked case / contract (for their cards).
  final Map<String, Map<String, dynamic>> _links = {};

  /// The picked account (its addresses for the site picker).
  Map<String, dynamic>? _account;

  /// What linking a case / contract filled in.
  String? _linkNote;

  // Folded parts.
  bool _moreOpen = false;
  bool _contactOpen = false;
  bool _manualCustomer = false;
  bool _siteEdit = false;
  bool _customEnd = false;
  bool _docOpen = false;
  bool _reportOpen = false;

  // Created with the job (not columns of the job).
  bool _appointment = false;
  Object? _checklistTemplate;
  final List<String> _checklist = [];
  final List<MultipartFile> _files = [];
  final _checkItem = TextEditingController();

  ApiClient get _api => context.read<AppConfig>().apiClient;
  DocFormMode get _mode => widget.mode;
  bool get _en => L10n.isEn;

  @override
  void initState() {
    super.initState();
    _host = nxFieldHostFor(context.read<AppConfig>().apiClient, module: 'job');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _checkItem.dispose();
    super.dispose();
  }

  String get _recordKey => switch (_mode) {
        DocFormMode.edit => widget.recordId ?? 'new',
        DocFormMode.duplicate => 'dup:${widget.recordId}',
        _ => widget.parent != null ? 'new:${widget.parent!.module}:${widget.parent!.row['id']}' : 'new',
      };

  static const _dateCols = [
    {'name': 'plan_start', 'type': 'DateTime'},
    {'name': 'plan_end', 'type': 'DateTime'},
    {'name': 'due_datetime', 'type': 'DateTime'},
  ];

  Future<void> _load() async {
    final config = context.read<AppConfig>();
    final session = config.session;
    final api = config.apiClient;
    try {
      final schemaF = api.getFieldSchema('job').then<ModuleFieldSchema?>((s) => s).catchError((_) => null);
      final ctxF = api.getJobFormContext().catchError((_) => <String, dynamic>{});
      final tplF = api.getJobActivityTemplates().catchError((_) => <Map<String, dynamic>>[]);
      final usersF = api.getUsersCached().catchError((_) => <Map<String, dynamic>>[]);
      Future<Map<String, dynamic>>? rowF;
      if (_mode != DocFormMode.create && widget.recordId != null) rowF = api.getEntity('job', widget.recordId!);
      final schema = await schemaF;
      final ctx = await ctxF;
      final row = rowF == null ? <String, dynamic>{} : await rowF;
      _activityTemplates = await tplF;
      _users = await usersF;
      final picklists = schema?.picklists ?? const <String, List<Map<String, dynamic>>>{};
      Map<String, dynamic> values;
      switch (_mode) {
        case DocFormMode.edit:
          values = {...?widget.initialValues, ...row};
          values['template_key'] = normLayout(values['template_key']);
          if ('${row['_shared_permission'] ?? ''}' == 'read_only') {
            _locked = true;
            _lockReason = 'คุณมีสิทธิ์ดูอย่างเดียวสำหรับใบสั่งงานนี้';
          }
          final st = '${row['job_status'] ?? ''}'.toLowerCase();
          if (st == 'cancelled' || st == 'completed' || st == 'closed') {
            _locked = true;
            _lockReason = 'ใบสั่งงานนี้ปิด / ยกเลิกแล้ว — แก้ไขไม่ได้ ทำซ้ำเป็นใบใหม่แทน';
          }
        case DocFormMode.duplicate:
          values = jobDuplicateValues(row, ctx: ctx, userId: session.userId);
          if (normLayout(row['template_key']) != values['template_key'] || '${row['job_template_id'] ?? ''}' != '${values['job_template_id'] ?? ''}' && '${row['job_template_id'] ?? ''}'.isNotEmpty) {
            _templateNotice = 'รูปแบบ / เทมเพลตเอกสารของใบต้นทางปิดใช้แล้ว — ใช้ค่าเริ่มต้นแทน';
          }
        case DocFormMode.create:
        case DocFormMode.revise:
          var prefill = <String, dynamic>{...?widget.initialValues};
          var p = widget.parent;
          // "สร้าง" on a case / contract page passes only the link: load the parent to pre-fill like create-job.
          if (p == null) {
            for (final (key, module) in const [('related_case_id', 'case'), ('related_contract_id', 'service_contract'), ('related_quotation_id', 'quotation')]) {
              final pid = '${unwrapFieldValue(prefill[key]) ?? ''}';
              if (pid.isEmpty || pid == 'null') continue;
              try {
                final r = await api.getEntity(module, pid);
                if (r.isNotEmpty) p = (module: module, row: {'id': pid, ...r});
              } catch (_) {}
              break;
            }
          }
          _fetchedParent = widget.parent == null ? p : null;
          if (p != null) {
            var summary = '';
            if (p.module == 'quotation') {
              try {
                summary = quotationLinesSummary(await api.getQuotationLines('${p.row['id']}'));
              } catch (_) {}
            }
            prefill = {...jobPrefillFrom(p.module, p.row, userId: session.userId, linesSummary: summary), ...prefill};
          }
          values = jobCreateValues(userId: session.userId, ctx: ctx, picklists: picklists, prefill: prefill);
      }
      normalizeFormDates(_dateCols, values, module: 'job');
      if (schema != null) normalizeFormDates(schema.fields, values, module: 'job');
      _userLabels(values, session.userId, session.displayName ?? session.email);
      final parent = widget.parent ?? _fetchedParent;
      _parentModule = parent?.module ?? (_mode == DocFormMode.create ? jobParentOf(values) : null);
      if (parent != null) {
        _parentLabel = entityTitle(parent.row, module: parent.module);
        if (parent.module != 'quotation') _links[parent.module] = parent.row;
      } else if (_parentModule != null) {
        _parentLabel = '#${values[_parentKey(_parentModule!)] ?? ''}';
      }
      if (!mounted) return;
      setState(() {
        _schema = DocFormSchema(module: 'job', fields: schema?.fields ?? const [], picklists: picklists);
        _ctx = ctx;
        _source = row;
        _values
          ..clear()
          ..addAll(values);
        _step = (widget.initialStep ?? 0).clamp(0, _steps.length - 1);
        _maxStep = _mode == DocFormMode.create ? _step : _steps.length - 1;
        _loading = false;
      });
      // Cards of the linked case / contract (edit / copy / prefilled link).
      for (final (key, module) in const [('related_case_id', 'case'), ('related_contract_id', 'service_contract')]) {
        final id = '${unwrapFieldValue(values[key]) ?? ''}';
        if (id.isEmpty || id == 'null' || _links.containsKey(module)) continue;
        api.getEntity(module, id).then((r) {
          if (mounted && r.isNotEmpty) setState(() => _links[module] = {'id': id, ...r});
        }).catchError((_) {});
      }
      final acc = '${unwrapFieldValue(values['related_account_id']) ?? ''}';
      if (acc.isNotEmpty && acc != 'null') {
        _loadAccountContacts(acc);
        if (_mode == DocFormMode.create) {
          // Pre-filled link (case / contract / account page): fill the customer like a pick.
          await _pickAccount({'id': acc});
        } else {
          if (values['related_account_id'] is! Map && !isBlankValue(values['customer_name'])) {
            _values['related_account_id'] = {'id': acc, 'label': '${values['customer_name']}'};
          }
          api.getEntity('account', acc).then((a) {
            if (mounted && a.isNotEmpty) setState(() => _account = {'id': acc, ...a});
          }).catchError((_) {});
        }
      }
      final con = '${unwrapFieldValue(values['related_contact_id']) ?? ''}';
      if (con.isNotEmpty && con != 'null' && mounted) {
        if (_mode == DocFormMode.create && isBlankValue(values['customer_contact_name'])) {
          await _pickContact({'id': con});
        } else if (_values['related_contact_id'] is! Map && !isBlankValue(values['customer_contact_name'])) {
          _values['related_contact_id'] = {'id': con, 'label': '${values['customer_contact_name']}'};
        }
      }
      final asset = '${unwrapFieldValue(values['related_asset_id']) ?? ''}';
      if (asset.isNotEmpty && asset != 'null' && values['related_asset_id'] is! Map) {
        api.getEntity('asset', asset).then((a) {
          if (mounted && a.isNotEmpty && unwrapFieldValue(_values['related_asset_id'])?.toString() == asset) {
            setState(() => _values['related_asset_id'] = {'id': asset, 'label': entityTitle(a, module: 'asset')});
          }
        }).catchError((_) {});
      }
      if (mounted) setState(() {});
      _baseline = _snapshot();
      _draftKey = DocFormDraftStore.key(businessId: session.businessId, module: 'job', record: _recordKey);
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

  static String _parentKey(String m) => switch (m) {
        'case' => 'related_case_id',
        'service_contract' => 'related_contract_id',
        _ => 'related_quotation_id',
      };

  void _userLabels(Map<String, dynamic> v, String? me, String? myName) {
    for (final k in const ['smownerid', 'engineer_user_id', 'salesperson_user_id']) {
      final o = v[k];
      if (o == null || o is Map || '$o'.isEmpty) continue;
      String? label;
      for (final u in _users) {
        if ('${u['id'] ?? u['user_id']}' == '$o') label = jobUserName(u);
      }
      if ((label == null || label.isEmpty) && '$o' == me) label = myName;
      if ((label == null || label.isEmpty) && k == 'engineer_user_id') label = '${v['engineer_name'] ?? ''}';
      if ((label == null || label.isEmpty) && k == 'salesperson_user_id') label = '${v['salesperson_name'] ?? ''}';
      if (label != null && label.isNotEmpty) v[k] = {'id': '$o', 'label': label};
    }
  }

  // ─────────────────────────────────────────────────────────────── drafts

  Map<String, dynamic> get _extraState => {
        'appointment': _appointment,
        'checklist_template': _checklistTemplate,
        'checklist': _checklist,
      };

  String _snapshot() => jsonEncode({'v': DocFormDraft(values: _values).toJson()['values'], 'x': _extraState});

  Future<void> _offerDraft() async {
    final key = _draftKey;
    if (key == null) return;
    final d = await DocFormDraftStore.read(key);
    if (d == null || !mounted) return;
    if (jsonEncode({'v': d.values, 'x': d.extra}) == _baseline) return;
    final resume = await askResumeDraft(context, savedAt: d.savedAt, what: tr('ใบสั่งงานนี้'));
    if (!mounted) return;
    if (resume == true) {
      setState(() {
        _values
          ..clear()
          ..addAll(d.values);
        _step = d.step.clamp(0, _steps.length - 1);
        if (_step > _maxStep) _maxStep = _step;
        _appointment = d.extra['appointment'] == true;
        _checklistTemplate = d.extra['checklist_template'];
        _checklist
          ..clear()
          ..addAll([for (final x in (d.extra['checklist'] as List? ?? const [])) '$x']);
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
    await DocFormDraftStore.write(key, DocFormDraft(values: _values, step: _step, extra: _extraState));
  }

  Future<void> flushDraft() async {
    _draftTimer?.cancel();
    await _writeDraft();
  }

  // ─────────────────────────────────────────────────────────────── values

  void _set(String name, dynamic v) {
    setState(() {
      _values[name] = v;
      if (name == 'engineer_user_id') _fillUser(v, 'engineer_name', 'engineer_phone');
      if (name == 'salesperson_user_id') _fillUser(v, 'salesperson_name', 'salesperson_phone');
    });
    _touched();
  }

  void _fillUser(Object? v, String nameKey, String phoneKey) {
    final id = '${unwrapFieldValue(v) ?? ''}';
    if (id.isEmpty || id == 'null') {
      _values[nameKey] = '';
      _values[phoneKey] = '';
      return;
    }
    final u = _users.where((x) => '${x['id'] ?? x['user_id']}' == id).firstOrNull;
    if (u == null) {
      if (v is Map && v['label'] != null) _values[nameKey] = '${v['label']}';
      return;
    }
    _values[nameKey] = jobUserName(u);
    final phone = userPhoneOf(u);
    if (phone.isNotEmpty) _values[phoneKey] = phone;
  }

  void _touched() => _scheduleDraft();

  void _patch(Map<String, dynamic> p) {
    setState(() => _values.addAll(p));
    _touched();
  }

  DateTime? _dt(Object? v) => parseThaiField(unwrapFieldValue(v), 'plan_start', module: 'job');

  String _str(String key) {
    final v = unwrapFieldValue(_values[key]);
    return v == null || '$v' == 'null' ? '' : '$v'.trim();
  }

  String _idOf(String key) {
    final v = _str(key);
    return v;
  }

  String _label(String key) {
    final v = _values[key];
    if (v is Map) return '${v['label'] ?? v['id'] ?? ''}';
    return isBlankValue(v) ? '' : '$v';
  }

  /// Optional columns some servers lack: drawn only when the schema has them.
  bool _shows(String name) => !_schema.hides(name) && (_schema.all.isEmpty || _schema.has(name));

  bool _lockedField(String name) => _locked || _schema.locks(name);

  Future<void> _pickAccount(Map<String, dynamic> hit) async {
    var row = hit;
    try {
      final full = await _api.getEntity('account', '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    final prevAcc = _idOf('related_account_id');
    final p = jobAccountPatch(row, _values);
    final changed = prevAcc.isNotEmpty && prevAcc != '${row['id']}';
    _account = row;
    _patch({
      ...p,
      'related_account_id': {'id': '${row['id']}', 'label': p['customer_name']},
      if (changed) ...{'related_contact_id': null, 'customer_contact_name': '', 'related_asset_id': null, 'related_location_id': null},
      if (isBlankValue(_values['site_address_snapshot']) || changed) 'site_address_snapshot': siteAddressOf(row),
      if ((isBlankValue(_values['location_name_snapshot']) || changed) && siteAddressOf(row).isNotEmpty) 'location_name_snapshot': p['customer_name'],
    });
    setState(() => _manualCustomer = false);
    _loadAccountContacts('${row['id']}');
  }

  Future<void> _pickContact(Map<String, dynamic> hit) async {
    var row = hit;
    try {
      final full = await _api.getEntity('contact', '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    final p = jobContactPatch(row, _values);
    _patch({...p, 'related_contact_id': {'id': '${row['id']}', 'label': p['customer_contact_name']}});
    final acc = contactAccountId(row);
    if (isBlankValue(_values['related_account_id']) && acc != null) await _pickAccount({'id': acc});
  }

  Future<void> _loadAccountContacts(String accountId) async {
    try {
      final rows = await _api.getAccountContacts(accountId);
      if (mounted) setState(() => _accountContacts = rows);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────── validation

  List<Map<String, String>> get _missing {
    final out = List.generate(_steps.length, (_) => <String, String>{});
    final core = kCoreFieldStep['job']!;
    for (final e in core.entries) {
      if (!_schema.editable(e.key)) continue;
      if (_schema.requires(e.key) && isBlankValue(_values[e.key])) out[e.value][e.key] = 'จำเป็นต้องกรอก';
    }
    if (_schema.editable('job_type') && isBlankValue(_values['job_type'])) out[0]['job_type'] = 'เลือกประเภทงาน';
    if (_schema.editable('job_name') && _str('job_name').isEmpty) out[0]['job_name'] = 'ตั้งชื่องาน';
    final email = _str('customer_email');
    if (email.isNotEmpty) {
      final err = validateFieldValue(FieldUiType.email, email, required: false);
      if (err != null) out[1]['customer_email'] = err;
    }
    final s = _dt(_values['plan_start']), e = _dt(_values['plan_end']);
    if (s != null && e != null && !e.isAfter(s)) out[2]['plan_end'] = 'เวลาสิ้นสุดต้องหลังเวลาเริ่ม';
    if (_appointment && s == null) out[2]['plan_start'] = 'ใส่เวลาเริ่มเพื่อสร้างนัดหมาย';
    for (var i = 0; i < _steps.length; i++) {
      out[i].addAll(validateExtraFields(_schema.extraFor(i), _values));
    }
    return out;
  }

  int _stepOf(String name) => kCoreFieldStep['job']?[name] ?? _schema.extra.where((e) => fieldName(e.field) == name).map((e) => e.step).firstOrNull ?? 3;

  String? _err(String name, Map<String, String> miss) => _shownErrors.contains(_stepOf(name)) ? miss[name] : null;

  void _go(int step) {
    _step = step;
    if (step > _maxStep) _maxStep = step;
    _scheduleDraft();
  }

  Future<void> _revealStep(int step, Map<String, String> miss) async {
    setState(() {
      _shownErrors.add(step);
      _go(step);
      // Open the folded parts that hold a missing field.
      if (step == 0 && miss.keys.any(_inMore)) _moreOpen = true;
      if (step == 1 && miss.keys.any(const {'customer_contact_name', 'customer_department', 'customer_email', 'contract_po_no'}.contains)) _contactOpen = true;
      if (step == 1 && miss.keys.any(const {'location_name_snapshot', 'site_address_snapshot'}.contains)) _siteEdit = true;
      if (step == 2 && miss.containsKey('plan_end')) _customEnd = true;
      if (step == 3 && miss.keys.any(_inReport)) _reportOpen = true;
    });
    HapticFeedback.heavyImpact();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || miss.isEmpty) return;
    await _anchors.reveal(miss.keys.first, miss.keys);
  }

  bool _inMore(String name) => name == 'job_code' || _schema.extraFor(0).any((f) => fieldName(f) == name);
  bool _inReport(String name) => _schema.extraFor(3, group: kJobReportGroup).any((f) => fieldName(f) == name);

  Future<void> _next() async {
    final miss = _missing[_step];
    if (miss.isNotEmpty) {
      await _revealStep(_step, miss);
      return;
    }
    setState(() => _go(_step + 1));
  }

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

  static const _idCols = {
    'related_account_id', 'related_contact_id', 'related_case_id', 'related_contract_id', 'related_quotation_id', 'related_asset_id',
    'related_location_id', 'smownerid', 'engineer_user_id', 'job_template_id', 'salesperson_user_id',
  };
  static const _carry = {'source', 'related_quotation_id', 'related_case_id', 'related_contract_id', 'deliverable_template', 'in_warranty', 'system_status'};

  Object? _wire(String name, Object? v) {
    var u = unwrapFieldValue(v);
    if (u is String && u.trim().isEmpty) return null;
    if (_idCols.contains(name) && u != null) u = int.tryParse('$u') ?? u;
    if (u is List) return jsonEncode(u);
    return u;
  }

  /// Body for `POST /api/entity/job` / `PUT /api/entity/job/:id` (web buildPayload).
  Map<String, dynamic> buildPayload() {
    final out = <String, dynamic>{};
    if (_mode != DocFormMode.edit) {
      for (final e in _values.entries) {
        if (e.key.startsWith('_')) continue;
        if (isNotAskedField('job', e.key) && !_carry.contains(e.key)) continue;
        if (_schema.hides(e.key) || _schema.locks(e.key)) continue;
        final w = _wire(e.key, e.value);
        if (w == null || w is Map) continue;
        out[e.key] = w;
      }
    }
    for (final name in kCoreFieldStep['job']!.keys) {
      if (!_schema.editable(name) || !_values.containsKey(name)) continue;
      final w = _wire(name, _values[name]);
      if (w == null && _mode != DocFormMode.edit) continue;
      out[name] = w;
    }
    out.addAll(collectEntityPayload([for (final e in _schema.extra) e.field], _values, currentRow: _source, module: 'job'));
    out['template_key'] = normLayout(_values['template_key']);
    out['job_template_id'] = _wire('job_template_id', _values['job_template_id']);
    for (final k in const ['job_status', 'job_no', 'actual_start', 'actual_end', 'evidence_photos']) {
      out.remove(k);
    }
    return out;
  }

  Future<void> _finish() async {
    if (_locked) return;
    if (!await _validateAll() || !mounted) return;
    setState(() => _busy = 'save');
    final api = _api;
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? id;
    Map<String, dynamic> saved = const {};
    try {
      final body = buildPayload();
      if (_mode == DocFormMode.edit) {
        id = widget.recordId;
        saved = await api.putEntity('job', id!, body);
      } else {
        saved = await api.postEntity('job', body);
        id = '${saved['id'] ?? saved['insertId'] ?? (saved['record'] is Map ? saved['record']['id'] : '') ?? ''}';
        if (id.isEmpty || id == 'null') throw StateError(tr('สร้างใบสั่งงานไม่สำเร็จ'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        _snack(e is StateError ? e.message : tr(formatApiError(e)));
      }
      return;
    }
    if (_draftKey != null) await DocFormDraftStore.clear(_draftKey!);
    _baseline = _snapshot();
    // Extras after the job exists: a failure never undoes the job.
    final warnings = <String>[];
    if (_mode != DocFormMode.edit) {
      try {
        if (_checklistTemplate != null) {
          await api.generateJobActivities(id, {'template_id': _checklistTemplate});
        } else if (_checklist.isNotEmpty) {
          await api.generateJobActivities(id, {
            'items': [
              for (var i = 0; i < _checklist.length; i++)
                {'key': 'k${i + 1}', 'subject': _checklist[i], 'activitytype': 'Visit', 'offset_days': 0, 'start_time': _startTime(), 'duration_min': 60, 'owner_rule': 'job_owner'},
            ],
          });
        }
      } catch (_) {
        warnings.add('เช็กลิสต์');
      }
    }
    if (_appointment && isBlankValue(_source['related_activity_id'])) {
      try {
        final s = _dt(_values['plan_start']), e = _dt(_values['plan_end']);
        await api.scheduleJob(id, when: s == null ? null : wallDateTime(s), end: e == null ? null : wallDateTime(e));
      } catch (_) {
        warnings.add('นัดหมาย');
      }
    }
    if (_files.isNotEmpty) {
      try {
        final atts = await api.uploadCommentAttachments(_files);
        await api.postEntityComment('job', id, '', attachments: atts);
      } catch (_) {
        warnings.add('ไฟล์แนบ');
      }
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (warnings.isNotEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(tr('บันทึกใบสั่งงานแล้ว แต่${warnings.join(' / ')}ไม่สำเร็จ — ทำต่อได้ในหน้ารายละเอียด'))));
    }
    setState(() => _busy = null);
    _close({'id': id, 'job_no': saved['job_no'] ?? _source['job_no']});
  }

  String _startTime() {
    final s = _dt(_values['plan_start']);
    return s == null ? '09:00' : jobClock(s);
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
    _close(null);
  }

  // ───────────────────────────────────────────────────────────────── build

  String get _title => switch (_mode) {
        DocFormMode.edit => 'แก้ไขใบสั่งงาน',
        DocFormMode.duplicate => 'ทำซ้ำใบสั่งงาน',
        _ => 'สร้างใบสั่งงาน',
      };

  bool _canOpen(int i) => _mode != DocFormMode.create || i <= _maxStep;

  @override
  Widget build(BuildContext context) {
    final missing = _loading ? const <Map<String, String>>[] : _missing;
    // Warn on a step only once it matters: visited and left, checked, or
    // (edit / copy) a prefilled step other than the current one.
    bool flag(int i) => (i <= _maxStep && i != _step) || _shownErrors.contains(i) || (_mode != DocFormMode.create && i != _step);
    return PopScope(
      // Back / swipe leaves at once; unsaved work stays as a local draft.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _popped();
      },
      child: DocStepShell(
        title: _title,
        subtitle: _mode == DocFormMode.edit ? '${_source['job_no'] ?? ''}' : (_mode == DocFormMode.duplicate ? '${tr('จาก')} ${_source['job_no'] ?? ''}' : null),
        steps: _steps,
        current: _step,
        missing: [for (var i = 0; i < missing.length; i++) flag(i) ? missing[i].length : 0],
        complete: [
          for (var i = 0; i < missing.length; i++) missing[i].isEmpty && ((i <= _maxStep && i != _step) || _mode != DocFormMode.create) && i < _steps.length - 1,
        ],
        canOpen: _canOpen,
        onStep: (i) => setState(() => _go(i)),
        loading: _loading,
        embedded: widget.embedded,
        onClose: _leave,
        banners: _loading ? const [] : _banners(),
        body: _loading ? const SizedBox.shrink() : _loadError != null ? _errorBody() : _body(missing),
        bottom: _loading || _loadError != null ? const SizedBox.shrink() : _bottom(),
        side: _loading || _loadError != null ? null : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _sideSummary()),
      ),
    );
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
    final no = '${_source['job_no'] ?? ''}';
    return [
      if (_locked && _lockReason != null) DocBanner(key: const ValueKey('docform-locked'), icon: NxI.lock, color: cs.error, text: _lockReason!),
      // Mode notes only on the first step: the other steps keep their room.
      if (_step == 0 && _mode == DocFormMode.duplicate)
        DocBanner(
          key: const ValueKey('job-duplicate-banner'),
          icon: NxI.copySimple,
          title: 'สำเนาจาก $no',
          text: 'ใบใหม่ เลขใหม่ สถานะเปิดงาน — ลูกค้า สถานที่ และรายละเอียดคัดลอกมาแล้ว กำหนดเวลาใหม่ในขั้น "เมื่อไร / ใคร"',
        ),
      if (_step == 0 && _mode == DocFormMode.edit && !_locked)
        DocBanner(
          key: const ValueKey('job-edit-banner'),
          icon: NxI.pencilSimple,
          title: 'แก้ไข $no',
          text: 'บันทึกทับใบเดิม — สถานะงานเปลี่ยนจากหน้ารายละเอียด (รับงาน / ปิดงาน)',
        ),
    ];
  }

  Widget _body(List<Map<String, String>> missing) {
    final children = switch (_step) {
      0 => _whatStep(missing[0]),
      1 => _customerStep(missing[1]),
      2 => _whenStep(missing[2]),
      _ => _detailsStep(missing[3]),
    };
    // One scroll view with a plain column: fields keep their state (and GlobalKeys) when rows above them come and go.
    return SingleChildScrollView(
      key: ValueKey('docform-body-$_step'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
      ]),
    );
  }

  /// A field the form draws (fixed label, schema required / read-only / hidden).
  Widget _field(String name, FieldUiType type, Map<String, String> miss, {String? hint, String? label, bool required = false, ValueChanged<dynamic>? onChanged, double gap = 16}) {
    if (_schema.hides(name)) return const SizedBox.shrink();
    return _anchors.wrap(
      name,
      Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: NxFormField(
          uiType: type,
          label: tr(label ?? jobFieldLabel(name)),
          name: name,
          value: _values[name],
          hint: hint == null ? null : tr(hint),
          required: required || _schema.requires(name),
          readOnly: _lockedField(name),
          errorText: trn(_err(name, miss)),
          host: _host,
          onChanged: onChanged ?? (v) => _set(name, v),
        ),
      ),
    );
  }

  Widget _extraForm(int step, String group, Map<String, String> miss) => NxEntityForm(
        key: _anchors.formKey('$step:$group'),
        fields: _schema.extraFor(step, group: group),
        values: _values,
        picklists: _schema.picklists,
        api: _api,
        module: 'job',
        enabled: !_locked,
        errors: _shownErrors.contains(step) ? miss : const {},
        onChanged: _set,
      );

  /// Business fields of [step] in their groups (the report group folds).
  List<Widget> _extraGroups(int step, Map<String, String> miss) => [
        for (final g in _schema.groupsFor(step))
          if (g == kJobReportGroup)
            JobCollapsible(
              key: ValueKey('docform-extra-$step-$g'),
              toggleKey: const ValueKey('job-report-toggle'),
              title: g,
              icon: NxI.clipboardText,
              color: const Color(0xFF0EA5E9),
              summary: _mode == DocFormMode.create ? 'ช่างกรอกตอนปิดงานได้ — เปิดเมื่อมีข้อมูลแล้ว' : 'ปัญหาที่พบ วิธีแก้ไข ข้อเสนอแนะ',
              open: _reportOpen || (_mode == DocFormMode.edit && _schema.extraFor(step, group: g).any((f) => !isBlankValue(_values[fieldName(f)]))) ||
                  (_shownErrors.contains(step) && miss.keys.any(_inReport)),
              onToggle: () => setState(() => _reportOpen = !_reportOpen),
              child: _extraForm(step, g, miss),
            )
          else
            DocSectionCard(key: ValueKey('docform-extra-$step-$g'), title: g, icon: NxI.note, color: _slate, child: _extraForm(step, g, miss)),
      ];

  // Step 1 · งานอะไร ----------------------------------------------------------

  List<JobChoice> get _typeChoices => jobChoices('job_type', _schema.picklists, kJobTypeFallback, en: _en);
  List<JobChoice> get _priorityChoices => jobChoices('job_priority', _schema.picklists, kJobPriorityFallback, en: _en);
  List<JobChoice> get _categoryChoices => jobChoices('job_category', _schema.picklists, kJobCategoryFallback, en: _en);

  Future<void> _openTypePicker() async {
    final v = await showDocOptionPicker(
      context,
      title: 'ประเภทงาน',
      keyPrefix: 'jobtype',
      selected: _str('job_type'),
      options: [for (final c in _typeChoices) DocOption(c.value, c.label, subtitle: c.help, icon: c.value == 'request' ? NxI.lifeBuoy : NxI.wrench)],
    );
    if (v == null || !mounted) return;
    _set('job_type', v);
    // The service report follows the job type (web create-job), unless chosen already.
    final deliverable = v == 'request' ? 'request_report' : 'service_report';
    if (_mode != DocFormMode.edit && const {'service_report', 'request_report', ''}.contains(_str('deliverable_template'))) _set('deliverable_template', deliverable);
  }

  Future<void> _openLinkPicker(String module) async {
    final s = context.read<AppConfig>().session;
    final key = module == 'case' ? 'related_case_id' : 'related_contract_id';
    final acc = _idOf('related_account_id');
    final picker = module == 'case' ? showJobCasePicker : showJobContractPicker;
    final picked = await picker(
      context,
      api: _api,
      userId: s.userId,
      accountId: acc.isEmpty ? null : acc,
      accountName: _str('customer_name').isEmpty ? null : _str('customer_name'),
      selectedId: _idOf(key).isEmpty ? null : _idOf(key),
    );
    if (picked == null || !mounted) return;
    if (picked.isNone) {
      setState(() {
                  _links.remove(module);
                  _linkNote = null;
                });
      _set(key, null);
      return;
    }
    var row = picked.row;
    try {
      final full = await _api.getEntity(module, '${row['id']}');
      if (full.isNotEmpty) row = {...row, ...full};
    } catch (_) {}
    if (!mounted) return;
    final hadAccount = !isBlankValue(_values['related_account_id']);
    final p = jobLinkPatch(module, row, _values);
    setState(() => _links[module] = row);
    _patch(p);
    final filled = <String>[
      if (p.containsKey('related_account_id')) 'ลูกค้า',
      if (p.containsKey('due_datetime')) 'กำหนดเสร็จ',
      if (p.containsKey('job_name')) 'ชื่องาน',
    ];
    if (!hadAccount && p['related_account_id'] != null) {
      await _pickAccount({'id': p['related_account_id']});
      if (p['related_contact_id'] != null) await _pickContact({'id': p['related_contact_id']});
    }
    // Said under the card (a snackbar would cover the ถัดไป button).
    if (mounted) setState(() => _linkNote = filled.isEmpty ? null : 'เติม${filled.join(' ')}จาก${module == 'case' ? 'เคส' : 'สัญญา'}แล้ว');
  }

  Widget _linkRow(String module, Map<String, String> miss) {
    final key = module == 'case' ? 'related_case_id' : 'related_contract_id';
    final k = module == 'case' ? 'case' : 'contract';
    if (_schema.hides(key)) return const SizedBox.shrink();
    final id = _idOf(key);
    final isParent = _parentModule == module;
    final locked = _lockedField(key) || isParent;
    final row = _links[module];
    Widget child;
    if (id.isEmpty) {
      child = JobFieldRow(
        key: ValueKey('job-$k-pick'),
        icon: module == 'case' ? NxI.lifeBuoy : NxI.fileText,
        label: jobFieldLabel(key),
        value: tr('ไม่เชื่อม'),
        muted: true,
        hint: tr(module == 'case' ? 'ค้นหาเคสที่เปิดอยู่ของลูกค้า' : 'ค้นหาสัญญาที่ใช้งานอยู่ของลูกค้า'),
        error: trn(_err(key, miss)),
        onTap: locked ? null : () => _openLinkPicker(module),
      );
    } else {
      child = JobLinkCard(
        key: ValueKey('job-$k-card'),
        module: module,
        parent: isParent,
        view: row == null ? JobLinkView(no: '#$id', title: '', customer: '', status: '') : jobLinkView(module, row),
        onChange: locked ? null : () => _openLinkPicker(module),
        onClear: locked
            ? null
            : () {
                setState(() {
                  _links.remove(module);
                  _linkNote = null;
                });
                _set(key, null);
              },
      );
    }
    return _anchors.wrap(key, Padding(padding: const EdgeInsets.only(bottom: 10), child: child));
  }

  List<Widget> _whatStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = _str('job_type');
    final typeChoice = _typeChoices.where((c) => c.value == type).firstOrNull;
    final category = _str('job_category');
    final parentTitle = switch (_parentModule) {
      'case' => 'สร้างจากเคส',
      'service_contract' => 'สร้างจากสัญญาบริการ',
      'quotation' => 'สร้างจากใบเสนอราคา',
      _ => '',
    };
    final moreErr = _shownErrors.contains(0) && miss.keys.any(_inMore);
    final moreOpen = _moreOpen || moreErr;
    final extraCount = _schema.extraFor(0).length;
    final code = _str('job_code');
    return [
      if (_parentModule != null)
        DocBanner(
          key: const ValueKey('job-parent'),
          icon: NxI.link,
          title: parentTitle,
          text: '$_parentLabel — ${tr('ลูกค้า ผู้ติดต่อ และกำหนดเสร็จเติมให้จากต้นทางแล้ว')}',
        ),
      DocSectionCard(
        title: 'งานอะไร',
        icon: NxI.wrench,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_schema.hides('job_type'))
            _anchors.wrap(
              'job_type',
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: JobFieldRow(
                  key: const ValueKey('job-type-pick'),
                  icon: type == 'request' ? NxI.lifeBuoy : NxI.wrench,
                  label: jobFieldLabel('job_type'),
                  required: true,
                  value: typeChoice?.label ?? (type.isEmpty ? tr('เลือกประเภทงาน') : type),
                  valueKey: const ValueKey('job-type-value'),
                  muted: type.isEmpty,
                  hint: typeChoice?.help == null ? null : tr(typeChoice!.help!),
                  error: trn(_err('job_type', miss)),
                  onTap: _lockedField('job_type') ? null : _openTypePicker,
                ),
              ),
            ),
          _field('job_name', FieldUiType.text, miss, required: true, hint: 'เช่น ล้างแอร์ประจำปี อาคาร B'),
          if (!_schema.hides('job_priority')) ...[
            const JobLabel('ความสำคัญ'),
            _anchors.wrap(
              'job_priority',
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: JobPrioritySegment(
                  choices: _priorityChoices,
                  value: _str('job_priority'),
                  onChanged: _lockedField('job_priority') ? null : (v) => _set('job_priority', v),
                ),
              ),
            ),
          ],
          if (_shows('job_category')) ...[
            JobLabel('ลักษณะงาน', trailing: Text(tr('แสดงบนรายงานบริการ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
            _anchors.wrap(
              'job_category',
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _categoryChoices)
                    ChoiceChip(
                      key: ValueKey('job-category-${c.value}'),
                      label: Text(tr(c.label)),
                      selected: category == c.value,
                      onSelected: _lockedField('job_category') ? null : (on) => _set('job_category', on ? c.value : null),
                    ),
                ]),
              ),
            ),
            if (category == 'other' && _shows('job_category_other')) _field('job_category_other', FieldUiType.text, miss, hint: 'เช่น ย้ายเครื่อง / ตรวจรับงาน'),
          ],
        ]),
      ),
      if (!_schema.hides('related_case_id') || !_schema.hides('related_contract_id'))
        DocSectionCard(
          key: const ValueKey('job-links'),
          title: 'เชื่อมกับเคส / สัญญา',
          subtitle: 'ไม่บังคับ — เติมลูกค้าและกำหนดเสร็จให้',
          icon: NxI.link,
          color: _slate,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _linkRow('case', miss),
            _linkRow('service_contract', miss),
            if (_linkNote != null)
              Row(children: [
                const Icon(NxI.checkCircle, size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Expanded(child: Text(tr(_linkNote!), key: const ValueKey('job-link-note'), style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w600))),
              ]),
          ]),
        ),
      if (_shows('job_code') || extraCount > 0)
        JobCollapsible(
          key: const ValueKey('job-more'),
          toggleKey: const ValueKey('job-more-toggle'),
          title: 'ข้อมูลเพิ่มเติม',
          icon: NxI.note,
          color: _slate,
          summary: code.isNotEmpty ? '${tr('รหัสอ้างอิง')} $code' : 'รหัสอ้างอิงงาน${extraCount > 0 ? ' และช่องของธุรกิจ $extraCount ช่อง' : ''} (ไม่บังคับ)',
          open: moreOpen,
          onToggle: () => setState(() => _moreOpen = !moreOpen),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_shows('job_code')) _field('job_code', FieldUiType.text, miss, hint: 'เช่น เลขงานจากระบบของลูกค้า — เลขที่ใบสั่งงานระบบออกให้เอง'),
            for (final g in _schema.groupsFor(0)) ...[
              if (_schema.groupsFor(0).length > 1 || g != 'ข้อมูลเพิ่มเติม') JobLabel(g),
              _extraForm(0, g, miss),
            ],
          ]),
        ),
    ];
  }

  // Step 2 · ลูกค้าและสถานที่ ---------------------------------------------------

  Future<void> _openCustomerPicker() async {
    final s = context.read<AppConfig>().session;
    final picked = await showCustomerPicker(context, api: _api, modules: const ['account', 'contact'], userId: s.userId, businessId: s.businessId);
    if (picked == null || !mounted) return;
    if (picked.module == 'contact') {
      await _pickContact(picked.row);
    } else {
      await _pickAccount(picked.row);
    }
  }

  Future<void> _openContactPicker() async {
    final acc = _idOf('related_account_id');
    final picked = await showContactPicker(
      context,
      api: _api,
      accountId: acc.isEmpty ? null : acc,
      accountName: _str('customer_name').isEmpty ? null : _str('customer_name'),
      selectedId: _idOf('related_contact_id').isEmpty ? null : _idOf('related_contact_id'),
      noneSubtitle: 'ไม่มีชื่อผู้ติดต่อบนใบงาน',
    );
    if (picked == null || !mounted) return;
    if (picked.isNone) {
      _patch({'related_contact_id': null, 'customer_contact_name': ''});
      return;
    }
    await _pickContact(picked.row);
  }

  Future<void> _openSitePicker() async {
    final acc = _idOf('related_account_id');
    final pick = await showJobSitePicker(
      context,
      api: _api,
      accountId: acc.isEmpty ? null : acc,
      accountName: _str('customer_name').isEmpty ? null : _str('customer_name'),
      account: _account,
      selectedLocationId: _idOf('related_location_id').isEmpty ? null : _idOf('related_location_id'),
    );
    if (pick == null || !mounted) return;
    _applySite(pick);
  }

  void _applySite(JobSitePick pick) {
    switch (pick.kind) {
      case 'location':
        final row = pick.location ?? const <String, dynamic>{};
        final p = jobLocationPatch(row, _values);
        _patch({...p, 'related_location_id': {'id': '${row['id']}', 'label': p['location_name_snapshot']}});
      case 'pin':
        _patch({
          'site_address_snapshot': pick.address,
          if (isBlankValue(_values['location_name_snapshot'])) 'location_name_snapshot': pick.name,
          'related_location_id': null,
        });
      default:
        _patch({
          'site_address_snapshot': pick.address,
          if (pick.name.isNotEmpty) 'location_name_snapshot': pick.name,
          'related_location_id': null,
        });
    }
  }

  Future<void> _pinOnMap() async {
    final hook = DocFormHooks.pickPin;
    final p = hook != null ? await hook(context) : await showNxMapPinPicker(context, title: tr('ปักหมุดสถานที่ทำงาน'));
    if (p == null || !mounted) return;
    final current = siteAddressText(_values['site_address_snapshot']);
    var addr = current;
    if (addr.isEmpty) {
      final lookup = DocFormHooks.reverseGeocode;
      addr = (lookup != null ? await lookup(p.lat, p.lng) : await GeoAddress.lookup(p.lat, p.lng)) ?? '';
    }
    if (!mounted) return;
    _applySite(JobSitePick(kind: 'pin', name: tr('จุดที่ปักหมุด'), address: siteAddressWithPin(addr, p.lat, p.lng)));
  }

  Future<void> _openAssetPicker() async {
    final acc = _idOf('related_account_id');
    final picked = await showJobAssetPicker(
      context,
      api: _api,
      accountId: acc.isEmpty ? null : acc,
      accountName: _str('customer_name').isEmpty ? null : _str('customer_name'),
      selectedId: _idOf('related_asset_id').isEmpty ? null : _idOf('related_asset_id'),
    );
    if (picked == null || !mounted) return;
    _set('related_asset_id', picked.isNone ? null : {'id': '${picked.row['id']}', 'label': entityTitle(picked.row, module: 'asset')});
  }

  List<Widget> _customerStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasAcc = !isBlankValue(_values['related_account_id']);
    final name = _str('customer_name');
    final hasCustomer = hasAcc || name.isNotEmpty;
    final lockedCustomer = _lockedField('related_account_id');
    final contactName = _str('customer_contact_name');
    final siteName = _str('location_name_snapshot');
    final siteAddr = siteAddressText(_values['site_address_snapshot']);
    final hasSite = siteName.isNotEmpty || siteAddr.isNotEmpty;
    final contactErr = _shownErrors.contains(1) && miss.keys.any(const {'customer_contact_name', 'customer_department', 'customer_email', 'contract_po_no'}.contains);
    final contactOpen = _contactOpen || contactErr;
    final siteErr = _shownErrors.contains(1) && miss.keys.any(const {'location_name_snapshot', 'site_address_snapshot'}.contains);
    final siteEdit = _siteEdit || siteErr || (!hasSite && _locked);
    final accAddr = _account == null ? '' : siteAddressOf(_account!);
    final assetLabel = _label('related_asset_id');
    return [
      DocSectionCard(
        title: 'ลูกค้า',
        icon: NxI.buildings,
        child: _anchors.wrap(
          'related_account_id',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hasCustomer && !_manualCustomer)
              JobCustomerCard(
                name: name.isEmpty ? _label('related_account_id') : name,
                kind: hasAcc ? 'บัญชีลูกค้า' : 'พิมพ์เอง',
                lines: [
                  if (accAddr.isNotEmpty) (NxI.mapPin, accAddr),
                  if ([_str('customer_mobile'), _str('customer_email')].any((x) => x.isNotEmpty))
                    (NxI.phone, [_str('customer_mobile'), _str('customer_email')].where((x) => x.isNotEmpty).join(' · ')),
                ],
                onChange: lockedCustomer ? null : _openCustomerPicker,
                onClear: lockedCustomer
                    ? null
                    : () {
                        _patch({'related_account_id': null, 'related_contact_id': null, 'customer_name': '', 'customer_contact_name': ''});
                        setState(() {
                          _account = null;
                          _accountContacts = const [];
                        });
                      },
              )
            else ...[
              JobPickTile(
                key: const ValueKey('job-customer-pick'),
                icon: NxI.magnifyingGlass,
                title: 'เลือกลูกค้า',
                subtitle: 'ค้นหาบัญชีลูกค้าหรือผู้ติดต่อ — เติมที่อยู่และเบอร์ให้',
                error: _err('related_account_id', miss) != null,
                onTap: lockedCustomer ? null : _openCustomerPicker,
              ),
              if (_err('related_account_id', miss) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(tr(_err('related_account_id', miss)!), key: const ValueKey('job-customer-error'), style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              if (_manualCustomer || (!hasAcc && name.isNotEmpty)) ...[
                const SizedBox(height: 12),
                _field('customer_name', FieldUiType.text, miss, label: 'ชื่อลูกค้า (ยังไม่มีในระบบ)', gap: 4),
              ] else if (!lockedCustomer)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('job-customer-manual'),
                    onPressed: () => setState(() => _manualCustomer = true),
                    icon: const Icon(NxI.pencilSimple, size: 16),
                    label: Text(tr('ไม่มีในระบบ? พิมพ์ชื่อลูกค้าเอง')),
                  ),
                ),
            ],
            if (hasCustomer && !_schema.hides('related_contact_id')) ...[
              const SizedBox(height: 10),
              _anchors.wrap(
                'related_contact_id',
                JobFieldRow(
                  key: const ValueKey('job-contact-pick'),
                  icon: NxI.addressBook,
                  label: jobFieldLabel('related_contact_id'),
                  value: contactName.isEmpty ? tr('ไม่ระบุ') : contactName,
                  valueKey: const ValueKey('job-contact-value'),
                  muted: contactName.isEmpty,
                  hint: hasAcc && _accountContacts.isNotEmpty ? tr('เลือกจาก ${_accountContacts.length} คนของลูกค้านี้') : null,
                  error: trn(_err('related_contact_id', miss)),
                  onTap: _lockedField('related_contact_id') ? null : _openContactPicker,
                ),
              ),
            ],
          ]),
        ),
      ),
      if (hasCustomer)
        JobCollapsible(
          key: const ValueKey('job-contact-details'),
          toggleKey: const ValueKey('job-contact-details-toggle'),
          title: 'ผู้ติดต่อบนใบงาน',
          icon: NxI.idCard,
          color: const Color(0xFF0EA5E9),
          summary: [contactName, _str('customer_department'), _str('customer_email')].where((x) => x.isNotEmpty).join(' · ').isEmpty
              ? 'ชื่อ แผนก อีเมล และเลขที่ PO ที่แสดงบนรายงาน'
              : [contactName, _str('customer_department'), _str('customer_email')].where((x) => x.isNotEmpty).join(' · '),
          open: contactOpen,
          onToggle: () => setState(() => _contactOpen = !contactOpen),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('customer_contact_name', FieldUiType.text, miss),
            if (_shows('customer_department')) _field('customer_department', FieldUiType.text, miss),
            _field('customer_email', FieldUiType.email, miss),
            if (_shows('contract_po_no')) _field('contract_po_no', FieldUiType.text, miss, gap: 4),
          ]),
        ),
      DocSectionCard(
        title: 'สถานที่ทำงาน',
        subtitle: 'ที่ช่างต้องไป และเบอร์ติดต่อหน้างาน',
        icon: NxI.mapPin,
        color: const Color(0xFF8B5CF6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hasSite)
            JobSiteCard(
              name: siteName,
              address: siteAddr,
              pinned: siteCoordsOf(_values['site_address_snapshot']) != null,
              onChange: _locked ? null : _openSitePicker,
              onPin: _locked ? null : _pinOnMap,
              onEdit: _locked ? null : () => setState(() => _siteEdit = !siteEdit),
              editing: siteEdit,
            )
          else
            JobPickTile(
              key: const ValueKey('job-site-pick'),
              icon: NxI.mapPinned,
              title: 'เลือกสถานที่ทำงาน',
              subtitle: hasAcc ? 'ที่อยู่ลูกค้า พื้นที่บริการ ปักหมุด หรือระบุเอง' : 'ปักหมุด หรือระบุที่อยู่เอง',
              onTap: _locked ? null : _openSitePicker,
            ),
          if (siteEdit) ...[
            const SizedBox(height: 14),
            _field('location_name_snapshot', FieldUiType.text, miss, hint: 'เช่น อาคาร B ชั้น 3'),
            _field('site_address_snapshot', FieldUiType.longText, miss, gap: 4),
          ],
          const SizedBox(height: 14),
          _field('customer_mobile', FieldUiType.phone, miss, hint: 'ช่างโทรหาก่อนเข้าหน้างาน', gap: 0),
        ]),
      ),
      if (!_schema.hides('related_asset_id'))
        DocSectionCard(
          title: 'สินทรัพย์ / เครื่องของลูกค้า',
          subtitle: 'ไม่บังคับ',
          icon: NxI.hardDrives,
          color: const Color(0xFF0EA5E9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _anchors.wrap(
              'related_asset_id',
              JobFieldRow(
                key: const ValueKey('job-asset-pick'),
                icon: NxI.hardDrives,
                label: 'เครื่อง / สินทรัพย์',
                value: assetLabel.isEmpty ? tr('ยังไม่ได้เลือก') : assetLabel,
                valueKey: const ValueKey('job-asset-label'),
                muted: assetLabel.isEmpty,
                onTap: _lockedField('related_asset_id') ? null : _openAssetPicker,
              ),
            ),
            if (_shows('in_warranty'))
              _anchors.wrap(
                'in_warranty',
                SwitchListTile(
                  key: const ValueKey('job-in-warranty'),
                  contentPadding: EdgeInsets.zero,
                  value: isTruthyFieldValue(_values['in_warranty']),
                  onChanged: _lockedField('in_warranty') ? null : (v) => _set('in_warranty', v),
                  title: Text(tr(jobFieldLabel('in_warranty'))),
                  subtitle: Text(tr('แสดงบนรายงานบริการ')),
                ),
              ),
          ]),
        ),
      ..._extraGroups(1, miss),
    ];
  }

  // Step 3 · เมื่อไร / ใคร ------------------------------------------------------

  void _setPlan(DateTime? start, DateTime? end) {
    _patch({'plan_start': start == null ? null : wallDateTime(start), 'plan_end': end == null ? null : wallDateTime(end)});
  }

  Future<void> _openUserPicker(String key) async {
    final s = context.read<AppConfig>().session;
    final title = switch (key) {
      'engineer_user_id' => 'เลือกวิศวกรบริการ',
      'salesperson_user_id' => 'เลือกฝ่ายขาย',
      _ => 'เลือกช่าง / ผู้รับผิดชอบ',
    };
    final start = _dt(_values['plan_start']);
    final picked = await showTechnicianPicker(
      context,
      api: _api,
      title: title,
      keyPrefix: key == 'smownerid' ? 'tech' : (key == 'engineer_user_id' ? 'engineer' : 'sales'),
      jobId: _mode == DocFormMode.edit ? widget.recordId : null,
      start: key == 'salesperson_user_id' ? null : start,
      end: key == 'salesperson_user_id' ? null : _dt(_values['plan_end']),
      selectedId: _idOf(key).isEmpty ? null : _idOf(key),
      meId: s.userId,
      businessId: s.businessId,
      allowNone: key != 'smownerid',
    );
    if (picked == null || !mounted) return;
    _set(key, picked.isNone ? null : {'id': '${picked.row['id'] ?? picked.row['user_id']}', 'label': jobUserName(picked.row)});
  }

  List<Widget> _whenStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = thaiNow();
    final start = _dt(_values['plan_start']);
    final end = _dt(_values['plan_end']);
    final due = _dt(_values['due_datetime']);
    final len = start != null && end != null && end.isAfter(start) ? end.difference(start) : null;
    final canPlan = !_locked && _schema.editable('plan_start');
    final summary = jobWhenSummary(start, end, en: _en);
    final endErr = _err('plan_end', miss);
    final customEnd = _customEnd || endErr != null || (len != null && !kJobDurationHours.any((h) => len == Duration(hours: h)));
    final appointmentDone = !isBlankValue(_source['related_activity_id']);
    String userValue(String key, String empty) => _label(key).isEmpty ? tr(empty) : _label(key);
    return [
      DocSectionCard(
        key: const ValueKey('job-schedule'),
        title: 'กำหนดการ',
        icon: NxI.calendarClock,
        trailing: start != null && canPlan
            ? TextButton(key: const ValueKey('job-when-clear'), onPressed: () => _setPlan(null, null), child: Text(tr('ล้าง')))
            : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The plan in one line.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: (start == null ? cs.onSurfaceVariant : cs.primary).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(start == null ? NxI.calendarBlank : NxI.calendarCheck, color: start == null ? cs.onSurfaceVariant : cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    summary.isEmpty ? tr('ยังไม่กำหนดเวลา') : summary,
                    key: const ValueKey('job-when-summary'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: start == null ? cs.onSurfaceVariant : null),
                  ),
                  Text(
                    len == null ? tr('เลือกเวลาด่วนด้านล่าง หรือวันที่และเวลาเริ่ม') : '${tr('ใช้เวลา')} ${jobDurationText(len, en: _en)}',
                    key: const ValueKey('job-when-length'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
          if (canPlan)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in jobQuickSlots(now, length: len ?? kJobDefaultLength))
                  ChoiceChip(
                    key: ValueKey('job-slot-${s.key}'),
                    label: Text(tr(s.label)),
                    selected: start != null && start == s.start,
                    onSelected: (_) => _setPlan(s.start, s.end),
                  ),
              ]),
            ),
          _anchors.wrap(
            'plan_start',
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: NxFormField(
                  key: const ValueKey('job-start-date'),
                  uiType: FieldUiType.date,
                  label: tr('วันที่'),
                  name: 'job_plan_date',
                  value: start == null ? null : ymd(start),
                  readOnly: !canPlan,
                  errorText: trn(_err('plan_start', miss)),
                  host: _host,
                  onChanged: (v) {
                    final d = parseYmd(v);
                    if (d == null) return;
                    final m = jobMoveStart(start, end, jobOnDay(start, d));
                    _setPlan(m.start, m.end);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: NxFormField(
                  key: const ValueKey('job-start-time'),
                  uiType: FieldUiType.time,
                  label: tr('เวลาเริ่ม'),
                  name: 'job_plan_time',
                  value: start == null ? null : jobClock(start),
                  readOnly: !canPlan,
                  host: _host,
                  onChanged: (v) {
                    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch('${v ?? ''}');
                    if (m == null) return;
                    final base = start ?? DateTime(now.year, now.month, now.day);
                    final moved = jobMoveStart(start, end, jobAtTime(base, int.parse(m.group(1)!), int.parse(m.group(2)!)));
                    _setPlan(moved.start, moved.end);
                  },
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (canPlan && _schema.editable('plan_end')) ...[
            const JobLabel('ใช้เวลา'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in kJobDurationHours)
                ChoiceChip(
                  key: ValueKey('job-dur-$h'),
                  label: Text(tr(h == 8 ? 'ทั้งวัน (8 ชม.)' : '$h ชม.')),
                  selected: len == Duration(hours: h),
                  onSelected: (_) {
                    final s = start ?? jobQuickSlots(now).first.start;
                    setState(() => _customEnd = false);
                    _setPlan(s, s.add(Duration(hours: h)));
                  },
                ),
              ChoiceChip(
                key: const ValueKey('job-dur-custom'),
                label: Text(tr('กำหนดเอง')),
                selected: customEnd,
                onSelected: (_) => setState(() => _customEnd = !customEnd),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          if (customEnd) _field('plan_end', FieldUiType.dateTime, miss, label: 'สิ้นสุด (แผน)'),
          _field('due_datetime', FieldUiType.dateTime, miss, gap: 8),
          if (!_lockedField('due_datetime'))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in jobDueQuick(now, planEnd: end))
                  ChoiceChip(
                    key: ValueKey('job-due-${q.key}'),
                    label: Text(tr(q.label)),
                    selected: due != null && due == q.at,
                    onSelected: (_) => _set('due_datetime', wallDateTime(q.at)),
                  ),
              ]),
            ),
          Text(tr('เวลาเริ่ม / เสร็จจริงบันทึกจากการเช็คอินหน้างาน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Divider(height: 24),
          if (appointmentDone)
            Row(children: [
              const Icon(NxI.calendarCheck, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('งานนี้มีนัดหมายในปฏิทินแล้ว'), key: const ValueKey('job-appointment-done'), style: theme.textTheme.bodyMedium)),
            ])
          else
            SwitchListTile(
              key: const ValueKey('job-appointment'),
              contentPadding: EdgeInsets.zero,
              value: _appointment,
              onChanged: _locked
                  ? null
                  : (v) {
                      setState(() => _appointment = v);
                      _touched();
                    },
              title: Text(tr('สร้างนัดหมายในปฏิทินของช่าง')),
              subtitle: Text(tr('ใช้เวลาตามแผน — ลูกค้าเห็นนัดเดียวกับที่ช่างเห็น')),
            ),
        ]),
      ),
      DocSectionCard(
        key: const ValueKey('job-people'),
        title: 'ใครทำ',
        icon: NxI.users,
        color: const Color(0xFFF97316),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_schema.hides('smownerid'))
            _anchors.wrap(
              'smownerid',
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: JobFieldRow(
                  key: const ValueKey('job-owner-pick'),
                  icon: NxI.userCircle,
                  label: jobFieldLabel('smownerid'),
                  value: userValue('smownerid', 'ยังไม่ได้เลือก'),
                  valueKey: const ValueKey('job-owner-value'),
                  muted: _label('smownerid').isEmpty,
                  hint: tr(start == null ? 'ค้นหา ดูทักษะ และใครว่าง' : 'ดูว่าใครว่างช่วง ${jobClock(start)} และตรงทักษะ'),
                  error: trn(_err('smownerid', miss)),
                  onTap: _lockedField('smownerid') ? null : () => _openUserPicker('smownerid'),
                ),
              ),
            ),
          if (_shows('engineer_user_id'))
            _anchors.wrap(
              'engineer_user_id',
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: JobFieldRow(
                  key: const ValueKey('job-engineer-pick'),
                  icon: NxI.userCheck,
                  label: jobFieldLabel('engineer_user_id'),
                  value: userValue('engineer_user_id', 'ไม่ระบุ'),
                  valueKey: const ValueKey('job-engineer-value'),
                  muted: _label('engineer_user_id').isEmpty,
                  hint: _str('engineer_phone').isEmpty ? null : _str('engineer_phone'),
                  onTap: _lockedField('engineer_user_id') ? null : () => _openUserPicker('engineer_user_id'),
                ),
              ),
            ),
          if (_shows('assign_group')) _field('assign_group', FieldUiType.text, miss, hint: 'เช่น ทีมแอร์ A / ทีมเครือข่าย', gap: 10),
          if (_shows('salesperson_user_id'))
            _anchors.wrap(
              'salesperson_user_id',
              JobFieldRow(
                key: const ValueKey('job-sales-pick'),
                icon: NxI.briefcase,
                label: jobFieldLabel('salesperson_user_id'),
                value: userValue('salesperson_user_id', 'ไม่ระบุ'),
                valueKey: const ValueKey('job-sales-value'),
                muted: _label('salesperson_user_id').isEmpty,
                hint: _str('salesperson_phone').isEmpty ? null : _str('salesperson_phone'),
                onTap: _lockedField('salesperson_user_id') ? null : () => _openUserPicker('salesperson_user_id'),
              ),
            ),
        ]),
      ),
      ..._extraGroups(2, miss),
    ];
  }

  // Step 4 · รายละเอียดและตรวจ --------------------------------------------------

  Future<void> _attach() async {
    final hook = DocFormHooks.pickFiles;
    final files = hook != null ? await hook(context) : await pickAttachments(context);
    if (files.isEmpty || !mounted) return;
    setState(() => _files.addAll(files));
  }

  static const _layoutLabels = {'template1': 'Template-1 · Service Report เดิม', 'template2': 'Template-2 · Service Report แบบใหม่'};

  String _templateLabel() {
    final id = _str('job_template_id');
    if (id.isEmpty) return tr('ค่าเริ่มต้นของรูปแบบ');
    final t = templatesOf(_ctx).where((t) => '${t['id']}' == id).firstOrNull;
    return t == null ? '#$id' : quotationTemplateLabel(t, th: !_en);
  }

  Future<void> _openTemplatePicker() async {
    final layout = normLayout(_values['template_key']);
    final list = templatesOfLayout(templatesOf(_ctx), layout);
    final v = await showDocOptionPicker(
      context,
      title: 'เทมเพลตเอกสาร',
      keyPrefix: 'jobtpl',
      selected: _str('job_template_id'),
      options: [
        DocOption('', tr('ค่าเริ่มต้นของรูปแบบ'), icon: NxI.fileText),
        for (final t in list) DocOption('${t['id']}', quotationTemplateLabel(t, th: !_en), icon: NxI.fileText),
      ],
    );
    if (v == null || !mounted) return;
    _set('job_template_id', v.isEmpty ? null : int.tryParse(v) ?? v);
  }

  Future<void> _openDeliverablePicker() async {
    final v = await showDocOptionPicker(
      context,
      title: 'แบบรายงานส่งมอบ',
      keyPrefix: 'deliverable',
      selected: _str('deliverable_template'),
      options: [for (final c in jobChoices('deliverable_template', _schema.picklists, kDeliverableFallback, en: _en)) DocOption(c.value, c.label)],
    );
    if (v != null && mounted) _set('deliverable_template', v);
  }

  List<Widget> _detailsStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final layouts = layoutChoices(allowedLayoutsOf(_ctx), _values['template_key'], _mode);
    final layout = normLayout(_values['template_key']);
    final templates = templatesOfLayout(templatesOf(_ctx), layout);
    final edit = _mode == DocFormMode.edit;
    final descField = _schema.all['description'];
    final descType = descField != null && resolveFieldUiType(descField) == FieldUiType.richText ? FieldUiType.richText : FieldUiType.longText;
    final deliverables = jobChoices('deliverable_template', _schema.picklists, kDeliverableFallback, en: _en);
    final showDoc = (layouts.length > 1 && !_schema.hides('template_key')) || templates.isNotEmpty || _shows('deliverable_template');
    return [
      DocSectionCard(
        title: 'รายละเอียดงาน',
        subtitle: 'ช่างอ่านก่อนเข้าหน้างาน',
        icon: NxI.note,
        child: _field('description', descType, miss, hint: 'อาการ / สิ่งที่ต้องทำ / ข้อควรระวัง', gap: 0),
      ),
      if (!edit)
        DocSectionCard(
          title: 'เช็กลิสต์งาน',
          subtitle: 'สร้างเป็นกิจกรรมของงานหลังบันทึก',
          icon: NxI.listChecks,
          color: const Color(0xFF10B981),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_activityTemplates.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _activityTemplates)
                  ChoiceChip(
                    key: ValueKey('job-checklist-tpl-${t['id']}'),
                    label: Text('${t['name'] ?? ''} · ${(t['items'] as List?)?.length ?? 0}'),
                    selected: '${_checklistTemplate ?? ''}' == '${t['id']}',
                    onSelected: (on) {
                      setState(() => _checklistTemplate = on ? t['id'] : null);
                      _touched();
                    },
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            if (_checklistTemplate == null) ...[
              for (var i = 0; i < _checklist.length; i++)
                ListTile(
                  key: ValueKey('job-check-$i'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(NxI.checkSquare, size: 20),
                  title: Text(_checklist[i]),
                  trailing: IconButton(
                    tooltip: tr('ลบ'),
                    onPressed: () {
                      setState(() => _checklist.removeAt(i));
                      _touched();
                    },
                    icon: Icon(NxI.x, size: 16, color: cs.onSurfaceVariant),
                  ),
                ),
              TextField(
                key: const ValueKey('job-check-input'),
                controller: _checkItem,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(hintText: tr('เพิ่มสิ่งที่ต้องทำ แล้วกด Enter'), prefixIcon: const Icon(NxI.plus, size: 18)),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  setState(() {
                    _checklist.add(v.trim());
                    _checkItem.clear();
                  });
                  _touched();
                },
              ),
            ],
          ]),
        ),
      if (!edit)
        DocSectionCard(
          title: 'ไฟล์แนบ',
          icon: NxI.paperclip,
          color: const Color(0xFF0EA5E9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < _files.length; i++)
              ListTile(
                key: ValueKey('job-file-$i'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(NxI.file, size: 20),
                title: Text(_files[i].filename ?? tr('ไฟล์')),
                trailing: IconButton(tooltip: tr('ลบ'), onPressed: () => setState(() => _files.removeAt(i)), icon: Icon(NxI.x, size: 16, color: cs.onSurfaceVariant)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(key: const ValueKey('job-attach'), onPressed: _attach, icon: const Icon(NxI.paperclip, size: 18), label: Text(tr('แนบไฟล์ / รูป'))),
            ),
          ]),
        ),
      ..._extraGroups(3, miss),
      if (showDoc)
        JobCollapsible(
          key: const ValueKey('job-doc'),
          toggleKey: const ValueKey('job-doc-toggle'),
          title: 'เอกสาร (รายงานบริการ)',
          icon: NxI.fileText,
          color: const Color(0xFF6366F1),
          summary: [tr(_layoutLabels[layout] ?? layout), if (_shows('deliverable_template')) jobChoiceLabel(deliverables, _values['deliverable_template'])].where((x) => x.isNotEmpty).join(' · '),
          open: _docOpen || _templateNotice != null,
          onToggle: () => setState(() => _docOpen = !_docOpen),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_templateNotice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr(_templateNotice!), key: const ValueKey('job-template-notice'), style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD97706), fontWeight: FontWeight.w600)),
              ),
            if (layouts.length > 1 && !_schema.hides('template_key')) ...[
              const JobLabel('รูปแบบเอกสาร'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in layouts)
                  ChoiceChip(
                    key: ValueKey('job-layout-$k'),
                    label: Text(tr(_layoutLabels[k] ?? k)),
                    selected: layout == k,
                    onSelected: _locked ? null : (_) => _patch({'template_key': k, 'job_template_id': defaultTemplateOfLayout(templatesOf(_ctx), k, firstAsFallback: true)}),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            if (templates.isNotEmpty) ...[
              JobFieldRow(
                key: const ValueKey('job-template-pick'),
                icon: NxI.fileText,
                label: 'เทมเพลตเอกสาร (โลโก้ / หัวเอกสาร)',
                value: _templateLabel(),
                valueKey: const ValueKey('job-template-value'),
                onTap: _locked || _schema.locks('job_template_id') ? null : _openTemplatePicker,
              ),
              const SizedBox(height: 10),
            ],
            if (_shows('deliverable_template'))
              JobFieldRow(
                key: const ValueKey('job-deliverable-pick'),
                icon: NxI.clipboardText,
                label: jobFieldLabel('deliverable_template'),
                value: jobChoiceLabel(deliverables, _values['deliverable_template']).isEmpty ? tr('ไม่ระบุ') : jobChoiceLabel(deliverables, _values['deliverable_template']),
                valueKey: const ValueKey('job-deliverable-value'),
                onTap: _lockedField('deliverable_template') ? null : _openDeliverablePicker,
              ),
          ]),
        ),
      ..._review(),
      if (edit && widget.recordId != null)
        DocSectionCard(
          title: 'เอกสารจริง',
          subtitle: 'ตามที่บันทึกไว้ล่าสุด',
          icon: NxI.filePdf,
          color: const Color(0xFFDC2626),
          child: RecordDocumentTab(module: 'job', row: {..._source, 'id': widget.recordId}),
        ),
    ];
  }

  Widget _editLink(int step) => TextButton.icon(
        key: ValueKey('job-review-edit-$step'),
        onPressed: () => setState(() => _go(step)),
        icon: const Icon(NxI.pencilSimple, size: 16),
        label: Text(tr('แก้ไข')),
      );

  String _when(Object? v) {
    final d = _dt(v);
    if (d == null) return '';
    return '${jobDayLabel(d, en: _en)} ${jobClock(d)}';
  }

  List<Widget> _review() {
    final start = _dt(_values['plan_start']), end = _dt(_values['plan_end']);
    final len = start != null && end != null && end.isAfter(start) ? end.difference(start) : null;
    final caseRow = _links['case'], contractRow = _links['service_contract'];
    final site = [_str('location_name_snapshot'), siteAddressText(_values['site_address_snapshot'])].where((x) => x.isNotEmpty).join(' · ');
    return [
      DocSectionCard(
        key: const ValueKey('job-review'),
        title: 'งาน',
        icon: NxI.wrench,
        trailing: _editLink(0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('ชื่องาน', _str('job_name'), valueKey: const ValueKey('job-sum-name')),
          DocKeyValue('ประเภทงาน', jobChoiceLabel(_typeChoices, _values['job_type']), valueKey: const ValueKey('job-sum-type')),
          DocKeyValue('ความสำคัญ', tr(jobChoiceLabel(_priorityChoices, _values['job_priority']))),
          if (_str('job_category').isNotEmpty)
            DocKeyValue('ลักษณะงาน', _str('job_category') == 'other' && _str('job_category_other').isNotEmpty ? _str('job_category_other') : tr(jobChoiceLabel(_categoryChoices, _values['job_category']))),
          if (_idOf('related_case_id').isNotEmpty) DocKeyValue('เคส', caseRow == null ? '#${_idOf('related_case_id')}' : jobLinkView('case', caseRow).heading),
          if (_idOf('related_contract_id').isNotEmpty) DocKeyValue('สัญญาบริการ', contractRow == null ? '#${_idOf('related_contract_id')}' : jobLinkView('service_contract', contractRow).heading),
          if (_str('job_code').isNotEmpty) DocKeyValue('รหัสอ้างอิง', _str('job_code')),
        ]),
      ),
      DocSectionCard(
        key: const ValueKey('job-review-customer'),
        title: 'ลูกค้าและสถานที่',
        icon: NxI.mapPin,
        color: const Color(0xFF8B5CF6),
        trailing: _editLink(1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('ลูกค้า', _str('customer_name'), valueKey: const ValueKey('job-sum-customer')),
          if (_str('customer_contact_name').isNotEmpty) DocKeyValue('ผู้ติดต่อ', _str('customer_contact_name'), valueKey: const ValueKey('job-sum-contact')),
          if (_str('customer_mobile').isNotEmpty) DocKeyValue('โทรหน้างาน', _str('customer_mobile')),
          DocKeyValue('สถานที่', site, valueKey: const ValueKey('job-sum-site')),
          if (_label('related_asset_id').isNotEmpty) DocKeyValue('สินทรัพย์', _label('related_asset_id')),
        ]),
      ),
      DocSectionCard(
        key: const ValueKey('job-review-when'),
        title: 'เมื่อไร / ใคร',
        icon: NxI.calendarClock,
        color: const Color(0xFFF97316),
        trailing: _editLink(2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocKeyValue('เวลา', jobWhenSummary(start, end, en: _en), valueKey: const ValueKey('job-sum-start')),
          if (len != null) DocKeyValue('ใช้เวลา', jobDurationText(len, en: _en)),
          if (!isBlankValue(_values['due_datetime'])) DocKeyValue('กำหนดเสร็จ', _when(_values['due_datetime']), valueKey: const ValueKey('job-sum-due')),
          DocKeyValue('ช่าง', _label('smownerid'), valueKey: const ValueKey('job-sum-tech')),
          if (_label('engineer_user_id').isNotEmpty) DocKeyValue('วิศวกรบริการ', _label('engineer_user_id')),
          if (_str('assign_group').isNotEmpty) DocKeyValue('ทีม', _str('assign_group')),
          if (_appointment) DocKeyValue('นัดหมาย', tr('สร้างในปฏิทินหลังบันทึก')),
          if (_checklistTemplate != null || _checklist.isNotEmpty)
            DocKeyValue('เช็กลิสต์', _checklistTemplate != null ? '${_activityTemplates.where((t) => '${t['id']}' == '$_checklistTemplate').firstOrNull?['name'] ?? ''}' : tr('${_checklist.length} รายการ')),
          if (_files.isNotEmpty) DocKeyValue('ไฟล์แนบ', tr('${_files.length} ไฟล์')),
        ]),
      ),
    ];
  }

  /// Tablet side panel: the job at a glance.
  Widget _sideSummary() {
    final start = _dt(_values['plan_start']), end = _dt(_values['plan_end']);
    return DocSectionCard(
      title: 'สรุป',
      icon: NxI.listChecks,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DocKeyValue('ชื่องาน', _str('job_name')),
        DocKeyValue('ประเภทงาน', jobChoiceLabel(_typeChoices, _values['job_type'])),
        DocKeyValue('ลูกค้า', _str('customer_name')),
        if (_str('customer_contact_name').isNotEmpty) DocKeyValue('ผู้ติดต่อ', _str('customer_contact_name')),
        DocKeyValue('สถานที่', [_str('location_name_snapshot'), siteAddressText(_values['site_address_snapshot'])].where((x) => x.isNotEmpty).join(' · ')),
        DocKeyValue('เวลา', jobWhenSummary(start, end, en: _en)),
        DocKeyValue('ช่าง', _label('smownerid')),
      ]),
    );
  }

  Widget _bottom() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final last = _step == _steps.length - 1;
    final busy = _busy != null;
    final start = _dt(_values['plan_start']), end = _dt(_values['plan_end']);
    final when = jobWhenSummary(start, end, en: _en);
    final name = _str('job_name');
    final summary = Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: jobPriorityColor(_str('job_priority')).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
        child: Icon(NxI.wrench, size: 18, color: jobPriorityColor(_str('job_priority'))),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name.isEmpty ? tr('ยังไม่ได้ตั้งชื่องาน') : name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: name.isEmpty ? cs.onSurfaceVariant : null)),
          Text(
            [
              _str('customer_name').isEmpty ? tr('ยังไม่มีลูกค้า') : _str('customer_name'),
              when.isEmpty ? tr('ยังไม่กำหนดเวลา') : when,
              if (_label('smownerid').isNotEmpty) _label('smownerid'),
            ].join(' · '),
            key: const ValueKey('docform-bar-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    ]);
    final saveLabel = switch (_mode) {
      DocFormMode.edit => 'บันทึกการแก้ไข',
      DocFormMode.duplicate => 'สร้างจากสำเนา',
      _ => 'สร้างใบสั่งงาน',
    };
    return DocBottomBar(summary: summary, actions: [
      if (_step > 0)
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: OutlinedButton(
            key: const ValueKey('docform-back'),
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: busy ? null : () => setState(() => _go(_step - 1)),
            child: Icon(NxI.arrowLeft, size: 18, semanticLabel: tr('ย้อนกลับ')),
          ),
        ),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: last
            ? FilledButton.icon(
                key: const ValueKey('docform-save'),
                style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: busy || _locked ? null : _finish,
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.checkCircle, size: 18),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr(saveLabel), maxLines: 1)),
              )
            : FilledButton.icon(
                key: const ValueKey('docform-next'),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: busy ? null : _next,
                icon: const Icon(NxI.arrowRight, size: 18),
                label: Text(tr('ถัดไป · ${_steps[_step + 1].title}'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
      ),
    ]);
  }
}
