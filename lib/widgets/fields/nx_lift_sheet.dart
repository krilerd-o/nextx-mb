import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/nx_breakpoint.dart';
import '../nx_surface_card.dart';

/// Compact: lift sheet. Two-pane: anchored popover near the field.
Future<T?> showNxLiftSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scroll) builder,
}) {
  if (NxBreakpoint.of(context).twoPane) {
    return _showAnchoredPopover<T>(context: context, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset > 0 ? inset + 16 : 0),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: inset > 0 ? 0.85 : 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scroll) {
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Expanded(child: builder(context, scroll)),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Future<T?> _showAnchoredPopover<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scroll) builder,
}) {
  // Field rect in global (root) coordinates.
  final box = context.findRenderObject() as RenderBox?;
  Rect field = const Rect.fromLTWH(24, 96, 0, 24);
  if (box != null && box.hasSize) field = box.localToGlobal(Offset.zero) & box.size;
  // The dialog is laid out inside one side of a fold (DisplayFeatureSubScreen
  // gives it only that side), so work out that side here, in global coords.
  final screen = MediaQuery.sizeOf(context);
  final hinge = NxBreakpoint.verticalHinge(context);
  var area = Offset.zero & screen;
  if (hinge != null) {
    area = field.center.dx < hinge.left ? Rect.fromLTRB(0, 0, hinge.left, screen.height) : Rect.fromLTRB(hinge.right, 0, screen.width, screen.height);
  }
  final reduced = NxMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    // Opens on the side of the fold the field is on (DisplayFeatureSubScreen).
    anchorPoint: field.center,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: NxMotion.duration(context, 400),
    pageBuilder: (ctx, _, _) => _PopoverBody(field: field, area: area, reduced: reduced, builder: builder),
    transitionBuilder: (ctx, anim, _, child) {
      final t = reduced ? 1.0 : NxMotion.settleCurve.transform(anim.value);
      return Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + (0.04 * t), alignment: Alignment.topLeft, child: child),
      );
    },
  );
}

/// Where the popover goes inside [area] (the dialog's sub-screen, global
/// coords): under the field, else above it; never under the keyboard.
Rect liftPopoverRect({required Rect field, required Rect area, required double keyboard, double width = 360, double height = 420}) {
  const m = 16.0;
  final w = width.clamp(0.0, area.width - 2 * m);
  final bottom = area.bottom - keyboard - m;
  var left = field.left.clamp(area.left + m, area.right - w - m);
  final below = bottom - (field.bottom + 8);
  final above = field.top - 8 - (area.top + m);
  double top, h;
  if (below >= height || below >= above) {
    top = field.bottom + 8;
    h = height.clamp(0.0, below);
  } else {
    h = height.clamp(0.0, above);
    top = field.top - 8 - h;
  }
  if (h < 160) {
    // Too tight around the field: use the free space of the area instead.
    h = (bottom - area.top - m).clamp(0.0, height);
    top = bottom - h;
  }
  // Never below the keyboard / area edge.
  if (top + h > bottom) top = bottom - h;
  if (top < area.top + m) {
    top = area.top + m;
    h = (bottom - top).clamp(0.0, height);
  }
  return Rect.fromLTWH(left - area.left, top - area.top, w, h);
}

class _PopoverBody extends StatefulWidget {
  const _PopoverBody({required this.field, required this.area, required this.reduced, required this.builder});

  final Rect field;
  final Rect area;
  final bool reduced;
  final Widget Function(BuildContext context, ScrollController scroll) builder;

  @override
  State<_PopoverBody> createState() => _PopoverBodyState();
}

class _PopoverBodyState extends State<_PopoverBody> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = liftPopoverRect(field: widget.field, area: widget.area, keyboard: MediaQuery.viewInsetsOf(context).bottom);
    return Stack(
      children: [
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: Material(
            color: NxAtmosphereTokens.of(context).cardElevated,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: NxSurfaceCard.shadows(Theme.of(context).brightness == Brightness.dark),
              ),
              child: widget.builder(context, _scroll),
            ),
          ),
        ),
      ],
    );
  }
}
