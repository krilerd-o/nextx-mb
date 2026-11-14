import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/auth_errors.dart';
import 'package:nextx_mobile/services/apple_auth.dart';
import 'package:nextx_mobile/services/google_auth.dart';

import 'support/fake_api.dart';

Future<(AppConfig, FakeNextxAdapter)> _config(Map<String, Object?> replies, {Map<String, int> status = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  final adapter = FakeNextxAdapter(replies, statusFor: status);
  config.apiClient.debugSetHttpAdapter(adapter);
  return (config, adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform buttons', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Apple only on iOS; Google on iOS only with an iOS client id', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AppleAuth.supported, isTrue);
      expect(GoogleAuth.supported, GoogleAuth.iosClientId.isNotEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AppleAuth.supported, isFalse);
      expect(GoogleAuth.supported, isTrue);
    });
  });

  group('Sign in with Apple → NEXTX', () {
    test('sends the identity token; an existing account asks to link first', () async {
      final (config, adapter) = await _config({
        'POST /api/auth/apple': {'needLinkConfirm': true, 'intentToken': 'intent-1', 'method': 'apple'},
      });
      await expectLater(
        config.loginWithAppleIdToken('apple-jwt'),
        throwsA(isA<LinkConfirmRequired>().having((e) => e.intentToken, 'intent', 'intent-1')),
      );
      final call = adapter.calls.singleWhere((c) => c.path == '/api/auth/apple');
      expect(Map<String, dynamic>.from(call.data as Map)['identity_token'], 'apple-jwt');
    });

    test('older server without the route → readable message', () async {
      final (config, _) = await _config({'POST /api/auth/apple': 'Cannot POST'}, status: {'POST /api/auth/apple': 404});
      await expectLater(
        config.loginWithAppleIdToken('apple-jwt'),
        throwsA(isA<AppleAuthError>().having((e) => authErrorMessage(e), 'msg', contains('ยังไม่รองรับ'))),
      );
    });

    test('token refused by the server → Apple message, not "wrong password"', () async {
      final (config, _) = await _config({}, status: {'POST /api/auth/apple': 401});
      await expectLater(config.loginWithAppleIdToken('bad'), throwsA(isA<AppleAuthError>()));
    });
  });

  group('iOS project files', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    test('privacy manifest and localized permission texts are in the app bundle', () {
      expect(File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync(), contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      expect(pbx, contains('PrivacyInfo.xcprivacy in Resources'));
      expect(pbx, contains('InfoPlist.strings in Resources'));
      for (final lang in ['en', 'th']) {
        final s = File('ios/Runner/$lang.lproj/InfoPlist.strings').readAsStringSync();
        for (final k in ['NSLocationWhenInUseUsageDescription', 'NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription', 'NSFaceIDUsageDescription']) {
          expect(s, contains('"$k"'), reason: '$lang $k');
        }
      }
    });

    test('Info.plist: Google ids from xcconfig (no secrets), LINE query schemes, iPad multitasking', () {
      expect(info, contains(r'<string>$(GOOGLE_IOS_CLIENT_ID)</string>'));
      expect(info, contains(r'<string>$(GOOGLE_REVERSED_CLIENT_ID)</string>'));
      expect(info, contains('<string>lineauth2</string>'));
      expect(info, contains('<key>UIRequiresFullScreen</key>\n\t<false/>'));
      expect(info, isNot(contains('.apps.googleusercontent.com')));
      expect(info, contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'));
      for (final f in ['Debug', 'Release']) {
        expect(File('ios/Flutter/$f.xcconfig').readAsStringSync(), contains('#include? "Secrets.xcconfig"'));
      }
    });

    test('Sign in with Apple entitlement', () {
      expect(File('ios/Runner/Runner.entitlements').readAsStringSync(), contains('com.apple.developer.applesignin'));
      expect(File('ios/Runner/RunnerRelease.entitlements').readAsStringSync(), contains('com.apple.developer.applesignin'));
    });

    test('push: GoogleService-Info.plist is bundled when CI wrote it; Release uses production APNs', () {
      // Copied by a build phase (the file is git-ignored; a missing file must not break the build).
      expect(pbx, contains('/* Bundle GoogleService-Info.plist */,'));
      expect(pbx, contains(r'SRC=\"${PROJECT_DIR}/Runner/GoogleService-Info.plist\"'));
      expect(pbx, contains(r'if [ -f \"$SRC\" ]'));
      expect(pbx, isNot(contains('GoogleService-Info.plist in Resources')));
      expect(File('.gitignore').readAsStringSync(), contains('ios/Runner/GoogleService-Info.plist'));
      // Runner target: Debug + Profile → development, Release → production.
      expect(RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;').allMatches(pbx).length, 2);
      expect(RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease\.entitlements;').allMatches(pbx).length, 1);
      final release = pbx.substring(pbx.indexOf('97C147071CF9000F007C117D /* Release */ = {'));
      expect(release.substring(0, release.indexOf('name = Release;')), contains('RunnerRelease.entitlements'));
      String aps(String f) => RegExp(r'<key>aps-environment</key>\s*<string>(\w+)</string>').firstMatch(File(f).readAsStringSync())!.group(1)!;
      expect(aps('ios/Runner/Runner.entitlements'), 'development');
      expect(aps('ios/Runner/RunnerRelease.entitlements'), 'production');
    });
  });
}
