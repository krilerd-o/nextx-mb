import 'package:flutter/cupertino.dart';
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
