import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/entity_modules.dart';
import '../core/navigation/notification_deep_link.dart';
import '../services/api_client.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_cached_future.dart';
import '../widgets/nx_skeleton.dart';
import 'calendar/activity_detail_screen.dart';
import 'chat/chat_room_screen.dart';
import 'comm_ai/call_summary_screen.dart';
import 'comm_ai/comm_ai_history_screen.dart';
import 'crm/entity_detail_screen.dart';
import 'crm/entity_list_screen.dart';
import 'workspace/task_detail_screen.dart';
import 'workspace/workspace_board_screen.dart';
import '../core/i18n.dart';

class EntityListRoute extends StatelessWidget {
  const EntityListRoute({super.key, required this.module});
  final String module;

  @override
  Widget build(BuildContext context) {
    return EntityListScreen(module: EntityModules.normalize(module), title: EntityModules.titleOf(module));
  }
}

class EntityByIdLoader extends StatefulWidget {
  const EntityByIdLoader({super.key, required this.module, required this.id, this.tab});
  final String module;
  final String id;

  /// Tab to open (from a notification).
  final String? tab;

  @override
  State<EntityByIdLoader> createState() => _EntityByIdLoaderState();
}

class _EntityByIdLoaderState extends State<EntityByIdLoader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppConfig>().apiClient.getEntity(widget.module, widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        if (snap.hasError) {
          return _LoaderPage(child: Center(child: Text(tr(formatApiError(snap.error!)))));
        }
        final row = {...?snap.data, 'id': widget.id};
        return EntityDetailScreen(
          module: EntityModules.normalize(widget.module),
          row: row,
          initialTab: widget.tab,
        );
      },
    );
  }
}

class ActivityByIdLoader extends StatefulWidget {
  const ActivityByIdLoader({super.key, required this.id});
  final String id;

  @override
  State<ActivityByIdLoader> createState() => _ActivityByIdLoaderState();
}

class _ActivityByIdLoaderState extends State<ActivityByIdLoader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppConfig>().apiClient.getEntity('activity', widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        final row = {...?snap.data, 'id': widget.id};
        return ActivityDetailScreen(row: row);
      },
    );
  }
}

class BoardByIdLoader extends StatelessWidget {
  const BoardByIdLoader({super.key, required this.boardId});
  final String boardId;

  @override
  Widget build(BuildContext context) {
    final slug = parseWorkspaceItemSlug(boardId);
    if (slug != null) {
      return WorkspaceItemBySlugLoader(slug: slug.value);
    }
    if (boardId.isNotEmpty && int.tryParse(boardId) == null) {
      return BoardByCodeLoader(code: boardId);
    }
    return WorkspaceBoardScreen(board: {'id': boardId, 'name': 'บอร์ด'});
  }
}

class BoardByCodeLoader extends StatefulWidget {
  const BoardByCodeLoader({super.key, required this.code});
  final String code;

  @override
  State<BoardByCodeLoader> createState() => _BoardByCodeLoaderState();
}

class _BoardByCodeLoaderState extends State<BoardByCodeLoader> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<Map<String, dynamic>?> _resolve() async {
    final want = widget.code.trim().toUpperCase();
    final boards = await context.read<AppConfig>().apiClient.getBoards(q: want);
    for (final b in boards) {
      if ((b['code']?.toString() ?? '').trim().toUpperCase() == want) return b;
    }
    for (final b in boards) {
      if ((b['code']?.toString() ?? '').trim().toUpperCase().contains(want)) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        if (snap.hasError) {
          return _LoaderPage(child: NxErrorRetry(error: snap.error!, onRetry: () => setState(() => _future = _resolve())));
        }
        final board = snap.data;
        if (board == null) {
          return _LoaderPage(
            child: Center(child: Text(tr('ไม่พบบอร์ด ${widget.code}'))),
          );
        }
        return WorkspaceBoardScreen(board: board);
      },
    );
  }
}

class WorkspaceItemBySlugLoader extends StatefulWidget {
  const WorkspaceItemBySlugLoader({super.key, required this.slug});
  final String slug;

  @override
  State<WorkspaceItemBySlugLoader> createState() => _WorkspaceItemBySlugLoaderState();
}

class _WorkspaceItemBySlugLoaderState extends State<WorkspaceItemBySlugLoader> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<Map<String, dynamic>?> _resolve() async {
    final parsed = parseWorkspaceItemSlug(widget.slug);
    final api = context.read<AppConfig>().apiClient;
    final items = await api.getWorkspaceItems(q: widget.slug, limit: 8);
    Map<String, dynamic>? pick(List<Map<String, dynamic>> rows) {
      if (parsed == null) return rows.isEmpty ? null : rows.first;
      for (final row in rows) {
        final code = (row['board_code'] ?? row['code'] ?? '').toString().trim().toUpperCase();
        final no = int.tryParse(row['item_no']?.toString() ?? '');
        if (code == parsed.boardCode && no == parsed.itemNo) return row;
      }
      return rows.isEmpty ? null : rows.first;
    }

