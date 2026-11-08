import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';
import 'cal_store.dart';
import 'cal_widgets.dart';
import 'cal_year_view.dart' show calPageBase;

/// Week / 3-day / day time grid.
/// - tap an empty slot → new appointment at that time
/// - long-press an appointment → drag to another time / day (15-min steps)
/// - drag the bottom edge → change how long it runs ("ขยายเวลา")
/// - "+N" in the all-day row → floating card with that day's appointments
class CalTimeGrid extends StatefulWidget {
  const CalTimeGrid({
    super.key,
    required this.store,
    required this.view,
    required this.anchor,
    required this.onAnchor,
    required this.onOpen,
    required this.onCreateAt,
    required this.onReschedule,
    required this.onOpenDay,
  });

  final CalStore store;
  final CalView view;
  final DateTime anchor;
  final ValueChanged<DateTime> onAnchor;
  final void Function(CalEvent e) onOpen;
  final void Function(DateTime at, {bool allDay}) onCreateAt;
  final Future<void> Function(CalEvent e, DateTime start, DateTime end) onReschedule;
  final ValueChanged<DateTime> onOpenDay;

  static const double hourH = 56;
  static const double gutter = 46;

  @override
  State<CalTimeGrid> createState() => CalTimeGridState();
}

class CalTimeGridState extends State<CalTimeGrid> {
  late DateTime _base = _periodStart(widget.anchor);
  late PageController _pc = PageController(initialPage: calPageBase);
  late double _vOffset = _initialOffset();

  int get _days => widget.view.gridDays;

  DateTime _periodStart(DateTime d) => widget.view == CalView.week ? weekStart(d) : calDay(d);
  DateTime _pageStart(int p) => _base.add(Duration(days: (p - calPageBase) * _days));

  double _initialOffset() {
    final now = thaiNow();
    final h = (now.hour - 1).clamp(0, 16);
    return h * CalTimeGrid.hourH;
  }

  @override
  void didUpdateWidget(covariant CalTimeGrid old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _base = _periodStart(widget.anchor);
      _pc.dispose();
      _pc = PageController(initialPage: calPageBase);
      return;
    }
    // Jumped elsewhere (today button, week strip, other view): show that page.
    final page = _pc.hasClients ? (_pc.page ?? calPageBase.toDouble()).round() : calPageBase;
    final shown = _pageStart(page);
    final a = calDay(widget.anchor);
    if (a.isBefore(shown) || !a.isBefore(shown.add(Duration(days: _days)))) {
      final target = calPageBase + (_periodStart(a).difference(_base).inDays / _days).round();
      if (_pc.hasClients) _pc.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pc,
      onPageChanged: (p) {
        HapticFeedback.selectionClick();
        final s = _pageStart(p);
        // Day/3-day: the first day shown; week: same weekday as before.
        widget.onAnchor(widget.view == CalView.week ? s.add(Duration(days: widget.anchor.weekday % 7)) : s);
      },
      itemBuilder: (context, p) {
        final start = _pageStart(p);
        final days = [for (var i = 0; i < _days; i++) start.add(Duration(days: i))];
        widget.store.ensure(days.first, days.last);
        return _GridPage(
          key: ValueKey('grid-${calKey(start)}-$_days'),
          days: days,
          parent: this,
        );
      },
    );
  }
}

class _GridPage extends StatefulWidget {
  const _GridPage({super.key, required this.days, required this.parent});
  final List<DateTime> days;
  final CalTimeGridState parent;

  @override
  State<_GridPage> createState() => _GridPageState();
}

enum _DragKind { move, resize }

class _GridPageState extends State<_GridPage> {
  late final _scroll = ScrollController(initialScrollOffset: widget.parent._vOffset);
  final _stackKey = GlobalKey();
  final _viewportKey = GlobalKey();

  CalEvent? _drag;
  _DragKind? _kind;
  double _grabMin = 0;
  DateTime? _gStart;
  DateTime? _gEnd;

