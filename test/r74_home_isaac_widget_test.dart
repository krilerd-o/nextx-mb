import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_charts.dart';
import 'package:nextx_mobile/screens/dashboard/home_isaac.dart';
import 'package:nextx_mobile/screens/dashboard/home_layout_editor.dart';
import 'package:nextx_mobile/screens/dashboard/home_widgets.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/services/api_exceptions.dart';

import 'support/fake_api.dart';

SessionState _s(List<String> keys) => SessionState(
      accessToken: 't',
      userId: '7',
      businessId: '1',
      menusLoaded: true,
      menuKeys: keys,
      displayName: 'สมชาย ใจดี',
    );

const _ai = ['attendance', 'calendar', 'ai-assistant'];

Finder _key(String k) => find.byKey(ValueKey(k));

String _sse(List<Map<String, Object?>> events) => [for (final e in events) 'data: ${jsonEncode(e)}\n\n'].join();

String _tomorrow10() {
  final d = thaiNow().add(const Duration(days: 1));
  return '${isaacDayKey(d)} 10:00:00';
}

const _reply = '- ลงเวลาเข้างานก่อนเริ่มงาน [[r1]]\n- **เตรียมตัว**พบลูกค้า A พรุ่งนี้ 10:00 [[r2]]\n- ทบทวนดีลที่ค้างอยู่';

class _Home {
  _Home(this.config, this.adapter, this.router);
  final AppConfig config;
  final FakeNextxAdapter adapter;
  final GoRouter router;

  int get asks => adapter.callKeys.where((k) => k == 'POST /api/ai/chat').length;
  String get location => router.routeInformationProvider.value.uri.path;
}

