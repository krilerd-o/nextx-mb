import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/minutes/minute_board.dart';
import '../../services/api_client.dart';
import '../../services/minutes/minute_board_controller.dart';
import '../../widgets/nx_icons.dart';

/// Shared meeting workspace — โน้ต · เช็กลิสต์ · บอร์ด · สเก็ตช์ — live for everyone in the meeting
/// (room participants and guests, the recorder, the meeting page).
class MinuteWorkspace extends StatefulWidget {
  const MinuteWorkspace({
    super.key,
    required this.controller,
    this.initialTab = 0,
    this.api,
    this.canPin = false,
    this.boardPinned = false,
    this.onPinBoard,
    this.onClose,
  });

  final MinuteBoardController controller;
  final int initialTab;
  final ApiClient? api;
  final bool canPin;
  final bool boardPinned;
  final VoidCallback? onPinBoard;
  final VoidCallback? onClose;

  @override
  State<MinuteWorkspace> createState() => _MinuteWorkspaceState();
}

class _MinuteWorkspaceState extends State<MinuteWorkspace> {
  late int _tab = widget.initialTab;
  MinuteBoardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = checklistProgress(c.items);
    final tabs = [
      (NxI.note, 'โน้ต', c.items.where((x) => x.kind == 'note').length.toString()),
      (NxI.listChecks, 'เช็กลิสต์', p.total > 0 ? '${p.done}/${p.total}' : ''),
      (NxI.squaresFour, 'บอร์ด', c.items.where((x) => x.kind == 'sticky').length.toString()),
      (NxI.pencilSimple, 'สเก็ตช์', ''),
    ];
    return Column(
      key: const ValueKey('minute-workspace'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: InkWell(
                        key: ValueKey('ws-tab-$i'),
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => setState(() => _tab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(color: _tab == i ? cs.surface : Colors.transparent, borderRadius: BorderRadius.circular(11), boxShadow: _tab == i ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null),
                          child: Column(children: [
                            Icon(tabs[i].$1, size: 17, color: _tab == i ? cs.primary : cs.onSurfaceVariant),
                            const SizedBox(height: 2),
                            Text(
                              tabs[i].$3.isEmpty || tabs[i].$3 == '0' ? tr(tabs[i].$2) : '${tr(tabs[i].$2)} ${tabs[i].$3}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _tab == i ? cs.primary : cs.onSurfaceVariant),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            if (widget.onClose != null) IconButton(tooltip: tr('ปิด'), onPressed: widget.onClose, icon: const Icon(NxI.x)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 2),
          child: Row(children: [
            _statusDot(cs),
            if (c.people.isNotEmpty) ...[const SizedBox(width: 10), Icon(NxI.users, size: 13, color: cs.onSurfaceVariant), const SizedBox(width: 3), Text('${c.people.length}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))],
            if (!c.canEdit && c.status == 'live') ...[const SizedBox(width: 10), Text(tr('ดูอย่างเดียว'), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))],
            const Spacer(),
            if (widget.canPin && widget.onPinBoard != null)
              ActionChip(
                key: const ValueKey('ws-pin-board'),
                visualDensity: VisualDensity.compact,
                avatar: Icon(NxI.pushPin, size: 14, color: widget.boardPinned ? cs.onPrimary : cs.primary),
                backgroundColor: widget.boardPinned ? cs.primary : null,
                label: Text(tr(widget.boardPinned ? 'เลิกปักหมุดบนจอ' : 'ปักหมุดให้ทุกคนเห็น'), style: TextStyle(fontSize: 11.5, color: widget.boardPinned ? cs.onPrimary : cs.primary)),
                onPressed: widget.onPinBoard,
              ),
          ]),
        ),
        Expanded(
          child: switch (_tab) {
            0 => _NotesTab(c: c),
            1 => _ChecklistTab(c: c, api: widget.api),
            2 => _BoardTab(c: c),
            _ => SketchTab(c: c),
          },
        ),
      ],
    );
  }

  Widget _statusDot(ColorScheme cs) {
    final (Color color, String label) = switch (c.status) {
      'live' => (const Color(0xFF10B981), 'ซิงก์สด'),
      'offline' => (const Color(0xFFF59E0B), 'ออฟไลน์ — จะส่งเมื่อกลับมาออนไลน์'),
      'error' => (cs.error, 'เปิดพื้นที่ทำงานไม่ได้'),
      _ => (cs.outline, 'กำลังเชื่อมต่อ'),
    };
    return Row(children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(tr(label), key: const ValueKey('ws-status'), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Open the workspace as a tall sheet (room, recorder).
Future<void> showMinuteWorkspaceSheet(BuildContext context, MinuteBoardController c, {int tab = 0, ApiClient? api, bool canPin = false, bool Function()? boardPinned, VoidCallback? onPinBoard}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.86,
      child: StatefulBuilder(
        builder: (ctx, setS) => MinuteWorkspace(
          controller: c,
          initialTab: tab,
          api: api,
          canPin: canPin,
          boardPinned: boardPinned?.call() ?? false,
          onPinBoard: onPinBoard == null
              ? null
              : () {
                  onPinBoard();
                  Future<void>.delayed(const Duration(milliseconds: 400), () => ctx.mounted ? setS(() {}) : null);
                },
        ),
      ),
    ),
  );
}

/* ───────────── shared bits ───────────── */

/// A text field bound to a board field: keeps what I type while others edit, saves after a pause.
class _BoundField extends StatefulWidget {
  const _BoundField({required this.value, required this.onSave, this.hint, this.style, this.maxLines = 1, this.readOnly = false, this.fieldKey});
  final String value;
  final ValueChanged<String> onSave;
  final String? hint;
  final TextStyle? style;
  final int? maxLines;
  final bool readOnly;
  final Key? fieldKey;

  @override
  State<_BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<_BoundField> {
  late final _ctl = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _t?.cancel();
        if (_ctl.text != widget.value) widget.onSave(_ctl.text);
      }
    });
  }

  @override
  void didUpdateWidget(_BoundField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _ctl.text) _ctl.text = widget.value;
  }

  @override
  void dispose() {
    _t?.cancel();
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _ctl,
    focusNode: _focus,
    readOnly: widget.readOnly,
    maxLines: widget.maxLines,
    minLines: 1,
    style: widget.style,
    decoration: InputDecoration(
      hintText: widget.hint == null ? null : tr(widget.hint!),
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    ),
    onChanged: (v) {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 450), () => widget.onSave(v));
    },
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.hint});
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: cs.primary)),
        const SizedBox(height: 10),
        Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tr(hint), textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/* ───────────── notes ───────────── */

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.c});
  final MinuteBoardController c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notes = c.items.where((x) => x.kind == 'note').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (notes.isEmpty) const _Empty(icon: NxI.note, title: 'จดโน้ตร่วมกัน', hint: 'ทุกคนในการประชุมเห็นและแก้ไขได้ทันที ไอแซคจะนำไปใช้ประกอบการสรุป'),
        for (final n in notes)
          Container(
            key: ValueKey('ws-note-${n.uid}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _BoundField(value: n.str('title'), hint: 'หัวข้อ', readOnly: !c.canEdit, style: const TextStyle(fontWeight: FontWeight.w700), onSave: (v) => c.put('note', n.uid, {'title': v}))),
                if (c.canEdit) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('ลบ'), icon: Icon(NxI.trash, size: 18, color: cs.onSurfaceVariant), onPressed: () => c.del(n.uid)),
              ]),
              _BoundField(fieldKey: const ValueKey('ws-note-text'), value: n.str('text'), hint: 'พิมพ์โน้ต… ทุกคนเห็นพร้อมกัน', maxLines: null, readOnly: !c.canEdit, style: const TextStyle(height: 1.45), onSave: (v) => c.put('note', n.uid, {'text': v})),
              const SizedBox(height: 6),
              Text(
                [n.author, if (n.updatedBy != null && n.updatedBy != n.author) '${tr('แก้ล่าสุด')} ${n.updatedBy}'].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
        if (c.canEdit)
          OutlinedButton.icon(
            key: const ValueKey('ws-add-note'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => c.put('note', newBoardUid('note'), {'title': '', 'text': ''}),
            icon: const Icon(NxI.plus, size: 18),
            label: Text(tr('เพิ่มโน้ต')),
          ),
      ],
    );
  }
}

