import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_hero.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

import 'support/fake_api.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('Home greeting header stays pinned while scrolling and turns to the page colours', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HomeChartCache.instance.clear();
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(
      accessToken: 't',
      userId: '7',
      businessId: '1',
      menusLoaded: true,
      menuKeys: ['workspace', 'attendance', 'calendar', 'ai-assistant'],
      displayName: 'สมชาย ใจดี',
    ));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({'GET /api/dashboard/home-summary': {'stats': {}}}));
    await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen())),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The greeting row is the floating header, not part of the scrolling hero.
    expect(find.descendant(of: _key('home-hero'), matching: _key('home-greeting')), findsNothing);
    expect(find.byType(HomeGreetingBar), findsOneWidget);
    final y0 = tester.getTopLeft(_key('home-greeting')).dy;
    expect(y0, greaterThanOrEqualTo(44), reason: 'below the status bar');
    final heroY0 = tester.getTopLeft(_key('home-hero')).dy;
    Color nameColor() => tester.widget<Text>(_key('home-name')).style!.color!;
    expect(nameColor(), Colors.white, reason: 'white on the scene');

    final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(400);
    await tester.pump(const Duration(milliseconds: 300));
    final hero = _key('home-hero');
    // The scene scrolls away (the list may already have dropped it).
    if (hero.evaluate().isNotEmpty) expect(tester.getTopLeft(hero).dy, lessThan(heroY0 - 300));
    expect(tester.getTopLeft(_key('home-greeting')).dy, y0, reason: 'the header stays put');
    expect(tester.getTopLeft(_key('home-search')).dy, greaterThanOrEqualTo(44));
    final onSurface = Theme.of(tester.element(_key('home-name'))).colorScheme.onSurface;
    expect(nameColor(), onSurface, reason: 'normal header colours once the page is under it');

    pos.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(nameColor(), Colors.white);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('lite edge blur draws no BackdropFilter (wash only); full keeps the blur ramp', (tester) async {
    final before = Effects.preference.value;
    addTearDown(() => Effects.preference.value = before);
    Effects.preference.value = EffectsPreference.lite;
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(height: 120, child: NxEdgeBlur(fromTop: true, solidFraction: 0.5)),
    ));
    expect(find.byType(BackdropFilter), findsNothing, reason: 'live blur costs low-end phones frames');
    final wash = tester.widget<DecoratedBox>(find.descendant(of: find.byType(NxEdgeBlur), matching: find.byType(DecoratedBox)));
    final g = (wash.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(g.colors.first.a, greaterThan(0.8), reason: 'the wash keeps text behind the header from ghosting');
    expect(g.colors.last.a, 0, reason: 'and fades out with no hard edge');

    Effects.preference.value = EffectsPreference.full;
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(height: 120, child: NxEdgeBlur(fromTop: true, solidFraction: 0.5)),
    ));
    expect(find.byType(BackdropFilter), findsNWidgets(12));
  });
}
