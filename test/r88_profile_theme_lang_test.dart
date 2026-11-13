// R88 — profile card: theme toggle (ระบบ / สว่าง / มืด) instead of the
// workspace switch; header TH | EN switch next to settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';

import 'support/profile_harness.dart';

void main() {
  tearDown(() => L10n.set('th'));

  testWidgets('theme toggle on the profile card changes the app theme', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const ProfileHubScreen(), const {}, size: const Size(430, 2600));
    expect(find.byKey(const ValueKey('profile-switch')), findsNothing, reason: 'replaced by the theme toggle');
    expect(find.byKey(const ValueKey('profile-theme-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-theme-dark')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(config.themeMode, ThemeMode.dark);
    await tester.tap(find.byKey(const ValueKey('profile-theme-light')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(config.themeMode, ThemeMode.light);
    await tester.tap(find.byKey(const ValueKey('profile-theme-system')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(config.themeMode, ThemeMode.system);
  });

  testWidgets('header TH | EN switch sits next to settings and changes the language', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const ProfileHubScreen(), const {}, size: const Size(430, 2600));
    final pill = find.byKey(const ValueKey('lang-pill'));
    expect(pill, findsOneWidget);
    expect(tester.getTopLeft(pill).dx, lessThan(tester.getTopLeft(find.byKey(const ValueKey('profile-open-settings'))).dx));
    expect(config.uiLocaleCode, 'th');
    await tester.tap(find.byKey(const ValueKey('lang-pill-en')));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(config.uiLocaleCode, 'en');
  });
}

