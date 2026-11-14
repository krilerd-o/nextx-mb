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
    this.isCancel = false,
  });
  final String id;
  final String label;

  /// Tint of the current step (e.g. won green / lost red); null = blue like the web.
  final Color? color;

  /// The step is a "done" status: when current it shows green, like the web's closed stage.
  final bool isDone;

  /// A stop status (ยกเลิก): drawn as the separate red capsule after the bar.
  final bool isCancel;
}

/// Colours of the web's chevron status strip (`CaseStatusStage.jsx`).
class _Tone {
  const _Tone(this.bg, this.fg);
  final Color bg;
  final Color fg;

  static _Tone passed(bool dark) => dark ? const _Tone(Color(0xFF0B3B2E), Color(0xFFA7F3D0)) : const _Tone(Color(0xFFD1FAE5), Color(0xFF065F46));
  static _Tone current(bool dark) => dark ? const _Tone(Color(0xFF1E2A4A), Color(0xFFBFDBFE)) : const _Tone(Color(0xFFDBEAFE), Color(0xFF1E40AF));
  static _Tone upcoming(bool dark, {required bool clickable}) => dark
      ? _Tone(const Color(0xFF1E293B), clickable ? const Color(0xFFCBD5E1) : const Color(0xFF64748B))
      : _Tone(const Color(0xFFF1F5F9), clickable ? const Color(0xFF64748B) : const Color(0xFF94A3B8));
  static _Tone cancelledTrack(bool dark) => dark ? const _Tone(Color(0xFF2A1215), Color(0xFFFCA5A5)) : const _Tone(Color(0xFFFEF2F2), Color(0xFFF87171));

  /// The current step in its own colour (soft fill, deep text).
  static _Tone tint(Color c, bool dark, Color surface) {
    final hsl = HSLColor.fromColor(c);
    return _Tone(
      Color.alphaBlend(c.withValues(alpha: dark ? 0.28 : 0.16), surface),
      hsl.withLightness(dark ? 0.82 : 0.3).withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).toColor(),
    );
  }
}

/// Red capsule for a stop status (ยกเลิก), after the bar like the web.
class NxCancelStage extends StatelessWidget {
  const NxCancelStage({super.key, required this.label, required this.active, this.onTap, this.tapKey, this.icon = true});
  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// Key on the tappable part (callers' tests find the stage by it).
  final Key? tapKey;
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = active ? (dark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2)) : (dark ? const Color(0xFF2A1215) : const Color(0xFFFEF2F2));
    final fg = active ? (dark ? const Color(0xFFFECACA) : const Color(0xFFB91C1C)) : (dark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626));
    final border = active ? (dark ? const Color(0xFF991B1B) : const Color(0xFFFECACA)) : (dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA).withValues(alpha: 0.8));
    return Semantics(
      button: onTap != null && !active,
      selected: active,
      label: label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: tapKey,
          onTap: active || onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Container(
            height: NxStatusStepper.pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon && active) ...[Icon(NxI.prohibit, size: 13, color: fg), const SizedBox(width: 4)],
                Text(tr(label), maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w800 : FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The record's statuses as one joined arrow bar, like the web's status strip:
/// numbered steps, passed ones green, the current one blue (or its own
/// colour / green when it is a done status), later ones grey; a stop status
/// (ยกเลิก) sits apart as a red capsule. Tapping a step calls [onPick]
/// (callers keep their confirm sheets). Used by every record screen (CRM,
/// FSM, Workspace).
///
/// The steps share the width when they fit; otherwise the bar scrolls and
/// the current step is brought into view.
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
    this.trailing = const [],
    this.revealTrailing = false,
  });

  /// Extra stages after the bar (e.g. a terminal "ยกเลิกงาน" [NxCancelStage]).
  final List<Widget> trailing;

  /// The record is in a trailing stage (nothing in the bar to scroll to; the
  /// trailing stages are pinned at the right and always visible).
  final bool revealTrailing;

  final List<NxStep> steps;

  /// Index of the current step; -1 when the value matches none.
  final int current;
  final ValueChanged<int>? onPick;
  final bool busy;
  final String stepKeyPrefix;
  final String doneKeyPrefix;
  final EdgeInsets padding;

  /// Height of a step (and of the cancel capsule).
  static const pillHeight = 36.0;

  /// Height of the whole framed bar (pill + 4 px padding + 1 px border, each side).
  static const barHeight = pillHeight + 10;

  /// Depth of the arrow point / notch, and how far the steps overlap (the
  /// rest is the thin slanted gap between them).
  static const tip = 11.0;
  static const overlap = 8.0;

  @override
  State<NxStatusStepper> createState() => _NxStatusStepperState();
}

