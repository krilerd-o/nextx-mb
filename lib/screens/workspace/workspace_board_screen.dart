import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/realtime_service.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_create_fab.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import 'task_detail_screen.dart';
import 'workspace_kanban_board.dart';
import '../../widgets/nx_icons.dart';

class WorkspaceBoardScreen extends StatefulWidget {
  const WorkspaceBoardScreen({super.key, required this.board});
  final Map<String, dynamic> board;

  @override
  State<WorkspaceBoardScreen> createState() => _WorkspaceBoardScreenState();
}

class _WorkspaceBoardScreenState extends State<WorkspaceBoardScreen> {
  List<Map<String, dynamic>> _statuses = [];
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Object? _error;
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;
  String? _businessId;

  String get _boardId => widget.board['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    // Someone else edits the board on the web → reload (debounced for bursts).
    _businessId = context.read<AppConfig>().session.businessId;
    if (_boardId.isNotEmpty) RealtimeService.instance.joinWorkspaceBoard(_boardId, businessId: _businessId);
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

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    if (int.tryParse(_boardId) == null) {
      if (!mounted) return;
      setState(() {
        _error = 'ไม่พบบอร์ดนี้';
        _loading = false;
      });
      return;
    }
    try {
      final api = context.read<AppConfig>().apiClient;
      final statuses = await api.getBoardStatuses(_boardId);
      final items = (await api.getWorkspaceItems(boardIds: _boardId)).where((e) {
        final t = (e['item_type'] ?? e['type'] ?? 'task').toString().toLowerCase();
        return t == 'task' || t == 'subtask' || t == 'bug' || t == 'story';
      }).toList();
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _statusName(Map<String, dynamic> row) {
    final id = row['status_id']?.toString();
    for (final s in _statuses) {
      if (s['id']?.toString() == id) {
        return s['label_th']?.toString() ?? s['name']?.toString() ?? 'อื่นๆ';
      }
    }
    return row['status_name']?.toString() ?? row['status']?.toString() ?? 'อื่นๆ';
  }

  Map<String, List<Map<String, dynamic>>> _group() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in _statuses) {
      final name = s['label_th']?.toString() ?? s['name']?.toString() ?? '';
      if (name.isNotEmpty) map.putIfAbsent(name, () => []);
    }
    for (final row in _items) {
      final key = _statusName(row);
      map.putIfAbsent(key, () => []).add({
        ...row,
        'status': key,
        'title': row['title'] ?? row['name'],
        'board_id': _boardId,
      });
    }
    return map;
  }

  Future<void> _setStatus(BuildContext context, Map<String, dynamic> row, String newStatus) async {
    int? statusId;
    for (final s in _statuses) {
      final name = s['label_th']?.toString() ?? s['name']?.toString();
      if (name == newStatus) {
        statusId = int.tryParse(s['id']?.toString() ?? '');
        break;
      }
    }
    final taskId = row['id']?.toString();
    if (statusId == null || taskId == null) return;
    try {
      await context.read<AppConfig>().apiClient.putBoardTask(_boardId, taskId, {
        'status_id': statusId,
      });
      await _load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _createTask() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('งานใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'ชื่อเรื่อง')),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'รายละเอียด (ไม่บังคับ)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('สร้าง')),
        ],
      ),
    );
    final text = title.text.trim();
    final desc = description.text.trim();
    title.dispose();
    description.dispose();
    if (ok == true && text.isNotEmpty) {
      try {
        await context.read<AppConfig>().apiClient.postBoardTask(
              _boardId,
              title: text,
              description: desc.isEmpty ? null : desc,
            );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.board['name']?.toString() ?? 'บอร์ด';
    final twoPane = NxBreakpoint.of(context).twoPane;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: name,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: _load,
          ),
          if (twoPane) NxAddButton(onPressed: _createTask),
        ],
      ),
      floatingActionButton: NxCreateFab(onPressed: _createTask),
      body: _loading
          ? const NxSkeletonList()
          : _error != null
              ? Center(child: Text(formatApiError(_error!)))
              : WorkspaceKanbanBoard(
                  grouped: _group(),
                  onTaskTap: (row) {
                    nxPush<void>(context, TaskDetailScreen(task: row)).then((_) => _load());
                  },
                  onChangeStatus: _setStatus,
                ),
    );
  }
}
