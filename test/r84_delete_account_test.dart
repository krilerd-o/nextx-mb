import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/delete_account_screen.dart';

import 'support/fake_api.dart';
import 'support/profile_harness.dart';

Map<String, Object?> _replies({bool sms = true}) => {
      'GET /api/me/verify/methods': {
        'email': {'available': true, 'masked': 'q•@example.com'},
        'sms': sms ? {'available': true, 'masked': '081-•••-1111'} : {'available': false, 'reason': 'not_configured'},
        'password': {'available': true},
      },
      'POST /api/me/verify/request': {'channel': 'email', 'destination_masked': 'x', 'resend_after': 60},
      'POST /api/me/verify/confirm': {'verify_token': 'vt', 'channel': 'email'},
      'POST /api/me/delete-account': {'deactivated': true, 'status': 'Inactive', 'message': 'ปิดบัญชีแล้ว — ติดต่อผู้ดูแลระบบหากต้องการเปิดใช้งานอีกครั้ง'},
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

void main() {
  testWidgets('explains it is a closure (Inactive), data kept, admin can re-activate', (tester) async {
    await pumpProfilePage(tester, const DeleteAccountScreen(), _replies());
    for (final t in ['การลบบัญชีคือการปิดบัญชี', 'บัญชีเป็น "ไม่ใช้งาน" (Inactive)', 'ข้อมูลยังเก็บไว้ครบ', 'ผู้ดูแลระบบเปิดใช้งานคืนได้', 'ไม่ใช่การลบผู้ใช้ออกจากระบบ']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.byKey(const ValueKey('del-email-send')), findsNothing, reason: 'tick "I understand" first');
  });

  testWidgets('both email and SMS must be verified, then the typed word → deactivate, sign out, login message', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(), size: const Size(430, 2400));
    _perChannel(api);
    await tester.tap(find.byKey(const ValueKey('del-understand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('del-email-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('del-sms-send')), findsOneWidget);
    await _verify(tester, 'email');
    expect(find.byKey(const ValueKey('del-email-verified')), findsOneWidget);
    expect(_submit(tester).onPressed, isNull, reason: 'SMS not verified yet');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('del-type'))).enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('del-sms-send')));
    await tester.pumpAndSettle();
    expect(find.text('Ref: R001'), findsOneWidget, reason: 'SMS ref code next to the code field');
    await tester.enterText(find.byKey(const ValueKey('del-sms-code')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('del-sms-confirm')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'ลบบัญชี');
    await tester.pump();
    expect(_submit(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/delete-account'), {'confirm': 'DELETE', 'verify_tokens': ['vt-email', 'vt-sms']});
    expect(config.isLoggedIn, isFalse);
    expect(config.loginNotice, 'ปิดบัญชีแล้ว — ติดต่อผู้ดูแลระบบหากต้องการเปิดใช้งานอีกครั้ง');
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('only the available channels are asked for (SMS not configured → email only)', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(sms: false));
    _perChannel(api);
    await tester.tap(find.byKey(const ValueKey('del-understand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('del-sms-send')), findsNothing);
    expect(find.byKey(const ValueKey('del-sms-unavailable')), findsOneWidget);
    await _verify(tester, 'email');
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'POST', '/api/me/delete-account')['verify_tokens'], ['vt-email']);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('401 STEP_UP_REQUIRED: message on the page, proofs asked again, still signed in', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const DeleteAccountScreen(), _replies(sms: false), status: {'POST /api/me/delete-account': 401}, errors: {
      'POST /api/me/delete-account': {
        'error_code': 'STEP_UP_REQUIRED',
        'message': 'กรุณายืนยันตัวตนด้วย SMS ก่อนลบบัญชี',
        'data': {'required': ['email', 'sms'], 'missing': ['sms']},
      },
    });
    _perChannel(api);
    await tester.tap(find.byKey(const ValueKey('del-understand')));
    await tester.pumpAndSettle();
    await _verify(tester, 'email');
    await tester.enterText(find.byKey(const ValueKey('del-type')), 'ลบบัญชี');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('del-submit')));
    await tester.pumpAndSettle();
    expect(find.text('กรุณายืนยันตัวตนด้วย SMS ก่อนลบบัญชี'), findsOneWidget);
    expect(find.byKey(const ValueKey('del-email-verified')), findsNothing, reason: 'single-use tokens → verify again');
    expect(config.isLoggedIn, isTrue);
    expect(config.session.accessToken, 'main-token');
    await tester.pump(const Duration(seconds: 61));
  });
}
