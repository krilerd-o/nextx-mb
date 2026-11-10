import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import '../core/nav_dock.dart';
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

/// "Menu position" picker for tablets: a small tablet preview where the menu
/// glides to the chosen spot, and a 3×3 grid of the 8 positions.
Future<void> showNavDockPicker(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    title: 'ตำแหน่งเมนู',
    child: const _NavDockPicker(),
  );
}

class _NavDockPicker extends StatelessWidget {
  const _NavDockPicker();

  static const _grid = <NxNavDock?>[
    NxNavDock.topLeft, NxNavDock.topCenter, NxNavDock.topRight,
    NxNavDock.left, null, NxNavDock.right,
    NxNavDock.bottomLeft, NxNavDock.bottomCenter, NxNavDock.bottomRight,
  ];

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dock = config.navDock;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('ใช้เมื่อเปิดบนแท็บเล็ตหรือจอกว้าง (มือถือแสดงแถบล่างเสมอ)'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Center(child: NxNavDockPreview(dock: dock)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.4,
          children: [
            for (final d in _grid)
              if (d == null)
                Center(child: Icon(NxI.monitorSmartphone, size: 20, color: cs.outline))
              else
                _DockChip(dock: d, selected: d == dock),
          ],
        ),
      ],
    );
  }
}

class _DockChip extends StatelessWidget {
  const _DockChip({required this.dock, required this.selected});
  final NxNavDock dock;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('nav-dock-${dock.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          context.read<AppConfig>().setNavDock(dock);
        },
        child: Center(
          child: Text(
            tr(dock.label),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? cs.onPrimary : cs.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

/// Mini tablet with the menu card at [dock]; moves with an animation.
class NxNavDockPreview extends StatelessWidget {
  const NxNavDockPreview({super.key, required this.dock, this.width = 240});
  final NxNavDock dock;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const d = Duration(milliseconds: 480);
    const curve = Curves.easeInOutCubic;
    final h = width * 0.68;
    const bar = 14.0;
    const m = 7.0;
    final room = bar + m * 2;
    Widget lines() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in [0.7, 1.0, 0.85, 1.0, 0.6])
              FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                ),
              ),
          ],
        );
    return Container(
      key: const ValueKey('nav-dock-preview'),
      width: width,
      height: h,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedPadding(
                  duration: d,
                  curve: curve,
                  padding: EdgeInsets.only(
                    left: (dock == NxNavDock.left ? room : 0) + 12,
                    right: (dock == NxNavDock.right ? room : 0) + 12,
                    top: (dock.isTop ? room : 0) + 12,
                    bottom: dock.isBottom ? room : 0,
                  ),
                  child: ClipRect(child: lines()),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(m),
                  child: AnimatedAlign(
                    alignment: dock.alignment,
                    duration: d,
                    curve: curve,
                    child: AnimatedContainer(
                      key: const ValueKey('nav-dock-preview-bar'),
                      duration: d,
                      curve: curve,
                      width: dock.vertical ? bar : width * 0.42,
                      height: dock.vertical ? h * 0.62 : bar,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
