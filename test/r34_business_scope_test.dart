import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/card_layout.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_birthdays.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/core/navigation/app_router.dart';
import 'package:nextx_mobile/core/recent_records.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/screens/app_shell.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

import 'support/fake_api.dart';

SessionState _s(String bid, String pkg) => SessionState(
      accessToken: 't',
      userId: '2',
      businessId: bid,
      businessName: '[QA] $bid',
      packageCode: pkg,
      menusLoaded: true,
      menuKeys: const ['lead', 'calendar'],
    );

Future<AppConfig> _config(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'getting_started_done': true});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({'GET /api/health': {'status': 'ok'}}));
  return config;
}

void main() {
  testWidgets('business scope + recently opened records are per business', (tester) async {
    final config = await _config(tester);
    config.debugOverrideSession(_s('1', 'crm'));
    final a = config.businessScope;
    await RecentRecords.instance.add(a, module: 'lead', id: '10', title: '[QA] Lead A');
    config.debugOverrideSession(_s('2', 'crm'));
    final b = config.businessScope;
    expect(b, isNot(a));
    await RecentRecords.instance.load(b);
    expect(RecentRecords.instance.items.value, isEmpty, reason: 'business 2 must not see business 1 records');
    await RecentRecords.instance.load(a);
    expect(RecentRecords.instance.items.value.single['title'], '[QA] Lead A');
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('switching business or package rebuilds the main shell (no old tab data)', (tester) async {
    final config = await _config(tester);
    config.debugOverrideSession(_s('1', 'crm'));
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
    await tester.pump(const Duration(milliseconds: 300));
    Key? shellKey() => tester.widgetList<AppShell>(find.byType(AppShell, skipOffstage: false)).firstOrNull?.key;
    final first = shellKey();
    expect(first, isNotNull);
    config.debugOverrideSession(_s('2', 'crm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final second = shellKey();
    expect(second, isNot(first));
    config.debugOverrideSession(_s('2', 'fsm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(shellKey(), isNot(second));
    RealtimeService.instance.disconnect();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });

  test('card layout per business; a new business starts from the older per-user one', () async {
    SharedPreferences.setMockInitialValues({});
    const user = 'https://qa.example.com|2';
    const user1 = '$user|b1', user2 = '$user|b2';
    final old = CardLayout.defaults('lead', const [], statusKey: null);
    await CardLayoutStore.save('lead', user, old);
    expect(await CardLayoutStore.load('lead', user1, fallbackScope: user), isNotNull);
    await CardLayoutStore.save('lead', user2, old);
    await CardLayoutStore.reset('lead', user);
    expect(await CardLayoutStore.load('lead', user1, fallbackScope: user), isNull);
    expect(await CardLayoutStore.load('lead', user2, fallbackScope: user), isNotNull);
  });

  test('birthday reminders follow the business, also from the cache', () async {
    SharedPreferences.setMockInitialValues({});
    CalBirthdays.clearCache();
    final api = ApiClient(dio: Dio(BaseOptions(baseUrl: 'https://qa.example.com')));
    api.debugSetHttpAdapter(FakeNextxAdapter({}));
    Future<void> open(String bid) async {
      api.attachSession(baseUrl: 'https://qa.example.com', accessToken: 't', userId: '2', businessId: bid);
      final b = CalBirthdays(api, scope: 'qa|2');
      await b.load();
      b.dispose();
    }

    final start = CalBirthdays.debugSyncCount;
    await open('1');
    await open('2');
    await open('1'); // from the cache, but reminders were business 2's
    expect(CalBirthdays.debugSyncCount - start, 3);
    await open('1'); // same business again: nothing to redo
    expect(CalBirthdays.debugSyncCount - start, 3);
  });
}
