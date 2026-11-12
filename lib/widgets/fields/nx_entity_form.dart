import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../nx_icons.dart';
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
import '../nx_shake.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';

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
    this.sectionOf,
    this.sections = const {},
    this.sectionOrder = const [],
    this.requiredOnly = false,
  });

  /// Groups fields into titled cards (web "modern form" sections) when set.
  final String Function(String name)? sectionOf;
  final Map<String, ({String title, IconData icon, Color color})> sections;
  final List<String> sectionOrder;

  /// Show only required fields (and anything already filled in): a short,
  /// easy form; the rest is one tap away.
  final bool requiredOnly;

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
  final _shakers = <String, GlobalKey<NxShakeState>>{};

  /// Folded section cards (tap the header); a section opens again by itself
  /// when one of its fields needs attention.
  final Set<String> _collapsed = {};
  final _sectionKeys = <String, GlobalKey>{};

  void jumpToSection(String key) {
    setState(() => _collapsed.remove(key));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sectionKeys[key]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.02, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      }
    });
  }

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

  /// Product / service discount: `<x>_discount` + `<x>_discount_type` ('amount' baht | 'percent').
  /// The type is a บาท / % toggle next to the number (same as the web), not a field of its own.
  static final _discountRe = RegExp(r'^(product|service)_discount$');
  bool _hasDiscountType(String name) =>
      _discountRe.hasMatch(name) && widget.fields.any((f) => fieldName(f) == '${name}_type');

  List<Map<String, dynamic>> _orderedFields() {
    final names = {for (final f in widget.fields) fieldName(f)};
    final list = [
      for (final f in widget.fields)
        if (!(fieldName(f).endsWith('_discount_type') && names.contains(fieldName(f).replaceFirst(RegExp(r'_type$'), '')))) f,
    ];
    if (list.any((f) => fieldSequence(f) != 0)) {
      list.sort((a, b) => fieldSequence(a).compareTo(fieldSequence(b)));
    }
    return list;
  }

  bool ensureVisible(String name) {
    final sec = widget.sectionOf?.call(name);
    if (sec != null && _collapsed.remove(sec)) setState(() {});
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

  /// Scrolls to [first] (the first missing/invalid field), then shakes every
  /// field in [names] with a short vibration so the user sees what's left.
  Future<void> revealErrors(String first, Iterable<String> names) async {
    var opened = false;
    for (final n in names) {
      final sec = widget.sectionOf?.call(n);
      if (sec != null && _collapsed.remove(sec)) opened = true;
    }
    if (opened) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    ensureVisible(first);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    var haptic = true;
    for (final n in names) {
      _shakers[n]?.currentState?.shake(haptic: haptic);
      haptic = false;
    }
  }

  Widget _fieldAt(int i, Map<String, dynamic> f) {
    final name = fieldName(f);
    // Same key on every build, so revealErrors() can always find the field.
    final visKey = name.isNotEmpty ? _keys.putIfAbsent(name, GlobalKey.new) : null;
    return NxShake(
      key: name.isEmpty ? null : _shakers.putIfAbsent(name, GlobalKey<NxShakeState>.new),
      child: KeyedSubtree(
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
      ),
    );
  }

  Widget _fieldOrDiscount(int i, Map<String, dynamic> f) {
    final name = fieldName(f);
    if (!_hasDiscountType(name)) return _fieldAt(i, f);
    final typeKey = '${name}_type';
    final percent = '${unwrapFieldValue(widget.values[typeKey]) ?? ''}' == 'percent';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _fieldAt(i, f)),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: SegmentedButton<String>(
            key: ValueKey('discount-type-$name'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: 'amount', label: Text(tr('บาท'))),
              const ButtonSegment(value: 'percent', label: Text('%')),
            ],
            selected: {percent ? 'percent' : 'amount'},
            onSelectionChanged: widget.enabled ? (v) => widget.onChanged(typeKey, v.first) : null,
          ),
        ),
      ],
    );
  }

  bool _filled(Map<String, dynamic> f) {
    final v = unwrapFieldValue(widget.values[fieldName(f)]);
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  bool _shown(Map<String, dynamic> f) =>
      !widget.requiredOnly || fieldIsRequired(f) || _filled(f) || widget.errors.containsKey(fieldName(f));

  @override
  Widget build(BuildContext context) {
    final all = _orderedFields().where(_shown).toList();
    final sectionOf = widget.sectionOf;
    if (sectionOf == null) return _buildFields(context, all);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final f in all) {
      buckets.putIfAbsent(sectionOf(fieldName(f)), () => []).add(f);
    }
    final order = [
      for (final k in [...widget.sectionOrder, ...buckets.keys.where((k) => !widget.sectionOrder.contains(k))])
        if (buckets[k]?.isNotEmpty ?? false) k,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Long forms: jump straight to a section (dot = still missing).
        if (order.length > 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final key in order)
                  () {
                    final meta = widget.sections[key];
                    final req = buckets[key]!.where(fieldIsRequired).toList();
                    final missing = req.where((f) => !_filled(f)).length;
                    final color = meta?.color ?? cs.primary;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        key: ValueKey('form-jump-$key'),
                        avatar: Icon(meta?.icon ?? NxI.note, size: 16, color: color),
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(tr(meta?.title ?? key)),
                          if (missing > 0) ...[
                            const SizedBox(width: 6),
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)),
                          ],
                        ]),
                        shape: const StadiumBorder(),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                        backgroundColor: cs.surface,
                        onPressed: () => jumpToSection(key),
                      ),
                    );
                  }(),
              ]),
            ),
          ),
        for (final key in order) _sectionCard(context, key, buckets[key]!),
      ],
    );
  }

  Widget _sectionCard(BuildContext context, String key, List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meta = widget.sections[key];
    final color = meta?.color ?? cs.primary;
    final req = list.where(fieldIsRequired).toList();
    final done = req.where(_filled).length;
    final filled = list.where(_filled).length;
    final open = !_collapsed.contains(key);
    final complete = done == req.length;
    return Container(
      key: _sectionKeys.putIfAbsent(key, GlobalKey.new),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? cs.surfaceContainerHigh : cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: theme.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('form-section-$key'),
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => open ? _collapsed.add(key) : _collapsed.remove(key)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                    child: Icon(meta?.icon ?? NxI.note, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(meta?.title ?? key), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (!open)
                        Text(
                          tr('กรอกแล้ว $filled/${list.length} ช่อง'),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ]),
                  ),
                  if (req.isNotEmpty)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        key: ValueKey('$done/${req.length}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (complete ? const Color(0xFF10B981) : cs.error).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (complete) ...[
                            const Icon(NxI.check, size: 12, color: Color(0xFF10B981)),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            complete ? tr('ครบแล้ว') : tr('จำเป็น $done/${req.length}'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: complete ? const Color(0xFF10B981) : cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(NxI.caretDown, size: 18, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                    child: _buildFields(context, list),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildFields(BuildContext context, List<Map<String, dynamic>> fields) {
    final theme = Theme.of(context);
    final pairShort = NxBreakpoint.of(context).twoPane;
    final children = <Widget>[];
    String? lastBlock;
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final block = widget.sectionOf == null ? fieldBlockLabel(f) : null;
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
          (widget.sectionOf == null ? fieldBlockLabel(next) : null) == block &&
          _isShortField(resolveFieldUiType(f)) &&
          _isShortField(resolveFieldUiType(next)) &&
          !_hasDiscountType(fieldName(f)) &&
          !_hasDiscountType(fieldName(next));
      if (canPair) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fieldOrDiscount(i, f)),
              const SizedBox(width: 12),
              Expanded(child: _fieldAt(i + 1, next)),
            ],
          ),
        );
        children.add(const SizedBox(height: 20));
        i += 1;
        continue;
      }
      children.add(_fieldOrDiscount(i, f));
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

