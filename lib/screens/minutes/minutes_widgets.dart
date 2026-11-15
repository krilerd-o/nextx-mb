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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final e in kMinuteLangs.entries)
            if (!exclude.contains(e.key))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  key: ValueKey('minute-lang-${e.key}'),
                  label: Text(tr(e.value)),
                  selected: selected.contains(e.key),
                  showCheckmark: !single,
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) {
                    if (single) return onChanged(on ? [e.key] : const []);
                    final next = [...selected];
                    on ? next.add(e.key) : next.remove(e.key);
                    onChanged(next);
                  },
                ),
              ),
        ],
      ),
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
    final cs = theme.colorScheme;
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final e in kMinuteTemplates.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                key: ValueKey('minute-template-${e.key}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 150,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: value == e.key ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: Border.all(color: value == e.key ? cs.primary : Colors.transparent, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr(e.value.$1), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: value == e.key ? cs.primary : null)),
                      const SizedBox(height: 2),
                      Text(tr(e.value.$2), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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

/// One command in the "+" sheet.
class MinuteCommand {
  const MinuteCommand(this.key, this.icon, this.title, this.hint, this.color, {this.needsRooms = false});
  final String key;
  final IconData icon;
  final String title;
  final String hint;
  final Color color;
  final bool needsRooms;
}

const kMinuteCommands = [
  MinuteCommand('record', NxI.microphone, 'บันทึกเสียง', 'ถอดข้อความสด แปลสด', kMinuteRecord),
  MinuteCommand('video', NxI.videoCamera, 'บันทึกวิดีโอ', 'เปิดกล้อง + ถอดข้อความสด', Color(0xFF7C3AED)),
  MinuteCommand('upload', NxI.uploadSimple, 'อัปโหลดไฟล์', 'เสียง / วิดีโอ ถึง 8 GB', Color(0xFF059669)),
  MinuteCommand('room', NxI.users, 'สร้างห้องประชุม', 'ลิงก์เชิญ แขกภายนอกเข้าได้', Color(0xFF0284C7), needsRooms: true),
  MinuteCommand('join', NxI.signIn, 'เข้าร่วมด้วยรหัส', 'รหัสห้อง หรือ ลิงก์', Color(0xFF475569), needsRooms: true),
];

/// "+": pick what to start. Returns the command key.
Future<String?> showMinuteCommandSheet(BuildContext context, {bool roomsAvailable = true}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      return SafeArea(
        child: Padding(
          key: const ValueKey('minutes-commands'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(tr('เริ่มอะไรดี'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              for (final c in kMinuteCommands)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      key: ValueKey('minutes-action-${c.key}'),
                      borderRadius: BorderRadius.circular(18),
                      onTap: c.needsRooms && !roomsAvailable
                          ? () => ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr('ผู้ดูแลยังไม่ได้เปิดใช้ห้องประชุม'))))
                          : () => Navigator.of(ctx).pop(c.key),
                      child: Opacity(
                        opacity: c.needsRooms && !roomsAvailable ? 0.45 : 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(color: c.color.withValues(alpha: dark ? 0.25 : 0.12), borderRadius: BorderRadius.circular(14)),
                                child: Icon(c.icon, color: dark ? Color.lerp(c.color, Colors.white, 0.35) : c.color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr(c.title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                    Text(tr(c.needsRooms && !roomsAvailable ? 'ผู้ดูแลยังไม่ได้เปิดใช้ห้องประชุม' : c.hint), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Source colour readable on light and dark backgrounds.
Color minuteTint(BuildContext context, Color c) => Theme.of(context).brightness == Brightness.dark ? Color.lerp(c, Colors.white, 0.35)! : c;
