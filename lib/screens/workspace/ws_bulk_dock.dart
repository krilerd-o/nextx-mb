import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'ws_bulk_change.dart';

/// Floating bulk-edit dock for Workspace items (Task list in an Epic, Subtasks in a Task, the board).
///
/// A pill above the bottom edge in the opposite colour of the theme (dark on light, light on dark).
/// Each tool opens a picker and applies at once; a snackbar offers "เลิกทำ" (undo restores the previous
/// values; delete is undone from the trash).
class WsBulkDock extends StatefulWidget {
  const WsBulkDock({
    super.key,
    required this.items,
    required this.api,
    required this.boardId,
    required this.onClear,
    required this.onChanged,
    this.boardCode,
    this.totalCount = 0,
    this.onSelectAll,
    this.statuses = const [],
    this.users = const {},
    this.epics = const [],
    this.parentOptions = const [],
  });

  /// Selected rows (full maps with id, type, status_id, labels …).
  final List<Map<String, dynamic>> items;
  final ApiClient api;
  final String boardId;
  final String? boardCode;
  final int totalCount;
  final VoidCallback? onSelectAll;
  final VoidCallback onClear;
  final Future<void> Function() onChanged;
  final List<WsStatus> statuses;
  final Map<String, String> users;
  final List<Map<String, dynamic>> epics;

  /// Tasks a Subtask may move under.
  final List<Map<String, dynamic>> parentOptions;

  @override
  State<WsBulkDock> createState() => _WsBulkDockState();
}

bool wsIsEpic(Map<String, dynamic> r) => wsType(r) == 'epic';
bool wsIsSubtask(Map<String, dynamic> r) {
  final t = wsType(r);
  return t == 'subtask' || t == 'checklist';
}

List<String> wsLabels(Map<String, dynamic> r) {
  final v = r['labels'];
  if (v is List) return [for (final x in v) '$x'];
  return const [];
}

/// Previous values kept for undo.
const _undoFields = ['status_id', 'assignee_id', 'priority', 'due_date', 'start_date', 'end_date', 'labels', 'epic_id', 'parent_id'];

class _WsBulkDockState extends State<WsBulkDock> {
  bool _busy = false;

  int get _count => widget.items.length;
  (String, String) _ref(Map<String, dynamic> r) => (wsIsEpic(r) ? 'epic' : 'task', '${r['id']}');

  /// Snackbar with an optional "เลิกทำ". Works after the dock is gone (e.g. after a delete clears the
  /// selection): the messenger, padding and reload callback are captured up front.
  void _snack(String text, {Future<void> Function()? undo}) {
    if (!mounted) return;
    _showSnack(ScaffoldMessenger.maybeOf(context), MediaQuery.paddingOf(context).bottom, widget.onChanged, text, undo: undo);
  }

