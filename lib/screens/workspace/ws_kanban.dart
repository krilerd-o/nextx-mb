import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/workspace_models.dart';
import '../../widgets/nx_icons.dart';

/// Result of a drop: item moved to [statusId], column order after the drop.
typedef WsMove = Future<bool> Function(Map<String, dynamic> item, String statusId, List<String> orderedIds);

/// Kanban board with "lifted" cards that follow the finger, auto-scroll at
/// the screen edges (sideways and inside long columns) and a status-chip bar
/// to drop straight into a far column (e.g. To do → Done).
class WsKanban extends StatefulWidget {
  const WsKanban({
    super.key,
    required this.statuses,
    required this.items,
    required this.onOpen,
    required this.onMove,
    this.onQuickAdd,
    this.users = const {},
    this.epics = const {},
    this.boardCode,
    this.selected = const {},
    this.onToggleSelect,
    this.padding = EdgeInsets.zero,
  });

  final List<WsStatus> statuses;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onOpen;
  final WsMove onMove;
  final Future<void> Function(String statusId, String title)? onQuickAdd;

  /// user id → name; epic id → epic row (for the coloured epic tag).
  final Map<String, String> users;
  final Map<String, Map<String, dynamic>> epics;
  final String? boardCode;

  /// Multi-select (ids). A long-press without moving toggles selection.
  final Set<String> selected;
  final void Function(Map<String, dynamic> item)? onToggleSelect;
  final EdgeInsets padding;

  static const double columnWidth = 290;

  @override
  State<WsKanban> createState() => WsKanbanState();
}

class WsKanbanState extends State<WsKanban> with SingleTickerProviderStateMixin {
  final _hScroll = ScrollController();
  final Map<String, ScrollController> _vScroll = {};
  final Map<String, GlobalKey> _cardKeys = {};
  final Map<String, GlobalKey> _columnKeys = {};

  /// Local columns (optimistic moves are applied here first).
  late Map<String, List<Map<String, dynamic>>> _cols = _group();

  // Drag state
  Map<String, dynamic>? _dragging;
  Offset? _pointer;
  Offset? _dragStart;
  String? _hoverStatus;
  int? _hoverIndex;
  late final Ticker _ticker = createTicker(_tick);
  String? _chipHover;
  DateTime? _chipHoverSince;

  static const _edge = 72.0;
  static const _maxSpeed = 18.0;

