import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/journey/case_flows.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
  });

  group('rules (same as the web)', () {
    test('classify: เปิดเคส is open, not closed', () {
      expect(classifyCaseStatus('เปิดเคส'), 'open');
      expect(classifyCaseStatus('ปิดเคส'), 'closed');
      expect(classifyCaseStatus('รอการตอบรับ'), 'waiting');
      expect(classifyCaseStatus('กำลังดำเนินการ'), 'in_progress');
      expect(classifyCaseStatus('ยกเลิก'), 'cancelled');
      expect(classifyCaseStatus(null), 'open');
    });
    test('allowed actions', () {
      expect(caseActions('เปิดเคส'), ['accept', 'forward', 'cancel']);
      expect(caseActions('รอการตอบรับ'), ['accept', 'resume', 'forward', 'cancel']);
      expect(caseActions('กำลังดำเนินการ'), ['close', 'wait', 'forward', 'cancel']);
      expect(caseActions('ปิดเคส'), isEmpty);
      expect(caseActions('ยกเลิก'), isEmpty);
      expect([caseStepAction(1), caseStepAction(2), caseStepAction(3), caseStepAction(0)], ['forward', 'accept', 'close', null]);
    });
  });

  Future<(FakeNextxAdapter, AppConfig)> pumpDetail(
    WidgetTester tester,
    Map<String, dynamic> row, {
    Map<String, int> statusFor = const {},
    Map<String, Object?> extra = const {},
    String role = 'member',
    String userId = '2',
  }) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/case/7': row,
      'GET /api/entity/case/7/comments': {'list': []},
      'GET /api/entity/case/7/tags': {'list': []},
      'GET /api/tags': {'list': []},
      'GET /api/fields/case': {'list': [], 'picklists': {}},
      'GET /api/entity/case/7/workflow-preview': {'summaryTh': '[QA] จะแจ้งลูกค้าว่ารับเคสแล้ว', 'to': '', 'cc': ''},
      'GET /api/field-service/cases/7/open-jobs': {'list': [
        {'id': 3, 'job_no': 'JOB-QA-3'},
      ]},
      'POST /api/entity/case/7/workflow-action': {'id': 7, 'case_status': 'กำลังดำเนินการ'},
      'GET /api/users': {'list': [
        {'user_id': 5, 'display_name': '[QA] ช่างเอ'},
      ]},
      ...extra,
    }, statusFor: statusFor);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(SessionState(accessToken: 't', userId: userId, businessId: '1', businessRole: role, menusLoaded: true, menuKeys: const ['case']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(home: EntityDetailScreen(module: 'case', row: const {'id': 7})),
    ));
    await settle(tester, 20);
    return (adapter, config);
  }

  Map<String, dynamic> lastBody(FakeNextxAdapter a) {
    final c = a.calls.lastWhere((x) => x.method == 'POST' && x.path.endsWith('/workflow-action'));
    final d = c.data;
    return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
  }

  const open = {'id': 7, 'case_no': 'CS-QA-7', 'case_title': '[QA] เคส R51', 'case_status': 'เปิดเคส', 'smownerid': 2};

  testWidgets('accept: window like the web → POST workflow-action (not PUT)', (tester) async {
    final (a, _) = await pumpDetail(tester, open);
    expect(find.byKey(const ValueKey('case-btn-accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('case-btn-close')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
    await settle(tester);
    expect(find.text('[QA] จะแจ้งลูกค้าว่ารับเคสแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    final b = lastBody(a);
    expect(b['action'], 'accept');
    expect(b['skip_email'], isTrue);
    expect(a.calls.where((x) => x.method == 'PUT'), isEmpty);
  });

  testWidgets('cancel: confirm text + cancel open jobs', (tester) async {
    final (a, _) = await pumpDetail(tester, open);
    await tester.tap(find.byKey(const ValueKey('case-btn-cancel')));
    await settle(tester);
    expect(find.textContaining('จะถูกปรับสถานะเป็นยกเลิก'), findsOneWidget);
    expect(find.byKey(const ValueKey('case-cancel-jobs')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    final b = lastBody(a);
    expect([b['action'], b['cancel_jobs']], ['cancel', true]);
  });

  testWidgets('close (in progress): description + time spent', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, 'case_status': 'กำลังดำเนินการ', 'original_estimate_minutes': 60});
    await tester.tap(find.byKey(const ValueKey('case-btn-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-time-spent')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('case-close-desc')), '[QA] แก้ไขเรียบร้อย');
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    final b = lastBody(a);
    expect(b['action'], 'close');
    expect(b['time_spent_minutes'], 60);
    expect(b['return_unused_manday'], isFalse);
    expect(b['case_description_closed'], contains('[QA] แก้ไขเรียบร้อย'));
  });

  testWidgets('read-only: clear warning, nothing sent', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, '_shared_permission': 'read_only'});
    await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-not-allowed')), findsOneWidget);
    expect(find.textContaining('ดูเคสนี้ได้อย่างเดียว'), findsOneWidget);
    expect(a.calls.where((x) => x.method == 'POST'), isEmpty);
  });

  testWidgets('forwarded to someone else: member cannot accept', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, 'case_status': 'รอการตอบรับ', 'smownerid': 9});
    await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
    await settle(tester);
    expect(find.textContaining('เฉพาะผู้รับผิดชอบปัจจุบันหรือผู้ดูแลระบบ'), findsOneWidget);
    expect(a.calls.where((x) => x.method == 'POST'), isEmpty);
  });

  testWidgets('server says 403 → friendly dialog, not a silent failure', (tester) async {
    await pumpDetail(tester, open, statusFor: {'POST /api/entity/case/7/workflow-action': 403}, extra: {});
    await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-not-allowed')), findsOneWidget);
    expect(find.textContaining('ติดต่อเจ้าของเคส'), findsOneWidget);
  });

  testWidgets('wait (พักเคส) with a quick reason, then resume', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, 'case_status': 'กำลังดำเนินการ'});
    await tester.tap(find.byKey(const ValueKey('case-btn-wait')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('case-wait-รอลูกค้าตอบกลับ')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    expect(lastBody(a), {'action': 'wait', 'note': 'รอลูกค้าตอบกลับ'});
  });

  testWidgets('resume from waiting', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, 'case_status': 'รอการตอบรับ', 'smownerid': 2});
    await tester.tap(find.byKey(const ValueKey('case-btn-resume')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    expect(lastBody(a), {'action': 'resume'});
  });

  testWidgets('accept: pick a customer contact → email filled + related_contact_id', (tester) async {
    final (a, _) = await pumpDetail(tester, {...open, 'related_account_id': 31}, extra: {
      'GET /api/entity/contact': {'list': [
        {'id': 41, 'contact_firstname': '[QA] สมชาย', 'contact_lastname': 'ทดสอบ', 'email_1st': 'qa.somchai@example.com'},
        {'id': 42, 'contact_firstname': '[QA] ไม่มีอีเมล'},
      ]},
    });
    await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('case-skip-email')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('case-contact-42')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('case-contact-41')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('case-flow-save')));
    await settle(tester);
    final b = lastBody(a);
    expect([b['email'], b['related_contact_id'], b['skip_email']], ['qa.somchai@example.com', 41, false]);
    final call = a.calls.firstWhere((c) => c.path == '/api/entity/contact');
    expect(call.queryParameters['filter[account_id_any]'], '31');
  });

  testWidgets('status history sheet', (tester) async {
    await pumpDetail(tester, open, extra: {
      'GET /api/entity/case/7/status-events': {'list': [
        {'action': 'wait', 'from_status': 'กำลังดำเนินการ', 'to_status': 'รอการตอบรับ', 'details': {'note': '[QA] รออะไหล่'}, 'at': '2026-11-11T03:00:00Z', 'user_name': '[QA] Second'},
        {'action': 'create', 'from_status': null, 'to_status': 'เปิดเคส', 'details': {}, 'at': '2026-11-10T03:00:00Z', 'user_name': '[QA] Second'},
      ]},
    });
    await tester.tap(find.byKey(const ValueKey('case-history-btn')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-history')), findsOneWidget);
    expect(find.text('พักเคส'), findsWidgets);
    expect(find.text('[QA] รออะไหล่'), findsOneWidget);
    expect(find.textContaining('11/11/'), findsOneWidget);
  });

  testWidgets('wide screen: record + info on the left, other tabs on the right', (tester) async {
    await pumpDetail(tester, open);
    tester.view.physicalSize = const Size(1280, 900);
    await settle(tester, 10);
    expect(find.byKey(const ValueKey('detail-wide')), findsOneWidget);
    final left = find.byKey(const ValueKey('detail-pane-left'));
    final right = find.byKey(const ValueKey('detail-pane-right'));
    expect(find.descendant(of: left, matching: find.byKey(const ValueKey('case-btn-accept'))), findsOneWidget);
    expect(find.descendant(of: left, matching: find.text('[QA] เคส R51')), findsWidgets);
    expect(find.descendant(of: right, matching: find.text('คอมเม้นท์')), findsOneWidget);
    expect(find.descendant(of: right, matching: find.text('ข้อมูล')), findsNothing);
    // Back to phone width: one column again.
    tester.view.physicalSize = const Size(420, 1600);
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('detail-wide')), findsNothing);
  });

  testWidgets('stepper: going back is explained; closed case has no buttons', (tester) async {
    await pumpDetail(tester, {...open, 'case_status': 'ปิดเคส'});
    expect(find.byKey(const ValueKey('case-btn-accept')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('step-เปิดเคส')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('step-เปิดเคส')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-not-allowed')), findsOneWidget);
  });
}

Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
