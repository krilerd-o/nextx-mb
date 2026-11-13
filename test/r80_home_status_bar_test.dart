import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Home hero starts below the status bar (empty page header keeps the top inset)', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HomeChartCache.instance.clear();
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['workspace'], displayName: 'สมชาย ใจดี'));
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
    for (final k in ['home-greeting', 'home-search']) {
      expect(tester.getTopLeft(find.byKey(ValueKey(k))).dy, greaterThanOrEqualTo(44), reason: '$k must not sit under the status bar');
    }

    // Any NxScrollScaffold with an empty header hands its body the full status-bar inset.
    double? seen;
    await tester.pumpWidget(MaterialApp(
      home: NxScrollScaffold(
        insetBody: false,
        header: const PreferredSize(preferredSize: Size.zero, child: SizedBox.shrink()),
        body: Builder(builder: (c) {
          seen = MediaQuery.paddingOf(c).top;
          return const SizedBox.expand();
        }),
      ),
    ));
    expect(seen, 44);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
