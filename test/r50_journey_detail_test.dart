import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<FakeNextxAdapter> _pump(WidgetTester tester, String module, Map<String, Object?> replies, {bool journey = true}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  final adapter = FakeNextxAdapter({
    'GET /api/entity/$module/9/comments': {'list': []},
    'GET /api/entity/$module/9/tags': {'list': []},
    'GET /api/tags': {'list': []},
    'GET /api/users': {
      'list': [
        {'user_id': 2, 'display_name': 'QA Me'},
        {'user_id': 5, 'display_name': 'QA Tech'},
      ],
    },
    'GET /api/fields/$module': {'list': [], 'picklists': {}},
    if (journey) 'GET /api/settings/job': {'config': {}},
    'GET /api/links/$module/9': {'quotations': [], 'jobs': [], 'activities': []},
    ...replies,
  });
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['job', 'quotation', 'activity']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(home: EntityDetailScreen(key: UniqueKey(), module: module, row: const {'id': 9})),
  ));
  await _frames(tester);
  return adapter;
}

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const job = {'id': 9, 'job_no': 'JOB-9', 'job_name': '[QA] R50 job', 'job_status': 'Open', 'smownerid': 2};
  final overview = {
    'job_id': 9,
    'job_status': 'Open',
    'has_owner': true,
    'can_accept': true,
    'activities': {'total': 0, 'open': 0, 'done': 0},
    'signatures': {'total': 1, 'signed': 0},
    'parts': 0,
  };

  testWidgets('older server (no Service Journey): the classic tabs, no Summary', (tester) async {
    await _pump(tester, 'job', {'GET /api/entity/job/9': job}, journey: false);
    expect(find.text('สรุป'), findsNothing);
    expect(find.text('ข้อมูล'), findsWidgets);
  });

  testWidgets('tablet: Summary on the left, other job tabs on the right', (tester) async {
    await _pump(tester, 'job', {
      'GET /api/entity/job/9': job,
      'GET /api/field-service/jobs/9/overview': overview,
      'GET /api/field-service/jobs/9/signatures': {'slots': []},
    });
    tester.view.physicalSize = const Size(1280, 1600);
    await _frames(tester);
    expect(find.byKey(const ValueKey('detail-wide')), findsOneWidget);
    final left = find.byKey(const ValueKey('detail-pane-left'));
    final right = find.byKey(const ValueKey('detail-pane-right'));
    expect(find.descendant(of: left, matching: find.byKey(const ValueKey('next-accept'))), findsOneWidget);
    expect(find.descendant(of: right, matching: find.text('ปฏิบัติงาน')), findsWidgets);
    expect(find.descendant(of: right, matching: find.text('สรุป')), findsNothing);
    // A KPI tile on the left switches the right pane.
    await tester.tap(find.byKey(const ValueKey('kpi-signatures')));
    await _frames(tester);
    expect(find.descendant(of: right, matching: find.text('ลายเซ็น')), findsWidgets);
  });

  testWidgets('job: Summary first; next step "accept" → sheet → workflow-action with expected status', (tester) async {
    final a = await _pump(tester, 'job', {
      'GET /api/entity/job/9': job,
      'GET /api/field-service/jobs/9/overview': overview,
      'GET /api/field-service/jobs/9/signatures': {'slots': []},
      'POST /api/entity/job/9/workflow-action': {'job_id': 9, 'action': 'accept', 'job_status': 'In Progress'},
    });
    expect(find.text('สรุป'), findsWidgets);
    expect(find.byKey(const ValueKey('next-accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi-signatures')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-action-accept')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    final b = _body(a, 'POST /api/entity/job/9/workflow-action');
    expect(b['action'], 'accept');
    expect(b['expected_status'], 'Open');
    expect(a.callKeys.where((k) => k == 'PUT /api/entity/job/9'), isEmpty, reason: 'status never goes through the generic PUT');
  });

  testWidgets('job: stage "ปิดงาน" opens the close dialog and lists missing signatures', (tester) async {
    final a = await _pump(tester, 'job', {
      'GET /api/entity/job/9': {...job, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/overview': {...overview, 'job_status': 'In Progress', 'can_close': true, 'activities': {'total': 2, 'open': 1, 'done': 1}},
      'GET /api/field-service/jobs/9/signatures': {
        'slots': [
          {'slot_key': 'customer', 'position_th': 'ลูกค้า', 'signature_path': null, 'signer_role': 'customer'},
        ],
      },
      'GET /api/field-service/jobs/9/close-preview': {'can_close': true, 'open_activities': 1},
      'POST /api/field-service/jobs/9/close': {'job_id': 9, 'job_status': 'Completed'},
    });
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.text('ลายเซ็นที่ยังขาด'), findsOneWidget);
    expect(find.byKey(const ValueKey('scope-job_and_activities')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    final b = _body(a, 'POST /api/field-service/jobs/9/close');
    expect(b['scope'], 'job_and_activities', reason: 'open activities → close them too by default');
    expect(b['expected_status'], 'In Progress');
  });

  const qt = {
    'id': 9,
    'quotation_no': 'QT-9',
    'quotation_status': 'อนุมัติใบเสนอราคา',
    'approval_state': 'approved',
    'offer_status': 'รอใบสั่งซื้อ',
    'grand_total': 12500,
  };
  final qtReplies = {
    'GET /api/quotation/9/approval-history': {'state': 'approved', 'steps': []},
    'GET /api/quotation/9/revisions': {'list': []},
    'GET /api/quotation/9/customer-activity': {'link_sent': true},
    'GET /api/quotation/9/lines': {
      'list': [
        {'id': 1, 'description': 'A', 'qty': 1, 'price': 12500},
      ],
    },
    'GET /api/settings/quotation': {'config': {'approval': {'required': false, 'levels': []}}},
  };

  testWidgets('quotation: next step "ปิดการขาย" → win / lose card → reason required → PUT outcome', (tester) async {
    final a = await _pump(tester, 'quotation', {
      'GET /api/entity/quotation/9': qt,
      ...qtReplies,
      'PUT /api/quotation/9/outcome': {'job_id': 77, 'job_created': true},
    });
    expect(find.byKey(const ValueKey('next-waiting_po')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi-total')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-action-close_sale')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('outcome-Won')));
    await _frames(tester, 4);
    final save = tester.widget<FilledButton>(find.byKey(const ValueKey('outcome-save')));
    expect(save.onPressed, isNull, reason: 'reason is required');
    await tester.tap(find.byKey(const ValueKey('outcome-reason-ราคาเหมาะสม')));
    await _frames(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('outcome-po')), 'PO-123');
    await tester.tap(find.byKey(const ValueKey('outcome-save')));
    await _frames(tester);
    final b = _body(a, 'PUT /api/quotation/9/outcome');
    expect(b['status'], 'Won');
    expect(b['reason'], 'ราคาเหมาะสม');
    expect(b['po_reference'], 'PO-123');
    expect(find.textContaining('สร้างใบสั่งงานให้แล้ว'), findsOneWidget);
  });

  testWidgets('quotation: offer bar step → PUT offer-status (not the generic PUT)', (tester) async {
    final a = await _pump(tester, 'quotation', {
      'GET /api/entity/quotation/9': {...qt, 'offer_status': 'เสนอราคา'},
      ...qtReplies,
      'PUT /api/quotation/9/offer-status': {'id': 9, 'offer_status': 'รอเปรียบเทียบ'},
    });
    await tester.ensureVisible(find.byKey(const ValueKey('offer-รอเปรียบเทียบ')));
    await tester.tap(find.byKey(const ValueKey('offer-รอเปรียบเทียบ')));
    await _frames(tester);
    expect(_body(a, 'PUT /api/quotation/9/offer-status')['offer_status'], 'รอเปรียบเทียบ');
    expect(a.callKeys.where((k) => k == 'PUT /api/entity/quotation/9'), isEmpty);
  });

  testWidgets('quotation: locked lines show the reason and Revise; submit approval sends levels', (tester) async {
    final a = await _pump(tester, 'quotation', {
      'GET /api/entity/quotation/9': {...qt, 'quotation_status': 'เปิดใบเสนอราคา', 'approval_state': 'none', 'offer_status': 'เสนอราคา'},
      ...qtReplies,
      'GET /api/settings/quotation': {
        'config': {
          'approval': {
            'required': true,
            'levels': [
              {'level': 1, 'enabled': true, 'label': 'หัวหน้า', 'mode': 'any', 'candidates': []},
            ],
          },
        },
      },
      'POST /api/quotation/9/approval/submit': {'ok': true},
    });
    expect(find.byKey(const ValueKey('next-submit_approval')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-action-submit_approval')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('approver-1-5')));
    await _frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('approval-submit')));
    await _frames(tester);
    final b = _body(a, 'POST /api/quotation/9/approval/submit');
    expect(b['levels'], [
      {
        'level': 1,
        'user_ids': [5],
      },
    ]);
  });
}
