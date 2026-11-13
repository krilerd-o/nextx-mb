import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/deal_stage.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_record_actions.dart';
import 'package:nextx_mobile/screens/fsm/case_manday.dart';
import 'package:nextx_mobile/screens/fsm/contract_flows.dart';

import 'support/fake_api.dart';

Map<String, dynamic> bodyOf(RequestOptions c) => Map<String, dynamic>.from(c.data is String ? jsonDecode(c.data as String) as Map : c.data as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget home, Map<String, Object?> replies, {String role = 'admin'}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter(replies);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', businessRole: role, menusLoaded: true, menuKeys: const ['case', 'service_contract', 'deal']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    await settle(tester, 6);
    return adapter;
  }

  testWidgets('case manday: request sends contract + hours (Hour), reject needs a reason', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: CaseMandayPanel(id: '15', row: {'customer_email': 'qa@example.com'}))),
      {
        'GET /api/entity/case/15/manday-summary': {
          'account': {'available_hours': 80, 'hours_per_day': 8},
          'case_contracts': [
            {'id': 74, 'contract_no': 'SC-74', 'usable': true, 'md_remain_hours': 80, 'md_entitlement_hours': 80, 'md_hours_per_day': 8, 'available_hours': 80},
          ],
        },
        'GET /api/entity/case/15/manday-requests': {'list': [
          {'id': 1, 'status': 'Pending', 'requested_hours': '2.00', 'contract_id': 74},
        ]},
        'POST /api/entity/case/15/manday-requests': {'id': 2, 'email': {'sent': true}},
        'POST /api/entity/case/manday-requests/1/reject': {'released_hours': 2},
      },
    );
    expect(find.text('SC-74'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('manday-request')));
    await settle(tester, 4);
    await tester.enterText(find.byKey(const ValueKey('manday-hours')), '4');
    await tester.tap(find.byKey(const ValueKey('manday-submit')));
    await settle(tester, 6);
    final req = bodyOf(a.calls.lastWhere((c) => c.method == 'POST' && c.path.endsWith('/manday-requests')));
    expect(req['contract_id'], 74);
    expect(req['qty'], 4);
    expect(req['unit'], 'Hour');
    expect(req['notify_email'], 'qa@example.com');
    expect(req['send_sign_email'], true);
    expect(req['skip_email'], false);

    await tester.tap(find.byKey(const ValueKey('manday-reject-1')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const ValueKey('manday-reject-ok'))); // empty → stays
    await settle(tester, 2);
    expect(a.callKeys.where((k) => k.endsWith('/reject')), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('manday-reject-reason')), '[QA] เกินขอบเขต');
    await tester.pump(); // R66: the confirm turns on once a reason is typed
    await tester.tap(find.byKey(const ValueKey('manday-reject-ok')));
    await settle(tester, 4);
    expect(bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/reject')))['reason'], '[QA] เกินขอบเขต');
  });

  test('contract actions follow the server rules', () {
    expect(contractActions(const {'contract_status': 'Draft'}), ['submit_approval', 'start_implement', 'transfer', 'cancel']);
    expect(contractActions(const {'contract_status': 'Draft', 'requires_approval': 0}).first, 'activate');
    expect(contractActions(const {'contract_status': 'Pending_Approval'}), ['approve', 'reject', 'cancel']);
    expect(contractActions(const {'contract_status': 'Cancelled'}), isEmpty);
    expect(contractActions(const {'contract_status': 'Cancelled'}, admin: true), ['reactivate']);
  });

  testWidgets('contract status change goes through workflow-action (never a plain PUT)', (tester) async {
    late BuildContext ctx;
    final a = await pump(tester, Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    }), {
      'POST /api/entity/service_contract/74/workflow-action': {'record': {'id': 74, 'contract_status': 'Draft'}, 'allowed_actions': []},
    });
    String? result;
    final f = EntityRecordActions.changeStatus(ctx, module: 'service_contract', row: const {'id': 74, 'contract_status': 'Pending_Approval'}).then((v) => result = v);
    await settle(tester, 3);
    await tester.tap(find.byKey(const ValueKey('contract-action-reject')));
    await settle(tester, 3);
    await tester.enterText(find.byKey(const ValueKey('contract-reason')), '[QA] เอกสารไม่ครบ');
    await tester.pump(); // R66: the confirm turns on once a reason is typed
    await tester.tap(find.byKey(const ValueKey('contract-reason-ok')));
    await settle(tester, 4);
    await f;
    final body = bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/workflow-action')));
    expect(body['action'], 'reject');
    expect(body['reject_reason'], '[QA] เอกสารไม่ครบ');
    expect(a.calls.where((c) => c.method == 'PUT'), isEmpty);
    expect(result, 'Draft');
  });

  test('deal stage payload: probability + lost reason', () {
    expect(dealStagePayload('Negotiation'), {'deal_stage': 'Negotiation', 'probability': 80});
    expect(dealStagePayload(kDealClosedLost, lostReason: 'ราคา'), {'deal_stage': 'Closed Lost', 'probability': 0, 'closed_reason': 'ราคา'});
    expect(nextDealStage('Qualification'), 'Value Proposition');
    expect(nextDealStage('Negotiation'), kDealClosedWon);
    expect(nextDealStage(kDealClosedWon), isNull);
    expect(mandayHuman(10, 8), '1 วัน 2 ชม.');
  });
}
