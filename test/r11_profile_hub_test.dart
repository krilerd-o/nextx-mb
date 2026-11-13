import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/profile/theme_settings_screen.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pump(WidgetTester tester, {Widget home = const SettingsScreen()}) async {
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
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return config;
}

void main() {
  testWidgets('settings page: what is left, grouped, filtered by search (profile lives on its own page)', (tester) async {
    await _pump(tester);
    expect(find.text('การตั้งค่า'), findsWidgets);
    expect(find.text('QA User'), findsNothing);
    for (final g in ['การใช้งาน', 'ข้อมูลและพื้นที่จัดเก็บ', 'เกี่ยวกับแอป', 'ช่วยเหลือและวินิจฉัย']) {
      expect(find.text(g.toUpperCase()), findsOneWidget, reason: g);
    }
    expect(find.text('เสียงชัตเตอร์'), findsOneWidget);
    expect(find.text('สีธีม'), findsNothing, reason: 'moved to จัดการธีม');

    await tester.enterText(find.byType(TextField), 'บันทึกปัญหา');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-diagnostics')), findsOneWidget);
    expect(find.text('เสียงชัตเตอร์'), findsNothing);
  });

  testWidgets('theme page: theme, language and colour all update AppConfig', (tester) async {
    final config = await _pump(tester, home: const ThemeSettingsScreen());
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(config.themeMode, ThemeMode.dark);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(config.uiLocaleCode, 'en');
    await tester.tap(find.text('ไทย'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('กุหลาบ'));
    await tester.pumpAndSettle();
    expect(AppConfig.accentKeys[config.accentIndex], 'rose');
  });
}
