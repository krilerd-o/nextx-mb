import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/isaac_coming_soon_screen.dart';
import 'package:nextx_mobile/screens/ai/isaac_embed_screen.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

Map<String, dynamic> _plugin({bool enabled = true, String audience = 'all_members', Map<String, dynamic>? menus}) => {
      'config': {
        'enabled': enabled,
        'audience': audience,
        'menus': {'assistant': true, 'notebook': true, 'minute_auto': true, 'agent': true, 'social_watch': true, ...?menus},
        'minute_auto': {'default_language': 'th', 'show_transcript': false, 'allow_export': true, 'notify_owner': true, 'auto_open_after_meeting': true},
      },
    };

List<String> _keys(IsaacAccess a, [SessionState s = _member]) => [for (final i in a.visibleItems(s)) i.key];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ISAAC AI menu = web visibleMenuItems.js', () {
    test('plugin on: all 5 in web order', () {
      final a = IsaacAccess.fromResponses(aiSettings: {'settings': {'ai_chat': true}}, pluginEffective: _plugin());
      expect(_keys(a), ['ai-assistant', 'isaac-notebook', 'ai-minute-auto', 'isaac-ai-agent', 'isaac-social-watch']);
    });

    test('plugin off: Assistant + coming-soon only (as on the QA server today)', () {
      final a = IsaacAccess.fromResponses(aiSettings: {'settings': {'ai_chat': true}}, pluginEffective: _plugin(enabled: false));
      expect(_keys(a), ['ai-assistant', 'isaac-ai-agent', 'isaac-social-watch']);
    });

    test('ai_chat off hides Assistant; menu toggles hide items', () {
      final a = IsaacAccess.fromResponses(
        aiSettings: {'settings': {'ai_chat': false}},
        pluginEffective: _plugin(menus: {'notebook': false, 'social_watch': false}),
      );
      expect(_keys(a), ['ai-minute-auto', 'isaac-ai-agent']);
    });

    test('audience = menu_permission needs the menu key (superadmin skips)', () {
      final a = IsaacAccess.fromResponses(aiSettings: {'settings': {'ai_chat': true}}, pluginEffective: _plugin(audience: 'menu_permission'));
      expect(_keys(a), isNot(contains('isaac-notebook')));
      const withKey = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['isaac-notebook']);
      expect(_keys(a, withKey), contains('isaac-notebook'));
      const admin = SessionState(accessToken: 't', userId: '1', businessId: '1', isSuperadmin: true);
      expect(_keys(a, admin), containsAll(['isaac-notebook', 'ai-minute-auto']));
    });

    test('plugin not loaded: nothing ISAAC except Assistant', () {
      final a = IsaacAccess.fromResponses(aiSettings: {'settings': {'ai_chat': true}});
      expect(_keys(a), ['ai-assistant']);
    });
  });

  group('launch URL (web buildIsaacLaunchUrl)', () {
    test('token stays in the hash; path and embed in the query', () {
      final url = buildIsaacLaunchUrl({'app_origin': 'https://isaac.example.com/', 'isaac_token': 'a b'}, path: '/', bust: '9');
      expect(url, 'https://isaac.example.com/?_moai=9&embed=moai#auth_token=a%20b');
    });

    test('Minute Auto keeps its options', () {
      final path = isaacMinutePath(_plugin()['config']['minute_auto'] as Map<String, dynamic>);
      expect(path, '/minute-auto?lang=th&transcript=0&auto_open=1');
      final url = buildIsaacLaunchUrl({'app_origin': 'https://isaac.example.com', 'isaac_token': 't'}, path: path);
      expect(url, 'https://isaac.example.com/minute-auto?lang=th&transcript=0&auto_open=1&embed=moai#auth_token=t');
    });

    test('server message wins; codes map to Thai', () {
      expect(isaacLaunchErrorText('ISAAC_403_PLUGIN_DISABLED', message: 'ข้อความจากเซิร์ฟเวอร์'), 'ข้อความจากเซิร์ฟเวอร์');
      expect(isaacLaunchErrorText('ISAAC_503_NOT_READY'), contains('ไอแซค'));
      expect(isaacLaunchErrorText('ISAAC_429_RATE_LIMIT'), contains('รอสักครู่'));
    });
  });

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget screen, Map<String, Object?> replies, {Map<String, int> status = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig()..debugOverrideSession(_member);
    final adapter = FakeNextxAdapter(replies, statusFor: status);
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  testWidgets('new ISAAC user: "set password from the email" card + retry', (tester) async {
    final adapter = await pump(tester, const IsaacEmbedScreen(menu: 'bot'), {
      'POST /api/integrations/isaac/launch': {'next_step': 'PASSWORD_SETUP_EMAILED', 'email': 'qa.second@example.com'},
    });
    final call = adapter.calls.firstWhere((c) => c.path == '/api/integrations/isaac/launch');
    expect(Map<String, dynamic>.from(call.data as Map)['menu'], 'bot');
    expect(find.byKey(const ValueKey('isaac-emailed')), findsOneWidget);
    expect(find.textContaining('qa.second@example.com'), findsOneWidget);
    await tester.tap(find.text('ตั้งรหัสผ่านแล้ว เปิดอีกครั้ง'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.calls.where((c) => c.path == '/api/integrations/isaac/launch').length, 2);
  });

  testWidgets('ISAAC not ready: server message + retry', (tester) async {
    await pump(
      tester,
      const IsaacEmbedScreen(menu: 'bot'),
      {'POST /api/integrations/isaac/launch': {'status': 'E', 'error_code': 'ISAAC_503_NOT_READY', 'message': 'ISAAC ยังไม่พร้อม'}},
      status: {'POST /api/integrations/isaac/launch': 503},
    );
    expect(find.byKey(const ValueKey('isaac-error')), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('coming soon page: web copy + button to the Assistant', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IsaacComingSoonScreen(product: 'social_watch')));
    await tester.pumpAndSettle();
    expect(find.text('AI Social Watch'), findsWidgets);
    expect(find.textContaining('เฝ้าดูแชทโซเชียล'), findsOneWidget);
    expect(find.byKey(const ValueKey('isaac-soon-cta')), findsOneWidget);
  });
}
