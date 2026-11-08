import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_overlay_panel.dart';
import 'cal_model.dart';

/// One appointment row: time column (or "ทั้งวัน"), colour bar, title,
/// place / type. Used by the month list, the agenda and the day popover.
class CalEventTile extends StatelessWidget {
  const CalEventTile({super.key, required this.event, this.onTap, this.onLongPress, this.day});

  final CalEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The day the row is listed under (multi-day events show "ต่อ" times).
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final e = event;
    final d = day ?? e.start;
    final startsToday = sameDay(e.start, d);
    final endsToday = sameDay(e.end.subtract(const Duration(minutes: 1)), d);
    final sub = [
      if (e.location.isNotEmpty) e.location,
      if (e.type.isNotEmpty) tr(e.type),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: e.allDay
                  ? Text(tr('ทั้งวัน'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(startsToday ? hm(e.start) : tr('ต่อ'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(endsToday ? hm(e.end) : '…', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
            ),
            Container(
              width: 3,
              height: sub.isEmpty ? 20 : 36,
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: e.status.toLowerCase() == 'cancelled' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (e.checkedIn) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(NxI.mapPin, size: 16, color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

/// Rows grouped on one rounded card with hairline dividers (as in the
/// reference design's day list).
class CalCard extends StatelessWidget {
  const CalCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 72, color: cs.outlineVariant.withValues(alpha: 0.5)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Floating card with the day's appointments, growing out of [anchor]
/// (the "+N" / day the user tapped) — like the reference "11 พฤศจิกายน".
Future<void> showCalDayPopover(
  BuildContext context, {
  required DateTime day,
  required List<CalEvent> events,
  required void Function(CalEvent e) onOpen,
  Rect? anchor,
}) {
  return showNxBlurPanel<void>(
    context: context,
    anchor: anchor,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              L10n.isEn ? '${day.day} ${monthName(day.month)} · ${weekdayLong(day)}' : '${day.day} ${monthName(day.month)} ${weekdayLong(day)}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (events.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(tr('ไม่มีกิจกรรม'))),
          for (final e in events)
            CalEventTile(
              event: e,
              day: day,
              onTap: () {
                Navigator.pop(ctx);
                onOpen(e);
              },
            ),
          const SizedBox(height: 6),
        ],
      );
    },
  );
}

/// Small round "today" button (shows today's date) to jump back.
class CalTodayButton extends StatelessWidget {
  const CalTodayButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        key: const ValueKey('cal-today'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: cs.primary, width: 1.6), borderRadius: BorderRadius.circular(6)),
              child: Text('${thaiNow().day}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary)),
            ),
          ),
        ),
      ),
    );
  }
}
