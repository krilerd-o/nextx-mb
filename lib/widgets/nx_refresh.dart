import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/nx_motion.dart';
import 'nx_icons.dart';

/// The innermost [NxRefresh] handles a pull; outer ones see it claimed.
final _claimed = Expando<bool>('nx-refresh');

enum _Phase { idle, pulling, armed, refreshing, done, failed }

/// Pull down to refresh: the app's only way to reload a page (no refresh
/// buttons). Drop-in for [RefreshIndicator].
///
/// A small glass bubble comes down below the floating header as you pull. Its
/// ring fills up, the arrow flips with a haptic tick once letting go will
/// refresh, it spins while loading, then shows ✓ "อัปเดตแล้ว" and slides away.
/// Works with bouncing (iOS) and clamping (Android) scroll physics.
class NxRefresh extends StatefulWidget {
  const NxRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset,
    this.color,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Where the bubble starts. Defaults to below the floating header
  /// (the top padding [NxScrollScaffold] gives a body that runs under it).
  final double? edgeOffset;
  final Color? color;
  final ScrollNotificationPredicate notificationPredicate;

  /// Pull distance (px) that triggers a refresh.
  static const trigger = 80.0;

  @override
  State<NxRefresh> createState() => NxRefreshState();
}

class NxRefreshState extends State<NxRefresh> with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  double _pull = 0; // finger distance past the top
  late final AnimationController _reveal = AnimationController(vsync: this, upperBound: 2, duration: const Duration(milliseconds: 280));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  bool get refreshing => _phase == _Phase.refreshing;

  @override
  void dispose() {
    _reveal.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// Run a refresh as if the user pulled (e.g. from code or tests).
  Future<void> show() => _start();

  void _setPull(double v) {
    _pull = v.clamp(0.0, NxRefresh.trigger * 2);
    final p = _pull / NxRefresh.trigger;
    _reveal.value = p;
    final next = p >= 1 ? _Phase.armed : (_pull > 0 ? _Phase.pulling : _Phase.idle);
    if (next == _Phase.armed && _phase != _Phase.armed) HapticFeedback.mediumImpact();
    if (next != _phase) setState(() => _phase = next);
  }

  bool _onScroll(ScrollNotification n) {
    if (!widget.notificationPredicate(n) || n.metrics.axis != Axis.vertical) return false;
    if (_claimed[n] == true) return false;
    _claimed[n] = true;
    if (_phase == _Phase.refreshing || _phase == _Phase.done || _phase == _Phase.failed) return false;
    final m = n.metrics;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      if (m.pixels < m.minScrollExtent) {
        _setPull(m.minScrollExtent - m.pixels); // bouncing: the list itself is pulled
      } else if (_pull > 0 && (n.scrollDelta ?? 0) > 0) {
        _setPull(_pull - n.scrollDelta!); // pushed back up
      }
    } else if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0 && m.extentBefore == 0) {
      _setPull(_pull - n.overscroll * 0.65); // clamping: stretch past the top
    } else if (n is ScrollUpdateNotification && n.dragDetails == null && _pull > 0) {
      _release(); // finger lifted, the list is bouncing back (iOS): start now
    } else if (n is ScrollEndNotification || (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      _release();
    }
    return false;
  }

  void _release() {
    if (_phase == _Phase.armed) {
      _start();
    } else if (_phase == _Phase.pulling) {
      _pull = 0;
      setState(() => _phase = _Phase.idle);
      _reveal.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  Future<void> _start() async {
    if (_phase == _Phase.refreshing) return;
    _pull = 0;
    setState(() => _phase = _Phase.refreshing);
    _reveal.animateTo(1, duration: const Duration(milliseconds: 220), curve: Curves.easeOutBack);
    if (!NxMotion.reduced(context)) _spin.repeat();
    var ok = true;
    // Spin at least a moment, so even an instant reload is seen to happen.
    final minSpin = Future<void>.delayed(const Duration(milliseconds: 650));
    try {
      await widget.onRefresh();
    } catch (_) {
      ok = false; // the page shows its own error
    }
    await minSpin;
    if (!mounted) return;
    _spin.stop();
    HapticFeedback.lightImpact();
    setState(() => _phase = ok ? _Phase.done : _Phase.failed);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;
    await _reveal.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeInCubic);
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.edgeOffset ?? MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_reveal, _spin]),
                builder: (context, _) {
                  final r = _reveal.value;
                  if (r <= 0.001 && _phase == _Phase.idle) return const SizedBox.shrink();
                  // Follows the finger with resistance, rests 14 px below the header.
                  final settled = math.min(r, 1.0) * 62 + math.max(0.0, r - 1) * 18;
                  return Transform.translate(
                    offset: Offset(0, settled - 48),
                    child: Opacity(
                      opacity: r.clamp(0.0, 1.0),
                      child: Center(child: _bubble(context, math.min(r, 1.0))),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, double progress) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = widget.color ?? cs.primary;
    final done = _phase == _Phase.done, failed = _phase == _Phase.failed;
    final Widget icon;
    if (done) {
      icon = Icon(NxI.check, key: const ValueKey('done'), size: 18, color: Colors.green.shade600);
    } else if (failed) {
      icon = Icon(NxI.warningCircle, key: const ValueKey('fail'), size: 18, color: cs.error);
    } else if (_phase == _Phase.refreshing) {
      icon = const SizedBox(key: ValueKey('spin'), width: 18, height: 18);
    } else {
      icon = AnimatedRotation(
        key: const ValueKey('arrow'),
        turns: _phase == _Phase.armed ? 0.5 : 0,
        duration: const Duration(milliseconds: 180),
        child: Icon(NxI.arrowDown, size: 18, color: _phase == _Phase.armed ? accent : cs.onSurfaceVariant),
      );
    }
    final label = done ? tr('อัปเดตแล้ว') : (failed ? tr('โหลดไม่สำเร็จ') : null);
    return AnimatedContainer(
      key: const ValueKey('nx-refresh'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
      constraints: const BoxConstraints(minWidth: 40),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? cs.surfaceContainerHighest : cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              if (!done && !failed)
                Transform.rotate(
                  angle: _phase == _Phase.refreshing ? _spin.value * 2 * math.pi : progress * math.pi,
                  child: CustomPaint(
                    size: const Size(26, 26),
                    painter: _RingPainter(
                      sweep: _phase == _Phase.refreshing ? 0.72 : progress * 0.86,
                      color: accent,
                      track: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: icon,
              ),
            ]),
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.sweep, required this.color, required this.track});
  final double sweep; // 0..1 of a full turn
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(1.2), 0, 2 * math.pi, false, p..color = track);
    if (sweep > 0) canvas.drawArc(rect.deflate(1.2), -math.pi / 2, sweep * 2 * math.pi, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.sweep != sweep || old.color != color;
}
