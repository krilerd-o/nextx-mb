import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/fsm/service_more.dart';
import 'package:nextx_mobile/screens/journey/case_flows.dart';
import 'package:nextx_mobile/screens/workspace/ws_bulk_change.dart';

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

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget home, Map<String, Object?> replies) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter(replies);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', businessRole: 'admin', menusLoaded: true, menuKeys: const ['case', 'service_contract', 'deal', 'job', 'workspace']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    await settle(tester, 6);
    return adapter;
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  const board14 = {'id': 14, 'name': '[QA] บอร์ด', 'code': 'QBA'};

  testWidgets('contract: Re-New previews then commits', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: ContractExtrasPanel(
            id: '74',
            canEdit: true,
            row: {'contract_no': 'SC-74', 'contract_status': 'Active', 'end_date': '2099-12-31', 'related_account_id': 3, 'contract_form': 'Direct'},
          ),
        ),
      ),
      {
        'GET /api/entity/service_contract/74/renewal-series': {'list': []},
        'POST /api/entity/service_contract/74/renew': {'defaults': {'start_date': '2027-11-01', 'end_date': '2028-10-31'}, 'next_version': 2, 'id': 75, 'contract_no': 'SC-75'},
        'GET /api/entity/service_contract/74/manday/transfer-preview': {
          'can_transfer': true,
          'account_id': 3,
          'account_name': '[QA] บริษัท',
          'account_hours_remain': 10,
          'contract': {'md_hours_per_day': 8, 'md_remain_hours': 80, 'available_hours': 80},
        },
        'POST /api/entity/service_contract/74/manday/transfer-to-account': {'hours': 2, 'contract_md_remain_hours': 78, 'account_hours_remain': 12},
      },
    );
    expect(find.byKey(const ValueKey('contract-renew')), findsOneWidget);
    expect(find.byKey(const ValueKey('contract-resend-sign')), findsNothing, reason: 'resend only while Pending_Approval');

    await tester.tap(find.byKey(const ValueKey('contract-renew')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('renew-ok')), findsOneWidget);
    final renews = a.calls.where((c) => c.method == 'POST' && c.path.endsWith('/renew')).toList();
    expect(renews, hasLength(1));
    expect(bodyOf(renews.first).containsKey('commit'), isFalse, reason: 'first call is a preview');
    await tester.tap(find.byKey(const ValueKey('renew-ok')));
    await settle(tester, 4);
    final commit = a.calls.where((c) => c.method == 'POST' && c.path.endsWith('/renew')).last;
    expect(bodyOf(commit)['commit'], 1);
    await drain(tester);
  });

  testWidgets('contract: Manday transfer sends hours to the account', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: ContractExtrasPanel(
            id: '74',
            canEdit: true,
            row: {'contract_no': 'SC-74', 'contract_status': 'Active', 'end_date': '2099-12-31', 'related_account_id': 3, 'contract_form': 'Direct'},
          ),
        ),
      ),
      {
        'GET /api/entity/service_contract/74/renewal-series': {'list': []},
        'GET /api/entity/service_contract/74/manday/transfer-preview': {
          'can_transfer': true,
          'account_id': 3,
          'account_name': '[QA] บริษัท',
          'account_hours_remain': 10,
          'contract': {'md_hours_per_day': 8, 'md_remain_hours': 80, 'available_hours': 80},
        },
        'POST /api/entity/service_contract/74/manday/transfer-to-account': {'hours': 2, 'contract_md_remain_hours': 78, 'account_hours_remain': 12},
      },
    );
    await tester.tap(find.byKey(const ValueKey('contract-transfer')));
    await settle(tester, 4);
    await tester.enterText(find.byKey(const ValueKey('transfer-hours')), '2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transfer-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transfer-ok')));
    await settle(tester, 4);
    final t = bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/transfer-to-account')));
    expect([t['qty'], t['unit'], t['account_id']], [2, 'Hour', 3]);
    expect(find.textContaining('โอนแล้ว'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('contract: resend sign link while Pending_Approval', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: ContractExtrasPanel(id: '75', canEdit: true, row: {'contract_no': 'SC-75', 'contract_status': 'Pending_Approval', 'contact_email': 'qa@example.com'}))),
      {
        'GET /api/entity/service_contract/75/renewal-series': {'list': []},
        'POST /api/entity/service_contract/75/resend-sign': {'sign_link': {'url': 'https://example.com/public/contract-sign/x'}},
      },
    );
    await tester.tap(find.byKey(const ValueKey('contract-resend-sign')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('resend-ok')));
    await settle(tester, 4);
    final b = bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/resend-sign')));
    expect(b['access_mode'], 'public');
    expect(b.containsKey('expires_preset'), isTrue);
    await drain(tester);
  });

  testWidgets('case: work from template and task on a board', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: CaseWorkspacePanel(caseId: '15', row: {'case_name': '[QA] เคส'}))),
      {
        'GET /api/case-work-templates': {'list': [{'id': 1, 'name': '[QA] งานบริการ', 'is_active': 1}]},
        'POST /api/entity/case/15/generate-work': {'created_count': 9, 'board_id': 16, 'board_name': 'งานบริการ'},
        'GET /api/boards': [board14],
        'POST /api/field-service/cases/15/workspace-task': {'board_id': 14, 'task_id': 383},
      },
    );
    await tester.tap(find.byKey(const ValueKey('case-work-template')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('case-tpl-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('case-tpl-ok')));
    await settle(tester, 4);
    final g = bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/generate-work')));
    expect(g['template_id'], 1);
    expect(g['board_id'], isNull, reason: 'no board picked = server default case board');
    expect(g['include_case_context'], isTrue);
    expect(find.byKey(const ValueKey('case-work-open-board')), findsOneWidget);
    await tester.tap(find.text('ปิด'));
    await settle(tester, 2);

    await tester.tap(find.byKey(const ValueKey('case-workspace-task')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('board-pick-14')));
    await settle(tester, 4);
    expect(bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/workspace-task')))['board_id'], 14);
    await drain(tester);
  });

  testWidgets('deal: Closed Won handoff creates a board with kickoff', (tester) async {
    final a = await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(onPressed: () => showDealWorkspaceHandoff(ctx, '7', afterWon: true), child: const Text('go')),
        ),
      ),
      {
        'GET /api/entity/deal/7/workspace': {'suggest_name': '[QA] ดีล', 'suggest_code': 'D1', 'is_closed_won': true},
        'POST /api/entity/deal/7/workspace': {'board_id': 17, 'board_name': '[QA] ดีล', 'created': true},
      },
    );
    await tester.tap(find.text('go'));
    await settle(tester, 4);
    expect(find.text('ภายหลัง'), findsOneWidget, reason: 'after Closed Won the user can skip');
    await tester.tap(find.byKey(const ValueKey('deal-ws-ok')));
    await settle(tester, 4);
    final b = bodyOf(a.calls.lastWhere((c) => c.method == 'POST' && c.path.endsWith('/deal/7/workspace')));
    expect([b['mode'], b['name'], b['code'], b['seed_kickoff']], ['create', '[QA] ดีล', 'D1', true]);
    await drain(tester);
  });

  testWidgets('workspace bulk: preview → job → undo', (tester) async {
    final a = await pump(
      tester,
      const WorkspaceBulkChangeScreen(items: [('task', '383'), ('task', '384')], boardId: '14'),
      {
        'POST /api/workspace/bulk/preview': {'operation': 'duplicate', 'total': 2, 'will_change': 2, 'skipped': 0, 'items': []},
        'POST /api/workspace/bulk/jobs': {'job_id': 'j1', 'total': 2},
        'GET /api/workspace/bulk/jobs/j1': {'id': 'j1', 'status': 'done', 'total': 2, 'done': 2, 'succeeded': 2, 'skipped': [], 'can_undo': true},
        'POST /api/workspace/bulk/jobs/j1/undo': {'id': 'j1', 'status': 'done', 'undo_failed': []},
      },
    );
    await tester.tap(find.byKey(const ValueKey('bulk-op-duplicate')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-preview')));
    await settle(tester, 4);
    final p = bodyOf(a.calls.lastWhere((c) => c.path.endsWith('/bulk/preview')));
    expect(p['operation'], 'duplicate');
    expect((p['items'] as List).length, 2);
    expect((p['options'] as Map)['scope'], 'children');
    await tester.ensureVisible(find.byKey(const ValueKey('bulk-run')));
    await tester.tap(find.byKey(const ValueKey('bulk-run')));
    await settle(tester, 6);
    await tester.pump(const Duration(milliseconds: 1300));
    await settle(tester, 6);
    expect(find.text('เสร็จแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-undo')));
    await settle(tester, 4);
    expect(a.calls.any((c) => c.method == 'POST' && c.path.endsWith('/jobs/j1/undo')), isTrue);
    expect(find.text('เลิกทำแล้ว'), findsOneWidget);
    await drain(tester);
  });

  test('case close: time spent parsing like the web (1d = 24h)', () {
    expect(CaseFlows.parseCaseMinutes('1h 30m'), 90);
    expect(CaseFlows.parseCaseMinutes('2h'), 120);
    expect(CaseFlows.parseCaseMinutes('1d'), 1440);
    expect(CaseFlows.parseCaseMinutes('45'), isNull, reason: 'needs a unit like the web');
    expect(CaseFlows.parseCaseMinutes('0'), 0);
    expect(CaseFlows.parseCaseMinutes('abc'), isNull);
    expect(CaseFlows.caseEstimateMinutes({'original_estimate_minutes': 60}), 60);
  });
}