/* ───────────── checklist ───────────── */

class _ChecklistTab extends StatefulWidget {
  const _ChecklistTab({required this.c, this.api});
  final MinuteBoardController c;
  final ApiClient? api;

  @override
  State<_ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<_ChecklistTab> {
  final _input = TextEditingController();
  bool _busy = false;
  MinuteBoardController get c => widget.c;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final (text, who) = parseCheckInput(_input.text);
    if (text.isEmpty) return;
    c.put('check', newBoardUid('chk'), {'text': text, 'assignee': ?who});
    _input.clear();
  }

  Future<void> _tasks() async {
    final api = widget.api;
    if (api == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await api.createMinuteBoardTasks(c.meetingId);
      final ok = r.where((x) => x['activity_id'] != null).length;
      messenger?.showSnackBar(SnackBar(content: Text(ok > 0 ? '${tr('สร้างงานแล้ว')} $ok ${tr('รายการ')}' : tr('ไม่มีรายการที่ต้องสร้างงาน'))));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e is ApiEnvelopeException ? e.message : tr('สร้างงานไม่สำเร็จ'))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checks = c.items.where((x) => x.kind == 'check').toList();
    final p = checklistProgress(c.items);
    return Column(children: [
      if (p.total > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Column(children: [
            Row(children: [
              Text('${tr('เสร็จแล้ว')} ${p.done}/${p.total}', key: const ValueKey('ws-progress'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('${p.pct}%', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: p.pct / 100, minHeight: 6, color: const Color(0xFF10B981), backgroundColor: cs.surfaceContainerHighest)),
          ]),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          children: [
            if (checks.isEmpty) const _Empty(icon: NxI.listChecks, title: 'เช็กลิสต์ของการประชุม', hint: 'เพิ่มสิ่งที่ต้องทำ ใส่ @ชื่อ เพื่อมอบหมาย แล้วสร้างเป็นงานใน CRM ได้'),
            for (final it in checks)
              Dismissible(
                key: ValueKey('ws-check-${it.uid}'),
                direction: c.canEdit ? DismissDirection.endToStart : DismissDirection.none,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: cs.errorContainer, child: Icon(NxI.trash, color: cs.onErrorContainer)),
                onDismissed: (_) => c.del(it.uid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Checkbox(key: const ValueKey('ws-check-box'), value: it.done, activeColor: const Color(0xFF10B981), onChanged: c.canEdit ? (v) => c.put('check', it.uid, {'done': v == true}) : null),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, right: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _BoundField(
                            value: it.str('text'),
                            readOnly: !c.canEdit,
                            maxLines: null,
                            style: TextStyle(decoration: it.done ? TextDecoration.lineThrough : null, color: it.done ? cs.onSurfaceVariant : null),
                            onSave: (v) => c.put('check', it.uid, {'text': v}),
                          ),
                          const SizedBox(height: 2),
                          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            _MiniChip(
                              icon: NxI.user,
                              label: it.str('assignee').isEmpty ? tr('ผู้รับผิดชอบ') : '@${it.str('assignee')}',
                              faded: it.str('assignee').isEmpty,
                              onTap: c.canEdit ? () => _askAssignee(it) : null,
                            ),
                            _MiniChip(
                              icon: NxI.calendarBlank,
                              label: it.str('due').isEmpty ? tr('กำหนดส่ง') : it.str('due'),
                              faded: it.str('due').isEmpty,
                              onTap: c.canEdit ? () => _pickDue(it) : null,
                            ),
                            if (it.data['task_id'] != null) _MiniChip(icon: NxI.checkCircle, label: tr('สร้างงานแล้ว'), color: const Color(0xFF10B981)),
                          ]),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
      if (c.canEdit)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('ws-check-input'),
                    controller: _input,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      hintText: tr('เพิ่มรายการ… (@ชื่อ เพื่อมอบหมาย)'),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(key: const ValueKey('ws-check-add'), onPressed: _add, icon: const Icon(NxI.plus)),
              ]),
              if (widget.api != null && p.total > 0) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('ws-make-tasks'),
                    onPressed: _busy ? null : _tasks,
                    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.clipboardText, size: 18),
                    label: Text(tr('สร้างงานใน CRM จากรายการที่ยังไม่เสร็จ')),
                  ),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }

  Future<void> _askAssignee(BoardItem it) async {
    final ctl = TextEditingController(text: it.str('assignee'));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ผู้รับผิดชอบ')),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: tr('ชื่อ เช่น สมชาย'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), ctl.dispose);
    if (v != null) c.put('check', it.uid, {'assignee': v.replaceFirst('@', '').isEmpty ? null : v.replaceFirst('@', '')});
  }

  Future<void> _pickDue(BoardItem it) async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(it.str('due'));
    final d = await showDatePicker(context: context, initialDate: cur ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
    if (d == null) return;
    c.put('check', it.uid, {'due': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'});
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label, this.onTap, this.faded = false, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool faded;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? (faded ? cs.onSurfaceVariant.withValues(alpha: 0.7) : cs.primary);
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: fg), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11.5, color: fg))]),
      ),
    );
  }
}

