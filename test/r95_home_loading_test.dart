// Performance round: Home loads with fewer requests and paints the last copy at once.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_birthdays.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';

import 'support/fake_api.dart';

const _session = SessionState(
  accessToken: 't',
  userId: '7',
  businessId: '1',
  menusLoaded: true,
  menuKeys: ['attendance', 'workspace', 'calendar', 'lead', 'deal', 'contact'],
  displayName: 'สมชาย ใจดี',
);

/// Holds every reply until [open] (the network is slow; the saved copy must show first).
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.inner);
  final FakeNextxAdapter inner;
  final gate = Completer<void>();
  void open() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    await gate.future;
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

Future<AppConfig> _config(WidgetTester tester, HttpClientAdapter adapter, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  HomeChartCache.instance.clear();
  CalBirthdays.clearCache();
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  config.debugOverrideSession(_session);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
  return config;
}

Future<void> _pumpHome(WidgetTester tester, AppConfig config, {double height = 4000}) async {
  tester.view.physicalSize = Size(412, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen())),
  ));
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Map<String, Object?> _baseReplies() => {
      'GET /api/dashboard/home-summary': {
        'stats': {'lead': 40, 'deal': 9, 'contact': 3},
      },
      'GET /api/home/work': {
        'counts': {'overdue': 2, 'today': 1, 'upcoming': 4},
        'items': [
          {'id': 5, 'board_id': 3, 'title': '[QA] งานค้าง', 'type': 'task', 'bucket': 'overdue', 'due_at': '2026-11-01 10:00:00'},
        ],
      },
    };

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  testWidgets('ภาพรวม from one home-stats call (no per-module / per-day counts)', (tester) async {
    final fake = FakeNextxAdapter({
      ..._baseReplies(),
      'GET /api/dashboard/home-stats': {
        'modules': {
          'lead': {'mine': 12, 'total': 40, 'spark': [0, 1, 0, 2, 0, 0, 3]},
          'deal': {'mine': 4, 'total': 9, 'spark': [0, 0, 0, 0, 0, 0, 1]},
          'contact': {'mine': 3, 'total': 3, 'spark': [0, 0, 0, 0, 0, 0, 0]},
        },
      },
    });
    final config = await _config(tester, fake);
    await _pumpHome(tester, config);
    await _settle(tester);
    expect(fake.calls.where((c) => c.path == '/api/dashboard/home-stats').single.queryParameters['days'], '7');
    final counts = fake.calls.where((c) => c.path.startsWith('/api/entity/') && c.queryParameters['cols'] == 'id');
    expect(counts, isEmpty, reason: 'no 7 totals + 49 daily counts');
    expect(find.byKey(const ValueKey('home-stat-lead')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('home-stat-lead')), matching: find.text('12')), findsOneWidget);
    // home-summary asks only for stats + upcoming; /api/home/work once.
    expect(fake.calls.singleWhere((c) => c.path == '/api/dashboard/home-summary').queryParameters['fields'], 'stats,upcoming');
    expect(fake.calls.where((c) => c.path == '/api/home/work' && c.queryParameters['scope'] == null).map((c) => c.queryParameters).toList(), hasLength(1));
    await _done(tester);
  });

  testWidgets('older server (home-stats 404): falls back to the per-module counts, asked once', (tester) async {
    final fake = FakeNextxAdapter(_baseReplies());
    final config = await _config(tester, fake);
    await _pumpHome(tester, config);
    await _settle(tester);
    expect(fake.callKeys.where((k) => k == 'GET /api/dashboard/home-stats'), hasLength(1));
    final lead = fake.calls.where((c) => c.path == '/api/entity/lead' && c.queryParameters['cols'] == 'id').toList();
    expect(lead.where((c) => c.queryParameters['period_start'] == null), hasLength(1), reason: 'my total');
    expect(lead.where((c) => c.queryParameters['period_start'] != null), hasLength(7), reason: 'one count per day');
    expect(lead.first.queryParameters['filter[smownerid]'], '7');

    // Pull-to-refresh: the missing route is not asked again on this server.
    await tester.fling(find.byKey(const ValueKey('home-scroll')), const Offset(0, 600), 1500);
    await _settle(tester, frames: 30);
    expect(fake.callKeys.where((k) => k == 'GET /api/dashboard/home-stats'), hasLength(1));
    await _done(tester);
  });

  testWidgets('cold start: the saved Home of this Space shows before the network answers, then refreshes', (tester) async {
    final fake = FakeNextxAdapter({
      ..._baseReplies(),
      'GET /api/dashboard/home-stats': {
        'modules': {
          'lead': {'mine': 13, 'total': 41, 'spark': [0, 0, 0, 0, 0, 0, 1]},
        },
      },
    });
    final gated = _GatedAdapter(fake);
    // Scope of the session above (server + user + business).
    final probe = await _config(tester, gated);
    final key = 'nx_home_cache_v1|${probe.businessScope}';
    final saved = jsonEncode({
      'summary': {
        'stats': {'lead': 40},
        'upcoming': [],
      },
      'work': {
        'counts': {'overdue': 0, 'today': 0, 'upcoming': 0},
      },
      'mine': {'lead': 77},
      'sparks': {},
      'whats_new': 0,
    });
    final config = await _config(tester, gated, prefs: {key: saved});
    await _pumpHome(tester, config);
    await _settle(tester, frames: 6);
    expect(fake.calls, isEmpty, reason: 'network still pending');
    expect(find.descendant(of: find.byKey(const ValueKey('home-stat-lead')), matching: find.text('77')), findsOneWidget,
        reason: 'last copy painted at once');
    expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'refreshing in the background');

    gated.open();
    await _settle(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('home-stat-lead')), matching: find.text('13')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final stored = jsonDecode(prefs!.getString(key)!) as Map;
    expect((stored['mine'] as Map)['lead'], 13, reason: 'the fresh payload is saved for next time');
    await _done(tester);
  });

  testWidgets('birthday box: one upcoming call on newer servers (no 500-row pages)', (tester) async {
    final today = DateTime.now();
    String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final fake = FakeNextxAdapter({
      ..._baseReplies(),
      'GET /api/calendar/birthdays/upcoming': {
        'items': [
          {'module': 'contact', 'id': 9, 'name': '[QA] คุณวันเกิด', 'birthdate': '1990-${ymd(today).substring(5)}', 'next_date': ymd(today), 'days_until': 0},
        ],
      },
    });
    final config = await _config(tester, fake);
    await _pumpHome(tester, config);
    await _settle(tester);
    expect(fake.calls.where((c) => c.path == '/api/calendar/birthdays/upcoming').single.queryParameters['days'], '30');
    expect(fake.calls.where((c) => c.queryParameters['period_field'] == 'birthdate'), isEmpty);
    expect(find.text('[QA] คุณวันเกิด'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('Home widgets are lazy rows: a short phone builds only what is near the screen', (tester) async {
    final fake = FakeNextxAdapter(_baseReplies());
    final config = await _config(tester, fake);
    await _pumpHome(tester, config, height: 700);
    await _settle(tester);
    expect(find.byKey(const ValueKey('home-scroll')), findsOneWidget);
    expect(find.byType(SliverList), findsWidgets);
    // Widgets paint over the hero's scene (it runs on under the first one), as in the old ListView.
    expect(tester.widget<CustomScrollView>(find.byKey(const ValueKey('home-scroll'))).paintOrder, SliverPaintOrder.lastIsTop);
    // The last widgets of the default order are not built until scrolled near.
    expect(find.byKey(const ValueKey('home-birthdays')), findsNothing);
    expect(fake.calls.where((c) => c.path == '/api/calendar/birthdays/upcoming'), isEmpty, reason: 'its data loads when it nears the screen');
    await _done(tester);
  });
}
