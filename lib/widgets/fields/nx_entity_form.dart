import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/entity_display.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import 'field_format.dart';
import 'field_ui_type.dart';
import 'field_validate.dart';
import 'nx_form_field.dart';
import 'nx_pick_option.dart';
import '../../core/i18n.dart';

class NxEntityForm extends StatefulWidget {
  const NxEntityForm({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.picklists = const {},
    this.api,
    this.module,
    this.enabled = true,
    this.errors = const {},
  });

  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
  final void Function(String name, dynamic value) onChanged;
  final Map<String, List<Map<String, dynamic>>> picklists;
  final ApiClient? api;
  final String? module;
  final bool enabled;
  final Map<String, String> errors;

  @override
  State<NxEntityForm> createState() => NxEntityFormState();
}

class NxEntityFormState extends State<NxEntityForm> {
  late final NxFieldHost _host;
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _host = NxFieldHost(
      loadUsers: widget.api == null
          ? null
          : (q) async {
              final rows = await widget.api!.getUsers(q: q);
              return rows.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
            },
      loadEntities: widget.api == null
          ? null
          : (module, q) async {
              final page = await widget.api!.getEntityList(module, limit: 30, q: q);
              return [
                for (final row in page.items)
                  NxPickOption(
                    value: strId(row['id']),
                    label: entityTitle(row, module: module),
                    subtitle: entitySubtitle(row),
                  ),
              ];
            },
      loadTags: widget.api == null
          ? null
          : (q) async {
              final rows = await widget.api!.getTags(module: widget.module, q: q);
              return rows.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
            },
      loadPackages: widget.api == null
          ? null
          : () async {
              final rows = await widget.api!.getBusinessPackages();
              return rows.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
            },
      loadPicklist: widget.api == null
          ? null
          : (name) async {
              final rows = await widget.api!.getPicklistValues(name);
              return rows.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
            },
      pickMedia: widget.api == null ? null : _pickMedia,
      uploadBytes: widget.api == null ? null : _uploadBytes,
      captureGps: () async {
        try {
          final fix = await LocationService().currentFix();
          return (lat: fix.latitude, lng: fix.longitude);
        } catch (_) {
          return null;
        }
      },
    );
  }

  Future<String?> _uploadBytes(List<int> bytes, String filename) async {
    try {
      final data = await widget.api!.uploadFiles([
        MultipartFile.fromBytes(bytes, filename: filename),
      ]);
      return extractUploadedMedia(data);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _pickMedia(NxMediaKind kind) async {
    final api = widget.api!;
    try {
      MultipartFile? part;
      if (kind == NxMediaKind.video) {
        final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (file == null) return null;
        part = MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name);
      } else if (kind == NxMediaKind.image) {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (file == null) return null;
        part = MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name);
      } else {
        final picked = await FilePicker.platform.pickFiles(withData: true);
        final f = picked?.files.single;
        if (f == null) return null;
        final bytes = f.bytes;
        if (bytes == null) return null;
        part = MultipartFile.fromBytes(bytes, filename: f.name);
      }
      final data = await api.uploadFiles([part]);
      return extractUploadedMedia(data);
    } catch (_) {
      return null;
    }
  }

  List<NxPickOption> _optionsFor(Map<String, dynamic> field) {
    final name = fieldName(field);
    final raw = widget.picklists[name] ?? const [];
    final opts = raw.map(NxPickOption.fromMap).where((o) => o.value.isNotEmpty).toList();
    final v = widget.values[name];
    if (v is Map) {
      final id = (v['id'] ?? v['value'] ?? '').toString();
      final lab = (v['label'] ?? v['name'] ?? '').toString();
      if (id.isNotEmpty && lab.isNotEmpty && opts.every((o) => o.value != id)) {
        opts.insert(0, NxPickOption(value: id, label: lab));
      }
    } else if (v != null && v.toString().isNotEmpty) {
      final related = widget.values['${name}_name'] ??
          widget.values['${name.replaceAll('_id', '')}_name'] ??
          widget.values['${name}_label'];
      if (related != null && related.toString().isNotEmpty) {
        final id = v.toString();
        if (opts.every((o) => o.value != id)) {
          opts.insert(0, NxPickOption(value: id, label: related.toString()));
        }
      }
    }
    return opts;
  }

  List<Map<String, dynamic>> _orderedFields() {
    final list = [...widget.fields];
    if (list.any((f) => fieldSequence(f) != 0)) {
      list.sort((a, b) => fieldSequence(a).compareTo(fieldSequence(b)));
    }
    return list;
  }

  bool ensureVisible(String name) {
    final ctx = _keys[name]?.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
    return true;
  }

  Widget _fieldAt(int i, Map<String, dynamic> f) {
    final name = fieldName(f);
    final visKey = (name.isNotEmpty && !_keys.containsKey(name))
        ? _keys.putIfAbsent(name, GlobalKey.new)
        : null;
    return KeyedSubtree(
      key: ValueKey('entity-field-$i-$name'),
      child: NxFormField(
        key: visKey,
        uiType: resolveFieldUiType(f),
        label: fieldLabel(f),
        name: name,
        value: widget.values[name],
        options: _optionsFor(f),
        required: fieldIsRequired(f),
        enabled: widget.enabled,
        readOnly: fieldIsReadonly(f),
        errorText: trn(widget.errors[name]),
        host: _host,
        onChanged: (v) => widget.onChanged(name, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairShort = NxBreakpoint.of(context).twoPane;
    final fields = _orderedFields();
    final children = <Widget>[];
    String? lastBlock;
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final block = fieldBlockLabel(f);
      if (block != null && block != lastBlock) {
        lastBlock = block;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              tr(block),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      final next = i + 1 < fields.length ? fields[i + 1] : null;
      final canPair = pairShort &&
          next != null &&
          fieldBlockLabel(next) == block &&
          _isShortField(resolveFieldUiType(f)) &&
          _isShortField(resolveFieldUiType(next));
      if (canPair) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fieldAt(i, f)),
              const SizedBox(width: 12),
              Expanded(child: _fieldAt(i + 1, next)),
            ],
          ),
        );
        children.add(const SizedBox(height: 20));
        i += 1;
        continue;
      }
      children.add(_fieldAt(i, f));
      children.add(const SizedBox(height: 20));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

