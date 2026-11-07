import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/nx_breakpoint.dart';
import 'nx_press_scale.dart';
import 'nx_surface_card.dart';
import 'nx_icons.dart';
import '../core/i18n.dart';

class NxSelectTile extends StatelessWidget {
  const NxSelectTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NxPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: nxMotion(context, 400),
        curve: NxMotion.settleCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.10) : NxAtmosphereTokens.of(context).cardElevated,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: NxSurfaceCard.shadows(theme.brightness == Brightness.dark),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title), style: theme.textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      tr(subtitle!),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(
              selected ? NxI.checkCircleFill : NxI.circle,
              color: selected ? cs.primary : cs.outline,
            ),
          ],
        ),
      ),
    );
  }
}
