import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/menu_access.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';

void main() {
  const salesOnly = SessionState(
    accessToken: 't',
    menusLoaded: true,
    menuKeys: ['lead', 'service-contract'],
  );

  test('ungated routes need no menu', () {
    expect(requiredMenusFor(AppRoutes.mainShell), isNull);
    expect(requiredMenusFor(AppRoutes.notifications), isNull);
    expect(requiredMenusFor(AppRoutes.profile), isNull);
  });

  test('record routes map to the module menu key', () {
    expect(requiredMenusFor('/crm/lead/42'), [MenuAccess.lead]);
    expect(requiredMenusFor('/fsm/service_contract/7'), [MenuAccess.serviceContract]);
    expect(requiredMenusFor('/chat/9'), [MenuAccess.chat]);
    // ISAAC AI การสื่อสาร is its own Package menu (not every chat package has it).
    expect(requiredMenusFor('/comm-ai'), [MenuAccess.commAi]);
    expect(requiredMenusFor('/comm-ai/settings'), [MenuAccess.commAi]);
    expect(requiredMenusFor('/modules/quotation/3'), [MenuAccess.quotation]);
    expect(accessRedirectFor(salesOnly, '/modules/quotation/3'), AppRoutes.mainShell);
    expect(accessRedirectFor(salesOnly, '/modules/lead'), isNull);
  });

  test('allowed deep links pass, others go to the shell', () {
    expect(accessRedirectFor(salesOnly, '/crm/lead/42'), isNull);
    expect(accessRedirectFor(salesOnly, '/fsm/service_contract/7'), isNull);
    expect(accessRedirectFor(salesOnly, '/crm/deal/1'), AppRoutes.mainShell);
    expect(accessRedirectFor(salesOnly, '/chat/9'), AppRoutes.mainShell);
    expect(accessRedirectFor(salesOnly, AppRoutes.leaveRequest), AppRoutes.mainShell);
    expect(accessRedirectFor(salesOnly, AppRoutes.approvals), AppRoutes.mainShell);
    const approver = SessionState(accessToken: 't', menusLoaded: true, menuKeys: ['quotation']);
    expect(accessRedirectFor(approver, AppRoutes.approvals), isNull);
  });

  test('does not block before menus load', () {
    const loading = SessionState(accessToken: 't', userId: '1', businessId: '1');
    expect(accessRedirectFor(loading, '/crm/deal/1'), isNull);
  });

  test('superadmin is never redirected', () {
    const admin = SessionState(accessToken: 't', menusLoaded: true, isSuperadmin: true);
    expect(accessRedirectFor(admin, '/mail'), isNull);
  });

  test('web App Link paths map to in-app routes', () {
    expect(notificationDeepLink('/modules/lead/view/42'), AppRoutes.crmRecord('lead', '42'));
    expect(notificationDeepLink('/modules/job/5'), AppRoutes.fsmRecord('job', '5'));
    expect(notificationDeepLink('/modules/case?open=3'), AppRoutes.crmRecord('case', '3'));
  });
}