  CalTimeGrid get w => widget.parent.widget;
  static const hH = CalTimeGrid.hourH;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Offset? _local(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  double get _colW {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return (box?.size.width ?? 300) / widget.days.length;
  }

  int _snap(double minutes, int step) => ((minutes / step).round() * step).clamp(0, 24 * 60);

  void _autoScroll(Offset global) {
    final vp = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (vp == null || !_scroll.hasClients) return;
    final y = vp.globalToLocal(global).dy;
    double dy = 0;
    if (y < 48) dy = -14;
    if (y > vp.size.height - 48) dy = 14;
    if (dy != 0) _scroll.jumpTo((_scroll.offset + dy).clamp(0, _scroll.position.maxScrollExtent));
  }

  void _startMove(CalEvent e, Offset global) {
    final p = _local(global);
    if (p == null) return;
    final dayIdx = widget.days.indexWhere((d) => sameDay(d, e.start)).clamp(0, widget.days.length - 1);
    final startMin = e.start.hour * 60 + e.start.minute;
    _grabMin = p.dy / hH * 60 - (sameDay(e.start, widget.days[dayIdx]) ? startMin : 0);
    HapticFeedback.mediumImpact();
    setState(() {
      _drag = e;
      _kind = _DragKind.move;
      _gStart = e.start;
      _gEnd = e.end;
    });
  }

  void _updateMove(Offset global) {
    final e = _drag;
    final p = _local(global);
    if (e == null || p == null) return;
    _autoScroll(global);
    final dayIdx = (p.dx / _colW).floor().clamp(0, widget.days.length - 1);
    final dur = e.end.difference(e.start).inMinutes;
    final m = _snap(p.dy / hH * 60 - _grabMin, 15).clamp(0, 24 * 60 - 15);
    final s = widget.days[dayIdx].add(Duration(minutes: m));
    if (s != _gStart) {
      HapticFeedback.selectionClick();
      setState(() {
        _gStart = s;
        _gEnd = s.add(Duration(minutes: dur));
      });
    }
  }

  double _resizeFromY = 0;

  void _startResize(CalEvent e, Offset global) {
    _resizeFromY = _local(global)?.dy ?? 0;
    HapticFeedback.mediumImpact();
    setState(() {
      _drag = e;
      _kind = _DragKind.resize;
      _gStart = e.start;
      _gEnd = e.end;
    });
  }

  void _updateResize(Offset global) {
    final e = _drag;
    final p = _local(global);
    if (e == null || p == null) return;
    _autoScroll(global);
    // By the distance dragged (grabbing the edge never jumps), 15-min steps,
    // at least 15 minutes, not past midnight of its day.
    final delta = ((p.dy - _resizeFromY) / hH * 60 / 15).round() * 15;
    var end = e.end.add(Duration(minutes: delta));
    final dayEnd = calDay(e.start).add(const Duration(days: 1));
    if (end.isAfter(dayEnd)) end = dayEnd;
    if (!end.isAfter(e.start.add(const Duration(minutes: 14)))) end = e.start.add(const Duration(minutes: 15));
    if (end != _gEnd) {
      HapticFeedback.selectionClick();
      setState(() => _gEnd = end);
    }
  }

  Future<void> _finish() async {
    final e = _drag;
    final s = _gStart;
    final en = _gEnd;
    setState(() {
      _drag = null;
      _kind = null;
    });
    if (e == null || s == null || en == null) return;
    if (s == e.start && en == e.end) return;
    await w.onReschedule(e, s, en);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final days = widget.days;
    final today = thaiNow();
    return ListenableBuilder(
      listenable: w.store,
      builder: (context, _) {
        final perDay = [for (final d in days) w.store.on(d)];
        final allDay = [for (final l in perDay) [for (final e in l) if (e.allDay || e.multiDay) e]];
        final bdays = [for (final d in days) w.store.birthdays.on(d)];
        final hasAllDay = allDay.any((l) => l.isNotEmpty) || bdays.any((l) => l.isNotEmpty);
        return Column(
          children: [
            if (w.view == CalView.day) _weekStrip(context, days.first, today) else _dayHeaders(context, days, today),
            if (hasAllDay) _allDayRow(context, days, allDay, bdays),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.vertical) widget.parent._vOffset = n.metrics.pixels;
                  return false;
                },
                child: SingleChildScrollView(
                  key: _viewportKey,
                  controller: _scroll,
                  physics: _drag != null ? const NeverScrollableScrollPhysics() : null,
                  padding: const EdgeInsets.only(bottom: 120),
                  child: SizedBox(
                    height: 24 * hH,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: CalTimeGrid.gutter,
                          child: Stack(children: [
                            for (var h = 1; h < 24; h++)
                              Positioned(
                                top: h * hH - 7,
                                right: 6,
                                child: Text('${h.toString().padLeft(2, '0')}:00', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
                              ),
                          ]),
                        ),
                        Expanded(
                          child: LayoutBuilder(builder: (context, box) {
                            final colW = box.maxWidth / days.length;
                            return Stack(
                              key: _stackKey,
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    key: const ValueKey('cal-grid-empty'),
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (d) {
                                      final i = (d.localPosition.dx / colW).floor().clamp(0, days.length - 1);
                                      final m = _snap(d.localPosition.dy / hH * 60 - 15, 30).clamp(0, 23 * 60 + 30);
                                      HapticFeedback.selectionClick();
                                      w.onCreateAt(days[i].add(Duration(minutes: m)));
                                    },
                                    child: CustomPaint(painter: _GridPainter(days: days.length, hourH: hH, color: cs.outlineVariant.withValues(alpha: 0.45))),
                                  ),
                                ),
                                for (var i = 0; i < days.length; i++) ..._blocks(context, days[i], i, colW, perDay[i]),
                                // Now line
                                for (var i = 0; i < days.length; i++)
                                  if (sameDay(days[i], today)) ...[
                                    Positioned(
                                      left: i * colW,
                                      width: colW,
                                      top: (today.hour * 60 + today.minute) / 60 * hH - 1,
                                      child: IgnorePointer(child: Container(height: 2, color: const Color(0xFFEF4444))),
                                    ),
                                    Positioned(
                                      left: i * colW - 4,
                                      top: (today.hour * 60 + today.minute) / 60 * hH - 4,
                                      child: IgnorePointer(
                                        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                                      ),
                                    ),
                                  ],
                                if (_drag != null && _gStart != null && _gEnd != null) _ghost(context, colW),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _blocks(BuildContext context, DateTime day, int i, double colW, List<CalEvent> events) {
    final timed = [for (final e in events) if (!e.allDay && !e.multiDay) e];
    final layout = layoutOverlaps(timed);
    return [
      for (final e in timed)
        () {
          final (col, n) = layout[e]!;
          final top = (e.start.hour * 60 + e.start.minute) / 60 * hH;
          final h = (e.minutes / 60 * hH).clamp(20.0, 24 * hH - top);
          final width = colW / (n == 0 ? 1 : n);
          final dragging = _drag?.id == e.id;
          return Positioned(
            key: ValueKey('cal-block-${e.id}'),
            left: i * colW + col * width + 1,
            width: width - 2,
            top: top + 1,
            height: h - 2,
            child: Opacity(
              opacity: dragging ? 0.35 : 1,
              child: _EventBlock(
                event: e,
                compact: widget.days.length > 3,
                onTap: () => w.onOpen(e),
                onLongPressStart: (d) => _startMove(e, d.globalPosition),
                onLongPressMove: (d) => _updateMove(d.globalPosition),
                onLongPressEnd: (_) => _finish(),
                onResizeStart: (d) => _startResize(e, d.globalPosition),
                onResizeUpdate: (d) => _updateResize(d.globalPosition),
                onResizeEnd: _finish,
              ),
            ),
          );
        }(),
    ];
  }

  Widget _ghost(BuildContext context, double colW) {
    final e = _drag!;
    final s = _gStart!;
    final en = _gEnd!;
    final i = widget.days.indexWhere((d) => sameDay(d, s)).clamp(0, widget.days.length - 1);
    final top = (s.hour * 60 + s.minute) / 60 * hH;
    final h = (en.difference(s).inMinutes / 60 * hH).clamp(20.0, 24 * hH - top);
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: i * colW + 1,
      width: colW - 2,
      top: top,
      height: h,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: e.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
            border: Border.all(color: cs.surface, width: 1.5),
          ),
          child: Text(
            '${hm(s)}–${hm(en)}${_kind == _DragKind.resize ? '  ·  ${formatDur(en.difference(s))}' : ''}',
            key: const ValueKey('cal-ghost-label'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
          ),
        ),
      ),
    );
  }

  Widget _dayHeaders(BuildContext context, List<DateTime> days, DateTime today) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: CalTimeGrid.gutter, top: 4, bottom: 6),
      child: Row(children: [
        for (final d in days)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => w.onOpenDay(d),
              child: Column(children: [
                Text(weekdayShort(d), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: sameDay(d, today) ? cs.primary : Colors.transparent, shape: BoxShape.circle),
                  child: Text(
                    '${d.day}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: sameDay(d, today) ? cs.onPrimary : cs.onSurface),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Day view: the whole week as a strip, the shown day ringed.
  Widget _weekStrip(BuildContext context, DateTime day, DateTime today) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ws = weekStart(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (_) {
            final d = ws.add(Duration(days: i));
            final sel = sameDay(d, day);
            final isToday = sameDay(d, today);
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  w.onAnchor(d);
                },
                child: Column(children: [
                  Text(weekdayShort(d), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isToday ? cs.primary : Colors.transparent,
                      shape: BoxShape.circle,
                      border: sel && !isToday ? Border.all(color: cs.primary, width: 1.6) : null,
                    ),
                    child: Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? cs.onPrimary : (sel ? cs.primary : cs.onSurface))),
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  Widget _allDayRow(BuildContext context, List<DateTime> days, List<List<CalEvent>> allDay, List<List<CalBirthday>> bdays) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const maxShown = 2; // two chips, then "+N" (as in the reference)
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: CalTimeGrid.gutter,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Text(tr('ทั้งวัน'), textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
            ),
          ),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Birthdays (pink, first) then all-day activities; past two → "+N".
                  ...() {
                    final items = <Widget Function()>[
                      for (final b in bdays[i])
                        () => Builder(
                              builder: (c) => _chip(
                                context,
                                '🎂 ${b.name}',
                                calBirthdayColor,
                                () => w.store.openBirthday(c, b, days[i]),
                                key: ValueKey('cal-bday-chip-${b.module}-${b.id}'),
                              ),
                            ),
                      for (final e in allDay[i]) () => _chip(context, e.title, e.color, () => w.onOpen(e)),
                    ];
                    final over = items.length > maxShown;
                    return [
                      for (final f in items.take(over ? maxShown - 1 : maxShown)) f(),
                      if (over)
                        Builder(
                          builder: (chipCtx) => _chip(
                            context,
                            '+${items.length - (maxShown - 1)}',
                            cs.primary,
                            () {
                              final box = chipCtx.findRenderObject() as RenderBox?;
                              showCalDayPopover(
                                context,
                                day: days[i],
                                events: w.store.on(days[i]),
                                birthdays: bdays[i],
                                onBirthday: (b) => w.store.onBirthday?.call(b, days[i], null),
                                onOpen: w.onOpen,
                                anchor: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                              );
                            },
                            key: ValueKey('cal-more-${calKey(days[i])}'),
                            center: true,
                          ),
                        ),
                    ];
                  }(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text, Color color, VoidCallback onTap, {Key? key, bool center = false}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(1, 1, 1, 1),
      child: Material(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color.lerp(color, Colors.black, 0.35)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "1 ชม. 30 นาที" / "1h 30m".
String formatDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (L10n.isEn) return [if (h > 0) '${h}h', if (m > 0) '${m}m'].join(' ');
  return [if (h > 0) '$h ชม.', if (m > 0) '$m นาที'].join(' ');
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({
    required this.event,
    required this.compact,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final CalEvent event;
  final bool compact;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMove;
  final GestureLongPressEndCallback onLongPressEnd;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final fg = Color.lerp(e.color, Colors.black, 0.45)!;
    return LayoutBuilder(builder: (context, box) {
      final tall = box.maxHeight >= 34;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onTap,
              onLongPressStart: onLongPressStart,
              onLongPressMoveUpdate: onLongPressMove,
              onLongPressEnd: onLongPressEnd,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 3, 4, 3),
                decoration: BoxDecoration(
                  color: e.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: e.color, width: 3)),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, maxLines: box.maxHeight >= 64 ? 2 : 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w700, color: fg)),
                    if (tall && !compact) Text('${hm(e.start)}–${hm(e.end)}', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ),
          ),
          // Bottom edge: drag to make it longer/shorter.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 14,
            child: GestureDetector(
              key: ValueKey('cal-resize-${e.id}'),
              behavior: HitTestBehavior.opaque,
              // Count the movement from the touch point (a quick flick still resizes).
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: onResizeStart,
              onVerticalDragUpdate: onResizeUpdate,
              onVerticalDragEnd: (_) => onResizeEnd(),
              child: Center(
                child: Container(width: 18, height: 3, decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.days, required this.hourH, required this.color});
  final int days;
  final double hourH;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    for (var h = 0; h <= 24; h++) {
      canvas.drawLine(Offset(0, h * hourH), Offset(size.width, h * hourH), p);
    }
    final half = Paint()
      ..color = color.withValues(alpha: color.a * 0.4)
      ..strokeWidth = 0.5;
    for (var h = 0; h < 24; h++) {
      canvas.drawLine(Offset(0, h * hourH + hourH / 2), Offset(size.width, h * hourH + hourH / 2), half);
    }
    final cw = size.width / days;
    for (var i = 0; i <= days; i++) {
      canvas.drawLine(Offset(i * cw, 0), Offset(i * cw, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.days != days || old.color != color || old.hourH != hourH;
}
