import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyAppLock = 'app_lock_biometric_v1';

/// Lock again when the app was in the background at least this long.
const kAppLockIdle = Duration(minutes: 5);

/// True when coming back to the app should show the lock screen.
bool shouldLockOnResume({required bool enabled, required DateTime? pausedAt, required DateTime now, Duration idle = kAppLockIdle}) =>
    enabled && pausedAt != null && now.difference(pausedAt) >= idle;

/// Optional fingerprint / face unlock. The session token stays in secure
/// storage as before — this only hides the app until the owner unlocks it.
class AppLock extends ChangeNotifier {
  AppLock._();
  static final AppLock instance = AppLock._();

  final LocalAuthentication _auth = LocalAuthentication();
  bool _enabled = false;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _pausedAt;

  bool get enabled => _enabled;
  bool get locked => _locked;

  /// Startup: lock right away when enabled (a cold start counts as "away").
  Future<void> load({required bool loggedIn}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_keyAppLock) ?? false;
    } catch (_) {
      _enabled = false;
    }
    _locked = _enabled && loggedIn;
    notifyListeners();
  }

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Turning it on asks for a scan first so nobody locks themselves out.
  Future<bool> setEnabled(bool on) async {
    if (on && !await authenticate()) return false;
    _enabled = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAppLock, on);
    notifyListeners();
    return true;
  }

  void onPaused() {
    if (_authenticating) return; // the system prompt itself pauses the app
    _pausedAt ??= DateTime.now();
  }

  void onResumed({required bool loggedIn}) {
    if (_authenticating) return;
    if (loggedIn && shouldLockOnResume(enabled: _enabled, pausedAt: _pausedAt, now: DateTime.now())) {
      _locked = true;
      notifyListeners();
    }
    _pausedAt = null;
  }

  Future<bool> authenticate() async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: 'ยืนยันตัวตนเพื่อเปิด MOAI NEXT',
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('AppLock: $e');
      return false;
    } finally {
      _authenticating = false;
      _pausedAt = null;
    }
  }

  Future<bool> unlock() async {
    final ok = await authenticate();
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// Signed out: nothing left to protect.
  void reset() {
    _locked = false;
    _pausedAt = null;
    notifyListeners();
  }
}
