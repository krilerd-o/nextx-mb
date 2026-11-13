import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/web_session_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/fake_api.dart';

const _s = SessionState(accessToken: 't', userId: '2', businessId: '77', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

Future<void> _load(Map<String, Object?> replies) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://qa.test'))..httpClientAdapter = FakeNextxAdapter(replies);
  IsaacAccessCache.clear();
  await IsaacAccessCache.load(ApiClient(dio: dio), '77', fresh: true);
}

void main() {
  tearDown(IsaacAccessCache.clear);

  test('ISAAC links before access is known: let the page decide', () {
    IsaacAccessCache.clear();
    expect(accessRedirectFor(_s, '/isaac'), isNull);
  });

  test('plugin off: Minute Auto goes home; Assistant and the native Notebook (NEXTX AI) stay', () async {
    await _load({
      'GET /api/ai/settings': {
        'settings': {'ai_chat': true},
      },
      'GET /api/settings/isaac-plugin/effective': {
        'config': {'enabled': false},
      },
    });
    expect(accessRedirectFor(_s, '/isaac'), isNull);
    expect(accessRedirectFor(_s, '/notebook/3'), isNull);
    expect(accessRedirectFor(_s, '/ai-minute-auto'), AppRoutes.mainShell);
    expect(accessRedirectFor(_s, '/ai'), isNull);
  });

  test('AI chat off: the Assistant link goes home too', () async {
    await _load({
      'GET /api/ai/settings': {
        'settings': {'ai_chat': false},
      },
      'GET /api/settings/isaac-plugin/effective': {
        'config': {'enabled': false},
      },
    });
    expect(accessRedirectFor(_s, '/ai'), AppRoutes.mainShell);
    expect(accessRedirectFor(_s, '/notebook'), AppRoutes.mainShell);
    expect(isaacItemFor('/notebook/3')?.key, 'isaac-notebook');
    expect(isaacItemFor('/ai-minute-auto')?.key, 'ai-minute-auto');
    expect(isaacItemFor('/ai/shared/x')?.key, 'ai-assistant');
    expect(isaacItemFor('/workspace'), isNull);
  });

  test('web session script targets the app business and package', () {
    final js = webSessionContextJs(businessId: '3', businessName: "[QA] ร้าน 'B'", packageCode: 'NEXT_T');
    expect(js, contains('moai_next_auth'));
    expect(js, contains('bid=3'));
    expect(js, contains('"NEXT_T"'));
    expect(webSessionContextJs(businessId: null), isEmpty);
  });
}
