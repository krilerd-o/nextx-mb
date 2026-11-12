// Manual tool: case workflow against local NEXTX (nextx_qa) with [QA] cases created for this run.
// QA_TOKEN_FILE=… QA_CASES="4 5" flutter test test_live/r51_case_live_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/journey/case_flows.dart';
import 'package:nextx_mobile/services/api_client.dart';

void main() {
  testWidgets('case workflow: preview → accept → close, cancel, wrong-state errors', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
      final ids = Platform.environment['QA_CASES']!.split(' ');
      final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
      final a = ids[0], b = ids[1];

      var c = await api.getEntity('case', a);
      print('[A] start status=${c['case_status']} → actions ${caseActions(c['case_status'])}');
      expect(classifyCaseStatus(c['case_status']), 'open');

      final pv = await api.previewCaseWorkflow(a, 'accept');
      print('[A] preview keys=${pv.keys.toList()} summaryTh=${'${pv['summaryTh']}'.split('\n').first}');

      // Close before accept → server refuses (400) with a Thai message the app shows.
      try {
        await api.caseWorkflowAction(a, {'action': 'close', 'skip_email': true});
        fail('close on open should fail');
      } catch (e) {
        print('[A] close-before-accept → ${caseErrorText(e)}');
      }

      await api.caseWorkflowAction(a, {'action': 'accept', 'skip_email': true, 'support_info': '[QA] รับเคสจากแอป'});
      c = await api.getEntity('case', a);
      print('[A] after accept status=${c['case_status']}');
      expect(classifyCaseStatus(c['case_status']), 'in_progress');

      await api.caseWorkflowAction(a, {'action': 'close', 'skip_email': true, 'case_description_closed': '<p>[QA] ปิดจากแอป</p>'});
      c = await api.getEntity('case', a);
      print('[A] after close status=${c['case_status']} desc=${c['case_description_closed']}');
      expect(classifyCaseStatus(c['case_status']), 'closed');

      final jobs = await api.getCaseOpenJobs(b);
      print('[B] open jobs=${jobs.length}');
      await api.caseWorkflowAction(b, {'action': 'cancel', 'reason': '[QA] ยกเลิกจากแอป'});
      c = await api.getEntity('case', b);
      print('[B] after cancel status=${c['case_status']}');
      expect(classifyCaseStatus(c['case_status']), 'cancelled');

      try {
        await api.caseWorkflowAction(b, {'action': 'accept', 'skip_email': true});
        fail('accept on cancelled should fail');
      } catch (e) {
        print('[B] accept-after-cancel → ${caseErrorText(e)}');
      }

      // Plain PUT does not change the status (why the old app "couldn't change status").
      try {
        await api.putEntity('case', b, {'case_status': 'เปิดเคส'});
      } catch (e) {
        print('[B] generic PUT refused → ${caseErrorText(e)}');
      }
      c = await api.getEntity('case', b);
      print('[B] after generic PUT status=${c['case_status']} (unchanged)');
    });
  });
}
