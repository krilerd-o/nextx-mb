import 'package:flutter/material.dart';
import 'card_scan/card_scan_flow.dart';
import 'card_scan/card_scan_models.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../core/entity_form_rules.dart';
import '../../core/thai_time.dart';
import '../../widgets/fields/field_validate.dart';
import 'package:flutter/services.dart';
import '../../widgets/nx_unsaved_guard.dart';

class EntityCreateScreen extends StatefulWidget {
  const EntityCreateScreen({
    super.key,
    required this.module,
    required this.title,
    this.recordId,
    this.initialValues,
    this.fields,
    this.picklists,
    this.embedded = false,
    this.onFinished,
    this.autoScan = false,
  });

  final String module;
  final String title;
  final String? recordId;
  final Map<String, dynamic>? initialValues;
  final List<Map<String, dynamic>>? fields;
  final Map<String, List<Map<String, dynamic>>>? picklists;
  final bool embedded;
  final ValueChanged<bool>? onFinished;

  /// Opened from "สแกนนามบัตร": start the card scan once the form is ready.
  final bool autoScan;

  bool get isEdit => recordId != null && recordId!.isNotEmpty;

  @override
  State<EntityCreateScreen> createState() => _EntityCreateScreenState();
}

class _EntityCreateScreenState extends State<EntityCreateScreen> {
  List<Map<String, dynamic>> _fields = [];
  Map<String, List<Map<String, dynamic>>> _picklists = {};
  final _values = <String, dynamic>{};
  final _formKey = GlobalKey<NxEntityFormState>();
  Map<String, String> _errors = {};
  bool _loading = true;
  bool _saving = false;

  /// Card scan (Lead / Contact / Account): fields filled from the card and
  /// the photo(s) to attach after saving.
  bool get _canScan => kCardScanModules.contains(widget.module) && _fields.isNotEmpty;
  List<String> _scannedLabels = const [];
  CardImages? _attachCard;
  bool _autoScanDone = false;

  Future<void> _scanCard() async {
    final formFields = <String, String>{
      for (final f in _fields)
        if (!fieldIsReadonly(f) && fieldName(f).isNotEmpty) fieldName(f): (f['label_th'] ?? f['label'] ?? fieldName(f)).toString(),
    };
    final r = await CardScanFlow.run(context, module: widget.module, formFields: formFields, currentValues: Map.of(_values));
    if (r == null || !mounted) return;
    setState(() {
      r.values.forEach((k, v) => _values[k] = v);
      if (r.note != null && formFields.containsKey('description')) {
        final cur = '${_values['description'] ?? ''}'.trim();
        _values['description'] = cur.isEmpty ? r.note : '$cur\n${r.note}';
      }
      _scannedLabels = [for (final k in r.values.keys) formFields[k] ?? k];
      _attachCard = r.attach ? r.images : null;
      _errors = {};
    });
    // The green "เติมจากนามบัตร" banner says what was filled (no snackbar over the Save button).
    HapticFeedback.lightImpact();
  }

