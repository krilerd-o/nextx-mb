import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/nx_icons.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';
import 'cal_store.dart';
import 'cal_widgets.dart';

/// "รายการ" — appointments grouped by day (as the reference "ตารางเวลา"),
/// from the anchor day onward; more months load as you reach the end, and
/// earlier ones on demand. With [events] it lists those instead (upcoming /
/// overdue modes).
class CalAgendaView extends StatefulWidget {
  const CalAgendaView({
    super.key,
    required this.store,
    required this.anchor,
    required this.onOpen,
    required this.onEventMenu,
    this.events,
    this.header,
  });

  final CalStore store;
  final DateTime anchor;
  final void Function(CalEvent e) onOpen;
  final void Function(CalEvent e) onEventMenu;

  /// Fixed list (upcoming / overdue) instead of the calendar range.
  final List<CalEvent>? events;
  final Widget? header;

  @override
  State<CalAgendaView> createState() => _CalAgendaViewState();
}

class _CalAgendaViewState extends State<CalAgendaView> {
  int _back = 0; // months shown before the anchor
  int _ahead = 2; // months shown after it

  DateTime get _from {
    final a = widget.anchor;
    return _back == 0 ? calDay(a) : DateTime(a.year, a.month - _back, 1);
  }

  DateTime get _to => DateTime(widget.anchor.year, widget.anchor.month + _ahead + 1, 1);

  @override
  void didUpdateWidget(covariant CalAgendaView old) {
    super.didUpdateWidget(old);
    if (!sameDay(old.anchor, widget.anchor)) {
      _back = 0;
      _ahead = 2;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (widget.events == null && n.metrics.extentAfter < 600 && !widget.store.loading) {
      setState(() => _ahead++);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.events == null) widget.store.ensure(_from, _to);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final list = widget.events ?? widget.store.between(_from, _to);
        // Day → events (multi-day events listed under each day they cover).
        final days = <DateTime, List<CalEvent>>{};
        for (final e in list) {
          var d = calDay(e.start.isBefore(_from) && widget.events == null ? _from : e.start);
          final last = calDay(e.end.subtract(const Duration(minutes: 1)));
          var guard = 0;
          while (!d.isAfter(last) && guard++ < 31) {
            if (widget.events != null || (!d.isBefore(_from) && d.isBefore(_to))) (days[d] ??= []).add(e);
            d = d.add(const Duration(days: 1));
          }
        }
        // Birthdays in the range (calendar mode only) — a day with only birthdays still shows.
        final bdays = <DateTime, List<CalBirthday>>{};
        if (widget.events == null && widget.store.birthdays.enabled) {
          for (var d = _from; d.isBefore(_to); d = DateTime(d.year, d.month, d.day + 1)) {
            final l = widget.store.birthdays.on(d);
            if (l.isNotEmpty) {
              bdays[d] = l;
              days.putIfAbsent(d, () => []);
            }
          }
        }
        final keys = days.keys.toList()..sort(widget.events != null && list.isNotEmpty && list.first.start.isAfter(list.last.start) ? (a, b) => b.compareTo(a) : (a, b) => a.compareTo(b));
        final today = thaiNow();
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 140),
            children: [
              ?widget.header,
              if (widget.events == null)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _back++),
                    icon: const Icon(NxI.caretUp, size: 16),
                    label: Text(tr('ดูก่อนหน้า')),
                  ),
                ),
              if (keys.isEmpty && !widget.store.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(children: [
                    Icon(NxI.calendarBlank, size: 40, color: cs.outline),
                    const SizedBox(height: 8),
                    Text(tr('ไม่มีกิจกรรม'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              for (final d in keys) ...[
                Padding(
                  key: ValueKey('cal-agenda-${calKey(d)}'),
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
                  child: Text(
                    sameDay(d, today) ? '${tr('วันนี้')} · ${dayHeading(d)}' : dayHeading(d),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: sameDay(d, today) ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                CalCard(children: [
                  for (final b in bdays[d] ?? const <CalBirthday>[])
                    Builder(builder: (c) => CalBirthdayTile(b: b, day: d, onTap: () => widget.store.openBirthday(c, b, d))),
                  for (final e in days[d]!..sort((a, b) => a.allDay != b.allDay ? (a.allDay ? -1 : 1) : a.start.compareTo(b.start)))
                    CalEventTile(event: e, day: d, onTap: () => widget.onOpen(e), onLongPress: () => widget.onEventMenu(e)),
                ]),
              ],
              if (widget.store.loading && widget.events == null)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ),
        );
      },
    );
  }
}