/* ───────────── board ───────────── */

Color stickyColor(String name, bool dark) {
  const light = {'yellow': 0xFFFEF3C7, 'pink': 0xFFFCE7F3, 'blue': 0xFFE0F2FE, 'green': 0xFFD1FAE5, 'purple': 0xFFEDE9FE, 'orange': 0xFFFFEDD5};
  const darkC = {'yellow': 0xFF4A3B12, 'pink': 0xFF4A1D35, 'blue': 0xFF0C3550, 'green': 0xFF0B3B2C, 'purple': 0xFF2E2259, 'orange': 0xFF4A2A10};
  return Color((dark ? darkC : light)[name] ?? (dark ? darkC : light)['yellow']!);
}

Color stickyDot(String name) => Color(const {'yellow': 0xFFF59E0B, 'pink': 0xFFEC4899, 'blue': 0xFF0EA5E9, 'green': 0xFF10B981, 'purple': 0xFF8B5CF6, 'orange': 0xFFF97316}[name] ?? 0xFFF59E0B);

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.c});
  final MinuteBoardController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final cols = c.items.where((x) => x.kind == 'col').toList();
    final stickies = c.items.where((x) => x.kind == 'sticky').toList();
    final me = c.myIdentity ?? c.myName;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        for (final col in cols)
          Container(
            key: ValueKey('ws-col-${col.uid}'),
            width: 250,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
            child: DragTarget<String>(
              onAcceptWithDetails: (d) {
                final list = stickies.where((s) => s.str('col') == col.uid && s.uid != d.data).toList();
                c.put('sticky', d.data, {'col': col.uid}, pos: boardPosBetween(list.isEmpty ? null : list.last.pos, null));
              },
              builder: (context, cand, _) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: stickyDot(col.str('color')), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: _BoundField(value: col.str('title'), readOnly: !c.canEdit, style: const TextStyle(fontWeight: FontWeight.w800), onSave: (v) => c.put('col', col.uid, {'title': v}))),
                    Text('${stickies.where((s) => s.str('col') == col.uid).length}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    if (c.canEdit)
                      PopupMenuButton<String>(
                        iconSize: 18,
                        icon: const Icon(NxI.dotsThreeVertical, size: 18),
                        onSelected: (v) => v == 'del' ? c.del(col.uid) : c.put('col', col.uid, {'color': v}),
                        itemBuilder: (_) => [
                          for (final k in kStickyColors) PopupMenuItem(value: k, child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: stickyDot(k), shape: BoxShape.circle)), const SizedBox(width: 8), Text(tr(_colorName(k)))])),
                          PopupMenuItem(value: 'del', child: Text(tr('ลบคอลัมน์'))),
                        ],
                      ),
                  ]),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: cand.isNotEmpty ? cs.primary.withValues(alpha: 0.06) : null, borderRadius: BorderRadius.circular(14)),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final s in stickies.where((s) => s.str('col') == col.uid))
                          LongPressDraggable<String>(
                            data: s.uid,
                            maxSimultaneousDrags: c.canEdit ? 1 : 0,
                            feedback: Material(color: Colors.transparent, child: SizedBox(width: 230, child: _StickyCard(s: s, c: c, me: me, dark: dark, cols: cols, ghost: true))),
                            childWhenDragging: Opacity(opacity: 0.3, child: _StickyCard(s: s, c: c, me: me, dark: dark, cols: cols)),
                            child: _StickyCard(s: s, c: c, me: me, dark: dark, cols: cols),
                          ),
                        if (c.canEdit)
                          TextButton.icon(
                            key: ValueKey('ws-add-sticky-${col.uid}'),
                            onPressed: () => c.put('sticky', newBoardUid('stk'), {'text': '', 'color': col.str('color').isEmpty ? 'yellow' : col.str('color'), 'col': col.uid}),
                            icon: const Icon(NxI.plus, size: 16),
                            label: Text(tr('เพิ่มการ์ด')),
                          ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        if (c.canEdit && cols.length < 12)
          SizedBox(
            width: 140,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () => c.put('col', newBoardUid('col'), {'title': tr('คอลัมน์ใหม่'), 'color': kStickyColors[cols.length % kStickyColors.length]}),
              icon: const Icon(NxI.plus, size: 18),
              label: Text(tr('คอลัมน์')),
            ),
          ),
      ],
    );
  }
}