/// Server dates for an edit / duplicate form, as Thai-time form values:
/// DATE columns (`1990-11-09T17:00:00.000Z` = 10 Nov in Thailand) become
/// `1990-11-10`, date-times become `yyyy-MM-ddTHH:mm:00` in Thai time —
/// what the pickers produce. Untouched dates then go back unchanged in
/// meaning (no day lost on every save).
/// Lead / Contact / Account ([module]) keep date-times as UTC: they open in
/// Thai time here and go back as UTC in [collectEntityPayload].
void normalizeFormDates(List<Map<String, dynamic>> fields, Map<String, dynamic> values, {String? module}) {
  for (final f in fields) {
    final name = fieldName(f);
    final raw = values[name];
    if (name.isEmpty || raw is! String || raw.trim().isEmpty) continue;
    final v = raw.trim();
    switch (resolveFieldUiType(f)) {
      case FieldUiType.date:
        if (v.length > 10 && v.contains(RegExp(r'^\d{4}-\d{2}-\d{2}[T ]'))) {
          final d = parseThaiDate(v);
          if (d != null) values[name] = formatYmd(d);
        }
      case FieldUiType.dateTime:
        if (RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(v)) {
          final d = parseThaiField(v, name, module: module);
          if (d != null) values[name] = '${formatYmd(d)}T${two(d.hour)}:${two(d.minute)}:00';
        }
      default:
        break;
    }
  }
}

Map<String, dynamic> collectEntityPayload(
  List<Map<String, dynamic>> fields,
  Map<String, dynamic> values, {
  Map<String, dynamic>? currentRow,
  String? module,
}) {
  final payload = <String, dynamic>{};
  final party = isPartyModule(module);
  for (final f in fields) {
    final name = fieldName(f);
    if (name.isEmpty) continue;
    var v = unwrapFieldValue(values[name]);
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    // Lead / Contact / Account: Thai form time → the UTC they store (like the web).
    if (party && v is String && (resolveFieldUiType(f) == FieldUiType.dateTime || name.toLowerCase().endsWith('_datetime'))) {
      v = toPartyUtcWall(v);
    }
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
