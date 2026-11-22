import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/delete_account_screen.dart';

import 'support/fake_api.dart';
import 'support/profile_harness.dart';

Map<String, Object?> _replies({bool sms = true, List<Map<String, Object?>> soleOwner = const []}) => {
      'GET /api/me/verify/methods': {
        'email': {'available': true, 'masked': 'q•@example.com'},
        'sms': sms ? {'available': true, 'masked': '081-•••-1111'} : {'available': false, 'reason': 'not_configured'},
        'password': {'available': true},
      },
      'GET /api/me/delete-account/preview': {
        'businesses': [
          {'business_id': 1, 'name': 'ร้านทดสอบ', 'role': 'member'},
          {'business_id': 2, 'name': 'บริษัทสอง', 'role': soleOwner.isEmpty ? 'admin' : 'owner'},
        ],
        'sole_owner': soleOwner,
        'devices': 2,
        'linked_sign_ins': ['google', 'apple'],
        'can_delete': soleOwner.isEmpty,
      },
      'POST /api/me/verify/request': {'channel': 'email', 'destination_masked': 'x', 'resend_after': 60},
      'POST /api/me/verify/confirm': {'verify_token': 'vt', 'channel': 'email'},
      'POST /api/me/delete-account': {'erased': true, 'businesses': 2},
      'POST /api/auth/logout': {},
      'DELETE /api/notifications/device-token': {},
    };

/// Each channel answers with its own token / ref code.
void _perChannel(FakeNextxAdapter api) {
  api.onRequest = (RequestOptions o) {
    final ch = o.data is Map ? '${(o.data as Map)['channel']}' : '';
    if (o.path == '/api/me/verify/confirm') api.replies['POST /api/me/verify/confirm'] = {'verify_token': 'vt-$ch', 'channel': ch};
    if (o.path == '/api/me/verify/request') {
      api.replies['POST /api/me/verify/request'] = {'channel': ch, 'destination_masked': ch == 'sms' ? '081-•••-1111' : 'q•@example.com', 'resend_after': 60, if (ch == 'sms') 'ref_code': 'R001'};
    }
  };
}

Future<void> _verify(WidgetTester tester, String ch) async {
  await tester.tap(find.byKey(ValueKey('del-$ch-send')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ValueKey('del-$ch-code')), '123456');
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('del-$ch-confirm')));
  await tester.pumpAndSettle();
}

ButtonStyleButton _submit(WidgetTester tester) => tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('del-submit')));

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('del-accept')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first says what is deleted for good and what stays with the business', (tester) async {
    await pumpProfilePage(tester, const DeleteAccountScreen(), _replies());
    for (final t in ['ลบบัญชีถาวร — กู้คืนไม่ได้', 'ข้อมูลส่วนตัวถูกลบทั้งหมด', 'เข้าสู่ระบบไม่ได้อีก', 'ออกจากทุกธุรกิจ', 'ข้อมูลงานยังอยู่กับธุรกิจ']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('Google, Apple'), findsOneWidget, reason: 'linked sign-ins are named');
    expect(find.textContaining('ร้านทดสอบ, บริษัทสอง'), findsOneWidget, reason: 'the businesses it leaves');
    expect(find.byKey(const ValueKey('del-type')), findsNothing, reason: 'accept first');
    expect(find.byKey(const ValueKey('del-email-send')), findsNothing);
  });

  testWidgets('the only owner of a business must transfer it first: listed, and no way on', (tester) async {
    await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(soleOwner: [{'business_id': 2, 'name': 'บริษัทสอง'}]));
    expect(find.byKey(const ValueKey('del-sole-owner')), findsOneWidget);
    expect(find.byKey(const ValueKey('del-sole-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('del-accept')), findsNothing);
    expect(find.byKey(const ValueKey('del-submit')), findsNothing);
  });

  testWidgets('accept → type the word → SMS and email OTP → erase → signed out on the welcome screen', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(), size: const Size(430, 2600), routes: {
      '/welcome': () => const Scaffold(body: Text('WELCOME')),
    });
    _perChannel(api);
    await _accept(tester);
    expect(find.byKey(const ValueKey('del-type')), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'ลบบัญชี');
    await tester.pump();
    expect(_submit(tester).onPressed, isNull, reason: 'the word is ลบบัญชีถาวร');
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'ลบบัญชีถาวร');
    await tester.pumpAndSettle();
    await _verify(tester, 'email');
    expect(_submit(tester).onPressed, isNull, reason: 'SMS not verified yet');
    await tester.tap(find.byKey(const ValueKey('del-sms-send')));
    await tester.pumpAndSettle();
    expect(find.text('Ref: R001'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('del-sms-code')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('del-sms-confirm')));
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/delete-account'), {'confirm': 'DELETE', 'mode': 'erase', 'verify_tokens': ['vt-email', 'vt-sms']});
    expect(config.isLoggedIn, isFalse);
    expect(config.loginNotice, kAccountDeletedNotice);
    expect(find.text('WELCOME'), findsOneWidget, reason: 'starts over on the first screen');
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('only the available channels are asked for (SMS not configured → email only)', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(sms: false));
    _perChannel(api);
    await _accept(tester);
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'DELETE');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('del-sms-send')), findsNothing);
    expect(find.byKey(const ValueKey('del-sms-unavailable')), findsOneWidget);
    await _verify(tester, 'email');
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/delete-account')['verify_tokens'], ['vt-email']);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('401 STEP_UP_REQUIRED: message on the page, proofs asked again, still signed in', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(sms: false), status: {'POST /api/me/delete-account': 401}, errors: {
      'POST /api/me/delete-account': {
        'error_code': 'STEP_UP_REQUIRED',
        'message': 'รหัสยืนยันนี้ถูกใช้ไปแล้ว — ยืนยันตัวตนอีกครั้ง',
        'data': {'required': ['email'], 'missing': ['email']},
      },
    });
    _perChannel(api);
    await _accept(tester);
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'ลบบัญชีถาวร');
    await tester.pumpAndSettle();
    await _verify(tester, 'email');
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(find.text('รหัสยืนยันนี้ถูกใช้ไปแล้ว — ยืนยันตัวตนอีกครั้ง'), findsOneWidget);
    expect(find.byKey(const ValueKey('del-email-verified')), findsNothing, reason: 'single-use tokens → verify again');
    expect(config.isLoggedIn, isTrue);
    expect(config.session.accessToken, 'main-token');
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('a server that cannot delete permanently (no preview) offers the web page instead', (tester) async {
    final r = _replies()..['GET /api/me/delete-account/preview'] = 'Cannot GET /api/me/delete-account/preview';
    final (config, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), r, status: {'GET /api/me/delete-account/preview': 404});
    expect(find.byKey(const ValueKey('del-no-erase')), findsOneWidget);
    expect(find.byKey(const ValueKey('del-web')), findsOneWidget);
    expect(find.byKey(const ValueKey('del-accept')), findsNothing);
    expect(api.callKeys.where((k) => k.startsWith('POST /api/me/delete-account')), isEmpty);
    expect(config.isLoggedIn, isTrue);
  });
}
