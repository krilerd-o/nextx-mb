import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/nx_breakpoint.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/effects.dart';
import '../core/nx_motion.dart';
import 'nx_surface_card.dart';

/// Remembers where the user last pressed, so a menu can grow out of the
/// button that opened it without every caller passing its position.
class NxTapTracker {
  NxTapTracker._();
  static Offset? last;
  static DateTime? _at;
  static bool _on = false;

  static void ensure() {
    if (_on) return;
    _on = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) {
        last = e.position;
        _at = DateTime.now();
      }
    });
  }

  /// Records [context]'s widget (the button being activated) as the anchor.
  /// Needed when a tap arrives without a pointer event (screen readers).
  static void markFrom(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    last = box.localToGlobal(box.size.center(Offset.zero));
    _at = DateTime.now();
  }

  /// Wraps a button callback so the menu it opens grows from that button.
  static VoidCallback? from(BuildContext context, VoidCallback? onTap) => onTap == null
      ? null
      : () {
          markFrom(context);
          onTap();
        };

  /// The last press if it was recent enough to be the one opening a menu.
  static Offset? recent() {
    final at = _at;
    if (at == null || DateTime.now().difference(at) > const Duration(seconds: 3)) return null;
    return last;
  }
}

/// Command menu (⋯ and other action buttons) shown like the notification
/// tray: a card that grows out of the button it belongs to and sits next to
/// it — not a dialog in the middle of the screen.
///
/// [anchor] is the opening button's global rect; when omitted, the last
/// press position is used (see [NxTapTracker]), else the header's top-right.
Future<T?> showNxBlurPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Rect? anchor,
}) {
  HapticFeedback.selectionClick();
  final size = MediaQuery.sizeOf(context);
  final pad = MediaQuery.paddingOf(context);
  final tap = NxTapTracker.recent();
  final origin = anchor ??
      (tap != null ? Rect.fromCenter(center: tap, width: 40, height: 40) : Rect.fromLTWH(size.width - 56, pad.top + 8, 40, 40));
  return Navigator.of(context, rootNavigator: true).push<T>(_PopoverRoute<T>(
    anchor: origin,
    builder: builder,
    blur: Effects.blur(context),
    reduced: NxMotion.reduced(context),
  ));
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({required this.anchor, required this.builder, required this.blur, required this.reduced});
  final Rect anchor;
  final WidgetBuilder builder;
  final bool blur;
  final bool reduced;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: blur ? 0.12 : 0.28);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'ปิด';
  @override
  Duration get transitionDuration => Duration(milliseconds: reduced ? 0 : 340);
  @override
  Duration get reverseTransitionDuration => Duration(milliseconds: reduced ? 0 : 200);
  @override
  ui.ImageFilter? get filter => blur ? ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5) : null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      _Popover(anchor: anchor, animation: animation, builder: builder);
}

class _Popover extends StatelessWidget {
  const _Popover({required this.anchor, required this.animation, required this.builder});
  final Rect anchor;
  final Animation<double> animation;
  final WidgetBuilder builder;

  static const double _gap = 8;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final width = (size.width - _margin * 2).clamp(0.0, 300.0);
    // Open toward the roomier side of the button.
    final onRight = anchor.center.dx > size.width / 2;
    final below = anchor.center.dy < size.height * 0.55;
    // On an opened foldable keep the panel on the side of the fold it came from.
    var minX = _margin, maxX = size.width - _margin;
    final hinge = NxBreakpoint.verticalHinge(context);
    if (hinge != null) {
      if (anchor.center.dx < hinge.left) {
        maxX = hinge.left - _margin;
      } else {
        minX = hinge.right + _margin;
      }
    }
    final left = (onRight ? anchor.right - width : anchor.left).clamp(minX, (maxX - width).clamp(minX, maxX)).toDouble();
    final double maxH = below
        ? size.height - (anchor.bottom + _gap) - pad.bottom - _margin
        : anchor.top - _gap - pad.top - _margin;
    // Grow from the corner nearest the button.
    final grow = Alignment(onRight ? 1 : -1, below ? -1 : 1);
    final curved = CurvedAnimation(parent: animation, curve: NxMotion.settleCurve, reverseCurve: Curves.easeInCubic);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final card = Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH.clamp(120.0, size.height)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NxAtmosphereTokens.of(context).cardElevated,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            boxShadow: NxSurfaceCard.shadows(dark),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            // Own transparent Material so ListTile ink shows above the card fill.
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(child: Builder(builder: builder)),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: below ? (anchor.bottom + _gap).clamp(pad.top + _margin, size.height) : null,
          bottom: below ? null : (size.height - anchor.top + _gap).clamp(pad.bottom + _margin, size.height),
          child: AnimatedBuilder(
            animation: curved,
            child: card,
            builder: (context, child) {
              final t = curved.value;
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(
                  alignment: grow,
                  scale: 0.35 + 0.65 * t,
                  child: child,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
