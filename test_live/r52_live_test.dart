// Manual tool: R52 against local NEXTX (nextx_qa) with [QA] records created by this run.
// QA_TOKEN_FILE=… flutter test test_live/r52_live_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/journey/case_flows.dart';
import 'package:nextx_mobile/screens/journey/quotation_versions.dart';
import 'package:nextx_mobile/services/api_client.dart';

void main() {
  testWidgets('R52 live', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
      final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
      final stamp = DateTime.now().millisecondsSinceEpoch;

      // ---- Quotation: create → revise with edited lines → compare → PDF variants.
      final saved = await api.saveQuotation(fields: {
        'title_th': '[QA] R52 ใบเสนอราคา $stamp',
        'valid_until': DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10),
      }, lines: [
        {'line_type': 'text', 'description': '[QA] กล้อง', 'qty': 4, 'quantity': 4, 'price': 2500, 'unit_price': 2500},
        {'line_type': 'text', 'description': '[QA] ค่าติดตั้ง', 'qty': 1, 'quantity': 1, 'price': 3000, 'unit_price': 3000},
      ]);
      final qt = '${saved['id']}';
      final src = await api.getEntity('quotation', qt);
      print('[qt] ${src['quotation_no']} total=${src['grand_total']}');
      final r = await api.reviseQuotationWith(qt, fields: {'title_th': '[QA] R52 ฉบับแก้ไข $stamp'}, lines: [
        {'line_no': 1, 'line_type': 'text', 'description': '[QA] กล้อง', 'quantity': 6, 'unit_price': 2400, 'discount_pct': 0},
        {'line_no': 2, 'line_type': 'text', 'description': '[QA] เครื่องบันทึก', 'quantity': 1, 'unit_price': 9000, 'discount_pct': 0},
      ], note: '[QA] เพิ่มกล้อง');
      print('[qt] revised → ${r['quotation_no']} (id ${r['id']})');
      final cmp = await api.compareQuotations(qt, '${r['id']}');
      final a = cmp['a'] as Map, b = cmp['b'] as Map;
      final diff = diffQuotationLines(extractMapList(a['lines']), extractMapList(b['lines']));
      print('[qt] compare: ${diff.map((d) => '${d.change.name}:${lineDescription(d.b ?? d.a!)}').join(', ')}');
      print('[qt] total ${(a['header'] as Map)['grand_total']} → ${(b['header'] as Map)['grand_total']}');
      expect(diff.map((d) => d.change), containsAll([LineChange.changed, LineChange.removed, LineChange.added]));
      for (final lang in ['th', 'en']) {
        for (final color in ['color', 'bw']) {
          final pdf = await api.getQuotationPdfVariant('${r['id']}', lang: lang, color: color);
          final head = String.fromCharCodes(pdf.take(5));
          print('[pdf] $lang/$color ${pdf.length} bytes $head');
          expect(head, '%PDF-');
        }
      }

      // ---- Approval inbox count.
      final inbox = await api.getApprovalInbox();
      print('[approvals] count=${inbox['count']}');

      // ---- Case: wait / resume / history / contacts.
      final c = await api.postEntity('case', {
        'case_name': '[QA] R52 เคส $stamp',
        'case_title': '[QA] R52 เคส $stamp',
        'case_priority': 'Medium',
        'case_type': 'Request',
      });
      final cid = '${c['id'] ?? (c['data'] is Map ? (c['data'] as Map)['id'] : '')}';
      await api.caseWorkflowAction(cid, {'action': 'accept', 'skip_email': true});
      await api.caseWorkflowAction(cid, {'action': 'wait', 'note': '[QA] รออะไหล่'});
      var row = await api.getEntity('case', cid);
      print('[case] after wait: ${row['case_status']} actions=${caseActions(row['case_status'])}');
      expect(caseActions(row['case_status']), contains('resume'));
      await api.caseWorkflowAction(cid, {'action': 'resume'});
      row = await api.getEntity('case', cid);
      print('[case] after resume: ${row['case_status']}');
      expect(classifyCaseStatus(row['case_status']), 'in_progress');
      final ev = await api.getCaseStatusEvents(cid);
      print('[case] history: ${ev.map((e) => '${e['action']}(${e['to_status']})').join(' ← ')}');
      expect(ev.first['action'], 'resume');
      final accounts = await api.getEntityList('account', limit: 5);
      if (accounts.items.isNotEmpty) {
        final contacts = await api.getAccountContacts('${accounts.items.first['id']}');
        print('[case] contacts of account ${accounts.items.first['id']}: ${contacts.length}');
      }
    });
  });
}