  static void _showSnack(
    ScaffoldMessengerState? m,
    double bottomInset,
    Future<void> Function() reload,
    String text, {
    Future<void> Function()? undo,
  }) {
    if (m == null || !m.mounted) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      // Float above the dock so "เลิกทำ" stays tappable.
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 84),
      action: undo == null
          ? null
          : SnackBarAction(
              label: tr('เลิกทำ'),
              onPressed: () async {
                try {
                  await undo();
                  await reload();
                  _showSnack(m, bottomInset, reload, tr('เลิกทำแล้ว'));
                } catch (e) {
                  _showSnack(m, bottomInset, reload, formatApiError(e));
                }
              },
            ),
    ));
  }

  Future<void> _apply(Map<String, dynamic> updates, String label) async {
    final targets = widget.items.where((r) {
      if (updates.containsKey('epic_id') && wsIsEpic(r)) return false;
      if (updates.containsKey('parent_id') && !wsIsSubtask(r)) return false;
      return true;
    }).toList();
    if (targets.isEmpty) {
      _snack(tr('ไม่มีรายการที่ใช้กับคำสั่งนี้ได้'));
      return;
    }
    final before = [
      for (final r in targets) (_ref(r), {for (final f in _undoFields) f: f == 'labels' ? wsLabels(r) : r[f]}),
    ];
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final inset = MediaQuery.paddingOf(context).bottom;
    final api = widget.api;
    final boardId = widget.boardId;
    final reload = widget.onChanged;
    try {
      await api.bulkUpdateWorkspaceItems(boardId, [for (final r in targets) _ref(r)], updates);
      HapticFeedback.mediumImpact();
      await reload();
      final touched = <String>{
        for (final k in updates.keys)
          switch (k) {
            'due_shift_days' => 'due_date',
            'labels_add' || 'labels_remove' => 'labels',
            _ => k,
          },
        if (updates.containsKey('parent_id')) 'epic_id',
      };
      _showSnack(messenger, inset, reload, tr('$label · ${targets.length} รายการ'), undo: () async {
        for (final (ref, prev) in before) {
          final back = <String, dynamic>{};
          for (final f in touched) {
            if (!prev.containsKey(f)) continue;
            final v = prev[f];
            if (f == 'status_id' && v == null) continue;
            if (f.endsWith('_date')) {
              back[f] = v == null ? '' : '$v'.substring(0, '$v'.length >= 10 ? 10 : '$v'.length);
            } else {
              back[f] = v ?? (f == 'labels' ? <String>[] : 'none');
            }
          }
          if (back.isNotEmpty) await api.bulkUpdateWorkspaceItems(boardId, [ref], back);
        }
      });
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _sheet<T>(String title, Widget Function(BuildContext sheet) body) =>
      showAppBottomSheet<T>(context: context, title: title, child: Builder(builder: body));

  Future<void> _status() async {
    final id = await _sheet<String>(tr('เปลี่ยนสถานะ'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in widget.statuses)
            ListTile(
              key: ValueKey('bulk-status-${s.id}'),
              leading: CircleAvatar(radius: 6, backgroundColor: s.color),
              title: Text(s.label),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
        ]));
    if (id == null || !mounted) return;
    final s = widget.statuses.firstWhere((x) => x.id == id);
    final now = {for (final r in widget.items) '${r['status_id'] ?? ''}'};
    final from = now.length == 1 ? widget.statuses.where((x) => x.id == now.first).firstOrNull : null;
    final ok = await showStatusChangeConfirm(
      context,
      recordTitle: tr('${widget.items.length} รายการ'),
      from: from?.label ?? 'หลายสถานะ',
      fromColor: from?.color,
      to: s.label,
      toColor: s.color,
      impact: s.isDone ? 'นับเป็นงานเสร็จ และแจ้งผู้ที่ติดตามงานนี้' : (s.isCancelled ? 'งานนี้จะถูกปิดโดยไม่นับว่าเสร็จ' : null),
      destructive: s.isCancelled,
    );
    if (ok == null || !mounted) return;
    await _apply({'status_id': int.tryParse(id) ?? id}, '${tr('สถานะ')}: ${s.label}');
  }

  Future<void> _person({required bool reporter}) async {
    final field = reporter ? 'reporter_id' : 'assignee_id';
    final title = reporter ? tr('ผู้รายงาน') : tr('มอบหมายให้');
    final id = await _sheet<String>(title, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(NxI.x), title: Text(tr('ไม่ระบุ')), onTap: () => Navigator.pop(ctx, 'none')),
          for (final u in widget.users.entries)
            ListTile(
              key: ValueKey('bulk-user-${u.key}'),
              leading: CircleAvatar(radius: 14, child: Text(u.value.isEmpty ? '?' : u.value.characters.first)),
              title: Text(u.value),
              onTap: () => Navigator.pop(ctx, u.key),
            ),
        ]));
    if (id == null) return;
    await _apply({field: id == 'none' ? 'none' : (int.tryParse(id) ?? id)}, '$title: ${id == 'none' ? tr('ไม่ระบุ') : widget.users[id] ?? id}');
  }

  Future<void> _priority() async {
    final p = await _sheet<String>(tr('ความสำคัญ'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in kWsPriorities)
            ListTile(
              key: ValueKey('bulk-priority-$p'),
              leading: Icon(wsPriorityStyle(p).icon, color: wsPriorityStyle(p).color),
              title: Text(tr(wsPriorityStyle(p).label)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]));
    if (p == null) return;
    await _apply({'priority': p}, '${tr('ความสำคัญ')}: ${tr(wsPriorityStyle(p).label)}');
  }

  Future<void> _dates() async {
    final today = thaiNow();
    String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final pick = await _sheet<Object>(tr('กำหนดส่ง'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const ValueKey('bulk-date-today'), leading: const Icon(NxI.calendarCheck), title: Text(tr('วันนี้')), onTap: () => Navigator.pop(ctx, ymd(today))),
          ListTile(leading: const Icon(NxI.calendarBlank), title: Text(tr('พรุ่งนี้')), onTap: () => Navigator.pop(ctx, ymd(today.add(const Duration(days: 1))))),
          ListTile(leading: const Icon(NxI.calendarBlank), title: Text(tr('อีก 1 สัปดาห์')), onTap: () => Navigator.pop(ctx, ymd(today.add(const Duration(days: 7))))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(tr('เลื่อนจากวันเดิมของแต่ละรายการ'), style: Theme.of(ctx).textTheme.labelMedium),
          ),
          Wrap(spacing: 8, children: [
            for (final n in const [-1, 1, 3, 7])
              ActionChip(key: ValueKey('bulk-shift-$n'), label: Text('${n > 0 ? '+' : ''}$n ${tr('วัน')}'), onPressed: () => Navigator.pop(ctx, n)),
          ]),
          ListTile(
            leading: const Icon(NxI.calendarPlus),
            title: Text(tr('เลือกวันที่…')),
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: today, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null && ctx.mounted) Navigator.pop(ctx, ymd(d));
            },
          ),
          ListTile(leading: const Icon(NxI.x), title: Text(tr('ล้างกำหนดส่ง')), onTap: () => Navigator.pop(ctx, '')),
        ]));
    if (pick == null) return;
    if (pick is int) {
      await _apply({'due_shift_days': pick}, '${tr('กำหนดส่ง')} ${pick > 0 ? '+' : ''}$pick ${tr('วัน')}');
    } else {
      await _apply({'due_date': pick}, '${tr('กำหนดส่ง')}: ${pick == '' ? tr('ล้าง') : pick}');
    }
  }

  Future<void> _labels() async {
    final existing = <String>{for (final r in widget.items) ...wsLabels(r)}.toList();
    final ctrl = TextEditingController();
    final res = await _sheet<(String, String)>(tr('ป้ายกำกับ'), (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const ValueKey('bulk-label-input'),
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: tr('ชื่อป้าย แล้วกดเพิ่ม'), prefixIcon: const Icon(NxI.tag, size: 18)),
            onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(ctx, ('add', v.trim())),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('bulk-label-add'),
            onPressed: () => ctrl.text.trim().isEmpty ? null : Navigator.pop(ctx, ('add', ctrl.text.trim())),
            icon: const Icon(NxI.plus, size: 18),
            label: Text(tr('เพิ่มป้ายให้ทุกรายการ')),
          ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr('แตะเพื่อเอาป้ายออก'), style: Theme.of(ctx).textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in existing) InputChip(label: Text(l), onDeleted: () => Navigator.pop(ctx, ('remove', l)), onPressed: () => Navigator.pop(ctx, ('remove', l))),
            ]),
          ],
        ]));
    // The sheet is still animating closed (its TextField uses ctrl) — dispose afterwards.
    Future<void>.delayed(const Duration(milliseconds: 600), ctrl.dispose);
    if (res == null) return;
    final (mode, l) = res;
    await _apply({mode == 'add' ? 'labels_add' : 'labels_remove': [l]}, mode == 'add' ? tr('เพิ่มป้าย "$l"') : tr('เอาป้าย "$l" ออก'));
  }

  Future<void> _epic() async {
    final id = await _sheet<String>(tr('ย้ายเข้า Epic'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(NxI.x), title: Text(tr('ไม่อยู่ใน Epic')), onTap: () => Navigator.pop(ctx, 'none')),
          for (final e in widget.epics)
            ListTile(
              leading: const Icon(NxI.lightning, color: Color(0xFF8B5CF6)),
              title: Text(wsTitle(e), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(wsKey(e, boardCode: widget.boardCode)),
              onTap: () => Navigator.pop(ctx, '${e['id']}'),
            ),
        ]));
    if (id == null) return;
    await _apply({'epic_id': id == 'none' ? 'none' : (int.tryParse(id) ?? id)}, id == 'none' ? tr('เอาออกจาก Epic') : 'Epic');
  }

  Future<void> _parent() async {
    final selected = {for (final r in widget.items) '${r['id']}'};
    final opts = widget.parentOptions.where((t) => !selected.contains('${t['id']}')).toList();
    final id = await _sheet<String>(tr('ย้ายไปใต้ Task'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          for (final t in opts)
            ListTile(
              key: ValueKey('bulk-parent-${t['id']}'),
              leading: const Icon(NxI.gitBranch, color: Color(0xFF0EA5E9)),
              title: Text(wsTitle(t), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(wsKey(t, boardCode: widget.boardCode)),
              onTap: () => Navigator.pop(ctx, '${t['id']}'),
            ),
        ]));
    if (id == null) return;
    await _apply({'parent_id': int.tryParse(id) ?? id}, tr('ย้ายไปใต้งานอื่น'));
  }

  Future<void> _duplicate() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final inset = MediaQuery.paddingOf(context).bottom;
    final api = widget.api;
    final boardId = widget.boardId;
    final reload = widget.onChanged;
    try {
      final created = await api.bulkDuplicateWorkspaceItems(boardId, [for (final r in widget.items) _ref(r)]);
      HapticFeedback.mediumImpact();
      await reload();
      _showSnack(messenger, inset, reload, tr('ทำซ้ำ ${created.length} รายการ'), undo: created.isEmpty
          ? null
          : () => api.bulkDeleteWorkspaceItems(boardId, [for (final r in created) ('task', '${r['id']}')]));
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบ $_count รายการ?')),
        content: Text(tr('รายการจะย้ายไปถังขยะ กู้คืนได้ หรือกดเลิกทำ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('bulk-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = _count;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final inset = MediaQuery.paddingOf(context).bottom;
      final api = widget.api;
      final reload = widget.onChanged;
      final trash = await api.bulkDeleteWorkspaceItems(widget.boardId, [for (final r in widget.items) _ref(r)]);
      HapticFeedback.mediumImpact();
      widget.onClear();
      await reload();
      _showSnack(messenger, inset, reload, tr('ย้ายลงถังขยะ $n รายการ'),
          undo: trash.isEmpty ? null : () => api.restoreWorkspaceTrashBulk(trash));
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final text = [for (final r in widget.items) '${wsLinkKey(r, boardCode: widget.boardCode)}  ${wsTitle(r)}'].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _snack(tr('คัดลอก $_count รายการแล้ว'));
  }

  Future<void> _more() async {
    final what = await _sheet<String>(tr('เพิ่มเติม'), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('bulk-change-open'),
            leading: const Icon(NxI.stack),
            title: Text(tr('Bulk Change (ย้ายบอร์ด / ทำซ้ำพร้อมงานย่อย / ติดตาม)')),
            subtitle: Text(tr('ดูตัวอย่างก่อนทำ และเลิกทำทั้งชุดได้')),
            onTap: () => Navigator.pop(ctx, 'bulk'),
          ),
          ListTile(leading: const Icon(NxI.clipboard), title: Text(tr('คัดลอกรหัสและชื่อ')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(NxI.user), title: Text(tr('ผู้รายงาน')), onTap: () => Navigator.pop(ctx, 'reporter')),
          if (widget.onSelectAll != null && widget.totalCount > _count)
            ListTile(leading: const Icon(NxI.checks), title: Text(tr('เลือกทั้งหมด (${widget.totalCount})')), onTap: () => Navigator.pop(ctx, 'all')),
        ]));
    switch (what) {
      case 'bulk':
        if (!mounted) return;
        final reload = widget.onChanged;
        final clear = widget.onClear;
        final changed = await openWorkspaceBulkChange(context, items: [for (final r in widget.items) _ref(r)], boardId: widget.boardId);
        if (changed) {
          clear();
          await reload();
        }
      case 'copy':
        await _copy();
      case 'reporter':
        await _person(reporter: true);
      case 'all':
        widget.onSelectAll?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Opposite of the theme so the dock stands out: dark on light, light on dark.
    final bg = cs.inverseSurface;
    final fg = cs.onInverseSurface;
    final hasTop = widget.items.any((r) => !wsIsEpic(r) && !wsIsSubtask(r));
    final hasSub = widget.items.any(wsIsSubtask);
    final tools = <(String, IconData, String, Future<void> Function())>[
      ('status', NxI.radioButton, tr('สถานะ'), _status),
      ('assignee', NxI.user, tr('ผู้รับผิดชอบ'), () => _person(reporter: false)),
      ('priority', NxI.flag, tr('ความสำคัญ'), _priority),
      ('dates', NxI.calendarBlank, tr('วันที่'), _dates),
      ('labels', NxI.tag, tr('ป้าย'), _labels),
      if (hasTop && widget.epics.isNotEmpty) ('epic', NxI.lightning, 'Epic', _epic),
      if (hasSub && widget.parentOptions.isNotEmpty) ('parent', NxI.gitBranch, tr('งานแม่'), _parent),
      ('duplicate', NxI.copySimple, tr('ทำซ้ำ'), _duplicate),
      ('delete', NxI.trash, tr('ลบ'), _delete),
      ('more', NxI.dotsThree, tr('เพิ่มเติม'), _more),
    ];
    return Material(
      key: const ValueKey('ws-bulk-dock'),
      color: bg,
      elevation: 10,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Container(
              key: const ValueKey('ws-bulk-count'),
              constraints: const BoxConstraints(minWidth: 30),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(15)),
              child: Text('$_count', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (id, icon, label, run) in tools)
                      _DockButton(
                        key: ValueKey('bulk-tool-$id'),
                        icon: icon,
                        label: label,
                        color: id == 'delete' ? const Color(0xFFF87171) : fg,
                        onTap: _busy ? null : run,
                      ),
                  ],
                ),
              ),
            ),
            if (_busy)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)))
            else
              IconButton(
                key: const ValueKey('ws-bulk-clear'),
                tooltip: tr('ล้างการเลือก'),
                onPressed: widget.onClear,
                icon: Icon(NxI.x, color: fg.withValues(alpha: 0.75), size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({super.key, required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: onTap == null ? color.withValues(alpha: 0.4) : color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color.withValues(alpha: onTap == null ? 0.4 : 0.9))),
            ],
          ),
        ),
      ),
    );
  }
}
