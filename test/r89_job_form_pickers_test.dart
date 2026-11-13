import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/doc_form/job_form_rules.dart';
import 'package:nextx_mobile/screens/doc_form/barcode_scan_sheet.dart';
import 'package:nextx_mobile/screens/doc_form/doc_form_launcher.dart';

import 'support/doc_form_harness.dart';
import 'support/r89_job_fake.dart';

/// R89: every lookup of the job form is its own search page with filters —
/// nothing is listed inside the form.

final List<Map<String, dynamic>?> results = [];

Widget opener({DocFormMode mode = DocFormMode.create, String? id}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => results.add(await openDocForm(context, module: 'job', mode: mode, id: id)),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<DocFormHarness> openJob(WidgetTester tester, {DocFormMode mode = DocFormMode.create, String? id}) async {
  final h = DocFormHarness(tester);
  await h.pump(opener(mode: mode, id: id), jobFakeReplies(), menus: const ['job', 'case', 'service_contract', 'account', 'contact', 'asset']);
  installJobFakeServer(h.adapter);
  await h.tap(const ValueKey('open'));
  await h.settle();
  return h;
}

Future<void> search(DocFormHarness h, String key, String text) async {
  await h.tester.enterText(find.byKey(ValueKey(key)), text);
  await h.tester.pump(const Duration(milliseconds: 350));
  await h.settle();
}

Map<String, dynamic> lastQuery(DocFormHarness h, String path) => h.adapter.calls.lastWhere((c) => c.path == path).queryParameters;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    results.clear();
    DocFormHooks.reset();
  });

  testWidgets('case picker: open / all statuses / mine filters, number · title · customer · status; linking fills the blanks', (tester) async {
    final h = await openJob(tester);
    expect(find.byKey(const ValueKey('case-search')), findsNothing, reason: 'no inline search');
    await h.tap(const ValueKey('job-case-pick'));
    expect(find.byKey(const ValueKey('case-picker')), findsOneWidget);
    expect(lastQuery(h, '/api/entity/case')['filter[case_status]'], kOpenCaseStatuses.join(','));
    for (final id in [12, 13, 15]) {
      expect(find.byKey(ValueKey('case-hit-$id')), findsOneWidget, reason: '$id open');
    }
    expect(find.byKey(const ValueKey('case-hit-14')), findsNothing, reason: 'closed case hidden by "เปิดอยู่"');
    expect(find.text('CS-0012 · แอร์ไม่เย็น ห้องประชุม 3'), findsOneWidget);
    expect(find.text('กำหนด 20/11/2569'), findsOneWidget);
    await h.tap(const ValueKey('case-chip-all'));
    expect(lastQuery(h, '/api/entity/case').containsKey('filter[case_status]'), isFalse);
    expect(find.byKey(const ValueKey('case-hit-14')), findsOneWidget);
    await h.tap(const ValueKey('case-chip-mine'));
    expect(lastQuery(h, '/api/entity/case')['filter[smownerid]'], '1');
    expect(find.byKey(const ValueKey('case-hit-13')), findsNothing, reason: 'owned by user 2');
    await search(h, 'case-search', 'ไฟดับ');
    expect(lastQuery(h, '/api/entity/case')['q'], 'ไฟดับ');
    expect(find.byKey(const ValueKey('case-hit-15')), findsOneWidget);
    expect(find.byKey(const ValueKey('case-hit-12')), findsNothing);
    await search(h, 'case-search', '');
    await h.tap(const ValueKey('case-hit-12'));
    // A compact card; customer / contact / due filled from the case (the typed name stays empty → case name).
    expect(find.byKey(const ValueKey('job-case-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-link-note')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'nothing covers the ถัดไป button');
    expect(find.text('Request — แอร์ไม่เย็น ห้องประชุม 3'), findsWidgets);
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('job-customer-card')), findsOneWidget);
    expect(h.textOf(const ValueKey('job-contact-value')), 'สมศรี ใจงาม');
    await h.tap(const ValueKey('docform-step-0'));
    // Unlink.
    await h.tap(const ValueKey('job-case-clear'));
    expect(find.byKey(const ValueKey('job-case-pick')), findsOneWidget);
  });

  testWidgets('contract picker: of this customer + active first; ใกล้หมดอายุ / all statuses; ไม่เชื่อม', (tester) async {
    final h = await openJob(tester);
    await h.tap(const ValueKey('docform-step-0'));
    await h.type('job_name', 'PM แอร์');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('job-customer-pick'));
    await search(h, 'customer-search', 'สยาม');
    expect(find.byKey(const ValueKey('customer-kind-lead')), findsNothing, reason: 'a job has no lead');
    await h.tap(const ValueKey('customer-hit-account-5'));
    await h.tap(const ValueKey('docform-step-0'));
    await h.tap(const ValueKey('job-contract-pick'));
    final q = lastQuery(h, '/api/entity/service_contract');
    expect([q['filter[contract_status]'], q['filter[related_account_id]']], ['Active', '5']);
    expect(find.byKey(const ValueKey('contract-hit-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('contract-hit-8')), findsNothing, reason: 'expired');
    expect(find.byKey(const ValueKey('contract-hit-9')), findsNothing, reason: 'another customer');
    await h.tap(const ValueKey('contract-chip-expiring'));
    expect(lastQuery(h, '/api/entity/service_contract')['filter[contract_due]'], 'expiring');
    expect(find.byKey(const ValueKey('contract-hit-4')), findsOneWidget);
    await h.tap(const ValueKey('contract-chip-all'));
    expect(find.byKey(const ValueKey('contract-hit-8')), findsOneWidget);
    expect(find.text('หมดอายุ'), findsOneWidget);
    await h.tap(const ValueKey('contract-chip-account'));
    expect(find.byKey(const ValueKey('contract-hit-9')), findsOneWidget, reason: 'all customers');
    await h.tap(const ValueKey('contract-hit-4'));
    expect(find.byKey(const ValueKey('job-contract-card')), findsOneWidget);
    expect(find.text('สิ้นสุด 5/12/2569'), findsOneWidget);
    await h.tap(const ValueKey('job-contract-change'));
    expect(find.byKey(const ValueKey('contract-none')), findsOneWidget);
    await h.tap(const ValueKey('contract-none'));
    expect(find.byKey(const ValueKey('job-contract-pick')), findsOneWidget);
  });

  testWidgets('contact: a picker row (of this customer, ไม่ระบุ) instead of a wall of chips', (tester) async {
    final h = await openJob(tester);
    await h.tap(const ValueKey('docform-next'));
    await h.type('job_name', 'x');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('job-customer-pick'));
    await h.tap(const ValueKey('customer-hit-account-5'));
    expect(find.byType(ChoiceChip), findsNothing, reason: 'no contact chips in the form');
    expect(find.text('เลือกจาก 2 คนของลูกค้านี้'), findsOneWidget);
    await h.tap(const ValueKey('job-contact-pick'));
    expect(find.byKey(const ValueKey('contact-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-hit-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-hit-73')), findsNothing, reason: 'another account');
    expect(find.text('ไม่มีชื่อผู้ติดต่อบนใบงาน'), findsOneWidget);
    await h.tap(const ValueKey('contact-hit-72'));
    expect(h.textOf(const ValueKey('job-contact-value')), 'วิชัย ศรีสุข');
    await h.tap(const ValueKey('job-contact-pick'));
    await h.tap(const ValueKey('contact-none'));
    expect(h.textOf(const ValueKey('job-contact-value')), 'ไม่ระบุ');
  });

  testWidgets('site picker: customer addresses, service locations (this customer / all), pin, Thai address page; asset picker', (tester) async {
    DocFormHooks.pickPin = (_) async => (lat: 13.7, lng: 100.6);
    DocFormHooks.reverseGeocode = (lat, lng) async => 'บางนา กรุงเทพมหานคร';
    final h = await openJob(tester);
    await h.tap(const ValueKey('docform-next'));
    await h.type('job_name', 'x');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('job-customer-pick'));
    await h.tap(const ValueKey('customer-hit-account-5'));
    await h.tap(const ValueKey('job-site-change'));
    expect(find.byKey(const ValueKey('site-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('site-account-0')), findsOneWidget);
    expect(lastQuery(h, '/api/entity/service_location')['filter[related_account_id]'], '5');
    expect(find.byKey(const ValueKey('site-loc-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('site-loc-23')), findsNothing);
    await h.tap(const ValueKey('site-chip-all'));
    expect(find.byKey(const ValueKey('site-loc-23')), findsOneWidget);
    await h.tap(const ValueKey('site-manual'));
    expect(find.byKey(const ValueKey('site-address-page')), findsOneWidget);
    await h.tester.pageBack();
    await h.settle();
    await h.tap(const ValueKey('site-loc-22'));
    expect(h.textOf(const ValueKey('job-site-name')), 'คลังสินค้าบางนา');
    expect(h.textOf(const ValueKey('job-site-address')), '88 ถนนบางนา-ตราด กม.5 บางพลี สมุทรปราการ');
    await h.tap(const ValueKey('job-site-pin'));
    expect(find.byKey(const ValueKey('job-site-pinned')), findsOneWidget);
    // Pin from the picker on a job without a site.
    await h.tap(const ValueKey('job-site-change'));
    await h.tap(const ValueKey('site-pin'));
    expect(h.textOf(const ValueKey('job-site-address')), 'บางนา กรุงเทพมหานคร');

    await h.tap(const ValueKey('job-asset-pick'));
    expect(lastQuery(h, '/api/entity/asset')['filter[related_account_id]'], '5');
    expect(find.byKey(const ValueKey('asset-hit-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-hit-33')), findsNothing);
    expect(find.text('S/N DK24-88812 · AS-0031 · บริษัท สยามเทค โซลูชั่น จำกัด'), findsOneWidget);
    await h.tap(const ValueKey('asset-hit-31'));
    expect(h.textOf(const ValueKey('job-asset-label')), 'แอร์ Daikin 24,000 BTU ห้องประชุม 3');
  });

  testWidgets('technician picker: skill match + who is free at the planned time; filters; recent picks', (tester) async {
    final h = await openJob(tester, mode: DocFormMode.edit, id: '1');
    await h.tap(const ValueKey('docform-step-2'));
    await h.tap(const ValueKey('job-owner-pick'));
    expect(find.byKey(const ValueKey('tech-picker')), findsOneWidget);
    expect(h.called('GET', '/api/field-service/jobs/1/match-users'), isTrue);
    final q = lastQuery(h, '/api/entity/activity');
    expect([q['calendar_from'], q['calendar_to']], ['2026-11-20', '2026-11-20']);
    expect(find.text('ช่วงงาน ศ. 20 พ.ย. 2569 · 09:00–12:00'), findsOneWidget);
    Text badge(String k) => tester.widget<Text>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text)));
    expect(badge('tech-skill-4').data, 'ตรงทักษะ 2/2');
    expect(badge('tech-skill-3').data, 'ตรงทักษะ 1/2');
    expect(badge('tech-avail-3').data, 'ชนเวลา 1 นัด');
    expect(badge('tech-avail-2').data, 'ว่างช่วงนี้', reason: 'a cancelled appointment does not count');
    expect(badge('tech-avail-4').data, 'ว่างช่วงนี้');
    // Best match first.
    final top4 = tester.getRect(find.byKey(const ValueKey('tech-hit-4'))).top;
    expect(top4, lessThan(tester.getRect(find.byKey(const ValueKey('tech-hit-3'))).top));
    expect(top4, lessThan(tester.getRect(find.byKey(const ValueKey('tech-hit-1'))).top));
    await h.tap(const ValueKey('tech-chip-free'));
    expect(find.byKey(const ValueKey('tech-hit-3')), findsNothing);
    await h.tap(const ValueKey('tech-chip-skill'));
    expect(find.byKey(const ValueKey('tech-hit-1')), findsNothing);
    expect(find.byKey(const ValueKey('tech-hit-3')), findsOneWidget);
    await h.tap(const ValueKey('tech-hit-4'));
    expect(h.textOf(const ValueKey('job-owner-value')), 'ช่างบอย ใจกล้า');
    final prefs = await h.prefsNow();
    expect(prefs['nx.docform.recent.technician.1'], contains('"id":"4"'));
    await h.tap(const ValueKey('job-owner-pick'));
    expect(find.byKey(const ValueKey('tech-recent-4')), findsOneWidget);
    await search(h, 'tech-search', 'วิภา');
    expect(find.byKey(const ValueKey('tech-hit-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('tech-hit-4')), findsNothing);
    await h.tap(const ValueKey('picker-close'));
    // The engineer picker can clear (ไม่ระบุ) and fills name + phone.
    await h.tap(const ValueKey('job-engineer-pick'));
    await h.tap(const ValueKey('engineer-hit-3'));
    expect(h.textOf(const ValueKey('job-engineer-value')), 'ช่างเอก ทองดี');
    expect(find.text('0833333333'), findsOneWidget);
  });

  testWidgets('job type: a picker with what each type means (no raw dropdown); the report follows the type', (tester) async {
    final h = await openJob(tester);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(h.textOf(const ValueKey('job-type-value')), 'Service Job');
    await h.tap(const ValueKey('job-type-pick'));
    expect(find.byKey(const ValueKey('jobtype-picker')), findsOneWidget);
    expect(find.text(kJobTypeHelp['request']!), findsOneWidget);
    await h.tap(const ValueKey('jobtype-request'));
    expect(h.textOf(const ValueKey('job-type-value')), 'Request Job');
    await h.tap(const ValueKey('docform-next'));
    await h.type('job_name', 'แจ้งซ่อม');
    await h.tap(const ValueKey('docform-next'));
    await h.type('cf_gate_code', '#1');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('job-doc-toggle'));
    expect(h.textOf(const ValueKey('job-deliverable-value')), 'ใบซ่อม / Request');
  });
}
