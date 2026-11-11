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

  testWidgets('inspection detail opens on the checklist tab', (tester) async {
    await pump(tester, const EntityDetailScreen(module: 'inspection', row: {'id': '5', 'inspection_no': 'IN-5'}), {
      'GET /api/entity/inspection/5': {'id': 5, 'inspection_no': 'IN-5'},
      'GET /api/field-service/inspections/5/lines': {'list': [
        {'id': 1, 'line_no': 1, 'item_label': '[QA] ตรวจสภาพทั่วไป'},
      ]},
    });
    await settle(tester);
    expect(find.text('รายการตรวจ'), findsWidgets);
    expect(find.byType(InspectionLinesEditor), findsOneWidget);
    expect(find.text('[QA] ตรวจสภาพทั่วไป'), findsOneWidget);
  });
}
