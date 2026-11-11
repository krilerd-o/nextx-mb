import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device is on a metered link (mobile data) — used to skip
/// heavy downloads such as animated Isaac GIFs. Wi-Fi / ethernet = not metered.
class NxNetwork {
  NxNetwork._();
  static final instance = NxNetwork._();

  /// true on mobile data only (unknown = false, so nothing is hidden by mistake).
  final ValueNotifier<bool> metered = ValueNotifier(false);

  /// false when the phone has no network at all (used to resend saved work).
  final ValueNotifier<bool> online = ValueNotifier(true);

  void _apply(List<ConnectivityResult> r) {
    metered.value = isMetered(r);
    online.value = r.isNotEmpty && !(r.length == 1 && r.first == ConnectivityResult.none);
  }
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  static bool isMetered(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.mobile) && !r.contains(ConnectivityResult.wifi) && !r.contains(ConnectivityResult.ethernet);

  void ensureStarted() {
    if (_started) return;
    _started = true;
    try {
      final c = Connectivity();
      c.checkConnectivity().then<void>(_apply).catchError((Object _) {});
      _sub = c.onConnectivityChanged.listen(_apply, onError: (_) {});
    } catch (_) {
      // No plugin (tests / unsupported platform): treat as unmetered.
    }
  }

  @visibleForTesting
  void debugSet(bool value) {
    _started = true;
    _sub?.cancel();
    metered.value = value;
  }
}
