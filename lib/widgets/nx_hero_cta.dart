import 'package:flutter/material.dart';

import 'nx_press_scale.dart';
import '../core/i18n.dart';

class NxHeroCta extends StatelessWidget {
  const NxHeroCta({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxPressScale(
      onTap: busy ? null : onPressed,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: onPressed == null || busy
                ? theme.colorScheme.primary.withValues(alpha: 0.45)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    tr(label),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
