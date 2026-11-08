import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import 'task_detail_screen.dart';
import 'workspace_item_form.dart';
import 'ws_kanban.dart';
import '../../widgets/nx_refresh.dart';

/// One board: Kanban (drag & drop with edge auto-scroll), grouped list, or
/// epics; search/filters; quick add per column; multi-select actions.
class WorkspaceBoardScreen extends StatefulWidget {
  const WorkspaceBoardScreen({super.key, required this.board});
  final Map<String, dynamic> board;

  @override
  State<WorkspaceBoardScreen> createState() => _WorkspaceBoardScreenState();
}

/// In-memory last load per board — reopening shows it at once, then refreshes.
final Map<String, ({List<Map<String, dynamic>> statuses, List<Map<String, dynamic>> tasks, List<Map<String, dynamic>> epics})>
    _boardCache = {};

class _WorkspaceBoardScreenState extends State<WorkspaceBoardScreen> {
  Map<String, dynamic> _board = {};
  List<WsStatus> _statuses = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _epics = [];
  Map<String, String> _users = {};
  bool _loading = true;
  Object? _error;
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;
  String? _businessId;
  String _view = 'kanban';
  NxListQuery _q = const NxListQuery();
  late final NxListPrefs _prefs = NxListPrefs('ws_board_${_boardId}_${context.read<AppConfig>().prefsScope}');
  final Set<String> _selected = {};

