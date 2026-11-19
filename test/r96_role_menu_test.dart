// AI Assistant / Notebook follow the role permission (like the web and the server's requireRoleMenu).
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';

Map<String, dynamic> _plugin() => {
      'config': {
        'enabled': true,
        'audience': 'all_members',
        'menus': {'assistant': true, 'notebook': true, 'minute_auto': true, 'agent': true, 'social_watch': true},
      },
    };

SessionState _s({List<String>? role, String? biz = 'member', List<String>? menus = const ['lead']}) =>
    SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: menus, businessRole: biz, roleMenuKeys: role);

void main() {
  final a = IsaacAccess.fromResponses(aiSettings: {'settings': {'ai_chat': true}}, pluginEffective: _plugin());
  List<String> keys(SessionState s) => [for (final i in a.visibleItems(s)) i.key];

  test('role without a permission set: Assistant shows even when the Package leaves it out (web rule)', () {
    expect(keys(_s()), containsAll(['ai-assistant', 'isaac-notebook']));
  });

  test('role set without the assistant: hidden, and /ai is redirected', () {
    final s = _s(role: const ['lead', 'contact']);
    expect(keys(s), isNot(contains('ai-assistant')));
    expect(keys(s), isNot(contains('isaac-notebook')));
    expect(s.roleAllows(const ['ai-assistant']), isFalse);
  });

  test('role with the notebook only: notebook yes, assistant no', () {
    final s = _s(role: const ['isaac-notebook']);
    expect(keys(s), contains('isaac-notebook'));
    expect(keys(s), isNot(contains('ai-assistant')));
  });

  test('owner / admin / superadmin always pass', () {
    expect(_s(role: const ['lead'], biz: 'owner').roleAllows(const ['ai-assistant']), isTrue);
    expect(_s(role: const ['lead'], biz: 'admin').roleAllows(const ['ai-assistant']), isTrue);
    expect(const SessionState(isSuperadmin: true, roleMenuKeys: ['lead']).roleAllows(const ['ai-assistant']), isTrue);
  });

  test('switching business clears the role keys', () {
    final s = _s(role: const ['lead']).copyWith(clearBusiness: true);
    expect(s.roleMenuKeys, isNull);
    expect(_s(role: const ['lead']).copyWith(clearRoleMenus: true).roleMenuKeys, isNull);
  });

  test('route guard uses the same rule', () {
    expect(isaacItemFor('/ai'), IsaacMenu.assistant);
    const menus = ['lead', 'ai-assistant'];
    expect(accessRedirectFor(_s(role: const ['lead'], menus: menus), '/ai/chat'), isNotNull);
    expect(accessRedirectFor(_s(role: const ['lead'], biz: 'owner', menus: menus), '/ai/chat'), isNull);
    expect(accessRedirectFor(_s(role: const ['ai-assistant'], menus: menus), '/ai'), isNull);
  });
}
