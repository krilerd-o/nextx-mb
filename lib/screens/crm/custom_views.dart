import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_shake.dart';

/// Label of a NEXTX field/option map in the current UI language.
String nxLabel(Map m, {String fallback = ''}) {
  final en = m['label_en'] ?? m['labelEn'] ?? m['value_en'];
  final th = m['label_th'] ?? m['labelTh'] ?? m['value_th'];
  final v = (L10n.isEn ? (en ?? m['label'] ?? th) : (th ?? m['label'] ?? en)) ?? m['name'] ?? m['value'] ?? fallback;
  return v.toString();
}

/// A NEXTX Custom View (มุมมอง) as returned by `/api/customviews`.
class CustomView {
  CustomView(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['id'].toString();
  String get name => raw['name']?.toString() ?? '';
  bool get isSystem => raw['is_system'] == true;
  bool get isDefault => raw['is_default'] == true;
  bool get canEdit => raw['can_edit'] == true;
  bool get canDelete => raw['can_delete'] == true;
  bool get canDuplicate => raw['can_duplicate'] != false;
  String get visibility => raw['visibility']?.toString() ?? 'private';
  List get conditions => raw['conditions'] is List ? raw['conditions'] as List : const [];
  String get displayName => isSystem && name.toLowerCase() == 'all' ? tr('ทั้งหมด') : name;
}

/// Views visible to the user, grouped like the web picker.
class CustomViewList {
  CustomViewList(this.views, this.groups, this.defaultId);
  final List<CustomView> views;
  final List<({String label, List<CustomView> items})> groups;
  final String? defaultId;

  static CustomViewList from(Map<String, dynamic> data) {
    final views = [
      for (final v in (data['list'] as List? ?? const []))
        if (v is Map) CustomView(Map<String, dynamic>.from(v)),
    ];
    final byId = {for (final v in views) v.id: v};
    final groups = <({String label, List<CustomView> items})>[];
    for (final g in (data['groups'] as List? ?? const [])) {
      if (g is! Map) continue;
      final items = [
        for (final it in (g['items'] as List? ?? const []))
          if (it is Map && byId[it['id'].toString()] != null) byId[it['id'].toString()]!,
      ];
      if (items.isEmpty) continue;
      final label = (L10n.isEn ? g['labelEn'] : g['labelTh'])?.toString() ?? g['key'].toString();
      groups.add((label: label, items: items));
    }
    if (groups.isEmpty && views.isNotEmpty) groups.add((label: 'มุมมอง', items: views));
    return CustomViewList(views, groups, data['default_id']?.toString());
  }
}

/// Bottom sheet: pick a view; per-view menu (edit / duplicate / delete by
/// permission) and "create view". Returns the id to apply, or null if unchanged.
Future<String?> showCustomViewPicker(
  BuildContext context, {
  required String module,
  required CustomViewList views,
  required String? currentId,
  required Future<void> Function() onChanged,
}) {
  return showAppBottomSheet<String>(
    context: context,
    title: 'มุมมอง',
    child: _CvPicker(module: module, views: views, currentId: currentId, onChanged: onChanged),
  );
}

class _CvPicker extends StatelessWidget {
  const _CvPicker({required this.module, required this.views, required this.currentId, required this.onChanged});
  final String module;
  final CustomViewList views;
  final String? currentId;
  final Future<void> Function() onChanged;

  Future<void> _edit(BuildContext context, CustomView? v, {bool copy = false}) async {
    final nav = Navigator.of(context);
    final api = context.read<AppConfig>().apiClient;
    Map<String, dynamic>? initial = v?.raw;
    if (copy && v != null) {
      try {
        initial = await api.duplicateCustomView(v.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
        }
        return;
      }
    }
    if (!context.mounted) return;
    final saved = await nxPush<Map<String, dynamic>>(
      context,
      CustomViewEditorScreen(module: module, initial: initial),
      root: true,
    );
    await onChanged();
    final copyId = initial == null ? null : initial['id']?.toString();
    final id = saved?['id']?.toString() ?? (copy ? copyId : null);
    if (nav.mounted) nav.pop(id);
  }

