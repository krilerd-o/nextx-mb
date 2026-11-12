import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/server_profile.dart';
import 'package:nextx_mobile/screens/auth/login_screen.dart';
import 'package:nextx_mobile/screens/auth/server_screen.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pumpServer(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
  final router = GoRouter(initialLocation: AppRoutes.server, routes: [
    GoRoute(path: AppRoutes.server, builder: (_, _) => const ServerScreen()),
    GoRoute(path: AppRoutes.login, builder: (_, _) => const Scaffold(body: Text('LOGIN-PAGE'))),
    GoRoute(path: AppRoutes.welcome, builder: (_, _) => const Scaffold(body: Text('WELCOME'))),
  ]);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp.router(routerConfig: router)));
  await tester.pump(const Duration(milliseconds: 100));
  return config;
}

void main() {
  late List<String> checked;
  setUp(() {
    checked = [];
    ServerScreen.scannerOverride = (onCode) => Column(children: [
          TextButton(key: const ValueKey('fake-scan-ok'), onPressed: () => onCode('moainext.moai-crm.com'), child: const Text('ok')),
          TextButton(key: const ValueKey('fake-scan-bad'), onPressed: () => onCode('https://example.com/menu'), child: const Text('bad')),
        ]);
    ServerScreen.verifyOverride = (input) async {
      checked.add(input);
      return input.contains('moai-crm.com')
          ? const ServerCheckResult(url: 'https://moainext.moai-crm.com', ok: true)
          : const ServerCheckResult(url: '', ok: false, message: 'เซิร์ฟเวอร์นี้ไม่ใช่ระบบ MOAI NEXT');
    };
  });
  tearDown(() {
    ServerScreen.scannerOverride = null;
    ServerScreen.verifyOverride = null;
  });

  testWidgets('no default-server card; two tabs: type in | scan', (tester) async {
    await _pumpServer(tester);
    expect(find.text('MOAI NEXT (ค่าเริ่มต้น)'), findsNothing);
    expect(find.text('กรอกด้วยตนเอง'), findsOneWidget);
    expect(find.text('สแกน'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-url')), findsOneWidget);
  });

  testWidgets('scan: the QR text goes into the box and a real server continues to sign in', (tester) async {
    await _pumpServer(tester);
    await tester.tap(find.text('สแกน'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-ok')));
    await tester.pumpAndSettle();
    expect(checked, ['moainext.moai-crm.com']);
    expect(find.text('LOGIN-PAGE'), findsOneWidget);
  });

  testWidgets('scan: not a MOAI NEXT server → dialog, and the box can be cleared', (tester) async {
    await _pumpServer(tester);
    await tester.tap(find.text('สแกน'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-bad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-scan-invalid')), findsOneWidget);
    expect(find.text('QR นี้ไม่ใช่ระบบ MOAI NEXT'), findsOneWidget);
    // The scanned text is shown in the dialog (and was put into the box).
    expect(find.descendant(of: find.byKey(const ValueKey('server-scan-invalid')), matching: find.text('https://example.com/menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('server-scan-clear')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('server-url')), 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('server-url'))).controller!.text, isEmpty);
    expect(find.text('LOGIN-PAGE'), findsNothing);
  });

  testWidgets('login scan tab: "วิธีสแกน" shows the animation with the three steps', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = AppConfig();
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: LoginScreen())));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('สแกน').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('บนเว็บ: ตั้งค่า'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('qr-howto')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('qr-howto-gif')), findsOneWidget);
    expect(find.textContaining('รูปโปรไฟล์ มุมซ้ายล่าง'), findsOneWidget);
    expect(find.textContaining('คิวอาร์โค้ดเข้าสู่ระบบ'), findsOneWidget);
  });
}
