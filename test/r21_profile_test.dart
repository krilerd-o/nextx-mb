import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/profile/change_password_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';

import 'support/fake_api.dart';

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget home, Map<String, dynamic> replies) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(
    accessToken: 'main-token',
    userId: '7',
    businessId: '1',
    businessName: 'QA Co',
    displayName: 'QA User',
    email: 'qa@example.com',
    menusLoaded: true,
    menuKeys: ['lead'],
  ));
  final adapter = FakeNextxAdapter(replies);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return (config, adapter);
}

void main() {
  testWidgets('profile page: me, my Spaces, the area menu, and a way into settings', (tester) async {
    await _pump(tester, const ProfileHubScreen(), {
      'GET /api/me/profile': {'profile': {'phone_mobile': '0811111111', 'title': 'Sales'}},
    });
    expect(find.text('โปรไฟล์'), findsWidgets);
    expect(find.text('QA User'), findsOneWidget);
    expect(find.text('ข้อมูลของฉัน'), findsNothing, reason: 'email / mobile rows moved to จัดการโปรไฟล์');
    for (final t in ['พื้นที่ทำงานของฉัน', 'บริษัท', 'แพ็กเกจที่ใช้ปัจจุบัน', 'สลับแพ็กเกจ', 'เพิ่มพื้นที่ทำงาน', 'จัดการความปลอดภัย', 'จัดการโปรไฟล์', 'สลับพื้นที่ทำงาน']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('แก้ไขโปรไฟล์'), findsNothing, reason: 'removed from the hub; it lives in จัดการโปรไฟล์');
    expect(find.textContaining('Space'), findsNothing, reason: 'Thai UI says พื้นที่ทำงาน');
    expect(find.textContaining('Package'), findsNothing, reason: 'Thai UI says แพ็กเกจ');
    // พื้นที่ทำงานของฉัน: company, current package, switch package, add — in that order.
    final ys = [for (final k in ['company', 'package', 'switch-package', 'add']) tester.getTopLeft(find.byKey(ValueKey('profile-ws-$k'))).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }
    expect(find.byKey(const ValueKey('profile-menu-settings')), findsOneWidget);
    expect(find.byTooltip('การตั้งค่า'), findsOneWidget);
    // Theme / colour controls live on จัดการธีม, not here.
    expect(find.text('สีธีม'), findsNothing);
  });

  group('change password by OTP', () {
    Future<FakeNextxAdapter> run(WidgetTester tester, {String uid = '7', bool link = false}) async {
      final (_, adapter) = await _pump(tester, const ChangePasswordScreen(), {
        'GET /api/me/profile': {'profile': {'phone_mobile': '0811111111'}},
        'POST /api/auth/otp/email/request': {'message': 'sent'},
        'POST /api/auth/otp/email/verify': link
            ? {'needLinkConfirm': true, 'intentToken': 'intent-1', 'method': 'email_otp'}
            : {'token': 'otp-token', 'user': {'id': uid}},
        'POST /api/auth/link/confirm': {'token': 'otp-token', 'user': {'id': uid}},
        'PUT /api/me/password': {'has_login_password': true},
        'POST /api/auth/logout': {},
      });
      expect(find.text('q•@example.com'), findsOneWidget, reason: 'masked email');
      expect(find.text('081-•••-1111'), findsOneWidget, reason: 'masked phone (SMS option)');
      await tester.tap(find.byKey(const ValueKey('pw-send')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const ValueKey('pw-code')), '123456');
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'NewPass@1');
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'NewPass@1');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      return adapter;
    }

    testWidgets('no old password: OTP proves it is me, then the new password is set', (tester) async {
      final adapter = await run(tester);
      final put = adapter.calls.singleWhere((c) => c.method == 'PUT' && c.path == '/api/me/password');
      expect(put.headers['Authorization'], 'Bearer otp-token');
      final body = Map<String, dynamic>.from(put.data as Map);
      expect(body, {'new_password': 'NewPass@1'});
      // The extra session from the OTP check is signed out again.
      final out = adapter.calls.singleWhere((c) => c.path == '/api/auth/logout');
      expect(out.headers['Authorization'], 'Bearer otp-token');
      // Other calls still use the signed-in session.
      expect(adapter.calls.firstWhere((c) => c.path == '/api/me/profile').headers['Authorization'], 'Bearer main-token');
    });

    testWidgets('first OTP use links the method, then changes the password', (tester) async {
      final adapter = await run(tester, link: true);
      expect(adapter.calls.where((c) => c.path == '/api/auth/link/confirm'), hasLength(1));
      final put = adapter.calls.singleWhere((c) => c.path == '/api/me/password');
      expect(put.headers['Authorization'], 'Bearer otp-token');
    });

    testWidgets('a code that belongs to another account is refused', (tester) async {
      final adapter = await run(tester, uid: '99');
      expect(adapter.calls.where((c) => c.path == '/api/me/password'), isEmpty);
      expect(find.byKey(const ValueKey('pw-error')), findsOneWidget);
      expect(find.text('รหัสนี้เป็นของบัญชีอื่น'), findsOneWidget);
    });

    testWidgets('new password must match and be long enough', (tester) async {
      await _pump(tester, const ChangePasswordScreen(), {'POST /api/auth/otp/email/request': {}});
      await tester.tap(find.byKey(const ValueKey('pw-send')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const ValueKey('pw-code')), '123456');
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'abcdef');
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'abcdeg');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pump();
      expect(find.text('รหัสไม่ตรงกัน'), findsOneWidget);
    });
  });

  group('theme colours = web palette', () {
    test('23 colours with the web keys, standard then pastel', () {
      expect(AppConfig.accentKeys.length, 23);
      expect(AppConfig.accentOptions.length, 23);
      expect(AppConfig.accentNames.length, 23);
      expect(AppConfig.accentKeys[1], 'blue');
      expect(AppConfig.accentOptions[1], const Color(0xFF0253CD));
      expect(AppConfig.accentKeys[AppConfig.accentPastelStart], 'pastel_rose');
    });

    test('a colour picked in the old 9-colour palette is kept', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({'flutter.accent_index': 4}); // old "กุหลาบ"
      FlutterSecureStorage.setMockInitialValues({});
      final config = AppConfig();
      for (var i = 0; i < 200 && !config.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(AppConfig.accentKeys[config.accentIndex], 'rose');
      await config.setAccentIndex(AppConfig.accentKeys.indexOf('pastel_mint'));
      final p = await SharedPreferences.getInstance();
      expect(p.getString('accent_key'), 'pastel_mint');
    });
  });

  test('a server the user confirmed is kept even if it looks like a local dev URL', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'flutter.api_base_url': 'http://127.0.0.1:4000', 'flutter.server_confirmed': true});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    for (var i = 0; i < 200 && !config.isReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(config.apiBaseUrl, 'http://127.0.0.1:4000', reason: 'a Space on this server must not jump to the default server');
  });

  test('effects default to "เบา"', () {
    expect(Effects.preference.value, EffectsPreference.lite);
  });
}
