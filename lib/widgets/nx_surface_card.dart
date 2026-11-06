import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'nx_press_scale.dart';

/// Inbox-style white tile — flat fill, tight soft shadow, no glossy rim.
class NxSurfaceCard extends StatelessWidget {
  const NxSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.radius,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final Color? color;

  static List<BoxShadow> shadows(bool dark) {
    if (dark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.40),
          offset: const Offset(0, 4),
          blurRadius: 10,
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x0A0F172A),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color(0x0A0F172A),
        offset: Offset(0, 4),
        blurRadius: 12,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = radius ?? AppTheme.cardRadius;
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? NxAtmosphereTokens.of(context).cardElevated,
        borderRadius: BorderRadius.circular(r),
        boxShadow: shadows(dark),
        border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (onTap == null && onLongPress == null) return card;
    return NxPressScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }
}
