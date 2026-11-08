import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';

/// Pill switch with a thumb that slides (and bounces a little) to the chosen
/// option — theme, language and other small choices.
class NxSlidingSegmented<T> extends StatelessWidget {
  const NxSlidingSegmented({required this.value, required this.options, required this.onChanged, this.translate = true});
  final T value;
  /// Off for language names, which always show in their own language.
  final bool translate;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final index = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(cs.primary, Colors.white, 0.12)!, cs.primary],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == index) return;
                          HapticFeedback.selectionClick();
                          onChanged(options[i].$1);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                              color: i == index ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (options[i].$3 != null) ...[
                                  // The chosen icon pops and turns a little (sun ↔ moon).
                                  AnimatedRotation(
                                    turns: i == index ? 0 : -0.08,
                                    duration: const Duration(milliseconds: 360),
                                    curve: Curves.easeOutBack,
                                    child: AnimatedScale(
                                      scale: i == index ? 1.15 : 1,
                                      duration: const Duration(milliseconds: 360),
                                      curve: Curves.easeOutBack,
                                      child: Icon(options[i].$3, size: 16, color: i == index ? cs.onPrimary : cs.onSurfaceVariant),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(child: Text(translate ? tr(options[i].$2) : options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Theme colour swatches; the chosen one grows and shows a check.