// R78 — job close follows the server setting close.require_both_signatures
// (NEXTX 43709562): off → the app does not block; on → block until the
// technician + customer signatures exist (a signed staff / customer slot
// counts, like the server); a 409 JOB_SIGNATURES_REQUIRED from any close path
// shows a friendly sheet with "เซ็นตอนนี้" + a way to the signature section.
import 'dart:convert';

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
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/deep_link_loaders.dart';
import 'package:nextx_mobile/screens/journey/job_report_signatures.dart';
import 'package:nextx_mobile/screens/journey/status_followups.dart';
import 'package:nextx_mobile/services/api_exceptions.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _job = {
  'id': 9,
  'job_no': 'JOB-9',
  'job_name': '[QA] R78 job',
  'job_status': 'In Progress',
  'job_priority': 'Normal',
  'smownerid': 2,
  'customer_name': 'บริษัท ลูกค้า QA',
  'customer_contact_name': 'คุณสมหญิง',
};
final _overview = {
  'job_id': 9,
  'job_status': 'In Progress',
  'has_owner': true,
  'can_accept': true,
  'can_close': true,
  'activities': {'total': 1, 'open': 0, 'done': 1},
  'signatures': {'total': 0, 'signed': 0},
  'parts': 0,
};

const _settingOff = {
  'config': {
    'close': {'require_signatures': false, 'require_both_signatures': false},
  },
};

const _err409 = {
  'error_code': 'JOB_SIGNATURES_REQUIRED',
  'message': 'ต้องมีลายเซ็นทั้งช่างและลูกค้าก่อนปิดงาน — ยังขาด: ลายเซ็นลูกค้า',
  'details': {
    'missing': ['customer_signature'],
    'required': ['technician_signature', 'customer_signature'],
    'labels': {
      'th': ['ลายเซ็นลูกค้า'],
      'en': ['Customer signature'],
    },
    'message_en': 'Both the technician and the customer must sign before the job can be closed — missing: Customer signature',
    'setting': 'close.require_both_signatures',
  },
};

Map<String, Object?> _base() => {
      'GET /api/entity/job/9/comments': {'list': []},
      'GET /api/entity/job/9/tags': {'list': []},
      'GET /api/tags': {'list': []},
      'GET /api/users': {
        'list': [
          {'user_id': 2, 'display_name': 'QA Me'},
        ],
      },
      'GET /api/fields/job': {'list': [], 'picklists': {}},
      'GET /api/settings/job': {'config': {}},
      'GET /api/links/job/9': {'quotations': [], 'jobs': [], 'activities': []},
      'GET /api/field-service/jobs/9/signatures': {'slots': []},
      'GET /api/field-service/jobs/9/sla': {'policy': null, 'response_due': null, 'resolve_due': null, 'breached_response': false, 'breached_resolve': false},
      'GET /api/entity/activity': {'list': []},
      'GET /api/field-service/jobs/9/overview': _overview,
      'GET /api/field-service/jobs/9/close-preview': {'can_close': true, 'open_activities': 0},
    };

Future<AppConfig> _config(WidgetTester tester, FakeNextxAdapter adapter) async {
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: 'QA Me', menusLoaded: true, menuKeys: ['job', 'activity']));
  config.apiClient.debugSetHttpAdapter(adapter);
  return config;
}

