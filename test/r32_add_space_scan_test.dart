import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/qr_login.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/auth/qr_login_scan_screen.dart';
import 'package:nextx_mobile/screens/spaces/add_space_sheet.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:nextx_mobile/widgets/nx_logout.dart';

import 'support/fake_api.dart';

final _code = 'cd' * 32;
late FakeNextxAdapter mainAdapter;

Future<AppConfig> _signedIn(WidgetTester tester, Widget home, {Size size = const Size(430, 932)}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  // Let the stored-settings load finish first, or it replaces the session below.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 'old', userId: '9', businessId: '1', email: 'me@a.example.com', menusLoaded: true));
  mainAdapter = FakeNextxAdapter({
    'GET /api/health': {'status': 'ok'},
    'GET /api/me': {
      'user': {'id': 2, 'first_name': 'QA', 'last_name': 'Other', 'email1': 'qa.other@example.com'},
      'business': {'id': 5, 'business_name': '[QA] Other Biz'},
    },
  });
  config.apiClient.debugSetHttpAdapter(mainAdapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  await tester.pump(const Duration(milliseconds: 100));
  return config;
}

void main() {
  testWidgets('add พื้นที่ทำงาน window: switch to "สแกน QR" → scan button opens the scanner', (tester) async {
    await _signedIn(
      tester,
      Scaffold(body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showAddSpaceSheet(c), child: const Text('open'))))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-space-email')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-space-mode-qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-space-qr-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-space-email')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-space-scan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final scan = tester.widget<QrLoginScanScreen>(find.byType(QrLoginScanScreen));
    expect(scan.addSpace, isTrue);
    expect(find.text('สแกน QR เพิ่มพื้นที่ทำงาน'), findsOneWidget);
  });

  testWidgets('scan while signed in: redeemed on the QR server, a new Space opens, the old one stays', (tester) async {
    final link = QrLoginLink(server: 'https://other.example.com', code: _code);
    SharedPreferences.setMockInitialValues({});
    final config = await _signedIn(tester, const SizedBox());
    final before = config.spaces.length;
    final temp = FakeNextxAdapter({
      'POST /api/auth/qr/redeem': {
        'token': 'qr-session',
        'user': {'id': 2, 'first_name': 'QA', 'last_name': 'Other', 'email1': 'qa.other@example.com'},
        'business': {'id': 5, 'business_name': '[QA] Other Biz'},
      },
    });
    config.debugTempClientAdapter = temp;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: QrLoginScanScreen(initial: link, addSpace: true))));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    final call = temp.calls.singleWhere((c) => c.path == '/api/auth/qr/redeem');
    expect(call.uri.host, 'other.example.com');
    expect(config.apiBaseUrl, 'https://other.example.com');
    expect(config.session.email, 'qa.other@example.com');
    expect(config.spaces.length, greaterThan(before));
    expect(config.spaces.any((s) => s.baseUrl.contains('other.example.com')), isTrue);
    // The new Space opens its realtime connection; stop it so no retry timer is left.
    RealtimeService.instance.disconnect();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('logout dialog: both buttons one line and the same height, even narrow + large text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
        home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => confirmNxLogout(c, config), child: const Text('go')))),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final ok = tester.getSize(find.byKey(const ValueKey('nx-logout-confirm')));
    final stay = tester.getSize(find.byKey(const ValueKey('nx-logout-cancel')));
    expect(ok.height, stay.height);
    expect(ok.height, lessThan(60));
    final label = find.descendant(of: find.byKey(const ValueKey('nx-logout-confirm')), matching: find.text('ออกจากระบบ'));
    expect(tester.widget<Text>(label).maxLines, 1);
  });
}
