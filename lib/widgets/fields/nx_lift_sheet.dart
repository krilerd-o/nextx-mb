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
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  var left = 24.0;
  var top = 120.0;
  if (box != null && overlay != null && box.hasSize) {
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    left = origin.dx;
    top = origin.dy + box.size.height + 8;
  }
  final screen = MediaQuery.sizeOf(context);
  const width = 360.0;
  const height = 420.0;
  left = left.clamp(16.0, screen.width - width - 16);
  top = top.clamp(24.0, screen.height - height - 24);

  final reduced = NxMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: NxMotion.duration(context, 400),
    pageBuilder: (ctx, _, _) {
      return _PopoverBody(
        left: left,
        top: top,
        width: width,
        height: height,
        reduced: reduced,
        builder: builder,
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final t = reduced ? 1.0 : NxMotion.settleCurve.transform(anim.value);
      return Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + (0.04 * t), alignment: Alignment.topLeft, child: child),
      );
    },
  );
}

class _PopoverBody extends StatefulWidget {
  const _PopoverBody({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.reduced,
    required this.builder,
  });

  final double left;
  final double top;
  final double width;
  final double height;
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
    return Stack(
      children: [
        Positioned(
          left: widget.left,
          top: widget.top,
          width: widget.width,
          height: widget.height,
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
