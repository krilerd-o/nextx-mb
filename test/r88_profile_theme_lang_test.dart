// R88 — profile: header theme switch (ระบบ / สว่าง / มืด) next to settings;
// TH | EN switch on the profile card instead of the workspace switch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';

import 'support/profile_harness.dart';

void main() {
  tearDown(() => L10n.set('th'));

  testWidgets('header theme switch sits next to settings and changes the app theme', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const ProfileHubScreen(), const {}, size: const Size(430, 2600));
    final pill = find.byKey(const ValueKey('theme-pill'));
    expect(pill, findsOneWidget);
    expect(tester.getTopLeft(pill).dx, lessThan(tester.getTopLeft(find.byKey(const ValueKey('profile-open-settings'))).dx));
    expect(tester.getTopLeft(pill).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('profile-lang-toggle'))).dy), reason: 'in the header, above the card');
    for (final m in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      await tester.tap(find.byKey(ValueKey('theme-pill-${m.name}')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(config.themeMode, m);
    }
  });

  testWidgets('TH | EN switch on the profile card replaces the workspace switch', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const ProfileHubScreen(), const {}, size: const Size(430, 2600));
    expect(find.byKey(const ValueKey('profile-switch')), findsNothing);
    final toggle = find.byKey(const ValueKey('profile-lang-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.getCenter(toggle).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('profile-manage'))).dy), reason: 'on the card, above the โปรไฟล์ section');
    expect(config.uiLocaleCode, 'th');
    await tester.tap(find.byKey(const ValueKey('profile-lang-en')));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(config.uiLocaleCode, 'en');
  });
}
