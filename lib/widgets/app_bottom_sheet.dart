import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/effects.dart';

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
  }) : super(
          backgroundColor: Colors.transparent,
          elevation: 0,
          modalBarrierColor: Colors.black.withValues(alpha: blur ? 0.18 : 0.38),
        );

  final bool blur;

  @override
  ui.ImageFilter? get filter => blur ? ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8) : null;
}

/// Rounded sheet body with grab handle.
class NxSheetBody extends StatelessWidget {
  const NxSheetBody({super.key, required this.child, this.title, this.padding});

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              child: Text(title!, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
  return Navigator.of(context).push<T>(
    NxSheetRoute<T>(
      blur: Effects.blur(context),
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
  List<double> snaps = const [0.5, 0.92],
  double? initial,
}) {
  final sizes = [...snaps]..sort();
  return Navigator.of(context).push<T>(
    NxSheetRoute<T>(
      blur: Effects.blur(context),
      builder: (ctx) => DraggableScrollableSheet(
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
  );
}
