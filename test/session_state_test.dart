import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/menu_access.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/workspace/workspace_kanban_board.dart';
import 'package:nextx_mobile/services/api_client.dart';

void main() {
  test('canAccess fails closed until menus load', () {
    const locked = SessionState(accessToken: 't', userId: '1', businessId: '1');
    expect(locked.canAccess(MenuAccess.lead), isFalse);
    expect(MenuAccess.allow(locked, MenuAccess.job), isFalse);
  });

  test('canAccess uses loaded menu keys', () {
    const session = SessionState(
      accessToken: 't',
      menusLoaded: true,
      menuKeys: ['lead', 'calendar'],
    );
    expect(session.canAccess(MenuAccess.lead), isTrue);
    expect(session.canAccess(MenuAccess.job), isFalse);
  });

  test('superadmin bypasses menu list', () {
    const session = SessionState(accessToken: 't', isSuperadmin: true);
    expect(session.canAccess(MenuAccess.mailbox), isTrue);
  });

  test('CRM/FSM hub keys and file-manager match the web', () {
    const session = SessionState(
      accessToken: 't',
      menusLoaded: true,
      menuKeys: ['product', 'service', 'quotation', 'file-manager', 'inspection'],
    );
    expect(MenuAccess.files, 'file-manager');
    expect(MenuAccess.anyCrm(session), isTrue);
    expect(MenuAccess.anyFsm(session), isTrue);
    expect(MenuAccess.allow(session, MenuAccess.files), isTrue);
    expect(MenuAccess.anyHr(session), isFalse);
  });

  test('extractMapList unwraps envelopes', () {
    expect(extractMapList({'list': [{'id': 1}]}), [{'id': 1}]);
    expect(extractMapList({'items': [{'id': 2}]}), [{'id': 2}]);
    expect(extractMapList([{'id': 3}]), [{'id': 3}]);
    expect(extractMapList('nope'), isEmpty);
  });

  test('EntityListPage.hasMore uses total when present', () {
    final page = EntityListPage(items: [{'id': 1}], limit: 30, offset: 0, total: 1);
    expect(page.hasMore, isFalse);
    final more = EntityListPage(items: List.generate(30, (i) => {'id': i}), limit: 30, offset: 0);
    expect(more.hasMore, isTrue);
  });

  test('kanban columns come from board grouped keys', () {
    expect(kanbanColumnKeys({'Doing': [], 'Done': []}), ['Doing', 'Done']);
    expect(kanbanColumnKeys({}), ['อื่นๆ']);
  });

  test('formatApiError prefers envelope message', () {
    expect(formatApiError(ApiEnvelopeException(400, 'X', 'อยู่นอกระยะ')), 'อยู่นอกระยะ');
    expect(formatApiError(ApiException(401, '')), contains('เซสชัน'));
  });

  test('notification deep links map web paths to go_router', () {
    expect(notificationDeepLink('/modules/lead/42'), AppRoutes.crmRecord('lead', '42'));
    expect(notificationDeepLink('/modules/job/view/88'), AppRoutes.fsmRecord('job', '88'));
    expect(notificationDeepLink('/modules/inspection/3'), AppRoutes.fsmRecord('inspection', '3'));
    expect(notificationDeepLink('/modules/product/9'), AppRoutes.crmRecord('product', '9'));
    expect(notificationDeepLink('/modules/service/2'), AppRoutes.crmRecord('service', '2'));
    expect(notificationDeepLink('/modules/service_contract'), AppRoutes.fsmModule('service_contract'));
    expect(notificationDeepLink('/modules/case?open=15'), AppRoutes.crmRecord('case', '15'));
    expect(notificationDeepLink('/calendar/9'), AppRoutes.activity('9'));
    expect(notificationDeepLink('/calendar?open=9'), AppRoutes.activity('9'));
    expect(
      notificationDeepLinkFromData({'url': '/workspace/1/2'}),
      AppRoutes.task('1', '2'),
    );
    expect(notificationDeepLink('/workspace/NSMO-250'), AppRoutes.board('NSMO-250'));
    expect(notificationDeepLink('/workspace/NSMO/NSMO-250'), AppRoutes.board('NSMO-250'));
    expect(notificationDeepLink('/workspace/boards/12'), AppRoutes.board('12'));
    expect(parseWorkspaceItemSlug('NSMO-250')?.boardCode, 'NSMO');
    expect(parseWorkspaceItemSlug('NSMO-250')?.itemNo, 250);
    expect(parseWorkspaceItemSlug('12'), isNull);
  });
}
