import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/auth_errors.dart';
import 'package:nextx_mobile/services/google_auth.dart';

void main() {
  test('Google config errors read as a clear message, not a stack', () {
    const e = GoogleAuthError('เข้าสู่ระบบด้วย Google ไม่ได้ เพราะแอปเวอร์ชันนี้ยังไม่ได้ลงทะเบียนกับ Google ของเซิร์ฟเวอร์');
    expect(authErrorMessage(e), contains('ยังไม่ได้ลงทะเบียน'));
  });

  test('launch logo ships per density (never stretched) + Android 12 splash icon', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/main/res/drawable-$d/splash_icon.png').existsSync(), isTrue, reason: d);
      expect(File('android/app/src/main/res/drawable-$d/splash_icon_v31.png').existsSync(), isTrue, reason: d);
    }
    expect(File('android/app/src/main/res/drawable/splash_icon.png').existsSync(), isFalse, reason: 'a density-less copy would be upscaled');
    expect(File('android/app/src/main/res/values-v31/styles.xml').readAsStringSync(), contains('windowSplashScreenAnimatedIcon'));
  });

  test('tester APKs use a fixed key when provided (stable SHA-1 for Google Sign-In), never committed', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    expect(gradle, contains('signingConfigs.tester'));
    expect(File('.github/workflows/flutter-ci.yml').readAsStringSync(), contains('ANDROID_TESTER_KEYSTORE_BASE64'));
    expect(File('android/.gitignore').readAsStringSync(), contains('tester.properties'));
  });
}
