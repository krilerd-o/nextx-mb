import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/profile/delete_account_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';

import 'support/fake_api.dart';

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget home, Map<String, dynamic> replies,
    {Map<String, int> status = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(_session);
  final adapter = FakeNextxAdapter(replies, statusFor: status);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  // Secure storage is mocked for logout; start-up loading may have read an
  // empty session from it (earlier test) → put the test session back.
  FlutterSecureStorage.setMockInitialValues({});
  config.debugOverrideSession(_session);
  await tester.pump();
  return (config, adapter);
}

const _session = SessionState(
  accessToken: 'main-token',
  userId: '7',
  businessId: '1',
  displayName: 'QA User',
  email: 'qa@example.com',
  menusLoaded: true,
  menuKeys: ['lead'],
);

const _otpReplies = <String, dynamic>{
  'GET /api/me/profile': {'profile': {'phone_mobile': '0811111111'}},
  'POST /api/auth/otp/email/request': {'message': 'sent'},
  'POST /api/auth/otp/email/verify': {'token': 'otp-token', 'user': {'id': 7}},
};

Future<void> _walk(WidgetTester tester, {String word = 'ลบบัญชี'}) async {
  await tester.tap(find.byKey(const ValueKey('del-understand')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('del-send')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('del-code')), '123456');
  await tester.enterText(find.byKey(const ValueKey('del-type')), word);
  await tester.pump();
}

void main() {
  testWidgets('"ลบบัญชี" lives in Settings → security; profile has theme + language instead', (tester) async {
    await _pump(tester, const ProfileHubScreen(), {'GET /api/me/profile': {'profile': {}}});
    expect(find.byKey(const ValueKey('profile-delete-account')), findsNothing);
    expect(find.byKey(const ValueKey('profile-theme')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-language')), findsOneWidget);
    await _pump(tester, const SettingsScreen(), const {});
    await tester.scrollUntilVisible(find.byKey(const ValueKey('settings-delete-account')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('settings-delete-account')), findsOneWidget);
  });

  testWidgets('explains first; the delete button needs OTP and the typed word', (tester) async {
    await _pump(tester, const DeleteAccountScreen(), _otpReplies);
    expect(find.text('สิ่งที่ถูกลบ'), findsOneWidget);
    expect(find.text('สิ่งที่ยังอยู่กับธุรกิจ'), findsOneWidget);
    expect(find.byKey(const ValueKey('del-send')), findsNothing, reason: 'tick "I understand" first');
    await _walk(tester, word: 'ลบ');
    final btn = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('del-submit')));
    expect(btn.onPressed, isNull, reason: 'wrong word → disabled');
  });

  testWidgets('OTP token deletes the account, then this device signs out and forgets it', (tester) async {
    final (config, adapter) = await _pump(tester, const DeleteAccountScreen(), {
      ..._otpReplies,
      'POST /api/me/delete-account': {'deleted': true},
      'POST /api/auth/logout': {},
      'DELETE /api/notifications/device-token': {},
    });
    await _walk(tester);
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    final call = adapter.calls.singleWhere((c) => c.path == '/api/me/delete-account');
    expect(call.headers['Authorization'], 'Bearer otp-token');
    expect(Map<String, dynamic>.from(call.data as Map), {'confirm': 'DELETE'});
    expect(config.isLoggedIn, isFalse);
  });

  testWidgets('older server without the endpoint → points to the web page', (tester) async {
    final (config, _) = await _pump(
      tester,
      const DeleteAccountScreen(),
      {..._otpReplies, 'POST /api/me/delete-account': 'Cannot POST /api/me/delete-account'},
      status: {'POST /api/me/delete-account': 404},
    );
    await _walk(tester);
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('del-web')), findsOneWidget);
    expect(config.isLoggedIn, isTrue, reason: 'nothing was deleted');
  });

  testWidgets('a refused OTP token does not sign the real session out', (tester) async {
    final (config, _) = await _pump(
      tester,
      const DeleteAccountScreen(),
      {..._otpReplies, 'POST /api/me/delete-account': {}},
      status: {'POST /api/me/delete-account': 401},
    );
    await _walk(tester);
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('del-error')), findsOneWidget);
    expect(config.isLoggedIn, isTrue);
  });
}
