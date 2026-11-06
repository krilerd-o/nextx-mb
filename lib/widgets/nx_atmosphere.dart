import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Single Inbox-tone fill so white cards can float.
class NxAtmosphere extends StatelessWidget {
  const NxAtmosphere({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = NxAtmosphereTokens.of(context);
    return ColoredBox(
      color: tokens.bottom,
      child: child,
    );
  }
}
