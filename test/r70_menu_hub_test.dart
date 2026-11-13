import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/i18n_en.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/menu_groups.dart';
import 'package:nextx_mobile/core/menu_hub_prefs.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/module/menu_group_screen.dart';
import 'package:nextx_mobile/screens/module/module_hub_screen.dart';

SessionState _s(List<String> keys, {String biz = '1'}) =>
    SessionState(accessToken: 't', userId: '2', businessId: biz, menusLoaded: true, menuKeys: keys, businessRole: 'member');

late AppConfig _config;

Future<void> _pump(
  WidgetTester tester,
  List<String> keys, {
  Map<String, Object> prefs = const {},
  Size size = const Size(400, 900),
  bool resetPrefs = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (resetPrefs) SharedPreferences.setMockInitialValues(prefs);
  _config = AppConfig()..debugOverrideSession(_s(keys));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ModuleHubScreen())),
    GoRoute(path: '/menu/:group', builder: (_, st) => MenuGroupScreen(groupId: st.pathParameters['group']!)),
    GoRoute(path: '/crm/:m', builder: (_, st) => Scaffold(body: Text('crm:${st.pathParameters['m']}'))),
    GoRoute(path: '/fsm/:m', builder: (_, st) => Scaffold(body: Text('fsm:${st.pathParameters['m']}'))),
  ]);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: _config, child: MaterialApp.router(routerConfig: router)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

/// Ids of the group cards from top-left to bottom-right.
List<String> _cardOrder(WidgetTester tester) {
  final ids = <(String, Offset)>[
    for (final id in defaultMenuOrder)
      if (find.byKey(ValueKey('menu-group-$id')).evaluate().isNotEmpty) (id, tester.getTopLeft(find.byKey(ValueKey('menu-group-$id')))),
  ];
  ids.sort((a, b) => a.$2.dy != b.$2.dy ? a.$2.dy.compareTo(b.$2.dy) : a.$2.dx.compareTo(b.$2.dx));
  return [for (final e in ids) e.$1];
}

