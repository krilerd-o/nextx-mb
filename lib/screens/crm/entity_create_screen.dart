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
      _fields = widget.fields!;
      _picklists = widget.picklists ?? {};
      applyFieldDefaults(_fields, _values);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final schema = await context.read<AppConfig>().apiClient.getFieldSchema(widget.module);
      final fields = schema.fields.where((f) {
        final name = fieldName(f);
        if (name.isEmpty || name == 'id' || name == 'business_id') return false;
        return !fieldIsReadonly(f);
      }).toList();
      if (mounted) {
        setState(() {
          _fields = fields;
          _picklists = schema.picklists;
          applyFieldDefaults(_fields, _values);
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
        if (result.first != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _formKey.currentState?.ensureVisible(result.first!);
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('กรอกช่องที่จำเป็นและตรวจรูปแบบก่อนบันทึก'))),
        );
        return;
      }
    }
    setState(() {
      _errors = {};
      _saving = true;
    });
    final payload = collectEntityPayload(_fields, _values, currentRow: widget.initialValues);
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
          : NxContentWidth(
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
                children: [
                  if (_error != null)
                    Text(tr(formatApiError(_error!)), style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                      onChanged: (name, v) => setState(() {
                        _values[name] = v;
                        _errors.remove(name);
                      }),
                    ),
                  KeyedSubtree(
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
                ],
              ),
            ),
    );
  }
}