  Future<void> _delete(BuildContext context, CustomView v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบมุมมอง "${v.name}"?')),
        content: Text(tr('รายการข้อมูลไม่ถูกลบ ลบเฉพาะมุมมองนี้')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    try {
      await context.read<AppConfig>().apiClient.deleteCustomView(v.id);
      await onChanged();
      if (nav.mounted) nav.pop(v.id == currentId ? views.defaultId ?? '' : null);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in views.groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              tr(g.label).toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.6),
            ),
          ),
          for (final v in g.items)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              leading: Icon(
                v.id == currentId ? NxI.checkCircle : (v.isSystem ? NxI.squaresFour : NxI.funnel),
                color: v.id == currentId ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(v.displayName),
              subtitle: Text(
                [
                  if (v.isDefault) tr('ค่าเริ่มต้น'),
                  tr(switch (v.visibility) { 'public' => 'สาธารณะ', 'share' => 'แชร์', _ => 'ส่วนตัว' }),
                  if (v.conditions.isNotEmpty) tr('${v.conditions.length} เงื่อนไข'),
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(context, v.id),
              trailing: PopupMenuButton<String>(
                icon: const Icon(NxI.dotsThreeVertical),
                onSelected: (a) {
                  if (a == 'edit') _edit(context, v);
                  if (a == 'copy') _edit(context, v, copy: true);
                  if (a == 'delete') _delete(context, v);
                },
                itemBuilder: (_) => [
                  if (v.canEdit) PopupMenuItem(value: 'edit', child: Text(tr('แก้ไข'))),
                  if (v.canDuplicate) PopupMenuItem(value: 'copy', child: Text(tr('ทำซ้ำ'))),
                  if (v.canDelete) PopupMenuItem(value: 'delete', child: Text(tr('ลบ'))),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _edit(context, null),
          icon: const Icon(NxI.plus),
          label: Text(tr('สร้างมุมมอง')),
        ),
      ],
    );
  }
}

/// Create / edit a Custom View: name, who sees it, conditions (field ·
/// operator · value), period, sort and default — mirrors the web editor.
class CustomViewEditorScreen extends StatefulWidget {
  const CustomViewEditorScreen({super.key, required this.module, this.initial});
  final String module;
  final Map<String, dynamic>? initial;

  @override
  State<CustomViewEditorScreen> createState() => _CustomViewEditorScreenState();
}

class _Cond {
  _Cond({this.field = '', this.op = 'eq', this.value = ''});
  String field;
  String op;
  String value;
}

class _CustomViewEditorScreenState extends State<CustomViewEditorScreen> {
  final _name = TextEditingController();
  final _nameShake = GlobalKey<NxShakeState>();
  Map<String, dynamic>? _meta;
  Map<String, List<Map<String, dynamic>>> _picklists = {};
  Object? _error;
  bool _saving = false;

