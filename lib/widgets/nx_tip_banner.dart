import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'nx_icons.dart';

/// One-time tip / hint banner shown at the top of list screens
/// ("กดค้างที่รายการเพื่อดูคำสั่ง …").
///
/// Always full width — it sits inside the same list padding as the cards, so
/// its edges line up with them — and theme-aware: a light primary tint with
/// dark ink on the light theme, a deeper tint with light text on the dark
/// theme (never white text on a pale background).
class NxTipBanner extends StatelessWidget {
  const NxTipBanner({
    super.key,
    required this.text,
    this.title,
    this.icon = NxI.info,
    this.onClose,
    this.closeKey,
    this.action,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String text;
  final String? title;
  final IconData icon;
  final VoidCallback? onClose;
  final Key? closeKey;

  /// Optional extra (e.g. a "ต่างกันอย่างไร" text button) under the text.
  final Widget? action;
  final EdgeInsetsGeometry margin;

  /// Banner background for [theme] (exposed for tests).
  static Color background(ThemeData theme) {
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(cs.primary.withValues(alpha: dark ? 0.22 : 0.09), cs.surface);
  }

  /// Text colour for [theme]: the regular on-surface ink, so it always reads.
  static Color foreground(ThemeData theme) => theme.colorScheme.onSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = foreground(theme);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: EdgeInsets.fromLTRB(14, 10, onClose == null ? 14 : 4, 10),
      decoration: BoxDecoration(
        color: background(theme),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: dark ? 0.35 : 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: dark ? Color.lerp(cs.primary, Colors.white, 0.35) : cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: onClose == null ? 0 : 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: fg)),
                    const SizedBox(height: 4),
                  ],
                  Text(text, style: theme.textTheme.bodySmall?.copyWith(color: fg, height: 1.4)),
                  ?action,
                ],
              ),
            ),
          ),
          if (onClose != null)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                key: closeKey,
                tooltip: tr('ปิด'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(NxI.x, size: 16, color: cs.onSurfaceVariant),
                onPressed: onClose,
              ),
            ),
        ],
      ),
    );
  }
}
