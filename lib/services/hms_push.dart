import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:huawei_push/huawei_push.dart';

import '../core/build_target.dart';
import '../core/navigation/notification_deep_link.dart';
import '../core/push_navigation.dart';

/// Huawei Push Kit for the AppGallery build (`--dart-define=NX_STORE=huawei`).
///
/// Needs `android/app/src/main/assets/agconnect-services.json` (CI writes it from
/// the AGCONNECT_SERVICES_JSON_BASE64 secret; never committed). Tokens are sent to
/// NEXTX with platform `huawei` and delivered by the server's HMS sender.
class HmsPush {
  HmsPush._();

  static bool get enabled => isHuaweiBuild && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static StreamSubscription<String>? _tokens;
  static Completer<String?>? _pending;
  static void Function(String token)? onTokenRefresh;

  /// Listens for taps on HMS notifications and for new tokens.
  static Future<void> init() async {
    if (!enabled) return;
    try {
      _tokens ??= Push.getTokenStream.listen(
        (t) {
          final p = _pending;
          if (p != null && !p.isCompleted) {
            p.complete(t);
          } else if (t.isNotEmpty) {
            onTokenRefresh?.call(t);
          }
        },
        onError: (Object e) {
          final p = _pending;
          if (p != null && !p.isCompleted) p.complete(null);
          debugPrint('[hms] token error: $e');
        },
      );
      final initial = await Push.getInitialNotification();
      _remember(initial);
      Push.onNotificationOpenedApp.listen(_remember);
    } catch (e) {
      debugPrint('[hms] init skipped: $e');
    }
  }

  /// The HMS token, or null when HMS Core is missing / not configured.
  static Future<String?> token({Duration timeout = const Duration(seconds: 8)}) async {
    if (!enabled) return null;
    await init();
    final c = Completer<String?>();
    _pending = c;
    try {
      Push.getToken('');
      final t = await c.future.timeout(timeout, onTimeout: () => null);
      return (t == null || t.isEmpty) ? null : t;
    } catch (e) {
      debugPrint('[hms] token: $e');
      return null;
    } finally {
      _pending = null;
    }
  }

  static Future<void> deleteToken() async {
    if (!enabled) return;
    try {
      await Push.deleteToken('');
    } catch (_) {}
  }

  static void _remember(dynamic opened) {
    final loc = deepLinkFromHmsTap(opened);
    if (loc != null) PushNavigation.instance.remember(loc);
  }
}

/// The app location carried by a tapped HMS notification: the server puts
/// `{url, id}` (same keys as FCM) in the message data; HMS hands it back in
/// `extras` or as the JSON `remoteMessage.data`.
@visibleForTesting
String? deepLinkFromHmsTap(dynamic opened) {
  if (opened is! Map) return null;
  final data = <String, dynamic>{};
  final extras = opened['extras'];
  if (extras is Map) data.addAll(extras.map((k, v) => MapEntry('$k', v)));
  final rm = opened['remoteMessage'];
  final raw = rm is Map ? rm['data'] : null;
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      final m = jsonDecode(raw);
      if (m is Map) data.addAll(m.map((k, v) => MapEntry('$k', v)));
    } catch (_) {}
  } else if (raw is Map) {
    data.addAll(raw.map((k, v) => MapEntry('$k', v)));
  }
  if (data.isEmpty) return null;
  return notificationDeepLinkFromData(data);
}
