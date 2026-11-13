import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/screens/profile/security_settings_screen.dart';
import 'package:nextx_mobile/screens/profile/theme_settings_screen.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';

import 'support/profile_harness.dart';

/// Every setting has exactly one home: key → the page that owns it.
const _homes = <String, String>{
  'theme-mode': 'theme',
  'theme-accent': 'theme',
  'theme-language': 'theme',
  'theme-date-format': 'theme',
  'theme-font': 'theme',
  'theme-ui-scale': 'theme',
  'theme-nav-dock': 'theme',
  'theme-effects': 'theme',
  'dev-tab-editor': 'devices',
  'dev-role-editor': 'devices',
  'dev-home-editor': 'devices',
  'settings-app-lock': 'security',
  'sec-change-password': 'security',
  'sec-advanced': 'security',
  'np-center': 'notifications',
  'settings-bday-remind': 'notifications',
  'settings-shutter': 'settings',
  'settings-diagnostics': 'settings',
  'settings-version': 'settings',
  'settings-offline-queue': 'settings',
};

final _pages = <String, Widget Function()>{
  'theme': () => const ThemeSettingsScreen(),
  'devices': () => const DevicesScreen(),
  'security': () => const SecuritySettingsScreen(),
  'notifications': () => NotificationPrefsScreen(permission: () async => true),
  'settings': () => const SettingsScreen(),
};

void main() {
  for (final page in _pages.entries) {
    testWidgets('"${page.key}" holds its settings and none of the others', (tester) async {
      await pumpProfilePage(tester, page.value(), {
        'GET /api/me/sessions': {'list': [], 'current_sid': 's1'},
        'GET /api/me/notification-preferences': {'channels': [], 'groups': []},
      }, size: const Size(430, 3200));
      for (final e in _homes.entries) {
        expect(find.byKey(ValueKey(e.key)), e.value == page.key ? findsOneWidget : findsNothing, reason: '${e.key} on ${page.key}');
      }
    });
  }

  testWidgets('old settings rows are gone from การตั้งค่า (theme, devices, security, signature, delete)', (tester) async {
    await pumpProfilePage(tester, const SettingsScreen(), const {}, size: const Size(430, 3200));
    for (final t in ['สีธีม', 'ฟอนต์', 'ขนาดหน้าจอ', 'ตำแหน่งเมนู (แท็บเล็ต)', 'แถบเมนูล่าง', 'บทบาทของฉัน', 'ปรับแต่งหน้าหลัก', 'ลายเซ็นของฉัน', 'เปลี่ยนรหัสผ่าน', 'ลบบัญชี', 'อุปกรณ์ที่เข้าใช้งาน', 'ศูนย์การแจ้งเตือน', 'มีอะไรใหม่']) {
      expect(find.text(t), findsNothing, reason: t);
    }
  });

  testWidgets('searching for a moved setting offers its page', (tester) async {
    await pumpProfilePage(tester, const SettingsScreen(), const {});
    await tester.enterText(find.byKey(const ValueKey('settings-search')), 'ฟอนต์');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-jump-theme')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-jump-security')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-jump-theme')));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeSettingsScreen), findsOneWidget);
  });

  testWidgets('theme page: effects and date format apply live', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const ThemeSettingsScreen(), const {}, size: const Size(430, 2600));
    final before = Effects.preference.value;
    addTearDown(() => Effects.preference.value = before);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('theme-effects')), matching: find.text('ปิด')));
    await tester.pumpAndSettle();
    expect(Effects.preference.value, EffectsPreference.off);
    await tester.tap(find.byKey(const ValueKey('date-format-yyyy-MM-dd HH:mm')));
    await tester.pumpAndSettle();
    expect(config.dateFormatPattern, 'yyyy-MM-dd HH:mm');
    await tester.tap(find.byKey(const ValueKey('theme-font-ibm_plex_sans_thai')));
    await tester.pumpAndSettle();
    expect(config.uiFontId, 'ibm_plex_sans_thai');
  });

  test('date pattern preview', () {
    final d = DateTime(2026, 11, 13, 14, 5);
    expect(formatDatePattern('dd/MM/yyyy HH:mm', d), '13/11/2569 14:05');
    expect(formatDatePattern('MM/dd/yyyy h:mm a', d), '11/13/2569 2:05 PM');
  });
}
