import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/change_password_screen.dart';

import 'support/profile_harness.dart';

Map<String, Object?> _replies({bool sms = true}) => {
      'GET /api/me/verify/methods': {
        'email': {'available': true, 'masked': 'q•@example.com'},
        'sms': sms ? {'available': true, 'masked': '081-•••-1111'} : {'available': false, 'reason': 'no_phone'},
        'password': {'available': true},
      },
      'POST /api/me/verify/request': {'channel': 'email', 'destination_masked': 'q•@example.com', 'expires_in': 600, 'resend_after': 60},
      'POST /api/me/verify/confirm': {'verify_token': 'vt-email', 'channel': 'email', 'expires_in': 600},
      'POST /api/me/verify/password': {'verify_token': 'vt-pw', 'channel': 'password', 'expires_in': 600},
      'PUT /api/me/password': {'has_login_password': true},
    };

Future<void> _newPassword(WidgetTester tester, {String a = 'NewPass@123', String? b}) async {
  await tester.enterText(find.byKey(const ValueKey('pw-new')), a);
  await tester.enterText(find.byKey(const ValueKey('pw-confirm')), b ?? a);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pw-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('email OTP: pick → code is sent → confirm → new password saved with the verify token', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const ChangePasswordScreen(), _replies());
    expect(find.text('q•@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pw-method-email')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/verify/request'), {'channel': 'email'}, reason: 'sent as soon as the method is picked');
    expect(find.text('ขอรหัสใหม่ได้ใน 60 วินาที'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pw-code')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pw-confirm')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/verify/confirm'), {'channel': 'email', 'code': '123456'});
    expect(find.byKey(const ValueKey('pw-verified-note')), findsOneWidget);
    // Strength hint + show / hide.
    await tester.enterText(find.byKey(const ValueKey('pw-new')), 'abc');
    await tester.pump();
    expect(find.text('ความแข็งแรง: สั้นเกินไป'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pw-new'))).obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('pw-show')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pw-new'))).obscureText, isFalse);
    await _newPassword(tester);
    expect(bodyOf(api, 'PUT', '/api/me/password'), {'new_password': 'NewPass@123', 'verify_token': 'vt-email'});
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('current password as the proof', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const ChangePasswordScreen(), _replies());
    await tester.tap(find.byKey(const ValueKey('pw-method-password')));
    await tester.pumpAndSettle();
    expect(api.callKeys, isNot(contains('POST /api/me/verify/request')));
    await tester.enterText(find.byKey(const ValueKey('pw-password')), 'Old@1234');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pw-confirm')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/verify/password'), {'password': 'Old@1234'});
    await _newPassword(tester);
    expect(bodyOf(api, 'PUT', '/api/me/password')['verify_token'], 'vt-pw');
  });

  testWidgets('a method the account lacks is shown with its reason and cannot be picked', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const ChangePasswordScreen(), _replies(sms: false));
    expect(find.text('ยังไม่มีเบอร์มือถือที่ยืนยันแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pw-method-sms')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pw-code')), findsNothing);
    expect(api.callKeys, isNot(contains('POST /api/me/verify/request')));
  });

  testWidgets('wrong code: message with attempts left, no password change, still signed in', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const ChangePasswordScreen(), _replies(), errors: {
      'POST /api/me/verify/confirm': {'error_code': 'VALIDATION', 'message': 'รหัสไม่ถูกต้อง', 'data': {'attempts_left': 2}},
    });
    await tester.tap(find.byKey(const ValueKey('pw-method-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pw-code')), '000000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pw-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('รหัสไม่ถูกต้อง · เหลือ 2 ครั้ง'), findsOneWidget);
    expect(api.callKeys, isNot(contains('PUT /api/me/password')));
    expect(config.isLoggedIn, isTrue);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('passwords must match; a refused save asks to verify again (tokens are single-use)', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const ChangePasswordScreen(), _replies(), status: {'PUT /api/me/password': 401}, errors: {
      'PUT /api/me/password': {
        'error_code': 'STEP_UP_REQUIRED',
        'message': 'กรุณายืนยันตัวตนก่อนเปลี่ยนรหัสผ่าน',
        'data': {'required': ['email', 'sms', 'password'], 'missing': ['email'], 'any_of': true},
      },
    });
    await tester.tap(find.byKey(const ValueKey('pw-method-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pw-password')), 'Old@1234');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pw-confirm')));
    await tester.pumpAndSettle();
    await _newPassword(tester, a: 'NewPass@123', b: 'NewPass@124');
    expect(find.text('รหัสไม่ตรงกัน'), findsOneWidget);
    expect(api.callKeys, isNot(contains('PUT /api/me/password')));
    await _newPassword(tester);
    expect(callCount(api, 'PUT /api/me/password'), 1);
    expect(find.text('กรุณายืนยันตัวตนก่อนเปลี่ยนรหัสผ่าน'), findsOneWidget);
    expect(find.byKey(const ValueKey('pw-method-email')), findsOneWidget, reason: 'back to step 1');
    expect(config.isLoggedIn, isTrue, reason: 'STEP_UP_REQUIRED never signs out');
  });

  test('password strength', () {
    expect(passwordStrength('abc').score, 0);
    expect(passwordStrength('abcdefgh').score, 1);
    expect(passwordStrength('Abcdefgh12!').score, 4);
  });
}
