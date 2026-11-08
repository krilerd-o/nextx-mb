import 'package:flutter/material.dart';

/// Whole-app screen scale (Settings → ขนาดหน้าจอ): text, control density and
/// icons follow one value, on top of the phone's own text-size setting.
class NxUiScale extends StatelessWidget {
  const NxUiScale({super.key, required this.scale, required this.child});

  /// 0.9 … 1.1 (1.0 = original size).
  final double scale;
  final Widget child;

  /// VisualDensity step for a scale (−1.5 at 90%, +1.5 at 110%).
  static double densityFor(double scale) =>
      (((scale - 1) / 0.05) * 0.75).clamp(-3.0, 3.0);

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final d = densityFor(scale);
    final iconSize = (theme.iconTheme.size ?? 24) * scale;
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale),
      ),
      child: Theme(
        data: theme.copyWith(
          visualDensity: VisualDensity(horizontal: d, vertical: d),
          iconTheme: theme.iconTheme.copyWith(size: iconSize),
        ),
        child: child,
      ),
    );
  }
}
