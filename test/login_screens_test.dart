import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/screens/auth/login_screen.dart';
import 'package:nextx_mobile/screens/auth/welcome_screen.dart';
import 'package:nextx_mobile/screens/onboarding/role_setup_screen.dart';
import 'package:nextx_mobile/screens/onboarding/tab_setup_screen.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pump(WidgetTester tester, Widget screen, {SessionState? session, FakeNextxAdapter? adapter}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  if (session != null) config.debugOverrideSession(session);
  config.apiClient.debugSetHttpAdapter(adapter ?? FakeNextxAdapter({}));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('welcome shows slides and both actions', (tester) async {
    await _pump(tester, const WelcomeScreen());
    expect(find.text('เริ่มต้นใช้งาน'), findsOneWidget);
    expect(find.text('ฉันมีบัญชีอยู่แล้ว'), findsOneWidget);
    expect(find.textContaining('ทำงานได้ทุกที่'), findsOneWidget);
  });

  testWidgets('login shows LINE only when the server has it configured', (tester) async {
    await _pump(tester, const LoginScreen(), adapter: FakeNextxAdapter({
      'GET /api/auth/line/check': {'channel_id': '12345', 'redirect_uri': 'x'},
    }));
    expect(find.text('LINE'), findsOneWidget);
    expect(find.text('Google'), findsNothing); // not supported on the test host
    expect(find.text('รหัสผ่าน'), findsWidgets);
    expect(find.text('สมัครสมาชิก'), findsOneWidget);
  });

  testWidgets('login without LINE config hides the social row', (tester) async {
    await _pump(tester, const LoginScreen(), adapter: FakeNextxAdapter({
      'GET /api/auth/line/check': {'channel_id': null},
    }));
    expect(find.text('LINE'), findsNothing);
    expect(find.text('หรือเข้าสู่ระบบด้วย'), findsNothing);
  });

  testWidgets('login OTP mode asks to send a code first', (tester) async {
    await _pump(tester, const LoginScreen());
    await tester.tap(find.text('OTP อีเมล'));
    await tester.pump();
    expect(find.text('ส่งรหัส OTP'), findsOneWidget);
    expect(find.text('รหัส OTP 6 หลัก'), findsNothing);
  });

  testWidgets('role setup needs at least one role', (tester) async {
    await _pump(tester, const RoleSetupScreen(), session: const SessionState(accessToken: 't', userId: '1', businessId: '1'));
    expect(find.text('คุณทำงานด้านไหน?'), findsOneWidget);
    expect(find.text('เลือกอย่างน้อย 1 ข้อ'), findsOneWidget);
    await tester.tap(find.text('ทีมขาย'));
    await tester.pump();
    expect(find.text('ถัดไป'), findsOneWidget);
  });

  testWidgets('tab setup suggests tabs from roles within permissions and saves', (tester) async {
    final config = await _pump(
      tester,
      const TabSetupScreen(initial: ShellTabsConfig(roles: ['sales'])),
      session: const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'calendar']),
    );
    // quotation has no permission → not suggested.
    expect(find.text('ลีด/ดีล'), findsWidgets);
    expect(find.text('ใบเสนอ'), findsNothing);
    await tester.tap(find.text('เริ่มใช้งาน'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(config.roleSetupDone, isTrue);
    expect(config.shellConfig?.roles, ['sales']);
    expect(config.shellTabs, ['dashboard', 'leads', 'calendar']);
  });
}