/// Home inside a GoRouter, so taps that navigate land on a marker page.
Future<_Home> _pump(
  WidgetTester tester,
  List<String> menus, {
  Map<String, Object?> prefs = const {},
  bool resetPrefs = true,
  AppConfig? reuse,
  FakeNextxAdapter? adapter,
  Size size = const Size(390, 2400),
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  if (resetPrefs) {
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
    FlutterSecureStorage.setMockInitialValues({});
    IsaacBriefCache.clearMemory();
  }
  HomeChartCache.instance.clear();
  resetHomeChartMemory();
  final config = reuse ?? AppConfig();
  if (reuse == null) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(_s(menus));
  }
  final fake = adapter ??
      FakeNextxAdapter({
        'GET /api/dashboard/home-summary': {
          'stats': {},
          'activities': [
            {'id': 55, 'subject': 'พบลูกค้า A', 'date_start': _tomorrow10(), 'location': 'สีลม'},
          ],
        },
      }, sseFor: {
        'POST /api/ai/chat': _sse([
          {'type': 'token', 'content': '- ลงเวลาเข้างานก่อนเริ่มงาน [[r1]]\n'},
          {'type': 'token', 'content': '- **เตรียมตัว**พบลูกค้า A พรุ่งนี้ 10:00 [[r2]]\n- ทบทวนดีลที่ค้างอยู่'},
          {'type': 'done', 'message': {'role': 'assistant', 'content': _reply}},
        ]),
      });
  config.apiClient.debugSetHttpAdapter(fake);
  await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: MobileDashboardScreen())),
    GoRoute(path: AppRoutes.aiChat, builder: (_, _) => const Scaffold(body: Text('AI-SCREEN'))),
    GoRoute(path: '/calendar/:id', builder: (_, st) => Scaffold(body: Text('ACT-${st.pathParameters['id']}'))),
    GoRoute(path: AppRoutes.attendance, builder: (_, _) => const Scaffold(body: Text('ATTENDANCE'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await _settle(tester);
  return _Home(config, fake, router);
}

Future<void> _settle(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

/// The Home layout prefs key for [menus]'s user (mocks set first).
Future<String> _layoutKey(WidgetTester tester, List<String> menus) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final probe = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  probe.debugOverrideSession(_s(menus));
  return 'nx_home_layout_v2_${probe.businessScope}';
}

Future<void> _tapIsaac(WidgetTester tester) async {
  await tester.ensureVisible(_key('home-isaac'));
  await tester.tap(_key('home-isaac'));
  await tester.pump();
}

String _v2(List<String> ids, {bool flagged = true}) => jsonEncode({
      'v': 2,
      if (flagged) 'isaac': true,
      'entries': [for (final id in ids) {'id': id, 'size': 'full'}],
    });

void main() {
  group('parsing + prompt', () {
    const facts = [
      IsaacFact('ยังไม่ได้ลงเวลาเข้างาน', route: '/hr/attendance'),
      IsaacFact('งาน Workspace: ครบกำหนดวันนี้ 2'),
      IsaacFact('นัดหมาย 10:00: พบลูกค้า A', route: '/calendar/55'),
    ];

    test('bullets resolve [[rN]] to the fact route; bold / headings stripped', () {
      final items = parseIsaacBrief('## สรุป\n- ลงเวลาก่อน [[r1]]\n* **พบ** ลูกค้า A [[r3]]\n1. ทบทวนงาน [[r2]]\n- อ้างผิด [[r9]]', facts);
      expect(items, const [
        IsaacBriefItem('ลงเวลาก่อน', route: '/hr/attendance'),
        IsaacBriefItem('พบ ลูกค้า A', route: '/calendar/55'),
        IsaacBriefItem('ทบทวนงาน'), // r2 has no route
        IsaacBriefItem('อ้างผิด'),
      ]);
    });

    test('a reply without list markers: every line is one item', () {
      expect(parseIsaacBrief('วันนี้ว่าง\nลองโทรหาลูกค้าเก่า', facts).map((e) => e.text), ['วันนี้ว่าง', 'ลองโทรหาลูกค้าเก่า']);
      expect(parseIsaacBrief('   ', facts), isEmpty);
    });

    test('prompt: references only on facts that open something; body = streaming chat, no tools, no saved chat', () {
      final now = DateTime(2026, 11, 13, 9, 5);
      final p = isaacBriefPrompt(facts, now);
      expect(p, contains('ยังไม่ได้ลงเวลาเข้างาน [[r1]]'));
      expect(p, contains('ครบกำหนดวันนี้ 2\n'), reason: 'no reference on a fact without a route');
      expect(p, contains('พบลูกค้า A [[r3]]'));
      expect(p, contains('2026-11-13 เวลา 09:05'));
      final body = isaacBriefBody(facts, now);
      expect(body['stream'], isTrue);
      expect(body['enable_tools'], isFalse);
      expect(body['inject_context'], isFalse);
      expect(body.containsKey('conversation_id'), isFalse);
      expect((body['messages'] as List).last['content'], p);
    });

    test('Thai error messages: quota, AI not set up, offline, other', () {
      expect(isaacErrorText(ApiEnvelopeException(402, 'AI_QUOTA_EXHAUSTED', 'x')), contains('โควตา AI เดือนนี้หมดแล้ว'));
      expect(isaacErrorText(ApiEnvelopeException(403, 'AI_FEATURE_DISABLED', 'x')), contains('ยังไม่ได้ตั้งค่า AI'));
      expect(isaacErrorText(ApiEnvelopeException(503, 'AI_AUTO_NO_MODEL', 'x')), contains('ยังไม่ได้ตั้งค่า AI'));
      expect(isaacErrorText(ApiEnvelopeException(429, 'AI_MODEL_DAILY_EXHAUSTED', 'x')), contains('โควตา AI วันนี้หมดแล้ว'));
      expect(isaacErrorText(ApiException(0, 'network')), contains('เชื่อมต่อไม่สำเร็จ'));
      expect(isaacErrorText(Exception('boom')), 'ไอแซคสรุปไม่สำเร็จ — ลองใหม่อีกครั้ง');
    });
  });

  group('layout', () {
    test('registered like the other widgets: on top of the default, gated by the AI menu', () {
      expect(HomeLayout.defaultEntries().first.id, 'ai');
      expect(HomeLayout.isKnown('ai'), isTrue);
      final info = HomeWidgetInfo.of('ai');
      expect(info.title, 'ไอแซคแนะนำ');
      expect(info.hint, isNotEmpty);
      expect(info.group, 'general');
      expect(homeWidgetAllowed(_s(_ai), 'ai'), isTrue);
      expect(homeWidgetAllowed(_s(['attendance', 'calendar']), 'ai'), isFalse);
    });

    test('saved layouts get it on top once; then the user\'s move / removal sticks', () async {
      const scope = 'u9|b1';
      SharedPreferences.setMockInitialValues({'nx_home_layout_v2_$scope': _v2(['today', 'quick', 'ai'], flagged: false)});
      final h = HomeLayout.instance;
      await h.load(scope, force: true);
      expect(h.visibleOrder, ['ai', 'today', 'quick']);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('nx_home_layout_v2_$scope')!)['isaac'], isTrue, reason: 'migrated once and saved');

      await h.saveEntries(scope, const [HomeEntry('today'), HomeEntry('ai')]);
      await h.load(scope, force: true);
      expect(h.visibleOrder, ['today', 'ai'], reason: 'moved down stays down');

      await h.saveEntries(scope, const [HomeEntry('today')]);
      await h.load(scope, force: true);
      expect(h.visibleOrder, ['today'], reason: 'removed stays removed');
    });
  });

  testWidgets('a normal widget: follows the saved order and sits below the hero', (tester) async {
    final key = await _layoutKey(tester, _ai);

    await _pump(tester, _ai, prefs: {key: _v2(['today', 'ai'])});
    final today = tester.getTopLeft(find.text('ลงเวลาวันนี้')).dy;
    final isaac = tester.getTopLeft(_key('home-isaac')).dy;
    expect(isaac, greaterThan(today), reason: 'second widget comes second');
    expect(tester.getTopLeft(_key('home-isaac')).dy, greaterThanOrEqualTo(tester.getBottomLeft(_key('home-hero')).dy));
    await _dispose(tester);

    await _pump(tester, _ai, prefs: {key: _v2(['ai', 'today'])});
    expect(tester.getTopLeft(_key('home-isaac')).dy, lessThan(tester.getTopLeft(find.text('ลงเวลาวันนี้')).dy));
    await _dispose(tester);
  });

  testWidgets('permission: hidden without the AI menu even when in the layout; not in the gallery', (tester) async {
    await _pump(tester, const ['attendance', 'calendar']);
    expect(HomeLayout.instance.visibleOrder.first, 'ai');
    expect(_key('home-isaac'), findsNothing);
    await tester.ensureVisible(_key('home-add-widget-link'));
    await tester.tap(_key('home-add-widget-link'));
    await tester.pumpAndSettle();
    expect(_key('widget-gallery'), findsOneWidget);
    expect(_key('gallery-ai'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('gallery: add "ไอแซคแนะนำ" back, and the layout editor removes it', (tester) async {
    final key = await _layoutKey(tester, _ai);

    final home = await _pump(tester, _ai, prefs: {key: _v2(['today', 'quick'])});
    expect(_key('home-isaac'), findsNothing);
    await tester.ensureVisible(_key('home-add-widget-link'));
    await tester.tap(_key('home-add-widget-link'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('gallery-ai'), matching: find.text('ไอแซคแนะนำ')), findsOneWidget);
    expect(_key('gallery-hint-ai'), findsOneWidget);
    await tester.tap(_key('gallery-add-ai'));
    // Edit mode wiggles (never settles): pump frames instead.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(_key('home-edit-done'));
    await _settle(tester, 6);
    expect(HomeLayout.instance.visibleOrder, ['today', 'quick', 'ai']);
    expect(_key('home-isaac'), findsOneWidget);
    await _dispose(tester);

    // ตั้งค่า → reorder / hide list has it too; removing it is saved.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: home.config, child: const MaterialApp(home: HomeLayoutEditorScreen())));
    await tester.pumpAndSettle();
    expect(_key('editor-ai'), findsOneWidget);
    await tester.tap(_key('editor-remove-ai'));
    await tester.pumpAndSettle();
    await tester.tap(_key('home-editor-save'));
    await _settle(tester, 4);
    await tester.runAsync(() => HomeLayout.instance.load(home.config.businessScope, force: true));
    expect(HomeLayout.instance.visibleOrder, isNot(contains('ai')));
    await _dispose(tester);
  });

  testWidgets('tap: opens in place with a loading shimmer, then ISAAC\'s bullets — no navigation', (tester) async {
    final home = await _pump(tester, _ai);
    expect(_key('home-isaac-body'), findsNothing);
    expect(home.asks, 0, reason: 'nothing is asked until the card is opened');
    await _tapIsaac(tester);
    expect(_key('home-isaac-body'), findsOneWidget);
    expect(_key('home-isaac-loading'), findsOneWidget);
    await _settle(tester);
    expect(home.location, '/', reason: 'stays on Home');
    expect(find.text('AI-SCREEN'), findsNothing);
    expect(home.asks, 1);
    final body = home.adapter.calls.firstWhere((c) => c.path == '/api/ai/chat').data as Map;
    expect(body['enable_tools'], isFalse);
    final prompt = '${(body['messages'] as List).last['content']}';
    expect(prompt, contains('ยังไม่ได้ลงเวลาเข้างาน [[r1]]'));
    expect(prompt, contains('พบลูกค้า A'));
    expect(_key('home-isaac-items'), findsOneWidget);
    expect(find.text('ลงเวลาเข้างานก่อนเริ่มงาน'), findsOneWidget);
    expect(find.text('เตรียมตัวพบลูกค้า A พรุ่งนี้ 10:00'), findsOneWidget);
    expect(find.text('ทบทวนดีลที่ค้างอยู่'), findsOneWidget);
    expect(find.textContaining('[[r'), findsNothing);
    expect(find.textContaining('สรุปเมื่อ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A bullet about a record opens it.
    await tester.tap(_key('home-isaac-item-1'));
    await tester.pumpAndSettle();
    expect(find.text('ACT-55'), findsOneWidget);
    home.router.pop();
    await tester.pumpAndSettle();

    // "ถามต่อในไอแซค" is the only way to the assistant.
    await tester.ensureVisible(_key('home-isaac-ask'));
    await tester.tap(_key('home-isaac-ask'));
    await tester.pumpAndSettle();
    expect(find.text('AI-SCREEN'), findsOneWidget);
    home.router.pop();
    await tester.pumpAndSettle();

    // Tap again → closes, still no navigation.
    await _tapIsaac(tester);
    await tester.pumpAndSettle();
    expect(_key('home-isaac-body'), findsNothing);
    expect(home.location, '/');
    await _dispose(tester);
  });

  testWidgets('cache: the day\'s summary is kept (memory + device); refresh asks again; a new day asks again', (tester) async {
    final home = await _pump(tester, _ai);
    await _tapIsaac(tester);
    await _settle(tester);
    expect(home.asks, 1);

    // Back to Home (same app run): open with the summary, nothing asked.
    await _dispose(tester);
    await _pump(tester, _ai, resetPrefs: false, reuse: home.config, adapter: home.adapter);
    expect(_key('home-isaac-items'), findsOneWidget, reason: 'stays open with the cached summary');
    expect(home.asks, 1);

    // App restarted (memory gone, device cache kept): tap shows it without asking.
    await _dispose(tester);
    IsaacBriefCache.clearMemory();
    await _pump(tester, _ai, resetPrefs: false, reuse: home.config, adapter: home.adapter);
    expect(_key('home-isaac-body'), findsNothing);
    await _tapIsaac(tester);
    await _settle(tester, 4);
    expect(_key('home-isaac-items'), findsOneWidget);
    expect(home.asks, 1);

    // Refresh on demand.
    await tester.tap(_key('home-isaac-refresh'));
    await tester.pump();
    await _settle(tester);
    expect(home.asks, 2);
    expect(_key('home-isaac-items'), findsOneWidget);
    await _dispose(tester);

    // Yesterday's summary is not shown.
    final scope = home.config.businessScope;
    IsaacBriefCache.clearMemory();
    final old = IsaacBrief(day: '2000-01-01', at: DateTime(2000), items: const [IsaacBriefItem('เก่า')]);
    final fresh = await _pump(tester, _ai, prefs: {IsaacBriefCache.prefsKey(scope): jsonEncode(old.toJson())});
    await _tapIsaac(tester);
    await _settle(tester);
    expect(find.text('เก่า'), findsNothing);
    expect(fresh.asks, 1);
    await _dispose(tester);
  });

  testWidgets('errors: quota / AI not set up show a Thai message and retry works', (tester) async {
    final adapter = FakeNextxAdapter(
      {'GET /api/dashboard/home-summary': {'stats': {}}},
      statusFor: {'POST /api/ai/chat': 402},
      errorsFor: {
        'POST /api/ai/chat': {'error_code': 'AI_QUOTA_EXHAUSTED', 'message': 'quota'},
      },
      sseFor: {
        'POST /api/ai/chat': _sse([
          {'type': 'done', 'message': {'content': '- เคลียร์งานค้าง'}},
        ]),
      },
    );
    final home = await _pump(tester, _ai, adapter: adapter);
    await _tapIsaac(tester);
    await _settle(tester);
    expect(_key('home-isaac-error'), findsOneWidget);
    expect(find.textContaining('โควตา AI เดือนนี้หมดแล้ว'), findsOneWidget);
    expect(home.location, '/');

    adapter.errorsFor['POST /api/ai/chat'] = {'error_code': 'AI_FEATURE_DISABLED', 'message': 'off'};
    await tester.tap(_key('home-isaac-retry'));
    await tester.pump();
    await _settle(tester);
    expect(find.textContaining('ยังไม่ได้ตั้งค่า AI'), findsOneWidget);

    // An error inside the stream too.
    adapter.errorsFor.clear();
    adapter.statusFor.clear();
    await tester.tap(_key('home-isaac-retry'));
    await tester.pump();
    await _settle(tester);
    expect(_key('home-isaac-error'), findsNothing);
    expect(find.text('เคลียร์งานค้าง'), findsOneWidget);
    expect(home.asks, 3);
    await _dispose(tester);
  });

  testWidgets('stream error event → message, not cached', (tester) async {
    final adapter = FakeNextxAdapter({'GET /api/dashboard/home-summary': {'stats': {}}}, sseFor: {
      'POST /api/ai/chat': _sse([
        {'type': 'error', 'error_code': 'AI_RATE_LIMITED', 'message': 'slow down'},
      ]),
    });
    final home = await _pump(tester, _ai, adapter: adapter);
    await _tapIsaac(tester);
    await _settle(tester);
    expect(find.textContaining('ส่งคำขอถี่เกินไป'), findsOneWidget);
    expect(IsaacBriefCache.peek(home.config.businessScope), isNull);
    await _dispose(tester);
  });

  testWidgets('open card: large text, dark mode, small phone and tablet — no overflow', (tester) async {
    for (final (size, scale, dark) in const [(Size(360, 2400), 1.35, true), (Size(1180, 1800), 1.0, false)]) {
      await _pump(tester, _ai, size: size, textScale: scale, dark: dark);
      await _tapIsaac(tester);
      await _settle(tester);
      expect(_key('home-isaac-items'), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
      await _dispose(tester);
    }
  });

  testWidgets('the card alone: very large text on a narrow phone, dark — open with a summary, no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    IsaacBriefCache.clearMemory();
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(_s(_ai));
    final scope = config.businessScope;
    final now = thaiNow();
    await tester.runAsync(() => IsaacBriefCache.write(
          scope,
          IsaacBrief(day: isaacDayKey(now), at: now, items: const [
            IsaacBriefItem('ลงเวลาเข้างานก่อนเริ่มงานให้เรียบร้อย แล้วค่อยเปิดดูงานที่ครบกำหนดวันนี้', route: '/hr/attendance'),
            IsaacBriefItem('เตรียมเอกสารสำหรับพบลูกค้า'),
          ]),
        ));
    IsaacBriefCache.setExpanded(scope, true);
    for (final dark in [true, false]) {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 1600), textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: IsaacBriefCard(suggestion: 'ยังไม่ได้ลงเวลาเข้างาน', facts: () => const []),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_key('home-isaac-items'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'dark=$dark');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
