import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/doc_form/doc_form_draft.dart';
import '../../core/doc_form/doc_form_rules.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../services/geo_address.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/field_validate.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/fields/nx_entity_picker_sheet.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_pin_picker.dart';
import '../crm/entity_detail_parts.dart' show pickAttachments;
import '../docs/document_tab.dart';
import 'barcode_scan_sheet.dart';
import 'doc_form_shell.dart';

const _steps = [
  DocStepInfo('งานอะไร', NxI.wrench),
  DocStepInfo('ลูกค้าและสถานที่', NxI.mapPin),
  DocStepInfo('เมื่อไร / ใคร', NxI.calendarClock),
  DocStepInfo('รายละเอียดและตรวจสร้าง', NxI.checkCircle),
];

/// Job (ใบสั่งงาน) create / edit / duplicate in 4 steps: งานอะไร → ลูกค้าและ
/// สถานที่ → เมื่อไร / ใคร → รายละเอียดและตรวจสร้าง. Saves like the web
/// (`POST /api/entity/job` · `PUT /api/entity/job/:id`); the status always
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
  List<Map<String, dynamic>> _matches = const [];
  bool _matching = false;
  bool _showLinks = false;

  // Created with the job (not columns of the job).
  bool _appointment = false;
  Object? _checklistTemplate;
  final List<String> _checklist = [];
  final List<MultipartFile> _files = [];
  final _checkItem = TextEditingController();

  ApiClient get _api => context.read<AppConfig>().apiClient;
  DocFormMode get _mode => widget.mode;

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
          values = jobDuplicateValues(row, ctx: ctx);
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
      final acc = '${unwrapFieldValue(values['related_account_id']) ?? ''}';
      if (acc.isNotEmpty && acc != 'null') {
        _loadAccountContacts(acc);
        if (_mode == DocFormMode.create) {
          // Pre-filled link (case / contract / account page): fill the customer like a pick.
          await _pickAccount({'id': acc});
        } else if (values['related_account_id'] is! Map && !isBlankValue(values['customer_name'])) {
          _values['related_account_id'] = {'id': acc, 'label': '${values['customer_name']}'};
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
    for (final k in const ['smownerid', 'engineer_user_id']) {
      final o = v[k];
      if (o == null || o is Map || '$o'.isEmpty) continue;
      String? label;
      for (final u in _users) {
        if ('${u['id'] ?? u['user_id']}' == '$o') label = '${u['display_name'] ?? u['name'] ?? u['label'] ?? ''}';
      }
      if ((label == null || label.isEmpty) && '$o' == me) label = myName;
      if ((label == null || label.isEmpty) && k == 'engineer_user_id') label = '${v['engineer_name'] ?? ''}';
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
      // End follows the start (keeps the length) unless set later.
      if (name == 'plan_start') {
        final s = _dt(v);
        final e = _dt(_values['plan_end']);
        if (s != null && (e == null || !e.isAfter(s))) _values['plan_end'] = wallDateTime(s.add(const Duration(hours: 2)));
      }
      if (name == 'engineer_user_id') _fillUser(v, 'engineer_name', 'engineer_phone');
      if (name == 'salesperson_user_id') _fillUser(v, 'salesperson_name', 'salesperson_phone');
    });
    _touched();
  }

  void _fillUser(Object? v, String nameKey, String phoneKey) {
    final id = '${unwrapFieldValue(v) ?? ''}';
    final u = _users.where((x) => '${x['id'] ?? x['user_id']}' == id).firstOrNull;
    if (u == null) {
      if (v is Map && v['label'] != null) _values[nameKey] = '${v['label']}';
      return;
    }
    _values[nameKey] = '${u['display_name'] ?? u['name'] ?? ([u['first_name'], u['last_name']].where((x) => '${x ?? ''}'.isNotEmpty).join(' '))}';
    final phone = '${u['phone_mobile'] ?? u['phone_work'] ?? u['phone'] ?? ''}';
    if (phone.isNotEmpty) _values[phoneKey] = phone;
  }

  void _touched() => _scheduleDraft();

  void _patch(Map<String, dynamic> p) {
    setState(() => _values.addAll(p));
    _touched();
  }

  DateTime? _dt(Object? v) => parseThaiField(unwrapFieldValue(v), 'plan_start', module: 'job');

  Future<void> _pickAccount(Map<String, dynamic> hit) async {
    var row = hit;
    try {
      final full = await _api.getEntity('account', '${hit['id']}');
      if (full.isNotEmpty) row = {...hit, ...full};
    } catch (_) {}
    if (!mounted) return;
    final prevAcc = '${unwrapFieldValue(_values['related_account_id']) ?? ''}';
    final p = jobAccountPatch(row, _values);
    final changed = prevAcc.isNotEmpty && prevAcc != '${row['id']}';
    _patch({
      ...p,
      'related_account_id': {'id': '${row['id']}', 'label': p['customer_name']},
      if (changed) ...{'related_contact_id': null, 'customer_contact_name': '', 'related_asset_id': null, 'related_location_id': null},
      if (isBlankValue(_values['site_address_snapshot']) || changed) 'site_address_snapshot': siteAddressOf(row),
    });
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
    if (_schema.editable('job_name') && '${_values['job_name'] ?? ''}'.trim().isEmpty) out[0]['job_name'] = 'ตั้งชื่องาน';
    if (_schema.editable('job_type') && isBlankValue(_values['job_type'])) out[0]['job_type'] = 'เลือกประเภทงาน';
    final email = '${_values['customer_email'] ?? ''}'.trim();
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
    });
    HapticFeedback.heavyImpact();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || miss.isEmpty) return;
    await _anchors.reveal(miss.keys.first, miss.keys);
  }

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
    String two(int n) => n.toString().padLeft(2, '0');
    return s == null ? '09:00' : '${two(s.hour)}:${two(s.minute)}';
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
        missing: [for (final m in missing) m.length],
        canOpen: _canOpen,
        onStep: (i) => setState(() => _go(i)),
        loading: _loading,
        embedded: widget.embedded,
        onClose: _leave,
        banners: [
          if (_locked && _lockReason != null) DocBanner(key: const ValueKey('docform-locked'), icon: NxI.lock, color: Theme.of(context).colorScheme.error, text: _lockReason!),
        ],
        body: _loading ? const SizedBox.shrink() : _loadError != null ? Center(child: Text(tr(formatApiError(_loadError!)))) : _body(missing),
        bottom: _loading || _loadError != null ? const SizedBox.shrink() : _bottom(),
        side: _loading || _loadError != null ? null : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _review()),
      ),
    );
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
        ..._extraGroups(_step, missing[_step]),
      ]),
    );
  }

  List<NxPickOption> _options(String name, List<(String, String)> fallback) {
    final raw = _schema.picklists[name] ?? const [];
    final opts = raw.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
    return opts.isNotEmpty ? opts : [for (final (v, l) in fallback) NxPickOption(value: v, label: l)];
  }

  Widget _field(String name, FieldUiType type, String label, Map<String, String> miss, {String? hint, List<NxPickOption> options = const [], bool required = false, ValueChanged<dynamic>? onChanged}) {
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

  List<Widget> _extraGroups(int step, Map<String, String> miss) => [
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
              module: 'job',
              enabled: !_locked,
              errors: _shownErrors.contains(step) ? miss : const {},
              onChanged: _set,
            ),
          ),
      ];

  // Step 1 ------------------------------------------------------------------

  List<Widget> _whatStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final parentTitle = switch (_parentModule) {
      'case' => 'สร้างจากเคส',
      'service_contract' => 'สร้างจากสัญญาบริการ',
      'quotation' => 'สร้างจากใบเสนอราคา',
      _ => '',
    };
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
          _field('job_type', FieldUiType.picklist, 'ประเภทงาน', miss, required: true, options: _options('job_type', const [('service', 'Service Job'), ('request', 'Request Job')])),
          _field('job_name', FieldUiType.text, 'ชื่องาน', miss, required: true, hint: 'เช่น ล้างแอร์ประจำปี อาคาร B'),
          if (!_schema.hides('job_priority')) ...[
            Text(tr(_schema.labelOf('job_priority', 'ความสำคัญ')), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _anchors.wrap(
              'job_priority',
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in _options('job_priority', const [('Urgent', 'เร่งด่วน'), ('High', 'สูง'), ('Normal', 'ปกติ'), ('Low', 'ต่ำ')]))
                    ChoiceChip(
                      key: ValueKey('job-priority-${o.value}'),
                      label: Text(tr(o.label)),
                      selected: '${unwrapFieldValue(_values['job_priority']) ?? ''}' == o.value,
                      onSelected: _locked || _schema.locks('job_priority') ? null : (_) => _set('job_priority', o.value),
                    ),
                ]),
              ),
            ),
          ],
        ]),
      ),
      if (_parentModule == null)
        DocSectionCard(
          title: 'เชื่อมกับเคส / สัญญา',
          subtitle: 'ไม่บังคับ',
          icon: NxI.link,
          color: const Color(0xFF64748B),
          trailing: IconButton(
            key: const ValueKey('job-links-toggle'),
            onPressed: () => setState(() => _showLinks = !_showLinks),
            icon: Icon(_showLinks ? NxI.caretUp : NxI.caretDown, size: 18),
          ),
          child: !_showLinks && isBlankValue(_values['related_case_id']) && isBlankValue(_values['related_contract_id'])
              ? Text(tr('แตะเพื่อเลือกเคสหรือสัญญาบริการที่งานนี้เกี่ยวข้อง'), style: theme.textTheme.bodySmall)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _field('related_case_id', FieldUiType.caseSelect, 'เคส', miss),
                  _field('related_contract_id', FieldUiType.contractSelect, 'สัญญาบริการ', miss),
                ]),
        ),
    ];
  }

  // Step 2 ------------------------------------------------------------------

  Future<void> _pinOnMap() async {
    final hook = DocFormHooks.pickPin;
    final p = hook != null ? await hook(context) : await showNxMapPinPicker(context, title: tr('ปักหมุดสถานที่ทำงาน'));
    if (p == null || !mounted) return;
    final lookup = DocFormHooks.reverseGeocode;
    final addr = lookup != null ? await lookup(p.lat, p.lng) : await GeoAddress.lookup(p.lat, p.lng);
    if (!mounted) return;
    final coord = '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';
    _patch({
      'site_address_snapshot': [if (addr != null && addr.trim().isNotEmpty) addr.replaceAll('\n', ' '), '($coord)'].join(' '),
      if (isBlankValue(_values['location_name_snapshot'])) 'location_name_snapshot': tr('จุดที่ปักหมุด'),
      'related_location_id': null,
    });
  }

  Future<void> _pickLocation() async {
    final acc = '${unwrapFieldValue(_values['related_account_id']) ?? ''}';
    final opt = await showNxEntityPickerSheet(
      context: context,
      title: tr('พื้นที่บริการของลูกค้า'),
      search: (q) async {
        final page = await _api.getEntityList('service_location', q: q, limit: 30, extra: {if (acc.isNotEmpty) 'related_account_id': acc});
        return [for (final r in page.items) NxPickOption(value: strId(r['id']), label: entityTitle(r, module: 'service_location'), subtitle: siteAddressOf(r))];
      },
    );
    if (opt == null || !mounted) return;
    var row = <String, dynamic>{'id': opt.value, 'location_name': opt.label};
    try {
      final full = await _api.getEntity('service_location', opt.value);
      if (full.isNotEmpty) row = {...row, ...full};
    } catch (_) {}
    if (!mounted) return;
    final p = jobLocationPatch(row, _values);
    _patch({...p, 'related_location_id': {'id': opt.value, 'label': p['location_name_snapshot']}});
  }

  Future<void> _pickAsset() async {
    final acc = '${unwrapFieldValue(_values['related_account_id']) ?? ''}';
    final opt = await showNxEntityPickerSheet(
      context: context,
      title: tr(acc.isEmpty ? 'สินทรัพย์' : 'สินทรัพย์ของลูกค้า'),
      search: (q) async {
        final page = await _api.getEntityList('asset', q: q, limit: 30, extra: {if (acc.isNotEmpty) 'related_account_id': acc});
        return [for (final r in page.items) NxPickOption(value: strId(r['id']), label: entityTitle(r, module: 'asset'), subtitle: '${r['serial_no'] ?? r['asset_code'] ?? ''}')];
      },
    );
    if (opt != null) _set('related_asset_id', {'id': opt.value, 'label': opt.label});
  }

  List<Widget> _customerStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasAcc = !isBlankValue(_values['related_account_id']);
    final assetLabel = () {
      final v = _values['related_asset_id'];
      if (v is Map) return '${v['label'] ?? v['id']}';
      return isBlankValue(v) ? '' : '#$v';
    }();
    return [
      DocSectionCard(
        title: 'ลูกค้า',
        icon: NxI.buildings,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('related_account_id', FieldUiType.accountSelect, 'บัญชีลูกค้า', miss, onChanged: (v) {
            final id = '${unwrapFieldValue(v) ?? ''}';
            if (id.isEmpty) {
              _patch({'related_account_id': null, 'related_contact_id': null});
              setState(() => _accountContacts = const []);
            } else {
              _pickAccount({'id': id});
            }
          }),
          if (!hasAcc) _field('customer_name', FieldUiType.text, 'ชื่อลูกค้า (ถ้ายังไม่มีบัญชี)', miss),
          if (_accountContacts.isNotEmpty && !_locked) ...[
            Text(tr('ผู้ติดต่อของลูกค้า'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _accountContacts.take(12))
                  ChoiceChip(
                    key: ValueKey('job-contact-${c['id']}'),
                    label: Text(entityTitle(c, module: 'contact')),
                    selected: '${unwrapFieldValue(_values['related_contact_id']) ?? ''}' == '${c['id']}',
                    onSelected: (_) => _pickContact(c),
                  ),
              ]),
            ),
          ],
          _field('related_contact_id', FieldUiType.contactSelect, 'ผู้ติดต่อ', miss, onChanged: (v) {
            final id = '${unwrapFieldValue(v) ?? ''}';
            if (id.isEmpty) {
              _patch({'related_contact_id': null});
            } else {
              _pickContact({'id': id});
            }
          }),
          _field('customer_mobile', FieldUiType.phone, 'มือถือผู้ติดต่อหน้างาน', miss),
          _field('customer_email', FieldUiType.email, 'อีเมลผู้ติดต่อ', miss),
        ]),
      ),
      DocSectionCard(
        title: 'สถานที่ทำงาน',
        icon: NxI.mapPin,
        color: const Color(0xFF8B5CF6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_locked)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (hasAcc)
                  ActionChip(
                    key: const ValueKey('job-place-account'),
                    avatar: const Icon(NxI.buildings, size: 16),
                    label: Text(tr('ที่อยู่ลูกค้า')),
                    onPressed: () => _pickAccount({'id': '${unwrapFieldValue(_values['related_account_id'])}'}).then((_) async {
                      try {
                        final a = await _api.getEntity('account', '${unwrapFieldValue(_values['related_account_id'])}');
                        if (mounted) _patch({'site_address_snapshot': siteAddressOf(a), 'related_location_id': null});
                      } catch (_) {}
                    }),
                  ),
                if (!_schema.hides('related_location_id'))
                  ActionChip(key: const ValueKey('job-place-location'), avatar: const Icon(NxI.mapTrifold, size: 16), label: Text(tr('พื้นที่บริการ')), onPressed: _pickLocation),
                ActionChip(key: const ValueKey('job-place-pin'), avatar: const Icon(NxI.mapPinned, size: 16), label: Text(tr('ปักหมุดบนแผนที่')), onPressed: _pinOnMap),
              ]),
            ),
          _field('location_name_snapshot', FieldUiType.text, 'ชื่อสถานที่', miss),
          _field('site_address_snapshot', FieldUiType.longText, 'ที่อยู่หน้างาน', miss),
        ]),
      ),
      if (!_schema.hides('related_asset_id'))
        DocSectionCard(
          title: 'สินทรัพย์ / เครื่องของลูกค้า',
          subtitle: 'ไม่บังคับ',
          icon: NxI.hardDrives,
          color: const Color(0xFF0EA5E9),
          child: _anchors.wrap(
            'related_asset_id',
            Row(children: [
              Expanded(child: Text(assetLabel.isEmpty ? tr('ยังไม่ได้เลือก') : assetLabel, key: const ValueKey('job-asset-label'), style: theme.textTheme.bodyMedium?.copyWith(color: assetLabel.isEmpty ? cs.onSurfaceVariant : null))),
              if (!_locked && !_schema.locks('related_asset_id')) ...[
                if (assetLabel.isNotEmpty) IconButton(tooltip: tr('ล้าง'), onPressed: () => _set('related_asset_id', null), icon: const Icon(NxI.x, size: 18)),
                TextButton.icon(key: const ValueKey('job-asset-pick'), onPressed: _pickAsset, icon: const Icon(NxI.magnifyingGlass, size: 16), label: Text(tr('เลือก'))),
              ],
            ]),
          ),
        ),
    ];
  }

  // Step 3 ------------------------------------------------------------------

  List<Widget> _whenStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final now = thaiNow();
    final start = _dt(_values['plan_start']);
    final saved = _mode == DocFormMode.edit ? widget.recordId : null;
    return [
      DocSectionCard(
        title: 'กำหนดการ',
        icon: NxI.calendarClock,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_locked && _schema.editable('plan_start'))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in jobQuickSlots(now))
                  ChoiceChip(
                    key: ValueKey('job-slot-${s.key}'),
                    label: Text(tr(s.label)),
                    selected: start != null && start == s.start,
                    onSelected: (_) => _patch({'plan_start': wallDateTime(s.start), 'plan_end': wallDateTime(s.end)}),
                  ),
              ]),
            ),
          _field('plan_start', FieldUiType.dateTime, 'เริ่ม (แผน)', miss),
          _field('plan_end', FieldUiType.dateTime, 'สิ้นสุด (แผน)', miss),
          if (start != null && !_locked && _schema.editable('plan_end'))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in const [1, 2, 4, 8])
                  ActionChip(
                    key: ValueKey('job-end-plus-$h'),
                    label: Text(tr('+$h ชม.')),
                    onPressed: () => _set('plan_end', wallDateTime(start.add(Duration(hours: h)))),
                  ),
              ]),
            ),
          _field('due_datetime', FieldUiType.dateTime, 'กำหนดเสร็จ', miss),
          Text(tr('เวลาเริ่ม / เสร็จจริงบันทึกจากการเช็คอินหน้างาน'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
      DocSectionCard(
        title: 'ใครทำ',
        icon: NxI.users,
        color: const Color(0xFFF97316),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('smownerid', FieldUiType.owner, 'ช่างผู้รับผิดชอบ', miss),
          if (_schema.has('engineer_user_id')) _field('engineer_user_id', FieldUiType.owner, 'วิศวกรบริการ', miss),
          if (saved != null && !_locked) ...[
            OutlinedButton.icon(
              key: const ValueKey('job-match-users'),
              onPressed: _matching
                  ? null
                  : () async {
                      setState(() => _matching = true);
                      try {
                        final d = await _api.matchJobUsers(saved);
                        if (mounted) setState(() => _matches = extractMapList(d));
                      } catch (e) {
                        _snack(tr(formatApiError(e)));
                      } finally {
                        if (mounted) setState(() => _matching = false);
                      }
                    },
              icon: const Icon(NxI.userCheck, size: 18),
              label: Text(tr('ช่างที่ตรงทักษะของงานนี้')),
            ),
            for (final u in _matches)
              ListTile(
                key: ValueKey('job-match-${u['id'] ?? u['user_id']}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(NxI.userCircle),
                title: Text('${u['display_name'] ?? u['name'] ?? u['email'] ?? ''}'),
                subtitle: u['email'] == null ? null : Text('${u['email']}'),
                trailing: const Icon(NxI.plus, size: 18),
                onTap: () => _set('smownerid', {'id': '${u['id'] ?? u['user_id']}', 'label': '${u['display_name'] ?? u['name'] ?? ''}'}),
              ),
          ] else
            Text(tr('หลังสร้างงาน ระบบช่วยหาช่างที่ตรงทักษะของงานได้ในแท็บปฏิบัติงาน'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
      DocSectionCard(
        title: 'นัดหมายลูกค้า',
        icon: NxI.calendarCheck,
        color: const Color(0xFF10B981),
        child: !isBlankValue(_source['related_activity_id'])
            ? Text(tr('งานนี้มีนัดหมายในปฏิทินแล้ว'), style: theme.textTheme.bodyMedium)
            : SwitchListTile(
                key: const ValueKey('job-appointment'),
                contentPadding: EdgeInsets.zero,
                value: _appointment,
                onChanged: _locked
                    ? null
                    : (v) {
                        setState(() => _appointment = v);
                        _touched();
                      },
                title: Text(tr('สร้างนัดหมายกับลูกค้าในปฏิทินของช่าง')),
                subtitle: Text(tr('ใช้เวลาเริ่มตามแผน — ลูกค้าเห็นนัดเดียวกับที่ช่างเห็น')),
              ),
      ),
    ];
  }

  // Step 4 ------------------------------------------------------------------

  Future<void> _attach() async {
    final hook = DocFormHooks.pickFiles;
    final files = hook != null ? await hook(context) : await pickAttachments(context);
    if (files.isEmpty || !mounted) return;
    setState(() => _files.addAll(files));
  }

  List<Widget> _detailsStep(Map<String, String> miss) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final templates = templatesOf(_ctx);
    final layouts = layoutChoices(allowedLayoutsOf(_ctx), _values['template_key'], _mode);
    final layout = normLayout(_values['template_key']);
    final edit = _mode == DocFormMode.edit;
    return [
      DocSectionCard(
        title: 'รายละเอียดงาน',
        icon: NxI.note,
        child: _field('description', FieldUiType.longText, 'รายละเอียด / สิ่งที่ต้องทำ', miss),
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
      if (layouts.length > 1 && !_schema.hides('template_key'))
        DocSectionCard(
          title: 'รูปแบบเอกสาร',
          icon: NxI.fileText,
          color: const Color(0xFF6366F1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_templateNotice != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr(_templateNotice!), style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD97706)))),
            Wrap(spacing: 8, children: [
              for (final k in layouts)
                ChoiceChip(
                  key: ValueKey('job-layout-$k'),
                  label: Text(tr(k == 'template2' ? 'เทมเพลต 2' : 'เทมเพลต 1')),
                  selected: layout == k,
                  onSelected: _locked ? null : (_) => _patch({'template_key': k, 'job_template_id': defaultTemplateOfLayout(templates, k, firstAsFallback: true)}),
                ),
            ]),
          ]),
        ),
      _review(),
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

  String _label(String key) {
    final v = _values[key];
    if (v is Map) return '${v['label'] ?? v['id'] ?? ''}';
    return isBlankValue(v) ? '' : '$v';
  }

  String _when(Object? v) {
    final d = _dt(v);
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${uiYear(d.year)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _review() {
    final type = _options('job_type', const [('service', 'Service Job'), ('request', 'Request Job')])
        .where((o) => o.value == '${unwrapFieldValue(_values['job_type']) ?? ''}')
        .firstOrNull
        ?.label;
    return DocSectionCard(
      key: const ValueKey('job-review'),
      title: 'ตรวจก่อนบันทึก',
      icon: NxI.listChecks,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DocKeyValue('ชื่องาน', '${_values['job_name'] ?? ''}', valueKey: const ValueKey('job-sum-name')),
        DocKeyValue('ประเภท', type ?? '${_values['job_type'] ?? ''}'),
        DocKeyValue('ลูกค้า', '${_values['customer_name'] ?? ''}', valueKey: const ValueKey('job-sum-customer')),
        if ('${_values['customer_contact_name'] ?? ''}'.isNotEmpty) DocKeyValue('ผู้ติดต่อ', '${_values['customer_contact_name']}'),
        DocKeyValue('สถานที่', ['${_values['location_name_snapshot'] ?? ''}', '${_values['site_address_snapshot'] ?? ''}'].where((x) => x.trim().isNotEmpty).join(' · ')),
        DocKeyValue('เริ่ม', _when(_values['plan_start']), valueKey: const ValueKey('job-sum-start')),
        DocKeyValue('สิ้นสุด', _when(_values['plan_end'])),
        DocKeyValue('ช่าง', _label('smownerid'), valueKey: const ValueKey('job-sum-tech')),
        if (_appointment) DocKeyValue('นัดหมาย', tr('สร้างในปฏิทินหลังบันทึก')),
        if (_checklistTemplate != null || _checklist.isNotEmpty)
          DocKeyValue('เช็กลิสต์', _checklistTemplate != null ? '${_activityTemplates.where((t) => '${t['id']}' == '$_checklistTemplate').firstOrNull?['name'] ?? ''}' : tr('${_checklist.length} รายการ')),
        if (_files.isNotEmpty) DocKeyValue('ไฟล์แนบ', tr('${_files.length} ไฟล์')),
      ]),
    );
  }

  Widget _bottom() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final last = _step == _steps.length - 1;
    final busy = _busy != null;
    final when = _when(_values['plan_start']);
    final summary = Row(children: [
      Icon(NxI.wrench, size: 18, color: cs.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${_values['job_name'] ?? ''}'.trim().isEmpty ? tr('ยังไม่ได้ตั้งชื่องาน') : '${_values['job_name']}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            [
              '${_values['customer_name'] ?? ''}'.trim().isEmpty ? tr('ยังไม่มีลูกค้า') : '${_values['customer_name']}',
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
    return DocBottomBar(summary: summary, actions: [
      if (_step > 0)
        SizedBox(
          height: 50,
          child: OutlinedButton(
            key: const ValueKey('docform-back'),
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: busy ? null : () => setState(() => _go(_step - 1)),
            child: const Icon(NxI.arrowLeft, size: 18),
          ),
        ),
      SizedBox(
        height: 50,
        child: last
            ? FilledButton.icon(
                key: const ValueKey('docform-save'),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: busy || _locked ? null : _finish,
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.check, size: 18),
                label: Text(tr(_mode == DocFormMode.edit ? 'บันทึก' : 'สร้างใบสั่งงาน')),
              )
            : FilledButton.icon(
                key: const ValueKey('docform-next'),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: busy ? null : _next,
                icon: const Icon(NxI.arrowRight, size: 18),
                label: Text(tr('ถัดไป · ${_steps[_step + 1].title}')),
              ),
      ),
    ]);
  }
}
