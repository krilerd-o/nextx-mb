import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/html_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_timeline.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_attachments.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../mail/mail_compose_screen.dart' show plainTextToHtml;
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
      return (icon: NxI.chatCircle, text: tr('คอมเม้นท์'), from: null, to: val(newV));
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
  }
  return (icon: NxI.info, text: action.replaceAll('_', ' '), from: val(oldV), to: val(newV));
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
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  Map<String, dynamic>? _replyTo;
  Map<String, dynamic>? _editing;
  List<Map<String, dynamic>> _pendingFiles = [];
  bool _sending = false;

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
    _composer.dispose();
    _composerFocus.dispose();
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

  // ── comments
  Future<void> _attach() async {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    final files = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.bytes != null) MultipartFile.fromBytes(f.bytes!, filename: f.name),
    ];
    if (files.isEmpty) return;
    setState(() => _sending = true);
    try {
      final up = await _api.uploadBoardAttachments(widget.boardId, files);
      if (mounted) setState(() => _pendingFiles = [..._pendingFiles, ...up]);
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty && _pendingFiles.isEmpty) return;
    setState(() => _sending = true);
    try {
      final html = plainTextToHtml(text);
      if (_editing != null) {
        await _api.updateItemComment(widget.boardId, widget.kind, widget.itemId, '${_editing!['id']}', html);
      } else {
        await _api.addItemComment(
          widget.boardId,
          widget.kind,
          widget.itemId,
          html,
          parentId: _replyTo == null ? null : '${_replyTo!['parent_id'] ?? _replyTo!['id']}',
          attachments: _pendingFiles,
        );
      }
      HapticFeedback.lightImpact();
      _composer.clear();
      setState(() {
        _replyTo = null;
        _editing = null;
        _pendingFiles = [];
      });
      await Future.wait([_loadComments(), _loadHistory()]);
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _like(Map<String, dynamic> c) async {
    HapticFeedback.selectionClick();
    final i = _comments!.indexOf(c);
    final liked = c['liked_by_me'] == true;
    final count = wsInt(c['like_count']) ?? 0;
    setState(() => _comments![i] = {...c, 'liked_by_me': !liked, 'like_count': count + (liked ? -1 : 1)});
    try {
      final r = await _api.toggleItemCommentLike(widget.boardId, widget.kind, widget.itemId, '${c['id']}');
      if (mounted && r.isNotEmpty) {
        setState(() => _comments![i] = {..._comments![i], 'liked_by_me': r['liked'] ?? !liked, 'like_count': r['like_count'] ?? count});
      }
    } catch (e) {
      if (mounted) setState(() => _comments![i] = c);
      _snack(formatApiError(e));
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> c) async {
    final ok = await _confirm('ลบคอมเม้นท์นี้?');
    if (!ok) return;
    try {
      await _api.deleteItemComment(widget.boardId, widget.kind, widget.itemId, '${c['id']}');
      await _loadComments();
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  void _startEdit(Map<String, dynamic> c) {
    setState(() {
      _editing = c;
      _replyTo = null;
      _composer.text = stripHtmlPreview('${c['body'] ?? ''}', maxLen: 100000);
    });
    _composerFocus.requestFocus();
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
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final (v, label, _, n) in tabs)
              ButtonSegment(value: v, label: Text(n == null || n == 0 ? tr(label) : '${tr(label)} $n', maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
          ],
          selected: {_tab == 1 && !_isTask ? 0 : _tab},
          onSelectionChanged: (s) {
            HapticFeedback.selectionClick();
            setState(() => _tab = s.first);
          },
        ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _comments;
    final roots = [for (final c in list ?? const <Map<String, dynamic>>[]) if (c['parent_id'] == null) c];
    final replies = <String, List<Map<String, dynamic>>>{};
    for (final c in list ?? const <Map<String, dynamic>>[]) {
      if (c['parent_id'] != null) (replies['${c['parent_id']}'] ??= []).add(c);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _composerBox(context),
        const SizedBox(height: 12),
        if (list == null) const NxSkeletonList(rows: 2),
        if (list != null && list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text(tr('ยังไม่มีคอมเม้นท์'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
          ),
        for (final c in roots) ...[
          _comment(context, c),
          for (final r in replies['${c['id']}'] ?? const <Map<String, dynamic>>[])
            Padding(padding: const EdgeInsets.only(left: 40), child: _comment(context, r)),
        ],
        // Replies whose parent is gone still show.
        for (final e in replies.entries)
          if (!roots.any((c) => '${c['id']}' == e.key))
            for (final r in e.value) _comment(context, r),
      ],
    );
  }

  Widget _composerBox(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final banner = _editing != null
        ? tr('กำลังแก้ไขคอมเม้นท์')
        : _replyTo != null
            ? tr('ตอบกลับ ${_replyTo!['user_name'] ?? ''}')
            : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (banner != null)
            Row(children: [
              Icon(_editing != null ? NxI.pencilSimple : NxI.reply, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(banner, style: theme.textTheme.labelMedium?.copyWith(color: cs.primary))),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('ยกเลิก'),
                icon: const Icon(NxI.x, size: 16),
                onPressed: () => setState(() {
                  if (_editing != null) _composer.clear();
                  _editing = null;
                  _replyTo = null;
                }),
              ),
            ]),
          // Files waiting to be sent: thumbnails / cards with remove (like the web).
          if (_pendingFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: NxAttachmentStrip(
                key: const ValueKey('ws-comment-pending'),
                items: _pendingFiles,
                thumb: 64,
                onRemove: (f) => setState(() => _pendingFiles = [..._pendingFiles]..remove(f)),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ws-comment-input'),
                  controller: _composer,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 5,
                  enabled: _live,
                  decoration: InputDecoration(hintText: tr('เขียนคอมเม้นท์…'), border: InputBorder.none, isDense: true),
                ),
              ),
              if (_editing == null)
                IconButton(tooltip: tr('แนบไฟล์'), onPressed: _sending || !_live ? null : _attach, icon: const Icon(NxI.paperclip, size: 20)),
              IconButton.filled(
                key: const ValueKey('ws-comment-send'),
                tooltip: tr('ส่ง'),
                onPressed: _sending || !_live ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(NxI.paperPlaneTilt, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comment(BuildContext context, Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mine = widget.meId != null && '${c['user_id']}' == widget.meId;
    final liked = c['liked_by_me'] == true;
    final likes = wsInt(c['like_count']) ?? 0;
    final name = '${c['user_name'] ?? widget.lookups.user(c['user_id'])}';
    final files = c['attachments'] is List ? (c['attachments'] as List).whereType<Map>().toList() : const <Map>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxAvatar(label: name, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(name, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  Text(wsDateTime(c['created_at']), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 2),
                if (nxCommentHasText('${c['body'] ?? ''}')) NxHtmlView(html: '${c['body'] ?? ''}', style: theme.textTheme.bodyMedium),
                if (files.isNotEmpty || nxInlineImages('${c['body'] ?? ''}').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: NxAttachmentStrip(
                      key: ValueKey('ws-comment-files-${c['id']}'),
                      items: [for (final f in files) Map<String, dynamic>.from(f), ...nxInlineImages('${c['body'] ?? ''}')],
                      thumb: 96,
                    ),
                  ),
                Row(children: [
                  _miniAction(
                    key: ValueKey('ws-like-${c['id']}'),
                    icon: NxI.heart,
                    label: likes > 0 ? '$likes' : tr('ถูกใจ'),
                    color: liked ? const Color(0xFFE11D48) : null,
                    onTap: _live ? () => _like(c) : null,
                  ),
                  _miniAction(
                    icon: NxI.reply,
                    label: tr('ตอบกลับ'),
                    onTap: _live
                        ? () {
                            setState(() {
                              _replyTo = c;
                              _editing = null;
                            });
                            _composerFocus.requestFocus();
                          }
                        : null,
                  ),
                  if (mine) ...[
                    _miniAction(icon: NxI.pencilSimple, label: tr('แก้ไข'), onTap: () => _startEdit(c)),
                    _miniAction(icon: NxI.trash, label: tr('ลบ'), color: cs.error, onTap: () => _deleteComment(c)),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction({Key? key, required IconData icon, required String label, Color? color, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color ?? cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _worklogs(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final logs = _logs;
    if (logs == null) return const NxSkeletonList(rows: 2);
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
    if (h == null) return const NxSkeletonList(rows: 3);
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
