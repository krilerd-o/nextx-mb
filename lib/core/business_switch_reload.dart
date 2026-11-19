import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';

/// Screens that list business data reload (and drop what they show) when the business changes, so a
/// list never shows another business's items after a switch.
mixin ReloadOnBusinessSwitch<T extends StatefulWidget> on State<T> {
  AppConfig? _bizConfig;
  String? _bizSeen;

  /// The business changed while this screen is open.
  void onBusinessSwitched();

  /// Call from initState.
  void watchBusiness() {
    final c = context.read<AppConfig>();
    _bizConfig = c;
    _bizSeen = c.session.businessId;
    c.addListener(_bizCheck);
  }

  void _bizCheck() {
    final bid = _bizConfig?.session.businessId;
    if (bid == _bizSeen) return;
    _bizSeen = bid;
    if (mounted) onBusinessSwitched();
  }

  @override
  void dispose() {
    _bizConfig?.removeListener(_bizCheck);
    super.dispose();
  }
}
