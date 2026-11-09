import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/fields/nx_picker_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_attachments.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../crm/entity_detail_parts.dart' show PendingEntityDeletes;
import 'smart_checklist_section.dart';
import 'workspace_item_form.dart';
import 'ws_activity_panel.dart';
import 'ws_detail_parts.dart';
import '../../widgets/nx_refresh.dart';

/// NEXTX board priorities (backend/src/routes/boards.js).
const taskPriorities = <String, String>{'highest': 'สูงสุด', 'high': 'สูง', 'medium': 'ปานกลาง', 'low': 'ต่ำ', 'lowest': 'ต่ำสุด'};

/// Task attachments arrive as a JSON array or a JSON string of one.
List<Map<String, dynamic>> taskAttachments(dynamic raw) {
  var v = raw;
  if (v is String && v.trim().isNotEmpty) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is! List) return const [];
  return [
    for (final a in v)
      if (a is Map && a['url'] != null) Map<String, dynamic>.from(a) else if (a is String) {'url': a, 'name': 'file'},
  ];
}

/// A DATE column as its Thai day: `2026-11-05T17:00:00.000Z` (midnight in
/// Bangkok) and `2026-11-06T00:00:00.000Z` / `2026-11-06` → `2026-11-06`.
String? taskDateOnly(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final d = parseThaiDate(s);
  if (d != null) return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(s)?.group(1);
}

const _linkTypes = {'blocks': 'บล็อก', 'is_blocked_by': 'ถูกบล็อกโดย', 'relates_to': 'เกี่ยวข้องกับ'};

