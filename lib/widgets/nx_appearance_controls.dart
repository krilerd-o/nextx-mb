import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import '../core/ui_font.dart';
import 'app_bottom_sheet.dart';
import 'nx_icons.dart';

/// "Font" picker: the same fonts as the web, each row previewed in its own
/// font. One tap applies it to the whole app (this device only).
Future<void> showUiFontPicker(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    title: 'ฟอนต์',
    child: const _FontList(),
  );
}

class _FontList extends StatelessWidget {
  const _FontList();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in kUiFonts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: f.id == config.uiFontId ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: ValueKey('ui-font-${f.id}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  HapticFeedback.selectionClick();
                  config.setUiFont(f.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          f.id == kDefaultUiFontId ? '${f.label} · ${tr('ค่าเริ่มต้น')}' : f.label,
                          style: TextStyle(fontFamily: f.family, fontFamilyFallback: uiFontFallback(f.family), fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'สวัสดี NEXTX 1,234.50',
                          style: TextStyle(
                            fontFamily: f.family,
                            fontFamilyFallback: uiFontFallback(f.family),
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                    AnimatedOpacity(
                      opacity: f.id == config.uiFontId ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(NxI.checkCircle, color: cs.primary),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Screen-scale control: 5 steps (90–110%) with a live preview line.
class NxUiScaleControl extends StatelessWidget {
  const NxUiScaleControl({super.key});

  static String label(double s) => '${(s * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i = kUiScales.indexOf(config.uiScale).clamp(0, kUiScales.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('A', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          Expanded(
            child: Slider(
              key: const ValueKey('ui-scale-slider'),
              value: i.toDouble(),
              min: 0,
              max: (kUiScales.length - 1).toDouble(),
              divisions: kUiScales.length - 1,
              label: label(kUiScales[i]),
              onChanged: (v) {
                final s = kUiScales[v.round()];
                if (s != config.uiScale) {
                  HapticFeedback.selectionClick();
                  config.setUiScale(s);
                }
              },
            ),
          ),
          Text('A', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        Row(children: [
          Expanded(
            child: Text(
              '${tr('ขนาด')} ${label(config.uiScale)}${config.uiScale == kDefaultUiScale ? ' · ${tr('ค่าเริ่มต้น')}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          if (config.uiScale != kDefaultUiScale)
            TextButton(
              key: const ValueKey('ui-scale-reset'),
              onPressed: () => config.setUiScale(kDefaultUiScale),
              child: Text(tr('คืนค่าเริ่มต้น')),
            ),
        ]),
      ],
    );
  }
}