String _colorName(String k) => const {'yellow': 'เหลือง', 'pink': 'ชมพู', 'blue': 'ฟ้า', 'green': 'เขียว', 'purple': 'ม่วง', 'orange': 'ส้ม'}[k] ?? k;

class _StickyCard extends StatelessWidget {
  const _StickyCard({required this.s, required this.c, required this.me, required this.dark, required this.cols, this.ghost = false});
  final BoardItem s;
  final MinuteBoardController c;
  final String me;
  final bool dark;
  final List<BoardItem> cols;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final votes = s.votes;
    final voted = votes.contains(me);
    final fg = dark ? Colors.white : const Color(0xFF1F2937);
    return Container(
      key: ValueKey('ws-sticky-${s.uid}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      decoration: BoxDecoration(
        color: stickyColor(s.str('color'), dark),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: ghost ? 0.25 : 0.06), blurRadius: ghost ? 14 : 3, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ghost
            ? Text(s.str('text'), style: TextStyle(color: fg))
            : _BoundField(value: s.str('text'), hint: 'พิมพ์ไอเดีย…', maxLines: null, readOnly: !c.canEdit, style: TextStyle(color: fg, height: 1.35), onSave: (v) => c.put('sticky', s.uid, {'text': v})),
        Row(children: [
          InkWell(
            key: ValueKey('ws-vote-${s.uid}'),
            borderRadius: BorderRadius.circular(99),
            onTap: c.canEdit ? () => c.put('sticky', s.uid, {'votes': voted ? votes.where((v) => v != me).toList() : [...votes, me]}) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: voted ? fg.withValues(alpha: 0.15) : null, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(voted ? NxI.thumbsUpFill : NxI.thumbsUp, size: 14, color: fg),
                if (votes.isNotEmpty) ...[const SizedBox(width: 4), Text('${votes.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))],
              ]),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(s.author ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.6)))),
          if (c.canEdit && !ghost)
            PopupMenuButton<String>(
              iconSize: 16,
              icon: Icon(NxI.dotsThreeVertical, size: 16, color: fg.withValues(alpha: 0.7)),
              tooltip: tr('ตัวเลือก'),
              onSelected: (v) {
                if (v == 'del') return c.del(s.uid);
                if (v.startsWith('col:')) return c.put('sticky', s.uid, {'col': v.substring(4)});
                c.put('sticky', s.uid, {'color': v});
              },
              itemBuilder: (_) => [
                for (final col in cols.where((x) => x.uid != s.str('col'))) PopupMenuItem(value: 'col:${col.uid}', child: Text('${tr('ย้ายไป')} ${col.str('title')}')),
                const PopupMenuDivider(),
                for (final k in kStickyColors) PopupMenuItem(value: k, child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: stickyDot(k), shape: BoxShape.circle)), const SizedBox(width: 8), Text(tr(_colorName(k)))])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'del', child: Text(tr('ลบการ์ด'))),
              ],
            ),
        ]),
      ]),
    );
  }
}

