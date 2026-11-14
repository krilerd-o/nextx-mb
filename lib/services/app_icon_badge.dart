import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

/// Sets the number on the app icon. Replaced in tests.
abstract class AppIconBadgeBackend {
  Future<void> update(int count);
}

/// `app_badge_plus`: iOS (UNUserNotificationCenter) and the Android launchers
/// that support numbers (Samsung, Huawei/Honor, Xiaomi, OPPO, vivo, Sony, …).
/// Launchers without numbers keep the system's notification dot.
class PluginAppIconBadge implements AppIconBadgeBackend {
  bool? _supported;

  @override
  Future<void> update(int count) async {
    if (kIsWeb) return;
    _supported ??= await AppBadgePlus.isSupported();
    if (_supported != true) return;
    await AppBadgePlus.updateBadge(count);
  }
}

/// The app icon's badge follows the unread notification count
/// ([UnreadNotifications] calls [set] on start / resume, foreground push,
/// read / read all, logout). While the app is closed only the server's push
/// can change it — see docs/PUSH_SETUP.md (iOS needs `apns.badge`).
class AppIconBadge {
  AppIconBadge._();
  static final AppIconBadge instance = AppIconBadge._();

  AppIconBadgeBackend backend = PluginAppIconBadge();

  int? _last;

  /// Last number sent to the icon (null before the first one).
  int? get last => _last;

  Future<void> set(int count) async {
    final n = count < 0 ? 0 : count;
    if (n == _last) return;
    _last = n;
    try {
      await backend.update(n);
    } catch (e) {
      // No plugin (tests, unsupported platform) or the launcher refused.
      debugPrint('[badge] $e');
    }
  }

  Future<void> clear() => set(0);

  @visibleForTesting
  void debugReset() => _last = null;
}