  String _visibility = 'private';
  bool _isDefault = false;
  String _logic = 'and';
  final List<_Cond> _conds = [];
  String? _periodField;
  String _periodPreset = '';
  String? _sortField;
  String _sortOrder = 'desc';
  final Set<String> _shareUsers = {};
  final Set<String> _shareRoles = {};


  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _name.text = i['name']?.toString() ?? '';
      _visibility = i['visibility']?.toString() ?? 'private';
      _isDefault = i['is_default'] == true;
      _logic = i['conditions_logic']?.toString() == 'or' ? 'or' : 'and';
      for (final c in (i['conditions'] as List? ?? const [])) {
        if (c is Map) {
          final v = c['value'];
          _conds.add(_Cond(
            field: c['field']?.toString() ?? '',
            op: c['operator']?.toString() ?? 'eq',
            value: v is List ? v.join(',') : (v?.toString() ?? ''),
          ));
        }
      }
      final p = i['period'];
      if (p is Map) {
        _periodField = p['field']?.toString();
        _periodPreset = p['preset']?.toString() ?? '';
      }
      _sortField = i['sort_field']?.toString();
      _sortOrder = i['sort_order']?.toString() == 'asc' ? 'asc' : 'desc';
      for (final s in (i['shares'] as List? ?? const [])) {
        if (s is Map && s['share_to_type'] == 'user') _shareUsers.add(s['share_to_id'].toString());
        if (s is Map && s['share_to_type'] == 'role') _shareRoles.add(s['share_to_id'].toString());
      }
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final meta = await api.getCustomViewMeta(widget.module);
      Map<String, List<Map<String, dynamic>>> pick = {};
      try {
        pick = (await api.getFieldSchema(widget.module)).picklists;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _meta = meta;
          _picklists = pick;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<Map<String, dynamic>> _list(String key) => [
        for (final f in (_meta?[key] as List? ?? const []))
          if (f is Map) Map<String, dynamic>.from(f),
      ];

  Map<String, dynamic>? _field(String name) => _list('fields').where((f) => f['name'] == name).firstOrNull;

  String _opLabel(String op) {
    final o = _list('operators').where((e) => e['value'] == op).firstOrNull;
    if (o == null) return op;
    return (L10n.isEn ? o['label_en'] : o['label_th'])?.toString() ?? op;
  }

  bool _noValue(String op) => op == 'is_empty' || op == 'is_not_empty';

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      nxShakeField(_nameShake);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กรุณาตั้งชื่อมุมมอง'))));
      return;
    }
    final body = <String, dynamic>{
      ...?widget.initial,
      'module': widget.module,
      'name': name,
      'visibility': _visibility,
      'is_default': _isDefault,
      'conditions_logic': _logic,
      'conditions': [
        for (final c in _conds)
          if (c.field.isNotEmpty && (_noValue(c.op) || c.value.trim().isNotEmpty))
            {
              'field': c.field,
              'operator': c.op,
              'value': (c.op == 'in' || c.op == 'not_in')
                  ? c.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                  : c.value.trim(),
            },
      ],
      'period': _periodField != null && _periodPreset.isNotEmpty ? {'field': _periodField, 'preset': _periodPreset} : null,
      'sort_field': _sortField,
      'sort_order': _sortOrder,
      'shares': [
        for (final u in _shareUsers) {'share_to_type': 'user', 'share_to_id': int.tryParse(u) ?? u},
        for (final r in _shareRoles) {'share_to_type': 'role', 'share_to_id': int.tryParse(r) ?? r},
      ],
    };
    for (final k in ['can_edit', 'can_delete', 'can_duplicate', 'created_at', 'updated_at']) {
      body.remove(k);
    }
    setState(() => _saving = true);
    final api = context.read<AppConfig>().apiClient;
    try {
      final id = widget.initial?['id']?.toString();
      final saved = id == null ? await api.createCustomView(body) : await api.updateCustomView(id, body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Widget _section(String title, List<Widget> children) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(title), style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
  }) {
    final has = items.any((e) => e.$1 == value);
    return DropdownButtonFormField<T>(
        icon: const Icon(NxI.caretDown, size: 18),
      initialValue: has ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr(label), isDense: true),
      items: [for (final e in items) DropdownMenuItem(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }

  Widget _valueInput(_Cond c) {
    final f = _field(c.field);
    final uitype = int.tryParse('${f?['uitype'] ?? ''}') ?? 0;
    final multi = c.op == 'in' || c.op == 'not_in';
    final pick = _picklists[c.field] ?? const [];
    List<(String, String)>? options;
    if (pick.isNotEmpty) {
      options = [for (final o in pick) ((o['value'] ?? o['value_th'] ?? '').toString(), nxLabel(o))];
    } else if (uitype == 53) {
      options = [for (final u in _list('users')) (u['id'].toString(), u['name']?.toString() ?? '')];
    }
    if (options != null) {
      final selected = c.value.split(',').where((e) => e.isNotEmpty).toSet();
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(o.$2),
              selected: selected.contains(o.$1),
              onSelected: (on) => setState(() {
                if (multi) {
                  on ? selected.add(o.$1) : selected.remove(o.$1);
                  c.value = selected.join(',');
                } else {
                  c.value = on ? o.$1 : '';
                }
              }),
            ),
        ],
      );
    }
    final isDate = [5, 6, 23, 70].contains(uitype);
    return TextFormField(
      key: ValueKey('${c.field}_${c.op}'),
      initialValue: c.value,
      readOnly: isDate,
      decoration: InputDecoration(
        labelText: tr(multi ? 'ค่า (คั่นด้วย ,)' : 'ค่า'),
        isDense: true,
        suffixIcon: isDate ? const Icon(NxI.calendarBlank, size: 18) : null,
      ),
      keyboardType: [7, 71, 72].contains(uitype) ? TextInputType.number : TextInputType.text,
      onTap: isDate
          ? () async {
              final d = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: DateTime.tryParse(c.value) ?? DateTime.now(),
              );
              if (d != null) {
                setState(() => c.value =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
              }
            }
          : null,
      onChanged: (v) => c.value = v,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fields = _list('fields');
    final dateFields = _list('date_fields');
    final presets = _list('period_presets').where((p) => p['value'] != 'custom').toList();
    return NxScrollScaffold(
      header: NxAppHeader(
        title: widget.initial?['id'] == null ? 'สร้างมุมมอง' : 'แก้ไขมุมมอง',
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton.filled(
                  tooltip: tr('บันทึก'),
                  onPressed: _meta == null ? null : _save,
                  icon: const Icon(NxI.check),
                ),
        ],
      ),
      body: _meta == null
          ? Center(
              child: _error != null ? Text(tr(formatApiError(_error!))) : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                NxShake(
                  key: _nameShake,
                  child: TextField(
                    controller: _name,
                    readOnly: widget.initial?['is_system'] == true,
                    decoration: InputDecoration(label: nxRequiredLabel(context, tr('ชื่อมุมมอง'))),
                  ),
                ),
                _section('ใครเห็นมุมมองนี้', [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'private', label: Text(tr('ส่วนตัว')), icon: const Icon(NxI.lock, size: 16)),
                      ButtonSegment(value: 'public', label: Text(tr('สาธารณะ')), icon: const Icon(NxI.globe, size: 16)),
                      ButtonSegment(value: 'share', label: Text(tr('แชร์')), icon: const Icon(NxI.users, size: 16)),
                    ],
                    selected: {_visibility},
                    onSelectionChanged: (s) => setState(() => _visibility = s.first),
                  ),
                  if (_visibility == 'share') ...[
                    const SizedBox(height: 12),
                    Text(tr('ผู้ใช้'), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final u in _list('users'))
                        FilterChip(
                          label: Text(u['name']?.toString() ?? ''),
                          selected: _shareUsers.contains(u['id'].toString()),
                          onSelected: (on) => setState(
                              () => on ? _shareUsers.add(u['id'].toString()) : _shareUsers.remove(u['id'].toString())),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Text(tr('บทบาท'), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final r in _list('roles'))
                        FilterChip(
                          label: Text(r['name']?.toString() ?? ''),
                          selected: _shareRoles.contains(r['id'].toString()),
                          onSelected: (on) => setState(
                              () => on ? _shareRoles.add(r['id'].toString()) : _shareRoles.remove(r['id'].toString())),
                        ),
                    ]),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('ใช้เป็นมุมมองเริ่มต้น')),
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v),
                  ),
                ]),
                _section('เงื่อนไข', [
                  if (_conds.length > 1)
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'and', label: Text(tr('ตรงทุกข้อ'))),
                        ButtonSegment(value: 'or', label: Text(tr('ตรงข้อใดข้อหนึ่ง'))),
                      ],
                      selected: {_logic},
                      onSelectionChanged: (s) => setState(() => _logic = s.first),
                    ),
                  for (var i = 0; i < _conds.length; i++)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _dropdown<String>(
                                  label: 'ฟิลด์',
                                  value: _conds[i].field,
                                  items: [for (final f in fields) (f['name'].toString(), nxLabel(f))],
                                  onChanged: (v) => setState(() {
                                    _conds[i].field = v ?? '';
                                    final ops = (_field(v ?? '')?['operators'] as List?)?.map((e) => '$e').toList();
                                    if (ops != null && ops.isNotEmpty && !ops.contains(_conds[i].op)) _conds[i].op = ops.first;
                                    _conds[i].value = '';
                                  }),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('ลบเงื่อนไข'),
                                icon: const Icon(NxI.trash, size: 18),
                                onPressed: () => setState(() => _conds.removeAt(i)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _dropdown<String>(
                            label: 'เงื่อนไข',
                            value: _conds[i].op,
                            items: [
                              for (final op in ((_field(_conds[i].field)?['operators'] as List?) ??
                                  _list('operators').map((e) => e['value']).toList()))
                                (op.toString(), _opLabel(op.toString())),
                            ],
                            onChanged: (v) => setState(() => _conds[i].op = v ?? 'eq'),
                          ),
                          if (_conds[i].field.isNotEmpty && !_noValue(_conds[i].op)) ...[
                            const SizedBox(height: 8),
                            _valueInput(_conds[i]),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _conds.add(_Cond())),
                      icon: const Icon(NxI.plus, size: 18),
                      label: Text(tr('เพิ่มเงื่อนไข')),
                    ),
                  ),
                ]),
                _section('ช่วงเวลา', [
                  _dropdown<String>(
                    label: 'ฟิลด์วันที่',
                    value: _periodField ??
                        (dateFields.any((f) => f['name'] == 'createdtime')
                            ? 'createdtime'
                            : (dateFields.isNotEmpty ? dateFields.first['name'].toString() : null)),
                    items: [for (final f in dateFields) (f['name'].toString(), nxLabel(f))],
                    onChanged: (v) => setState(() => _periodField = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ChoiceChip(
                      label: Text(tr('ไม่กำหนด')),
                      selected: _periodPreset.isEmpty,
                      onSelected: (_) => setState(() => _periodPreset = ''),
                    ),
                    for (final p in presets)
                      ChoiceChip(
                        label: Text(nxLabel(p)),
                        selected: _periodPreset == p['value'],
                        onSelected: (_) => setState(() {
                          _periodPreset = p['value'].toString();
                          _periodField ??= dateFields.any((f) => f['name'] == 'createdtime') || dateFields.isEmpty
                              ? 'createdtime'
                              : dateFields.first['name'].toString();
                        }),
                      ),
                  ]),
                ]),
                _section('เรียงลำดับ', [
                  _dropdown<String>(
                    label: 'เรียงตาม',
                    value: _sortField,
                    items: [for (final f in fields) (f['name'].toString(), nxLabel(f))],
                    onChanged: (v) => setState(() => _sortField = v),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'desc', label: Text(tr('มาก → น้อย / ใหม่ → เก่า'))),
                      ButtonSegment(value: 'asc', label: Text(tr('น้อย → มาก / เก่า → ใหม่'))),
                    ],
                    selected: {_sortOrder},
                    onSelectionChanged: (s) => setState(() => _sortOrder = s.first),
                  ),
                ]),
              ],
            ),
    );
  }
}
