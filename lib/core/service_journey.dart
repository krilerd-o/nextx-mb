import 'package:flutter/foundation.dart';

import '../services/api_client.dart';

/// Whether the current server has NEXTX Service Journey (Quotation / Job
/// workflow, overview, photos, signatures…). Older servers keep using the
/// generic entity detail screen.
class ServiceJourney {
  ServiceJourney._();

  static final Map<String, Future<bool>> _cache = {};

  /// Cached per server for the session (a probe that fails offline is retried).
  static Future<bool> supported(ApiClient api) {
    final key = api.baseUrl;
    final hit = _cache[key];
    if (hit != null) return hit;
    final f = api.probeServiceJourney().catchError((Object _) {
      _cache.remove(key); // offline / error: probe again next time
      return false;
    });
    _cache[key] = f;
    return f;
  }

  /// Modules that get the journey detail screen.
  static const modules = {'job', 'quotation'};

  static bool handles(String module) => modules.contains(module);

  @visibleForTesting
  static void debugSet(String baseUrl, bool value) => _cache[baseUrl] = Future.value(value);

  @visibleForTesting
  static void debugClear() => _cache.clear();
}