  @override
  void didUpdateWidget(covariant WsKanban old) {
    super.didUpdateWidget(old);
    if (_dragging == null && (old.items != widget.items || old.statuses != widget.statuses)) {
      _cols = _group();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hScroll.dispose();
    for (final c in _vScroll.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, List<Map<String, dynamic>>> _group() {
    final out = {for (final s in widget.statuses) s.id: <Map<String, dynamic>>[]};
    final fallback = widget.statuses.isEmpty ? '' : widget.statuses.first.id;
    for (final it in widget.items) {
      final sid = '${it['status_id'] ?? ''}';
      (out[sid] ?? out[fallback] ?? (out[fallback] = [])).add(it);
    }
    for (final l in out.values) {
      l.sort((a, b) => (wsInt(a['sort_order']) ?? 0).compareTo(wsInt(b['sort_order']) ?? 0));
    }
    return out;
  }

  ScrollController _vc(String sid) => _vScroll.putIfAbsent(sid, ScrollController.new);
  GlobalKey _ck(String id) => _cardKeys.putIfAbsent(id, GlobalKey.new);
  GlobalKey _colKey(String sid) => _columnKeys.putIfAbsent(sid, GlobalKey.new);

  /// Test hook / programmatic scroll position.
  double get horizontalOffset => _hScroll.hasClients ? _hScroll.offset : 0;

  // ── auto-scroll while dragging near the edges
  void _tick(Duration _) {
    final p = _pointer;
    if (p == null || _dragging == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_hScroll.hasClients) return;
    final local = box.globalToLocal(p);
    final w = box.size.width;
    double dx = 0;
    if (local.dx < _edge) dx = -_maxSpeed * (1 - local.dx / _edge);
    if (local.dx > w - _edge) dx = _maxSpeed * (1 - (w - local.dx) / _edge);
    if (dx != 0) {
      final pos = _hScroll.position;
      final to = (pos.pixels + dx).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (to == pos.pixels) dx = 0;
      _hScroll.jumpTo(to);
    }
    // Vertical, inside the hovered column.
    var scrolledV = false;
    final sid = _hoverStatus;
    if (sid != null) {
      final vc = _vScroll[sid];
      final colBox = _columnKeys[sid]?.currentContext?.findRenderObject() as RenderBox?;
      if (vc != null && vc.hasClients && colBox != null) {
        final cl = colBox.globalToLocal(p);
        final h = colBox.size.height;
        double dy = 0;
        if (cl.dy < _edge) dy = -_maxSpeed * (1 - (cl.dy / _edge).clamp(0, 1));
        if (cl.dy > h - _edge) dy = _maxSpeed * (1 - ((h - cl.dy) / _edge).clamp(0, 1));
        if (dy != 0) {
          final pos = vc.position;
          final to = (pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent);
          scrolledV = to != pos.pixels;
          vc.jumpTo(to);
        }
      }
    }
    // Columns slid under a still finger: recompute the drop target.
    if (dx != 0 || scrolledV) _updateDrag(p);
    // Hovering a status chip for a moment jumps the board to that column.
    final chip = _chipHover;
    if (chip != null && _chipHoverSince != null && DateTime.now().difference(_chipHoverSince!) > const Duration(milliseconds: 380)) {
      _chipHoverSince = null;
      _scrollToStatus(chip);
    }
  }

  void _scrollToStatus(String sid) {
    final i = widget.statuses.indexWhere((s) => s.id == sid);
    if (i < 0 || !_hScroll.hasClients) return;
    final target = (i * (WsKanban.columnWidth + 10)).clamp(0.0, _hScroll.position.maxScrollExtent);
    _hScroll.animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  /// Index in [sid]'s column where a card dropped at [global] would go.
  int _indexAt(String sid, Offset global) {
    final list = _cols[sid] ?? const [];
    for (var i = 0; i < list.length; i++) {
      final id = '${list[i]['id']}';
      if (id == '${_dragging?['id']}') continue;
      final box = _cardKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (global.dy < top + box.size.height / 2) return i;
    }
    return list.length;
  }

  void _startDrag(Map<String, dynamic> item, Offset at) {
    HapticFeedback.mediumImpact();
    setState(() {
      _dragging = item;
      _dragStart = at;
      _pointer = at;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  void _updateDrag(Offset global) {
    _pointer = global;
    // Which column is under the finger?
    String? hover;
    for (final s in widget.statuses) {
      final box = _columnKeys[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final o = box.localToGlobal(Offset.zero);
      if (Rect.fromLTWH(o.dx, o.dy, box.size.width, box.size.height).contains(global)) {
        hover = s.id;
        break;
      }
    }
    final idx = hover == null ? null : _indexAt(hover, global);
    if (hover != _hoverStatus || idx != _hoverIndex) {
      if (hover != null && hover != _hoverStatus) HapticFeedback.selectionClick();
      setState(() {
        _hoverStatus = hover;
        _hoverIndex = idx;
      });
    }
  }

  Future<void> _endDrag({String? forceStatus, bool toEnd = false}) async {
    _ticker.stop();
    final item = _dragging;
    final start = _dragStart;
    final end = _pointer;
    final target = forceStatus ?? _hoverStatus;
    final index = toEnd ? null : _hoverIndex;
    setState(() {
      _dragging = null;
      _hoverStatus = null;
      _hoverIndex = null;
      _chipHover = null;
    });
    if (item == null) return;
    // Long-press without moving = select.
    if (forceStatus == null && start != null && end != null && (end - start).distance < 12) {
      widget.onToggleSelect?.call(item);
      return;
    }
    if (target == null) return;
    final id = '${item['id']}';
    final from = '${item['status_id']}';
    final before = {for (final e in _cols.entries) e.key: List.of(e.value)};
    // Apply locally first.
    final next = {for (final e in _cols.entries) e.key: List.of(e.value)};
    next[from]?.removeWhere((e) => '${e['id']}' == id);
    final dest = next.putIfAbsent(target, () => []);
    var at = index ?? dest.length;
    if (from == target) {
      final oldIdx = before[from]!.indexWhere((e) => '${e['id']}' == id);
      if (oldIdx >= 0 && oldIdx < at) at -= 1;
    }
    at = at.clamp(0, dest.length);
    final moved = {...item, 'status_id': int.tryParse(target) ?? target};
    dest.insert(at, moved);
    final unchanged = from == target && before[from]!.indexWhere((e) => '${e['id']}' == id) == at;
    if (unchanged) return;
    setState(() => _cols = next);
    HapticFeedback.lightImpact();
    final ok = await widget.onMove(item, target, [for (final e in dest) '${e['id']}']);
    if (!ok && mounted) setState(() => _cols = before);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Listener(
          onPointerMove: (e) {
            if (_dragging != null) _updateDrag(e.position);
          },
          child: ListView.separated(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            padding: widget.padding.add(const EdgeInsets.fromLTRB(12, 8, 12, 12)),
            itemCount: widget.statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _column(context, widget.statuses[i]),
          ),
        ),
        // Status chips appear while dragging: hover to jump, drop to move.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          top: _dragging == null ? -70 : widget.padding.top + 4,
          child: IgnorePointer(
            ignoring: _dragging == null,
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in widget.statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                      child: DragTarget<Map<String, dynamic>>(
                        onWillAcceptWithDetails: (_) {
                          if (_chipHover != s.id) {
                            _chipHover = s.id;
                            _chipHoverSince = DateTime.now();
                            HapticFeedback.selectionClick();
                            setState(() {});
                          }
                          return true;
                        },
                        onLeave: (_) => setState(() => _chipHover = null),
                        onAcceptWithDetails: (_) => _endDrag(forceStatus: s.id, toEnd: true),
                        builder: (context, cand, _) {
                          final on = _chipHover == s.id;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? s.color : cs.surface.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: s.color, width: 1.4),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
                            ),
                            child: Text(
                              s.label,
                              style: TextStyle(
                                color: on ? Colors.white : s.color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _column(BuildContext context, WsStatus s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = _cols[s.id] ?? const [];
    final hovering = _dragging != null && _hoverStatus == s.id;
    final estimate = rows.fold<int>(0, (a, r) => a + (wsInt(r['original_estimate_minutes']) ?? 0));
    final draggingId = '${_dragging?['id']}';
    final visible = [for (final r in rows) if ('${r['id']}' != draggingId || _dragging == null) r];
    final gapAt = hovering ? (_hoverIndex ?? visible.length).clamp(0, visible.length) : -1;

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (_) => _endDrag(),
      builder: (context, _, _) => AnimatedContainer(
        key: _colKey(s.id),
        duration: const Duration(milliseconds: 180),
        width: WsKanban.columnWidth,
        decoration: BoxDecoration(
          color: hovering ? s.color.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hovering ? s.color : Colors.transparent, width: 1.6),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                    child: Text('${rows.length}', style: theme.textTheme.labelMedium?.copyWith(color: s.color, fontWeight: FontWeight.w700)),
                  ),
                  if (estimate > 0) ...[
                    const SizedBox(width: 6),
                    Text(formatMinutes(estimate), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _vc(s.id),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (var i = 0; i <= visible.length; i++) ...[
                    if (i == gapAt)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 64,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: s.color.withValues(alpha: 0.6), width: 1.4),
                          color: s.color.withValues(alpha: 0.06),
                        ),
                      ),
                    if (i < visible.length) _draggableCard(context, visible[i], s),
                  ],
                  if (widget.onQuickAdd != null) _QuickAdd(onSubmit: (t) => widget.onQuickAdd!(s.id, t)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draggableCard(BuildContext context, Map<String, dynamic> item, WsStatus s) {
    final id = '${item['id']}';
    final card = WsTaskCard(
      item: item,
      users: widget.users,
      epic: widget.epics['${item['epic_id']}'],
      boardCode: widget.boardCode,
      selected: widget.selected.contains(id),
      onTap: () => widget.selected.isNotEmpty ? widget.onToggleSelect?.call(item) : widget.onOpen(item),
    );
    return Padding(
      key: _ck(id),
      padding: const EdgeInsets.only(bottom: 8),
      child: LongPressDraggable<Map<String, dynamic>>(
        data: item,
        delay: const Duration(milliseconds: 260),
        hapticFeedbackOnStart: false,
        onDragStarted: () => _startDrag(item, _pointer ?? Offset.zero),
        onDragUpdate: (d) {
          _dragStart ??= d.globalPosition;
          _updateDrag(d.globalPosition);
        },
        onDraggableCanceled: (_, _) => _endDrag(),
        onDragEnd: (d) {
          if (!d.wasAccepted && _dragging != null) _endDrag();
        },
        feedback: _LiftedCard(width: WsKanban.columnWidth - 16, pointerDx: () => _pointer?.dx, child: card),
        childWhenDragging: const SizedBox.shrink(),
        child: Listener(
          onPointerDown: (e) => _pointer = e.position,
          child: card,
        ),
      ),
    );
  }
}

/// Card under the finger: slightly bigger, shadowed and tilted by drag direction.
class _LiftedCard extends StatefulWidget {
  const _LiftedCard({required this.width, required this.child, required this.pointerDx});
  final double width;
  final Widget child;
  final double? Function() pointerDx;

  @override
  State<_LiftedCard> createState() => _LiftedCardState();
}

class _LiftedCardState extends State<_LiftedCard> with SingleTickerProviderStateMixin {
  late final Ticker _t = createTicker((_) {
    final x = widget.pointerDx();
    if (x == null) return;
    final v = (x - (_lastX ?? x)).clamp(-30.0, 30.0);
    _lastX = x;
    final target = v / 30 * 0.035; // ≈ ±2°
    if ((target - _tilt).abs() > 0.001) setState(() => _tilt += (target - _tilt) * 0.25);
  });
  double _tilt = 0;
  double? _lastX;

  @override
  void initState() {
    super.initState();
    _t.start();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 1.04),
      duration: const Duration(milliseconds: 160),
      builder: (context, scale, child) => Transform.rotate(
        angle: _tilt,
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Material(
        color: Colors.transparent,
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(width: widget.width, child: widget.child),
      ),
    );
  }
}

/// Kanban / list card for a Workspace item.
class WsTaskCard extends StatelessWidget {
  const WsTaskCard({
    super.key,
    required this.item,
    this.users = const {},
    this.epic,
    this.boardCode,
    this.selected = false,
    this.onTap,
    this.dense = false,
  });

  final Map<String, dynamic> item;
  final Map<String, String> users;
  final Map<String, dynamic>? epic;
  final String? boardCode;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = wsTypeStyle(wsType(item));
    final pr = wsPriorityStyle('${item['priority'] ?? ''}');
    final due = wsDueIn(item['due_date']);
    final assignee = users['${item['assignee_id']}'];
    final spent = wsInt(item['time_spent_minutes']) ?? 0;
    final est = wsInt(item['original_estimate_minutes']) ?? 0;
    final labels = [for (final l in (item['labels'] is List ? item['labels'] as List : const [])) '$l'];
    final done = '${item['is_completed']}' == '1';
    return Material(
      color: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5), width: selected ? 1.6 : 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, size: 15, color: type.color),
                  const SizedBox(width: 6),
                  Text(wsKey(item, boardCode: boardCode), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (selected) Icon(NxI.checkCircle, size: 16, color: cs.primary) else Icon(pr.icon, size: 16, color: pr.color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                wsTitle(item),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
              if (epic != null || labels.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (epic != null) _Tag(text: wsTitle(epic!), color: const Color(0xFF8B5CF6), icon: NxI.lightning),
                    for (final l in labels.take(3)) _Tag(text: l, color: cs.onSurfaceVariant),
                  ],
                ),
              ],
              if (!dense && (due != null || est > 0 || spent > 0 || assignee != null)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (due != null)
                      _Meta(
                        icon: NxI.calendarBlank,
                        text: wsShortDate(item['due_date']),
                        color: due < 0 && !done ? cs.error : (due == 0 ? const Color(0xFFF59E0B) : cs.onSurfaceVariant),
                      ),
                    if (est > 0 || spent > 0) ...[
                      const SizedBox(width: 8),
                      _Meta(icon: NxI.timer, text: est > 0 ? '${formatMinutes(spent)}/${formatMinutes(est)}' : formatMinutes(spent), color: cs.onSurfaceVariant),
                    ],
                    const Spacer(),
                    if (assignee != null)
                      Tooltip(
                        message: assignee,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: cs.primary.withValues(alpha: 0.15),
                          child: Text(assignee.characters.first, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
                if (est > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: math.min(1, spent / est),
                      minHeight: 4,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: spent > est ? cs.error : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      );
}

/// "+ เพิ่มงาน" at the bottom of a column: type a title, Enter to create.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.onSubmit});
  final Future<void> Function(String title) onSubmit;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  bool _open = false;
  bool _busy = false;
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final t = _c.text.trim();
    if (t.isEmpty) {
      setState(() => _open = false);
      return;
    }
    setState(() => _busy = true);
    await widget.onSubmit(t);
    if (!mounted) return;
    _c.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_open) {
      return TextButton.icon(
        onPressed: () => setState(() => _open = true),
        icon: const Icon(NxI.plus, size: 18),
        label: Text(tr('เพิ่มงาน')),
        style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: cs.onSurfaceVariant),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: _c,
        autofocus: true,
        enabled: !_busy,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _go(),
        decoration: InputDecoration(
          hintText: tr('ชื่องาน แล้วกด Enter'),
          isDense: true,
          border: InputBorder.none,
          suffixIcon: _busy
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(NxI.x, size: 16), onPressed: () => setState(() => _open = false)),
        ),
      ),
    );
  }
}
