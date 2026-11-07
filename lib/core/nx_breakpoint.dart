import 'package:flutter/material.dart';

export 'nx_motion.dart';

enum NxSize { mini, mobile, tablet, desktop, wide }

/// Window width only — never switch layout just because of landscape.
class NxBreakpoint {
  const NxBreakpoint._(this.size, this.width, this.height);

  final NxSize size;
  final double width;
  final double height;

  static NxBreakpoint of(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final w = mq.width;
    final NxSize size;
    if (w < 360) {
      size = NxSize.mini;
    } else if (w < 600) {
      size = NxSize.mobile;
    } else if (w < 840) {
      size = NxSize.tablet;
    } else if (w < 1200) {
      size = NxSize.desktop;
    } else {
      size = NxSize.wide;
    }
    return NxBreakpoint._(size, w, mq.height);
  }

  bool get isMini => size == NxSize.mini;
  bool get isCompact => size == NxSize.mini || size == NxSize.mobile;
  /// Rail / two-pane need width and enough height so a phone in landscape
  /// keeps the bottom glass bar (width-only would treat 844×390 as desktop).
  bool get useRail => !isCompact && height >= 600;
  bool get twoPane => useRail;
  bool get iconOnlyNav => isMini;

  double get titleSize => isMini ? 22 : 28;

  int get gridColumns {
    switch (size) {
      case NxSize.mini:
        return 1;
      case NxSize.mobile:
        return 2;
      case NxSize.tablet:
        return 3;
      case NxSize.desktop:
      case NxSize.wide:
        return 4;
    }
  }

  double get formMaxWidth {
    switch (size) {
      case NxSize.mini:
      case NxSize.mobile:
        return double.infinity;
      case NxSize.tablet:
        return 560;
      case NxSize.desktop:
      case NxSize.wide:
        return 640;
    }
  }

  double get contentMaxWidth {
    switch (size) {
      case NxSize.wide:
        return 1120;
      case NxSize.desktop:
        return 960;
      default:
        return double.infinity;
    }
  }

  double get listPaneWidth {
    if (size == NxSize.tablet) return (width * 0.38).clamp(280, 360);
    return 360;
  }

  double get pagePadding {
    if (isMini) return 12;
    if (useRail) return 24;
    return 16;
  }

  EdgeInsets bodyInsets(BuildContext context, {bool rail = false}) {
    final pad = MediaQuery.paddingOf(context);
    if (rail) {
      return EdgeInsets.only(left: 12, right: pagePadding, bottom: pad.bottom + 12);
    }
    return EdgeInsets.only(bottom: 88 + pad.bottom);
  }

  EdgeInsets scrollPadding(BuildContext context, {bool inShell = false, bool hasFab = false}) {
    final h = pagePadding;
    var bottom = 24.0;
    if (inShell) {
      bottom = bodyInsets(context, rail: useRail).bottom;
    } else if (hasFab) {
      bottom = 88;
    }
    // Inside the tab shell the floating bar adds to the bottom padding.
    final safe = MediaQuery.paddingOf(context).bottom;
    if (safe > 0) bottom = (hasFab ? 88 : 24) + safe;
    return EdgeInsets.fromLTRB(h, 8, h, bottom);
  }
}

class NxContentWidth extends StatelessWidget {
  const NxContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final cap = maxWidth ?? NxBreakpoint.of(context).formMaxWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = cap.isFinite && cap < constraints.maxWidth ? cap : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: w,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}

