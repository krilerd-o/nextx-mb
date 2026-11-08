import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(
    accessToken: 't',
    userId: '7',
    businessId: '1',
    businessName: 'QA Co',
    displayName: 'QA User',
    email: 'qa@example.com',
    menusLoaded: true,
    menuKeys: ['lead', 'calendar'],
  ));
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: SettingsScreen())));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return config;
}

void main() {
  testWidgets('settings page: grouped settings, filtered by search (profile lives on its own page)', (tester) async {
    await _pump(tester);
    expect(find.text('การตั้งค่า'), findsWidgets);
    expect(find.text('QA User'), findsNothing);
    for (final g in ['รูปลักษณ์', 'เมนูและการใช้งาน', 'บัญชีและความปลอดภัย']) {
      expect(find.text(g), findsOneWidget);
    }
    expect(find.text('สีธีม'), findsOneWidget);
    expect(find.text('แถบเมนูล่าง'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'รหัสผ่าน');
    await tester.pumpAndSettle();
    expect(find.text('เปลี่ยนรหัสผ่าน'), findsOneWidget);
    expect(find.text('สีธีม'), findsNothing);
  });

  testWidgets('theme mode and colour pickers update AppConfig', (tester) async {
    final config = await _pump(tester);
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(config.themeMode, ThemeMode.dark);

    await tester.tap(find.bySemanticsLabel('กุหลาบ'));
    await tester.pumpAndSettle();
    expect(AppConfig.accentKeys[config.accentIndex], 'rose');
  });
}
