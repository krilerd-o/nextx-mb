import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/workspace_models.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_chrome.dart';
import '../../widgets/nx_icons.dart';
import 'ws_detail_parts.dart' show confirmWsStatus;

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

  // "ย้ายไปที่" dock: a pill at the bottom while dragging; finger on it opens
  // the panel of statuses (end states as big buttons).
  final _dockKey = GlobalKey();
  final Map<String, GlobalKey> _dockRowKeys = {};
  bool _dockOpen = false;
  bool _overDock = false;
  String? _dockHover;

  /// Columns waiting for the server after a drop ("กำลังอัปเดต…").
  final Set<String> _updating = {};
  String? _flashId;
  Timer? _flashTimer;

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
    if (_dragging != null) NxChromeBus.dragging.value = false;
    _flashTimer?.cancel();
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
    // Choosing in the dock: the board holds still.
    if (_overDock || _dockOpen) return;
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
  }

  Rect? _rectOf(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Dock hit-testing by pointer; true when the finger is on the dock.
  bool _updateDock(Offset global) {
    final dock = _rectOf(_dockKey);
    final on = dock != null && dock.inflate(_dockOpen ? 0 : 8).contains(global);
    String? hover;
    if (_dockOpen) {
      for (final e in _dockRowKeys.entries) {
        final r = _rectOf(e.value);
        if (r != null && r.contains(global)) {
          hover = e.key;
          break;
        }
      }
    }
    // Leaving the open panel upward folds it back to the pill.
    final close = _dockOpen && dock != null && global.dy < dock.top - 24;
    final open = !_dockOpen && on;
    if (open || close || on != _overDock || hover != _dockHover) {
      if (open) HapticFeedback.mediumImpact();
      if (hover != null && hover != _dockHover) HapticFeedback.selectionClick();
      setState(() {
        if (open) _dockOpen = true;
        if (close) _dockOpen = false;
        _overDock = on;
        _dockHover = close ? null : hover;
      });
    }
    return on || _dockOpen;
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
    // Tab bar + FAB step aside so the dock owns the bottom edge.
    NxChromeBus.dragging.value = true;
    setState(() {
      _dragging = item;
      _dragStart = at;
      _pointer = at;
      _dockOpen = false;
      _overDock = false;
      _dockHover = null;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  void _updateDrag(Offset global) {
    _pointer = global;
    if (_updateDock(global)) {
      if (_hoverStatus != null) {
        setState(() {
          _hoverStatus = null;
          _hoverIndex = null;
        });
      }
      return;
    }
    // Which column is under the finger? Between two columns (the gap, or a
    // fat finger at the edge) the nearest one wins, so a drop never misses.
    String? hover;
    var best = 40.0;
    for (final s in widget.statuses) {
      final box = _columnKeys[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final o = box.localToGlobal(Offset.zero);
      final r = Rect.fromLTWH(o.dx, o.dy, box.size.width, box.size.height);
      if (r.contains(global)) {
        hover = s.id;
        break;
      }
      if (global.dy < r.top || global.dy > r.bottom) continue;
      final d = global.dx < r.left ? r.left - global.dx : global.dx - r.right;
      if (d < best) {
        best = d;
        hover = s.id;
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
    NxChromeBus.dragging.value = false;
    final item = _dragging;
    final start = _dragStart;
    final end = _pointer;
    // Dropped in the open dock: on a status row/button, or nowhere (cancel).
    final viaDock = _dockOpen || _overDock;
    if (viaDock) {
      forceStatus = _dockOpen ? _dockHover : null;
      toEnd = true;
    }
    final target = viaDock ? forceStatus : (forceStatus ?? _hoverStatus);
    final index = toEnd ? null : _hoverIndex;
    setState(() {
      _dragging = null;
      _hoverStatus = null;
      _hoverIndex = null;
      _dockOpen = false;
      _overDock = false;
      _dockHover = null;
    });
    if (item == null) return;
    // Long-press without moving = select.
    if (!viaDock && forceStatus == null && start != null && end != null && (end - start).distance < 12) {
      widget.onToggleSelect?.call(item);
      return;
    }
    if (target == null) return;
    // Another column = a status change: ask first; cancel leaves the card where it was.
    if ('${item['status_id']}' != target && !await confirmWsStatus(context, item: item, statuses: widget.statuses, to: target)) return;
    if (!mounted) return;
    await _applyMove(item, target, index: index, scrollTo: viaDock);
  }

  /// Moves [item] to [target] (at [index] or the end), server call, rollback
  /// on refusal, then an undo snackbar when the status changed.
  Future<void> _applyMove(Map<String, dynamic> item, String target, {int? index, bool scrollTo = false, bool undoable = true}) async {
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
    final unchanged = from == target && (before[from]?.indexWhere((e) => '${e['id']}' == id) ?? -1) == at;
    if (unchanged) return;
    setState(() {
      _cols = next;
      _updating.add(target);
      _flashId = id;
    });
    HapticFeedback.lightImpact();
    if (scrollTo) _scrollToStatus(target);
    final ok = await widget.onMove(item, target, [for (final e in dest) '${e['id']}']);
    if (!mounted) return;
    setState(() {
      _updating.remove(target);
      if (!ok) _cols = before;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _flashId == id) setState(() => _flashId = null);
    });
    if (!ok || !undoable || from == target) return;
    final s = widget.statuses.where((x) => x.id == target).firstOrNull;
    final count = next[target]?.length ?? 0;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      key: const ValueKey('ws-move-snack'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('ย้ายไปยัง ${s?.label ?? ''} แล้ว'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(tr('$count งาน'), style: const TextStyle(fontSize: 12)),
        ],
      ),
      // Actions make snackbars persist by default; these must time out.
      persist: false,
      action: SnackBarAction(
        label: tr('เลิกทำ'),
        onPressed: () => _undo(moved, from, before[from] ?? const []),
      ),
    ));
  }

  /// Puts the card back in its old column at its old place.
  Future<void> _undo(Map<String, dynamic> moved, String from, List<Map<String, dynamic>> oldOrder) async {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    final id = '${moved['id']}';
    final at = oldOrder.indexWhere((e) => '${e['id']}' == id);
    await _applyMove(moved, from, index: at < 0 ? null : at, scrollTo: true, undoable: false);
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
        // "ย้ายไปที่" dock: rises from the bottom while dragging.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _dragging == null,
            child: LayoutBuilder(builder: (context, box) => _dock(context, cs, box.maxHeight)),
          ),
        ),
      ],
    );
  }

  Widget _dock(BuildContext context, ColorScheme cs, double maxH) {
    final theme = Theme.of(context);
    final dragging = _dragging != null;
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 12;
    final from = '${_dragging?['status_id'] ?? ''}';
    final rows = [for (final s in widget.statuses) if (!s.isTerminal) s];
    final ends = [for (final s in widget.statuses) if (s.isTerminal) s];
    final hoverIdx = rows.indexWhere((s) => s.id == _dockHover);
    final panelH = math.min(maxH * 0.62, 52.0 + rows.length * 60 + (ends.isEmpty ? 8 : 104));
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dur = Duration(milliseconds: reduced ? 0 : 320);

    Widget row(WsStatus s) {
      final on = _dockHover == s.id;
      final current = s.id == from;
      final items = _cols[s.id] ?? const [];
      final est = items.fold<int>(0, (a, r) => a + (wsInt(r['original_estimate_minutes']) ?? 0));
      return AnimatedScale(
        key: _dockRowKeys.putIfAbsent(s.id, GlobalKey.new),
        scale: on ? 1.02 : 1,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4))] : null,
          ),
          child: Opacity(
            opacity: current ? 0.45 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  Text(
                    current ? tr('ปัจจุบัน') : [tr('${items.length} งาน'), if (est > 0) formatMinutes(est)].join(' · '),
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: on ? 1 : 0.18,
                    minHeight: 3,
                    color: s.color,
                    backgroundColor: s.color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget end(WsStatus s) {
      final on = _dockHover == s.id;
      final icon = s.isDone ? NxI.checkCircle : NxI.prohibit;
      final color = s.isDone ? const Color(0xFF10B981) : const Color(0xFFEF4444);
      return Expanded(
        child: AnimatedContainer(
          key: _dockRowKeys.putIfAbsent(s.id, GlobalKey.new),
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.16) : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? color : cs.outlineVariant.withValues(alpha: 0.5), width: on ? 1.6 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(scale: on ? 1.18 : 1, duration: const Duration(milliseconds: 160), child: Icon(icon, size: 28, color: color)),
              const SizedBox(height: 6),
              Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    final panel = Column(
      key: const ValueKey('ws-dock-panel'),
      children: [
        Container(
          height: 48,
          color: cs.inverseSurface,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Icon(NxI.moveRight, size: 18, color: cs.onInverseSurface),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('ย้ายไปที่'), style: theme.textTheme.titleSmall?.copyWith(color: cs.onInverseSurface, fontWeight: FontWeight.w700))),
            if (hoverIdx >= 0)
              Text('${hoverIdx + 1}/${rows.length}', style: theme.textTheme.labelLarge?.copyWith(color: cs.onInverseSurface.withValues(alpha: 0.8))),
          ]),
        ),
        Expanded(
          child: ColoredBox(
            color: cs.surfaceContainerHigh,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final s in rows) row(s)],
            ),
          ),
        ),
        if (ends.isNotEmpty)
          Container(
            height: 96,
            color: cs.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(children: [for (final s in ends) end(s)]),
          ),
      ],
    );

    final pill = Row(
      key: const ValueKey('ws-dock-pill'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(NxI.moveRight, size: 18, color: cs.onInverseSurface),
        const SizedBox(width: 8),
        Text(tr('ย้ายไปที่'), style: theme.textTheme.titleSmall?.copyWith(color: cs.onInverseSurface, fontWeight: FontWeight.w700)),
      ],
    );

    return Stack(
      children: [
        AnimatedPositioned(
          duration: dur,
          curve: Curves.easeOutBack,
          left: _dockOpen ? 12 : 48,
          right: _dockOpen ? 12 : 48,
          bottom: dragging ? bottom : -90,
          height: _dockOpen ? panelH : 52,
          child: AnimatedContainer(
            key: _dockKey,
            duration: dur,
            curve: Curves.easeOutCubic,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _overDock && !_dockOpen ? Color.lerp(cs.inverseSurface, cs.primary, 0.35) : cs.inverseSurface,
              borderRadius: BorderRadius.circular(_dockOpen ? 24 : 26),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              // The panel is laid out at full height while the box grows into it.
              child: _dockOpen
                  ? OverflowBox(
                      key: const ValueKey('ws-dock-panel-box'),
                      alignment: Alignment.topCenter,
                      minHeight: panelH,
                      maxHeight: panelH,
                      child: panel,
                    )
                  : pill,
            ),
          ),
        ),
      ],
    );
  }

  /// Grey box that white cards stand out on (light), a raised tone (dark).
  static Color _columnFill(ThemeData theme) => theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : Color.alphaBlend(theme.colorScheme.onSurface.withValues(alpha: 0.055), theme.scaffoldBackgroundColor);

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
        clipBehavior: Clip.antiAlias,
        // A solid box per status (clear even on a light page), its colour as
        // a bar across the top; the column under the finger lights up.
        decoration: BoxDecoration(
          color: hovering ? Color.alphaBlend(s.color.withValues(alpha: 0.10), _columnFill(theme)) : _columnFill(theme),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hovering ? s.color : cs.outlineVariant.withValues(alpha: 0.35), width: hovering ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(height: 4, color: s.color),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _updating.contains(s.id)
                        ? tr('กำลังอัปเดต…')
                        : [tr('${rows.length} งาน'), if (estimate > 0) formatMinutes(estimate)].join(' · '),
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: _updating.contains(s.id)
                  ? LinearProgressIndicator(minHeight: 2, color: s.color, backgroundColor: Colors.transparent)
                  : null,
            ),
            Expanded(
              child: ListView(
                controller: _vc(s.id),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                children: [
                  if (visible.isEmpty && gapAt < 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(children: [
                        Icon(NxI.kanban, size: 28, color: cs.outline),
                        const SizedBox(height: 6),
                        Text(tr('ไม่มีงาน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
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
          // The card that just landed glows in its new status colour.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                _flashId == id
                    ? BoxShadow(color: s.color.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)
                    : BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: card,
          ),
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
                        child: NxAvatar(
                          key: ValueKey('ws-card-avatar-${item['assignee_id']}'),
                          label: assignee,
                          size: 24,
                          imageUrl: nxUserPhotos['${item['assignee_id']}'],
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
