import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/thai_time.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';
import 'cal_store.dart';

/// Pages forever in both directions around [base] (page 1000 = base).
const int calPageBase = 1000;

/// Twelve small months; tapping one zooms into that month (the rect it was
/// tapped at is handed back so the switch can grow out of it).
class CalYearView extends StatefulWidget {
  const CalYearView({super.key, required this.store, required this.anchor, required this.onAnchor, required this.onOpenMonth});

  final CalStore store;
  final DateTime anchor;
  final ValueChanged<DateTime> onAnchor;
  final void Function(DateTime month, Rect from) onOpenMonth;

  @override
  State<CalYearView> createState() => _CalYearViewState();
}

class _CalYearViewState extends State<CalYearView> {
  late final int _baseYear = widget.anchor.year;
  late final _pc = PageController(initialPage: calPageBase);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _load(int year) => widget.store.ensure(DateTime(year, 1, 1), DateTime(year, 12, 31));

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pc,
      onPageChanged: (p) {
        HapticFeedback.selectionClick();
        final y = _baseYear + p - calPageBase;
        widget.onAnchor(DateTime(y, widget.anchor.month, 1));
      },
      itemBuilder: (context, p) {
        final year = _baseYear + p - calPageBase;
        _load(year);
        return ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth > 700 ? 4 : 3;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 10, childAspectRatio: 0.82),
              itemCount: 12,
              itemBuilder: (context, i) {
                final m = DateTime(year, i + 1, 1);
                return Builder(
                  builder: (cellCtx) => InkWell(
                    key: ValueKey('cal-year-month-${i + 1}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final box = cellCtx.findRenderObject() as RenderBox?;
                      final r = box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
                      HapticFeedback.selectionClick();
                      widget.onOpenMonth(m, r);
                    },
                    child: CalMiniMonth(month: m, counts: widget.store.countsIn(m), isBirthday: (d) => widget.store.birthdays.on(d).isNotEmpty),
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}

/// A month at thumbnail size: name, weekday initials and days; today is a
/// filled circle, days with appointments are bold in the accent colour.
class CalMiniMonth extends StatelessWidget {
  const CalMiniMonth({super.key, required this.month, this.counts = const {}, this.dense = true, this.isBirthday});

  final DateTime month;
  final Map<String, int> counts;
  final bool dense;

  /// Days with a customer birthday are drawn in pink.
  final bool Function(DateTime day)? isBirthday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = thaiNow();
    final isThisMonth = month.year == today.year && month.month == today.month;
    final first = DateTime(month.year, month.month, 1);
    final lead = first.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final size = dense ? 9.0 : 11.0;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            monthName(month.month),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: isThisMonth ? cs.primary : null),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final cw = box.maxWidth / 7;
              final rows = ((lead + days) / 7).ceil() + 1;
              final ch = box.maxHeight / rows;
              Widget cell(Widget child) => SizedBox(width: cw, height: ch, child: Center(child: child));
              return Wrap(
                children: [
                  for (final w in weekHeaders) cell(Text(w, style: TextStyle(fontSize: size - 2, color: cs.onSurfaceVariant))),
                  for (var i = 0; i < lead; i++) cell(const SizedBox()),
                  for (var d = 1; d <= days; d++)
                    cell(() {
                      final date = DateTime(month.year, month.month, d);
                      final isToday = sameDay(date, today);
                      final has = (counts[calKey(date)] ?? 0) > 0;
                      final bday = isBirthday?.call(date) ?? false;
                      final t = Text(
                        '$d',
                        style: TextStyle(
                          fontSize: size,
                          height: 1,
                          fontWeight: has || bday || isToday ? FontWeight.w800 : FontWeight.w500,
                          color: isToday ? cs.onPrimary : (bday ? calBirthdayColor : (has ? cs.primary : cs.onSurface)),
                        ),
                      );
                      if (!isToday) return t;
                      return Container(
                        width: ch.clamp(10.0, cw),
                        height: ch.clamp(10.0, cw),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                        child: t,
                      );
                    }()),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
