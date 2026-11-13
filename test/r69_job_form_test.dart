import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/doc_form/barcode_scan_sheet.dart';
import 'package:nextx_mobile/screens/doc_form/doc_form_launcher.dart';

import 'support/doc_form_harness.dart';

Map<String, dynamic> fld(String name, String type, {String section = 'main', bool required = false, String access = 'editable'}) =>
    {'name': name, 'type': type, 'section': section, 'required': required, 'access': access, 'presence': 1, 'label_th': name};

final jobFields = [
  fld('job_no', 'Counter'), fld('job_name', 'Text'), fld('job_type', 'Enum'), fld('job_status', 'Enum'), fld('job_priority', 'Enum'),
  fld('source', 'Enum'), fld('related_case_id', 'CaseSelect'), fld('related_contract_id', 'ContractSelect'), fld('related_asset_id', 'AssetSelect'),
  fld('related_location_id', 'LocationSelect'), fld('related_account_id', 'AccountSelect'), fld('related_contact_id', 'ContactSelect'),
  fld('customer_name', 'Text'), fld('plan_start', 'DateTime'), fld('plan_end', 'DateTime'), fld('due_datetime', 'DateTime'),
  fld('actual_start', 'DateTime'), fld('actual_end', 'DateTime'), fld('description', 'LongText'), fld('smownerid', 'PicklistUser'),
  fld('site_address_snapshot', 'Text'), fld('location_name_snapshot', 'Text'), fld('customer_contact_name', 'Text'),
  fld('customer_mobile', 'Phone'), fld('customer_email', 'Email'), fld('problem_found', 'Text'), fld('work_types', 'Text'),
  fld('cf_gate_code', 'Text', section: 'สถานที่หน้างาน', required: true),
];