    var hit = pick(items);
    if (hit == null && parsed != null) {
      final boards = await api.getBoards(q: parsed.boardCode);
      Map<String, dynamic>? board;
      for (final b in boards) {
        if ((b['code']?.toString() ?? '').trim().toUpperCase() == parsed.boardCode) {
          board = b;
          break;
        }
      }
      final boardId = board?['id']?.toString();
      if (boardId != null && boardId.isNotEmpty) {
        final scoped = await api.getWorkspaceItems(boardIds: boardId, q: widget.slug, limit: 20);
        hit = pick(scoped);
        if (hit == null) {
          final all = await api.getWorkspaceItems(boardIds: boardId, limit: 200);
          hit = pick(all);
        }
      }
    }
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        if (snap.hasError) {
          return _LoaderPage(
            child: NxErrorRetry(
              error: snap.error!,
              onRetry: () => setState(() => _future = _resolve()),
            ),
          );
        }
        final row = snap.data;
        if (row == null) {
          return _LoaderPage(
            child: Center(child: Text(tr('ไม่พบงาน ${widget.slug}'))),
          );
        }
        return TaskDetailScreen(task: row);
      },
    );
  }
}

class TaskByIdLoader extends StatelessWidget {
  const TaskByIdLoader({super.key, required this.boardId, required this.taskId});
  final String boardId;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    if (boardId == 'boards' && int.tryParse(taskId) != null) {
      return BoardByIdLoader(boardId: taskId);
    }
    final nested = parseWorkspaceItemSlug(taskId);
    if (nested != null) {
      return WorkspaceItemBySlugLoader(slug: nested.value);
    }
    final asItem = parseWorkspaceItemSlug(boardId);
    if (asItem != null) {
      return WorkspaceItemBySlugLoader(slug: asItem.value);
    }
    return _TaskRecordLoader(boardId: boardId, taskId: taskId);
  }
}

/// Fetches the full task row so deep links show title/description, not an empty shell.
class _TaskRecordLoader extends StatefulWidget {
  const _TaskRecordLoader({required this.boardId, required this.taskId});
  final String boardId;
  final String taskId;

  @override
  State<_TaskRecordLoader> createState() => _TaskRecordLoaderState();
}

class _TaskRecordLoaderState extends State<_TaskRecordLoader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<Map<String, dynamic>> _resolve() async {
    final fallback = <String, dynamic>{'id': widget.taskId, 'board_id': widget.boardId};
    try {
      final rows = await context
          .read<AppConfig>()
          .apiClient
          .getWorkspaceItems(boardIds: widget.boardId, limit: 200);
      for (final row in rows) {
        if (row['id']?.toString() == widget.taskId) {
          return {...row, 'board_id': row['board_id'] ?? widget.boardId};
        }
      }
    } catch (_) {
      // Fall back to the minimal row; TaskDetailScreen still loads worklogs by id.
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        return TaskDetailScreen(
          task: snap.data ?? {'id': widget.taskId, 'board_id': widget.boardId},
        );
      },
    );
  }
}

class ChatByIdLoader extends StatefulWidget {
  const ChatByIdLoader({super.key, required this.roomId});
  final String roomId;

  @override
  State<ChatByIdLoader> createState() => _ChatByIdLoaderState();
}

class _ChatByIdLoaderState extends State<ChatByIdLoader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<Map<String, dynamic>> _resolve() async {
    final fallback = <String, dynamic>{'id': widget.roomId, 'name': 'แชท'};
    try {
      final rooms = await context.read<AppConfig>().apiClient.getChatRooms();
      for (final room in rooms) {
        if (room['id']?.toString() == widget.roomId) return room;
      }
    } catch (_) {
      // Open the room anyway; messages are fetched by id.
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoaderPage(child: NxSkeletonDetail());
        }
        return ChatRoomScreen(room: snap.data ?? {'id': widget.roomId, 'name': 'แชท'});
      },
    );
  }
}

class JobByIdLoader extends StatelessWidget {
  const JobByIdLoader({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return EntityDetailScreen(module: 'job', row: {'id': id});
  }
}

/// Loading / error page for a link: always has a header, so there is a way
/// back (or home when the link opened the app).
class _LoaderPage extends StatelessWidget {
  const _LoaderPage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(64),
          child: SafeArea(bottom: false, child: NxAppHeader(title: '')),
        ),
        body: child,
      );
}


/// Detail screen for an in-app route, to show in a split view's right pane.
/// null = not a record route (open it the normal way).
Widget? nxPaneForRoute(String route) {
  final uri = Uri.tryParse(route);
  if (uri == null) return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length == 3 && (seg[0] == 'crm' || seg[0] == 'fsm')) {
    return EntityByIdLoader(module: seg[1], id: seg[2], tab: uri.queryParameters['tab']);
  }
  if (seg.length == 2 && seg[0] == 'calendar') return ActivityByIdLoader(id: seg[1]);
  if (seg.length == 3 && seg[0] == 'comm-ai' && seg[1] == 'calls') return CallSummaryScreen(callId: seg[2]);
  if (seg.length == 3 && seg[0] == 'comm-ai' && seg[1] == 'summaries') return ChatSummaryDetailScreen(id: seg[2]);
  return null;
}