  /// "เฉพาะช่องจำเป็น": a short form with just what must be filled.
  bool _requiredOnly = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialValues != null) {
      _values.addAll(widget.initialValues!);
    }
    if (widget.fields != null && widget.fields!.isNotEmpty) {
      _fields = _prepare(widget.fields!);
      _picklists = widget.picklists ?? {};
      _applyDefaults();
      _loading = false;
      _maybeAutoScan();
    } else {
      _load();
    }
  }

  void _maybeAutoScan() {
    if (!widget.autoScan || _autoScanDone || !_canScan) return;
    _autoScanDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanCard();
    });
  }

  /// Drops system columns and marks the fields the web always requires.
  List<Map<String, dynamic>> _prepare(List<Map<String, dynamic>> fields) => [
        for (final f in fields)
          if (!kSkipCreateColumns.contains(fieldName(f)) && f['type'] != 'Counter')
            moduleRequiresField(widget.module, fieldName(f)) ? {...f, 'required': true} : f,
      ];

  /// New records start like on the web: owner = me, first status, today…;
  /// then the schema's own default values. Edits keep the stored values.
  void _applyDefaults() {
    if (!widget.isEdit) {
      final names = {for (final f in _fields) fieldName(f)};
      final defs = createDefaults(
        widget.module,
        userId: context.read<AppConfig>().session.userId,
        picklists: _picklists,
      );
      final session = context.read<AppConfig>().session;
      defs.forEach((k, v) {
        final cur = _values[k];
        if (v == null || !names.contains(k) || (cur != null && '$cur'.isNotEmpty)) return;
        // Owner = me: carry my name so the user picker shows it straight away.
        _values[k] = k == 'smownerid'
            ? {'id': '$v', 'label': session.displayName ?? session.email ?? '$v'}
            : v;
      });
    }
    applyFieldDefaults(_fields, _values);
    normalizeFormDates(_fields, _values, module: widget.module);
  }

  /// The case subject suggested from its type (while the user hasn't typed one).
  String? _lastSuggestion;

  void _onField(String name, dynamic v) {
    setState(() {
      _values[name] = v;
      _errors.remove(name);
      if (widget.module == 'case' && name == 'case_type') {
        final cur = '${_values['case_name'] ?? ''}'.trim();
        if (cur.isEmpty || cur == _lastSuggestion) {
          _lastSuggestion = caseSubjectSuggestion('${v ?? ''}');
          _values['case_name'] = _lastSuggestion;
          _errors.remove('case_name');
        }
      }
      // An appointment ends an hour after it starts unless set later.
      if (widget.module == 'activity' && name == 'date_start') {
        // Both as Thai wall-clock time (the stored end may still carry a zone).
        final start = parseThaiField(v, 'date_start', module: 'activity');
        final end = parseThaiField(_values['date_end'], 'date_end', module: 'activity');
        if (start != null && (end == null || !end.isAfter(start))) {
          final e = start.add(const Duration(hours: 1));
          String two(int n) => n.toString().padLeft(2, '0');
          _values['date_end'] = '${e.year}-${two(e.month)}-${two(e.day)} ${two(e.hour)}:${two(e.minute)}:00';
        }
      }
    });
  }

  int get _requiredCount => _fields.where(fieldIsRequired).length;
  int get _requiredDone => _fields.where((f) {
        if (!fieldIsRequired(f)) return false;
        final v = unwrapFieldValue(_values[fieldName(f)]);
        return v != null && (v is! String || v.trim().isNotEmpty) && (v is! List || v.isNotEmpty);
      }).length;

  Future<void> _load() async {
    try {
      final schema = await context.read<AppConfig>().apiClient.getFieldSchema(widget.module);
      final fields = _prepare(schema.fields.where((f) {
        final name = fieldName(f);
        if (name.isEmpty || name == 'id' || name == 'business_id') return false;
        return !fieldIsReadonly(f);
      }).toList());
      if (mounted) {
        setState(() {
          _fields = fields;
          _picklists = schema.picklists;
          _applyDefaults();
          _loading = false;
        });
        _maybeAutoScan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_fields.isEmpty) {
      if ((_values['subject']?.toString() ?? '').trim().isEmpty) {
        setState(() => _errors = {'subject': 'จำเป็นต้องกรอก'});
        return;
      }
    } else {
      final result = validateEntityFields(_fields, _values);
      if (result.errors.isNotEmpty) {
        setState(() => _errors = result.errors);
        HapticFeedback.heavyImpact();
        if (result.first != null) {
          // Jump to the first one, then shake every field still missing.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _formKey.currentState?.revealErrors(result.first!, result.errors.keys);
          });
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('ยังไม่ได้กรอก ${result.errors.length} ช่องที่จำเป็น/ไม่ถูกรูปแบบ'))),
        );
        return;
      }
    }
    setState(() {
      _errors = {};
      _saving = true;
    });
    final payload = collectEntityPayload(_fields, _values, currentRow: widget.initialValues, module: widget.module);
    // Links set by the caller (e.g. an appointment booked from a record) are
    // sent even when the form doesn't show those fields.
    if (!widget.isEdit) {
      for (final k in const ['related_module', 'related_id']) {
        final v = widget.initialValues?[k];
        if (v != null && payload[k] == null) payload[k] = v;
      }
    }
    if (payload.isEmpty && _values['subject'] != null) {
      payload['subject'] = _values['subject'];
    }
    try {
      final api = context.read<AppConfig>().apiClient;
      String? id = widget.recordId;
      if (widget.isEdit) {
        await api.putEntity(widget.module, widget.recordId!, payload);
      } else {
        final res = await api.postEntity(widget.module, payload);
        id = '${res['id'] ?? res['insertId'] ?? res['record']?['id'] ?? ''}';
      }
      // Card photo goes with the saved record (a failure never undoes the save).
      final card = _attachCard;
      if (card != null && id != null && id.isNotEmpty && id != 'null') {
        final messenger = ScaffoldMessenger.of(context);
        CardScanFlow.attachToRecord(api, module: widget.module, id: id, images: card).catchError((Object e) {
          messenger.showSnackBar(SnackBar(content: Text(tr('บันทึกแล้ว แต่แนบรูปนามบัตรไม่สำเร็จ: ${formatApiError(e)}'))));
        });
      }
      if (mounted) _finish(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finish(bool ok) {
    if (widget.embedded) {
      widget.onFinished?.call(ok);
    } else {
      Navigator.pop(context, ok);
    }
  }

  // Back / swipe asks before throwing away what was typed.
  @override
  Widget build(BuildContext context) => NxUnsavedGuard(
        enabled: !widget.embedded,
        snapshot: () => '$_values',
        child: _buildForm(context),
      );


  Widget _buildForm(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final pad = NxBreakpoint.of(context).pagePadding;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: NxAppHeader(
        title: widget.title,
        actions: [
          if (_canScan)
            IconButton(
              key: const ValueKey('form-scan-card'),
              tooltip: tr('สแกนนามบัตร'),
              icon: const Icon(NxI.idCard),
              onPressed: _scanCard,
            ),
        ],
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? IconButton(
                tooltip: tr('ปิด'),
                onPressed: () => _finish(false),
                icon: const Icon(NxI.x),
              )
            : null,
      ),
      body: _loading
          ? const NxSkeletonForm()
          : Column(
              children: [
                if (_fields.isNotEmpty && _requiredCount > 0)
                  _RequiredProgress(
                    done: _requiredDone,
                    total: _requiredCount,
                    requiredOnly: _requiredOnly,
                    onRequiredOnly: (v) => setState(() => _requiredOnly = v),
                  ),
                Expanded(
                  child: NxContentWidth(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (_error != null)
                          Text(tr(formatApiError(_error!)), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        if (_canScan && _scannedLabels.isEmpty && !widget.isEdit)
                          _ScanBanner(onTap: _scanCard),
                        if (_scannedLabels.isNotEmpty)
                          _ScannedBanner(labels: _scannedLabels, attach: _attachCard != null, onRescan: _scanCard),
                        if (!widget.isEdit && kFormInsight[widget.module] != null)
                          _InsightBanner(text: kFormInsight[widget.module]!),
                        if (_fields.isEmpty)
                          NxFormField(
                            uiType: FieldUiType.text,
                            label: 'ชื่อเรื่อง',
                            required: true,
                            errorText: trn(_errors['subject']),
                            value: _values['subject'],
                            onChanged: (v) => setState(() => _values['subject'] = v),
                          )
                        else
                          NxEntityForm(
                            key: _formKey,
                            fields: _fields,
                            values: _values,
                            picklists: _picklists,
                            api: api,
                            module: widget.module,
                            errors: _errors,
                            sectionOf: (name) => formSectionOf(widget.module, name),
                            sections: kFormSections,
                            sectionOrder: kFormSectionOrder,
                            requiredOnly: _requiredOnly,
                            onChanged: _onField,
                          ),
                      ],
                    ),
                  ),
                ),
                // Save stays reachable while scrolling a long form.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 10),
                    child: Row(children: [
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          key: const ValueKey('entity-cancel'),
                          style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 22)),
                          onPressed: _saving ? null : () => _finish(false),
                          child: Text(tr('ยกเลิก')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyedSubtree(
                          key: const ValueKey('entity-save'),
                          child: NxHeroCta(
                            label: widget.isEdit ? 'บันทึก' : 'สร้าง',
                            busy: _saving,
                            onPressed: _saving
                                ? null
                                : () {
                                    Feedback.forTap(context);
                                    _save();
                                  },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Thin bar under the header: how many required fields are filled.
class _RequiredProgress extends StatelessWidget {
  const _RequiredProgress({required this.done, required this.total, required this.requiredOnly, required this.onRequiredOnly});
  final int done;
  final int total;
  final bool requiredOnly;
  final ValueChanged<bool> onRequiredOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final complete = done >= total;
    final color = complete ? const Color(0xFF10B981) : cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                complete ? tr('กรอกช่องจำเป็นครบแล้ว') : tr('ช่องจำเป็น $done/$total'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: complete ? color : cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
            // Short form: only required fields (+ what is already filled).
            FilterChip(
              key: const ValueKey('form-required-only'),
              label: Text(tr('เฉพาะที่จำเป็น')),
              selected: requiredOnly,
              showCheckmark: true,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              onSelected: onRequiredOnly,
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: total == 0 ? 1 : done / total),
              duration: const Duration(milliseconds: 300),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                color: color,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "สแกนนามบัตร" call-to-action on a new Lead / Contact / Account.
class _ScanBanner extends StatelessWidget {
  const _ScanBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const ValueKey('form-scan-banner'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: cs.primary.withValues(alpha: 0.15), child: Icon(NxI.idCard, color: cs.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('สแกนนามบัตร'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(tr('ถ่ายหรือเลือกรูปนามบัตร แล้วกรอกให้อัตโนมัติ'), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(NxI.caretRight, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which fields came from the card (the user still checks and saves).
class _ScannedBanner extends StatelessWidget {
  const _ScannedBanner({required this.labels, required this.attach, required this.onRescan});
  final List<String> labels;
  final bool attach;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF16A34A);
    return Container(
      key: const ValueKey('form-scanned'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(NxI.idCard, size: 18, color: green)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('เติมจากนามบัตร ${labels.length} ช่อง — ตรวจสอบแล้วกดบันทึก'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(labels.map(tr).join(' · '), style: theme.textTheme.bodySmall),
                if (attach)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr('จะแนบรูปนามบัตรให้หลังบันทึก'), style: theme.textTheme.bodySmall?.copyWith(color: green)),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onRescan, child: Text(tr('สแกนใหม่'))),
        ],
      ),
    );
  }
}

class _InsightBanner extends StatelessWidget {
  const _InsightBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(NxI.sparkle, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(tr(text), style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