Map<String, Object?> jobReplies() => {
      'GET /api/fields/job': {
        'list': jobFields,
        'picklists': {
          'job_type': [{'value': 'service', 'value_th': 'Service Job', 'is_default': 1}, {'value': 'request', 'value_th': 'Request Job'}],
          'job_priority': [{'value': 'Urgent', 'value_th': 'เร่งด่วน'}, {'value': 'High', 'value_th': 'สูง'}, {'value': 'Normal', 'value_th': 'ปกติ', 'is_default': 1}],
        },
      },
      'GET /api/field-service/job-form-context': {
        'layouts': {'allowed_layouts': ['template1'], 'default_layout': 'template1'},
        'templates': <Object>[],
        'document': {'new_defaults': <String, Object>{}},
      },
      'GET /api/settings/job/activity-templates': [
        {'id': 3, 'name': 'PM แอร์', 'items': [{'subject': 'ล้างแผง'}, {'subject': 'เช็คน้ำยา'}]},
      ],
      'GET /api/users': {'list': [{'id': 1, 'display_name': 'สมชาย ใจดี'}, {'id': 2, 'display_name': 'ช่างเอก', 'phone_mobile': '0822222222'}]},
      'GET /api/entity/account/5': {'id': 5, 'account_name': 'บริษัท เอ จำกัด', 'address_line1': '99 พระราม 9', 'address_district': 'ห้วยขวาง', 'address_province': 'กรุงเทพมหานคร', 'mobile_1st': '0811111111'},
      'GET /api/entity/contact': {'list': [{'id': 7, 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจงาม'}]},
      'GET /api/entity/contact/7': {'id': 7, 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจงาม', 'mobile_1st': '0899999999', 'account_id': 5},
      'POST /api/entity/job': {'id': 77, 'job_no': 'JOB-77'},
      'POST /api/field-service/jobs/77/generate-activities': {'created': 2},
      'POST /api/field-service/jobs/77/schedule': {'activity_id': 501},
      'POST /api/files/upload': {'files': [{'id': 9, 'url': '/uploads/a.jpg', 'storage_path': 'a.jpg', 'name': 'a.jpg'}]},
      'POST /api/entity/job/77/comments': {'id': 1},
    };

final List<Map<String, dynamic>?> results = [];

Widget opener({DocFormMode mode = DocFormMode.create, String? id, Map<String, dynamic>? prefill, ({String module, Map<String, dynamic> row})? parent}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => results.add(await openDocForm(context, module: 'job', mode: mode, id: id, initialValues: prefill, parent: parent)),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    results.clear();
    DocFormHooks.reset();
  });

  final kase = {
    'id': 12, 'case_no': 'CS-12', 'case_name': 'แอร์ไม่เย็น', 'case_priority': 'High', 'related_account_id': 5, 'related_contact_id': 7,
    'account_name': 'บริษัท เอ จำกัด', 'due_datetime': '2026-11-20 17:00:00', 'smownerid': 1,
  };

  testWidgets('from a case: pre-filled, the case shown as a locked card; contact / site / time by pickers and chips; created like the web', (tester) async {
    final h = DocFormHarness(tester);
    DocFormHooks.pickFiles = (_) async => [MultipartFile.fromBytes(utf8.encode('jpg'), filename: 'หน้างาน.jpg')];
    DocFormHooks.pickPin = (_) async => (lat: 13.75, lng: 100.5);
    DocFormHooks.reverseGeocode = (lat, lng) async => 'ถนนพระราม 9 ห้วยขวาง';
    await h.pump(opener(parent: (module: 'case', row: kase)), jobReplies());
    await h.tap(const ValueKey('open'));
    await h.settle();

    expect(find.byKey(const ValueKey('job-parent')), findsOneWidget);
    expect(find.text('สร้างจากเคส'), findsWidgets);
    expect(find.byKey(const ValueKey('job-case-card')), findsOneWidget, reason: 'the parent case as a card');
    expect(find.byKey(const ValueKey('job-case-change')), findsNothing, reason: 'the parent link is not changed here');
    expect(find.byKey(const ValueKey('nx-field-related_case_id')), findsNothing, reason: 'no raw relation field');
    expect(find.text('Request — แอร์ไม่เย็น'), findsWidgets);
    // Not in the form: status, actual times (check-in), JSON tick lists.
    for (final n in ['job_status', 'actual_start', 'actual_end', 'work_types']) {
      expect(find.byKey(ValueKey('nx-field-$n')), findsNothing, reason: n);
    }
    // Later steps are not nagged before the user gets there.
    expect(find.byKey(const ValueKey('docform-step-missing-1')), findsNothing);

    await h.tap(const ValueKey('docform-next'));
    // Customer from the case's account as a card; the contact is a picker row (no chip wall).
    expect(find.byKey(const ValueKey('job-customer-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-contact-7')), findsNothing);
    expect(h.textOf(const ValueKey('job-site-address')), '99 พระราม 9 ห้วยขวาง กรุงเทพมหานคร', reason: 'site address from the account');
    await h.tap(const ValueKey('job-contact-pick'));
    await h.tap(const ValueKey('contact-hit-7'));
    expect(h.textOf(const ValueKey('job-contact-value')), 'สมศรี ใจงาม');
    await h.tap(const ValueKey('job-site-pin'));
    expect(find.byKey(const ValueKey('job-site-pinned')), findsOneWidget);
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-missing-banner')), findsOneWidget, reason: 'gate code still missing');
    await h.type('cf_gate_code', '#1234');
    await h.tap(const ValueKey('docform-next'));

    await h.tap(const ValueKey('job-slot-tomorrow_am'));
    final now = thaiNow();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await h.tap(const ValueKey('job-dur-4'));
    await h.tap(const ValueKey('job-appointment'));
    await h.tap(const ValueKey('docform-next'));

    await h.tap(const ValueKey('job-checklist-tpl-3'));
    await h.tap(const ValueKey('job-attach'));
    expect(find.text('หน้างาน.jpg'), findsOneWidget);
    expect(h.textOf(const ValueKey('job-sum-customer')), 'บริษัท เอ จำกัด');
    expect(find.text('สร้างใบสั่งงาน'), findsWidgets);
    await h.tap(const ValueKey('docform-save'), settleFrames: 12);

    final b = h.body('POST', '/api/entity/job');
    expect([b['job_name'], b['job_type'], b['job_priority'], b['source'], b['related_case_id'], b['related_account_id'], b['related_contact_id']],
        ['Request — แอร์ไม่เย็น', 'request', 'High', 'case', 12, 5, 7]);
    expect([b['customer_name'], b['customer_contact_name'], b['customer_mobile'], b['cf_gate_code']], ['บริษัท เอ จำกัด', 'สมศรี ใจงาม', '0899999999', '#1234']);
    expect(b['plan_start'], wallDateTime(DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9)));
    expect(b['plan_end'], wallDateTime(DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13)));
    expect(b['site_address_snapshot'], '99 พระราม 9 ห้วยขวาง กรุงเทพมหานคร (13.750000,100.500000)', reason: 'the pin keeps the address and adds the coordinates');
    expect([b['due_datetime'], b['deliverable_template'], b['smownerid']], ['2026-11-20 17:00:00', 'request_report', 1]);
    for (final k in ['job_status', 'job_no', 'actual_start', 'actual_end']) {
      expect(b.containsKey(k), isFalse, reason: k);
    }
    expect(h.body('POST', '/api/field-service/jobs/77/generate-activities'), {'template_id': 3});
    expect(h.body('POST', '/api/field-service/jobs/77/schedule')['date_start'], b['plan_start']);
    expect(h.called('POST', '/api/files/upload'), isTrue);
    expect((h.body('POST', '/api/entity/job/77/comments')['attachments'] as List), isNotEmpty);
    expect(results.single?['id'], '77');
  });

  testWidgets('required per step: job name on งานอะไร; case / contract as picker rows; priority segments', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener(), jobReplies());
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('docform-step-missing-0')), findsNothing, reason: 'quiet until ถัดไป');
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('docform-step-missing-0')), '1', reason: 'job name');
    expect(find.text('ตั้งชื่องาน'), findsOneWidget);
    expect(find.byKey(const ValueKey('job-customer-pick')), findsNothing, reason: 'still on step 1');
    expect(find.byKey(const ValueKey('job-case-pick')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-contract-pick')), findsOneWidget);
    await h.type('job_name', 'ล้างแอร์ประจำปี');
    await h.tap(const ValueKey('job-priority-Urgent'));
    expect(find.byKey(const ValueKey('docform-step-missing-0')), findsNothing);
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('job-customer-pick')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-field-customer_name')), findsNothing, reason: 'typed customer only when asked');
    await h.tap(const ValueKey('job-customer-manual'));
    expect(find.byKey(const ValueKey('nx-field-customer_name')), findsOneWidget);
  });

  testWidgets('ทำซ้ำ: customer / place / details copied; owner = me (web); dates, status cleared', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener(mode: DocFormMode.duplicate, id: '1'), {
      ...jobReplies(),
      'GET /api/entity/job/1': {
        'id': 1, 'job_no': 'JOB-1', 'job_status': 'Completed', 'job_name': 'ล้างแอร์', 'job_type': 'service', 'related_account_id': 5,
        'customer_name': 'บริษัท เอ จำกัด', 'site_address_snapshot': 'อาคาร B ชั้น 3', 'description': 'ล้าง 3 เครื่อง', 'cf_gate_code': '#9',
        'plan_start': '2026-11-01 09:00:00', 'plan_end': '2026-11-01 11:00:00', 'actual_start': '2026-11-01 09:10:00', 'smownerid': 2,
        'customer_signature': 'sig.png', 'related_activity_id': 400,
      },
    });
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.text('ทำซ้ำใบสั่งงาน'), findsOneWidget);
    expect(find.byKey(const ValueKey('job-duplicate-banner')), findsOneWidget);
    expect(find.text('ล้างแอร์ (Copy)'), findsWidgets);
    await h.tap(const ValueKey('docform-step-3'));
    expect(h.textOf(const ValueKey('job-sum-start')), '—');
    expect(h.textOf(const ValueKey('job-sum-tech')), 'สมชาย ใจดี');
    expect(find.text('สร้างจากสำเนา'), findsOneWidget);
    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final b = h.body('POST', '/api/entity/job');
    expect([b['job_name'], b['related_account_id'], b['site_address_snapshot'], b['description'], b['cf_gate_code'], b['smownerid']],
        ['ล้างแอร์ (Copy)', 5, 'อาคาร B ชั้น 3', 'ล้าง 3 เครื่อง', '#9', 1]);
    for (final k in ['job_status', 'job_no', 'plan_start', 'plan_end', 'actual_start', 'customer_signature', 'id', 'related_activity_id']) {
      expect(b.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('edit: PUT with the form fields only; end before start is flagged on เมื่อไร', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener(mode: DocFormMode.edit, id: '1'), {
      ...jobReplies(),
      'GET /api/entity/job/1': {
        'id': 1, 'job_no': 'JOB-1', 'job_status': 'Open', 'job_name': 'ล้างแอร์', 'job_type': 'service', 'cf_gate_code': '#9',
        'plan_start': '2026-11-20T09:00:00', 'plan_end': '2026-11-20T08:00:00', 'smownerid': 2, 'related_activity_id': 400,
      },
      'PUT /api/entity/job/1': {'id': 1},
    });
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('job-edit-banner')), findsOneWidget);
    expect(h.textOf(const ValueKey('docform-step-missing-2')), '1');
    await h.tap(const ValueKey('docform-step-2'));
    expect(find.byKey(const ValueKey('job-appointment-done')), findsOneWidget);
    await h.tap(const ValueKey('job-dur-2'));
    expect(find.byKey(const ValueKey('docform-step-missing-2')), findsNothing);
    await h.tap(const ValueKey('docform-step-3'));
    expect(find.text('บันทึกการแก้ไข'), findsOneWidget);
    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final b = h.body('PUT', '/api/entity/job/1');
    expect([b['job_name'], b['plan_end'], b['smownerid']], ['ล้างแอร์', '2026-11-20T11:00:00', 2]);
    expect(b.containsKey('job_status'), isFalse);
    expect(h.called('POST', '/api/field-service/jobs/1/schedule'), isFalse);
  });
}