/* ───────────── sketch ───────────── */

Color _hex(String v) {
  final h = v.replaceFirst('#', '');
  return Color(int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16) ?? 0xFF111827);
}

String _toHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class SketchPainter extends CustomPainter {
  SketchPainter({required this.strokes, this.inks = const [], this.drawing});
  final List<BoardItem> strokes;
  final List<LiveInk> inks;
  final Map<String, dynamic>? drawing;

  void _draw(Canvas canvas, Size size, String? tool, List<double> raw, String color, double w) {
    final pts = shapePoints(tool, raw);
    if (pts.length < 2) return;
    final marker = tool == 'marker';
    final paint = Paint()
      ..color = _hex(color).withValues(alpha: marker ? 0.35 : 1)
      ..strokeWidth = math.max(1, w * size.width / 1000 * (marker ? 3 : 1))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts[0] * size.width, pts[1] * size.height);
    if (pts.length == 2) path.lineTo(pts[0] * size.width + 0.1, pts[1] * size.height + 0.1);
    for (var i = 2; i + 1 < pts.length; i += 2) {
      path.lineTo(pts[i] * size.width, pts[i + 1] * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    for (final s in strokes) {
      _draw(canvas, size, s.data['tool'] as String?, s.pts, s.str('color'), (s.data['w'] as num?)?.toDouble() ?? 3);
    }
    for (final i in inks) {
      _draw(canvas, size, i.tool, i.pts, i.color, i.w);
    }
    final d = drawing;
    if (d != null) _draw(canvas, size, d['tool'] as String?, (d['pts'] as List<double>), d['color'] as String, (d['w'] as num).toDouble());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SketchPainter old) => true;
}

/// Read-only live view of a sketch page (the room stage when the host pins the board).
class SketchView extends StatelessWidget {
  const SketchView({super.key, required this.c, this.page = 0});
  final MinuteBoardController c;
  final int page;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (_, _) => Center(
      child: AspectRatio(
        aspectRatio: kSketchRatio,
        child: CustomPaint(
          painter: SketchPainter(
            strokes: c.items.where((x) => x.kind == 'stroke' && x.page == page).toList(),
            inks: c.inks.values.where((i) => i.page == page).toList(),
          ),
        ),
      ),
    ),
  );
}