bool _isShortField(FieldUiType type) {
  switch (type) {
    case FieldUiType.phone:
    case FieldUiType.email:
    case FieldUiType.taxId:
    case FieldUiType.number:
    case FieldUiType.percent:
    case FieldUiType.time:
    case FieldUiType.date:
    case FieldUiType.currency:
      return true;
    default:
      return false;
  }
}

String extractUploadedMedia(Map<String, dynamic> data) {
  final files = extractMapList(data['files'] ?? data);
  if (files.isNotEmpty) {
    final f = files.first;
    return formatMedia(url: (f['url'] ?? f['path'] ?? f['file_name'] ?? '').toString(), fileId: f['id'] ?? f['file_id']);
  }
  final url = (data['url'] ?? data['path'] ?? '').toString();
  return formatMedia(url: url, fileId: data['id'] ?? data['file_id']);
}

Map<String, dynamic> collectEntityPayload(
  List<Map<String, dynamic>> fields,
  Map<String, dynamic> values, {
  Map<String, dynamic>? currentRow,
}) {
  final payload = <String, dynamic>{};
  for (final f in fields) {
    final name = fieldName(f);
    if (name.isEmpty) continue;
    final v = unwrapFieldValue(values[name]);
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    final old = currentRow?[name];
    if (old is int) {
      final n = int.tryParse(v.toString());
      payload[name] = n ?? v;
    } else if (old is num) {
      final n = num.tryParse(v.toString());
      payload[name] = n ?? v;
    } else {
      payload[name] = v;
    }
  }
  return payload;
}

({Map<String, String> errors, String? first}) validateEntityFields(
  List<Map<String, dynamic>> fields,
  Map<String, dynamic> values,
) {
  final errors = <String, String>{};
  String? first;
  for (final f in fields) {
    if (fieldIsReadonly(f)) continue;
    final name = fieldName(f);
    if (name.isEmpty) continue;
    final err = validateFieldValue(
      resolveFieldUiType(f),
      unwrapFieldValue(values[name]),
      required: fieldIsRequired(f),
    );
    if (err != null) {
      errors[name] = err;
      first ??= name;
    }
  }
  return (errors: errors, first: first);
}

void applyFieldDefaults(List<Map<String, dynamic>> fields, Map<String, dynamic> values) {
  for (final f in fields) {
    final name = fieldName(f);
    if (name.isEmpty) continue;
    if (values[name] != null && values[name].toString().isNotEmpty) continue;
    final d = fieldDefaultValue(f);
    if (d != null && d.toString().isNotEmpty) {
      values[name] = d;
    }
  }
}
