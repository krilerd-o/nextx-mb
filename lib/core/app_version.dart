import 'package:package_info_plus/package_info_plus.dart';

/// App version from the installed package (pubspec `version:`), loaded once at start.
class AppVersion {
  AppVersion._();

  static const _override = String.fromEnvironment('APP_VERSION');
  static String _value = _override.isNotEmpty ? _override : '0.5.0+5';

  static String get value => _value;

  static Future<void> load() async {
    if (_override.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _value = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Tests / unsupported platforms keep the pubspec fallback.
    }
  }
}