class SketchTab extends StatefulWidget {
  const SketchTab({super.key, required this.c});
  final MinuteBoardController c;

  @override
  State<SketchTab> createState() => _SketchTabState();
}

class _SketchTabState extends State<SketchTab> {
  String _tool = 'pen';
  int _color = kPenColors.first;
  double _w = 3;
  int _page = 0;
  int _extra = 1;
  Map<String, dynamic>? _drawing;
  DateTime _lastInk = DateTime.fromMillisecondsSinceEpoch(0);
  int _sent = 0;

  MinuteBoardController get c => widget.c;

  static const _tools = [
    ('pen', NxI.pencilSimple, 'ปากกา'),
    ('marker', NxI.highlighter, 'ไฮไลต์'),
    ('line', NxI.lineSegment, 'เส้นตรง'),
    ('arrow', NxI.arrowUpRight, 'ลูกศร'),
    ('rect', NxI.square, 'สี่เหลี่ยม'),
    ('ellipse', NxI.circle, 'วงรี'),
    ('eraser', NxI.eraser, 'ยางลบ'),
  ];

  (double, double) _at(Offset local, Size size) => ((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  void _start(Offset local, Size size) {
    if (!c.canEdit) return;
    final (x, y) = _at(local, size);
    if (_tool == 'eraser') {
      _erase(x, y);
      _drawing = {'erase': true};
      return;
    }
    HapticFeedback.selectionClick();
    final color = _tool == 'marker' && _color == kPenColors.first ? 0xFFF59E0B : _color;
    setState(() => _drawing = {'uid': newBoardUid('str'), 'page': _page, 'color': _toHex(color), 'w': _w, 'tool': _tool, 'pts': <double>[x, y]});
    _sent = 0;
  }

  void _erase(double x, double y) {
    final hit = strokeAt(c.items, _page, x, y);
    if (hit != null) {
      HapticFeedback.lightImpact();
      c.del(hit.uid);
    }
  }

  void _move(Offset local, Size size) {
    final d = _drawing;
    if (d == null) return;
    final (x, y) = _at(local, size);
    if (d['erase'] == true) return _erase(x, y);
    final pts = d['pts'] as List<double>;
    setState(() => pts.addAll([x, y]));
    final now = DateTime.now();
    if (now.difference(_lastInk).inMilliseconds > 60) {
      _lastInk = now;
      final shape = kShapeTools.contains(d['tool']);
      c.ink({'uid': d['uid'], 'page': _page, 'color': d['color'], 'w': d['w'], 'tool': d['tool'], 'pts': shape ? [pts[0], pts[1], x, y] : pts.sublist(_sent)});
      _sent = math.max(0, pts.length - 2);
    }
  }

  void _end() {
    final d = _drawing;
    setState(() => _drawing = null);
    if (d == null || d['erase'] == true) return;
    final raw = d['pts'] as List<double>;
    final shape = kShapeTools.contains(d['tool']);
    var pts = shape ? [raw[0], raw[1], raw[raw.length - 2], raw[raw.length - 1]] : simplifyPoints(raw);
    if (pts.length == 2) pts = [...pts, ...pts];
    c.ink({'uid': d['uid'], 'page': _page, 'done': true, 'pts': const []});
    c.put('stroke', d['uid'] as String, {'page': _page, 'color': d['color'], 'w': d['w'], 'tool': d['tool'], 'pts': pts});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = sketchPageCount(c.items, extra: _extra);
    final strokes = c.items.where((x) => x.kind == 'stroke' && x.page == _page).toList();
    final mine = strokes.where((s) => s.authorIdentity == c.myIdentity || (s.authorIdentity == null && s.pending)).toList();
    final drawingNow = c.inks.values.where((i) => i.page == _page).toList();
    return Column(children: [
      if (c.canEdit)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final t in _tools)
                IconButton(
                  key: ValueKey('ws-tool-${t.$1}'),
                  tooltip: tr(t.$3),
                  isSelected: _tool == t.$1,
                  style: IconButton.styleFrom(backgroundColor: _tool == t.$1 ? cs.primary : null, foregroundColor: _tool == t.$1 ? cs.onPrimary : null),
                  onPressed: () => setState(() => _tool = t.$1),
                  icon: Icon(t.$2, size: 19),
                ),
              const VerticalDivider(indent: 10, endIndent: 10),
              for (final col in kPenColors)
                GestureDetector(
                  onTap: () => setState(() => _color = col),
                  child: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                    decoration: BoxDecoration(
                      color: Color(col),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == col ? cs.primary : cs.outlineVariant, width: _color == col ? 3 : 1),
                    ),
                  ),
                ),
              SizedBox(width: 110, child: Slider(value: _w, min: 1, max: 16, onChanged: (v) => setState(() => _w = v))),
              IconButton(tooltip: tr('เลิกทำ (เส้นของฉัน)'), onPressed: mine.isEmpty ? null : () => c.del(mine.last.uid), icon: const Icon(NxI.arrowCounterClockwise, size: 19)),
              IconButton(
                tooltip: tr('ล้างหน้านี้'),
                onPressed: strokes.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: Text(tr('ล้างทุกเส้นในหน้านี้สำหรับทุกคน?')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ล้าง'))),
                            ],
                          ),
                        );
                        if (ok == true) c.clearPage(_page);
                      },
                icon: const Icon(NxI.trash, size: 19),
              ),
            ],
          ),
        ),
      Expanded(
        child: Container(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(10),
          child: Center(
            child: AspectRatio(
              aspectRatio: kSketchRatio,
              child: LayoutBuilder(
                builder: (_, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  return GestureDetector(
                    key: const ValueKey('ws-canvas'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _start(d.localPosition, size),
                    onPanUpdate: (d) => _move(d.localPosition, size),
                    onPanEnd: (_) => _end(),
                    onTapUp: (d) {
                      _start(d.localPosition, size);
                      _end();
                    },
                    child: CustomPaint(size: size, painter: SketchPainter(strokes: strokes, inks: drawingNow, drawing: _drawing?['erase'] == true ? null : _drawing)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(NxI.caretLeft, size: 18)),
            Text('${tr('หน้า')} ${_page + 1}/$pages', key: const ValueKey('ws-page'), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            IconButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), icon: const Icon(NxI.caretRight, size: 18)),
            if (c.canEdit && pages < 50)
              TextButton.icon(
                onPressed: () => setState(() {
                  _extra = pages + 1;
                  _page = pages;
                }),
                icon: const Icon(NxI.plus, size: 16),
                label: Text(tr('หน้าใหม่')),
              ),
            const Spacer(),
            if (drawingNow.isNotEmpty) Flexible(child: Text('✏️ ${drawingNow.map((i) => i.by).toSet().join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.primary))),
          ]),
        ),
      ),
    ]);
  }
}
