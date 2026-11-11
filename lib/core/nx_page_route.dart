import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:go_router/go_router.dart';

import 'nx_breakpoint.dart';

Future<T?> nxPush<T>(BuildContext context, Widget page, {bool? root}) {
  final useRoot = root ?? !NxBreakpoint.of(context).twoPane;
  return Navigator.of(context, rootNavigator: useRoot).push<T>(
    CupertinoPageRoute<T>(builder: (_) => page),
  );
}

/// Leave the current page: pop when something is underneath, otherwise go
/// home (a page opened alone from a notification / link).
void nxLeavePage(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    GoRouter.of(context).go('/main');
  }
}

/// Opens a record's detail page. Phone: full page (like [nxPush]).
/// Tablet / unfolded, from screens that need their full width (calendar,
/// boards, search): a panel slides in from the right over the page, with its
/// own navigator; tap outside or back to close.
Future<T?> nxOpenDetail<T>(BuildContext context, Widget page, {bool? root}) {
  if (!NxBreakpoint.of(context).twoPane) return nxPush<T>(context, page, root: root ?? true);
  return Navigator.of(context, rootNavigator: true).push<T>(NxSidePanelRoute<T>(child: page));
}

class NxSidePanelRoute<T> extends PopupRoute<T> {
  NxSidePanelRoute({required this.child});
  final Widget child;

  @override
  Color? get barrierColor => const Color(0x52000000);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'close';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.5).clamp(420.0, 640.0);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        key: const ValueKey('side-panel'),
        width: width > size.width ? size.width : width,
        height: double.infinity,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
          child: HeroControllerScope.none(
            child: Navigator(onGenerateRoute: (s) => CupertinoPageRoute<void>(settings: s, builder: (_) => child)),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(a), child: child);
  }
}
