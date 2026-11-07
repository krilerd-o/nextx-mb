import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/field_format.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';

/// Create / edit / duplicate a Workspace item (Epic, Task, Bug, Story,
/// Subtask, Checklist). Same fields and defaults as the NEXTX web form.
/// Pops with the saved item map.
class WorkspaceItemFormScreen extends StatefulWidget {
  const WorkspaceItemFormScreen({
    super.key,
    required this.board,
    required this.statuses,
    this.epics = const [],
    this.tasks = const [],
    this.kind = 'task',
    this.edit,
    this.duplicateFrom,
    this.parent,
    this.users = const {},
  });

  /// user id → name (labels for people fields).
  final Map<String, String> users;

  final Map<String, dynamic> board;
  final List<WsStatus> statuses;
  final List<Map<String, dynamic>> epics;
  final List<Map<String, dynamic>> tasks;

  /// `epic` or `task` (task covers task/bug/story/subtask/checklist).
  final String kind;

  /// Item being edited (null = create).
  final Map<String, dynamic>? edit;

  /// Source when duplicating ("ทำซ้ำ").
  final Map<String, dynamic>? duplicateFrom;

  /// Parent task for a new subtask / checklist.
  final Map<String, dynamic>? parent;

  @override
  State<WorkspaceItemFormScreen> createState() => _WorkspaceItemFormScreenState();
}

const _sections = {
  'main': (title: 'ข้อมูลงาน', icon: NxI.checkSquare, color: Color(0xFF3B82F6)),
  'people': (title: 'สถานะและผู้รับผิดชอบ', icon: NxI.user, color: Color(0xFFF97316)),
  'time': (title: 'วันที่และเวลา', icon: NxI.calendarBlank, color: Color(0xFF10B981)),
  'group': (title: 'จัดกลุ่ม', icon: NxI.lightning, color: Color(0xFF8B5CF6)),
};

class _WorkspaceItemFormScreenState extends State<WorkspaceItemFormScreen> {
  final _formKey = GlobalKey<NxEntityFormState>();
  final Map<String, dynamic> _values = {};
  Map<String, String> _errors = {};
  bool _saving = false;
  bool _copyChildren = true;
  List<String> _labelOptions = const [];

  bool get _isEdit => widget.edit != null;
  String get _boardId => '${widget.board['id'] ?? widget.edit?['board_id'] ?? ''}';
  String get _kind => widget.edit != null ? wsKind(widget.edit!) : widget.kind;

