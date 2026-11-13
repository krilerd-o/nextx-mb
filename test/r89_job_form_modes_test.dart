import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/doc_form/barcode_scan_sheet.dart';
import 'package:nextx_mobile/screens/doc_form/doc_form_launcher.dart';

import 'support/doc_form_harness.dart';
import 'support/r89_job_fake.dart';

/// R89: create / edit / duplicate send what the web sends; the stepper,
/// the field fixes ("ประเภทงาน (เอกสาร)" …) and phone layouts.

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

Future<DocFormHarness> openJob(WidgetTester tester, {DocFormMode mode = DocFormMode.create, String? id, Size size = const Size(430, 2400), Map<String, Object?> extra = const {}}) async {
  final h = DocFormHarness(tester);
  await h.pump(opener(mode: mode, id: id), jobFakeReplies(extra: extra), menus: const ['job', 'case', 'service_contract', 'account', 'contact', 'asset'], size: size);
  installJobFakeServer(h.adapter);
  await h.tap(const ValueKey('open'));
  await h.settle();
  return h;
}

/// Create through every step: Request, urgent, PM, case 12, contact 72,
/// location 22, asset 31 in warranty, gate code, tomorrow 09:00 + 3 h,
/// owner 3, engineer 4, team, template 2.
Future<void> fillCreate(DocFormHarness h) async {
  await h.tap(const ValueKey('job-type-pick'));
  await h.tap(const ValueKey('jobtype-request'));
  await h.type('job_name', 'แอร์ไม่เย็น ห้องประชุม 3');
  await h.tap(const ValueKey('job-priority-Urgent'));
  await h.tap(const ValueKey('job-category-other'));
  await h.type('job_category_other', 'ย้ายเครื่อง');
  await h.tap(const ValueKey('job-case-pick'));
  await h.tap(const ValueKey('case-hit-12'), settleFrames: 10);
  await h.tap(const ValueKey('job-more-toggle'));
  await h.type('job_code', 'SIAM-7781');
  await h.tap(const ValueKey('docform-next'));

  await h.tap(const ValueKey('job-contact-pick'));
  await h.tap(const ValueKey('contact-hit-72'));
  await h.tap(const ValueKey('job-site-change'));
  await h.tap(const ValueKey('site-loc-22'));
  await h.tap(const ValueKey('job-asset-pick'));
  await h.tap(const ValueKey('asset-hit-31'));
  await h.tap(const ValueKey('job-in-warranty'));
  await h.type('cf_gate_code', '#4410');
  await h.tap(const ValueKey('docform-next'));

  await h.tap(const ValueKey('job-slot-tomorrow_am'));
  await h.tap(const ValueKey('job-dur-3'));
  await h.tap(const ValueKey('job-due-plan_end'));
  await h.tap(const ValueKey('job-owner-pick'));
  await h.tap(const ValueKey('tech-hit-3'));
  await h.tap(const ValueKey('job-engineer-pick'));
  await h.tap(const ValueKey('engineer-hit-4'));
  await h.type('assign_group', 'ทีมแอร์ A');
  await h.tap(const ValueKey('docform-next'));

  await h.type('description', 'ห้องประชุม 3 แอร์ไม่เย็น');
  await h.tap(const ValueKey('job-doc-toggle'));
  await h.tap(const ValueKey('job-layout-template2'));
  await h.tap(const ValueKey('job-template-pick'));
  await h.tap(const ValueKey('jobtpl-3'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    results.clear();
    DocFormHooks.reset();
  });

  group('the three modes', () {
    testWidgets('create: POST /api/entity/job with every step, no status / number; extras after', (tester) async {
      final h = await openJob(tester);
      await fillCreate(h);
      // Review with jump-to-edit links; the mode's own button.
      expect(h.textOf(const ValueKey('job-sum-contact')), 'วิชัย ศรีสุข');
      expect(h.textOf(const ValueKey('job-sum-site')), 'คลังสินค้าบางนา · 88 ถนนบางนา-ตราด กม.5 บางพลี สมุทรปราการ');
      final now = thaiNow();
      final t = DateTime(now.year, now.month, now.day + 1);
      expect(h.textOf(const ValueKey('job-sum-start')), endsWith('· 09:00–12:00'));
      expect(find.text('สร้างใบสั่งงาน'), findsWidgets);
      await h.tap(const ValueKey('job-review-edit-1'));
      expect(find.byKey(const ValueKey('job-customer-card')), findsOneWidget);
      await h.tap(const ValueKey('docform-step-3'));
      await h.tap(const ValueKey('docform-save'), settleFrames: 12);

      final b = h.body('POST', '/api/entity/job');
      expect(b.containsKey('id'), isFalse);
      expect([b['job_type'], b['job_name'], b['job_priority'], b['job_category'], b['job_category_other'], b['job_code']],
          ['request', 'แอร์ไม่เย็น ห้องประชุม 3', 'Urgent', 'other', 'ย้ายเครื่อง', 'SIAM-7781']);
      expect([b['related_case_id'], b['related_account_id'], b['related_contact_id'], b['customer_name'], b['customer_contact_name'], b['customer_mobile']],
          [12, 5, 72, 'บริษัท สยามเทค โซลูชั่น จำกัด', 'วิชัย ศรีสุข', '0812223333']);
      expect([b['related_location_id'], b['location_name_snapshot'], b['site_address_snapshot'], b['related_asset_id'], b['in_warranty'], b['cf_gate_code']],
          [22, 'คลังสินค้าบางนา', '88 ถนนบางนา-ตราด กม.5 บางพลี สมุทรปราการ', 31, true, '#4410']);
      expect([b['plan_start'], b['plan_end'], b['due_datetime']],
          [wallDateTime(DateTime(t.year, t.month, t.day, 9)), wallDateTime(DateTime(t.year, t.month, t.day, 12)), wallDateTime(DateTime(t.year, t.month, t.day, 12))]);
      expect([b['smownerid'], b['engineer_user_id'], b['engineer_name'], b['engineer_phone'], b['assign_group']], [3, 4, 'ช่างบอย ใจกล้า', '0844444444', 'ทีมแอร์ A']);
      expect([b['template_key'], b['job_template_id'], b['deliverable_template'], b['description']], ['template2', 3, 'request_report', 'ห้องประชุม 3 แอร์ไม่เย็น']);
      for (final k in ['job_status', 'job_no', 'actual_start', 'actual_end', 'evidence_photos', 'warranty_cycle_index', 'acknowledgement_note']) {
        expect(b.containsKey(k), isFalse, reason: k);
      }
      expect(results.single?['id'], '77');
    });

    testWidgets('edit: PUT /api/entity/job/1 with the form fields (cleared ones null), never status / sign-off', (tester) async {
      final h = await openJob(tester, mode: DocFormMode.edit, id: '1');
      expect(find.byKey(const ValueKey('job-edit-banner')), findsOneWidget);
      expect(find.text('JOB26-0001'), findsWidgets);
      // Links / people / place shown as cards from the saved ids.
      expect(find.byKey(const ValueKey('job-contract-card')), findsOneWidget);
      expect(find.text('SC-2026-004 · MA ระบบแอร์รายปี 2026'), findsOneWidget);
      await h.tap(const ValueKey('job-priority-Urgent'));
      await h.tap(const ValueKey('job-contract-clear'));
      await h.tap(const ValueKey('docform-step-1'));
      expect(h.textOf(const ValueKey('job-site-name')), 'สำนักงานใหญ่ อาคาร A');
      expect(find.byKey(const ValueKey('job-site-pinned')), findsOneWidget);
      expect(h.textOf(const ValueKey('job-asset-label')), 'แอร์ Daikin 24,000 BTU ห้องประชุม 3');
      await h.tap(const ValueKey('docform-step-2'));
      expect(h.textOf(const ValueKey('job-when-summary')), 'ศ. 20 พ.ย. 2569 · 09:00–12:00');
      expect(h.textOf(const ValueKey('job-owner-value')), 'ช่างเอก ทองดี');
      await h.tap(const ValueKey('job-dur-4'));
      expect(h.textOf(const ValueKey('job-when-summary')), 'ศ. 20 พ.ย. 2569 · 09:00–13:00');
      await h.tap(const ValueKey('docform-step-3'));
      expect(find.text('บันทึกการแก้ไข'), findsOneWidget);
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('PUT', '/api/entity/job/1');
      expect([b['job_priority'], b['related_contract_id'], b['plan_start'], b['plan_end'], b['smownerid'], b['engineer_user_id']],
          ['Urgent', null, '2026-11-20T09:00:00', '2026-11-20T13:00:00', 3, 4]);
      expect([b['job_category'], b['job_code'], b['in_warranty'], b['related_location_id'], b['related_asset_id'], b['template_key'], b['job_template_id']],
          ['pm', 'PO-SIAM-7781', true, 21, 31, 'template2', 2]);
      for (final k in ['job_status', 'job_no', 'actual_start', 'customer_signature', 'acknowledgement_note', 'warranty_cycle_index', 'related_activity_id']) {
        expect(b.containsKey(k), isFalse, reason: k);
      }
      expect(h.called('POST', '/api/entity/job'), isFalse);
    });

    testWidgets('duplicate: a new job (POST, no id), "(Copy)", owner = me, new plan; links / place / people kept', (tester) async {
      final h = await openJob(tester, mode: DocFormMode.duplicate, id: '1');
      expect(find.text('ทำซ้ำใบสั่งงาน'), findsOneWidget);
      expect(find.text('จาก JOB26-0001'), findsOneWidget);
      expect(find.byKey(const ValueKey('job-duplicate-banner')), findsOneWidget);
      await h.tap(const ValueKey('docform-step-2'));
      expect(h.textOf(const ValueKey('job-when-summary')), 'ยังไม่กำหนดเวลา');
      expect(h.textOf(const ValueKey('job-owner-value')), 'สมชาย ใจดี');
      await h.tap(const ValueKey('job-slot-tomorrow_pm'));
      await h.tap(const ValueKey('docform-step-3'));
      expect(find.text('สร้างจากสำเนา'), findsOneWidget);
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('POST', '/api/entity/job');
      expect(b.containsKey('id'), isFalse);
      expect([b['job_name'], b['smownerid'], b['engineer_user_id'], b['related_contract_id'], b['related_location_id'], b['job_category'], b['job_template_id'], b['in_warranty']],
          ['ล้างแอร์ประจำไตรมาส อาคาร A (Copy)', 1, 4, 4, 21, 'pm', 2, true]);
      expect(b['plan_start'], endsWith('T13:00:00'));
      for (final k in ['job_no', 'job_status', 'actual_start', 'customer_signature', 'related_activity_id', 'acknowledgement_note', 'warranty_cycle_index', 'due_datetime']) {
        expect(b.containsKey(k), isFalse, reason: k);
      }
      expect(h.called('PUT', '/api/entity/job/1'), isFalse);
    });
  });

  testWidgets('stepper: quiet at first, amber count for a step left with missing fields, green check when done; first missing field revealed', (tester) async {
    final h = await openJob(tester);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('docform-step-missing-$i')), findsNothing);
      expect(find.byKey(ValueKey('docform-step-done-$i')), findsNothing);
    }
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('docform-step-missing-0')), '1');
    expect(find.byKey(const ValueKey('docform-missing-banner')), findsOneWidget);
    await h.type('job_name', 'งาน');
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-step-done-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('docform-step-missing-1')), findsNothing, reason: 'the current step is not nagged before ถัดไป');
    // Back to step 1 leaves step 2 behind with its required business field.
    await h.tap(const ValueKey('docform-step-0'));
    expect(h.textOf(const ValueKey('docform-step-missing-1')), '1');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-missing-banner')), findsOneWidget);
    await h.type('cf_gate_code', '#1');
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('docform-next'));
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('docform-step-done-$i')), findsOneWidget, reason: 'step $i');
    }
    // A plan ending before it starts is flagged on เมื่อไร and opens the end field there.
    await h.tap(const ValueKey('docform-step-2'));
    await h.tap(const ValueKey('job-slot-tomorrow_am'));
    await h.tap(const ValueKey('job-dur-custom'));
    expect(find.byKey(const ValueKey('nx-field-plan_end')), findsOneWidget);
  });

  testWidgets('fields: no column notes as labels, job_category is ลักษณะงาน (report), report fields folded, rich text toolbar above the text', (tester) async {
    final fields = [
      for (final f in realJobFields) f['name'] == 'description' ? {...f, 'type': 'RichText'} : f,
    ];
    final h = await openJob(tester, mode: DocFormMode.edit, id: '1', extra: {
      'GET /api/fields/job': {'list': fields, 'picklists': realJobPicklists},
    });
    for (var step = 0; step < 4; step++) {
      await h.tap(ValueKey('docform-step-$step'));
      for (final bad in ['ประเภทงาน (เอกสาร)', 'ที่อยู่ไซต์ (snapshot)', 'ชื่อสถานที่ (snapshot)', 'มือถือลูกค้า', 'รหัสใบสั่งงาน', 'ตรวจประกันครั้งที่', 'หมายเหตุรับทราบ', 'ชื่อเซลล์']) {
        expect(find.textContaining(bad), findsNothing, reason: 'step $step: $bad');
      }
    }
    await h.tap(const ValueKey('docform-step-0'));
    expect(find.text('ลักษณะงาน'), findsOneWidget);
    expect(find.text('แสดงบนรายงานบริการ'), findsWidgets);
    expect(find.byKey(const ValueKey('job-category-pm')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-field-job_code')), findsNothing, reason: 'ข้อมูลเพิ่มเติม folded');
    await h.tap(const ValueKey('job-more-toggle'));
    expect(find.text('รหัสอ้างอิงงาน'), findsOneWidget);
    await h.tap(const ValueKey('docform-step-1'));
    expect(find.byType(Switch), findsOneWidget, reason: 'in_warranty is a switch, not a text box');
    await h.tap(const ValueKey('docform-step-3'));
    expect(find.byKey(const ValueKey('nx-field-problem_found')), findsNothing, reason: 'report fields folded');
    await h.tap(const ValueKey('job-report-toggle'));
    expect(find.byKey(const ValueKey('nx-field-problem_found')), findsOneWidget);
    final f = find.byKey(const ValueKey('nx-field-description'));
    Rect r(String k) => tester.getRect(find.descendant(of: f, matching: find.byKey(ValueKey(k))));
    expect(r('rte-bold').bottom, lessThanOrEqualTo(r('rte-field').top), reason: 'toolbar above the text');
  });

  testWidgets('autosave: a left form keeps a local draft and offers it back', (tester) async {
    final h = await openJob(tester);
    await h.type('job_name', 'ร่างงานค้าง');
    await h.tap(const ValueKey('docform-close'));
    await h.settle();
    expect(find.byKey(const ValueKey('open')), findsOneWidget);
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('docform-draft-resume')), findsOneWidget);
    await h.tap(const ValueKey('docform-draft-resume'));
    expect(find.text('ร่างงานค้าง'), findsWidgets);
  });

  group('no horizontal overflow on a phone', () {
    for (final (w, scale) in [(360.0, 1.0), (360.0, 1.3), (412.0, 1.3)]) {
      testWidgets('${w.toInt()} px · text ×$scale: every step and picker', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = await openJob(tester, size: Size(w, 780), mode: DocFormMode.edit, id: '1');
        // The stepper fits: the last step stays on screen.
        expect(tester.getRect(find.byKey(const ValueKey('docform-step-3'))).right, lessThanOrEqualTo(w));
        // Every screen is checked on its own (an overflow is reported as an exception).
        Future<void> tap(String key) async {
          await h.tap(ValueKey(key));
          expect(tester.takeException(), isNull, reason: 'after $key');
        }

        Future<void> picker(String open) async {
          await tap(open);
          await tap('picker-close');
        }

        await picker('job-type-pick');
        await tap('job-contract-change');
        await tap('picker-close');
        await picker('job-case-pick');
        await tap('job-more-toggle');
        await tap('docform-step-1');
        await picker('job-customer-change');
        await picker('job-contact-pick');
        await picker('job-site-change');
        await picker('job-asset-pick');
        await tap('job-contact-details-toggle');
        await tap('job-site-edit');
        await tap('docform-step-2');
        await picker('job-owner-pick');
        await tap('job-dur-custom');
        await tap('docform-step-3');
        await tap('job-doc-toggle');
        await tap('job-report-toggle');
        await tap('job-review-edit-0');
      });
    }
  });
}
