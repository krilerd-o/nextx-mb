import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/approvals/approvals_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_record_actions.dart';
import 'package:nextx_mobile/screens/jobs/my_jobs_screen.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(FakeNextxAdapter, AppConfig)> _pump(WidgetTester tester, Widget home, Map<String, Object?> replies) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  final adapter = FakeNextxAdapter({'GET /api/settings/job': {'config': {}}, ...replies});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(
    accessToken: 't',
    userId: '2',
    businessId: '1',
    menusLoaded: true,
    menuKeys: ['job', 'quotation', 'activity', 'calendar', 'pending-approvals'],
  ));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: home))));
  await _frames(tester);
  return (adapter, config);
}

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('duplicate quotation = new quotation through /quotation/save (fresh status, no approval)', (tester) async {
    final (a, _) = await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => EntityRecordActions.duplicate(context, module: 'quotation', row: const {'id': 9}),
          child: const Text('dup'),
        ),
      ),
      {
        'GET /api/entity/quotation/9': {
          'id': 9,
          'quotation_no': 'QT-9',
          'quotation_status': 'ปิดการขาย',
          'outcome_result': 'Won',
          'approval_state': 'approved',
          'public_token': 'tok',
          'account_id': 31,
          'title_th': '[QA] R50 dup',
        },
        'GET /api/quotation/9/lines': {
          'list': [
            {'id': 1, 'quotation_id': 9, 'description': 'A', 'qty': 2, 'price': 100},
          ],
        },
        'POST /api/quotation/save': {'id': 55, 'created': true},
        'GET /api/entity/quotation/55': {'id': 55},
      },
    );
    await tester.tap(find.text('dup'));
    await _frames(tester);
    await tester.tap(find.text('ทำซ้ำ'));
    await _frames(tester);
    final b = _body(a, 'POST /api/quotation/save');
    expect(b.containsKey('id'), isFalse, reason: 'create, not update');
    final f = Map<String, dynamic>.from(b['fields'] as Map);
    expect(f['title_th'], '[QA] R50 dup');
    expect(f['account_id'], 31);
    for (final k in ['quotation_status', 'outcome_result', 'approval_state', 'public_token', 'quotation_no', 'id']) {
      expect(f.containsKey(k), isFalse, reason: '$k must not be copied');
    }
    final lines = (b['lines'] as List).cast<Map>();
    expect(lines.single.containsKey('id'), isFalse);
    expect(lines.single['qty'], 2);
    expect(a.callKeys, isNot(contains('POST /api/entity/quotation/9/duplicate')));
  });

  testWidgets('job PUT never sends evidence_photos (uploads in progress are kept)', (tester) async {
    final (a, config) = await _pump(tester, const SizedBox(), {'PUT /api/entity/job/9': {'id': 9}});
    await tester.runAsync(() => config.apiClient.putEntity('job', '9', {'job_name': 'x', 'evidence_photos': []}));
    final b = _body(a, 'PUT /api/entity/job/9');
    expect(b, {'job_name': 'x'});
  });

  testWidgets('approvals: inbox shows quotations, activities and jobs sent to me; job "รับงาน" accepts', (tester) async {
    final (a, _) = await _pump(tester, const ApprovalsScreen(), {
      'GET /api/approvals/inbox': {
        'quotations': [
          {'id': 9, 'quotation_no': 'QT-9', 'customer_name': 'ลูกค้า QA', 'grand_total': 1000, 'approval_level': 1},
        ],
        'activities': [
          {'id': 11, 'subject': '[QA] เยี่ยมลูกค้า'},
        ],
        'jobs': [
          {'id': 21, 'job_no': 'JOB-21', 'job_name': '[QA] ซ่อมแอร์'},
        ],
        'count': 3,
      },
      'POST /api/entity/job/21/workflow-action': {'job_id': 21, 'job_status': 'In Progress'},
    });
    await _frames(tester);
    expect(find.text('[QA] เยี่ยมลูกค้า'), findsOneWidget);
    expect(find.text('JOB-21 [QA] ซ่อมแอร์'), findsOneWidget);
    expect(find.text('งานที่ส่งถึงฉัน'), findsWidgets);
    await tester.tap(find.byTooltip('รับงาน'));
    await _frames(tester);
    expect(_body(a, 'POST /api/entity/job/21/workflow-action')['action'], 'accept');
  });

  testWidgets('my jobs: "รอคุณรับงาน" card with one-tap accept', (tester) async {
    final (a, _) = await _pump(tester, const MyJobsScreen(), {
      'GET /api/field-service/me/jobs': {'list': []},
      'GET /api/field-service/jobs/awaiting-me': {
        'list': [
          {'id': 31, 'job_no': 'JOB-31', 'job_name': '[QA] ติดตั้ง', 'customer_name': 'QA'},
        ],
      },
      'POST /api/entity/job/31/workflow-action': {'job_id': 31, 'job_status': 'In Progress'},
    });
    await _frames(tester);
    expect(find.byKey(const ValueKey('jobs-awaiting-me')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-31')));
    await _frames(tester);
    expect(_body(a, 'POST /api/entity/job/31/workflow-action')['action'], 'accept');
  });
}
