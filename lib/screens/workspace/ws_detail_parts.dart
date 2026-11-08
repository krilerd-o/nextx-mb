import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';

/// Passed steps are green with a check, like the CRM stepper.
const _green = Color(0xFF16A34A);

/// Status stepper: the board's statuses in order, the current one filled.
/// Tapping another step changes the status (with a haptic tick).
class WsStatusStepper extends StatelessWidget {
  const WsStatusStepper({super.key, required this.statuses, required this.current, this.onPick, this.busy = false});

  final List<WsStatus> statuses;
  final String? current;
  final ValueChanged<WsStatus>? onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final at = statuses.indexWhere((s) => s.id == current);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: statuses.length,
        separatorBuilder: (_, i) => Center(
          child: Container(
            width: 14,
            height: 2,
            color: i < at ? _green.withValues(alpha: 0.7) : cs.outlineVariant,
          ),
        ),
        itemBuilder: (context, i) {
          final s = statuses[i];
          final on = i == at;
          final passed = at >= 0 && i < at;
          return Semantics(
            button: true,
            selected: on,
            label: s.label,
            child: GestureDetector(
              onTap: busy || on || onPick == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onPick!(s);
                    },
              child: AnimatedContainer(
                key: ValueKey('ws-step-${s.id}'),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? s.color : (passed ? _green.withValues(alpha: 0.14) : cs.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: on ? s.color : (passed ? _green : cs.outlineVariant), width: 1.2),
                  boxShadow: on ? [BoxShadow(color: s.color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (passed)
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                        child: const Icon(NxI.check, size: 11, color: Colors.white),
                      )
                    else if (on && s.isDone) ...[
                      const Icon(NxI.check, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      s.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: on ? Colors.white : (passed ? (theme.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D)) : cs.onSurfaceVariant),
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ring of spent / estimate with remaining time and the log + timer buttons.
class WsTimeCard extends StatelessWidget {
  const WsTimeCard({
    super.key,
    required this.spent,
    required this.estimate,
    required this.remaining,
    this.onLog,
    this.timer,
  });

  final int spent;
  final int? estimate;
  final int? remaining;
  final VoidCallback? onLog;
  final Widget? timer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final est = estimate ?? 0;
    final ratio = est > 0 ? spent / est : (spent > 0 ? 1.0 : 0.0);
    final over = est > 0 && spent > est;
    final color = over ? cs.error : const Color(0xFF10B981);
    final left = remaining ?? (est > 0 ? math.max(0, est - spent) : null);
    // Compact, modern card: numbers on one line, a slim progress bar, then
    // the two actions side by side.
    return Container(
      key: const ValueKey('ws-time-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(NxI.timer, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: formatMinutes(spent), style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (est > 0) TextSpan(text: ' / ${formatMinutes(est)}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                ]),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (left != null)
                Text(
                  over ? tr('เกิน ${formatMinutes(spent - est)}') : tr('คงเหลือ ${formatMinutes(left)}'),
                  style: theme.textTheme.labelMedium?.copyWith(color: over ? cs.error : cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                )
              else
                Text(tr('เวลาที่ใช้'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: est > 0 || spent > 0 ? v : 0, minHeight: 6, color: color, backgroundColor: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          if (onLog != null || timer != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onLog != null)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('ws-log-time'),
                      onPressed: onLog,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                      icon: const Icon(NxI.clock, size: 18),
                      label: Text(tr('ลงเวลา')),
                    ),
                  ),
                if (onLog != null && timer != null) const SizedBox(width: 8),
                if (timer != null) Expanded(child: Center(child: timer!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class WsTaskTimer extends StatefulWidget {
  const WsTaskTimer({super.key, required this.prefsKey, required this.onStop});

  final String prefsKey;

  /// Called with the elapsed minutes (≥ 1) when stopped.
  final ValueChanged<int> onStop;

  @override
  State<WsTaskTimer> createState() => _WsTaskTimerState();
}

class _WsTaskTimerState extends State<WsTaskTimer> {
  DateTime? _started;
  Timer? _tick;

  String get _key => 'ws_timer_${widget.prefsKey}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final ms = p.getInt(_key);
      if (ms != null && mounted) _run(DateTime.fromMillisecondsSinceEpoch(ms));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _run(DateTime from) {
    setState(() => _started = from);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggle() async {
    final p = await SharedPreferences.getInstance();
    HapticFeedback.mediumImpact();
    if (_started == null) {
      final now = DateTime.now();
      await p.setInt(_key, now.millisecondsSinceEpoch);
      _run(now);
      return;
    }
    final mins = math.max(1, (DateTime.now().difference(_started!).inSeconds / 60).round());
    await p.remove(_key);
    _tick?.cancel();
    setState(() => _started = null);
    widget.onStop(mins);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _started != null;
    String two(int n) => n.toString().padLeft(2, '0');
    final d = running ? DateTime.now().difference(_started!) : Duration.zero;
    final label = running ? '${d.inHours > 0 ? '${d.inHours}:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : tr('จับเวลา');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        key: const ValueKey('ws-timer'),
        onPressed: _toggle,
        style: TextButton.styleFrom(foregroundColor: running ? cs.error : cs.primary, visualDensity: VisualDensity.compact),
        icon: Icon(running ? NxI.stop : NxI.play, size: 16),
        label: Text(label, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
      ),
    );
  }
}

/// Result of the log-time sheet.
class WsWorklogInput {
  const WsWorklogInput({required this.minutes, this.description, this.remaining, this.startedAt});
  final int minutes;
  final String? description;
  final int? remaining;

  /// `YYYY-MM-DD HH:mm:00` in Thai time, like the web.
  final String? startedAt;
}

/// Sheet to log (or edit) time: quick chips, free text "1h 30m", when, what,
/// and the remaining estimate.
Future<WsWorklogInput?> showWsLogTimeSheet(
  BuildContext context, {
  int? minutes,
  String? description,
  int? remaining,
  String? startedAt,
  bool edit = false,
}) {
  return showAppBottomSheet<WsWorklogInput>(
    context: context,
    title: edit ? tr('แก้ไขการลงเวลา') : tr('ลงเวลา'),
    child: _LogTimeBody(minutes: minutes, description: description, remaining: remaining, startedAt: startedAt, edit: edit),
  );
}

class _LogTimeBody extends StatefulWidget {
  const _LogTimeBody({this.minutes, this.description, this.remaining, this.startedAt, this.edit = false});
  final int? minutes;
  final String? description;
  final int? remaining;
  final String? startedAt;
  final bool edit;

  @override
  State<_LogTimeBody> createState() => _LogTimeBodyState();
}

class _LogTimeBodyState extends State<_LogTimeBody> {
  late final _spent = TextEditingController(text: widget.minutes == null ? '' : formatMinutes(widget.minutes));
  late final _desc = TextEditingController(text: widget.description ?? '');
  late final _remain = TextEditingController(text: widget.remaining == null ? '' : formatMinutes(widget.remaining));
  late DateTime _when = parseThai(widget.startedAt) ?? thaiNow();
  String? _error;

  @override
  void dispose() {
    _spent.dispose();
    _desc.dispose();
    _remain.dispose();
    super.dispose();
  }

  void _chip(int m) {
    HapticFeedback.selectionClick();
    final cur = parseDuration(_spent.text) ?? 0;
    setState(() {
      _spent.text = formatMinutes(_spent.text.trim().isEmpty ? m : cur + m);
      _error = null;
    });
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(_when.year - 2),
      lastDate: DateTime(_when.year + 1),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    setState(() => _when = DateTime(d.year, d.month, d.day, t?.hour ?? _when.hour, t?.minute ?? _when.minute));
  }

  void _submit() {
    final m = parseDuration(_spent.text);
    if (m == null) {
      HapticFeedback.heavyImpact();
      setState(() => _error = tr('รูปแบบเวลา เช่น 2h 30m, 90m, 1d'));
      return;
    }
    final r = _remain.text.trim().isEmpty ? null : parseDuration(_remain.text);
    String two(int n) => n.toString().padLeft(2, '0');
    final w = _when;
    Navigator.pop(
      context,
      WsWorklogInput(
        minutes: m,
        description: _desc.text.trim(),
        remaining: r,
        startedAt: '${w.year}-${two(w.month)}-${two(w.day)} ${two(w.hour)}:${two(w.minute)}:00',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      // showAppBottomSheet already lifts the sheet above the keyboard.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (m, l) in const [(15, '+15m'), (30, '+30m'), (60, '+1h'), (120, '+2h'), (240, '+4h')])
                ActionChip(label: Text(l), onPressed: () => _chip(m)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('ws-log-spent'),
            controller: _spent,
            autofocus: widget.minutes == null,
            decoration: InputDecoration(
              labelText: tr('เวลาที่ใช้'),
              hintText: '1h 30m',
              errorText: _error,
              prefixIcon: const Icon(NxI.timer),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(NxI.calendarBlank),
            title: Text(tr('วันเวลาที่ทำ')),
            subtitle: Text('${_when.day}/${_when.month}/${uiYear(_when.year)} ${two(_when.hour)}:${two(_when.minute)}'),
            trailing: const Icon(NxI.caretRight),
            onTap: _pickWhen,
          ),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: tr('รายละเอียดงาน'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remain,
            decoration: InputDecoration(
              labelText: tr('เวลาคงเหลือ (ไม่บังคับ)'),
              hintText: '2h',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          KeyedSubtree(
            key: const ValueKey('ws-log-save'),
            child: NxHeroCta(label: widget.edit ? 'บันทึก' : 'ลงเวลา', onPressed: _submit),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('รูปแบบเวลา เช่น 2h 30m, 90m, 1d'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the fields card: icon, label, value; tap to edit.
class WsFieldRow extends StatelessWidget {
  const WsFieldRow({super.key, required this.icon, required this.label, required this.value, this.onTap, this.valueWidget});

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final empty = value.isEmpty && valueWidget == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: Text(tr(label), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: valueWidget ??
                  Text(
                    empty ? tr('—') : value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: empty ? null : FontWeight.w600,
                      color: empty ? cs.outline : null,
                    ),
                  ),
            ),
            if (onTap != null) Icon(NxI.caretRight, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

/// Rounded section card with a title row and optional trailing action.
class WsSection extends StatelessWidget {
  const WsSection({super.key, required this.title, required this.icon, required this.child, this.trailing, this.color});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = color ?? cs.primary;
    return Container(
      // Standard 16 px inside the box; the header sits clear of the fields.
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 16, color: c),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
