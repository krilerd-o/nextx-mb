import 'package:flutter/material.dart';

/// Thin progress line shown while a screen that already shows (cached) data
/// refreshes in the background — instead of swapping the page for a skeleton.
class NxRefreshBar extends StatelessWidget {
  const NxRefreshBar({super.key, required this.visible});
  final bool visible;

  static const height = 2.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: visible
          ? LinearProgressIndicator(
              key: const ValueKey('nx-refresh-bar'),
              minHeight: height,
              backgroundColor: Colors.transparent,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            )
          : null,
    );
  }
}

/// [child] with an [NxRefreshBar] laid over its top edge (no layout shift).
class NxRefreshOverlay extends StatelessWidget {
  const NxRefreshOverlay({super.key, required this.refreshing, required this.child, this.top = 0});
  final bool refreshing;
  final Widget child;

  /// Distance from the top (e.g. under a floating header).
  final double top;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned(left: 0, right: 0, top: top, child: IgnorePointer(child: NxRefreshBar(visible: refreshing))),
    ]);
  }
}