Future<void> _setup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<FakeNextxAdapter> _pumpDetail(WidgetTester tester, Map<String, Object?> replies, {Map<String, Map<String, Object?>>? errorsFor, Map<String, int> statusFor = const {}}) async {
  await _setup(tester);
  final adapter = FakeNextxAdapter({..._base(), ...replies}, errorsFor: errorsFor, statusFor: statusFor);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: await _config(tester, adapter),
    child: MaterialApp(home: EntityDetailScreen(key: UniqueKey(), module: 'job', row: const {'id': 9})),
  ));
  await _frames(tester);
  return adapter;
}

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rules', () {
    test('close.require_both_signatures: default on, only an explicit false turns it off', () {
      expect(jobRequireBothSignatures(null), isTrue);
      expect(jobRequireBothSignatures(const {'config': {}}), isTrue);
      expect(jobRequireBothSignatures(const {'config': {'close': {'require_signatures': true}}}), isTrue);
      expect(jobRequireBothSignatures(const {'config': {'close': {'require_both_signatures': true}}}), isTrue);
      expect(jobRequireBothSignatures(_settingOff), isFalse);
      expect(jobRequireBothSignatures(const {'close': {'require_both_signatures': false}}), isFalse, reason: 'a bare config works too');
    });

    test('signed slots count like the server: customer role → customer, any other role → technician', () {
      const row = {'id': 9};
      expect(jobReportMissing(row), ['technician', 'customer']);
      expect(jobReportMissing(row, slots: const [
        {'slot_key': 'staff', 'signer_role': 'staff', 'signature_path': 'job-signatures/s.png'},
      ]), ['customer']);
      expect(jobReportMissing(row, slots: const [
        {'slot_key': 'cust', 'signer_role': 'customer', 'signature_path': 'job-signatures/c.png'},
      ]), ['technician']);
      expect(jobReportMissing(row, slots: const [
        {'slot_key': 'mgr', 'signer_role': null, 'signature_path': 'job-signatures/m.png'},
        {'slot_key': 'cust', 'signer_role': 'customer', 'signature_path': ''},
      ]), ['customer'], reason: 'no role = staff; an empty slot does not count');
      expect(jobReportMissing(const {'technician_signature': 'signatures/t.png'}, slots: const [
        {'slot_key': 'cust', 'signer_role': 'customer', 'signature_path': 'job-signatures/c.png'},
      ]), isEmpty);
    });

    test('server keys → app roles; 409 parsed from the envelope', () {
      expect(jobSignatureRolesFromServer(const ['customer_signature']), ['customer']);
      expect(jobSignatureRolesFromServer(const ['technician_signature', 'customer_signature']), ['technician', 'customer']);
      expect(jobSignatureRolesFromServer(null), isEmpty);
      final e = ApiEnvelopeException(409, 'JOB_SIGNATURES_REQUIRED', 'x', details: Map<String, dynamic>.from(_err409['details']! as Map));
      expect(jobSignaturesRequiredMissing(e), ['customer']);
      expect(jobSignaturesRequiredMissing(ApiEnvelopeException(409, 'JOB_SIGNATURES_REQUIRED', 'x')), ['technician', 'customer']);
      expect(jobSignaturesRequiredMissing(ApiEnvelopeException(400, 'VALIDATION', 'x')), isNull);
      expect(jobSignaturesRequiredText(const ['customer']), contains('ลายเซ็นลูกค้า'));
      expect(journeyErrorText(e), 'ต้องมีลายเซ็นทั้งช่างและลูกค้าก่อนปิดงาน');
    });

    test('next step / checklist follow the setting and count slots', () {
      const row = {'job_status': 'In Progress', 'smownerid': 2};
      expect(jobNextAction(row, _overview, requireReportSignatures: true).key, 'report_signatures');
      expect(jobNextAction(row, _overview, requireReportSignatures: false).key, 'ready_to_close');
      final slots = [
        {'signer_role': 'staff', 'signature_path': 'job-signatures/s.png'},
        {'signer_role': 'customer', 'signature_path': 'job-signatures/c.png'},
      ];
      expect(jobNextAction(row, _overview, requireReportSignatures: true, slots: slots).key, 'ready_to_close');
      final c = jobCloseChecklist(row, _overview, requireReportSignatures: true, slots: slots.sublist(0, 1));
      final rs = c.firstWhere((i) => i.key == 'report_signatures');
      expect(rs.ok, isFalse);
      expect(rs.value, '1/2');
      expect(jobCloseChecklist(row, _overview).any((i) => i.key == 'report_signatures'), isFalse);
    });
  });

  testWidgets('setting ON (default): close blocked in-app with the shortcut to the signature section', (tester) async {
    final a = await _pumpDetail(tester, {
      'GET /api/entity/job/9': {..._job, 'customer_signature': 'signatures/c.png'},
    });
    expect(find.byKey(const ValueKey('next-report_signatures')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-technician')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-customer')), findsNothing);
    expect(a.callKeys, isNot(contains('GET /api/field-service/jobs/9/close-preview')));
    // "ไปที่ส่วนลายเซ็น" closes the sheet and scrolls to the section.
    await tester.tap(find.byKey(const ValueKey('job-close-open-signatures')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsNothing);
    final sec = tester.getRect(find.byKey(const ValueKey('job-signatures-section')));
    expect(sec.top, lessThan(2400), reason: 'signature section on screen');
    expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/close')));
  });

  testWidgets('setting ON: signed staff + customer slots satisfy the rule (no report boxes needed)', (tester) async {
    await _pumpDetail(tester, {
      'GET /api/entity/job/9': _job,
      'GET /api/field-service/jobs/9/signatures': {
        'slots': [
          {'slot_key': 'staff', 'position_th': 'ช่าง', 'signer_role': 'staff', 'signature_path': 'job-signatures/s.png'},
          {'slot_key': 'cust', 'position_th': 'ลูกค้า', 'signer_role': 'customer', 'signature_path': 'job-signatures/c.png'},
        ],
      },
      'GET /api/field-service/jobs/9/overview': {..._overview, 'signatures': {'total': 2, 'signed': 2}},
    });
    expect(find.byKey(const ValueKey('next-ready_to_close')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('job-signatures-badge'))).data, '2/2');
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsNothing);
    expect(find.byKey(const ValueKey('scope-job_only')), findsOneWidget);
  });

  testWidgets('setting OFF: no in-app block — the close window opens and closes the job', (tester) async {
    final a = await _pumpDetail(tester, {
      'GET /api/settings/job': _settingOff,
      'GET /api/entity/job/9': _job,
      'GET /api/field-service/jobs/9/close-preview': {
        'can_close': true,
        'open_activities': 0,
        'signatures': {'require_signatures': false, 'require_both_signatures': false, 'missing': [], 'missing_slots': []},
      },
      'POST /api/field-service/jobs/9/close': {'job_id': 9, 'job_status': 'Completed'},
    });
    expect(find.byKey(const ValueKey('next-ready_to_close')), findsOneWidget);
    expect(find.text('ต้องมีลายเซ็น 2 รายการ'), findsNothing, reason: 'no "required" hint when the business turned it off');
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    expect(_body(a, 'POST /api/field-service/jobs/9/close')['scope'], 'job_only');
  });

  testWidgets('close-preview says signatures are missing (server truth) → sheet instead of the close window', (tester) async {
    final a = await _pumpDetail(tester, {
      'GET /api/settings/job': _settingOff, // stale local setting
      'GET /api/entity/job/9': _job,
      'GET /api/field-service/jobs/9/close-preview': {
        'can_close': true,
        'open_activities': 0,
        'signatures': {'require_both_signatures': true, 'missing': ['technician_signature', 'customer_signature'], 'missing_slots': []},
      },
    });
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-technician')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-close-sign-customer')), findsOneWidget);
    expect(find.byKey(const ValueKey('scope-job_only')), findsNothing);
    expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/close')));
  });

  testWidgets('409 JOB_SIGNATURES_REQUIRED on close → friendly sheet, "เซ็นตอนนี้" opens the signing page', (tester) async {
    await _pumpDetail(
      tester,
      {'GET /api/settings/job': _settingOff, 'GET /api/entity/job/9': {..._job, 'technician_signature': 'signatures/t.png'}},
      errorsFor: {'POST /api/field-service/jobs/9/close': _err409},
      statusFor: {'POST /api/field-service/jobs/9/close': 409},
    );
    await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('job-close-needs-signatures-text'))).data, 'ปิดงานไม่ได้: ต้องมีลายเซ็นทั้งช่างและลูกค้า — ยังขาดลายเซ็นลูกค้า');
    expect(find.byKey(const ValueKey('job-close-sign-technician')), findsNothing);
    expect(find.byKey(const ValueKey('job-close-open-signatures')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-close-sign-customer')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-sign-page')), findsOneWidget);
  });

  testWidgets('list long-press path (JobFlows without a page): 409 → sheet, "ไปที่ส่วนลายเซ็น" opens the job on its signatures', (tester) async {
    await _setup(tester);
    final adapter = FakeNextxAdapter(
      {..._base(), 'GET /api/entity/job/9': _job},
      errorsFor: {'POST /api/field-service/jobs/9/close': _err409},
      statusFor: {'POST /api/field-service/jobs/9/close': 409},
    );
    bool? result;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: await _config(tester, adapter),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('run-close'),
                onPressed: () async => result = await JobFlows.run(context, jobId: '9', action: 'close', row: Map<String, dynamic>.from(_job)),
                child: const Text('close'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('run-close')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('journey-confirm')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('job-close-needs-signatures')), findsOneWidget);
    expect(find.text('ต้องมีลายเซ็นทั้งช่างและลูกค้าก่อนปิดงาน'), findsNothing, reason: 'the sheet, not a bare snack');
    await tester.tap(find.byKey(const ValueKey('job-close-open-signatures')));
    await _frames(tester, 20);
    expect(result, isTrue, reason: 'caller reloads');
    final loader = tester.widget<EntityByIdLoader>(find.byType(EntityByIdLoader));
    expect(loader.module, 'job');
    expect(loader.id, '9');
    expect(loader.tab, 'signatures');
  });
}
