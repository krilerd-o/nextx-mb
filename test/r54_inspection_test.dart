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
import 'package:nextx_mobile/screens/fsm/inspection_lines.dart';
import 'package:nextx_mobile/screens/fsm/inspection_summary.dart';
import 'package:nextx_mobile/screens/jobs/job_inspection_screen.dart';

import 'support/fake_api.dart';

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
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['job', 'inspection']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    await settle(tester, 6);
    return adapter;
  }

  List<dynamic> lastPut(FakeNextxAdapter a) {
    final c = a.calls.lastWhere((c) => c.method == 'PUT');
    final d = c.data is String ? jsonDecode(c.data as String) : c.data;
    return (d as Map)['lines'] as List;
  }

  testWidgets('add a line from the box → shows in the list and saves automatically', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: InspectionLinesEditor(inspectionId: '7', showPdf: false))),
      {
        'GET /api/field-service/inspections/7/lines': {'list': [
          {'id': 1, 'line_no': 1, 'item_label': '[QA] ตรวจสภาพทั่วไป', 'item_result': 'pass'},
        ]},
        'PUT /api/field-service/inspections/7/lines': {'list': []},
      },
    );
    expect(find.text('รายการตรวจ (1)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('insp-add-field')), '[QA] ตรวจแรงดันน้ำยา');
    await tester.tap(find.byKey(const ValueKey('insp-add-btn')));
    await settle(tester);
    expect(find.text('[QA] ตรวจแรงดันน้ำยา'), findsOneWidget);
    expect(find.text('รายการตรวจ (2)'), findsOneWidget);
    final lines = lastPut(a);
    expect(lines.map((l) => l['item_label']), ['[QA] ตรวจสภาพทั่วไป', '[QA] ตรวจแรงดันน้ำยา']);
    expect(find.byKey(const ValueKey('insp-saved')), findsOneWidget);

    // Result buttons.
    await tester.tap(find.byKey(const ValueKey('insp-1-fail')));
    await settle(tester);
    expect(lastPut(a)[1]['item_result'], 'fail');
    expect(find.text('ไม่ผ่าน 1'), findsOneWidget);
  });

  testWidgets('empty → ready-made set adds its items', (tester) async {
    final a = await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: InspectionLinesEditor(inspectionId: '7', showPdf: false))),
      {
        'GET /api/field-service/inspections/7/lines': {'list': []},
        'PUT /api/field-service/inspections/7/lines': {'list': []},
      },
    );
    expect(find.byKey(const ValueKey('insp-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('insp-preset-งานซ่อม')));
    await settle(tester);
    expect(lastPut(a).length, 5);
    expect(find.text('วินิจฉัยสาเหตุ'), findsOneWidget);
  });

  testWidgets('job → no inspection yet → create → checklist appears', (tester) async {
    var created = false;
    final replies = <String, Object?>{
      'GET /api/entity/inspection': {'list': []},
      'POST /api/field-service/jobs/19/inspection': {'id': 3, 'inspection_no': 'INSP-3'},
      'GET /api/field-service/inspections/3/lines': {'list': [
        {'id': 1, 'line_no': 1, 'item_label': 'ตรวจสภาพทั่วไป'},
      ]},
    };
    final a = await pump(tester, const JobInspectionScreen(job: {'id': 19, 'job_no': 'JOB-19', 'job_name': '[QA] งาน'}), replies);
    expect(find.byKey(const ValueKey('job-insp-empty')), findsOneWidget);
    a.onRequest = (o) {
      if (o.method == 'POST') created = true;
      if (created && o.path == '/api/entity/inspection') {
        replies['GET /api/entity/inspection'] = {'list': [
          {'id': 3, 'inspection_no': 'INSP-3', 'related_job_id': 19},
        ]};
      }
    };
    await tester.tap(find.byKey(const ValueKey('job-insp-create')));
    await settle(tester, 14);
    expect(find.byKey(const ValueKey('insp-editor')), findsOneWidget);
    expect(find.text('ตรวจสภาพทั่วไป'), findsOneWidget);
    final list = a.calls.firstWhere((c) => c.path == '/api/entity/inspection');
    expect(list.queryParameters['filter[related_job_id]'], '19');
  });

  testWidgets('inspection detail opens on the summary tab; checklist is next', (tester) async {
    await pump(tester, const EntityDetailScreen(module: 'inspection', row: {'id': '5', 'inspection_no': 'IN-5'}), {
      'GET /api/entity/inspection/5': {'id': 5, 'inspection_no': 'IN-5'},
      'GET /api/field-service/inspections/5/lines': {'list': [
        {'id': 1, 'line_no': 1, 'item_label': '[QA] ตรวจสภาพทั่วไป'},
      ]},
    });
    await settle(tester);
    expect(find.byType(InspectionSummary), findsOneWidget);
    expect(find.text('รายการตรวจ'), findsWidgets);
    // Next step = continue checking → opens the checklist tab.
    await tester.ensureVisible(find.byKey(const ValueKey('insp-sum-next')));
    await tester.tap(find.byKey(const ValueKey('insp-sum-next')));
    await settle(tester);
    expect(find.byType(InspectionLinesEditor), findsOneWidget);
    expect(find.text('[QA] ตรวจสภาพทั่วไป'), findsOneWidget);
  });

  testWidgets('summary: ring, counts, verdict, failed items and links', (tester) async {
    final opened = <String>[];
    final tabs = <String>[];
    await pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: InspectionSummary(
            row: const {'id': 5, 'inspection_no': 'IN-5', 'inspection_name': '[QA] ตรวจรับแอร์', 'inspection_status': 'Draft', 'related_job_id': 19, 'related_job_id_name': 'JOB-19 [QA]', 'customer_name': '[QA] ลูกค้า', 'technician_signature': 'x.png'},
            canEdit: true,
            onGoTab: tabs.add,
            onOpen: (m, id) => opened.add('$m:$id'),
            onChangeStatus: () => tabs.add('status'),
          ),
        ),
      ),
      {
        'GET /api/field-service/inspections/5/lines': {'list': [
          {'id': 1, 'item_label': '[QA] ตรวจสภาพ', 'item_result': 'pass'},
          {'id': 2, 'item_label': '[QA] แรงดันน้ำยา', 'item_result': 'fail', 'remark': '[QA] ต่ำกว่าเกณฑ์'},
          {'id': 3, 'item_label': '[QA] ทำความสะอาด', 'item_result': 'na'},
          {'id': 4, 'item_label': '[QA] ทดสอบ', 'item_result': 'pass'},
        ]},
      },
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);
    expect(find.text('ไม่ผ่าน 1 รายการ'), findsOneWidget);
    expect(find.byKey(const ValueKey('insp-sum-failed')), findsOneWidget);
    expect(find.text('[QA] ต่ำกว่าเกณฑ์'), findsOneWidget);
    expect(find.text('JOB-19 [QA]'), findsOneWidget);
    expect(find.text('เซ็นแล้ว'), findsOneWidget);
    expect(find.text('ยังไม่เซ็น'), findsOneWidget);
    // All checked → next step saves the inspection status.
    await tester.tap(find.byKey(const ValueKey('insp-sum-next')));
    expect(tabs, ['status']);
    await tester.ensureVisible(find.byKey(const ValueKey('insp-sum-job')));
    await tester.tap(find.byKey(const ValueKey('insp-sum-job')));
    expect(opened, ['job:19']);
    await tester.tap(find.byKey(const ValueKey('insp-sum-count-fail')));
    expect(tabs.last, 'checklist');
  });

  test('verdict from the checklist', () {
    expect(inspVerdict(InspCounts.of(const [])), InspVerdict.empty);
    expect(inspVerdict(InspCounts.of(const [{'item_result': 'pass'}, {'item_result': null}])), InspVerdict.inProgress);
    expect(inspVerdict(InspCounts.of(const [{'item_result': 'pass'}, {'item_result': 'na'}])), InspVerdict.passed);
    expect(inspVerdict(InspCounts.of(const [{'item_result': 'pass'}, {'item_result': 'fail'}])), InspVerdict.failed);
  });
}
