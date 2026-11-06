import 'package:flutter/foundation.dart';

/// Holds a go_router location opened from a push notification until the session is ready.
class PushNavigation extends ChangeNotifier {
  PushNavigation._();
  static final PushNavigation instance = PushNavigation._();

  String? _pending;

  String? get pending => _pending;

  void remember(String? location) {
    if (location == null || location.isEmpty) return;
    _pending = location;
    notifyListeners();
  }

  String? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
