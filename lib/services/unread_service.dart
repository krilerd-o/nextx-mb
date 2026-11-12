import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/approval_queue.dart';
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

/// Items waiting for *my* approval (badge on the "รออนุมัติ" menu).
/// New servers: `/api/approvals/inbox` count (quotations + activities + jobs
/// sent to me). Older servers: quotations waiting on me.
class PendingApprovals extends ChangeNotifier {
  PendingApprovals._() {
    _sub = RealtimeService.instance.on('notification').listen((_) => _soon());
  }
  static final PendingApprovals instance = PendingApprovals._();

  // ignore: unused_field
  late final StreamSubscription<RealtimeEvent> _sub;
  int _count = 0;
  ApiClient? _api;
  String? _userId;
  Timer? _debounce;

  int get count => _count;

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      final api = _api;
      if (api != null) refresh(api, userId: _userId);
    });
  }

  Future<void> refresh(ApiClient api, {String? userId}) async {
    _api = api;
    _userId = userId ?? _userId;
    var n = 0;
    try {
      final inbox = await api.getApprovalInbox();
      n = int.tryParse('${inbox['count'] ?? ''}') ??
          [for (final k in ['quotations', 'activities', 'jobs']) (inbox[k] is List ? (inbox[k] as List).length : 0)].fold(0, (a, b) => a + b);
    } catch (_) {
      try {
        final rows = await api.getPendingQuotationApprovals();
        n = rows.where((r) => isAwaitingMyApproval(r, _userId)).length;
      } catch (e) {
        debugPrint('[approvals] $e');
        return;
      }
    }
    if (n != _count) {
      _count = n;
      notifyListeners();
    }
  }

  void clear() {
    _count = 0;
    notifyListeners();
  }
}
