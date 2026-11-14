import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../push_navigation.dart';
import 'notification_deep_link.dart';

/// What tapping one push notification does (from its `data`, all strings):
/// open [location] in the app — in the Space of [businessId] when that is
/// another one — or, for `app_update` with a store link, open the store.
@immutable
class PushTap {
  const PushTap({this.location, this.businessId, this.storeUrl});
  final String? location;
  final String? businessId;
  final String? storeUrl;

  @override
  String toString() => 'PushTap($location, business: $businessId, store: $storeUrl)';
}

/// Keys of the push `data` kept in a foreground notification's payload.
const pushDataKeys = [
  'url', 'link_path', 'id', 'link_id', 'extra', 'link_extra', 'event', 'business_id', //
  'notification_id', 'store_android', 'store_ios', 'type',
];

PushTap pushTapFromData(Map<String, dynamic> data, {bool? ios}) {
  String? s(String k) {
    final v = data[k]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  return PushTap(
    location: notificationDeepLinkFromData(data),
    businessId: s('business_id'),
    storeUrl: s('event') == 'app_update' ? appStoreLinkOf(data, ios: ios) : null,
  );
}

/// Store link of an app update for this platform (`store_ios` /
/// `store_android`, the other one as a fallback, then an `http(s)` `url` —
/// round-1 system broadcasts put the store there). Null when none is usable.
String? appStoreLinkOf(Map<String, dynamic> data, {bool? ios}) {
  String? s(String k) {
    final v = data[k]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  bool usable(String? v) {
    final u = v == null ? null : Uri.tryParse(v);
    return u != null && (u.scheme == 'https' || u.scheme == 'http' || u.scheme == 'market' || u.scheme == 'itms-apps') && (u.host.isNotEmpty || u.scheme == 'market');
  }

  final isIos = ios ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  final order = isIos ? ['store_ios', 'store_android'] : ['store_android', 'store_ios'];
  for (final k in [...order, 'url']) {
    if (usable(s(k))) return s(k);
  }
  return null;
}

/// Opens the store (an app update) outside the app — replaced in tests.
Future<bool> Function(Uri uri) pushStoreLauncher = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Acts on a tapped push: the store for an app update, otherwise its screen
/// (after switching Space when the notification is from another business).
Future<void> handlePushTap(Map<String, dynamic> data) async {
  final tap = pushTapFromData(data);
  final store = tap.storeUrl;
  if (store != null) {
    try {
      if (await pushStoreLauncher(Uri.parse(store))) return;
    } catch (e) {
      debugPrint('[push] store: $e');
    }
  }
  PushNavigation.instance.remember(tap.location, businessId: tap.businessId);
}

/// Payload of a local (foreground) notification: the push data as JSON.
String encodePushPayload(Map<String, dynamic> data) => jsonEncode({
      for (final k in pushDataKeys)
        if (data[k] != null && '${data[k]}'.isNotEmpty) k: '${data[k]}',
    });

/// Tap on a local notification: a JSON push payload, or (birthday reminders,
/// older builds) a plain app location.
Future<void> handleNotificationPayload(String? payload) async {
  final p = payload?.trim() ?? '';
  if (p.isEmpty) return;
  if (p.startsWith('{')) {
    try {
      final m = jsonDecode(p);
      if (m is Map) {
        await handlePushTap(m.map((k, v) => MapEntry('$k', v)));
        return;
      }
    } catch (_) {}
  }
  PushNavigation.instance.remember(p);
}
