import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Consent to send my data to third-party AI providers (App Store guideline 5.1.2(i)).
///
/// Asked once per user on this device, before the first AI feature: ISAAC, AI Assistant, AI Minute Meeting,
/// AI Notebook and the Home ISAAC brief. Declining keeps AI off; the rest of the app works. It can be
/// changed any time in Profile → ความเป็นส่วนตัวและ AI.
class AiConsent extends ChangeNotifier {
  AiConsent._();
  static final AiConsent instance = AiConsent._();

  /// Tests of other features run with consent given (see test/flutter_test_config.dart); the consent
  /// tests turn this off.
  static bool debugAssumeGranted = false;

  static const _prefix = 'ai_consent_v1_';
  final Map<String, bool> _cache = {};

  String _key(String? userId) => '$_prefix${(userId == null || userId.isEmpty) ? 'anon' : userId}';

  /// Known answer for [userId] without waiting (null = not loaded / never asked).
  bool? peek(String? userId) => debugAssumeGranted ? true : _cache[_key(userId)];

  Future<bool> isGranted(String? userId) async {
    if (debugAssumeGranted) return true;
    final k = _key(userId);
    final hit = _cache[k];
    if (hit != null) return hit;
    try {
      final v = (await SharedPreferences.getInstance()).getString(k);
      _cache[k] = v != null && v.startsWith('granted');
    } catch (_) {
      _cache[k] = false;
    }
    return _cache[k]!;
  }

  Future<void> set(String? userId, bool granted) async {
    final k = _key(userId);
    _cache[k] = granted;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(k, '${granted ? 'granted' : 'declined'}@${DateTime.now().toUtc().toIso8601String()}');
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() => _cache.clear();
}
