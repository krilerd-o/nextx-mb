import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/auth_redirect.dart';
import 'package:nextx_mobile/core/server_profile.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';

import 'support/fake_api.dart';

String _jwt(Map<String, dynamic> payload) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64(payload)}.sig';
}

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _health({Map<String, dynamic>? mobile}) => {
      'app': 'MOAI NEXT API',
      'signature': 'aisystem',
      'mobile': ?mobile,
    };

Future<AppConfig> _readyConfig(FakeNextxAdapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  config.apiClient.debugSetHttpAdapter(adapter);
  while (!config.isReady) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version compare and update need', () {
    expect(compareVersions('1.2.10+5', '1.2.9'), 1);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('0.2.0+2', '1.0.0'), -1);
    const info = MobileServerInfo(minVersion: '1.0.0', latestVersion: '1.3.0');
    expect(updateNeedFor(info, '0.9.9'), UpdateNeed.required);
    expect(updateNeedFor(info, '1.1.0+7'), UpdateNeed.optional);
    expect(updateNeedFor(info, '1.3.0'), UpdateNeed.none);
    expect(updateNeedFor(null, '0.0.1'), UpdateNeed.none);
  });

  test('mobile info parses from health and older servers give null', () {
    final m = MobileServerInfo.fromJson({'min_version': '1.0.0', 'store_url': '', 'features': ['sliding_session', 'line_app']})!;
    expect(m.minVersion, '1.0.0');
    expect(m.storeUrl, isNull);
    expect(m.has('line_app'), isTrue);
    expect(m.has('prefs_mobile'), isFalse);
    expect(MobileServerInfo.fromJson(null), isNull);
    expect(MobileServerInfo.fromJson(MobileServerInfo.fromJson(m.toJson())!.toJson())!.features, m.features);
  });

  test('app link from LINE is parsed like the web callback', () {
    expect(parseAuthRedirect('moainext://app/login?token=abc')!.token, 'abc');
    expect(parseAuthRedirect('/login?error=line_not_linked')!.error, 'line_not_linked');
    expect(parseAuthRedirect('/login'), isNull);
  });

  test('server shell is adopted only when usable', () {
    expect(ShellTabsConfig.fromServer({'roles': ['sales'], 'tabs': null})!.roles, ['sales']);
    expect(ShellTabsConfig.fromServer({'roles': [], 'tabs': []}), isNull);
    expect(ShellTabsConfig.fromServer('x'), isNull);
  });

  test('old server: no mobile info, every request marks the app', () async {
    final adapter = FakeNextxAdapter({'GET /api/health': _health()});
    final config = await _readyConfig(adapter);
    await config.refreshServerInfo(force: true);
    expect(config.serverInfo, isNull);
    expect(config.updateNeed, UpdateNeed.none);
    expect(adapter.calls.last.headers['X-Nextx-Client'], 'mobile');
  });

  test('sliding session: a renewed token from X-Session-Token replaces the old one', () async {
    final oldTok = _jwt({'userId': 1, 'iat': _secs(DateTime.now().subtract(const Duration(days: 2)))});
    final newTok = _jwt({'userId': 1, 'iat': _secs(DateTime.now())});
    final adapter = FakeNextxAdapter(
      {'GET /api/me': {'user': {'id': 1}}},
      headersFor: {'GET /api/me': {'x-session-token': newTok}},
    );
    final config = await _readyConfig(adapter);
    config.debugOverrideSession(SessionState(accessToken: oldTok, userId: '1', businessId: '1'));
    await config.apiClient.getMe();
    expect(config.session.accessToken, newTok);
    expect(adapter.calls.last.headers['Authorization'], 'Bearer $oldTok');
    await config.apiClient.getMe();
    expect(adapter.calls.last.headers['Authorization'], 'Bearer $newTok');
    expect(adapter.callKeys, isNot(contains('POST /api/auth/refresh')));
  });

  test('signed out: a late renewed token is ignored', () async {
    final adapter = FakeNextxAdapter(
      {'GET /api/health': _health()},
      headersFor: {'GET /api/health': {'x-session-token': _jwt({'userId': 1})}},
    );
    final config = await _readyConfig(adapter);
    await config.refreshServerInfo(force: true);
    expect(config.session.accessToken, isNull);
  });

  test('new server: forced update and menu sync', () async {
    final adapter = FakeNextxAdapter({
      'GET /api/health': _health(mobile: {'min_version': '99.0.0', 'features': ['sliding_session', 'prefs_mobile']}),
      'PATCH /api/me/preferences': {'mobile_shell': null},
    });
    final config = await _readyConfig(adapter);
    await config.refreshServerInfo(force: true);
    expect(config.updateNeed, UpdateNeed.required);
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1'));

    await config.saveShellConfig(const ShellTabsConfig(roles: ['hr'], tabs: ['hr', 'chat']));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final patch = adapter.calls.singleWhere((c) => c.path == '/api/me/preferences');
    expect((patch.data as Map)['mobile_shell'], {'roles': ['hr'], 'tabs': ['hr', 'chat']});
  });
}
