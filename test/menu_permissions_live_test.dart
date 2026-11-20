import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('route guard follows the menus', () {
    const noMeeting = SessionState(accessToken: 't', businessId: 'guard-1', menusLoaded: true, menuKeys: ['lead']);
    const meeting = SessionState(accessToken: 't', businessId: 'guard-1', menusLoaded: true, menuKeys: ['ai-minute-meeting']);

    test('meeting join links (/m/:code) need AI Minute Meeting, even before ISAAC access is cached', () {
      expect(isaacItemFor('/m/ABC123'), IsaacMenu.minuteMeeting);
      expect(accessRedirectFor(noMeeting, '/m/ABC123'), AppRoutes.mainShell);
      expect(accessRedirectFor(noMeeting, '/ai-minutes/5'), AppRoutes.mainShell);
      expect(accessRedirectFor(meeting, '/m/ABC123'), isNull);
      expect(accessRedirectFor(meeting, '/ai-minutes/5'), isNull);
    });

    test('store page: orders, or stock only for business admins (same as the menu)', () {
      const stockMember = SessionState(accessToken: 't', menusLoaded: true, menuKeys: ['mini-store-stock'], businessRole: 'member');
      const stockAdmin = SessionState(accessToken: 't', menusLoaded: true, menuKeys: ['mini-store-stock'], businessRole: 'admin');
      const orders = SessionState(accessToken: 't', menusLoaded: true, menuKeys: ['mini-store-orders']);
      expect(accessRedirectFor(stockMember, AppRoutes.commerce), AppRoutes.mainShell);
      expect(accessRedirectFor(stockAdmin, AppRoutes.commerce), isNull);
      expect(accessRedirectFor(orders, AppRoutes.commerce), isNull);
    });

    test('Assistant: when the menu shows it (ai_chat on) the page opens, as on the web', () async {
      SharedPreferences.setMockInitialValues({});
      IsaacAccessCache.attach(await SharedPreferences.getInstance());
      const s = SessionState(accessToken: 't', businessId: 'ai-1', menusLoaded: true, menuKeys: ['lead']);
      // Nothing cached yet: the Package menu key decides.
      expect(accessRedirectFor(s, '/ai'), AppRoutes.mainShell);
      IsaacAccessCache.debugPut('ai-1', const IsaacAccess(aiChat: true));
      expect(IsaacAccessCache.peek('ai-1')!.visible(IsaacMenu.assistant, s), isTrue);
      expect(accessRedirectFor(s, '/ai'), isNull);
      IsaacAccessCache.debugPut('ai-1', const IsaacAccess(aiChat: false));
      expect(accessRedirectFor(s, '/ai'), AppRoutes.mainShell);
    });
  });

  test('Home tab stays (the app landing page), the bar is never empty', () {
    final tabs = resolveShellTabs(roles: const ['general'], allowed: (k) => k.contains('community-workspace'));
    expect(tabs.first, 'dashboard');
    expect(shellTabById('dashboard')!.anyMenu, isEmpty);
  });

  group('AppConfig menus', () {
    Future<AppConfig> config(SessionState s, Map<String, Object?> replies) async {
      FlutterSecureStorage.setMockInitialValues({});
      final c = AppConfig();
      // Let the startup load finish first so it cannot overwrite the session below.
      for (var i = 0; i < 200 && !c.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      c.debugOverrideSession(s);
      c.apiClient.debugSetHttpAdapter(FakeNextxAdapter(replies));
      return c;
    }

    test('a business that becomes unrestricted drops the old menu list (memory and device)', () async {
      SharedPreferences.setMockInitialValues({'session_menu_keys': 'lead'});
      final c = await config(
        const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']),
        {
          'GET /api/me': {
            'user': {'id': 2, 'email1': 'a@b.c'},
            'business': {'id': 1, 'business_name': 'A'},
          },
        },
      );
      expect(c.session.canAccess('deal'), isFalse);
      await c.refreshSession();
      expect(c.session.menuKeys, isNull);
      expect(c.session.canAccess('deal'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session_menu_keys'), isNull);
    });

    test('switching business forgets the saved menus of the old one', () async {
      SharedPreferences.setMockInitialValues({'session_menu_keys': 'lead,deal', 'session_role_menu_keys': 'lead'});
      final c = await config(
        const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'deal']),
        const {}, // every call fails: the refresh after the switch cannot load the new menus
      );
      await c.selectBusiness(businessId: '9', businessName: 'B');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session_menu_keys'), isNull);
      expect(prefs.getString('session_role_menu_keys'), isNull);
      expect(c.session.menusLoaded, isFalse);
    });

    test('permissions:changed refreshes once per change, a change during a refresh runs one more', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await config(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true), const {});
      var runs = 0;
      final gate = Completer<void>();
      Future<void> refresh() async {
        runs++;
        if (runs == 1) await gate.future;
      }

      final first = c.handlePermissionsChanged(refresh: refresh);
      c.handlePermissionsChanged(refresh: refresh);
      c.handlePermissionsChanged(refresh: refresh);
      gate.complete();
      await first;
      expect(runs, 2);
      await c.handlePermissionsChanged(refresh: refresh);
      expect(runs, 3);
    });
  });

  test('the socket forwards permissions:changed', () {
    expect(RealtimeService.forwardedEvents, contains(kPermissionsChangedEvent));
  });
}
