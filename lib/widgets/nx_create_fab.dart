import 'package:flutter/material.dart';

import '../core/nx_breakpoint.dart';
import 'nx_icons.dart';
import '../core/i18n.dart';

/// Circular add control — plus Regular on theme primary, same language as the screenshot.
class NxAddButton extends StatelessWidget {
  const NxAddButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'สร้าง',
    this.size = 40,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr(tooltip),
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 2,
          shadowColor: scheme.primary.withValues(alpha: 0.35),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(NxI.plus, size: size * 0.45, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

class NxCreateFab extends StatelessWidget {
  const NxCreateFab({
    super.key,
    required this.onPressed,
    this.label = 'สร้าง',
    this.onLongPress,
  });

  final VoidCallback onPressed;
  final String label;

  /// Optional: long-press for more create choices.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    if (bp.twoPane) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bp.useRail ? 8 : 4),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: FloatingActionButton(
        onPressed: onPressed,
        tooltip: trn(label),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        highlightElevation: 6,
        shape: const CircleBorder(),
        child: const Icon(NxI.plus, size: 28),
      ),
      ),
    );
  }
}
