// Manual tool: the app against a production-version NEXTX (main) on :4001 using nextx_qa,
// to prove new features degrade gracefully. QA_TOKEN_FILE=… flutter test test_live/r52_old_server_test.dart
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_record_actions.dart' show resetDuplicatedJob;
import 'package:nextx_mobile/screens/journey/case_flows.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/unread_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://127.0.0.1:4001';

void main() {
  final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  late String jobId;

  testWidgets('APIs on an older server', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final api = ApiClient()..attachSession(baseUrl: _base, accessToken: token, businessId: '1');
      ServiceJourney.debugClear();
      expect(await api.probeServiceJourney(), isFalse);
      print('[old] Service Journey: not available → classic screens');

      // Case workflow exists on production servers.
      final c = await api.postEntity('case', {'case_name': '[QA] R52 old $stamp', 'case_title': '[QA] R52 old $stamp', 'case_priority': 'Medium', 'case_type': 'Request'});
      final cid = '${c['id'] ?? (c['data'] is Map ? (c['data'] as Map)['id'] : '')}';
      for (final a in ['accept', 'wait', 'resume']) {
        await api.caseWorkflowAction(cid, {'action': a, 'skip_email': true});
      }
      await api.caseWorkflowAction(cid, {'action': 'close', 'skip_email': true, 'case_description_closed': '<p>[QA] ปิดบนเซิร์ฟเวอร์เดิม</p>'});
      final row = await api.getEntity('case', cid);
      print('[old] case accept→wait→resume→close: ${row['case_status']}');
      expect(classifyCaseStatus(row['case_status']), 'closed');
      final ev = await api.getCaseStatusEvents(cid);
      print('[old] case history events: ${ev.length}');

      // Approval badge: inbox missing → falls back without error.
      await PendingApprovals.instance.refresh(api, userId: '1');
      print('[old] approvals badge (fallback count): ${PendingApprovals.instance.count}');

      // PDF variant falls back to what the server has.
      final qts = await api.getEntityList('quotation', limit: 1);
      if (qts.items.isNotEmpty) {
        final pdf = await api.getQuotationPdfVariant('${qts.items.first['id']}', lang: 'en', color: 'bw');
        print('[old] quotation PDF ${pdf.length} bytes ${String.fromCharCodes(pdf.take(5))}');
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      }

      // Job duplicate: old server copies the status; the app puts it back to Open.
      final j = await api.postEntity('job', {'job_name': '[QA] R52 old job $stamp', 'job_status': 'In Progress'});
      final src = '${j['id'] ?? (j['data'] is Map ? (j['data'] as Map)['id'] : '')}';
      final dup = await api.duplicateEntity('job', src);
      final before = (await api.getEntity('job', dup))['job_status'];
      await resetDuplicatedJob(api, dup);
      final after = (await api.getEntity('job', dup))['job_status'];
      print('[old] job duplicate status: $before → $after');
      expect(after, 'Open');
      jobId = src;

      expect(notificationDeepLink('/modules/quotation/view/1', extra: 'quotation_approval'), '/crm/quotation/1?tab=approval');
    });
  });

  testWidgets('job detail on an older server = classic tabs, no crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = null;
    ServiceJourney.debugClear();
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    config.debugOverrideSession(SessionState(accessToken: token, userId: '1', businessId: '1', menusLoaded: true, menuKeys: const ['job']));
    await tester.runAsync(() => config.setApiBaseUrl(_base));
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: EntityDetailScreen(module: 'job', row: {'id': jobId}))));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('สรุป'), findsNothing);
    expect(find.text('ข้อมูล'), findsWidgets);
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((t) => t.isNotEmpty).take(25).toList();
    print('[old] visible: $texts');
    expect(find.textContaining('[QA] R52 old job'), findsWidgets);
    expect(find.textContaining('เข้าสู่ระบบ'), findsNothing);
    print('[old] job detail: classic tabs shown');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