  String get _boardId => widget.board['id']?.toString() ?? '';
  String get _code => '${_board['code'] ?? widget.board['code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _board = Map<String, dynamic>.from(widget.board);
    wsRememberBoard(_board);
    final hit = _boardCache[_boardId];
    if (hit != null) _apply(hit.statuses, hit.tasks, hit.epics);
    _prefs.loadQuery().then((q) {
      if (q != null && mounted) setState(() => _q = q);
    });
    _load();
    _businessId = context.read<AppConfig>().session.businessId;
    if (_boardId.isNotEmpty) RealtimeService.instance.joinWorkspaceBoard(_boardId, businessId: _businessId);
    // Someone edits the board on the web → reload (debounced for bursts).
    _live = RealtimeService.instance.events.where((e) => e.type.startsWith('workspace:item_')).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    if (_boardId.isNotEmpty) RealtimeService.instance.leaveWorkspaceBoard(_boardId, businessId: _businessId);
    super.dispose();
  }

  void _apply(List<Map<String, dynamic>> st, List<Map<String, dynamic>> tasks, List<Map<String, dynamic>> epics) {
    _statuses = WsStatus.list(st);
    _tasks = [for (final t in tasks) {...t, 'board_id': t['board_id'] ?? _boardId, 'board_code': _code}];
    _epics = [for (final e in epics) {...e, '_kind': 'epic', 'board_id': e['board_id'] ?? _boardId, 'board_code': _code}];
    _loading = false;
  }

  Future<void> _load() async {
    if (int.tryParse(_boardId) == null) {
      setState(() {
        _error = 'ไม่พบบอร์ดนี้';
        _loading = false;
      });
      return;
    }
    final api = context.read<AppConfig>().apiClient;
    try {
      final r = await Future.wait([
        api.getBoardStatuses(_boardId),
        api.getBoardTasks(_boardId),
        api.getBoardEpics(_boardId),
        api.getBoard(_boardId).then<Object>((b) => b).catchError((_) => <String, dynamic>{}),
        api.getUsersCached().then<Object>((u) => u).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final st = r[0] as List<Map<String, dynamic>>;
      final tasks = r[1] as List<Map<String, dynamic>>;
      final epics = r[2] as List<Map<String, dynamic>>;
      _boardCache[_boardId] = (statuses: st, tasks: tasks, epics: epics);
      setState(() {
        final b = r[3] as Map<String, dynamic>;
        if (b.isNotEmpty) _board = {..._board, ...b};
        wsRememberBoard(_board);
        nxRememberUserPhotos(r[4] as List<Map<String, dynamic>>, context.read<AppConfig>().apiClient.absoluteUrl);
        _users = {
          for (final u in r[4] as List<Map<String, dynamic>>)
            '${u['id']}': [u['first_name'], u['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim().isNotEmpty
                ? [u['first_name'], u['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim()
                : '${u['user_name'] ?? u['email1'] ?? u['id']}',
        };
        _apply(st, tasks, epics);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  // ── filters
  List<NxFilterGroup> get _groups {
    final labels = <String>{
      for (final t in _tasks)
        for (final l in (t['labels'] is List ? t['labels'] as List : const [])) '$l',
    }.toList()
      ..sort();
    return [
      const NxFilterGroup(key: 'scope', label: 'ขอบเขต', multi: false, options: [NxFilterOption('mine', 'ของฉัน')]),
      NxFilterGroup(key: 'type', label: 'ประเภท', options: [
        for (final t in ['task', 'bug', 'story', 'subtask', if (_tasks.any((x) => x['type'] == 'checklist')) 'checklist']) NxFilterOption(t, wsTypeStyle(t).label),
      ]),
      NxFilterGroup(key: 'priority', label: 'ความสำคัญ', options: [
        for (final p in kWsPriorities) NxFilterOption(p, wsPriorityStyle(p).label),
      ]),
      NxFilterGroup(key: 'due', label: 'ครบกำหนด', multi: false, options: const [
        NxFilterOption('overdue', 'เลยกำหนด'),
        NxFilterOption('today', 'วันนี้'),
        NxFilterOption('week', '7 วันข้างหน้า'),
        NxFilterOption('none', 'ไม่กำหนดส่ง'),
      ]),
      if (_epics.isNotEmpty)
        NxFilterGroup(key: 'epic', label: 'Epic', options: [for (final e in _epics) NxFilterOption('${e['id']}', wsTitle(e))]),
      if (_users.isNotEmpty)
        NxFilterGroup(key: 'assignee', label: 'ผู้รับผิดชอบ', options: [
          for (final e in _users.entries)
            if (_tasks.any((t) => '${t['assignee_id']}' == e.key)) NxFilterOption(e.key, e.value),
        ]),
      if (labels.isNotEmpty) NxFilterGroup(key: 'label', label: 'ป้ายกำกับ', options: [for (final l in labels) NxFilterOption(l, l)]),
      const NxFilterGroup(key: 'show', label: 'แสดง', options: [NxFilterOption('children', 'แสดงงานย่อย')]),
    ];
  }

  List<Map<String, dynamic>> get _visibleTasks {
    final me = context.read<AppConfig>().session.userId ?? '';
    final showChildren = _q.has('show', 'children') || _q.values('type').any((t) => t == 'subtask' || t == 'checklist');
    return nxApplyLocalQuery<Map<String, dynamic>>(
      [
        for (final t in _tasks)
          if (showChildren || (t['type'] != 'subtask' && t['type'] != 'checklist')) t,
      ],
      _q,
      text: (t) => '${wsKey(t)} ${t['title'] ?? ''} ${t['description_preview'] ?? ''}',
      filters: {
        'scope': (t, v) => !v.contains('mine') || '${t['assignee_id']}' == me,
        'type': (t, v) => v.contains('${t['type'] ?? 'task'}'),
        'priority': (t, v) => v.contains('${t['priority'] ?? 'medium'}'),
        'epic': (t, v) => v.contains('${t['epic_id']}'),
        'assignee': (t, v) => v.contains('${t['assignee_id']}'),
        'label': (t, v) => (t['labels'] is List ? t['labels'] as List : const []).any((l) => v.contains('$l')),
        'due': (t, v) {
          final d = wsDueIn(t['due_date']);
          if (v.contains('none')) return d == null;
          if (d == null) return false;
          return (v.contains('overdue') && d < 0) || (v.contains('today') && d == 0) || (v.contains('week') && d >= 0 && d <= 7);
        },
      },
      sorts: {
        'due': (a, b) => '${a['due_date'] ?? '9999'}'.compareTo('${b['due_date'] ?? '9999'}'),
        'priority': (a, b) => kWsPriorities.indexOf('${a['priority'] ?? 'medium'}').compareTo(kWsPriorities.indexOf('${b['priority'] ?? 'medium'}')),
        'updated': (a, b) => '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'),
      },
    );
  }

  // ── actions
  Future<bool> _move(Map<String, dynamic> item, String statusId, List<String> order) async {
    final api = context.read<AppConfig>().apiClient;
    try {
      if ('${item['status_id']}' != statusId) {
        await api.updateWorkspaceItem(_boardId, 'task', '${item['id']}', {'status_id': int.tryParse(statusId) ?? statusId});
      }
      try {
        await api.reorderBoardTasks(_boardId, order);
      } catch (_) {
        // Order is a nicety (mixed types in a column can be refused); the status stuck.
      }
      final idx = _tasks.indexWhere((t) => '${t['id']}' == '${item['id']}');
      if (idx >= 0) {
        _tasks[idx] = {..._tasks[idx], 'status_id': int.tryParse(statusId) ?? statusId};
        for (var i = 0; i < order.length; i++) {
          final j = _tasks.indexWhere((t) => '${t['id']}' == order[i]);
          if (j >= 0) _tasks[j] = {..._tasks[j], 'sort_order': i};
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ย้ายไม่สำเร็จ: ${formatApiError(e)}'))));
      }
      return false;
    }
  }

  Future<void> _quickAdd(String statusId, String title) async {
    final config = context.read<AppConfig>();
    try {
      await config.apiClient.createWorkspaceItem(_boardId, 'task', wsQuickAddBody(title: title, statusId: statusId, me: config.session.userId));
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    await nxPush<void>(
      context,
      TaskDetailScreen(task: {...item, 'board_id': _boardId, 'board_code': _code, 'board_name': _board['name']}),
      root: true,
    );
    if (mounted) _load();
  }

  Future<void> _create({String kind = 'task'}) async {
    final saved = await nxPush<Map<String, dynamic>>(
      context,
      WorkspaceItemFormScreen(board: _board, statuses: _statuses, epics: _epics, tasks: _tasks, kind: kind, users: _users),
      root: true,
    );
    if (saved != null && mounted) _load();
  }

  /// Long-press on +: choose Task or Epic.
  Future<void> _createChoice() async {
    HapticFeedback.mediumImpact();
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('ws-create-task'),
            leading: const Icon(NxI.checkSquare),
            title: Text(tr('สร้าง Task')),
            onTap: () => Navigator.pop(ctx, 'task'),
          ),
          ListTile(
            key: const ValueKey('ws-create-epic'),
            leading: const Icon(NxI.lightning),
            title: Text(tr('สร้าง Epic')),
            onTap: () => Navigator.pop(ctx, 'epic'),
          ),
        ]),
      ),
    );
    if (kind != null && mounted) _create(kind: kind);
  }

  void _toggle(Map<String, dynamic> item) {
    HapticFeedback.selectionClick();
    final id = '${item['id']}';
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  Future<void> _bulk(String what) async {
    final api = context.read<AppConfig>().apiClient;
    final items = [for (final id in _selected) ('task', id)];
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (what == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ลบ ${items.length} รายการ?')),
            content: Text(tr('รายการจะย้ายไปถังขยะ กู้คืนได้')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
            ],
          ),
        );
        if (ok != true) return;
        await api.bulkDeleteWorkspaceItems(_boardId, items);
      } else {
        final pick = await showAppBottomSheet<String>(
          context: context,
          title: what == 'status' ? 'เปลี่ยนสถานะ' : (what == 'priority' ? 'เปลี่ยนความสำคัญ' : 'มอบหมายให้'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (what == 'status')
                for (final s in _statuses)
                  ListTile(
                    leading: CircleAvatar(radius: 6, backgroundColor: s.color),
                    title: Text(s.label),
                    onTap: () => Navigator.pop(context, s.id),
                  ),
              if (what == 'priority')
                for (final p in kWsPriorities)
                  ListTile(
                    leading: Icon(wsPriorityStyle(p).icon, color: wsPriorityStyle(p).color),
                    title: Text(tr(wsPriorityStyle(p).label)),
                    onTap: () => Navigator.pop(context, p),
                  ),
              if (what == 'assignee')
                for (final u in _users.entries)
                  ListTile(leading: const Icon(NxI.user), title: Text(u.value), onTap: () => Navigator.pop(context, u.key)),
            ],
          ),
        );
        if (pick == null) return;
        final key = switch (what) { 'status' => 'status_id', 'priority' => 'priority', _ => 'assignee_id' };
        await api.bulkUpdateWorkspaceItems(_boardId, items, {key: what == 'priority' ? pick : (int.tryParse(pick) ?? pick)});
      }
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('อัปเดต ${items.length} รายการแล้ว'))));
      setState(_selected.clear);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  /// View menu behind the folded header icon.
  void _pickView() {
    HapticFeedback.selectionClick();
    final cs = Theme.of(context).colorScheme;
    showNxBlurPanel<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, label, icon) in const [
              ('kanban', 'บอร์ด', NxI.kanban),
              ('list', 'รายการ', NxI.listBullets),
              ('epic', 'Epic', NxI.lightning),
            ])
              ListTile(
                leading: Icon(icon, color: _view == v ? cs.primary : null),
                title: Text(tr(label)),
                trailing: _view == v ? Icon(NxI.check, color: cs.primary) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _view = v);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_board['name'] ?? 'บอร์ด'}';
    final theme = Theme.of(context);
    final tasks = _loading ? const <Map<String, dynamic>>[] : _visibleTasks;
    final PreferredSizeWidget header = _selected.isNotEmpty
        ? AppBar(
            leading: IconButton(icon: const Icon(NxI.x), onPressed: () => setState(_selected.clear)),
            title: Text(tr('เลือก ${_selected.length} รายการ')),
            actions: [
              IconButton(tooltip: tr('เปลี่ยนสถานะ'), icon: const Icon(NxI.flag), onPressed: () => _bulk('status')),
              IconButton(tooltip: tr('มอบหมายให้'), icon: const Icon(NxI.user), onPressed: () => _bulk('assignee')),
              IconButton(tooltip: tr('ความสำคัญ'), icon: const Icon(NxI.chevronsUp), onPressed: () => _bulk('priority')),
              IconButton(tooltip: tr('ลบ'), icon: const Icon(NxI.trash), onPressed: () => _bulk('delete')),
            ],
          )
        : NxAppHeader(
            title: name,
            // Automatic deal codes (D26…) mean nothing to people.
            subtitle: _code.isEmpty || RegExp(r'^D\d{8,}$').hasMatch(_code) || _code.toUpperCase() == name.toUpperCase() ? null : _code,
            actions: [
            ],
            menu: [
              NxHeaderMenuItem(label: 'สร้าง Task', icon: NxI.checkSquare, onTap: () => _create()),
              NxHeaderMenuItem(label: 'สร้าง Epic', icon: NxI.lightning, onTap: () => _create(kind: 'epic')),
            ],
          );
    final toolbar = NxListToolbar(
      query: _q,
      prefs: _prefs,
      liveSearch: true,
      searchHint: 'ค้นหารหัส / ชื่องาน',
      quickGroup: 'scope',
      groups: _groups,
      resultCount: _loading ? null : tasks.length,
      // Folded: the view switch becomes one header icon showing the current view.
      extraActions: [
        NxChromeAction(
          id: 'view',
          icon: switch (_view) { 'list' => NxI.listBullets, 'epic' => NxI.lightning, _ => NxI.kanban },
          tooltip: 'มุมมอง',
          onTap: _pickView,
        ),
      ],
      // Compact view switch (icons; the current one also shows its name),
      // on the same row as the "ของฉัน" chip.
      leading: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _ViewSwitch(value: _view, onChanged: (v) => setState(() => _view = v)),
        ),
      ],
      sorts: const [
        NxSortOption('board', 'ตามลำดับบนบอร์ด'),
        NxSortOption('due', 'ครบกำหนดก่อน'),
        NxSortOption('priority', 'ความสำคัญสูงก่อน'),
        NxSortOption('updated', 'แก้ไขล่าสุด'),
      ],
      onChanged: (q) {
        setState(() => _q = q);
        _prefs.saveQuery(q.copyWith(q: ''));
      },
    );

    Widget body;
    if (_loading) {
      body = _view == 'kanban' ? const NxSkeletonBoard() : const NxSkeletonList();
    } else if (_error != null && _tasks.isEmpty) {
      body = Center(child: Text(tr(formatApiError(_error!))));
    } else if (_view == 'epic') {
      body = _epicList(theme);
    } else if (_view == 'list') {
      body = _groupedList(theme, tasks);
    } else {
      body = WsKanban(
        statuses: _statuses,
        items: tasks,
        users: _users,
        epics: {for (final e in _epics) '${e['id']}': e},
        boardCode: _code,
        onOpen: _open,
        onMove: _move,
        onQuickAdd: _quickAdd,
        selected: _selected,
        onToggleSelect: _toggle,
      );
    }

    return NxScrollScaffold(
      header: header,
      floatingActionButton: _selected.isEmpty ? NxCreateFab(onPressed: () => _create(), onLongPress: _createChoice) : null,
      body: Column(
        children: [
          toolbar,
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _groupedList(ThemeData theme, List<Map<String, dynamic>> tasks) {
    return NxRefresh(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          for (final s in _statuses)
            _StatusSection(
              status: s,
              items: [for (final t in tasks) if ('${t['status_id']}' == s.id) t],
              builder: (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onLongPress: () => _toggle(t),
                  child: WsTaskCard(
                    item: t,
                    users: _users,
                    epic: _epics.where((e) => '${e['id']}' == '${t['epic_id']}').firstOrNull,
                    boardCode: _code,
                    selected: _selected.contains('${t['id']}'),
                    onTap: () => _selected.isNotEmpty ? _toggle(t) : _open(t),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _epicList(ThemeData theme) {
    final cs = theme.colorScheme;
    final doneIds = {for (final s in _statuses) if (s.isDone) s.id};
    if (_epics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(NxI.lightning, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(tr('ยังไม่มี Epic')),
            TextButton.icon(onPressed: () => _create(kind: 'epic'), icon: const Icon(NxI.plus), label: Text(tr('สร้าง Epic'))),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final e in _epics)
          () {
            final children = [for (final t in _tasks) if ('${t['epic_id']}' == '${e['id']}') t];
            final done = children.where((t) => doneIds.contains('${t['status_id']}') || '${t['is_completed']}' == '1').length;
            final spent = children.fold<int>(0, (a, t) => a + (wsInt(t['time_spent_minutes']) ?? 0));
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(e),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(NxI.lightning, size: 16, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 6),
                        Text(wsKey(e, boardCode: _code), style: theme.textTheme.labelSmall),
                        const Spacer(),
                        Text(tr('$done/${children.length} งาน'), style: theme.textTheme.labelMedium),
                      ]),
                      const SizedBox(height: 4),
                      Text(wsTitle(e), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: children.isEmpty ? 0 : done / children.length,
                          minHeight: 6,
                          color: const Color(0xFF8B5CF6),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                      if (spent > 0) ...[
                        const SizedBox(height: 6),
                        Text(tr('ลงเวลาแล้ว ${formatMinutes(spent)}'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _StatusSection extends StatefulWidget {
  const _StatusSection({required this.status, required this.items, required this.builder});
  final WsStatus status;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) builder;

  @override
  State<_StatusSection> createState() => _StatusSectionState();
}

class _StatusSectionState extends State<_StatusSection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              AnimatedRotation(
                turns: _open ? 0 : -0.25,
                duration: const Duration(milliseconds: 180),
                child: const Icon(NxI.caretDown, size: 18),
              ),
              const SizedBox(width: 6),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(s.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${widget.items.length}', style: theme.textTheme.labelMedium?.copyWith(color: s.color)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _open ? Column(children: [for (final t in widget.items) widget.builder(t)]) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _views = [('kanban', 'บอร์ด', NxI.kanban), ('list', 'รายการ', NxI.listBullets), ('epic', 'Epic', NxI.lightning)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      // Same height as the chips next to it; the purple pill fills it.
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label, icon) in _views)
            Semantics(
              button: true,
              selected: v == value,
              label: tr(label),
              child: GestureDetector(
                key: ValueKey('ws-view-$v'),
                onTap: () {
                  if (v == value) return;
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  height: double.infinity,
                  constraints: const BoxConstraints(minWidth: 40),
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(horizontal: v == value ? 12 : 9),
                  decoration: BoxDecoration(color: v == value ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(17)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 18, color: v == value ? cs.onPrimary : cs.onSurfaceVariant),
                    if (v == value) ...[
                      const SizedBox(width: 4),
                      Text(tr(label), style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
