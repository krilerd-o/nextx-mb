import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/history_events.dart';
import '../../core/html_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_scroll_tabs.dart';
import '../../widgets/nx_timeline.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/comments/nx_comment_composer.dart';
import '../../widgets/comments/nx_comment_thread.dart';
import '../../widgets/comments/nx_comments_controller.dart';
import 'ws_detail_parts.dart';

/// Lookups the history uses to turn ids into names.
class WsLookups {
  const WsLookups({this.users = const {}, this.statuses = const [], this.items = const {}});

  /// user id → name
  final Map<String, String> users;
  final List<WsStatus> statuses;

  /// `task:12` / `epic:3` → row (for epic / parent / blocked-by names)
  final Map<String, Map<String, dynamic>> items;

  String user(dynamic id) {
    final k = '${id ?? ''}';
    if (k.isEmpty || k == 'null') return tr('ไม่มี');
    return users[k] ?? '#$k';
  }

  String status(dynamic id) {
    final k = '${id ?? ''}';
    return statuses.where((s) => s.id == k).firstOrNull?.label ?? (k.isEmpty ? '—' : '#$k');
  }

  String item(String kind, dynamic id) {
    final k = '${id ?? ''}';
    if (k.isEmpty || k == 'null') return tr('ไม่มี');
    final r = items['$kind:$k'];
    return r == null ? '#$k' : '${wsKey(r)} ${wsTitle(r)}';
  }
}

