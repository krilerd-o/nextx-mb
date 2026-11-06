import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/auth_redirect.dart';
import 'package:nextx_mobile/core/hub_selection.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/onboarding_redirect.dart';
import 'package:nextx_mobile/core/server_profile.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/fake_api.dart';

void main() {
  group('server', () {
    test('normalizes what people type', () {
      expect(normalizeServerUrl('moainext.moai-crm.com'), 'https://moainext.moai-crm.com');
      expect(normalizeServerUrl(' https://CRM.Example.com/ '), 'https://crm.example.com');
      expect(normalizeServerUrl('https://crm.example.com/api'), 'https://crm.example.com');
      expect(normalizeServerUrl('http://192.168.1.10:8080'), 'http://192.168.1.10:8080');
      expect(normalizeServerUrl(''), '');
      expect(serverLabel('https://crm.example.com'), 'crm.example.com');
    });

    test('only a MOAI NEXT health signature is accepted', () {
      expect(isNextxHealth({'status': 'S', 'data': {'app': 'MOAI NEXT API', 'signature': 'aisystem'}}), isTrue);
      expect(isNextxHealth({'status': 'S', 'data': {'app': 'Other', 'signature': 'aisystem'}}), isFalse);
      expect(isNextxHealth({'status': 'ok'}), isFalse);
      expect(isNextxHealth('html'), isFalse);
    });

    test('verifyNextxServer calls /api/health on the normalized url', () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      final adapter = FakeNextxAdapter({
        'GET https://crm.example.com/api/health': {'app': 'MOAI NEXT API', 'signature': 'aisystem'},
      });
      dio.httpClientAdapter = adapter;
      final ok = await verifyNextxServer('crm.example.com', dio: dio);
      expect(ok.ok, isTrue);
      expect(ok.url, 'https://crm.example.com');
      final bad = await verifyNextxServer('other.example.com', dio: dio);
      expect(bad.ok, isFalse);
      expect(bad.message, contains('MOAI NEXT'));
    });

    test('recent servers are distinct, newest first', () {
      var r = pushRecentServer([], 'a.com');
      r = pushRecentServer(r, 'b.com');
      r = pushRecentServer(r, 'https://a.com/');
      expect(r, ['https://a.com', 'https://b.com']);
    });
  });

  group('LINE redirect capture', () {
    test('token on the SPA /login page', () {
      final r = parseAuthRedirect('https://moainext.moai-crm.com/login?token=abc.def');
      expect(r?.token, 'abc.def');
    });
    test('errors and linking', () {
      expect(parseAuthRedirect('https://x.com/login?error=line_not_linked')?.error, 'line_not_linked');
      expect(parseAuthRedirect('https://x.com/login/?line=linked')?.linked, isTrue);
      expect(authRedirectErrorText('line_not_linked'), contains('ยังไม่ได้ผูก'));
    });
    test('LINE pages and plain /login are ignored', () {
      expect(parseAuthRedirect('https://access.line.me/oauth2/v2.1/login?x=1'), isNull);
      expect(parseAuthRedirect('https://x.com/login'), isNull);
      expect(parseAuthRedirect('https://x.com/api/auth/line/callback?code=1'), isNull);
    });
  });

  group('business / package', () {
    test('hides cancelled and sandbox businesses like the web hub', () {
      final list = visibleBusinesses([
        {'id': 1, 'business_code': 'ACME'},
        {'id': 2, 'business_code': 'ACME-SBX'},
        {'id': 3, 'status': 'cancelled'},
        {'id': 4, 'is_sandbox': 1},
        {'id': 5, 'business_code': 'B', 'is_default': true},
      ]);
      expect(list.map((b) => b['id']), [1, 5]);
      expect(defaultBusiness(list)?['id'], 5);
    });

    test('packages: enabled only, no all_package', () {
      final list = visiblePackages([
        {'id': 1, 'code': 'next_s', 'enabled': true},
        {'id': 2, 'code': 'all_package', 'enabled': true},
        {'id': 3, 'code': 'next_t', 'enabled': false},
        {'id': 4, 'code': 'next_h'},
      ]);
      expect(list.map((p) => p['code']), ['next_s', 'next_h']);
    });

    test('auto package: last → user default → business default → only one', () {
      final ps = [
        {'id': 1, 'code': 'next_s'},
        {'id': 2, 'code': 'next_t'},
      ];
      expect(autoPackage(ps, lastCode: 'next_t', userDefaultId: '1')?['code'], 'next_t');
      expect(autoPackage(ps, userDefaultId: '1', businessDefaultId: '2')?['code'], 'next_s');
      expect(autoPackage(ps, businessDefaultId: '2')?['code'], 'next_t');
      expect(autoPackage(ps), isNull);
      expect(autoPackage([ps.first])?['code'], 'next_s');
      expect(autoPackage(ps, lastCode: 'gone', userDefaultId: 'null'), isNull);
    });

    test('every request carries X-Business-Id and X-Package-Code', () async {
      final adapter = FakeNextxAdapter({'GET /api/me': {'user': {'id': 1}}});
      final api = ApiClient(dio: Dio(BaseOptions(baseUrl: 'https://x.test')));
      api.debugSetHttpAdapter(adapter);
      api.attachSession(baseUrl: 'https://x.test', accessToken: 't', businessId: '9', packageCode: 'next_s');
      await api.getMe();
      final h = adapter.calls.single.headers;
      expect(h['X-Business-Id'], '9');
      expect(h['X-Package-Code'], 'next_s');
      expect(h['Authorization'], 'Bearer t');
    });
  });

  group('bottom tabs', () {
    bool all(List<String> _) => true;

    test('roles merge in order, capped at 4', () {
      final tabs = resolveShellTabs(roles: ['sales', 'hr'], allowed: all);
      expect(tabs, ['dashboard', 'leads', 'quotation', 'calendar']);
      expect(resolveShellTabs(roles: ['field'], allowed: all), ['jobs', 'calendar', 'hr', 'chat']);
    });

    test('tabs without menu permission are dropped and topped up', () {
      // Only chat allowed besides always-on tabs.
      bool onlyChat(List<String> keys) => keys.contains('community-chat');
      final tabs = resolveShellTabs(roles: ['sales'], allowed: onlyChat);
      expect(tabs.contains('leads'), isFalse);
      expect(tabs.first, 'dashboard');
      expect(tabs.length, greaterThanOrEqualTo(2));
      expect(tabs, contains('chat'));
    });

    test('custom arrangement wins, unknown ids ignored', () {
      final tabs = resolveShellTabs(roles: ['sales'], custom: ['chat', 'nope', 'dashboard'], allowed: all);
      expect(tabs, ['chat', 'dashboard']);
    });

    test('config round-trips', () {
      const c = ShellTabsConfig(roles: ['sales', 'hr'], tabs: ['dashboard', 'hr']);
      final back = ShellTabsConfig.decode(c.encode())!;
      expect(back.roles, ['sales', 'hr']);
      expect(back.tabs, ['dashboard', 'hr']);
      expect(ShellTabsConfig.decode('garbage'), isNull);
      expect(roleSummary(['hr']), 'ทีม HR');
      expect(workRoles.length, 9);
    });
  });

  group('onboarding redirect', () {
    String? go(String loc, {bool ready = true, bool login = true, bool server = true, bool biz = true, bool pkg = true, bool role = true}) =>
        onboardingRedirect(loc: loc, ready: ready, loggedIn: login, serverConfirmed: server, hasBusiness: biz, hasPackage: pkg, roleSetupDone: role);

    test('walks each step in order', () {
      expect(go(AppRoutes.mainShell, ready: false), AppRoutes.splash);
      expect(go(AppRoutes.mainShell, login: false, server: false), AppRoutes.welcome);
      expect(go(AppRoutes.server, login: false, server: false), isNull);
      expect(go(AppRoutes.mainShell, login: false), AppRoutes.login);
      expect(go(AppRoutes.server, login: false), isNull);
      expect(go(AppRoutes.mainShell, biz: false), AppRoutes.hub);
      expect(go(AppRoutes.mainShell, pkg: false), AppRoutes.package);
      expect(go(AppRoutes.mainShell, role: false), AppRoutes.roleSetup);
      expect(go(AppRoutes.tabSetup, role: false), isNull);
    });

    test('setup screens bounce to the app when done; others stay', () {
      expect(go(AppRoutes.login), AppRoutes.mainShell);
      expect(go(AppRoutes.package), AppRoutes.mainShell);
      expect(go(AppRoutes.mail), isNull);
      expect(go(AppRoutes.tabEditor), isNull);
    });
  });
}
