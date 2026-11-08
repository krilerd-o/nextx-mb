import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/nx_icons.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';
import 'cal_store.dart';
import 'cal_widgets.dart';

/// Month grid over the selected day's list. Scrolling the list up folds the
/// month into the selected week (animated, like the reference design);
/// pulling down — or tapping the handle — opens it again. Swipe sideways to
/// change month (or week while folded).
class CalMonthView extends StatefulWidget {
  const CalMonthView({
    super.key,
    required this.store,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onEventMenu,
    required this.onCreate,
  });

  final CalStore store;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final void Function(CalEvent e) onOpen;
  final void Function(CalEvent e) onEventMenu;
  final ValueChanged<DateTime> onCreate;

  static const double rowH = 50;
  static const double dowH = 28;

  @override
  State<CalMonthView> createState() => CalMonthViewState();
}

class CalMonthViewState extends State<CalMonthView> {
  final _scroll = ScrollController();
  int _dir = 1; // slide direction of the last swipe
  int _swipes = 0; // keys the slide animation (only swipes animate, not folding)

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// First Sunday shown and number of week rows for [month].
  static (DateTime, int) gridOf(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final start = weekStart(first);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((first.weekday % 7 + days) / 7).ceil();
    return (start, rows);
  }

  double get collapse {
    if (!_scroll.hasClients) return 0;
    final (_, rows) = gridOf(widget.selected);
    final range = (rows - 1) * CalMonthView.rowH;
    return range <= 0 ? 0 : (_scroll.offset / range).clamp(0.0, 1.0);
  }

