import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/effects.dart';
import '../core/i18n.dart';
import 'nx_icons.dart';

/// Covers the app for a moment while the UI language changes: the screen
/// blurs and dims, a pill shows the new language, the strings are swapped
/// underneath (every element rebuilt, state kept), then it all clears.
class NxLanguageSwitchLayer extends StatefulWidget {
  const NxLanguageSwitchLayer({super.key, required this.child});

  final Widget child;

  @override
  State<NxLanguageSwitchLayer> createState() => _NxLanguageSwitchLayerState();
}

class _NxLanguageSwitchLayerState extends State<NxLanguageSwitchLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 380),
  );
  String _label = '';

  @override
  void initState() {
    super.initState();
    L10n.switcher = _switch;
  }

  @override
  void dispose() {
    if (L10n.switcher == _switch) L10n.switcher = null;
    _c.dispose();
    super.dispose();
  }

  Future<void> _switch(String code, VoidCallback apply) async {
    if (!mounted) {
      apply();
      return;
    }
    final animate = Effects.animate(context);
    setState(() => _label = code == 'en' ? 'English' : 'ภาษาไทย');
    if (animate) await _c.forward(from: 0);
    apply();
    if (!mounted) return;
    rebuildAllChildren(context);
    // Let the translated frame paint under the cover before revealing it.
    final painted = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => painted.complete());
    await painted.future;
    if (!mounted) return;
    if (animate) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) await _c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blur = Effects.blur(context);
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_c.value);
            if (t == 0) return const SizedBox.shrink();
            Widget veil = ColoredBox(
              color: cs.surface.withValues(alpha: 0.55 * t),
            );
            if (blur) {
              veil = BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
                child: veil,
              );
            }
            return Positioned.fill(
              child: AbsorbPointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(child: veil),
                    Center(
                      child: Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.86 + 0.14 * t,
                          child: Material(
                            color: cs.inverseSurface,
                            shape: const StadiumBorder(),
                            elevation: 6,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.rotate(
                                    angle: (1 - t) * -1.2,
                                    child: Icon(
                                      NxI.globe,
                                      size: 20,
                                      color: cs.onInverseSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: cs.onInverseSurface),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
