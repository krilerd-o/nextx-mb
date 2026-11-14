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

/// Device facts [Effects.detect] looks at (0 / false = unknown).
@immutable
class DeviceSpecs {
  const DeviceSpecs({this.cores = 0, this.ramMb = 0, this.androidSdk = 0, this.lowRam = false});
  final int cores;
  final int ramMb;
  final int androidSdk;
  final bool lowRam;
}

class Effects {
  Effects._();

  static const _prefKey = 'nx_effects_pref';

  /// Default is "เบา" (lite) until the user picks something else.
  static final ValueNotifier<EffectsPreference> preference = ValueNotifier(EffectsPreference.lite);

  /// Set once at startup from the device (see [detect]).
  static EffectsLevel deviceDefault = EffectsLevel.full;

  /// [specs]: what main read from device_info_plus (null on web / tests → cores only).
  static Future<void> init({DeviceSpecs? specs}) async {
    deviceDefault = detect(
      web: kIsWeb,
      platform: defaultTargetPlatform,
      cores: specs?.cores ?? _cores(),
      ramMb: specs?.ramMb ?? 0,
      androidSdk: specs?.androidSdk ?? 0,
      lowRamFlag: specs?.lowRam ?? false,
    );
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

  /// Android phones under this much RAM get "lite" in auto mode.
  static const androidFullRamMb = 6 * 1024;

  /// iPhones / iPads under this much RAM (2 GB models: 6s, 7, SE 1) get "lite".
  static const iosFullRamMb = 3 * 1024;

  /// Android 12 (API 31) and newer; older releases also tend to be older, slower GPUs.
  static const androidFullSdk = 31;

  /// What "อัตโนมัติ" resolves to on this device. New installs still start on
  /// "เบา" ([preference] defaults to lite); this only matters once the user picks auto.
  ///
  /// Android → lite when any of: ≤ 4 CPU cores, < 6 GB RAM, Android < 12 (SDK 31) or the
  /// system's own low-RAM flag; iOS → lite under 3 GB RAM; web → lite. Unknown values
  /// (0) never count against the device.
  static EffectsLevel detect({
    required bool web,
    required TargetPlatform platform,
    int cores = 0,
    int ramMb = 0,
    int androidSdk = 0,
    bool lowRamFlag = false,
  }) {
    if (web) return EffectsLevel.lite;
    if (platform == TargetPlatform.android) {
      if (lowRamFlag) return EffectsLevel.lite;
      if (cores > 0 && cores <= 4) return EffectsLevel.lite;
      if (ramMb > 0 && ramMb < androidFullRamMb) return EffectsLevel.lite;
      if (androidSdk > 0 && androidSdk < androidFullSdk) return EffectsLevel.lite;
    } else if (platform == TargetPlatform.iOS) {
      if (ramMb > 0 && ramMb < iosFullRamMb) return EffectsLevel.lite;
    }
    return EffectsLevel.full;
  }

  static int _cores() {
    try {
      return _coreCounter?.call() ?? 0;
    } catch (_) {
      return 0;
    }
  }

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
