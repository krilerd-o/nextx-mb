import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import 'nx_icons.dart';

/// Green for passed steps (same as the web stepper).
const kNxStepPassedGreen = Color(0xFF16A34A);

/// One step of [NxStatusStepper].
class NxStep {
  const NxStep({
    required this.id,
    required this.label,
    this.color,
    this.isDone = false,
  });
  final String id;
  final String label;

  /// Fill of the current step (board status colour); null = theme primary.
  final Color? color;

  /// The step is a "done" status: the current pill shows a check.
  final bool isDone;
}

/// Status steps in order, joined by a line (green up to the current one),
/// the current step filled with a soft shadow, passed ones green with a
/// check. Used by every record screen (CRM, FSM, Workspace).
///
/// The row is taller than the pills so the current pill's shadow is not cut
/// off, and it scrolls the current step into view.
class NxStatusStepper extends StatefulWidget {
  const NxStatusStepper({
    super.key,
    required this.steps,
    required this.current,
    this.onPick,
    this.busy = false,
    this.stepKeyPrefix = 'nx-step-',
    this.doneKeyPrefix = 'nx-step-done-',
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<NxStep> steps;

  /// Index of the current step; -1 when the value matches none.
  final int current;
  final ValueChanged<int>? onPick;
  final bool busy;
  final String stepKeyPrefix;
  final String doneKeyPrefix;
  final EdgeInsets padding;

  static const pillHeight = 44.0;

  /// Room above / below the pill for its shadow.
  static const shadowTop = 6.0;
  static const shadowBottom = 14.0;

  @override
  State<NxStatusStepper> createState() => _NxStatusStepperState();
}

class _NxStatusStepperState extends State<NxStatusStepper> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(animate: false),
    );
  }

  @override
  void didUpdateWidget(NxStatusStepper old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(animate: true),
      );
    }
  }

  void _reveal({required bool animate}) {
    if (!mounted || widget.current < 0) return;
    final ctx = _keys[widget.current]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 280) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final at = widget.current;
    final passedFg = theme.brightness == Brightness.dark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF15803D);
    return SizedBox(
      height:
          NxStatusStepper.pillHeight +
          NxStatusStepper.shadowTop +
          NxStatusStepper.shadowBottom,
      // A Row (not a lazy ListView): every step is built, so the current one
      // can always be scrolled into view; boards have a handful of statuses.
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: widget.padding.copyWith(
          top: NxStatusStepper.shadowTop,
          bottom: NxStatusStepper.shadowBottom,
        ),
        child: Row(
          children: [
            for (var i = 0; i < widget.steps.length; i++) ...[
              if (i > 0)
                Container(
                  width: 14,
                  height: 2,
                  color: at >= 0 && i - 1 < at
                      ? kNxStepPassedGreen.withValues(alpha: 0.7)
                      : cs.outlineVariant,
                ),
              _step(context, i, at, passedFg),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(BuildContext context, int i, int at, Color passedFg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = widget.steps[i];
    final on = i == at;
    final passed = at >= 0 && i < at;
    final fill = s.color ?? cs.primary;
    final onFill = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Semantics(
      key: _keys.putIfAbsent(i, GlobalKey.new),
      button: true,
      selected: on,
      label: s.label,
      child: GestureDetector(
        onTap: widget.busy || on || widget.onPick == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPick!(i);
              },
        child: AnimatedContainer(
          height: NxStatusStepper.pillHeight,
          key: ValueKey('${widget.stepKeyPrefix}${s.id}'),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? fill
                : (passed
                      ? kNxStepPassedGreen.withValues(alpha: 0.14)
                      : cs.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(NxStatusStepper.pillHeight / 2),
            border: Border.all(
              color: on
                  ? fill
                  : (passed ? kNxStepPassedGreen : cs.outlineVariant),
              width: 1.2,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: fill.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (passed)
                Container(
                  key: ValueKey('${widget.doneKeyPrefix}${s.id}'),
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: kNxStepPassedGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(NxI.check, size: 11, color: Colors.white),
                )
              else if (on && s.isDone) ...[
                Icon(NxI.check, size: 14, color: onFill),
                const SizedBox(width: 4),
              ],
              Text(
                tr(s.label),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: on
                      ? onFill
                      : (passed ? passedFg : cs.onSurfaceVariant),
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
