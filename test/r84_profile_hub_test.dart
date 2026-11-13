import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/my_signatures_screen.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_manage_screen.dart';
import 'package:nextx_mobile/screens/profile/security_settings_screen.dart';
import 'package:nextx_mobile/screens/profile/theme_settings_screen.dart';
import 'package:nextx_mobile/screens/profile_edit_screen.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';
import 'package:nextx_mobile/screens/whats_new/whats_new_screen.dart';

import 'support/profile_harness.dart';

const _replies = <String, Object?>{
  'GET /api/me/profile': {'profile': {'first_name': 'QA', 'phone_mobile': '0811111111'}},
  'GET /api/me/sessions': {'list': [], 'current_sid': 's1'},
  'GET /api/whats-new': [],
  'GET /api/me/signatures': {},
  'GET /api/me/notification-preferences': {'channels': [], 'push_paused': false, 'groups': []},
};

final _routes = <String, Widget Function()>{
  '/devices': () => const DevicesScreen(),
  '/whats-new': () => const WhatsNewScreen(),
  '/settings': () => const SettingsScreen(),
};

void main() {
  testWidgets('first card: avatar + camera, name, email, chips, TH | EN; จัดการโปรไฟล์ in its own section', (tester) async {
    await pumpProfilePage(tester, const ProfileHubScreen(), _replies);
    final hero = find.byKey(const ValueKey('profile-hero'));
    for (final f in [
      find.byKey(const ValueKey('profile-photo')),
      find.text('QA User'),
      find.text('qa@example.com'),
      find.text('MEMBER'),
      find.text('QA Co'),
      find.byKey(const ValueKey('profile-lang-toggle')),
    ]) {
      expect(find.descendant(of: hero, matching: f), findsOneWidget);
    }
    expect(find.descendant(of: hero, matching: find.byKey(const ValueKey('profile-edit'))), findsNothing, reason: 'no แก้ไขโปรไฟล์ on the hub');
    expect(find.text('ข้อมูลของฉัน'), findsNothing);
    expect(find.descendant(of: hero, matching: find.byKey(const ValueKey('profile-manage'))), findsNothing, reason: 'จัดการโปรไฟล์ moved to its own section');
    // โปรไฟล์ section (จัดการโปรไฟล์) comes before บัญชีและการตั้งค่า.
    expect(tester.getTopLeft(find.byKey(const ValueKey('profile-manage'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('profile-menu-theme'))).dy));
    expect(tester.getTopLeft(find.text('โปรไฟล์').last).dy, lessThan(tester.getTopLeft(find.text('บัญชีและการตั้งค่า')).dy));
    expect(find.text('พื้นที่ทำงานของฉัน'), findsOneWidget);
  });

  testWidgets('menu order: theme, devices, signatures, security, notifications, what\'s new, settings; no edit button (it lives in จัดการโปรไฟล์)', (tester) async {
    await pumpProfilePage(tester, const ProfileHubScreen(), _replies, size: const Size(430, 2600));
    final ys = [for (final id in kProfileMenuOrder) tester.getTopLeft(find.byKey(ValueKey('profile-menu-$id'))).dy];
    expect(kProfileMenuOrder, ['theme', 'devices', 'signatures', 'security', 'notifications', 'whats-new', 'settings']);
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: kProfileMenuOrder[i]);
    }
    final labels = ['จัดการธีม', 'จัดการอุปกรณ์', 'จัดการลายเซ็น', 'จัดการความปลอดภัย', 'จัดการการแจ้งเตือน', 'มีอะไรใหม่', 'การตั้งค่า'];
    for (var i = 0; i < labels.length; i++) {
      expect(find.descendant(of: find.byKey(ValueKey('profile-menu-${kProfileMenuOrder[i]}')), matching: find.text(labels[i])), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('profile-edit')), findsNothing, reason: 'removed at the owner\'s request');
    expect(tester.getTopLeft(find.byKey(const ValueKey('nx-logout-button'))).dy, greaterThan(ys.last), reason: 'logout is last');
    // No theme / language controls on the profile any more.
    expect(find.byKey(const ValueKey('profile-theme')), findsNothing);
    expect(find.byKey(const ValueKey('theme-mode')), findsNothing);
  });

  final pages = <String, Type>{
    'theme': ThemeSettingsScreen,
    'devices': DevicesScreen,
    'signatures': MySignaturesScreen,
    'security': SecuritySettingsScreen,
    'notifications': NotificationPrefsScreen,
    'whats-new': WhatsNewScreen,
    'settings': SettingsScreen,
  };
  for (final e in pages.entries) {
    testWidgets('menu "${e.key}" opens its own page', (tester) async {
      await pumpProfilePage(tester, const ProfileHubScreen(), _replies, size: const Size(430, 2600), routes: _routes);
      await tester.tap(find.byKey(ValueKey('profile-menu-${e.key}')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byWidgetPredicate((w) => w.runtimeType == e.value), findsOneWidget);
    });
  }

  testWidgets('จัดการโปรไฟล์ opens, and แก้ไขโปรไฟล์ is reached from there', (tester) async {
    await pumpProfilePage(tester, const ProfileHubScreen(), _replies, size: const Size(430, 2600));
    await tester.tap(find.byKey(const ValueKey('profile-manage')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ProfileManageScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pm-edit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ProfileEditScreen), findsOneWidget);
  });
}
