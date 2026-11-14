import 'package:flutter/foundation.dart';

/// Holds a go_router location opened from a push notification until the session is ready.
class PushNavigation extends ChangeNotifier {
  PushNavigation._();
  static final PushNavigation instance = PushNavigation._();

  String? _pending;
  String? _businessId;

  String? get pending => _pending;

  /// Business the pending notification belongs to (push `business_id`):
  /// when it is another Space's, the app switches there before opening it.
  String? get pendingBusinessId => _businessId;

  void remember(String? location, {String? businessId}) {
    if (location == null || location.isEmpty) return;
    _pending = location;
    final b = businessId?.trim();
    _businessId = (b == null || b.isEmpty) ? null : b;
    notifyListeners();
  }

  /// Open the pending location wherever the app is now.
  void clearBusiness({bool notify = true}) {
    if (_businessId == null) return;
    _businessId = null;
    if (notify) notifyListeners();
  }

  String? take() {
    final value = _pending;
    _pending = null;
    _businessId = null;
    return value;
  }
}
