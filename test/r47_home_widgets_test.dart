import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_charts.dart';
import 'package:nextx_mobile/screens/dashboard/home_edit_mode.dart';
import 'package:nextx_mobile/screens/dashboard/home_layout_editor.dart';
import 'package:nextx_mobile/screens/dashboard/home_widgets.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';

import 'support/fake_api.dart';

const _sales = {
  'deal': {
    'byStage': [
      {'name': 'Qualification', 'value': '4', 'amount': '400000'},
      {'name': 'Negotiation', 'value': 2, 'amount': 900000},
      {'name': 'Closed Won', 'value': 3, 'amount': 1200000},
    ],
    'wonCount': '3',
    'wonAmount': '1200000',
    'lostCount': 1,
    'winRate': null,
  },
  'quotation': {
    'byStatus': [
      {'name': 'Sent', 'value': '5'},
      {'name': 'Draft', 'value': '0'},
    ],
  },
  'trend': [
    {'month': '2026-10', 'won_amount': '500000'},
    {'month': '2026-11', 'won_amount': 1200000},
  ],
};

void main() {
  group('layout v2', () {
    test('v1 order/hidden moves over: order kept, hidden left out, charts after เคส', () async {
      SharedPreferences.setMockInitialValues({
        'nx_home_layout_u1': '{"order":["sales","today","cases","quick"],"hidden":["ai"]}',
      });
      final h = HomeLayout.instance;
      await h.load('u1|b1', legacyScope: 'u1', force: true);
      final ids = h.visibleOrder;
      expect(ids.first, 'sales');
      expect(ids.contains('ai'), isFalse);
      expect(h.hidden, {'ai'});
      final iCases = ids.indexOf('cases');
      expect(ids.sublist(iCases + 1, iCases + 1 + HomeLayout.defaultCharts.length), HomeLayout.defaultCharts);
      expect(h.entry('chart_won')!.size, HomeSize.half);
      expect(h.entry('chart_pipeline')!.size, HomeSize.full);
    });

    test('saved per business; unknown ids dropped; full-only charts stay full', () async {
      SharedPreferences.setMockInitialValues({
        'nx_home_layout_v2_u1|b2': jsonEncode({
          'entries': [
            {'id': 'chart_pipeline', 'size': 'half'},
            {'id': 'gone_widget'},
            {'id': 'chart_won', 'size': 'full', 'period': 'quarter', 'team': true},
            {'id': 'today'},
          ],
        }),
      });
      final h = HomeLayout.instance;
      await h.load('u1|b2', force: true);
      expect(h.visibleOrder, ['chart_pipeline', 'chart_won', 'today']);
      expect(h.entry('chart_pipeline')!.size, HomeSize.full);
      expect(h.entry('chart_won'), const HomeEntry('chart_won', size: HomeSize.full, period: 'quarter', team: true));

      await h.saveEntries('u1|b2', [const HomeEntry('chart_leave', size: HomeSize.half), const HomeEntry('today')]);
      await h.load('u1|b3', force: true); // another business → defaults
      expect(h.visibleOrder, HomeLayout.defaultEntries().map((e) => e.id).toList());
      await h.load('u1|b2', force: true);
      expect(h.visibleOrder, ['chart_leave', 'today']);
    });
  });

  group('ranges + parsers', () {
    test('periods in Thai days, previous period for ▲▼', () {
      final now = DateTime(2026, 11, 10);
      expect(chartRange('month', now).toString(), '2026-11-01..2026-11-30');
      expect(previousRange('month', now).toString(), '2026-10-01..2026-10-31');
      expect(chartRange('week', now).toString(), '2026-11-09..2026-11-15');
      expect(chartRange('m6', now).toString(), '2026-06-01..2026-11-30');
      expect(chartRange('d30', now).toString(), '2026-10-12..2026-11-10');
      expect(previousRange('quarter', now).toString(), '2026-07-01..2026-09-30');
      expect(previousRange('year', now).toString(), '2025-01-01..2025-12-31');
    });

    test('string counts become numbers; closed stages out of the pipeline; zero slices dropped', () {
      final stages = parsePipeline(_sales);
      expect(stages.map((s) => s.label), ['Qualification', 'Negotiation']);
      expect(stages.first.value, 4);
      expect(stages.first.amount, 400000);
      final rate = parseWinRate(_sales);
      expect(rate.rate, closeTo(0.75, 1e-9));
      expect(parseSlices((_sales['quotation']! as Map)['byStatus']).map((s) => '$s'), ['Sent=5.0']);
      final won = parseWon(_sales, {'deal': {'wonAmount': '1000000'}});
      expect(won.amount, 1200000);
      expect(won.deltaPct, closeTo(20, 1e-9));
      expect(parseSalesTrend(_sales).labels, ['ต.ค.', 'พ.ย.']);
      expect(parseSla({'counts': {'met': '9', 'missed': '1'}, 'compliance_pct': null}).rate, closeTo(0.9, 1e-9));
      expect(parseLeadConversion({'lead': {'kpis': {'created': 6, 'converted': 2, 'conversion_rate': 0.333}}}).rate, 0.333);
      final act = parseActivityTrend({
        'trend': [
          {'key': '2026-11-07', 'counts': {'done': '1', 'missed': 2, 'upcoming': 0}},
        ],
      });
      expect(act.labels, ['7/11']);
      expect(act.series['พลาด'], [2]);
      expect(parseLeave([
        {'leave_type_name': 'ลาป่วย', 'total_days': '30.00', 'used_days': 4},
        {'leave_type_name': 'ไม่มีสิทธิ์', 'total_days': '0'},
      ]).single.left, 26);
      final many = parseSlices([for (var i = 0; i < 8; i++) {'name': 'S$i', 'value': 8 - i}]);
      expect(many.length, 5);
      expect(many.last.label, 'อื่นๆ');
    });
  });

  group('loading', () {
    Future<(AppConfig, FakeNextxAdapter)> setup(WidgetTester tester, {String? role}) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HomeChartCache.instance.clear();
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      config.debugOverrideSession(SessionState(
          accessToken: 't',
          userId: '7',
          businessId: '1',
          menusLoaded: true,
          businessRole: role,
          menuKeys: const ['deal', 'quotation', 'lead', 'case', 'workspace'],
        ));
      final adapter = FakeNextxAdapter({
        'GET /api/dashboard/sales': _sales,
        'GET /api/home/work': {
          'work_weeks': [
            {'week': '2026-11-02', 'created': '2', 'cleared': 1},
          ],
        },
      });
      config.apiClient.debugSetHttpAdapter(adapter);
      return (config, adapter);
    }

    ChartRequest req(AppConfig c, HomeEntry e) =>
        ChartRequest(api: c.apiClient, session: c.session, entry: e, scope: 's', now: DateTime(2026, 11, 10));

    testWidgets('ของฉัน sends userId = me, ทีม (admin) sends none; one request shared by widgets; cache reused', (tester) async {
      final (config, adapter) = await setup(tester, role: 'admin');
      await tester.runAsync(() async {
        await Future.wait([
          loadChartData(req(config, const HomeEntry('chart_winrate'))),
          loadChartData(req(config, const HomeEntry('chart_quote'))),
        ]);
      });
      final mine = adapter.calls.where((c) => c.path == '/api/dashboard/sales').toList();
      expect(mine.length, 1, reason: 'win rate + quotation share one month request');
      expect(mine.single.queryParameters['userId'], '7');
      expect(mine.single.queryParameters['dateFrom'], '2026-11-01');
      expect(mine.single.queryParameters['dateTo'], '2026-11-30');

      await tester.runAsync(() => loadChartData(req(config, const HomeEntry('chart_winrate', team: true))));
      final team = adapter.calls.where((c) => c.path == '/api/dashboard/sales').last;
      expect(team.queryParameters.containsKey('userId'), isFalse);

      final before = adapter.calls.length;
      await tester.runAsync(() => loadChartData(req(config, const HomeEntry('chart_winrate'))));
      expect(adapter.calls.length, before, reason: 'fresh cache → no request');
      await tester.runAsync(() => loadChartData(req(config, const HomeEntry('chart_winrate')), force: true));
      expect(adapter.calls.length, before + 1, reason: 'pull to refresh forces');
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets('member cannot switch to ทีม: still sends userId', (tester) async {
      final (config, adapter) = await setup(tester, role: 'member');
      expect(canSeeTeam(config.session), isFalse);
      await tester.runAsync(() => loadChartData(req(config, const HomeEntry('chart_winrate', team: true))));
      expect(adapter.calls.single.queryParameters['userId'], '7');
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets('work chart asks my insights with days', (tester) async {
      final (config, adapter) = await setup(tester);
      final d = (await tester.runAsync(() => loadChartData(req(config, const HomeEntry('chart_work', period: 'd90')))))! as SeriesData;
      expect(adapter.calls.single.queryParameters, {'scope': 'insights', 'days': '90'});
      expect(d.series['สร้าง'], [2]);
      await tester.pump(const Duration(minutes: 2));
    });
  });

  test('permissions: charts follow menu access', () {
    const s = SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['lead']);
    expect(homeWidgetAllowed(s, 'chart_lead_source'), isTrue);
    expect(homeWidgetAllowed(s, 'chart_won'), isFalse);
    expect(homeWidgetAllowed(s, 'chart_closing'), isFalse);
    expect(homeWidgetAllowed(s, 'chart_leave'), isFalse);
    expect(homeWidgetAllowed(s, 'today'), isTrue);
  });

  group('edit mode grid', () {
    Future<_HarnessState> pumpGrid(WidgetTester tester, List<HomeEntry> entries) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: _Harness(key: key, entries: entries)))));
      return key.currentState!;
    }

    final three = [
      const HomeEntry('chart_a_alpha'),
      const HomeEntry('chart_b_beta'),
      const HomeEntry('chart_c_gamma'),
    ];

    testWidgets('long-press enters edit mode; ⊖ hides; drag A onto C reorders', (tester) async {
      final h = await pumpGrid(tester, three);
      expect(find.byKey(const ValueKey('home-hide-chart_a_alpha')), findsNothing);
      await tester.longPress(find.text('Box chart_b_beta'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.editing, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('home-hide-chart_a_alpha')), findsOneWidget);

      final from = tester.getCenter(find.text('Box chart_a_alpha'));
      final to = tester.getCenter(find.text('Box chart_c_gamma'));
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 450));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.ids.last, 'chart_a_alpha');

      await tester.tap(find.byKey(const ValueKey('home-hide-chart_b_beta')));
      await tester.pump();
      expect(h.ids, isNot(contains('chart_b_beta')));
    });

    testWidgets('½ / full toggle shows only for resizable charts and packs halves into one row', (tester) async {
      final h = await pumpGrid(tester, [
        const HomeEntry('chart_won', size: HomeSize.half),
        const HomeEntry('chart_winrate', size: HomeSize.half),
        const HomeEntry('chart_pipeline'),
      ]);
      h.setEditing(true);
      await tester.pump();
      expect(find.byKey(const ValueKey('home-size-chart_won')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-size-chart_pipeline')), findsNothing);
      final a = tester.getTopLeft(find.byKey(const ValueKey('home-drag-chart_won')));
      final b = tester.getTopLeft(find.byKey(const ValueKey('home-drag-chart_winrate')));
      expect(a.dy, b.dy, reason: 'two halves share a row');
      await tester.tap(find.byKey(const ValueKey('home-size-chart_won')));
      await tester.pump();
      expect(h.entries.first.size, HomeSize.full);
      expect(tester.getTopLeft(find.byKey(const ValueKey('home-drag-chart_won'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('home-drag-chart_winrate'))).dy));
    });
  });

  testWidgets('chart card: sample renders all 13 charts light + dark without errors', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['deal']));
    for (final dark in [false, true]) {
      for (final c in HomeLayout.charts) {
        for (final size in c.resizable ? HomeSize.values : [c.defaultSize]) {
          await tester.pumpWidget(ChangeNotifierProvider.value(
            value: config,
            child: MaterialApp(
              theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: size == HomeSize.half ? 190 : 388,
                    child: HomeChartCard(entry: HomeEntry(c.id, size: size), sample: sampleChartData(c.id)),
                  ),
                ),
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 900));
          expect(tester.takeException(), isNull, reason: '${c.id} ${size.name} dark=$dark');
        }
      }
    }
  });

  testWidgets('settings editor: remove + add from gallery + save → Home layout changes', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['deal', 'lead']));
    await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: HomeLayoutEditorScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-chart_won')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-remove-chart_won')));
    await tester.pump();
    expect(find.byKey(const ValueKey('editor-chart_won')), findsNothing);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('home-editor-add')), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('home-editor-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('widget-gallery')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('gallery-add-chart_lead_source')), 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('widget-gallery')), matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const ValueKey('gallery-add-chart_lead_source')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-chart_lead_source')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-editor-save')));
    await tester.pumpAndSettle();
    final ids = HomeLayout.instance.visibleOrder;
    expect(ids, isNot(contains('chart_won')));
    expect(ids.last, 'chart_lead_source');
    final saved = (await tester.runAsync(SharedPreferences.getInstance))!.getString('nx_home_layout_v2_${config.businessScope}');
    expect(saved, contains('chart_lead_source'));
  });

  testWidgets('Home: long-press → edit mode (wiggle, ⊖); เสร็จ saves; ยกเลิก restores', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HomeChartCache.instance.clear();
    resetHomeChartMemory();
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['deal']));
    await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({
      'GET /api/dashboard/sales': _sales,
      'GET /api/dashboard/home-summary': {'stats': {}},
    }));
    await pumpHome(tester, config);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('home-chart-chart_winrate')), findsOneWidget);
    expect(find.text('75%'), findsOneWidget, reason: 'win rate from string counts 3 won / 1 lost');

    await tester.longPress(find.byKey(const ValueKey('home-chart-chart_winrate')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-edit-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hide-chart_winrate')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-hide-chart_winrate')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('home-chart-chart_winrate')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-edit-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-chart-chart_winrate')), findsOneWidget, reason: 'ยกเลิก = back to before');
    expect(HomeLayout.instance.entry('chart_winrate'), isNotNull);

    await tester.longPress(find.byKey(const ValueKey('home-chart-chart_winrate')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('home-size-chart_winrate')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('home-hide-chart_won')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('home-edit-done')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-hide-chart_winrate')), findsNothing, reason: 'left edit mode');
    expect(HomeLayout.instance.entry('chart_won'), isNull);
    expect(HomeLayout.instance.entry('chart_winrate')!.size, HomeSize.full);
    final saved = (await tester.runAsync(SharedPreferences.getInstance))!.getString('nx_home_layout_v2_${config.businessScope}')!;
    expect(saved, isNot(contains('chart_won"')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}

/// Minimal Home: owns entries + editing like the dashboard does.
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.entries});
  final List<HomeEntry> entries;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with SingleTickerProviderStateMixin {
  late List<HomeEntry> entries = List.of(widget.entries);
  bool editing = false;
  late final AnimationController wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  List<String> get ids => [for (final e in entries) e.id];
  void setEditing(bool v) => setState(() => editing = v);

  @override
  void dispose() {
    wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeWidgetGrid(
        entries: entries,
        editing: editing,
        wiggle: wiggle,
        onStartEditing: () => setState(() => editing = true),
        onMove: (id, before) => setState(() {
          final from = entries.indexWhere((e) => e.id == id);
          final to = entries.indexWhere((e) => e.id == before);
          final e = entries.removeAt(from);
          entries.insert(to, e);
        }),
        onHide: (id) => setState(() => entries.removeWhere((e) => e.id == id)),
        onResize: (id) => setState(() => entries = [
              for (final e in entries) e.id == id ? e.copyWith(size: e.size == HomeSize.half ? HomeSize.full : HomeSize.half) : e,
            ]),
        build: (e) => SizedBox(height: 120, child: Center(child: Text('Box ${e.id}'))),
      );
}

/// Real Home screen: long-press a widget → edit mode → ⊖ + เสร็จ saves.
Future<void> pumpHome(WidgetTester tester, AppConfig config) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen())),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}
