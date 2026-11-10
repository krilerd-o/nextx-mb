import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/effects.dart';
import '../core/i18n.dart';
import 'nx_overlay_panel.dart' show NxTapTracker;

/// Bottom sheet route whose barrier blurs the page behind (expo-backdrop),
/// falling back to a plain dim on lite/off devices.
class NxSheetRoute<T> extends ModalBottomSheetRoute<T> {
  NxSheetRoute({
    required super.builder,
    required this.blur,
    super.isScrollControlled = true,
    super.showDragHandle = false,
    super.useSafeArea = false,
    super.settings,
    super.anchorPoint,
  }) : super(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // Dim + blur are drawn in buildTransitions so they follow the drag.
          modalBarrierColor: Colors.transparent,
        );

  final bool blur;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // The route animation tracks the sheet while it is dragged, so the
    // backdrop blurs/dims in step with the finger (expo-backdrop).
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
                final dim = ColoredBox(color: Colors.black.withValues(alpha: (blur ? 0.22 : 0.4) * t));
                if (!blur || t < 0.02) return dim;
                return BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t), child: dim);
              },
            ),
          ),
        ),
        super.buildTransitions(context, animation, secondaryAnimation, child),
      ],
    );
  }
}

/// Rounded sheet body with grab handle.
class NxSheetBody extends StatelessWidget {
  const NxSheetBody({super.key, required this.child, this.title, this.padding});

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry? padding;

  /// Tallest a sheet may be: 85% of the screen and always clear of the
  /// status bar, like the other sheets (long lists scroll inside instead of
  /// pushing the sheet up to the top edge).
  static double maxHeightOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    final belowBar = h - mq.padding.top - 24;
    final cap = h * 0.85;
    return cap < belowBar ? cap : belowBar;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeightOf(context)),
      child: _body(context, cs),
    );
  }

  Widget _body(BuildContext context, ColorScheme cs) {
    return Material(
      color: Theme.of(context).bottomSheetTheme.backgroundColor ?? cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Text(tr(title!), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          Flexible(child: Padding(padding: padding ?? EdgeInsets.zero, child: child)),
        ],
      ),
    );
  }
}

/// Short sheet sized to content (actions, confirm, forms).
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  // Root navigator: above the tab bar and any nested list navigator, so
  // system back closes the sheet. anchorPoint: opens on the tapped side of a fold.
  return Navigator.of(context, rootNavigator: true).push<T>(
    NxSheetRoute<T>(
      blur: Effects.blur(context),
      anchorPoint: NxTapTracker.recent(),
      builder: (ctx) => NxSheetBody(
        title: title,
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.paddingOf(ctx).bottom + MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// Tall sheet that snaps between [snaps] (fractions of screen height) and
/// hands its scroll controller to [builder] so lists drag the sheet.
Future<T?> showNxSnapSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController controller) builder,
  String? title,
  List<double> snaps = const [0.5, 0.85],
  double? initial,
}) {
  final sizes = [...snaps]..sort();
  return Navigator.of(context, rootNavigator: true).push<T>(
    NxSheetRoute<T>(
      blur: Effects.blur(context),
      anchorPoint: NxTapTracker.recent(),
      // Lift the whole sheet above the keyboard (search fields in it).
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          snap: true,
          minChildSize: sizes.first * 0.6,
          initialChildSize: initial ?? sizes.first,
          maxChildSize: sizes.last,
          snapSizes: sizes,
          builder: (ctx, controller) => NxSheetBody(
            title: title,
            child: builder(ctx, controller),
          ),
        ),
      ),
    ),
  );
}

/// Height for a sheet of [fraction] of the screen that still fits above the
/// keyboard (pair with bottom padding = viewInsets).
double nxSheetHeight(BuildContext context, double fraction) {
  final mq = MediaQuery.of(context);
  final room = mq.size.height - mq.viewInsets.bottom - mq.padding.top - 24;
  final want = mq.size.height * fraction;
  return want < room ? want : (room < 160 ? 160 : room);
}
