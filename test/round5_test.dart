import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/error_reporting.dart';
import 'package:nextx_mobile/core/invite_link.dart';
import 'package:nextx_mobile/core/recent_accounts.dart';
import 'package:nextx_mobile/screens/auth/register_screen.dart';
import 'package:nextx_mobile/services/app_lock.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/widgets/nx_hero_cta.dart';
import 'package:nextx_mobile/widgets/nx_workspace_switcher.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('error log entry keeps time, kind, message and app frames', () {
    final stack = StackTrace.fromString('#0 foo (package:nextx_mobile/a.dart:1)\n#1 bar (dart:async)\n#2 baz (package:nextx_mobile/b.dart:2)');
    final e = ErrorReporting.formatEntry(StateError('boom'), stack, fatal: true, at: DateTime(2026, 11, 6, 9));
    expect(e, startsWith('2026-11-06T09:00:00.000 FATAL Bad state: boom'));
    expect(e, contains('package:nextx_mobile/a.dart'));
    expect(e, isNot(contains('dart:async')));
    final long = ErrorReporting.formatEntry('x' * 1000, null);
    expect(long.length, lessThan(460));
  });

  test('package suggests a work role', () {
    expect(suggestedRolesForPackage('next_s'), ['sales']);
    expect(suggestedRolesForPackage('next_h'), ['hr']);
    expect(suggestedRolesForPackage('next_o'), ['online']);
    expect(suggestedRolesForPackage(null), isEmpty);
    expect(suggestedRolesForPackage('unknown'), isEmpty);
  });

  test('session refresh is throttled', () {
    final now = DateTime(2026, 11, 6, 10);
    const gap = Duration(minutes: 5);
    expect(shouldRefreshSession(null, now, gap), isTrue);
    expect(shouldRefreshSession(now.subtract(const Duration(minutes: 2)), now, gap), isFalse);
    expect(shouldRefreshSession(now.subtract(const Duration(minutes: 5)), now, gap), isTrue);
  });

  test('shell tabs drop tabs whose permission is gone', () {
    bool Function(List<String>) has(List<String> keys) => (any) => any.any(keys.contains);
    final withLead = resolveShellTabs(roles: ['sales'], allowed: has(['lead', 'quotation', 'calendar']));
    expect(withLead, ['dashboard', 'leads', 'quotation', 'calendar']);
    final without = resolveShellTabs(roles: ['sales'], allowed: has(['calendar']));
    expect(without, isNot(contains('leads')));
    expect(without, isNot(contains(kMenuTabId)));
    expect(without.first, 'dashboard');
  });

  test('last tab is remembered per user', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    while (!config.isReady) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '9', businessId: '1'));
    await config.setLastTab('chat');
    expect(config.lastTab, 'chat');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => k.startsWith('last_tab_') && k.endsWith('_9')), isTrue);
  });

  testWidgets('workspace switcher lists packages of the business', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    await tester.runAsync(() async {
      while (!config.isReady) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    config.debugOverrideSession(const SessionState(
        accessToken: 't', userId: '1', businessId: '5', businessName: 'ร้านเอ', packageCode: 'next_s'));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({
      'GET /api/businesses/5/packages': [
        {'id': '1', 'code': 'next_s', 'name': 'NEXT S', 'enabled': true},
        {'id': '2', 'code': 'next_h', 'name': 'NEXT H', 'enabled': true},
      ],
    }));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config, child: const MaterialApp(home: Scaffold(body: NxWorkspaceSwitcher()))));
    expect(find.text('ร้านเอ · NEXT S'), findsOneWidget);
    await tester.tap(find.text('ร้านเอ · NEXT S'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('NEXT H'), findsOneWidget);
    expect(find.text('เปลี่ยนธุรกิจ'), findsOneWidget);
  });

  // ---- Round 5 C ----
  test('recent accounts: newest first, deduped per server, capped', () {
    const s1 = 'https://a.com';
    var list = <RecentAccount>[];
    list = pushRecentAccount(list, const RecentAccount(server: s1, loginId: 'Ann@x.com', name: 'Ann'));
    list = pushRecentAccount(list, const RecentAccount(server: s1, loginId: 'bob@x.com'));
    list = pushRecentAccount(list, const RecentAccount(server: s1, loginId: 'ann@x.com', name: 'Ann B'));
    list = pushRecentAccount(list, const RecentAccount(server: 'https://b.com', loginId: 'ann@x.com'));
    expect(recentAccountsFor(list, s1).map((e) => e.name), ['Ann B', '']);
    final back = decodeRecentAccounts(encodeRecentAccounts(list));
    expect(back.length, 3);
    expect(removeRecentAccount(back, back.first).length, 2);
    expect(decodeRecentAccounts('not json'), isEmpty);
    for (var i = 0; i < 9; i++) {
      list = pushRecentAccount(list, RecentAccount(server: s1, loginId: 'u$i'));
    }
    expect(list.length, 5);
  });

  test('invite links from the web and the app scheme', () {
    final web = parseInviteLink(Uri.parse('https://moainext.moai-crm.com/register?invite=abc123'))!;
    expect(web.token, 'abc123');
    expect(web.server, 'https://moainext.moai-crm.com');
    final app = parseInviteLink(Uri.parse('moainext://app/register?invite=zz'))!;
    expect(app.token, 'zz');
    expect(app.server, isNull);
    expect(parseInviteLink(Uri.parse('/register?invite=t'))!.token, 't');
    expect(parseInviteLink(Uri.parse('https://x.com/register')), isNull);
    expect(parseInviteLink(Uri.parse('https://x.com/login?invite=t')), isNull);
  });

  test('app lock asks again only after the idle time', () {
    final now = DateTime(2026, 11, 6, 12);
    expect(shouldLockOnResume(enabled: true, pausedAt: now.subtract(const Duration(minutes: 6)), now: now), isTrue);
    expect(shouldLockOnResume(enabled: true, pausedAt: now.subtract(const Duration(minutes: 1)), now: now), isFalse);
    expect(shouldLockOnResume(enabled: false, pausedAt: now.subtract(const Duration(hours: 1)), now: now), isFalse);
    expect(shouldLockOnResume(enabled: true, pausedAt: null, now: now), isFalse);
  });

  testWidgets('register from an invite hides the serial key and sends invite_token', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = AppConfig();
    await tester.runAsync(() async {
      while (!config.isReady) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final adapter = FakeNextxAdapter({'POST /api/auth/register': {'pending': true}});
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config, child: const MaterialApp(home: RegisterScreen(inviteToken: 'inv-1'))));
    expect(find.textContaining('สมัครจากลิงก์เชิญ'), findsOneWidget);
    expect(find.text('ฉันมีรหัสเชิญ / ซีเรียลคีย์'), findsNothing);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ann Lee');
    await tester.enterText(fields.at(1), 'ann@x.com');
    await tester.enterText(fields.at(2), 'Passw0rd!x');
    await tester.enterText(fields.at(3), 'Passw0rd!x');
    await tester.tap(find.byType(NxHeroCta));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    final call = adapter.calls.singleWhere((c) => c.path == '/api/auth/register');
    expect((call.data as Map)['invite_token'], 'inv-1');
    expect((call.data as Map)['signup_type'], 'with_key');
  });
}
