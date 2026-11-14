import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/journey_rules.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/approvals/approvals_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/journey/job_report_signatures.dart';
import 'package:nextx_mobile/widgets/nx_scroll_tabs.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _platformCalls = <MethodCall>[];

Future<FakeNextxAdapter> _pump(WidgetTester tester, Map<String, Object?> replies, {Size size = const Size(430, 2400), double textScale = 1, bool dark = false}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  _platformCalls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    _platformCalls.add(c);
    return null;
  });
  final adapter = FakeNextxAdapter({
    'GET /api/entity/job/9/comments': {'list': []},
    'GET /api/entity/job/9/tags': {'list': []},
    'GET /api/tags': {'list': []},
    'GET /api/users': {
      'list': [
        {'user_id': 2, 'display_name': 'QA Me'},
        {'user_id': 5, 'display_name': 'QA Tech'},
      ],
    },
    'GET /api/fields/job': {'list': [], 'picklists': {}},
    'GET /api/settings/job': {'config': {}},
    'GET /api/links/job/9': {'quotations': [], 'jobs': [], 'activities': []},
    'GET /api/field-service/jobs/9/signatures': {'slots': []},
    'GET /api/field-service/jobs/9/sla': {'policy': null, 'response_due': null, 'resolve_due': null, 'breached_response': false, 'breached_resolve': false},
    'GET /api/entity/activity': {'list': []},
    ...replies,
  });
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: 'QA Me', menusLoaded: true, menuKeys: ['job', 'quotation', 'activity', 'pending-approvals', 'inspection']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: EntityDetailScreen(key: UniqueKey(), module: 'job', row: const {'id': 9}),
    ),
  ));
  await _frames(tester);
  return adapter;
}

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await _frames(tester);
}

