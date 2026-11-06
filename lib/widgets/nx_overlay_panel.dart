import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/nx_motion.dart';
import 'nx_surface_card.dart';

Future<T?> showNxBlurPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final reduced = NxMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(0.28),
    transitionDuration: NxMotion.duration(context, 400),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: NxAtmosphereTokens.of(ctx).cardElevated,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    boxShadow: NxSurfaceCard.shadows(Theme.of(ctx).brightness == Brightness.dark),
                  ),
                  child: builder(ctx),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final t = reduced ? 1.0 : NxMotion.settleCurve.transform(anim.value);
      return Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + (0.04 * t), child: child),
      );
    },
  );
}
