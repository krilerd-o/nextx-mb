import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/menu_access.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_layout_editor.dart';
import 'package:nextx_mobile/screens/dashboard/home_widgets.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/screens/onboarding/tab_setup_screen.dart';

import 'support/fake_api.dart';

SessionState _s(List<String> keys, {bool superadmin = false}) => SessionState(
      accessToken: 't',
      userId: '7',
      businessId: '1',
      menusLoaded: true,
      menuKeys: keys,
      isSuperadmin: superadmin,
    );

const _hrOnly = ['attendance', 'leave-request'];
const _salesOnly = ['lead', 'deal', 'quotation'];

Finder _key(String k) => find.byKey(ValueKey(k));

/// The "n/4" badge next to แท็บที่แสดง.
String _count() => (find.descendant(of: _key('tab-count'), matching: find.byType(Text)).evaluate().single.widget as Text).data!;

/// Tap one option of the NxSlidingSegmented wrapped in [filterKey].
Future<void> _filter(WidgetTester tester, String filterKey, String label) async {
  await tester.tap(find.descendant(of: _key(filterKey), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Set<String> _keysWithPrefix(String prefix) => {
      for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix)).evaluate())
        (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
    };

Future<AppConfig> _pumpTabs(WidgetTester tester, SessionState session, {List<String> roles = const ['sales'], bool fromSettings = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(session);
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
  await tester.pumpWidget(const SizedBox()); // fresh state per call
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(home: TabSetupScreen(initial: ShellTabsConfig(roles: roles), fromSettings: fromSettings)),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return config;
}

Future<AppConfig> _homeConfig(WidgetTester tester, SessionState session, {Size size = const Size(430, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  HomeChartCache.instance.clear();
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  config.debugOverrideSession(session);
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({'GET /api/dashboard/home-summary': {'stats': {}}}));
  await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
  return config;
}

Future<void> _pumpEditor(WidgetTester tester, AppConfig config) async {
  await tester.pumpWidget(const SizedBox()); // fresh state (and no open sheet) per call
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: HomeLayoutEditorScreen())));
  await tester.pumpAndSettle();
}

Future<void> _openGallery(WidgetTester tester) async {
  await tester.scrollUntilVisible(_key('home-editor-add'), 300, scrollable: find.byType(Scrollable).first);
  await tester.tap(_key('home-editor-add'));
  await tester.pumpAndSettle();
  expect(_key('widget-gallery'), findsOneWidget);
}

