import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../widgets/nx_icons.dart';

/// Brand colours of ไอแซคบันทึกประชุม (indigo → violet, like the other ISAAC screens).
const kMinuteGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]);
const kMinuteRecord = Color(0xFFE11D48);

IconData minuteSourceIcon(MinuteMeeting m) => switch (m.source) {
  'room' => NxI.users,
  'upload' => m.video ? NxI.videoCamera : NxI.uploadSimple,
  _ => m.video ? NxI.videoCamera : NxI.microphone,
};

Color minuteSourceColor(String source) => switch (source) {
  'room' => const Color(0xFF0EA5E9),
  'upload' => const Color(0xFF10B981),
  _ => kMinuteRecord,
};

/// Status pill: live (red dot), processing (progress), ready, failed.
class MinuteStatusChip extends StatelessWidget {
  const MinuteStatusChip({super.key, required this.meeting});
  final MinuteMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = meeting;
    final (Color bg, Color fg) = switch (m.status) {
      'live' || 'paused' => (kMinuteRecord.withValues(alpha: 0.12), kMinuteRecord),
      'ready' => (const Color(0xFF10B981).withValues(alpha: 0.12), const Color(0xFF047857)),
      'failed' => (cs.errorContainer, cs.onErrorContainer),
      _ => (cs.primary.withValues(alpha: 0.10), cs.primary),
    };
    final label = tr(minuteStatusLabel(m.status, stage: m.stage));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.status == 'live') ...[Container(width: 6, height: 6, decoration: const BoxDecoration(color: kMinuteRecord, shape: BoxShape.circle)), const SizedBox(width: 5)],
          if (m.busy) ...[SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg)), const SizedBox(width: 5)],
          Text(m.busy && m.progress > 0 ? '$label ${m.progress}%' : label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Chips to pick languages (multi) — translation targets.
class MinuteLangChips extends StatelessWidget {
  const MinuteLangChips({super.key, required this.selected, required this.onChanged, this.exclude = const {}, this.single = false});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final Set<String> exclude;
  final bool single;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in kMinuteLangs.entries)
          if (!exclude.contains(e.key))
            FilterChip(
              key: ValueKey('minute-lang-${e.key}'),
              label: Text(tr(e.value)),
              selected: selected.contains(e.key),
              visualDensity: VisualDensity.compact,
              onSelected: (on) {
                if (single) return onChanged(on ? [e.key] : const []);
                final next = [...selected];
                on ? next.add(e.key) : next.remove(e.key);
                onChanged(next);
              },
            ),
      ],
    );
  }
}

/// Template picker (single choice) with a short hint under each.
class MinuteTemplatePicker extends StatelessWidget {
  const MinuteTemplatePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in kMinuteTemplates.entries)
          ChoiceChip(
            key: ValueKey('minute-template-${e.key}'),
            label: Text(tr(e.value.$1)),
            tooltip: tr(e.value.$2),
            selected: value == e.key,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(e.key),
            labelStyle: theme.textTheme.labelMedium,
          ),
      ],
    );
  }
}

/// Section title inside sheets / forms.
class MinuteSectionTitle extends StatelessWidget {
  const MinuteSectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: theme.colorScheme.primary), const SizedBox(width: 6)],
          Expanded(child: Text(tr(text), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ],
      ),
    );
  }
}

/// "12 พ.ย. 14:05" (Bangkok wall clock of the device).
String minuteWhen(DateTime? t) {
  if (t == null) return '';
  const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${tr(months[t.month - 1])} $hh:$mm';
}
