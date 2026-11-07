import 'package:flutter/material.dart';
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
import '../../widgets/fields/field_validate.dart';
import 'package:flutter/services.dart';

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
  });

  final String module;
  final String title;
  final String? recordId;
  final Map<String, dynamic>? initialValues;
  final List<Map<String, dynamic>>? fields;
  final Map<String, List<Map<String, dynamic>>>? picklists;
  final bool embedded;
  final ValueChanged<bool>? onFinished;

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
    } else {
      _load();
    }
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
        final start = DateTime.tryParse('${v ?? ''}'.replaceFirst(' ', 'T'));
        final end = DateTime.tryParse('${_values['date_end'] ?? ''}'.replaceFirst(' ', 'T'));
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
    final payload = collectEntityPayload(_fields, _values, currentRow: widget.initialValues);
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
      if (widget.isEdit) {
        await api.putEntity(widget.module, widget.recordId!, payload);
      } else {
        await api.postEntity(widget.module, payload);
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

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final pad = NxBreakpoint.of(context).pagePadding;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: NxAppHeader(
        title: widget.title,
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
                  _RequiredProgress(done: _requiredDone, total: _requiredCount),
                Expanded(
                  child: NxContentWidth(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (_error != null)
                          Text(tr(formatApiError(_error!)), style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                ),
              ],
            ),
    );
  }
}

/// Thin bar under the header: how many required fields are filled.
class _RequiredProgress extends StatelessWidget {
  const _RequiredProgress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final complete = done >= total;
    final color = complete ? const Color(0xFF10B981) : cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
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
          ),
          const SizedBox(width: 10),
          Text(
            complete ? tr('กรอกช่องจำเป็นครบแล้ว') : tr('ช่องจำเป็น $done/$total'),
            style: theme.textTheme.labelMedium?.copyWith(color: complete ? color : cs.onSurfaceVariant),
          ),
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
