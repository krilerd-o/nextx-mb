import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_charts.dart';
import 'package:nextx_mobile/screens/dashboard/home_hero.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';

import 'support/fake_api.dart';

SessionState _s(List<String> keys, {String? name = 'สมชาย ใจดี'}) => SessionState(
      accessToken: 't',
      userId: '7',
      businessId: '1',
      menusLoaded: true,
      menuKeys: keys,
      displayName: name,
    );

Finder _key(String k) => find.byKey(ValueKey(k));

Map<String, Object?> _sales({Object? target}) => {
      'deal': {
        'wonCount': '3',
        'wonAmount': '1200000',
        'lostCount': 1,
        'targetAmount': ?target,
      },
      'quotation': {
        'byStatus': [
          {'name': 'Sent', 'value': '5'},
          {'name': 'Draft', 'value': 2},
        ],
      },
    };

Future<(AppConfig, FakeNextxAdapter)> _pumpHome(WidgetTester tester, SessionState session, {Map<String, Object?> replies = const {}}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  HomeChartCache.instance.clear();
  resetHomeChartMemory();
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  config.debugOverrideSession(session);
  final adapter = FakeNextxAdapter({'GET /api/dashboard/home-summary': {'stats': {}}, ...replies});
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen())),
  ));
  for (var i = 0; i < 14; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 60));
  }
  return (config, adapter);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  group('time-of-day scene', () {
    DateTime at(int h, int m) => DateTime(2026, 11, 12, h, m);

    test('phase boundaries: dawn / late morning / noon / afternoon / evening / night', () {
      final cases = {
        at(0, 0): HeroPhase.night,
        at(4, 59): HeroPhase.night,
        at(5, 0): HeroPhase.dawn,
        at(7, 59): HeroPhase.dawn,
        at(8, 0): HeroPhase.lateMorning,
        at(10, 59): HeroPhase.lateMorning,
        at(11, 0): HeroPhase.noon,
        at(12, 59): HeroPhase.noon,
        at(13, 0): HeroPhase.afternoon,
        at(15, 59): HeroPhase.afternoon,
        at(16, 0): HeroPhase.evening,
        at(18, 59): HeroPhase.evening,
        at(19, 0): HeroPhase.night,
        at(23, 59): HeroPhase.night,
      };
      cases.forEach((t, phase) => expect(heroPhaseFor(t), phase, reason: '$t'));
    });

    test('colours change smoothly minute by minute, and midnight joins up', () {
      double diff(HeroPalette a, HeroPalette b) {
        var d = 0.0;
        final ca = a.colors, cb = b.colors;
        for (var i = 0; i < ca.length; i++) {
          for (final (x, y) in [(ca[i].r, cb[i].r), (ca[i].g, cb[i].g), (ca[i].b, cb[i].b), (ca[i].a, cb[i].a)]) {
            d = d > (x - y).abs() ? d : (x - y).abs();
          }
        }
        for (final (x, y) in [(a.starAlpha, b.starAlpha), (a.moonAlpha, b.moonAlpha), (a.cloudAlpha, b.cloudAlpha), (a.birdAlpha, b.birdAlpha)]) {
          d = d > (x - y).abs() ? d : (x - y).abs();
        }
        return d;
      }

      var worst = 0.0;
      for (var m = 0; m < 24 * 60; m++) {
        final d = diff(heroPaletteAtMinute(m.toDouble()), heroPaletteAtMinute(m + 1.0));
        if (d > worst) worst = d;
      }
      expect(worst, lessThan(0.03), reason: 'no visible jump between two minutes');
      expect(diff(heroPaletteAtMinute(0), heroPaletteAtMinute(24 * 60)), 0);
      expect(diff(heroPaletteAt(at(23, 59)), heroPaletteAt(at(0, 0))), lessThan(0.01));
      // Seconds blend too (not only whole minutes).
      expect(diff(heroPaletteAt(DateTime(2026, 11, 12, 17, 45, 30)), heroPaletteAt(at(17, 45))), lessThan(0.02));
    });

    test('each phase looks like its time of day', () {
      double lum(Color c) => c.computeLuminance();
      final noon = heroPaletteAt(at(12, 0));
      final night = heroPaletteAt(at(22, 0));
      final dawn = heroPaletteAt(at(6, 30));
      final evening = heroPaletteAt(at(17, 45));
      expect(noon.skyTop.b, greaterThan(noon.skyTop.r), reason: 'blue sky');
      expect(noon.hillMid.g, greaterThan(noon.hillMid.r), reason: 'green hills');
      expect(lum(night.skyTop), lessThan(lum(noon.skyTop) * 0.3));
      expect(lum(night.hillMid), lessThan(lum(noon.hillMid)));
      expect(evening.skyHorizon.r, greaterThan(evening.skyHorizon.b), reason: 'warm sunset');
      expect(dawn.skyHorizon.r, greaterThan(dawn.skyHorizon.b), reason: 'warm sunrise');
      expect(night.starAlpha, 1);
      expect(noon.starAlpha, 0);
      expect(dawn.mist.a, greaterThan(noon.mist.a), reason: 'morning mist');
    });

    test('sun crosses the day sky, moon the night sky', () {
      expect(heroSunProgress(at(3, 0)), isNull);
      expect(heroSunProgress(at(22, 0)), isNull);
      expect(heroSunProgress(at(6, 30)), inExclusiveRange(0, 0.1));
      expect(heroSunProgress(at(12, 7)), closeTo(0.5, 0.01));
      expect(heroSunProgress(at(17, 45)), inExclusiveRange(0.9, 1));
      expect(heroMoonProgress(at(12, 0)), isNull);
      expect(heroMoonProgress(at(22, 0)), inExclusiveRange(0.2, 0.5));
      expect(heroMoonProgress(at(3, 0)), inExclusiveRange(0.6, 1));
      expect(heroMoonProgress(at(23, 59))! < heroMoonProgress(at(0, 1))!, isTrue, reason: 'continues past midnight');
    });
  });

  group('scene motion', () {
    Future<HomeHeroSceneState> pumpScene(WidgetTester tester, {bool reduce = false, bool ticker = true, EffectsPreference pref = EffectsPreference.lite}) async {
      Effects.preference.value = pref;
      addTearDown(() => Effects.preference.value = EffectsPreference.lite);
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: ticker,
          child: SizedBox(width: 412, height: 420, child: HomeHeroScene(key: const ValueKey('scene'), time: DateTime(2026, 11, 12, 9, 30))),
        ),
      ));
      return tester.state<HomeHeroSceneState>(_key('scene'));
    }

    testWidgets('moves while shown (lite and full)', (tester) async {
      for (final pref in [EffectsPreference.lite, EffectsPreference.full]) {
        final s = await pumpScene(tester, pref: pref);
        expect(s.animating, isTrue, reason: '$pref');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('reduce motion / effects off / hidden: still frame, no motion timer', (tester) async {
      expect((await pumpScene(tester, reduce: true)).animating, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect((await pumpScene(tester, pref: EffectsPreference.off)).animating, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect((await pumpScene(tester, ticker: false)).animating, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pauses when its tab is hidden and resumes when shown', (tester) async {
      Widget tabs(int index) => MediaQuery(
            data: const MediaQueryData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: IndexedStack(index: index, children: [
                SizedBox(width: 412, height: 420, child: HomeHeroScene(key: const ValueKey('scene'), time: DateTime(2026, 11, 12, 12))),
                const SizedBox(),
              ]),
            ),
          );
      await tester.pumpWidget(tabs(0));
      final s = tester.state<HomeHeroSceneState>(_key('scene'));
      expect(s.animating, isTrue);
      await tester.pumpWidget(tabs(1));
      expect(s.animating, isFalse);
      await tester.pumpWidget(tabs(0));
      expect(s.animating, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pauses once scrolled out of view', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(controller: scroll, children: [
            SizedBox(height: 420, child: HomeHeroScene(key: const ValueKey('scene'), time: DateTime(2026, 11, 12, 15))),
            const SizedBox(height: 3000),
          ]),
        ),
      ));
      final s = tester.state<HomeHeroSceneState>(_key('scene'));
      expect(s.animating, isTrue);
      scroll.jumpTo(200);
      await tester.pump();
      expect(s.animating, isTrue, reason: 'still partly visible');
      scroll.jumpTo(500);
      await tester.pump();
      expect(s.animating, isFalse);
      scroll.jumpTo(0);
      await tester.pump();
      expect(s.animating, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('headline kind by permission', () {
    test('sales / service / attendance / none', () {
      expect(homeHeadlineKind(_s(['deal', 'attendance'])), HomeHeadlineKind.sales);
      expect(homeHeadlineKind(_s(['quotation'])), HomeHeadlineKind.sales);
      expect(homeHeadlineKind(_s(['job', 'attendance'])), HomeHeadlineKind.service);
      expect(homeHeadlineKind(_s(['case'])), HomeHeadlineKind.service);
      expect(homeHeadlineKind(_s(['attendance', 'leave-request'])), HomeHeadlineKind.attendance);
      expect(homeHeadlineKind(_s(['workspace'])), HomeHeadlineKind.none);
      expect(homeHeadlineKind(_s(const [])), HomeHeadlineKind.none);
    });

    test('delta label', () {
      expect(heroDeltaLabel(23.44), '+23.4%');
      expect(heroDeltaLabel(-5), '−5%');
      expect(heroDeltaLabel(140.2), '+140%');
    });
  });

  testWidgets('hero only greets: drawn scene, greeting + short date, name, search, bell; no business chip', (tester) async {
    await _pumpHome(tester, _s(['attendance', 'leave-request']));
    expect(_key('home-hero-scene'), findsOneWidget);
    expect(find.descendant(of: _key('home-hero'), matching: find.byType(Image)), findsNothing, reason: 'no photo any more');
    expect(_key('home-hero-dim'), findsNothing, reason: 'light mode is not dimmed');
    final greeting = tester.widget<Text>(_key('home-greeting')).data!;
    expect(greeting, startsWith(greetingFor(thaiNow())));
    expect(greeting, contains(thaiShortDate(thaiNow())));
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(_key('home-search'), findsOneWidget);
    expect(_key('home-bell'), findsOneWidget);
    expect(find.textContaining('NEXT'), findsNothing, reason: 'business switcher chip removed from Home');
    await _dispose(tester);
  });

  testWidgets('no headline number on the photo for any role; clock-in stays in the today card', (tester) async {
    for (final keys in const [
      ['attendance', 'leave-request'],
      ['deal', 'quotation', 'attendance'],
      ['quotation'],
      ['job', 'attendance'],
    ]) {
      await _pumpHome(tester, _s(keys), replies: {
        'GET /api/dashboard/sales': _sales(),
        'GET /api/hr/attendance/summary': {
          'summary': {'clock_in_at': '2026-11-12 10:09:00'},
        },
      });
      for (final k in ['home-headline-attendance', 'home-headline-sales', 'home-headline-quotes', 'home-headline-service']) {
        expect(_key(k), findsNothing, reason: '$keys $k');
      }
      expect(find.descendant(of: _key('home-hero'), matching: find.textContaining('฿')), findsNothing);
      if (keys.contains('attendance')) {
        expect(find.text('ลงเวลาวันนี้'), findsOneWidget, reason: 'attendance row in the today card');
      }
      await _dispose(tester);
    }
  });

  testWidgets('ISAAC card only with the AI menu; arrow opens the assistant', (tester) async {
    await _pumpHome(tester, _s(['attendance', 'ai-assistant']));
    expect(_key('home-isaac'), findsOneWidget);
    expect(_key('home-isaac-open'), findsOneWidget);
    expect(find.text('ISAAC แนะนำ'), findsOneWidget);
    expect(tester.widget<Text>(_key('home-isaac-text')).data, isNotEmpty);
    await _dispose(tester);

    await _pumpHome(tester, _s(['attendance']));
    expect(_key('home-isaac'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('small phone with large text in dark mode, and tablet: no overflow', (tester) async {
    for (final (size, scale, dark) in const [(Size(360, 1800), 1.35, true), (Size(1180, 1600), 1.0, false)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HomeChartCache.instance.clear();
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      config.debugOverrideSession(_s(['deal', 'quotation', 'lead', 'attendance', 'ai-assistant', 'workspace', 'calendar'],
          name: 'ชื่อยาวมากมากมาก นามสกุลยาวมากมากมากมาก'));
      config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({
        'GET /api/dashboard/home-summary': {
          'stats': {'lead': 1, 'deal': 2, 'quotation': 3},
        },
        'GET /api/dashboard/sales': _sales(target: 3000000),
      }));
      await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale), padding: const EdgeInsets.only(top: 44)),
            child: const Scaffold(body: MobileDashboardScreen()),
          ),
        ),
      ));
      for (var i = 0; i < 14; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(tester.takeException(), isNull, reason: '$size');
      expect(_key('home-isaac'), findsOneWidget);
      expect(_key('home-hero-scene'), findsOneWidget);
      expect(_key('home-hero-dim'), dark ? findsOneWidget : findsNothing);
      await _dispose(tester);
    }
  });

  test('isaacSuggestion takes the first part of the day summary', () {
    expect(isaacSuggestion('ยังไม่ได้ลงเวลาเข้างาน · มีงานครบกำหนดวันนี้ 2 รายการ'), 'ยังไม่ได้ลงเวลาเข้างาน');
    expect(isaacSuggestion('  ข้อความเดียว '), 'ข้อความเดียว');
  });

  group('column chart', () {
    test('selects the latest column with a value', () {
      expect(defaultColumnIndex([1, 2, 0, 0]), 1);
      expect(defaultColumnIndex([0, 0, 3]), 2);
      expect(defaultColumnIndex([0, 0]), 1);
      expect(defaultColumnIndex(const []), -1);
    });

    testWidgets('floating label follows the tapped column', (tester) async {
      const d = SeriesData(labels: ['ก.ย.', 'ต.ค.', 'พ.ย.'], series: {
        'ยอด': [500000, 1200000, 0],
      });
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SizedBox(width: 300, height: 200, child: ColumnsChart(d, baht: true, empty: '-'))),
        ),
      ));
      expect(find.descendant(of: _key('col-tip'), matching: find.text('฿1.2M')), findsOneWidget);
      await tester.tap(_key('col-0'));
      await tester.pump();
      expect(find.descendant(of: _key('col-tip'), matching: find.text('฿500K')), findsOneWidget);
    });
  });
}