  void toggle() {
    final (_, rows) = gridOf(widget.selected);
    final range = (rows - 1) * CalMonthView.rowH;
    HapticFeedback.selectionClick();
    _scroll.animateTo(collapse > 0.5 ? 0 : range, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
  }

  void _swipe(double v) {
    if (v.abs() < 250) return;
    final folded = collapse > 0.5;
    final s = widget.selected;
    final step = v < 0 ? 1 : -1;
    _dir = step;
    _swipes++;
    HapticFeedback.selectionClick();
    if (folded) {
      widget.onSelect(s.add(Duration(days: 7 * step)));
    } else {
      final m = DateTime(s.year, s.month + step, 1);
      final today = thaiNow();
      widget.onSelect(m.year == today.year && m.month == today.month ? calDay(today) : m);
    }
  }

  bool _onEnd(ScrollEndNotification n) {
    // Settle fully open or fully folded.
    final (_, rows) = gridOf(widget.selected);
    final range = (rows - 1) * CalMonthView.rowH;
    final o = _scroll.offset;
    if (o > 0 && o < range) {
      final to = o > range / 2 ? range : 0.0;
      Future.microtask(() => _scroll.animateTo(to, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sel = widget.selected;
    final (start, rows) = gridOf(sel);
    widget.store.ensure(start, start.add(Duration(days: rows * 7)));
    // Grid + the handle under it (pinned with the folded week, as in the reference).
    const handleH = 20.0;
    final maxExt = CalMonthView.dowH + rows * CalMonthView.rowH + handleH;
    final minExt = CalMonthView.dowH + CalMonthView.rowH + handleH;
    final today = thaiNow();
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final events = widget.store.on(sel);
        final bdays = widget.store.birthdays.on(sel);
        return LayoutBuilder(builder: (context, box) {
          return NotificationListener<ScrollEndNotification>(
            onNotification: _onEnd,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _GridHeader(
                    minExt: minExt,
                    maxExt: maxExt,
                    color: theme.scaffoldBackgroundColor,
                    builder: (t) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onHorizontalDragEnd: (d) => _swipe(d.primaryVelocity ?? 0),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, a) => SlideTransition(
                              position: Tween(begin: Offset(0.25 * _dir, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: KeyedSubtree(
                              key: ValueKey('swipe-$_swipes'),
                              child: _grid(context, sel, start, rows, t, today),
                            ),
                          ),
                        ),
                        GestureDetector(
                          key: const ValueKey('cal-month-handle'),
                          onTap: toggle,
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            height: handleH,
                            child: Center(
                              // A bar while open, a chevron while folded (tap to open).
                              child: t > 0.9
                                  ? Icon(NxI.caretDown, size: 18, color: cs.outline)
                                  : Container(width: 36, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              sameDay(sel, today) ? tr('วันนี้') : dayHeading(sel),
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (bdays.isNotEmpty) ...[
                            const Icon(NxI.cakeFill, size: 14, color: calBirthdayColor),
                            const SizedBox(width: 3),
                            Text('${bdays.length}', style: theme.textTheme.labelMedium?.copyWith(color: calBirthdayColor, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 10),
                          ],
                          if (events.isNotEmpty) Text(tr('${events.length} กิจกรรม'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ],
                  ),
                ),
                if (bdays.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CalCard(children: [
                        for (final b in bdays)
                          Builder(builder: (c) => CalBirthdayTile(b: b, day: sel, onTap: () => widget.store.openBirthday(c, b, sel))),
                      ]),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: events.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(children: [
                            Icon(NxI.calendarBlank, size: 36, color: cs.outline),
                            const SizedBox(height: 8),
                            Text(tr('ไม่มีกิจกรรม'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            TextButton.icon(
                              onPressed: () => widget.onCreate(sel),
                              icon: const Icon(NxI.plus, size: 18),
                              label: Text(tr('เพิ่มกิจกรรม')),
                            ),
                          ]),
                        )
                      : CalCard(children: [
                          for (final e in events)
                            CalEventTile(event: e, day: sel, onTap: () => widget.onOpen(e), onLongPress: () => widget.onEventMenu(e)),
                        ]),
                ),
                // Room so even a short day can fold the month.
                SliverToBoxAdapter(child: SizedBox(height: (box.maxHeight - minExt - 60).clamp(120.0, 2000.0))),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _grid(BuildContext context, DateTime sel, DateTime start, int rows, double t, DateTime today) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selRow = calDay(sel).difference(start).inDays ~/ 7;
    final counts = <String, List<Color>>{};
    for (final e in widget.store.between(start, start.add(Duration(days: rows * 7)))) {
      for (var d = calDay(e.start); d.isBefore(e.end) && d.isBefore(start.add(Duration(days: rows * 7))); d = d.add(const Duration(days: 1))) {
        (counts[calKey(d)] ??= []).add(e.color);
      }
    }
    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: CalMonthView.dowH,
            child: Row(children: [
              for (final w in weekHeaders)
                Expanded(child: Center(child: Text(w, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)))),
            ]),
          ),
          for (var r = 0; r < rows; r++)
            SizedBox(
              // The selected week stays; the others fold away with the scroll.
              height: r == selRow ? CalMonthView.rowH : CalMonthView.rowH * (1 - t),
              child: Opacity(
                opacity: r == selRow ? 1 : (1 - t * 1.6).clamp(0.0, 1.0),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: CalMonthView.rowH,
                  maxHeight: CalMonthView.rowH,
                  child: Row(children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(child: _day(context, start.add(Duration(days: r * 7 + c)), sel, today, counts)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _day(BuildContext context, DateTime d, DateTime sel, DateTime today, Map<String, List<Color>> counts) {
    final cs = Theme.of(context).colorScheme;
    final inMonth = d.month == sel.month;
    final isSel = sameDay(d, sel);
    final isToday = sameDay(d, today);
    final dots = counts[calKey(d)] ?? const [];
    final bday = widget.store.birthdays.on(d).isNotEmpty;
    return InkWell(
      key: ValueKey('cal-day-${calKey(d)}'),
      customBorder: const CircleBorder(),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onSelect(d);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSel ? cs.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isSel ? Border.all(color: cs.primary, width: 1.4) : null,
            ),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSel || isToday ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? cs.onPrimary : (isToday ? cs.primary : (inMonth ? cs.onSurface : cs.outline)),
                ),
              ),
              // Someone's birthday: a small pink cake on the corner of the day.
              if (bday)
                Positioned(
                  key: ValueKey('cal-bday-mark-${calKey(d)}'),
                  right: -9,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
                    child: Icon(NxI.cakeFill, size: 11, color: inMonth ? calBirthdayColor : calBirthdayColor.withValues(alpha: 0.45)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in dots.take(3))
                  Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridHeader extends SliverPersistentHeaderDelegate {
  _GridHeader({required this.minExt, required this.maxExt, required this.builder, required this.color});
  final double minExt;
  final double maxExt;
  final Color color;
  final Widget Function(double t) builder;

  @override
  double get minExtent => minExt;
  @override
  double get maxExtent => maxExt;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExt - minExt;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // Laid out at its natural height and clipped to the header (a grid still
    // sliding out may be taller than the folded header).
    return ColoredBox(
      color: color,
      child: SizedBox(
        height: (maxExt - shrinkOffset).clamp(minExt, maxExt),
        child: ClipRect(
          child: OverflowBox(alignment: Alignment.topCenter, minHeight: 0, maxHeight: double.infinity, child: builder(t)),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _GridHeader old) => true;
}