/// Task / epic detail like the NEXTX web panel: status stepper, time card
/// with log + stopwatch, editable fields, subtasks / epic children, checklist,
/// attachments, watchers, links and comments / time logs / history.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Map<String, dynamic> _item = Map<String, dynamic>.from(widget.task);
  List<WsStatus> _statuses = const [];
  List<Map<String, dynamic>> _epics = const [];
  List<Map<String, dynamic>> _tasks = const [];
  Map<String, String> _users = const {};
  List<Map<String, dynamic>> _watchers = const [];
  List<Map<String, dynamic>> _links = const [];
  bool _saving = false;
  bool _showAll = false;
  bool _editingTitle = false;
  final _titleCtrl = TextEditingController();
  final _subtaskCtrl = TextEditingController();
  final _activity = GlobalKey<WsActivityPanelState>();
  static const _bleed = ValueKey('ws-full-bleed');
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;
  String? _businessId;

  String get _boardId => strId(_item['board_id']);
  String get _id => strId(_item['id']);
  String get _kind => wsKind(_item);
  bool get _isEpic => _kind == 'epic';
  String get _type => wsType(_item);
  bool get _isChild => _type == 'subtask' || _type == 'checklist';
  String? get _code => _item['board_code']?.toString();
  bool get _online => context.read<AppConfig>().isLoggedIn && _boardId.isNotEmpty && _id.isNotEmpty;
  String? get _me => context.read<AppConfig>().session.userId;

  @override
  void initState() {
    super.initState();
    if (!_online) return;
    _load();
    _businessId = context.read<AppConfig>().session.businessId;
    RealtimeService.instance.joinWorkspaceBoard(_boardId, businessId: _businessId);
    _live = RealtimeService.instance.events.where((e) => e.type.startsWith('workspace:')).listen((e) {
      final d = e.data;
      if (d['id'] != null && '${d['id']}' != _id && '${d['task_id'] ?? d['item_id'] ?? ''}' != _id) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || _saving) return;
        _reloadItem();
        _activity.currentState?.reload();
      });
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    if (_boardId.isNotEmpty && _live != null) RealtimeService.instance.leaveWorkspaceBoard(_boardId, businessId: _businessId);
    _titleCtrl.dispose();
    _subtaskCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(text))));
  }

  ApiClient get _api => context.read<AppConfig>().apiClient;

  Future<void> _load() async {
    final api = _api;
    final r = await Future.wait<Object?>([
      api.getWorkspaceItem(_boardId, _kind, _id).catchError((_) => null),
      api.getBoardStatuses(_boardId).catchError((_) => <Map<String, dynamic>>[]),
      api.getBoardEpics(_boardId).catchError((_) => <Map<String, dynamic>>[]),
      api.getBoardTasks(_boardId).catchError((_) => <Map<String, dynamic>>[]),
      api.getUsersCached().catchError((_) => <Map<String, dynamic>>[]),
      if ((_code ?? '').isEmpty) api.getBoard(_boardId).then<Object?>((b) => b).catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      final full = r[0] as Map<String, dynamic>?;
      if (full != null) _item = {..._item, ...full};
      _statuses = WsStatus.list(r[1] as List<Map<String, dynamic>>);
      _epics = [
        for (final e in r[2] as List<Map<String, dynamic>>) {...e, '_kind': 'epic'},
      ];
      _tasks = r[3] as List<Map<String, dynamic>>;
      _users = {for (final u in r[4] as List<Map<String, dynamic>>) '${u['id']}': userDisplayName(u)};
      nxRememberUserPhotos(r[4] as List<Map<String, dynamic>>, _api.absoluteUrl);
      if (r.length > 5 && r[5] is Map) {
        final b = r[5] as Map;
        _item['board_code'] ??= b['code'];
        _item['board_name'] ??= b['name'];
        wsRememberBoard(Map<String, dynamic>.from(b));
      }
    });
    _loadSide();
  }

  Future<void> _loadSide() async {
    try {
      final w = await _api.getItemWatchers(_boardId, _kind, _id);
      if (mounted) setState(() => _watchers = w);
    } catch (_) {}
    try {
      final l = await _api.getItemLinks(_boardId, _kind, _id);
      if (mounted) setState(() => _links = l);
    } catch (_) {}
  }

  Future<void> _reloadItem() async {
    try {
      final full = await _api.getWorkspaceItem(_boardId, _kind, _id);
      if (full != null && mounted) setState(() => _item = {..._item, ...full});
    } catch (_) {}
  }

  Future<void> _reloadTasks() async {
    try {
      final t = await _api.getBoardTasks(_boardId);
      if (mounted) setState(() => _tasks = t);
    } catch (_) {}
  }

  /// PUT the changed fields; [local] is shown at once and kept on success.
  Future<bool> _update(Map<String, dynamic> body, {Map<String, dynamic> local = const {}}) async {
    if (body.isEmpty || !_online) return false;
    final before = _item;
    setState(() {
      _saving = true;
      _item = {..._item, ...body, ...local};
    });
    try {
      final updated = await _api.updateWorkspaceItem(_boardId, _kind, _id, body);
      if (!mounted) return true;
      setState(() {
        _item = {..._item, ...updated, ...local};
        _saving = false;
      });
      _activity.currentState?.reload();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _item = before;
          _saving = false;
        });
        HapticFeedback.heavyImpact();
      }
      _snack(formatApiError(e));
      return false;
    }
  }

  // ── status / title
  Future<void> _setStatus(WsStatus s) async {
    final ok = await _update({'status_id': int.tryParse(s.id) ?? s.id});
    if (ok) {
      HapticFeedback.mediumImpact();
      if (s.isDone) _snack('ย้ายไป ${s.label} แล้ว');
    }
  }

  Future<void> _saveTitle() async {
    final t = _titleCtrl.text.trim();
    setState(() => _editingTitle = false);
    if (t.isEmpty || t == wsTitle(_item)) return;
    await _update({'title': t});
  }

  // ── time
  Future<void> _logTime({int? minutes}) async {
    final r = await showWsLogTimeSheet(context, minutes: minutes, remaining: wsInt(_item['time_remaining_minutes']));
    if (r == null || !mounted) return;
    try {
      await _api.addWorklog(_boardId, _id, minutes: r.minutes, description: r.description, remainingMinutes: r.remaining, startedAt: r.startedAt);
      HapticFeedback.mediumImpact();
      _snack('ลงเวลาแล้ว ${formatMinutes(r.minutes)}');
      _activity.currentState?.showTab(1);
      await Future.wait([_reloadItem(), _activity.currentState?.reload() ?? Future.value()]);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  // ── field editors
  Future<void> _pickUser(String field) async {
    final v = await showNxPickerSheet(
      context: context,
      title: tr(wsFieldLabel(field)),
      value: '${_item[field] ?? ''}',
      radio: true,
      options: [
        NxPickOption(value: '', label: tr('ไม่มอบหมาย')),
        if (_me != null) NxPickOption(value: _me!, label: '${_users[_me] ?? tr('ฉัน')} (${tr('ฉัน')})'),
        for (final e in _users.entries)
          if (e.key != _me) NxPickOption(value: e.key, label: e.value),
      ],
    );
    if (v == null || v == '${_item[field] ?? ''}') return;
    await _update({field: v.isEmpty ? null : int.tryParse(v) ?? v});
  }

  Future<void> _pickEnum(String field, List<NxPickOption> options, {bool nullable = false}) async {
    final v = await showNxPickerSheet(
      context: context,
      title: tr(wsFieldLabel(field)),
      value: '${_item[field] ?? ''}',
      radio: true,
      options: [
        if (nullable) NxPickOption(value: '', label: tr('ไม่มี')),
        ...options,
      ],
    );
    if (v == null || v == '${_item[field] ?? ''}') return;
    final numeric = field.endsWith('_id');
    await _update({field: v.isEmpty ? null : (numeric ? int.tryParse(v) ?? v : v)});
  }

  Future<void> _pickDate(String field) async {
    final cur = DateTime.tryParse(taskDateOnly(_item[field]) ?? '');
    final now = thaiNow();
    final d = await showDatePicker(
      context: context,
      switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
      switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      initialDate: cur ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    await _update({field: '${d.year}-${two(d.month)}-${two(d.day)}'});
  }

  Future<String?> _askText(String title, {String initial = '', String? hint, TextInputType? keyboard, String? Function(String)? validate}) {
    final ctrl = TextEditingController(text: initial);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr(title)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: keyboard,
            maxLines: keyboard == TextInputType.multiline ? 8 : 1,
            minLines: 1,
            decoration: InputDecoration(hintText: hint, errorText: error, border: const OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
            FilledButton(
              onPressed: () {
                final e = validate?.call(ctrl.text.trim());
                if (e != null) {
                  set(() => error = tr(e));
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(tr('บันทึก')),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _editEstimate(String field) async {
    final cur = wsInt(_item[field]);
    final v = await _askText(
      wsFieldLabel(field),
      initial: cur == null || cur == 0 ? '' : formatMinutes(cur),
      hint: '2h 30m',
      validate: (s) => s.isEmpty || parseDuration(s) != null ? null : 'รูปแบบเวลา เช่น 2h 30m, 90m, 1d',
    );
    if (v == null) return;
    final m = v.isEmpty ? null : parseDuration(v);
    await _update(field == 'original_estimate_minutes' ? {'original_estimate': m} : {field: m});
  }

  Future<void> _editStoryPoints() async {
    final v = await _askText(
      'Story points',
      initial: '${_item['story_points'] ?? ''}',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      validate: (s) => s.isEmpty || num.tryParse(s) != null ? null : 'ต้องเป็นตัวเลข',
    );
    if (v == null) return;
    await _update({'story_points': v.isEmpty ? null : num.parse(v)});
  }

  List<String> get _labels => _item['labels'] is List ? [for (final l in _item['labels'] as List) '$l'] : const [];

  Future<void> _editLabels() async {
    final known = <String>{
      for (final t in _tasks)
        for (final l in (t['labels'] is List ? t['labels'] as List : const [])) '$l',
      ..._labels,
    }.toList()..sort();
    final picked = await showNxMultiPickerSheet(
      context: context,
      title: tr('ป้ายกำกับ'),
      values: _labels.toSet(),
      options: [for (final l in known) NxPickOption(value: l, label: l)],
    );
    if (picked == null) return;
    await _update({'labels': picked.toList()});
  }

  Future<void> _addLabel() async {
    final v = await _askText('เพิ่มป้ายกำกับ');
    if (v == null || v.isEmpty || _labels.contains(v)) return;
    await _update({
      'labels': [..._labels, v],
    });
  }

  Future<void> _editDescription() async {
    final d = '${_item['description'] ?? ''}';
    final v = await _askText('คำอธิบาย', initial: d, keyboard: TextInputType.multiline);
    if (v == null || v == d) return;
    await _update({'description': v});
  }

  // ── children
  List<Map<String, dynamic>> get _children => _isEpic
      ? [
          for (final t in _tasks)
            if ('${t['epic_id']}' == _id && t['parent_id'] == null) t,
        ]
      : [
          for (final t in _tasks)
            if ('${t['parent_id']}' == _id) t,
        ];

  bool _done(Map<String, dynamic> t) {
    final s = _statuses.where((s) => s.id == '${t['status_id']}').firstOrNull;
    return s?.isDone == true || '${t['is_completed']}' == '1' || t['is_completed'] == true;
  }

  Future<void> _toggleChild(Map<String, dynamic> t) async {
    final done = _done(t);
    final target = done
        ? (_statuses.where((s) => s.isInitial).firstOrNull ?? _statuses.firstOrNull)
        : _statuses.where((s) => s.isDone).firstOrNull ?? _statuses.lastOrNull;
    if (target == null) return;
    HapticFeedback.selectionClick();
    final i = _tasks.indexOf(t);
    setState(() => _tasks = [..._tasks]..[i] = {...t, 'status_id': int.tryParse(target.id) ?? target.id, 'is_completed': done ? 0 : 1});
    try {
      await _api.updateWorkspaceItem(_boardId, 'task', '${t['id']}', {'status_id': int.tryParse(target.id) ?? target.id});
    } catch (e) {
      if (mounted) setState(() => _tasks = [..._tasks]..[i] = t);
      _snack(formatApiError(e));
    }
  }

  Future<void> _quickSubtask() async {
    final title = _subtaskCtrl.text.trim();
    if (title.isEmpty) return;
    _subtaskCtrl.clear();
    try {
      await _api.createWorkspaceItem(_boardId, 'task', {
        'title': title,
        'type': 'subtask',
        'parent_id': int.tryParse(_id) ?? _id,
        if (_item['epic_id'] != null) 'epic_id': _item['epic_id'],
        if (_me != null) 'assignee_id': int.tryParse(_me!) ?? _me,
      });
      HapticFeedback.lightImpact();
      await _reloadTasks();
    } catch (e) {
      _subtaskCtrl.text = title;
      _snack(formatApiError(e));
    }
  }

  Map<String, dynamic> _withBoard(Map<String, dynamic> row) => {
    ...row,
    'board_id': _boardId,
    'board_code': _item['board_code'],
    'board_name': _item['board_name'],
  };

  Future<void> _open(Map<String, dynamic> row) async {
    await nxPush<void>(context, TaskDetailScreen(task: _withBoard(row)));
    if (mounted) {
      _reloadTasks();
      _reloadItem();
    }
  }

  // ── attachments
  List<Map<String, dynamic>> get _attachments => taskAttachments(_item['attachments']);

  Future<void> _addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    final files = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.bytes != null) MultipartFile.fromBytes(f.bytes!, filename: f.name),
    ];
    if (files.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final uploaded = await _api.uploadBoardAttachments(_boardId, files);
      if (!mounted) return;
      setState(() => _saving = false);
      await _update({
        'attachments': [..._attachments, ...uploaded],
      });
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(formatApiError(e));
    }
  }

  // ── watchers / links
  bool get _watching => _me != null && _watchers.any((w) => '${w['user_id']}' == _me);

  Future<void> _toggleWatch([String? userId]) async {
    final uid = userId ?? _me;
    if (uid == null) return;
    final on = _watchers.any((w) => '${w['user_id']}' == uid);
    try {
      on ? await _api.removeItemWatcher(_boardId, _kind, _id, uid) : await _api.addItemWatcher(_boardId, _kind, _id, uid);
      HapticFeedback.selectionClick();
      final w = await _api.getItemWatchers(_boardId, _kind, _id);
      if (mounted) setState(() => _watchers = w);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _addWatcher() async {
    final v = await showNxPickerSheet(
      context: context,
      title: tr('เพิ่มผู้ติดตาม'),
      options: [
        for (final e in _users.entries)
          if (!_watchers.any((w) => '${w['user_id']}' == e.key)) NxPickOption(value: e.key, label: e.value),
      ],
    );
    if (v != null && v.isNotEmpty) await _toggleWatch(v);
  }

  String _watcherName(Map<String, dynamic> w) {
    final n = [w['first_name'], w['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim();
    if (n.isNotEmpty) return n;
    return '${w['jira_display_name'] ?? w['user_name'] ?? _users['${w['user_id']}'] ?? '#${w['user_id']}'}';
  }

  Map<String, dynamic>? _linkTarget(Map<String, dynamic> l) {
    final outgoing = '${l['from_type']}' == _kind && '${l['from_id']}' == _id;
    final kind = outgoing ? '${l['to_type']}' : '${l['from_type']}';
    final id = outgoing ? '${l['to_id']}' : '${l['from_id']}';
    final pool = kind == 'epic' ? _epics : _tasks;
    return pool.where((t) => '${t['id']}' == id).firstOrNull ?? {'id': id, if (kind == 'epic') '_kind': 'epic', 'title': '#$id'};
  }

  String _linkLabel(Map<String, dynamic> l) {
    final outgoing = '${l['from_type']}' == _kind && '${l['from_id']}' == _id;
    final t = '${l['link_type']}';
    if (!outgoing && t == 'blocks') return 'ถูกบล็อกโดย';
    if (!outgoing && t == 'is_blocked_by') return 'บล็อก';
    return _linkTypes[t] ?? t;
  }

  Future<void> _addLink() async {
    final type = await showNxPickerSheet(
      context: context,
      title: tr('ประเภทลิงก์'),
      options: [for (final e in _linkTypes.entries) NxPickOption(value: e.key, label: tr(e.value))],
    );
    if (type == null || !mounted) return;
    final target = await showNxPickerSheet(
      context: context,
      title: tr('เลือกงาน'),
      options: [
        for (final t in _tasks)
          if ('${t['id']}' != _id || _isEpic)
            NxPickOption(
              value: 'task:${t['id']}',
              label: '${wsKey(t, boardCode: _code)} ${wsTitle(t)}',
            ),
        for (final e in _epics)
          if ('${e['id']}' != _id || !_isEpic)
            NxPickOption(
              value: 'epic:${e['id']}',
              label: '${wsKey(e, boardCode: _code)} ${wsTitle(e)}',
              subtitle: 'Epic',
            ),
      ],
    );
    if (target == null) return;
    final [k, id] = target.split(':');
    try {
      await _api.addItemLink(_boardId, _kind, _id, toKind: k, toId: id, linkType: type);
      final l = await _api.getItemLinks(_boardId, _kind, _id);
      if (mounted) setState(() => _links = l);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _removeLink(Map<String, dynamic> l) async {
    try {
      await _api.deleteItemLink(_boardId, '${l['id']}');
      setState(() => _links = [..._links]..remove(l));
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  // ── menu actions
  Future<void> _editAll() async {
    final saved = await nxPush<Map<String, dynamic>>(
      context,
      WorkspaceItemFormScreen(
        board: {'id': _boardId, 'code': _code, 'name': _item['board_name']},
        statuses: _statuses,
        epics: _epics,
        tasks: _tasks,
        edit: _item,
        users: _users,
      ),
    );
    if (saved != null && mounted) {
      await _reloadItem();
      _activity.currentState?.reload();
    }
  }

  Future<void> _duplicate() async {
    final saved = await nxPush<Map<String, dynamic>>(
      context,
      WorkspaceItemFormScreen(
        board: {'id': _boardId, 'code': _code, 'name': _item['board_name']},
        statuses: _statuses,
        epics: _epics,
        tasks: _tasks,
        kind: _kind,
        duplicateFrom: _item,
        users: _users,
      ),
    );
    if (saved != null && mounted) {
      await nxPush<void>(context, TaskDetailScreen(task: _withBoard(saved)));
    }
  }

  Future<void> _addSubtaskForm() async {
    final saved = await nxPush<Map<String, dynamic>>(
      context,
      WorkspaceItemFormScreen(
        board: {'id': _boardId, 'code': _code, 'name': _item['board_name']},
        statuses: _statuses,
        epics: _epics,
        tasks: _tasks,
        parent: _item,
        users: _users,
      ),
    );
    if (saved != null) _reloadTasks();
  }

  Future<void> _moveBoard() async {
    List<Map<String, dynamic>> boards;
    try {
      boards = await _api.getBoards();
    } catch (e) {
      _snack(formatApiError(e));
      return;
    }
    if (!mounted) return;
    final v = await showNxPickerSheet(
      context: context,
      title: tr('ย้ายไปบอร์ด'),
      options: [
        for (final b in boards)
          if ('${b['id']}' != _boardId) NxPickOption(value: '${b['id']}', label: '${b['name'] ?? b['id']}', subtitle: b['code']?.toString()),
      ],
    );
    if (v == null || !mounted) return;
    try {
      await _api.moveWorkspaceItem(_boardId, _kind, _id, v);
      if (!mounted) return;
      _snack('ย้ายงานแล้ว');
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  String get _webUrl {
    final base = Uri.tryParse(context.read<AppConfig>().apiBaseUrl);
    final key = wsLinkKey(_item, boardCode: _code);
    if (base == null) return key;
    return base.replace(path: key.contains('-') ? '/workspace/$key' : '/workspace/$_boardId', query: null).toString();
  }

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: wsLinkKey(_item, boardCode: _code)));
    HapticFeedback.selectionClick();
    _snack('คัดลอกรหัสแล้ว');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบงานนี้?')),
        content: Text(tr('งานจะถูกย้ายไปถังขยะของ Workspace')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = _api;
    final board = _boardId, kind = _kind, id = _id;
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: 'ws_$kind',
      ids: [id],
      label: wsKey(_item, boardCode: _code),
      commit: () => api.deleteWorkspaceItem(board, kind, id),
    );
    Navigator.of(context).pop(true);
  }

  void _menu() {
    final cs = Theme.of(context).colorScheme;
    showNxBlurPanel<void>(
      context: context,
      builder: (ctx) {
        Widget item(IconData i, String t, VoidCallback f, {Color? color}) => ListTile(
          leading: Icon(i, color: color),
          title: Text(tr(t), style: color == null ? null : TextStyle(color: color)),
          onTap: () {
            Navigator.pop(ctx);
            f();
          },
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(NxI.pencilSimple, 'แก้ไขทั้งหมด', _editAll),
              item(NxI.copySimple, 'ทำซ้ำ', _duplicate),
              if (!_isEpic && !_isChild) item(NxI.subtask, 'เพิ่มงานย่อย', _addSubtaskForm),
              if (!_isEpic) item(NxI.clock, 'ลงเวลา', _logTime),
              item(NxI.arrowsLeftRight, 'ย้ายไปบอร์ดอื่น', _moveBoard),
              item(NxI.hash, 'คัดลอกรหัส', _copyKey),
              item(NxI.shareNetwork, 'แชร์ลิงก์', () => Share.share(wsShareText(_item, _webUrl, boardCode: _code))),
              item(NxI.sparkle, 'ถาม Isaac', () => context.push(AppRoutes.aiAsk(module: 'workspace_item', id: _id, title: '${wsKey(_item, boardCode: _code)} ${_item['title'] ?? ''}'.trim()))),
              item(NxI.trash, _isEpic ? 'ลบ Epic' : 'ลบงาน', _delete, color: cs.error),
            ],
          ),
        );
      },
    );
  }

  // ── build
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = wsTypeStyle(_type);
    final key = wsKey(_item, boardCode: _code);
    final epic = _epics.where((e) => '${e['id']}' == '${_item['epic_id']}').firstOrNull;
    final parent = _tasks.where((t) => '${t['id']}' == '${_item['parent_id']}').firstOrNull;
    final title = wsTitle(_item).isEmpty ? entityTitle(_item, module: 'task') : wsTitle(_item);
    final desc = _item['description']?.toString() ?? '';
    final children = _children;

    return NxScrollScaffold(
      // Board in the header; the key shows once, in the path below.
      header: NxAppHeader(
        title: '${_item['board_name'] ?? wsDisplayCode(_code ?? '')}',
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_online) ...[
            IconButton(tooltip: _watching ? tr('เลิกติดตาม') : tr('ติดตาม'), icon: Icon(_watching ? NxI.eyeSlash : NxI.eye), onPressed: () => _toggleWatch()),
            IconButton(tooltip: tr('เพิ่มเติม'), icon: const Icon(NxI.dotsThree), onPressed: _menu),
          ],
        ],
      ),
      body: NxRefresh(
        onRefresh: () async {
          await _load();
          await _activity.currentState?.reload();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
          // Everything gets the page gutter except the full-width status stepper.
          children: [
            for (final c in <Widget>[
              // Path: EPIC-1 › TASK-2 › SUB-5 (keys only, tap to open) · priority
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Tooltip(
                    message: tr(type.label),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: type.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: Icon(type.icon, size: 15, color: type.color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final row in [?epic, ?parent]) ...[
                            InkWell(
                              key: ValueKey('ws-path-${wsKey(row, boardCode: _code)}'),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _open(row),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                child: Text(
                                  wsKey(row, boardCode: _code),
                                  style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(NxI.caretRight, size: 14, color: cs.outline),
                            ),
                          ],
                          GestureDetector(
                            onLongPress: _copyKey,
                            child: Text(
                              key,
                              key: const ValueKey('ws-path-self'),
                              style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_item['priority'] != null)
                    Builder(
                      builder: (_) {
                        final p = wsPriorityStyle('${_item['priority']}');
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: p.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(p.icon, size: 14, color: p.color),
                              const SizedBox(width: 3),
                              Text(tr(p.label), style: theme.textTheme.labelMedium?.copyWith(color: p.color, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Title (tap to edit in place)
              if (_editingTitle)
                TextField(
                  controller: _titleCtrl,
                  autofocus: true,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(isDense: true),
                  onSubmitted: (_) => _saveTitle(),
                  onTapOutside: (_) => _saveTitle(),
                )
              else
                GestureDetector(
                  onTap: _online
                      ? () => setState(() {
                          _titleCtrl.text = title;
                          _editingTitle = true;
                        })
                      : null,
                  child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                ),
              const SizedBox(height: 16),
              if (_statuses.isNotEmpty)
                Padding(
                  key: _bleed,
                  padding: const EdgeInsets.only(bottom: 14),
                  child: WsStatusStepper(statuses: _statuses, current: '${_item['status_id'] ?? ''}', busy: _saving, onPick: _online ? _setStatus : null),
                ),
              if (_online) Padding(padding: const EdgeInsets.only(bottom: 12), child: _isEpic ? _epicTime(children) : _timeCard()),
              _descriptionSection(context, desc),
              _fieldsSection(context, epic, parent),
              if (_online && (_isEpic || !_isChild)) _childrenSection(context, children),
              if (_online && !_isEpic) SmartChecklistSection(boardId: _boardId, taskId: _id),
              if (_online) ...[
                const SizedBox(height: 12),
                _attachmentsSection(context),
                _peopleSection(context),
                _linksSection(context),
                const SizedBox(height: 4),
              ],
              WsActivityPanel(
                key: _activity,
                boardId: _boardId,
                kind: _kind,
                itemId: _id,
                meId: _me,
                lookups: WsLookups(
                  users: _users,
                  statuses: _statuses,
                  items: {
                    for (final t in _tasks) 'task:${t['id']}': {...t, 'board_code': _code},
                    for (final e in _epics) 'epic:${e['id']}': {...e, 'board_code': _code},
                  },
                ),
                onWorklogChanged: _reloadItem,
              ),
            ])
              c.key == _bleed ? c : Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: c),
          ],
        ),
      ),
    );
  }

  Widget _timeCard() => WsTimeCard(
    spent: wsInt(_item['time_spent_minutes']) ?? 0,
    estimate: wsInt(_item['original_estimate_minutes']),
    remaining: wsInt(_item['time_remaining_minutes']),
    onLog: _logTime,
    timer: WsTaskTimer(
      prefsKey: '${_boardId}_$_id',
      onStop: (m) => _logTime(minutes: m),
    ),
  );

  Widget _epicTime(List<Map<String, dynamic>> children) {
    var spent = 0, est = 0;
    for (final c in children) {
      spent += wsInt(c['time_spent_minutes']) ?? 0;
      est += wsInt(c['original_estimate_minutes']) ?? 0;
    }
    return WsTimeCard(
      spent: spent + (wsInt(_item['time_spent_minutes']) ?? 0),
      estimate: est > 0 ? est : wsInt(_item['original_estimate_minutes']),
      remaining: null,
    );
  }

  Widget _descriptionSection(BuildContext context, String desc) {
    final theme = Theme.of(context);
    final rich = looksLikeHtmlString(desc);
    return WsSection(
      title: 'คำอธิบาย',
      icon: NxI.textT,
      trailing: _online && !rich ? IconButton(tooltip: tr('แก้ไข'), icon: const Icon(NxI.pencilSimple, size: 18), onPressed: _editDescription) : null,
      child: desc.trim().isEmpty
          ? Text(tr('ไม่มีคำอธิบาย'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          : NxHtmlView(html: desc, style: theme.textTheme.bodyLarge),
    );
  }

  Widget _fieldsSection(BuildContext context, Map<String, dynamic>? epic, Map<String, dynamic>? parent) {
    final cs = Theme.of(context).colorScheme;
    String date(String f) {
      final d = taskDateOnly(_item[f]);
      if (d == null) return '';
      final p = parseThai(d);
      return p == null ? d : '${p.day}/${p.month}/${uiYear(p.year)}';
    }

    final due = wsDueIn(_item['due_date']);
    final blocked = _tasks.where((t) => '${t['id']}' == '${_item['blocked_by_id']}').firstOrNull;
    final recur = {'none': 'ไม่ทำซ้ำ', 'weekly': 'ทุกสัปดาห์', 'biweekly': 'ทุก 2 สัปดาห์', 'monthly': 'ทุกเดือน'};
    final rows = <(bool, Widget)>[
      (
        _item['assignee_id'] != null,
        WsFieldRow(
          icon: NxI.user,
          label: 'ผู้รับผิดชอบ',
          value: _item['assignee_id'] == null ? '' : _users['${_item['assignee_id']}'] ?? '${_item['assignee_name'] ?? '#${_item['assignee_id']}'}',
          onTap: _online ? () => _pickUser('assignee_id') : null,
        ),
      ),
      (
        _item['reporter_id'] != null,
        WsFieldRow(
          icon: NxI.user,
          label: 'ผู้รายงาน',
          value: _item['reporter_id'] == null ? '' : _users['${_item['reporter_id']}'] ?? '#${_item['reporter_id']}',
          onTap: _online ? () => _pickUser('reporter_id') : null,
        ),
      ),
      (
        _item['priority'] != null,
        WsFieldRow(
          icon: NxI.flag,
          label: 'ความสำคัญ',
          value: _item['priority'] == null ? '' : tr(wsPriorityStyle('${_item['priority']}').label),
          onTap: _online
              ? () => _pickEnum('priority', [
                  for (final p in kWsPriorities) NxPickOption(value: p, label: tr(wsPriorityStyle(p).label), color: wsPriorityStyle(p).color),
                ])
              : null,
        ),
      ),
      if (!_isEpic)
        (
          true,
          WsFieldRow(
            icon: wsTypeStyle(_type).icon,
            label: 'ประเภท',
            value: tr(wsTypeStyle(_type).label),
            onTap: _online
                ? () => _pickEnum('type', [
                    for (final t in ['task', 'bug', 'story', 'subtask', if (_type == 'checklist') 'checklist'])
                      NxPickOption(value: t, label: tr(wsTypeStyle(t).label), color: wsTypeStyle(t).color),
                  ])
                : null,
          ),
        ),
      (
        date('start_date').isNotEmpty,
        WsFieldRow(icon: NxI.calendarBlank, label: 'วันเริ่ม', value: date('start_date'), onTap: _online ? () => _pickDate('start_date') : null),
      ),
      (
        date('end_date').isNotEmpty,
        WsFieldRow(icon: NxI.calendarBlank, label: 'วันสิ้นสุด', value: date('end_date'), onTap: _online ? () => _pickDate('end_date') : null),
      ),
      if (!_isEpic)
        (
          date('due_date').isNotEmpty,
          WsFieldRow(
            icon: NxI.calendarBlank,
            label: 'ครบกำหนด',
            value: date('due_date'),
            valueWidget: date('due_date').isEmpty
                ? null
                : Text(
                    '${date('due_date')}${due == null
                        ? ''
                        : due < 0
                        ? ' · ${tr('เลย ${-due} วัน')}'
                        : due == 0
                        ? ' · ${tr('วันนี้')}'
                        : ''}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: due != null && due < 0 && !_done(_item) ? cs.error : null),
                  ),
            onTap: _online ? () => _pickDate('due_date') : null,
          ),
        ),
      (
        (wsInt(_item['original_estimate_minutes']) ?? 0) > 0,
        WsFieldRow(
          icon: NxI.timer,
          label: 'เวลาประมาณ',
          value: (wsInt(_item['original_estimate_minutes']) ?? 0) > 0 ? formatMinutes(wsInt(_item['original_estimate_minutes'])) : '',
          onTap: _online ? () => _editEstimate('original_estimate_minutes') : null,
        ),
      ),
      (
        (wsInt(_item['time_remaining_minutes']) ?? 0) > 0,
        WsFieldRow(
          icon: NxI.timer,
          label: 'เวลาคงเหลือ',
          value: (wsInt(_item['time_remaining_minutes']) ?? 0) > 0 ? formatMinutes(wsInt(_item['time_remaining_minutes'])) : '',
          onTap: _online ? () => _editEstimate('time_remaining_minutes') : null,
        ),
      ),
      (
        '${_item['story_points'] ?? ''}'.isNotEmpty,
        WsFieldRow(icon: NxI.hash, label: 'Story points', value: '${_item['story_points'] ?? ''}', onTap: _online ? _editStoryPoints : null),
      ),
      if (!_isEpic)
        (
          epic != null,
          WsFieldRow(
            icon: NxI.lightning,
            label: 'Epic',
            value: epic == null ? '' : '${wsKey(epic, boardCode: _code)} ${wsTitle(epic)}',
            onTap: _online
                ? () => _pickEnum('epic_id', [
                    for (final e in _epics)
                      NxPickOption(
                        value: '${e['id']}',
                        label: '${wsKey(e, boardCode: _code)} ${wsTitle(e)}',
                      ),
                  ], nullable: true)
                : null,
          ),
        ),
      if (_isChild)
        (
          parent != null,
          WsFieldRow(
            icon: NxI.treeStructure,
            label: 'งานแม่',
            value: parent == null ? '' : '${wsKey(parent, boardCode: _code)} ${wsTitle(parent)}',
            onTap: parent == null ? null : () => _open(parent),
          ),
        ),
      if (!_isEpic)
        (
          _labels.isNotEmpty,
          WsFieldRow(
            icon: NxI.tag,
            label: 'ป้ายกำกับ',
            value: _labels.join(', '),
            valueWidget: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final l in _labels) Chip(label: Text(l), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                if (_online)
                  ActionChip(avatar: const Icon(NxI.plus, size: 14), label: Text(tr('เพิ่ม')), visualDensity: VisualDensity.compact, onPressed: _addLabel),
              ],
            ),
            onTap: _online ? _editLabels : null,
          ),
        ),
      if (!_isEpic)
        (
          blocked != null,
          WsFieldRow(
            icon: NxI.prohibit,
            label: 'ถูกบล็อกโดย',
            value: blocked == null ? '' : '${wsKey(blocked, boardCode: _code)} ${wsTitle(blocked)}',
            onTap: _online
                ? () => _pickEnum('blocked_by_id', [
                    for (final t in _tasks)
                      if ('${t['id']}' != _id)
                        NxPickOption(
                          value: '${t['id']}',
                          label: '${wsKey(t, boardCode: _code)} ${wsTitle(t)}',
                        ),
                  ], nullable: true)
                : null,
          ),
        ),
      if (!_isEpic)
        (
          (_item['recurrence_type'] ?? 'none') != 'none',
          WsFieldRow(
            icon: NxI.repeat,
            label: 'ทำซ้ำอัตโนมัติ',
            value: tr(recur['${_item['recurrence_type'] ?? 'none'}'] ?? '${_item['recurrence_type']}'),
            onTap: _online ? () => _pickEnum('recurrence_type', [for (final e in recur.entries) NxPickOption(value: e.key, label: tr(e.value))]) : null,
          ),
        ),
    ];
    final shown = [
      for (final (filled, w) in rows)
        if (_showAll || filled) w,
    ];
    return WsSection(
      title: 'ข้อมูล',
      icon: NxI.listChecks,
      color: const Color(0xFFF97316),
      trailing: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        segments: [
          ButtonSegment(value: false, label: Text(tr('มีข้อมูล'))),
          ButtonSegment(value: true, label: Text(tr('ทั้งหมด'))),
        ],
        selected: {_showAll},
        onSelectionChanged: (s) => setState(() => _showAll = s.first),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: Column(
          children: shown.isEmpty ? [Padding(padding: const EdgeInsets.all(8), child: Text(tr('ยังไม่มีข้อมูล — แตะ "ทั้งหมด" เพื่อกรอก')))] : shown,
        ),
      ),
    );
  }

  Widget _childrenSection(BuildContext context, List<Map<String, dynamic>> children) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final done = children.where(_done).length;
    return WsSection(
      title: _isEpic ? 'งานใน Epic' : 'งานย่อย',
      icon: _isEpic ? NxI.lightning : NxI.subtask,
      color: _isEpic ? const Color(0xFF8B5CF6) : const Color(0xFF0EA5E9),
      trailing: children.isEmpty ? null : Text('$done/${children.length}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: done / children.length),
                  duration: const Duration(milliseconds: 500),
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: const Color(0xFF10B981)),
                ),
              ),
            ),
          for (final c in children)
            Row(
              children: [
                if (!_isEpic)
                  Checkbox(value: _done(c), onChanged: (_) => _toggleChild(c), visualDensity: VisualDensity.compact)
                else
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(wsTypeStyle(wsType(c)).icon, size: 16, color: wsTypeStyle(wsType(c)).color),
                  ),
                Expanded(
                  child: InkWell(
                    onTap: () => _open(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${wsKey(c, boardCode: _code)}  ',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                            TextSpan(text: wsTitle(c)),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: _done(c) ? TextDecoration.lineThrough : null,
                          color: _done(c) ? cs.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                  ),
                ),
                Builder(
                  builder: (_) {
                    final s = _statuses.where((s) => s.id == '${c['status_id']}').firstOrNull;
                    if (s == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        s.label,
                        style: theme.textTheme.labelSmall?.copyWith(color: s.color, fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ],
            ),
          if (!_isEpic)
            TextField(
              key: const ValueKey('ws-subtask-add'),
              controller: _subtaskCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _quickSubtask(),
              decoration: InputDecoration(
                hintText: tr('เพิ่มงานย่อย แล้วกด Enter'),
                prefixIcon: const Icon(NxI.plus, size: 18),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          if (_isEpic && children.isEmpty) Text(tr('ยังไม่มีงานใน Epic นี้'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _attachmentsSection(BuildContext context) {
    final files = _attachments;
    return WsSection(
      title: files.isEmpty ? 'ไฟล์แนบ' : 'ไฟล์แนบ (${files.length})',
      icon: NxI.paperclip,
      color: const Color(0xFF64748B),
      trailing: TextButton.icon(onPressed: _saving ? null : _addAttachment, icon: const Icon(NxI.plus, size: 16), label: Text(tr('แนบไฟล์'))),
      child: files.isEmpty
          ? Text(tr('ยังไม่มีไฟล์แนบ'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
          : NxAttachmentStrip(
              key: const ValueKey('ws-attachments'),
              items: [for (final a in files) Map<String, dynamic>.from(a)],
              thumb: 92,
              onRemove: _saving ? null : (a) => _update({'attachments': files.where((x) => x['url'] != a['url']).toList()}),
            ),
    );
  }

  Widget _peopleSection(BuildContext context) {
    return WsSection(
      title: _watchers.isEmpty ? 'ผู้ติดตาม' : 'ผู้ติดตาม (${_watchers.length})',
      icon: NxI.eye,
      color: const Color(0xFF14B8A6),
      trailing: TextButton.icon(onPressed: _addWatcher, icon: const Icon(NxI.plus, size: 16), label: Text(tr('เพิ่ม'))),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final w in _watchers)
            InputChip(
              avatar: NxAvatar(label: _watcherName(w), size: 22),
              label: Text(_watcherName(w)),
              onDeleted: () => _toggleWatch('${w['user_id']}'),
            ),
          if (!_watching) ActionChip(avatar: const Icon(NxI.eye, size: 16), label: Text(tr('ติดตามงานนี้')), onPressed: () => _toggleWatch()),
        ],
      ),
    );
  }

  Widget _linksSection(BuildContext context) {
    final theme = Theme.of(context);
    return WsSection(
      title: _links.isEmpty ? 'ลิงก์งาน' : 'ลิงก์งาน (${_links.length})',
      icon: NxI.link,
      color: const Color(0xFF6366F1),
      trailing: TextButton.icon(onPressed: _addLink, icon: const Icon(NxI.plus, size: 16), label: Text(tr('เพิ่ม'))),
      child: Column(
        children: [
          for (final l in _links)
            Builder(
              builder: (_) {
                final t = _linkTarget(l)!;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(wsTypeStyle(wsType(t)).icon, color: wsTypeStyle(wsType(t)).color, size: 18),
                  title: Text('${wsKey(t, boardCode: _code)} ${wsTitle(t)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(tr(_linkLabel(l)), style: theme.textTheme.labelSmall),
                  onTap: () => _open(t),
                  trailing: IconButton(tooltip: tr('นำออก'), icon: const Icon(NxI.unlink, size: 18), onPressed: () => _removeLink(l)),
                );
              },
            ),
        ],
      ),
    );
  }
}