/// Readable sentence for one activity row (same events as the web history).
({IconData icon, String text, String? from, String? to}) wsDescribeActivity(Map<String, dynamic> a, WsLookups l) {
  final action = '${a['action'] ?? ''}';
  final field = '${a['target_type'] ?? ''}';
  final oldV = a['old_value'];
  final newV = a['new_value'];
  String? val(dynamic v) {
    if (v == null || '$v'.isEmpty || '$v' == 'null') return null;
    switch (field) {
      case 'status_id':
        return l.status(v);
      case 'assignee_id' || 'reporter_id':
        return l.user(v);
      case 'epic_id':
        return l.item('epic', v);
      case 'parent_id' || 'blocked_by_id':
        return l.item('task', v);
      case 'priority':
        return tr(wsPriorityStyle('$v').label);
      case 'type':
        return tr(wsTypeStyle('$v').label);
      case 'original_estimate_minutes' || 'time_remaining_minutes' || 'time_spent_minutes':
        return formatMinutes(int.tryParse('$v'));
      case 'start_date' || 'end_date' || 'due_date':
        return wsShortDate(v).isEmpty ? '$v' : '${wsShortDate(v)} ${uiYear(parseThai(v)!.year)}';
      case 'description':
        return null;
    }
    final s = looksLikeHtmlString('$v') ? stripHtmlPreview('$v', maxLen: 100000) : '$v';
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  switch (action) {
    case 'status_change':
      return (icon: NxI.arrowRight, text: tr('เปลี่ยนสถานะ'), from: l.status(oldV), to: l.status(newV));
    case 'assignee_change':
      return (icon: NxI.user, text: tr('เปลี่ยนผู้รับผิดชอบ'), from: l.user(oldV), to: l.user(newV));
    case 'comment':
      return (icon: NxI.chatCircle, text: historyText('เพิ่มคอมเมนต์'), from: null, to: val(newV));
    case 'worklog':
      return (icon: NxI.clock, text: tr('ลงเวลา ${newV ?? ''}').trim(), from: null, to: null);
    case 'worklog_update':
      return (icon: NxI.clock, text: tr('แก้ไขการลงเวลา'), from: oldV == null ? null : '$oldV', to: newV == null ? null : '$newV');
    case 'worklog_delete':
      return (icon: NxI.trash, text: tr('ลบการลงเวลา ${oldV ?? ''}').trim(), from: null, to: null);
    case 'create' || 'created':
      return (icon: NxI.plus, text: tr('สร้างรายการ'), from: null, to: null);
    case 'field_change':
      if (field == 'description') return (icon: NxI.pencilSimple, text: tr('แก้ไขคำอธิบาย'), from: null, to: null);
      return (icon: NxI.pencilSimple, text: tr('แก้ไข ${wsFieldLabel(field)}'), from: val(oldV) ?? tr('ว่าง'), to: val(newV) ?? tr('ว่าง'));
    // Jira import: summary / description edits.
    case 'edit':
      return (icon: NxI.pencilSimple, text: tr('แก้ไข ${wsFieldLabel(field)}'), from: null, to: null);
    case 'delete' || 'deleted':
      return (icon: NxI.trash, text: tr('ลบรายการ'), from: null, to: null);
    // workspaceSoftDelete: new_value = the item's title.
    case 'trash_delete':
      return (icon: NxI.trash, text: historyText('ย้ายไปถังขยะ'), from: null, to: val(newV));
    case 'trash_restore':
      return (icon: NxI.arrowCounterClockwise, text: historyText('กู้คืนจากถังขยะ'), from: null, to: val(newV));
  }
  // Unknown action: a readable title, never the raw key.
  final t = historyActionTitle(action);
  if (!t.known && kDebugMode) debugPrint('[history] unknown workspace action "$action"');
  return (icon: t.kind == HistoryKind.other ? NxI.info : kHistoryKindStyle[t.kind]!.$1, text: t.title, from: val(oldV), to: val(newV));
}

/// Activity area under the task: comments / time logs / change history.
class WsActivityPanel extends StatefulWidget {
  const WsActivityPanel({
    super.key,
    required this.boardId,
    required this.kind,
    required this.itemId,
    required this.lookups,
    this.meId,
    this.onWorklogChanged,
    this.initialTab = 0,
  });

  final String boardId;
  final String kind;
  final String itemId;
  final WsLookups lookups;
  final String? meId;

  /// After a worklog is added / edited / deleted (the item's time changes).
  final VoidCallback? onWorklogChanged;
  final int initialTab;

  @override
  State<WsActivityPanel> createState() => WsActivityPanelState();
}

class WsActivityPanelState extends State<WsActivityPanel> {
  late int _tab = widget.initialTab;
  List<Map<String, dynamic>>? _comments;
  List<Map<String, dynamic>>? _logs;
  List<Map<String, dynamic>>? _history;

  /// Comments: same composer / thread as record comments, with likes (the web's workspace thread).
  late final NxCommentsController _comments$ = NxCommentsController(
    api: NxCommentsApi.workspace(_api, widget.boardId, widget.kind, widget.itemId),
    onChanged: () => Future.wait([_loadComments(), _loadHistory()]),
    meId: widget.meId,
    keyPrefix: 'ws-',
  );

  ApiClient get _api => context.read<AppConfig>().apiClient;
  bool get _isTask => widget.kind != 'epic';
  bool get _live => context.read<AppConfig>().isLoggedIn && widget.boardId.isNotEmpty && widget.itemId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _comments$.dispose();
    super.dispose();
  }

  /// Reloads everything (also called by the screen on realtime events).
  Future<void> reload() async {
    if (!_live) {
      setState(() {
        _comments = const [];
        _logs = const [];
        _history = const [];
      });
      return;
    }
    await Future.wait([_loadComments(), if (_isTask) loadWorklogs(), _loadHistory()]);
  }

  Future<void> _loadComments() async {
    try {
      final l = await _api.getItemComments(widget.boardId, widget.kind, widget.itemId);
      if (mounted) setState(() => _comments = l);
    } catch (_) {
      if (mounted) setState(() => _comments ??= const []);
    }
  }

  Future<void> loadWorklogs() async {
    try {
      final l = await _api.getTaskWorklogs(widget.boardId, widget.itemId);
      if (mounted) setState(() => _logs = l);
    } catch (_) {
      if (mounted) setState(() => _logs ??= const []);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final l = await _api.getItemActivity(widget.boardId, widget.kind, widget.itemId);
      if (mounted) setState(() => _history = l);
    } catch (_) {
      if (mounted) setState(() => _history ??= const []);
    }
  }

  void showTab(int i) => setState(() => _tab = i);

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(t))));
  }

  Future<bool> _confirm(String q) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(q)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
          ],
        ),
      ) ==
      true;

  // ── worklogs
  Future<void> _editLog(Map<String, dynamic> log) async {
    final r = await showWsLogTimeSheet(
      context,
      edit: true,
      minutes: wsInt(log['time_spent_minutes']),
      description: stripHtmlPreview('${log['work_description'] ?? ''}', maxLen: 100000),
      remaining: wsInt(log['time_remaining_minutes']),
      startedAt: '${log['started_at'] ?? log['created_at'] ?? ''}',
    );
    if (r == null) return;
    try {
      await _api.updateWorklog(widget.boardId, widget.itemId, '${log['id']}',
          minutes: r.minutes, description: r.description, remainingMinutes: r.remaining, startedAt: r.startedAt);
      await Future.wait([loadWorklogs(), _loadHistory()]);
      widget.onWorklogChanged?.call();
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    if (!await _confirm('ลบการลงเวลานี้?')) return;
    try {
      await _api.deleteWorklog(widget.boardId, widget.itemId, '${log['id']}');
      await Future.wait([loadWorklogs(), _loadHistory()]);
      widget.onWorklogChanged?.call();
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (0, 'คอมเม้นท์', NxI.chatCircle, _comments?.length),
      if (_isTask) (1, 'ลงเวลา', NxI.clock, _logs?.length),
      (2, 'ประวัติ', NxI.clockCounterClockwise, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(builder: (context) {
          final cur = _tab == 1 && !_isTask ? 0 : _tab;
          final idx = tabs.indexWhere((t) => t.$1 == cur);
          return NxScrollTabs(
            keyPrefix: 'ws-activity-tab-',
            labels: [for (final (_, label, _, n) in tabs) n == null || n == 0 ? label : '$label $n'],
            index: idx < 0 ? 0 : idx,
            onChanged: (i) => setState(() => _tab = tabs[i].$1),
          );
        }),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              1 when _isTask => _worklogs(context),
              2 => _historyList(context),
              _ => _commentsList(context),
            },
          ),
        ),
      ],
    );
  }

  Widget _commentsList(BuildContext context) {
    final list = _comments;
    if (list == null) return const NxSkeletonComments(rows: 2);
    // Composer first (the web's workspace thread), then the threads.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxCommentComposer(controller: _comments$, enabled: _live),
        const SizedBox(height: 14),
        NxCommentThreadView(
          comments: list,
          controller: _comments$,
          nameOf: widget.lookups.user,
          emptyHint: 'เขียนจากช่องด้านบน — พิมพ์ @ เพื่อกล่าวถึง แนบรูป ไฟล์ หรือลิงก์ได้',
        ),
      ],
    );
  }

  Widget _worklogs(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final logs = _logs;
    if (logs == null) return const NxSkeletonTimeline(rows: 3);
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text(tr('ยังไม่มีการลงเวลา'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
      );
    }
    // Totals per person, then a day-by-day timeline (newest first).
    final perUser = <String, int>{};
    for (final l in logs) {
      perUser.update('${l['user_id']}', (v) => v + (wsInt(l['time_spent_minutes']) ?? 0), ifAbsent: () => wsInt(l['time_spent_minutes']) ?? 0);
    }
    DateTime? when(Map<String, dynamic> l) => parseThai(l['started_at']) ?? parseThai(l['created_at']);
    final sorted = [...logs]..sort((a, b) => (when(b) ?? DateTime(0)).compareTo(when(a) ?? DateTime(0)));
    final days = <String, List<Map<String, dynamic>>>{};
    for (final l in sorted) {
      final d = when(l);
      (days[d == null ? '' : '${d.day}/${d.month}/${uiYear(d.year)}'] ??= []).add(l);
    }
    final total = perUser.values.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(avatar: const Icon(NxI.timer, size: 16), label: Text(tr('รวม ${formatMinutes(total)}'))),
            for (final e in perUser.entries)
              Chip(
                avatar: NxAvatar(label: widget.lookups.user(e.key), size: 20),
                label: Text('${widget.lookups.user(e.key)} · ${formatMinutes(e.value)}'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final d in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(d.key, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ),
          for (final l in d.value)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(formatMinutes(wsInt(l['time_spent_minutes'])), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${widget.lookups.user(l['user_id'])} · ${wsDateTime(l['started_at'] ?? l['created_at']).split(' ').last}',
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        if ('${l['work_description'] ?? ''}'.trim().isNotEmpty)
                          NxHtmlView(html: '${l['work_description']}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (l['can_manage'] == true) ...[
                    IconButton(
                      key: ValueKey('ws-log-edit-${l['id']}'),
                      tooltip: tr('แก้ไข'),
                      icon: const Icon(NxI.pencilSimple, size: 16),
                      onPressed: () => _editLog(l),
                    ),
                    IconButton(
                      tooltip: tr('ลบ'),
                      icon: Icon(NxI.trash, size: 16, color: cs.error),
                      onPressed: () => _deleteLog(l),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _historyList(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = _history;
    if (h == null) return const NxSkeletonTimeline(rows: 3);
    if (h.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text(tr('ยังไม่มีประวัติ'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
      );
    }
    return NxTimeline(entries: [
      for (final a in h)
        () {
          final d = wsDescribeActivity(a, widget.lookups);
          final who = '${a['user_name'] ?? widget.lookups.user(a['user_id'])}';
          return NxTimelineEntry(
            at: parseThai(a['created_at']),
            icon: d.icon,
            title: Text.rich(TextSpan(children: [
              TextSpan(text: '$who ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: d.text, style: const TextStyle(fontWeight: FontWeight.w500)),
            ])),
            body: d.from == null && d.to == null
                ? null
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (d.from != null) _valuePill(context, d.from!, old: true),
                      if (d.from != null && d.to != null) Icon(NxI.arrowRight, size: 14, color: cs.onSurfaceVariant),
                      if (d.to != null) _valuePill(context, d.to!),
                    ],
                  ),
            who: who,
          );
        }(),
    ]);
  }

  Widget _valuePill(BuildContext context, String text, {bool old = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: old ? cs.surfaceContainerHighest : cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: old ? cs.onSurfaceVariant : cs.primary,
          decoration: old ? TextDecoration.lineThrough : null,
          fontWeight: old ? null : FontWeight.w700,
        ),
      ),
    );
  }
}
