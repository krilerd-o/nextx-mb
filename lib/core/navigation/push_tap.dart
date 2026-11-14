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

  final isIos = ios ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  String? store;
  if (s('event') == 'app_update') {
    store = isIos ? (s('store_ios') ?? s('store_android')) : (s('store_android') ?? s('store_ios'));
    final u = store == null ? null : Uri.tryParse(store);
    if (u == null || !u.hasScheme) store = null;
  }
  return PushTap(location: notificationDeepLinkFromData(data), businessId: s('business_id'), storeUrl: store);
}

/// Opens the store ([storeUrl]) — replaced in tests.
@visibleForTesting
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