  @override
  void initState() {
    super.initState();
    final src = widget.edit ?? widget.duplicateFrom;
    final session = context.read<AppConfig>().session;
    final me = session.userId;
    if (src != null) {
      for (final k in [
        'title', 'description', 'type', 'status_id', 'priority', 'assignee_id', 'reporter_id', 'start_date', 'end_date',
        'due_date', 'epic_id', 'parent_id', 'blocked_by_id', 'story_points', 'recurrence_type', 'release_id',
      ]) {
        final v = src[k];
        if (v != null && '$v'.isNotEmpty) _values[k] = k.endsWith('_date') ? '$v'.split('T').first : v;
      }
      _values['title'] = wsTitle(src);
      // Show names, not ids, in the people pickers.
      for (final k in ['assignee_id', 'reporter_id']) {
        final id = src[k];
        if (id != null && '$id'.isNotEmpty) _values[k] = {'id': '$id', 'label': widget.users['$id'] ?? '$id'};
      }
      final est = wsInt(src['original_estimate_minutes']);
      if (est != null && est > 0) _values['original_estimate'] = formatMinutes(est);
      final labels = src['labels'];
      if (labels is List && labels.isNotEmpty) _values['labels'] = joinMulti(labels.map((e) => '$e'));
      if (src['description'] is String && '${src['description']}'.contains('<')) {
        // Rich text from the web: keep it intact, edit on the web.
        _values.remove('description');
        _values['_richDescription'] = true;
      }
    }
    if (widget.duplicateFrom != null) {
      _values['title'] = '${_values['title'] ?? ''} ${tr('(สำเนา)')}'.trim();
      _values.remove('status_id');
    }
    if (!_isEdit) {
      // Defaults like the web: initial status, medium priority, reporter/assignee = me.
      _values['status_id'] ??= (widget.statuses.where((s) => s.isInitial).firstOrNull ?? widget.statuses.firstOrNull)?.id;
      _values['priority'] ??= 'medium';
      _values['type'] ??= widget.parent != null ? 'subtask' : 'task';
      if (me != null) {
        _values['reporter_id'] ??= {'id': me, 'label': session.displayName ?? me};
        _values['assignee_id'] ??= {'id': me, 'label': session.displayName ?? me};
      }
      if (widget.parent != null) {
        _values['parent_id'] = '${widget.parent!['id']}';
        if (widget.parent!['epic_id'] != null) _values['epic_id'] = '${widget.parent!['epic_id']}';
      }
      _values['recurrence_type'] ??= 'none';
    }
    _labelOptions = <String>{
      for (final t in widget.tasks)
        for (final l in (t['labels'] is List ? t['labels'] as List : const [])) '$l',
    }.toList()
      ..sort();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await context.read<AppConfig>().apiClient.getBoardItemTags(_boardId);
      if (!mounted) return;
      setState(() => _labelOptions = {
            ..._labelOptions,
            for (final t in tags) '${t['name'] ?? t['label'] ?? t['tag'] ?? ''}',
          }.where((e) => e.isNotEmpty).toList()
            ..sort());
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _fields {
    final epic = _kind == 'epic';
    final type = '${_values['type'] ?? 'task'}';
    final child = type == 'subtask' || type == 'checklist';
    return [
      {'name': 'title', 'label_th': 'ชื่องาน', 'label_en': 'Title', 'type': 'Text', 'required': true, '_s': 'main'},
      if (!epic) {'name': 'type', 'label_th': 'ประเภท', 'label_en': 'Type', 'type': 'Enum', 'required': true, '_s': 'main'},
      if (!_values.containsKey('_richDescription'))
        {'name': 'description', 'label_th': 'คำอธิบาย', 'label_en': 'Description', 'type': 'LongText', '_s': 'main'},
      {'name': 'status_id', 'label_th': 'สถานะ', 'label_en': 'Status', 'type': 'Enum', 'required': true, '_s': 'people'},
      {'name': 'priority', 'label_th': 'ความสำคัญ', 'label_en': 'Priority', 'type': 'Enum', '_s': 'people'},
      {'name': 'assignee_id', 'label_th': 'ผู้รับผิดชอบ', 'label_en': 'Assignee', 'type': 'PicklistUser', '_s': 'people'},
      {'name': 'reporter_id', 'label_th': 'ผู้รายงาน', 'label_en': 'Reporter', 'type': 'PicklistUser', '_s': 'people'},
      {'name': 'start_date', 'label_th': 'วันเริ่ม', 'label_en': 'Start date', 'type': 'Date', '_s': 'time'},
      {'name': 'end_date', 'label_th': 'วันสิ้นสุด', 'label_en': 'End date', 'type': 'Date', '_s': 'time'},
      {'name': 'due_date', 'label_th': 'ครบกำหนด', 'label_en': 'Due date', 'type': 'Date', '_s': 'time'},
      {'name': 'original_estimate', 'label_th': 'เวลาประมาณ (เช่น 2h 30m)', 'label_en': 'Estimate (e.g. 2h 30m)', 'type': 'Text', '_s': 'time'},
      if (!epic) {'name': 'story_points', 'label_th': 'Story points', 'label_en': 'Story points', 'type': 'Number', '_s': 'time'},
      if (!epic && widget.epics.isNotEmpty) {'name': 'epic_id', 'label_th': 'Epic', 'label_en': 'Epic', 'type': 'Enum', '_s': 'group'},
      if (!epic && child) {'name': 'parent_id', 'label_th': 'งานแม่', 'label_en': 'Parent', 'type': 'Enum', 'required': true, '_s': 'group'},
      if (!epic) {'name': 'labels', 'label_th': 'ป้ายกำกับ', 'label_en': 'Labels', 'type': 'MultiSelect', '_s': 'group'},
      if (!epic) {'name': 'blocked_by_id', 'label_th': 'ถูกบล็อกโดย', 'label_en': 'Blocked by', 'type': 'Enum', '_s': 'group'},
      if (!epic) {'name': 'recurrence_type', 'label_th': 'ทำซ้ำอัตโนมัติ', 'label_en': 'Repeat', 'type': 'Enum', '_s': 'group'},
    ];
  }

  Map<String, List<Map<String, dynamic>>> get _picklists {
    Map<String, dynamic> o(String v, String th) => {'value': v, 'value_th': tr(th), 'value_en': tr(th)};
    final selfId = '${widget.edit?['id'] ?? ''}';
    return {
      'type': [for (final t in const ['task', 'bug', 'story', 'subtask', 'checklist']) o(t, wsTypeStyle(t).label)],
      'status_id': [for (final s in widget.statuses) o(s.id, s.label)],
      'priority': [for (final p in kWsPriorities) o(p, wsPriorityStyle(p).label)],
      'epic_id': [for (final e in widget.epics) o('${e['id']}', '${wsKey(e)} ${wsTitle(e)}')],
      'parent_id': [
        for (final t in widget.tasks)
          if ('${t['id']}' != selfId && t['type'] != 'subtask' && t['type'] != 'checklist') o('${t['id']}', '${wsKey(t)} ${wsTitle(t)}'),
      ],
      'blocked_by_id': [
        for (final t in widget.tasks)
          if ('${t['id']}' != selfId) o('${t['id']}', '${wsKey(t)} ${wsTitle(t)}'),
      ],
      'labels': [for (final l in _labelOptions) o(l, l)],
      'recurrence_type': [
        o('none', 'ไม่ทำซ้ำ'),
        o('weekly', 'ทุกสัปดาห์'),
        o('biweekly', 'ทุก 2 สัปดาห์'),
        o('monthly', 'ทุกเดือน'),
      ],
    };
  }

  dynamic _id(dynamic v) {
    if (v is Map) v = v['id'] ?? v['value'];
    if (v == null || '$v'.isEmpty) return null;
    return int.tryParse('$v') ?? v;
  }

  Future<void> _save() async {
    final errors = <String, String>{};
    for (final f in _fields) {
      if (f['required'] == true) {
        final v = _values[f['name']];
        if (v == null || (v is String && v.trim().isEmpty)) errors['${f['name']}'] = 'จำเป็นต้องกรอก';
      }
    }
    final estRaw = '${_values['original_estimate'] ?? ''}'.trim();
    final est = estRaw.isEmpty ? null : parseDuration(estRaw);
    if (estRaw.isNotEmpty && est == null) errors['original_estimate'] = 'รูปแบบเวลา เช่น 2h 30m, 90m, 1d';
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      HapticFeedback.heavyImpact();
      final first = _fields.map((f) => '${f['name']}').firstWhere(errors.containsKey);
      WidgetsBinding.instance.addPostFrameCallback((_) => _formKey.currentState?.revealErrors(first, errors.keys));
      return;
    }
    final type = _kind == 'epic' ? null : '${_values['type'] ?? 'task'}';
    final labels = splitMulti(_values['labels']);
    final body = <String, dynamic>{
      'title': '${_values['title']}'.trim(),
      if (type != null) 'type': type,
      if (_values.containsKey('description')) 'description': '${_values['description'] ?? ''}',
      'status_id': _id(_values['status_id']),
      'priority': _values['priority'] ?? 'medium',
      'assignee_id': _id(_values['assignee_id']),
      'reporter_id': _id(_values['reporter_id']),
      'start_date': _values['start_date'],
      'end_date': _values['end_date'],
      'due_date': _values['due_date'],
      'original_estimate': est,
      if (type != null) ...{
        'story_points': _values['story_points'] == null || '${_values['story_points']}'.isEmpty ? null : num.tryParse('${_values['story_points']}'),
        'epic_id': _id(_values['epic_id']),
        'parent_id': _id(_values['parent_id']),
        'blocked_by_id': _id(_values['blocked_by_id']),
        'labels': labels,
        'recurrence_type': _values['recurrence_type'] ?? 'none',
      },
    };
    if (!_isEdit) body.removeWhere((k, v) => v == null);
    setState(() => _saving = true);
    final api = context.read<AppConfig>().apiClient;
    try {
      final saved = _isEdit
          ? await api.updateWorkspaceItem(_boardId, _kind, '${widget.edit!['id']}', body)
          : await api.createWorkspaceItem(_boardId, _kind, body);
      // Duplicate: bring the checklist / subtasks along when asked.
      final src = widget.duplicateFrom;
      if (src != null && _copyChildren && saved['id'] != null && _kind == 'task') {
        await _copyChildrenOf(api, src, '${saved['id']}');
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, {...saved, 'board_id': _boardId, if (_kind == 'epic') '_kind': 'epic'});
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _copyChildrenOf(ApiClient api, Map<String, dynamic> src, String newId) async {
    final srcId = '${src['id']}';
    for (final t in widget.tasks.where((t) => '${t['parent_id']}' == srcId)) {
      try {
        await api.createWorkspaceItem(_boardId, 'task', {
          'title': wsTitle(t),
          'type': t['type'] ?? 'subtask',
          'parent_id': int.tryParse(newId) ?? newId,
          if (t['assignee_id'] != null) 'assignee_id': t['assignee_id'],
          if (t['priority'] != null) 'priority': t['priority'],
        });
      } catch (_) {}
    }
    try {
      for (final c in await api.getSmartChecklist(_boardId, srcId)) {
        final title = '${c['title'] ?? ''}';
        if (title.isNotEmpty) await api.addSmartChecklistItem(_boardId, newId, title);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = wsTypeStyle(_kind == 'epic' ? 'epic' : '${_values['type'] ?? 'task'}');
    final title = _isEdit
        ? tr('แก้ไข ${tr(type.label)}')
        : widget.duplicateFrom != null
            ? tr('ทำซ้ำ ${tr(type.label)}')
            : tr('สร้าง ${tr(type.label)}');
    final richDesc = '${(widget.edit ?? widget.duplicateFrom)?['description'] ?? ''}'.contains('<');
    return Scaffold(
      appBar: NxAppHeader(title: title, subtitle: '${widget.board['name'] ?? ''}'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (richDesc)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(NxI.info, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(tr('คำอธิบายมีรูปแบบ (rich text) — แก้ไขบนเว็บเพื่อไม่ให้รูปแบบหาย'))),
                    ]),
                  ),
                NxEntityForm(
                  key: _formKey,
                  fields: _fields,
                  values: _values,
                  picklists: _picklists,
                  api: context.read<AppConfig>().apiClient,
                  errors: _errors,
                  sectionOf: (name) => '${_fields.firstWhere((f) => f['name'] == name, orElse: () => {'_s': 'main'})['_s']}',
                  sections: _sections,
                  sectionOrder: const ['main', 'people', 'time', 'group'],
                  onChanged: (name, v) => setState(() {
                    _values[name] = v;
                    _errors.remove(name);
                  }),
                ),
                if (widget.duplicateFrom != null && _kind == 'task')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('คัดลอกงานย่อยและเช็คลิสต์ด้วย')),
                    subtitle: Text(tr('ไม่รวมเวลาที่ลงไว้และคอมเมนต์')),
                    value: _copyChildren,
                    onChanged: (v) => setState(() => _copyChildren = v),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: KeyedSubtree(
                key: const ValueKey('ws-save'),
                child: NxHeroCta(label: _isEdit ? 'บันทึก' : 'สร้าง', busy: _saving, onPressed: _saving ? null : _save),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
