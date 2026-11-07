import 'package:flutter/material.dart';

import 'nx_icons.dart';
import 'nx_press_scale.dart';

/// Onboarding step header: round back button, segmented progress, `2/5`.
class NxStepHeader extends StatelessWidget {
  const NxStepHeader({super.key, required this.step, required this.total, this.onBack});

  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: onBack == null
                ? null
                : Material(
                    color: cs.surface,
                    shape: CircleBorder(side: BorderSide(color: cs.outlineVariant)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onBack,
                      child: const Icon(NxI.arrowLeft, size: 20),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                for (var i = 1; i <= total; i++)
                  Expanded(
                    flex: i == step ? 2 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= step ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$step', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '/$total', style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

/// Selectable card with a dashed/checked circle on the right (onboarding choices).
class NxChoiceCard extends StatelessWidget {
  const NxChoiceCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = color ?? cs.primary;
    return NxPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 14 : 16),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: 0.45) : Colors.transparent, width: 1.4),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected
                  ? Icon(NxI.checkCircleFill, key: const ValueKey('on'), color: cs.primary, size: 24)
                  : Icon(NxI.radioOff, key: const ValueKey('off'), color: cs.outline, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}
