import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/auth_redirect.dart';
import 'package:nextx_mobile/core/qr_login.dart';
import 'package:nextx_mobile/screens/auth/login_screen.dart';
import 'package:nextx_mobile/screens/auth/qr_login_scan_screen.dart';

import 'support/fake_api.dart';

final _code = 'ab' * 32;

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget screen, {Map<String, Object?> replies = const {}, Map<String, int> status = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  final adapter = FakeNextxAdapter(replies, statusFor: status);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return (config, adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QR link', () {
    test('accepts only a MOAI NEXT login QR with an http(s) server and a 64-hex code', () {
      final ok = QrLoginLink.parse('moainext://app/qr-login?s=${Uri.encodeComponent('https://crm.example.com/')}&c=$_code');
      expect(ok?.server, 'https://crm.example.com');
      expect(ok?.code, _code);
      expect(QrLoginLink.parse('https://example.com/?c=$_code'), isNull);
      expect(QrLoginLink.parse('moainext://app/qr-login?s=ftp://x&c=$_code'), isNull);
      expect(QrLoginLink.parse('moainext://app/qr-login?s=https://x.com&c=123'), isNull);
      expect(QrLoginLink.parse('moainext://app/invite?s=https://x.com&c=$_code'), isNull);
      expect(QrLoginLink.parse(null), isNull);
    });

    test('Google browser sign-in can come back with a merge intent', () {
      final r = parseAuthRedirect('moainext://app/login?merge_intent=mi-1');
      expect(r?.mergeIntent, 'mi-1');
    });
  });

  testWidgets('login has 4 modes; สแกน shows the QR panel instead of the fields', (tester) async {
    await _pump(tester, const LoginScreen());
    for (final l in ['รหัสผ่าน', 'อีเมล', 'SMS', 'สแกน']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await tester.tap(find.text('สแกน'));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-id')), findsNothing);
    expect(find.text('สแกน QR จากเว็บ'), findsOneWidget);
    expect(find.text('ลืมรหัสผ่าน?'), findsNothing);
  });

  testWidgets('QR from the camera app: redeem → success animation → signed in', (tester) async {
    final link = QrLoginLink(server: 'https://qa.example.com', code: _code);
    final (config, adapter) = await _pump(tester, QrLoginScanScreen(initial: link), replies: {
      'POST /api/auth/qr/redeem': {
        'token': 'qr-session',
        'user': {'id': 2, 'first_name': 'QA', 'last_name': 'Second', 'email1': 'qa.second@example.com'},
        'business': {'id': 1, 'business_name': '[QA] Biz'},
      },
    });
    final call = adapter.calls.singleWhere((c) => c.path == '/api/auth/qr/redeem');
    expect(Map<String, dynamic>.from(call.data as Map)['code'], _code);
    expect(find.byKey(const ValueKey('qr-success')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('เข้าสู่ระบบสำเร็จ'), findsOneWidget);
    expect(find.text('QA Second'), findsOneWidget);
    expect(find.text('[QA] Biz'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(config.isLoggedIn, isTrue);
    expect(config.apiBaseUrl, 'https://qa.example.com');
  });

  testWidgets('used or expired QR → clear message and a rescan button', (tester) async {
    final link = QrLoginLink(server: 'https://qa.example.com', code: _code);
    final (config, _) = await _pump(tester, QrLoginScanScreen(initial: link), status: {'POST /api/auth/qr/redeem': 401});
    expect(find.byKey(const ValueKey('qr-error')), findsOneWidget);
    expect(find.textContaining('QR หมดอายุหรือถูกใช้แล้ว'), findsOneWidget);
    expect(find.text('สแกนอีกครั้ง'), findsOneWidget);
    expect(config.isLoggedIn, isFalse);
  });
}
