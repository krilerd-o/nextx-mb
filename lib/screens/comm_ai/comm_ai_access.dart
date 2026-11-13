import '../../services/api_client.dart';

/// What `GET /api/comm-ai/settings` says about this business: the Package is on (`available`),
/// the ISAAC dashboard is on (`insights_available`), and whether this user can change the settings.
/// Cached per [ApiClient] (one per signed-in session); call [invalidate] after saving settings.
class CommAiAccess {
  const CommAiAccess({this.available = true, this.insights = true, this.canEdit = false, this.settings = const {}});

  /// Older servers do not send the flags → treat as on (the server still refuses what is off).
  factory CommAiAccess.fromSettings(Map<String, dynamic> r) => CommAiAccess(
        available: r['available'] != false,
        insights: r['available'] != false && r['insights_available'] != false,
        canEdit: r['can_edit'] == true,
        settings: r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : const {},
      );

  final bool available;
  final bool insights;
  final bool canEdit;
  final Map<String, dynamic> settings;

  static final _cache = Expando<Future<CommAiAccess>>('commAiAccess');

  static Future<CommAiAccess> of(ApiClient api) {
    final hit = _cache[api];
    if (hit != null) return hit;
    final f = api.getCommAiSettings().then(CommAiAccess.fromSettings).catchError((Object _) {
      // Unknown (offline, old server): keep the actions and ask again next time.
      _cache[api] = null;
      return const CommAiAccess();
    });
    return _cache[api] = f;
  }

  static void invalidate(ApiClient api) => _cache[api] = null;
}
