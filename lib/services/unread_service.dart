import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'realtime_service.dart';

/// Unread count from `GET /api/notifications/summary`
/// (`{ total, by_category }`); older shapes (`unread`, list rows) still work.
int parseUnreadSummary(Map<String, dynamic> summary) {
  for (final key in const ['total', 'unread', 'unread_count']) {
    final v = summary[key];
    if (v is num) return v.toInt();
  }
  var sum = 0;
  for (final row in extractMapList(summary)) {
    sum += (row['unread'] as num?)?.toInt() ?? (row['count'] as num?)?.toInt() ?? 0;
  }
  return sum;
}

/// App-wide unread notification count shared by every bell/badge.
class UnreadNotifications extends ChangeNotifier {
  UnreadNotifications._() {
    _sub = RealtimeService.instance.on('notification').listen((_) => bump());
  }
  static final UnreadNotifications instance = UnreadNotifications._();

  // ignore: unused_field
  late final StreamSubscription<RealtimeEvent> _sub;
  int _count = 0;
  ApiClient? _api;

  int get count => _count;

  void _set(int v) {
    final next = v < 0 ? 0 : v;
    if (next == _count) return;
    _count = next;
    notifyListeners();
  }

  /// Re-reads the server count. Safe to call often (resume, after login).
  Future<void> refresh(ApiClient api) async {
    _api = api;
    try {
      _set(parseUnreadSummary(await api.getNotificationSummary()));
    } catch (e) {
      debugPrint('[unread] $e');
    }
  }

  Future<void> refreshIfBound() async {
    final api = _api;
    if (api != null) await refresh(api);
  }

  void bump() => _set(_count + 1);
  void markedRead() => _set(_count - 1);
  void clear() => _set(0);
}
