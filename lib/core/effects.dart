import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much visual effect (blur, shaders, motion) the device should draw.
///
/// * [full] — backdrop blur, progressive blur, shader headers, motion blur.
/// * [lite] — translucent fills instead of live blur; simple animations.
/// * [off]  — flat surfaces, no decorative animation (also used when the OS
///   asks to reduce motion).
enum EffectsLevel { full, lite, off }

/// User choice in settings; `auto` picks from the device.
enum EffectsPreference { auto, full, lite, off }

class Effects {
  Effects._();

  static const _prefKey = 'nx_effects_pref';

  /// Default is "เบา" (lite) until the user picks something else.
  static final ValueNotifier<EffectsPreference> preference = ValueNotifier(EffectsPreference.lite);

  /// Set once at startup from the device (CPU cores / platform).
  static EffectsLevel deviceDefault = EffectsLevel.full;

  static Future<void> init() async {
    deviceDefault = _detect();
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      preference.value = EffectsPreference.values.firstWhere((e) => e.name == raw, orElse: () => EffectsPreference.lite);
    } catch (_) {}
  }

  static Future<void> setPreference(EffectsPreference v) async {
    preference.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, v.name);
    } catch (_) {}
  }

  static EffectsLevel _detect() {
    if (kIsWeb) return EffectsLevel.lite;
    // Low-end Android phones usually have ≤4 cores; live blur costs them frames.
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final cores = _cores();
        if (cores > 0 && cores <= 4) return EffectsLevel.lite;
      }
    } catch (_) {}
    return EffectsLevel.full;
  }

  static int _cores() => _coreCounter?.call() ?? 0;

  /// Injected from main (dart:io is not available on web).
  static int Function()? _coreCounter;
  static void setCoreCounter(int Function() f) => _coreCounter = f;

  static EffectsLevel resolve(EffectsPreference pref, {bool reduceMotion = false}) {
    if (reduceMotion) return EffectsLevel.off;
    switch (pref) {
      case EffectsPreference.full:
        return EffectsLevel.full;
      case EffectsPreference.lite:
        return EffectsLevel.lite;
      case EffectsPreference.off:
        return EffectsLevel.off;
      case EffectsPreference.auto:
        return deviceDefault;
    }
  }

  /// Current level for [context] (honours "reduce motion" from the OS).
  static EffectsLevel of(BuildContext context) =>
      resolve(preference.value, reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static bool blur(BuildContext context) => of(context) == EffectsLevel.full;
  static bool animate(BuildContext context) => of(context) != EffectsLevel.off;
}

extension EffectsPreferenceLabel on EffectsPreference {
  String get label {
    switch (this) {
      case EffectsPreference.auto:
        return 'อัตโนมัติ (ตามเครื่อง)';
      case EffectsPreference.full:
        return 'เต็ม — เบลอ/เอฟเฟกต์ครบ';
      case EffectsPreference.lite:
        return 'เบา — ลื่นบนเครื่องรุ่นเก่า';
      case EffectsPreference.off:
        return 'ปิด — เรียบ ไม่มีการเคลื่อนไหว';
    }
  }
}
