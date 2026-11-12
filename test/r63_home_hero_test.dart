import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
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
  group('time-of-day tone', () {
    test('hours map to morning / afternoon / evening / night', () {
      HeroTone at(int h) => heroToneFor(DateTime(2026, 11, 12, h, 30));
      expect(at(4), HeroTone.night);
      expect(at(5), HeroTone.morning);
      expect(at(10), HeroTone.morning);
      expect(at(11), HeroTone.afternoon);
      expect(at(15), HeroTone.afternoon);
      expect(at(16), HeroTone.evening);
      expect(at(18), HeroTone.evening);
      expect(at(19), HeroTone.night);
      expect(at(23), HeroTone.night);
      expect(at(0), HeroTone.night);
    });

    test('matrix: afternoon as shot, evening warm, night dark/blue, dark mode dims', () {
      final afternoon = heroToneMatrix(HeroTone.afternoon);
      expect(afternoon, [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
      final evening = heroToneMatrix(HeroTone.evening);
      expect(evening[0], greaterThan(evening[12]), reason: 'red gain above blue = warm');
      final night = heroToneMatrix(HeroTone.night);
      expect(night[0], lessThan(0.5));
      expect(night[12], greaterThan(night[0]), reason: 'blue tint');
      final morning = heroToneMatrix(HeroTone.morning);
      expect(morning[0], greaterThan(1));
      final dimmed = heroToneMatrix(HeroTone.afternoon, dark: true);
      expect(dimmed[0], lessThan(1));
      expect(dimmed[18], 1, reason: 'alpha untouched');
      expect(heroToneOverlay(HeroTone.afternoon).every((c) => c.a == 0), isTrue);
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

  testWidgets('hero only greets: photo, greeting + short date, name, search, bell; no business chip', (tester) async {
    await _pumpHome(tester, _s(['attendance', 'leave-request']));
    final img = tester.widget<Image>(_key('home-hero-image'));
    expect((img.image as AssetImage).assetName, kHomeHeroImage);
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