void main() {
  group('ปรับแต่งเมนูล่าง', () {
    testWidgets('capsules list only allowed tabs, no filter on this page', (tester) async {
      await _pumpTabs(tester, _s(['lead', 'calendar']));
      // Suggested for sales within permissions: dashboard, leads, calendar.
      expect(_keysWithPrefix('tab-chosen-'), {'dashboard', 'leads', 'calendar'});
      expect(_keysWithPrefix('tab-option-'), {'dashboard', 'leads', 'crm', 'calendar', 'search', 'notifications'}); // crm: lead is a CRM menu
      expect(_count(), '3/4');
      expect(find.byKey(const ValueKey('tab-filter')), findsNothing);
    });

    testWidgets('add / remove from the list; full → inline note, add disabled, no SnackBar', (tester) async {
      await _pumpTabs(tester, _s(['lead', 'calendar']));
      await tester.tap(_key('tab-toggle-search'));
      await tester.pumpAndSettle();
      expect(_key('tab-chosen-search'), findsOneWidget);
      expect(_count(), '4/4');
      expect(_key('tab-full-note'), findsOneWidget);

      // Full: tapping another tab's add does nothing and shows no SnackBar.
      await tester.tap(_key('tab-toggle-notifications'));
      await tester.pumpAndSettle();
      expect(_key('tab-chosen-notifications'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      // ✓ on an added tab removes it → room again.
      await tester.tap(_key('tab-toggle-leads'));
      await tester.pumpAndSettle();
      expect(_key('tab-chosen-leads'), findsNothing);
      expect(_key('tab-full-note'), findsNothing);
      expect(_count(), '3/4');

      // The ⊖ on a chosen row removes too.
      await tester.tap(_key('tab-remove-dashboard'));
      await tester.pumpAndSettle();
      expect(_keysWithPrefix('tab-chosen-'), {'calendar', 'search'});
    });

    testWidgets('descriptions of the chosen tabs are one line; "เพิ่มแท็บ" shows capsules', (tester) async {
      await _pumpTabs(tester, _s(['lead', 'calendar']));
      // Not-added tabs are capsules (icon + label), no description line.
      expect(find.descendant(of: _key('tab-option-search'), matching: find.text('ค้นหา')), findsOneWidget);
      expect(find.descendant(of: _key('tab-option-search'), matching: find.text('ค้นหาทุกโมดูล')), findsNothing);
      for (final d in shellTabCatalog.where((d) => ['dashboard', 'leads', 'calendar'].contains(d.id))) {
        final texts = tester.widgetList<Text>(find.text(d.description)).toList();
        expect(texts, isNotEmpty, reason: d.id);
        for (final t in texts) {
          expect(t.maxLines, 1, reason: d.id);
          expect(t.overflow, TextOverflow.ellipsis);
        }
      }
    });

    testWidgets('drag the grip to reorder, then save', (tester) async {
      final config = await _pumpTabs(tester, _s(['lead', 'calendar']));
      final rowH = tester.getSize(_key('tab-chosen-dashboard')).height;
      final g = await tester.startGesture(tester.getCenter(_key('tab-grip-dashboard')));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, rowH * 2.4 / 10));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มใช้งาน'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(config.shellTabs, ['leads', 'calendar', 'dashboard']);
    });

    testWidgets('tabs follow permissions: HR only, sales only, superadmin', (tester) async {
      await _pumpTabs(tester, _s([..._hrOnly]), roles: ['hr']);
      var opts = _keysWithPrefix('tab-option-');
      expect(opts, containsAll(['hr', 'dashboard', 'search', 'notifications']));
      expect(opts, isNot(contains('leads')));
      expect(opts, isNot(contains('approvals')), reason: 'approvals needs quotation / leave-management / pending-approvals');
      expect(opts, isNot(contains('calendar')));
      expect(_keysWithPrefix('tab-chosen-'), isNot(contains('approvals')));

      await _pumpTabs(tester, _s([..._salesOnly]), roles: ['sales']);
      opts = _keysWithPrefix('tab-option-');
      expect(opts, containsAll(['leads', 'quotation', 'crm', 'approvals']));
      expect(opts, isNot(contains('hr')));
      expect(opts, isNot(contains('jobs')));

      await _pumpTabs(tester, _s(const [], superadmin: true), roles: ['sales']);
      expect(_keysWithPrefix('tab-option-'), {for (final d in shellTabCatalog) d.id});
    });

    testWidgets('a saved tab without permission is dropped and does not count toward 4', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final config = AppConfig();
      config.debugOverrideSession(_s([..._hrOnly]));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: TabSetupScreen(initial: ShellTabsConfig(roles: ['hr'], tabs: ['hr', 'leads', 'quotation', 'dashboard']))),
      ));
      await tester.pump();
      expect(_keysWithPrefix('tab-chosen-'), {'hr', 'dashboard'});
      expect(_count(), '2/4');
      expect(_key('tab-full-note'), findsNothing);
    });

    testWidgets('fromSettings keeps ค่าแนะนำ and a sticky save', (tester) async {
      await _pumpTabs(tester, _s(['lead', 'calendar']), fromSettings: true);
      expect(find.text('ค่าแนะนำ'), findsOneWidget);
      expect(find.text('บันทึก'), findsOneWidget);
      await tester.tap(_key('tab-remove-dashboard'));
      await tester.pump();
      await tester.tap(find.text('ค่าแนะนำ'));
      await tester.pump();
      expect(_keysWithPrefix('tab-chosen-'), {'dashboard', 'leads', 'calendar'});
    });
  });

  group('ปรับแต่งหน้าหลัก', () {
    testWidgets('rows: one-line summary, ⋮ moves, grip drag reorders', (tester) async {
      final config = await _homeConfig(tester, _s(['deal', 'lead', 'case', 'workspace', 'calendar']));
      await _pumpEditor(tester, config);
      final summaries = find.byWidgetPredicate((w) => w is Text && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('editor-summary-'));
      expect(summaries, findsWidgets);
      for (final t in tester.widgetList<Text>(summaries)) {
        expect(t.maxLines, 1);
        expect(t.overflow, TextOverflow.ellipsis);
      }

      double y(String id) => tester.getTopLeft(_key('editor-$id')).dy;
      // The first two rows (today, work for this user).
      final order = [for (final e in HomeLayout.instance.entries) if (homeWidgetAllowed(config.session, e.id)) e.id];
      final a = order[0], b = order[1];
      expect(y(a), lessThan(y(b)));
      await tester.tap(_key('editor-menu-$a'));
      await tester.pumpAndSettle();
      expect(_key('editor-menu-_MoveAction.up-$a'), findsOneWidget);
      await tester.tap(find.text('ย้ายลง'));
      await tester.pumpAndSettle();
      expect(y(a), greaterThan(y(b)), reason: '⋮ → ย้ายลง');

      // Drag b's grip back below a.
      final rowH = tester.getSize(_key('editor-$b')).height;
      final g = await tester.startGesture(tester.getCenter(_key('editor-grip-$b')));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, rowH * 1.4 / 10));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(y(a), lessThan(y(b)), reason: 'drag reorder');
    });

    testWidgets('lists only allowed widgets; hidden ones stay in the saved layout', (tester) async {
      final config = await _homeConfig(tester, _s(['lead']));
      await _pumpEditor(tester, config);
      final listed = _keysWithPrefix('editor-remove-');
      expect(listed, containsAll(['birthdays', 'stats', 'recent']));
      expect(listed, isNot(contains('today')));
      expect(listed, isNot(contains('chart_won')));
      expect(listed, isNot(contains('work')));
      expect(find.textContaining('ไม่มีสิทธิ์'), findsNothing);

      await tester.tap(_key('home-editor-save'));
      await tester.pumpAndSettle();
      final ids = HomeLayout.instance.entries.map((e) => e.id).toList();
      expect(ids, containsAll(['today', 'work', 'chart_won']), reason: 'come back when the permission does');
      expect(ids.indexOf('today'), lessThan(ids.indexOf('recent')), reason: 'kept in place');
    });
  });

  group('เพิ่มวิดเจ็ต', () {
    testWidgets('filters ทั้งหมด | ยังไม่เพิ่ม | เพิ่มแล้ว; one-line hints', (tester) async {
      final config = await _homeConfig(tester, _s(['deal', 'lead']), size: const Size(430, 8000));
      await _pumpEditor(tester, config);
      await _openGallery(tester);
      final all = _keysWithPrefix('gallery-hint-');
      expect(all, containsAll(['chart_won', 'chart_lead_source']));
      for (final t in tester.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && '${w.key}'.contains('gallery-hint-')))) {
        expect(t.maxLines, 1);
      }

      await _filter(tester, 'gallery-filter', 'ยังไม่เพิ่ม');
      expect(_keysWithPrefix('gallery-added-'), isEmpty);
      expect(_keysWithPrefix('gallery-add-'), contains('chart_lead_source'));
      expect(_keysWithPrefix('gallery-hint-'), isNot(contains('chart_won')));

      await _filter(tester, 'gallery-filter', 'เพิ่มแล้ว');
      expect(_keysWithPrefix('gallery-add-'), isEmpty);
      expect(_keysWithPrefix('gallery-added-'), contains('chart_won'));
      expect(_keysWithPrefix('gallery-hint-'), isNot(contains('chart_lead_source')));
      // Category headers still group the list.
      expect(find.text('ขาย'), findsOneWidget);
    });

    testWidgets('gallery follows permissions: HR only vs sales only vs superadmin', (tester) async {
      var config = await _homeConfig(tester, _s([..._hrOnly]), size: const Size(430, 8000));
      await _pumpEditor(tester, config);
      await _openGallery(tester);
      var ids = _keysWithPrefix('gallery-hint-');
      expect(ids, containsAll(['chart_leave', 'today', 'quick', 'recent']));
      expect(ids, isNot(contains('chart_won')));
      expect(ids, isNot(contains('sales')));
      expect(ids, isNot(contains('birthdays')));
      expect(ids, isNot(contains('work')));

      config = await _homeConfig(tester, _s([..._salesOnly]), size: const Size(430, 8000));
      await _pumpEditor(tester, config);
      await _openGallery(tester);
      ids = _keysWithPrefix('gallery-hint-');
      expect(ids, containsAll(['chart_won', 'chart_quote', 'chart_lead_source', 'sales', 'birthdays', 'stats']));
      expect(ids, isNot(contains('chart_leave')));
      expect(ids, isNot(contains('today')));
      expect(ids, isNot(contains('ai')));

      config = await _homeConfig(tester, _s(const [], superadmin: true), size: const Size(430, 8000));
      expect([...HomeLayout.charts.map((c) => c.id), ...HomeLayout.defaultOrder].every((id) => homeWidgetAllowed(config.session, id)), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('Home follows permissions', () {
    Future<Set<String>> editIds(WidgetTester tester, SessionState s) async {
      final config = await _homeConfig(tester, s, size: const Size(430, 4000));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen())),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.ensureVisible(_key('home-arrange'));
      await tester.pump();
      await tester.tap(_key('home-arrange'));
      await tester.pump(const Duration(milliseconds: 400));
      final ids = _keysWithPrefix('home-hide-');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      return ids;
    }

    testWidgets('HR only vs sales only show different widgets', (tester) async {
      final hr = await editIds(tester, _s([..._hrOnly]));
      expect(hr, containsAll(['today', 'quick', 'recent']));
      expect(hr, isNot(contains('chart_won')));
      expect(hr, isNot(contains('sales')));
      expect(hr, isNot(contains('work')));
      expect(hr, isNot(contains('chart_work')));

      final sales = await editIds(tester, _s([..._salesOnly]));
      expect(sales, containsAll(['chart_won', 'chart_winrate', 'sales', 'stats', 'birthdays']));
      expect(sales, isNot(contains('today')));
      expect(sales, isNot(contains('work')));
      expect(sales, isNot(contains('ai')));
      expect(hr, isNot(equals(sales)));
    });
  });

  test('quick shortcut keys cover the รออนุมัติ menus', () {
    expect(kHomeQuickMenuKeys, containsAll([MenuAccess.quotation, MenuAccess.leaveManagement, MenuAccess.pendingApprovals]));
  });

  testWidgets('page opened before the menus arrive fills in when they do (cold start)', (tester) async {
    final config = await _pumpTabs(tester, const SessionState(accessToken: 't', userId: '1', businessId: '1'));
    // Menus not loaded yet: only the always-on tabs.
    expect(find.byKey(const ValueKey('tab-option-leads')), findsNothing);
    // Menus arrive: no Package / no role limit = unrestricted (same as the web).
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('tab-option-leads')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-chosen-leads')), findsOneWidget); // sales role suggests ลีด/ดีล
  });
}
