import 'package:flutter/cupertino.dart';

import 'nx_breakpoint.dart';

Future<T?> nxPush<T>(BuildContext context, Widget page, {bool? root}) {
  final useRoot = root ?? !NxBreakpoint.of(context).twoPane;
  return Navigator.of(context, rootNavigator: useRoot).push<T>(
    CupertinoPageRoute<T>(builder: (_) => page),
  );
}