class _NxStatusStepperState extends State<NxStatusStepper> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  final _trailingKey = GlobalKey();
  final _viewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void didUpdateWidget(NxStatusStepper old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current || old.revealTrailing != widget.revealTrailing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: true));
    }
  }

  void _reveal({required bool animate}) {
    if (!mounted) return;
    // Stop capsules and trailing stages are pinned (always in view).
    final at = widget.current;
    if (widget.revealTrailing || at < 0 || at >= widget.steps.length || widget.steps[at].isCancel) return;
    final ctx = _keys[at]?.currentContext;
    if (ctx == null) return;
    // Only the bar's own scroll view (never the page around it).
    final pos = _scroll.hasClients ? _scroll.position : null;
    if (pos == null || pos.maxScrollExtent <= 0) return;
    final box = ctx.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || view == null || !box.attached || !view.attached) return;
    final left = box.localToGlobal(Offset.zero, ancestor: view).dx + pos.pixels;
    final target = (left + box.size.width / 2 - view.size.width / 2).clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _labelStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2);
  static const _hPad = 10.0;

  /// Width a step needs to show "n label" unclipped.
  double _need(BuildContext context, int n, String label) {
    final scaler = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      // The app font (as the Text will draw it), not the bare default.
      text: TextSpan(text: '$n  ${tr(label)}', style: DefaultTextStyle.of(context).style.merge(_labelStyle).copyWith(fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w + _hPad * 2 + NxStatusStepper.tip * 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final at = widget.current;
    final main = <int>[for (var i = 0; i < widget.steps.length; i++) if (!widget.steps[i].isCancel) i];
    final stops = <int>[for (var i = 0; i < widget.steps.length; i++) if (widget.steps[i].isCancel) i];
    final cancelled = at >= 0 && widget.steps[at].isCancel;
    // Position of the current step along the bar (-1 when cancelled / unknown).
    final atPos = cancelled ? -1 : main.indexOf(at);
    final surface = dark ? const Color(0xFF0F172A) : Colors.white;
    final frame = dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final extras = <Widget>[
      for (final i in stops)
        NxCancelStage(
          key: _keys.putIfAbsent(i, GlobalKey.new),
          tapKey: ValueKey('${widget.stepKeyPrefix}${widget.steps[i].id}'),
          label: widget.steps[i].label,
          active: i == at,
          onTap: widget.busy || widget.onPick == null ? null : () => widget.onPick!(i),
        ),
      if (widget.trailing.isNotEmpty) Row(key: _trailingKey, mainAxisSize: MainAxisSize.min, children: widget.trailing),
    ];

    Widget bar(double? fitWidth) {
      final n = main.length;
      final needs = [for (var k = 0; k < n; k++) _need(context, k + 1, widget.steps[main[k]].label)];
      const o = NxStatusStepper.overlap;
      final total = needs.fold<double>(0, (a, b) => a + b) - o * (n - 1);
      // Fill the width like the web when every step fits (the spare room shared
      // out); otherwise each step takes what it needs and the bar scrolls.
      final fits = fitWidth != null && n > 0 && total <= fitWidth;
      final spare = fits ? (fitWidth - total) / n : 0.0;
      final widths = [for (final w in needs) w + spare];
      final width = fits ? fitWidth : total;
      final children = <Widget>[];
      var x = 0.0;
      for (var k = 0; k < n; k++) {
        final i = main[k];
        final s = widget.steps[i];
        final on = k == atPos;
        final passed = atPos >= 0 && k < atPos;
        final clickable = !widget.busy && !on && widget.onPick != null;
        final tone = cancelled
            ? _Tone.cancelledTrack(dark)
            : passed
                ? _Tone.passed(dark)
                : on
                    // Own colour first (won / lost); a done or final status reads as
                    // finished (green) like the web's closed stage; else blue.
                    ? (s.color != null
                        ? _Tone.tint(s.color!, dark, surface)
                        : (s.isDone || k == n - 1 ? _Tone.passed(dark) : _Tone.current(dark)))
                    : _Tone.upcoming(dark, clickable: clickable);
        children.add(Positioned(
          left: x,
          top: 0,
          bottom: 0,
          width: widths[k],
          child: Semantics(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            button: clickable,
            selected: on,
            label: tr(s.label),
            child: ClipPath(
              clipper: NxChevronClipper(first: k == 0, last: k == n - 1),
              child: Material(
                color: tone.bg,
                child: InkWell(
                  key: ValueKey('${widget.stepKeyPrefix}${s.id}'),
                  onTap: clickable
                      ? () {
                          HapticFeedback.selectionClick();
                          widget.onPick!(i);
                        }
                      : null,
                  child: Padding(
                    padding: EdgeInsets.only(left: k == 0 ? _hPad : NxStatusStepper.tip + 2, right: k == n - 1 ? _hPad : NxStatusStepper.tip + 2),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          KeyedSubtree(
                            key: passed ? ValueKey('${widget.doneKeyPrefix}${s.id}') : null,
                            child: Text(
                              '${k + 1}',
                              style: _labelStyle.copyWith(color: tone.fg.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              tr(s.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _labelStyle.copyWith(color: tone.fg, fontWeight: on ? FontWeight.w800 : FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        x += widths[k] - o;
      }
      return SizedBox(width: width, height: NxStatusStepper.pillHeight, child: Stack(clipBehavior: Clip.none, children: children));
    }

    final framed = Container(
      key: const ValueKey('nx-status-bar'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: frame.withValues(alpha: 0.9)),
      ),
      // The stop capsule(s) stay pinned at the right; only the steps scroll.
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  key: _viewKey,
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: bar(c.maxWidth),
                ),
              ),
            ),
          ),
          for (final e in extras) ...[const SizedBox(width: 6), e],
        ],
      ),
    );
    return Padding(padding: widget.padding.copyWith(top: 0, bottom: 0), child: framed);
  }
}

/// Arrow-shaped step: a point on the right (not the last), a notch on the
/// left (not the first) — the web's `clip-path: polygon(...)`.
class NxChevronClipper extends CustomClipper<Path> {
  const NxChevronClipper({required this.first, required this.last});
  final bool first;
  final bool last;

  @override
  Path getClip(Size size) {
    const t = NxStatusStepper.tip;
    final w = size.width;
    final h = size.height;
    final p = Path()..moveTo(0, 0);
    if (last) {
      p
        ..lineTo(w, 0)
        ..lineTo(w, h);
    } else {
      p
        ..lineTo(w - t, 0)
        ..lineTo(w, h / 2)
        ..lineTo(w - t, h);
    }
    p.lineTo(0, h);
    if (!first) p.lineTo(t, h / 2);
    return p..close();
  }

  @override
  bool shouldReclip(NxChevronClipper old) => old.first != first || old.last != last;
}