const _job = {
  'id': 9,
  'job_no': 'JOB-9',
  'job_name': '[QA] R73 job',
  'job_status': 'Open',
  'job_priority': 'Normal',
  'smownerid': 2,
  'customer_name': 'บริษัท ลูกค้า QA',
  'customer_contact_name': 'คุณสมหญิง',
  'customer_mobile': '081-234-5678',
  'customer_email': 'site@qa.test',
  'site_address_snapshot': '99 ถนนพระราม 9 กรุงเทพฯ',
};
final _overview = {
  'job_id': 9,
  'job_status': 'Open',
  'has_owner': true,
  'can_accept': true,
  'activities': {'total': 0, 'open': 0, 'done': 0},
  'signatures': {'total': 0, 'signed': 0},
  'parts': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stepper: "ยกเลิกงาน" is the last stage of the row (no chip line below)', (tester) async {
    final a = await _pump(tester, {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview});
    final ids = ['Open', 'Waiting', 'In Progress', 'Completed'];
    final rects = [for (final id in ids) tester.getRect(find.byKey(ValueKey('jstep-$id')))];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left), reason: '${ids[i]} after ${ids[i - 1]}');
      expect(rects[i].center.dy, closeTo(rects[0].center.dy, 1), reason: 'same row');
    }
    // "ยกเลิกงาน" is the red capsule pinned at the end of the same row.
    final stop = tester.getRect(find.byKey(const ValueKey('jstep-Cancelled')));
    final bar = tester.getRect(find.descendant(of: find.byKey(const ValueKey('journey-stages')), matching: find.byType(SingleChildScrollView)));
    expect(stop.left, greaterThan(bar.right));
    expect(stop.center.dy, closeTo(rects[0].center.dy, 1));
    expect(find.byKey(const ValueKey('journey-chip-cancel')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('jstep-Cancelled')), matching: find.text('ยกเลิกงาน')), findsOneWidget);
    // Tapping it opens the cancel window.
    await tester.drag(find.byKey(const ValueKey('journey-stages')), const Offset(-400, 0));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('jstep-Cancelled')));
    await _frames(tester);
    expect(find.text('เหตุผลที่ยกเลิก *'), findsOneWidget);
    expect(a.callKeys, isNot(contains('POST /api/entity/job/9/workflow-action')));
  });

  testWidgets('stepper: a cancelled job shows the terminal stage filled, no side chip', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'Cancelled', 'cancel_reason': 'ลูกค้ายกเลิก'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'Cancelled'},
    });
    expect(find.descendant(of: find.byKey(const ValueKey('jstep-Cancelled')), matching: find.text('ยกเลิก')), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-side-cancelled')), findsNothing);
  });

  testWidgets('tabs: ปฏิบัติงาน / กิจกรรม / ลายเซ็น merged into สรุป; other tabs stay', (tester) async {
    await _pump(tester, {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview});
    final labels = tester.widget<NxScrollTabs>(find.byType(NxScrollTabs).first).labels;
    expect(labels, containsAll(['สรุป', 'เอกสาร', 'ข้อมูล', 'ประวัติ']));
    expect(labels, isNot(contains('ปฏิบัติงาน')));
    expect(labels, isNot(contains('กิจกรรม')));
    expect(labels, isNot(contains('ลายเซ็น')));
    expect(labels.first, 'สรุป');
    // All the sections are on the one summary page ("งานสนาม" needs the
    // Workspace or Inspection menu — the harness user has Inspection).
    for (final k in ['next-accept', 'kpi-schedule', 'job-work-info', 'job-activities', 'journey-photo-camera', 'job-report-section', 'job-signatures-section', 'job-field-ops']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('next step card is slim: icon + title + hint + inline button, small secondary actions', (tester) async {
    await _pump(tester, {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview});
    final card = tester.getSize(find.byKey(const ValueKey('next-accept')));
    expect(card.height, lessThan(130), reason: 'compact card');
    final button = tester.getRect(find.byKey(const ValueKey('next-action-accept')));
    final title = tester.getRect(find.byKey(const ValueKey('next-title')));
    expect(button.center.dy, closeTo(title.center.dy, 24), reason: 'button inline with the title');
    expect(find.byKey(const ValueKey('next-secondary-forward')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-secondary-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-hint')), findsOneWidget);
  });

  testWidgets('รับงาน: "ส่งอีเมลแจ้งลูกค้า" starts unchecked → skip_email true', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': _job,
      'GET /api/field-service/jobs/9/overview': _overview,
      'POST /api/entity/job/9/workflow-action': {'job_id': 9, 'action': 'accept', 'job_status': 'In Progress'},
    });
    await tester.tap(find.byKey(const ValueKey('next-action-accept')));
    await _frames(tester);
    final box = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('journey-check')));
    expect(box.value, isFalse);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    final b = _body(a, 'POST /api/entity/job/9/workflow-action');
    expect(b['action'], 'accept');
    expect(b['skip_email'], isTrue);
  });

  testWidgets('KPI boxes นัดหมาย / ช่าง / กิจกรรมเสร็จ / ลายเซ็น have equal heights', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress', 'smownerid_name': 'ช่างสมชาย ใจดี ผู้มีชื่อยาวมากจริงๆ เพื่อทดสอบ'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress', 'activities': {'total': 3, 'open': 1, 'done': 2, 'next_at': '2026-11-20T02:00:00Z'}},
    });
    final hs = [for (final k in ['schedule', 'owner', 'activities', 'signatures']) tester.getSize(find.byKey(ValueKey('kpi-$k'))).height];
    expect(hs.toSet().length, 1, reason: 'heights $hs');
  });

  testWidgets('ปฏิบัติงาน: activities with Thai status, type, time, assignee, check-in/out; tap opens', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress', 'activities': {'total': 2, 'open': 1, 'done': 1}},
      'GET /api/links/job/9': {
        'quotations': [],
        'jobs': [],
        'activities': [
          {'id': 31, 'title': 'เข้าหน้างาน ติดตั้ง', 'subject': 'เข้าหน้างาน ติดตั้ง', 'activitytype': 'Visit', 'status': 'Completed', 'date_start': '2026-11-12T09:00:00.000Z'},
          {'id': 32, 'title': 'โทรนัดลูกค้า', 'subject': 'โทรนัดลูกค้า', 'activitytype': 'Call', 'status': 'In Progress', 'date_start': '2026-11-13T10:00:00.000Z'},
        ],
      },
      'GET /api/entity/activity': {
        'list': [
          {
            'id': 31,
            'subject': 'เข้าหน้างาน ติดตั้ง',
            'activitytype': 'Visit',
            'status': 'Completed',
            'date_start': '2026-11-12T09:00:00.000Z',
            'date_end': '2026-11-12T11:00:00.000Z',
            'checkindate': '2026-11-12T09:05:00.000Z',
            'checkoutdate': '2026-11-12T10:20:00.000Z',
            'smownerid': 5,
            'photos': [{}, {}, {}],
          },
        ],
      },
      'GET /api/entity/activity/31': {'id': 31, 'subject': 'เข้าหน้างาน ติดตั้ง', 'activitytype': 'Visit', 'status': 'Completed'},
      'GET /api/entity/activity/31/comments': {'list': []},
    });
    final list = find.byKey(const ValueKey('job-activities'));
    expect(find.descendant(of: list, matching: find.text('ปฏิบัติงาน (2)')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('job-act-status-31')), matching: find.text('เสร็จสิ้น')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('job-act-status-32')), matching: find.text('กำลังดำเนินการ')), findsOneWidget);
    expect(find.text('เข้า 09:05 · ออก 10:20 · 1 ชม. 15 นาที'), findsOneWidget);
    expect(find.textContaining('QA Tech'), findsOneWidget, reason: 'assignee name from the users list');
    expect(find.textContaining('12/11/2569 09:00–11:00'), findsOneWidget);
    expect(find.textContaining('Completed'), findsNothing, reason: 'no raw English status');
    // Newest first.
    expect(tester.getRect(find.byKey(const ValueKey('job-act-32'))).top, lessThan(tester.getRect(find.byKey(const ValueKey('job-act-31'))).top));
    await _tapKey(tester, 'job-act-31');
    expect(a.callKeys, contains('GET /api/entity/activity/31'));
  });

  testWidgets('job photos: gallery grid with count, slim add buttons, delete with confirm', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': {
        ..._job,
        'job_status': 'In Progress',
        'evidence_photos': [
          for (var i = 0; i < 3; i++) {'id': 'ph$i', 'path': 'job/9/p$i.jpg', 'name': 'p$i.jpg', 'mime': 'image/jpeg'},
        ],
      },
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
      'PUT /api/field-service/jobs/9/photos': {'photos': []},
    });
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('journey-photo-$i')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('journey-photo-count')), matching: find.text('3')), findsOneWidget);
    for (final k in ['camera', 'fast', 'gallery']) {
      expect(tester.getSize(find.byKey(ValueKey('journey-photo-$k'))).height, lessThan(60), reason: 'slim $k');
    }
    await tester.ensureVisible(find.byKey(const ValueKey('journey-photo-1')));
    await tester.longPress(find.byKey(const ValueKey('journey-photo-1')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('visit-photo-action-delete')));
    await _frames(tester);
    expect(find.text('รูปจะถูกลบออกจากใบสั่งงานนี้ และกู้คืนไม่ได้'), findsOneWidget);
    expect(a.callKeys, isNot(contains('PUT /api/field-service/jobs/9/photos')), reason: 'asks first');
    await tester.tap(find.byKey(const ValueKey('visit-photo-delete-confirm')));
    await _frames(tester);
    expect(_body(a, 'PUT /api/field-service/jobs/9/photos')['remove'], ['ph1']);
  });

  testWidgets('report: ＋Problem / Action Taken / Suggestions / Remark → card → autosave to the job fields', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress', 'customer_suggestion': 'ควรล้างแอร์ทุก 6 เดือน'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
      'PUT /api/entity/job/9': {'id': '9', 'message': 'Updated'},
    });
    for (final f in ['problem_found', 'work_performed', 'additional_remark']) {
      expect(find.byKey(ValueKey('outcome-chip-$f')), findsOneWidget, reason: f);
    }
    expect(find.text('Problem'), findsOneWidget);
    expect(find.text('Action Taken'), findsOneWidget);
    expect(find.text('Remark'), findsOneWidget);
    // A filled one shows as a card, not a chip.
    expect(find.byKey(const ValueKey('outcome-chip-customer_suggestion')), findsNothing);
    expect(find.byKey(const ValueKey('outcome-card-customer_suggestion')), findsOneWidget);
    expect(find.text('ควรล้างแอร์ทุก 6 เดือน'), findsOneWidget);

    await _tapKey(tester, 'outcome-chip-problem_found');
    expect(find.byKey(const ValueKey('outcome-editor-problem_found')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('outcome-field-problem_found')), 'คอมเพรสเซอร์ไม่ทำงาน');
    await tester.pump(const Duration(milliseconds: 900));
    await _frames(tester);
    expect(_body(a, 'PUT /api/entity/job/9'), {'problem_found': 'คอมเพรสเซอร์ไม่ทำงาน'});

    await _tapKey(tester, 'outcome-chip-work_performed');
    await tester.enterText(find.byKey(const ValueKey('outcome-field-work_performed')), 'เปลี่ยนคาปาซิเตอร์');
    await _tapKey(tester, 'outcome-done-work_performed');
    expect(_body(a, 'PUT /api/entity/job/9'), {'work_performed': 'เปลี่ยนคาปาซิเตอร์'});
  });

  testWidgets('signatures: two boxes ผู้ให้บริการ / ลูกค้า, equal size, image + name + date when signed', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {
        ..._job,
        'job_status': 'In Progress',
        'technician_signature': 'signatures/t.png',
        'technician_signed_by_name': 'ช่างสมชาย',
        'technician_signed_at': '2026-11-13T03:00:00.000Z',
      },
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
    });
    final t = find.byKey(const ValueKey('job-sig-box-technician'));
    final c = find.byKey(const ValueKey('job-sig-box-customer'));
    expect(t, findsOneWidget);
    expect(c, findsOneWidget);
    expect(tester.getSize(t), tester.getSize(c));
    expect(find.descendant(of: t, matching: find.text('ผู้ให้บริการ')), findsOneWidget);
    expect(find.descendant(of: t, matching: find.text('Serviced by')), findsOneWidget);
    expect(find.descendant(of: t, matching: find.byKey(const ValueKey('job-sig-image-technician'))), findsOneWidget);
    expect(find.descendant(of: t, matching: find.text('( ช่างสมชาย )')), findsOneWidget);
    expect(find.descendant(of: t, matching: find.text('วันที่ 13/11/2569 10:00')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('Customer accepted by')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('แตะเพื่อเซ็น')), findsOneWidget);
  });

  testWidgets('sign: full-screen page (rotation allowed, restored after) → upload PNG → PUT technician_* fields', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
      'POST /api/uploads/signature': {'path': 'signatures/sig_qa.png', 'url': '/uploads/signatures/sig_qa.png'},
      'PUT /api/entity/job/9': {'id': '9', 'message': 'Updated'},
    });
    await _tapKey(tester, 'job-sig-box-technician');
    expect(find.byKey(const ValueKey('job-sign-page')), findsOneWidget);
    final orient = _platformCalls.where((c) => c.method == 'SystemChrome.setPreferredOrientations').toList();
    expect(orient, isNotEmpty);
    expect(orient.last.arguments, containsAll(['DeviceOrientation.portraitUp', 'DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']));
    expect(find.text('เซ็นในกรอบนี้'), findsNothing, reason: 'painted, not a Text widget');
    // Name prefilled with me (technician).
    expect(tester.widget<TextField>(find.byKey(const ValueKey('job-sign-name'))).controller!.text, 'QA Me');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('job-sign-save'))).onPressed, isNull, reason: 'nothing drawn yet');
    final pad = tester.getRect(find.byKey(const ValueKey('job-sign-pad')));
    final g = await tester.startGesture(pad.center - const Offset(60, 0));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(10, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    // Undo removes the stroke; draw again.
    await tester.tap(find.byKey(const ValueKey('job-sign-undo')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('job-sign-save'))).onPressed, isNull);
    final g2 = await tester.startGesture(pad.center - const Offset(60, 0));
    for (var i = 0; i < 12; i++) {
      await g2.moveBy(const Offset(10, -2));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g2.up();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('job-sign-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await _frames(tester, 20);
    expect(find.byKey(const ValueKey('job-sign-page')), findsNothing);
    final restored = _platformCalls.where((c) => c.method == 'SystemChrome.setPreferredOrientations').last;
    expect(restored.arguments, isEmpty, reason: 'back to the app orientation');
    final up = a.calls.lastWhere((c) => c.path == '/api/uploads/signature');
    expect(up.data, isA<FormData>());
    expect((up.data as FormData).files.single.value.filename, 'job-9-technician.png');
    final b = _body(a, 'PUT /api/entity/job/9');
    expect(b['technician_signature'], 'signatures/sig_qa.png');
    expect(b['technician_signed_by_name'], 'QA Me');
    expect('${b['technician_signed_at']}', matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$')));
    expect(b.keys.where((k) => k.startsWith('customer_')), isEmpty);
  });

  testWidgets('sign: customer name prefilled from the job contact; landscape gives the pad the width', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
    });
    await _tapKey(tester, 'job-sig-box-customer');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('job-sign-name'))).controller!.text, 'คุณสมหญิง');
    tester.view.physicalSize = const Size(900, 420);
    await _frames(tester);
    final pad = tester.getSize(find.byKey(const ValueKey('job-sign-pad')));
    expect(pad.width, greaterThan(pad.height * 1.6));
    final name = tester.getRect(find.byKey(const ValueKey('job-sign-name')));
    final padRect = tester.getRect(find.byKey(const ValueKey('job-sign-pad')));
    expect(name.left, greaterThan(padRect.right), reason: 'name + save beside the pad in landscape');
  });

  testWidgets('close is blocked until both signatures exist: next-step hint + shortcut to sign', (tester) async {
    final a = await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress', 'customer_signature': 'signatures/c.png'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress', 'can_close': true, 'activities': {'total': 1, 'open': 0, 'done': 1}},
      'GET /api/field-service/jobs/9/close-preview': {'can_close': true, 'open_activities': 0},
    });
    expect(find.byKey(const ValueKey('next-report_signatures')), findsOneWidget);
    expect(find.text('ต้องมีลายเซ็น 2 รายการ (ผู้ให้บริการ + ลูกค้า) ก่อนปิดงาน'), findsOneWidget);
    expect(find.text('เก็บลายเซ็นก่อนปิดงาน (1/2)'), findsOneWidget);
    {
      final bar = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('journey-stages')), matching: find.byType(Scrollable))).position;
      bar.jumpTo(bar.maxScrollExtent); // the last step may be scrolled off on a narrow screen
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-technician')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-customer')), findsNothing, reason: 'customer already signed');
    expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/close')));
    expect(a.callKeys, isNot(contains('GET /api/field-service/jobs/9/close-preview')), reason: 'the close window never opens');
    await tester.tap(find.byKey(const ValueKey('job-close-sign-technician')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-sign-page')), findsOneWidget);
  });

  testWidgets('close goes on when both report signatures are there', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress', 'customer_signature': 'signatures/c.png', 'technician_signature': 'signatures/t.png'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress', 'can_close': true, 'activities': {'total': 1, 'open': 0, 'done': 1}},
      'GET /api/field-service/jobs/9/close-preview': {'can_close': true, 'open_activities': 0},
    });
    expect(find.byKey(const ValueKey('next-ready_to_close')), findsOneWidget);
    {
      final bar = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('journey-stages')), matching: find.byType(Scrollable))).position;
      bar.jumpTo(bar.maxScrollExtent); // the last step may be scrolled off on a narrow screen
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsNothing);
    expect(find.byKey(const ValueKey('scope-job_only')), findsOneWidget);
  });

  testWidgets('large text + dark: the whole summary lays out without overflow; next button drops under the title', (tester) async {
    await _pump(
      tester,
      {
        'GET /api/entity/job/9': {
          ..._job,
          'job_status': 'In Progress',
          'technician_signature': 'signatures/t.png',
          'technician_signed_by_name': 'ช่างสมชาย ใจดีมากๆ',
          'problem_found': 'ปัญหายาวมาก ' * 10,
        },
        'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress', 'activities': {'total': 1, 'open': 1, 'done': 0}},
        'GET /api/links/job/9': {
          'quotations': [],
          'jobs': [],
          'activities': [
            {'id': 31, 'subject': 'เข้าหน้างาน ติดตั้งระบบดับเพลิงชั้น 3 อาคาร B', 'activitytype': 'Visit', 'status': 'In Progress', 'date_start': '2026-11-12T09:00:00.000Z'},
          ],
        },
      },
      size: const Size(360, 5200),
      textScale: 1.6,
      dark: true,
    );
    expect(find.byKey(const ValueKey('job-signatures-section')), findsOneWidget);
    final button = tester.getRect(find.byKey(const ValueKey('next-action-open_activities')));
    final title = tester.getRect(find.byKey(const ValueKey('next-title')));
    expect(button.top, greaterThan(title.bottom - 1), reason: 'stacked at large text');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet: summary sections in the left pane, sign boxes side by side', (tester) async {
    await _pump(tester, {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview}, size: const Size(1280, 2400));
    final left = find.byKey(const ValueKey('detail-pane-left'));
    expect(find.descendant(of: left, matching: find.byKey(const ValueKey('job-report-section'))), findsOneWidget);
    final t = tester.getRect(find.byKey(const ValueKey('job-sig-box-technician')));
    final c = tester.getRect(find.byKey(const ValueKey('job-sig-box-customer')));
    expect(c.left, greaterThan(t.right - 1));
    expect(c.top, t.top);
    final hs = [for (final k in ['schedule', 'owner', 'activities', 'signatures']) tester.getRect(find.byKey(ValueKey('kpi-$k')))];
    expect(hs.map((r) => r.height).toSet().length, 1);
  });

  test('signature export: strokes trimmed and scaled to fill the report box', () async {
    final png = await exportSignaturePng([
      [const Offset(10, 10), const Offset(30, 14), const Offset(50, 12)],
      [const Offset(20, 20), const Offset(40, 22)],
    ]);
    expect(png, isNotNull);
    final codec = await ui.instantiateImageCodec(png!);
    final img = (await codec.getNextFrame()).image;
    expect(img.width, kSignExportSize.width.round());
    expect(img.height, kSignExportSize.height.round());
    final raw = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var minX = img.width, maxX = 0, minY = img.height, maxY = 0;
    for (var y = 0; y < img.height; y++) {
      for (var x = 0; x < img.width; x++) {
        if (raw.getUint8((y * img.width + x) * 4 + 3) > 0) {
          minX = x < minX ? x : minX;
          maxX = x > maxX ? x : maxX;
          minY = y < minY ? y : minY;
          maxY = y > maxY ? y : maxY;
        }
      }
    }
    final inkW = maxX - minX, inkH = maxY - minY;
    expect(inkW > img.width * 0.8 || inkH > img.height * 0.8, isTrue, reason: 'ink fills the box ($inkW x $inkH)');
    expect(raw.getUint8(3), 0, reason: 'transparent background');
  });

  test('job priority / type labels in Thai like the web', () {
    expect(jobPriorityLabel('Normal'), 'ปกติ');
    expect(jobPriorityLabel('Urgent'), 'เร่งด่วน');
    expect(jobPriorityLabel('High'), 'สูง');
    expect(jobPriorityLabel('Low'), 'ต่ำ');
    expect(jobPriorityLabel('Normal', options: const [{'value': 'Normal', 'value_th': 'ธรรมดา'}]), 'ธรรมดา');
    expect(jobPriorityLabel(null), '');
    expect(jobPickLabel('repair'), 'ซ่อมแซม');
  });

  testWidgets('work info: Thai priority pill, contact with call / e-mail, site with navigate, no empty SLA bar', (tester) async {
    await _pump(tester, {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview});
    final info = find.byKey(const ValueKey('job-work-info'));
    expect(find.descendant(of: find.byKey(const ValueKey('job-priority-pill')), matching: find.text('ปกติ')), findsOneWidget);
    expect(find.descendant(of: info, matching: find.text('Normal')), findsNothing);
    expect(find.byKey(const ValueKey('job-info-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-info-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-info-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-sla-chip')), findsNothing, reason: 'no SLA policy → no bar');
    expect(find.text('SLA'), findsNothing);
  });

  testWidgets('work info: SLA chip with the due time when the job has a policy', (tester) async {
    await _pump(tester, {
      'GET /api/entity/job/9': {..._job, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/overview': {..._overview, 'job_status': 'In Progress'},
      'GET /api/field-service/jobs/9/sla': {
        'policy': {'id': 1, 'name': 'มาตรฐาน', 'response_minutes': 60, 'resolve_minutes': 480},
        'response_due': '2020-01-01T01:00:00.000Z',
        'resolve_due': '2020-01-01T08:00:00.000Z',
        'breached_response': true,
        'breached_resolve': true,
      },
    });
    final chip = find.byKey(const ValueKey('job-sla-chip'));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.textContaining('SLA เกินกำหนดแก้ไข')), findsOneWidget);
  });

  testWidgets('approvals → งานที่ส่งถึงฉัน shows the job priority in Thai', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ServiceJourney.debugClear();
    final adapter = FakeNextxAdapter({
      'GET /api/settings/job': {'config': {}},
      'GET /api/approvals/inbox': {
        'quotations': [],
        'activities': [
          {'id': 11, 'subject': '[QA] เยี่ยมลูกค้า', 'activitytype': 'Visit', 'date_start': '2026-11-12T14:00:00.000Z'},
        ],
        'jobs': [
          {'id': 21, 'job_no': 'JOB-21', 'job_name': '[QA] ซ่อมแอร์', 'customer_name': 'ลูกค้า QA', 'job_priority': 'Normal'},
        ],
        'count': 2,
      },
    });
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['job', 'activity', 'pending-approvals']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: Scaffold(body: ApprovalsScreen()))));
    await _frames(tester, 20);
    expect(find.text('ลูกค้า QA · ปกติ'), findsOneWidget);
    expect(find.textContaining('Normal'), findsNothing);
    expect(find.textContaining('เข้าพบลูกค้า · 12/11/2569 14:00'), findsOneWidget);
    expect(find.textContaining('Visit'), findsNothing);
  });
}
