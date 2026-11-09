import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'nx_avatar.dart';

/// One row of a history timeline.
class NxTimelineEntry {
  const NxTimelineEntry({
    required this.at,
    required this.icon,
    required this.title,
    this.body,
    this.who,
    this.whoImage,
    this.chip,
    this.color,
  });

  /// When it happened, in Thai time (null = unknown, shown without a date).
  final DateTime? at;
  final IconData icon;
  final Widget title;
  final Widget? body;

  /// Who did it (avatar on the right).
  final String? who;
  final String? whoImage;

  /// Small pill under the text; defaults to the time (HH:mm).
  final String? chip;
  final Color? color;
}

const _thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Modern history timeline: a date badge (day + month) at the start of each
/// day, a year marker when the year changes, a dotted rail with a dot per
/// entry, the text, a time pill and the person's avatar.
class NxTimeline extends StatelessWidget {
  const NxTimeline({super.key, required this.entries, this.now});

  /// Newest first.
  final List<NxTimelineEntry> entries;

  /// "Today" for the year marker (tests); defaults to the clock.
  final DateTime? now;

  static String two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final thisYear = (now ?? DateTime.now()).year;
    final rows = <Widget>[];
    DateTime? prevDay;
    int? prevYear = thisYear;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final at = e.at;
      final day = at == null ? null : DateTime(at.year, at.month, at.day);
      if (at != null && at.year != prevYear) {
        rows.add(_YearMarker(year: at.year));
        prevYear = at.year;
      }
      final firstOfDay = day != null && day != prevDay;
      prevDay = day ?? prevDay;
      rows.add(_Row(
        key: ValueKey('timeline-$i'),
        entry: e,
        showDate: firstOfDay,
        last: i == entries.length - 1,
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _YearMarker extends StatelessWidget {
  const _YearMarker({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 2, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text('${uiYear(year)}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.entry, required this.showDate, required this.last});
  final NxTimelineEntry entry;
  final bool showDate;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = entry.color ?? cs.primary;
    final at = entry.at;
    final chip = entry.chip ?? (at == null ? null : '${NxTimeline.two(at.hour)}:${NxTimeline.two(at.minute)}');
    final months = L10n.isEn ? _enMonths : _thMonths;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date badge (only on the first entry of a day).
          SizedBox(
            width: 46,
            child: Align(
              alignment: Alignment.topCenter,
              child: showDate && at != null
                  ? Container(
                      width: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: double.infinity,
                          color: accent,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          alignment: Alignment.center,
                          child: Text(
                            NxTimeline.two(at.day),
                            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(months[at.month - 1], style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    )
                  : null,
            ),
          ),
          // Rail: dot + dotted line down to the next entry.
          SizedBox(
            width: 24,
            child: Column(children: [
              const SizedBox(height: 4),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: showDate ? accent : cs.outline, width: 2),
                  color: theme.scaffoldBackgroundColor,
                ),
              ),
              if (!last) Expanded(child: CustomPaint(painter: _DottedLine(color: cs.outlineVariant), size: const Size(2, double.infinity))),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 6),
                            child: Icon(entry.icon, size: 15, color: accent),
                          ),
                          Expanded(child: DefaultTextStyle.merge(style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), child: entry.title)),
                        ]),
                        if (entry.body != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant), child: entry.body!),
                          ),
                        if (chip != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                              child: Text(chip, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if ((entry.who ?? '').trim().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Tooltip(message: entry.who!, child: NxAvatar(label: entry.who!, size: 30, imageUrl: entry.whoImage)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLine extends CustomPainter {
  _DottedLine({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    for (double y = 4; y < size.height - 2; y += 7) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + 3).clamp(0, size.height)), p);
    }
  }

  @override
  bool shouldRepaint(_DottedLine old) => old.color != color;
}