Future<void> _longPressDrag(WidgetTester tester, Finder from, Offset to) async {
  final g = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 700)); // long-press starts the drag
  final start = tester.getCenter(from);
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(Offset.lerp(start, to, i / 10)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => L10n.set('th'));

  group('search from the header icon', () {
    testWidgets('icon reveals a focused field; typing filters; clear and close', (tester) async {
      await _pump(tester, ['case', 'deal', 'lead']);
      expect(find.byKey(const ValueKey('menu-search')), findsNothing);
      expect(find.byKey(const ValueKey('menu-group-sales')), findsOneWidget);

      await tester.tap(find.byTooltip('ค้นหาเมนู'));
      await tester.pump();
      await tester.pump();
      final field = find.byKey(const ValueKey('menu-search'));
      expect(field, findsOneWidget);
      final editable = tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);

      await tester.enterText(field, 'ดีล');
      await tester.pump();
      expect(find.byKey(const ValueKey('menu-group-sales')), findsNothing); // results, not cards
      expect(find.byKey(const ValueKey('menu-item-deal')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-item-case')), findsNothing);

      // Clear keeps the box open; the cards come back.
      await tester.tap(find.byKey(const ValueKey('menu-search-clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('menu-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-group-sales')), findsOneWidget);

      // Close hides it.
      await tester.tap(find.byKey(const ValueKey('menu-search-close')));
      await tester.pump();
      expect(find.byKey(const ValueKey('menu-search')), findsNothing);
    });

    testWidgets('a hit opens the menu; no hit says so', (tester) async {
      await _pump(tester, ['case', 'deal']);
      await tester.tap(find.byTooltip('ค้นหาเมนู'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('menu-search')), 'zzzz');
      await tester.pump();
      expect(find.text('ไม่พบเมนู'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('menu-search')), 'เคส');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('menu-item-case')));
      await tester.pumpAndSettle();
      expect(find.text('crm:case'), findsOneWidget);
    });
  });

  group('view switch', () {
    testWidgets('header icon switches to the list view and it is remembered per user', (tester) async {
      await _pump(tester, ['lead', 'deal']);
      expect(find.byKey(const ValueKey('menu-group-customers')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-list-group-customers')), findsNothing);

      await tester.tap(find.byTooltip('มุมมองรายการ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-list-group-customers')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-group-customers')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MenuHubPrefs.viewKey(_config.prefsScope)), 'list');

      // Opening the page again (same user) starts in the list view.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, ['lead', 'deal'], resetPrefs: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-list-group-customers')), findsOneWidget);

      // ⋮ → มุมมองกลุ่ม goes back.
      await tester.tap(find.byTooltip('เพิ่มเติม'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-view-groups')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-group-customers')), findsOneWidget);
      expect(prefs.getString(MenuHubPrefs.viewKey(_config.prefsScope)), 'groups');
    });

    testWidgets('another user keeps their own view', (tester) async {
      await _pump(tester, ['lead'], prefs: {MenuHubPrefs.viewKey('someone_else'): 'list'});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-group-customers')), findsOneWidget);
    });
  });

  group('list view', () {
    testWidgets('rows grouped per menu group, only menus the user may open', (tester) async {
      await _pump(tester, ['lead', 'deal', 'quotation']);
      await tester.tap(find.byTooltip('มุมมองรายการ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-list-group-customers')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-list-group-sales')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-list-group-service')), findsNothing);
      expect(find.byKey(const ValueKey('menu-list-group-general')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-row-lead')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-row-account')), findsNothing); // no permission
      expect(find.byKey(const ValueKey('menu-row-deal')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-row-quotation')), findsOneWidget);
      // ลูกค้า rows sit inside the ลูกค้า section.
      expect(
        find.descendant(of: find.byKey(const ValueKey('menu-list-group-customers')), matching: find.byKey(const ValueKey('menu-row-lead'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('menu-list-group-customers')), matching: find.byKey(const ValueKey('menu-row-deal'))),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('menu-row-deal')));
      await tester.pumpAndSettle();
      expect(find.text('crm:deal'), findsOneWidget);
    });

    testWidgets('every visible menu of every group has a row (same rules as the grid)', (tester) async {
      final s = _s(['workspace', 'calendar', 'lead', 'account', 'deal', 'case', 'job', 'mailbox', 'community-chat', 'product', 'mini-store-stock']);
      final groups = visibleMenuGroups(s, isaac: const IsaacAccess(aiChat: true));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MenuHubListView(groups: groups)))));
      for (final g in groups) {
        expect(find.byKey(ValueKey('menu-list-group-${g.def.id}')), findsOneWidget, reason: g.def.id);
        for (final it in g.items) {
          expect(find.byKey(ValueKey('menu-row-${it.id}')), findsOneWidget, reason: it.id);
        }
      }
      expect(find.byKey(const ValueKey('menu-row-store')), findsNothing); // stock alone needs an admin
      expect(find.byKey(const ValueKey('menu-list-group-ai')), findsOneWidget);
    });

    testWidgets('list view follows the saved group order', (tester) async {
      final s = _s(['lead', 'deal', 'case']);
      final groups = orderMenuGroups(visibleMenuGroups(s), ['service', 'sales', 'customers']);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MenuHubListView(groups: groups)))));
      final y = [for (final id in ['service', 'sales', 'customers']) tester.getTopLeft(find.byKey(ValueKey('menu-list-group-$id'))).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
    });

    testWidgets('dark theme renders', (tester) async {
      final groups = visibleMenuGroups(_s(['lead', 'deal']));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SingleChildScrollView(child: MenuHubListView(groups: groups))),
      ));
      expect(find.byKey(const ValueKey('menu-row-lead')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('group order', () {
    test('normalize keeps known ids, drops unknown / duplicates, adds new groups at their default place', () {
      expect(normalizeMenuOrder(null), defaultMenuOrder);
      expect(normalizeMenuOrder(['sales', 'x', 'sales', 'work']).first, 'sales');
      expect(normalizeMenuOrder([...defaultMenuOrder.reversed, 'x']), defaultMenuOrder.reversed.toList());
      expect(normalizeMenuOrder(['sales', 'work']).toSet(), defaultMenuOrder.toSet());
      expect(normalizeMenuOrder(['sales', 'work']).length, defaultMenuOrder.length);
    });

    test('rearranging visible groups keeps hidden ones in their slots', () {
      final next = applyVisibleMenuOrder(defaultMenuOrder, ['service', 'customers', 'sales']);
      expect(next, ['work', 'service', 'customers', 'sales', 'comms', 'ai', 'apps']);
      expect(isDefaultMenuOrder(next), isFalse);
      expect(isDefaultMenuOrder(defaultMenuOrder), isTrue);
    });

    testWidgets('long-press + drag moves a card; order is saved per user + business; reset', (tester) async {
      await _pump(tester, ['lead', 'deal', 'case']);
      expect(_cardOrder(tester), ['customers', 'sales', 'service']);

      await _longPressDrag(tester, find.byKey(const ValueKey('menu-group-service')), tester.getCenter(find.byKey(const ValueKey('menu-group-customers'))));
      expect(_cardOrder(tester), ['service', 'customers', 'sales']);

      final prefs = await SharedPreferences.getInstance();
      final key = MenuHubPrefs.orderKey(_config.businessScope);
      expect(_config.businessScope, contains('|b1'));
      expect(jsonDecode(prefs.getString(key)!), ['work', 'service', 'customers', 'sales', 'comms', 'ai', 'apps']);

      // Back to the page: the order is kept.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, ['lead', 'deal', 'case'], resetPrefs: false);
      await tester.pumpAndSettle();
      expect(_cardOrder(tester), ['service', 'customers', 'sales']);

      // The list view uses the same order.
      await tester.tap(find.byTooltip('มุมมองรายการ'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('menu-list-group-service'))).dy <
            tester.getTopLeft(find.byKey(const ValueKey('menu-list-group-customers'))).dy,
        isTrue,
      );
      await tester.tap(find.byTooltip('มุมมองกลุ่ม'));
      await tester.pumpAndSettle();

      // ⋮ → รีเซ็ตลำดับ.
      await tester.tap(find.byTooltip('เพิ่มเติม'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-reset-order')));
      await tester.pumpAndSettle();
      expect(_cardOrder(tester), ['customers', 'sales', 'service']);
      expect(prefs.getString(key), isNull);
    });

    testWidgets('tablet: cards in the left pane reorder too; list view stays one centred column', (tester) async {
      await _pump(tester, ['lead', 'deal', 'case'], size: const Size(1200, 900));
      expect(_cardOrder(tester), ['customers', 'sales', 'service']);
      await _longPressDrag(tester, find.byKey(const ValueKey('menu-group-service')), tester.getCenter(find.byKey(const ValueKey('menu-group-customers'))));
      expect(_cardOrder(tester), ['service', 'customers', 'sales']);
      await tester.tap(find.byTooltip('มุมมองรายการ'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('menu-list-group-service'))).width, lessThanOrEqualTo(760));
    });

    testWidgets('small phone: header fits (no overflow)', (tester) async {
      await _pump(tester, ['lead'], size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('ค้นหาเมนู'), findsOneWidget);
      expect(find.byTooltip('มุมมองรายการ'), findsOneWidget);
      expect(find.byTooltip('เพิ่มเติม'), findsOneWidget);
    });

    testWidgets('another business has its own order', (tester) async {
      await _pump(tester, ['lead', 'deal'], prefs: {
        MenuHubPrefs.orderKey('other|b9'): jsonEncode(['sales', 'customers']),
      });
      await tester.pumpAndSettle();
      expect(_cardOrder(tester), ['customers', 'sales']);
    });

    testWidgets('a dragged card near the bottom edge scrolls the page', (tester) async {
      await _pump(
        tester,
        ['workspace', 'lead', 'deal', 'case', 'mailbox', 'product'],
        size: const Size(400, 520),
      );
      final scrollable = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
      final pos = tester.state<ScrollableState>(scrollable).position;
      expect(pos.pixels, 0);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('menu-group-work'))));
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveTo(const Offset(100, 510));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pos.pixels, greaterThan(0));
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group('ISAAC naming', () {
    test('Thai UI says ไอแซคเอไอ / ไอแซค; English keeps ISAAC AI', () {
      final ai = kMenuGroups.firstWhere((g) => g.id == 'ai');
      expect(ai.title, 'ไอแซคเอไอ');
      L10n.set('en');
      expect(tr('ไอแซคเอไอ'), 'ISAAC AI');
      expect(tr('ไอแซค'), 'ISAAC');
      expect(tr('ไอแซคแนะนำ'), 'ISAAC suggests');
      expect(tr('แดชบอร์ดไอแซค'), 'ISAAC insights');
      expect(tr('แดชบอร์ดไอแซค การสื่อสาร'), 'ISAAC communication insights');
      expect(tr('ไอแซคเอไอ การสื่อสาร'), 'ISAAC AI for Communication');
      expect(tr('ถามไอแซค'), 'Ask Isaac');
      L10n.set('th');
      expect(tr('ไอแซคเอไอ'), 'ไอแซคเอไอ');
    });

    test('no Thai i18n key spells ISAAC in Latin letters', () {
      for (final k in [...enStrings.keys, ...enPatterns.keys]) {
        expect(RegExp(r'\b(ISAAC|Isaac)\b').hasMatch(k), isFalse, reason: k);
      }
    });

    test('no Thai UI string in lib/ spells ISAAC in Latin letters', () {
      final thai = RegExp(r'[฀-๿]');
      final latin = RegExp(r'\b(ISAAC|Isaac)\b(?!_)');
      final bad = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('i18n_en.dart')) continue;
        for (final (i, line) in f.readAsLinesSync().indexed) {
          final code = line.contains('//') ? line.substring(0, line.indexOf('//')) : line;
          if (code.trimLeft().isEmpty) continue;
          // A string literal with Thai text and a Latin ISAAC in it.
          for (final m in RegExp(r"'([^'\n]*)'").allMatches(code)) {
            final s = m.group(1)!;
            if (thai.hasMatch(s) && latin.hasMatch(s)) bad.add('${f.path}:${i + 1}: $s');
          }
        }
      }
      expect(bad, isEmpty);
    });

    testWidgets('menu page shows ไอแซคเอไอ in Thai and ISAAC AI in English', (tester) async {
      final groups = visibleMenuGroups(_s(['ai-assistant']), isaac: const IsaacAccess(aiChat: true));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MenuHubListView(groups: groups)))));
      expect(find.text('ไอแซคเอไอ'), findsOneWidget);
      L10n.set('en');
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: Scaffold(body: SingleChildScrollView(child: MenuHubListView(groups: groups)))));
      expect(find.text('ISAAC AI'), findsOneWidget);
      expect(find.text('ไอแซคเอไอ'), findsNothing);
    });
  });
}
