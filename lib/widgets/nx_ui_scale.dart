import 'package:flutter/material.dart';

/// Whole-app screen scale (Settings → ขนาดหน้าจอ): text, control density and
/// icons follow one value, on top of the phone's own text-size setting.
///
/// Sits above every page and so rebuilds with every MediaQuery change (each
/// frame of the keyboard sliding in). The scaled [ThemeData] is therefore built
/// once per (theme, scale) and reused — a new ThemeData each frame meant a
/// copy plus a deep compare of every theme field on every keyboard frame.
class NxUiScale extends StatefulWidget {
  const NxUiScale({super.key, required this.scale, required this.child});

  /// 0.9 … 1.1 (1.0 = original size).
  final double scale;
  final Widget child;

  /// VisualDensity step for a scale (−1.5 at 90%, +1.5 at 110%).
  static double densityFor(double scale) =>
      (((scale - 1) / 0.05) * 0.75).clamp(-3.0, 3.0);

  /// [theme] with density and icon size for [scale].
  static ThemeData scaledTheme(ThemeData theme, double scale) {
    final d = densityFor(scale);
    return theme.copyWith(
      visualDensity: VisualDensity(horizontal: d, vertical: d),
      iconTheme: theme.iconTheme.copyWith(size: (theme.iconTheme.size ?? 24) * scale),
    );
  }

  @override
  State<NxUiScale> createState() => _NxUiScaleState();
}

class _NxUiScaleState extends State<NxUiScale> {
  ThemeData? _base;
  double? _scale;
  ThemeData? _scaled;

  ThemeData _themeFor(ThemeData base, double scale) {
    if (!identical(base, _base) || scale != _scale || _scaled == null) {
      _base = base;
      _scale = scale;
      _scaled = NxUiScale.scaledTheme(base, scale);
    }
    return _scaled!;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    if ((scale - 1).abs() < 0.001) return widget.child;
    final theme = _themeFor(Theme.of(context), scale);
    // Only the text scaler changes; everything else is passed through as is.
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
      child: Theme(data: theme, child: widget.child),
    );
  }
}
