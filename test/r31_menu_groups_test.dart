import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/menu_groups.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/module/menu_group_screen.dart';
import 'package:nextx_mobile/screens/module/module_hub_screen.dart';

SessionState _s(List<String> keys, {bool admin = false}) =>
    SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: keys, businessRole: admin ? 'admin' : 'member');

void main() {
  test('groups follow the web nav rail order; empty groups are hidden', () {
    final g = visibleMenuGroups(_s(['lead', 'deal', 'case', 'mailbox', 'community-chat', 'workspace', 'calendar', 'product']));
    expect(g.map((x) => x.def.id), ['work', 'customers', 'sales', 'service', 'comms', 'apps']);
    final cust = g.firstWhere((x) => x.def.id == 'customers');
    expect(cust.items.map((i) => i.id), ['lead']); // account / contact not allowed
    final comms = g.firstWhere((x) => x.def.id == 'comms');
    expect(comms.sections.map((s) => s.title), ['คุยกับลูกค้า', 'คุยในทีม']);
  });

  test('only lead + deal → only ลูกค้า and งานขาย', () {
    final g = visibleMenuGroups(_s(['lead', 'deal']));
    expect(g.map((x) => x.def.title), ['ลูกค้า', 'งานขาย']);
  });

  test('ISAAC AI comes from IsaacAccess like the web', () {
    expect(visibleMenuGroups(_s(['ai-assistant'])).any((x) => x.def.id == 'ai'), isFalse);
    final g = visibleMenuGroups(_s(['ai-assistant']), isaac: const IsaacAccess(aiChat: true));
    final ai = g.firstWhere((x) => x.def.id == 'ai');
    expect(ai.items.map((i) => i.id), contains('ai-assistant'));
  });

  test('store stock alone needs a business admin', () {
    bool hasStore(SessionState s) => visibleMenuGroups(s).any((g) => g.items.any((i) => i.id == 'store'));
    expect(hasStore(_s(['mini-store-stock'])), isFalse);
    expect(hasStore(_s(['mini-store-stock'], admin: true)), isTrue);
    expect(hasStore(_s(['mini-store-orders'])), isTrue);
  });

  Future<GoRouter> pumpHub(WidgetTester tester, List<String> keys, {Size size = const Size(400, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig()..debugOverrideSession(_s(keys));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ModuleHubScreen())),
      GoRoute(path: '/menu/:group', builder: (_, st) => MenuGroupScreen(groupId: st.pathParameters['group']!)),
      GoRoute(path: '/crm/:m', builder: (_, st) => Scaffold(body: Text('crm:${st.pathParameters['m']}'))),
      GoRoute(path: '/fsm/:m', builder: (_, st) => Scaffold(body: Text('fsm:${st.pathParameters['m']}'))),
      GoRoute(path: '/jobs', builder: (_, _) => const Scaffold(body: Text('jobs'))),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp.router(routerConfig: router)));
    await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  testWidgets('menu page: group cards → group page with web sections → open a menu', (tester) async {
    await pumpHub(tester, ['case', 'job', 'service-contract', 'deal']);
    expect(find.byKey(const ValueKey('menu-group-service')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-group-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-group-customers')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-group-service')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-section-งานบริการ')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-section-สัญญา')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-item-case')));
    await tester.pumpAndSettle();
    expect(find.text('crm:case'), findsOneWidget);
  });

  testWidgets('search finds a menu across groups and opens it', (tester) async {
    await pumpHub(tester, ['case', 'deal']);
    await tester.enterText(find.byKey(const ValueKey('menu-search')), 'ดีล');
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-group-sales')), findsNothing); // results, not cards
    await tester.tap(find.byKey(const ValueKey('menu-item-deal')));
    await tester.pumpAndSettle();
    expect(find.text('crm:deal'), findsOneWidget);
  });

  testWidgets('tablet: groups on the left, chosen group on the right', (tester) async {
    await pumpHub(tester, ['case', 'deal', 'lead'], size: const Size(1200, 900));
    expect(find.byKey(const ValueKey('menu-pane-customers')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-group-service')));
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-pane-service')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-case')), findsOneWidget);
  });

  testWidgets('group cards in the grid all have the same height', (tester) async {
    await pumpHub(tester, ['workspace', 'calendar', 'quotation', 'lead', 'account', 'contact', 'deal', 'case', 'job', 'mailbox', 'community-chat', 'product']);
    final heights = {
      for (final id in ['work', 'customers', 'sales', 'service', 'comms', 'apps'])
        tester.getSize(find.byKey(ValueKey('menu-group-$id'))).height.round(),
    };
    expect(heights.length, 1, reason: '$heights');
  });
}
