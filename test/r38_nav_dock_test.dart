import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/nav_dock.dart';
import 'package:nextx_mobile/core/navigation/app_router.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:nextx_mobile/widgets/nx_appearance_controls.dart';
import 'package:nextx_mobile/widgets/nx_tab_nav.dart';

import 'support/fake_api.dart';

const _session = SessionState(
  accessToken: 't',
  userId: '2',
  businessId: '1',
  businessName: '[QA] Biz',
  packageCode: 'crm',
  menusLoaded: true,
  menuKeys: ['lead', 'calendar'],
);

Future<AppConfig> _config(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'getting_started_done': true, ...prefs});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({'GET /api/health': {'status': 'ok'}}));
  config.debugOverrideSession(_session);
  return config;
}

Future<GoRouter> _pumpTablet(WidgetTester tester, AppConfig config) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => config.saveShellConfig(const ShellTabsConfig(roles: ['sales'])));
  late GoRouter router;
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: Builder(builder: (context) {
      router = createAppRouter(config);
      return MaterialApp.router(routerConfig: router);
    }),
  ));
  router.go('/main');
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return router;
}

Future<void> _end(WidgetTester tester) async {
  RealtimeService.instance.disconnect();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

Rect _nav(WidgetTester tester) => tester.getRect(find.byType(NxTabNav).last);

void main() {
  test('dock ids round-trip; unknown → left', () {
    for (final d in NxNavDock.values) {
      expect(resolveNavDock(d.id), d);
    }
    expect(resolveNavDock('nope'), NxNavDock.left);
    expect(resolveNavDock(null), NxNavDock.left);
  });

  testWidgets('tablet: menu moves to each position with an animation', (tester) async {
    final config = await _config(tester);
    await _pumpTablet(tester, config);
    expect(config.navDock, NxNavDock.left);
    final left = _nav(tester);
    expect(left.center.dx, lessThan(120));
    expect(left.height, greaterThan(left.width), reason: 'vertical rail');

    await config.setNavDock(NxNavDock.right);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mid = _nav(tester).center.dx;
    expect(mid, inExclusiveRange(left.center.dx + 50, 1180), reason: 'gliding, not jumping');
    await tester.pump(const Duration(seconds: 1));
    expect(_nav(tester).center.dx, greaterThan(1160));

    await config.setNavDock(NxNavDock.bottomCenter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final bottom = _nav(tester);
    expect(bottom.width, greaterThan(bottom.height), reason: 'horizontal bar');
    expect(bottom.center.dx, closeTo(640, 2));
    expect(bottom.bottom, greaterThan(760));

    await config.setNavDock(NxNavDock.topRight);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final tr = _nav(tester);
    expect(tr.top, lessThan(20));
    expect(tr.right, greaterThan(1260));
    // Content makes room under the top bar.
    expect(tester.getTopLeft(find.byKey(const ValueKey('shell-dock-body'))).dy, 0);
    final body = tester.widget<AnimatedPadding>(find.byKey(const ValueKey('shell-dock-body')));
    expect((body.padding as EdgeInsets).top, greaterThan(80));
    await _end(tester);
  });

  testWidgets('saved position is used at start; the change waits while another page is on top', (tester) async {
    final config = await _config(tester, {'nav_dock': 'bottom_left'});
    final router = await _pumpTablet(tester, config);
    expect(config.navDock, NxNavDock.bottomLeft);
    final start = _nav(tester);
    expect(start.left, lessThan(20));
    expect(start.bottom, greaterThan(760));

    router.push('/profile');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await config.setNavDock(NxNavDock.right);
    await tester.pump(const Duration(seconds: 1));
    // Still at the old place underneath …
    expect(tester.getRect(find.byType(NxTabNav, skipOffstage: false).first).left, lessThan(20));
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // … and moves once the shell is visible again.
    final moving = _nav(tester).center.dx;
    expect(moving, inExclusiveRange(start.center.dx, 1180));
    await tester.pump(const Duration(seconds: 1));
    expect(_nav(tester).center.dx, greaterThan(1160));
    await _end(tester);
  });

  testWidgets('picker: 8 positions, tap saves and the preview moves', (tester) async {
    final config = await _config(tester);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showNavDockPicker(context), child: const Text('open'))),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final d in NxNavDock.values) {
      expect(find.byKey(ValueKey('nav-dock-${d.id}')), findsOneWidget);
    }
    final before = tester.getCenter(find.byKey(const ValueKey('nav-dock-preview-bar')));
    await tester.tap(find.byKey(const ValueKey('nav-dock-top_center')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mid = tester.getCenter(find.byKey(const ValueKey('nav-dock-preview-bar')));
    await tester.pumpAndSettle();
    final after = tester.getCenter(find.byKey(const ValueKey('nav-dock-preview-bar')));
    expect(config.navDock, NxNavDock.topCenter);
    expect(after.dy, lessThan(before.dy));
    expect(mid.dx, inExclusiveRange(before.dx, after.dx));
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('nav_dock'), 'top_center');
    await tester.pump(const Duration(minutes: 2));
  });
}
