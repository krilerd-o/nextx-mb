import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/fsm/service_more.dart' show JobWorkspaceButton;
import 'package:nextx_mobile/screens/journey/job_activity_gen.dart';
import 'package:nextx_mobile/screens/journey/job_sign_link.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _baseMenus = ['job', 'quotation', 'activity', 'pending-approvals'];

final _clipboard = <String>[];

Map<String, Object?> _common() => {
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
      'GET /api/field-service/jobs/9/sla': {'policy': null},
      'GET /api/entity/activity': {'list': []},
    };

void _mockPlatform() {
  _clipboard.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'Clipboard.setData') _clipboard.add('${(c.arguments as Map)['text']}');
    return null;
  });
}

Future<FakeNextxAdapter> _pump(WidgetTester tester, Map<String, Object?> replies, {List<String> menus = _baseMenus, Size size = const Size(412, 2600)}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  PublicLinkHooks.reset();
  _mockPlatform();
  final adapter = FakeNextxAdapter({..._common(), ...replies});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: 'QA Me', menusLoaded: true, menuKeys: menus));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(PublicLinkHooks.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
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

/// Scroll [key] to the middle (clear of the pinned header) and tap it.
Future<void> _tap(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  expect(f, findsOneWidget, reason: '$key');
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await _frames(tester, 4);
  await tester.tap(f);
  await _frames(tester);
}

String _text(WidgetTester tester, Key key) => tester.widget<Text>(find.byKey(key)).data ?? '';

const _job = {
  'id': 9,
  'job_no': 'JOB-9',
  'job_name': 'ล้างแอร์',
  'job_status': 'In Progress',
  'smownerid': 2,
  'customer_name': 'บริษัท ลูกค้า QA',
  'plan_start': '2026-11-20T02:00:00Z', // 09:00 Bangkok, Friday
};
final _overview = {
  'job_id': 9,
  'job_status': 'In Progress',
  'has_owner': true,
  'activities': {'total': 0, 'open': 0, 'done': 0},
  'signatures': {'total': 0, 'signed': 0},
  'parts': 0,
};

const _template = {
  'id': 3,
  'name': 'ติดตั้งแอร์ 3 ขั้น',
  'description': 'สำรวจ ติดตั้ง ส่งมอบ',
  'category': 'ติดตั้ง',
  'items': [
    {'key': 'a1', 'subject': 'สำรวจหน้างาน {{job_no}}', 'activitytype': 'Visit', 'offset_days': 0, 'start_time': '09:00', 'duration_min': 60, 'owner_rule': 'job_owner'},
    {'subject': 'ติดตั้ง', 'activitytype': 'Task', 'offset_days': 1, 'start_time': '13:00', 'duration_min': 120, 'owner_rule': 'user', 'owner_user_id': 5},
    {'key': 'a3', 'subject': 'ส่งมอบงาน', 'activitytype': 'Meeting', 'offset_days': 2, 'all_day': true, 'owner_rule': 'creator'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ลิงก์สำหรับลงนาม', () {
    test('status: server Accepted / Signed (any case), token, none', () {
      expect(jobSignLinkStatus({}, {'customer_ack_status': 'Accepted'}), 'accepted');
      expect(jobSignLinkStatus({}, {'customer_ack_status': 'Signed'}), 'signed');
      expect(jobSignLinkStatus({'customer_ack_status': 'signed'}, {}), 'signed');
      expect(jobSignLinkStatus({'customer_signed_at': '2026-11-12T03:00:00Z'}, {}), 'signed');
      expect(jobSignLinkStatus({'public_token': 'abc'}, {}), 'sent');
      expect(jobSignLinkStatus({}, {}), 'none');
      expect([for (final s in ['none', 'sent', 'accepted', 'signed']) jobSignLinkStatusLabel(s)],
          ['ยังไม่ได้สร้างลิงก์', 'ส่งลิงก์แล้ว · รอลงนาม', 'ลูกค้ารับทราบแล้ว', 'ลูกค้าลงนามแล้ว']);
      expect(shortPublicLink('https://app.nextx.test/public/job/0123456789abcdef'), 'app.nextx.test/…/01234567…');
    });

    testWidgets('สร้างลิงก์ → the link shows in the card (chip, copy, share, open, QR) and the job reloads', (tester) async {
      final a = await _pump(tester, {
        'GET /api/entity/job/9': _job,
        'GET /api/field-service/jobs/9/overview': _overview,
        'POST /api/field-service/jobs/9/public-link': {'token': 'tok1234567890', 'path': '/public/job/tok1234567890', 'pdf_path': '/api/public/field-service/jobs/public/tok1234567890/birt-pdf'},
      });
      expect(find.text('ลิงก์สำหรับลงนาม'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('job-link-status')), matching: find.text('ยังไม่ได้สร้างลิงก์')), findsOneWidget);
      expect(find.byKey(const ValueKey('job-link-url')), findsNothing);
      final gets = a.callKeys.where((k) => k == 'GET /api/entity/job/9').length;

      await _tap(tester, const ValueKey('job-public-link'));
      expect(a.callKeys, contains('POST /api/field-service/jobs/9/public-link'));
      expect(find.text('สร้างลิงก์แล้ว'), findsOneWidget, reason: 'snack');
      expect(_text(tester, const ValueKey('job-link-short')), endsWith('/…/tok12345…'));
      expect(find.descendant(of: find.byKey(const ValueKey('job-link-status')), matching: find.text('ส่งลิงก์แล้ว · รอลงนาม')), findsOneWidget);
      expect(a.callKeys.where((k) => k == 'GET /api/entity/job/9').length, greaterThan(gets), reason: 'card refreshes the job');
      expect(find.byKey(const ValueKey('public-link-url')), findsNothing, reason: 'no modal: the link is inline');

      String? shared;
      Uri? opened;
      PublicLinkHooks.share = (t) async => shared = t;
      PublicLinkHooks.open = (u) async => opened = u;
      await _tap(tester, const ValueKey('job-link-copy'));
      expect(_clipboard.last, endsWith('/public/job/tok1234567890'));
      await _tap(tester, const ValueKey('job-link-share'));
      expect(shared, contains('JOB-9'));
      expect(shared, endsWith('/public/job/tok1234567890'));
      await _tap(tester, const ValueKey('job-link-open'));
      expect(opened?.path, '/public/job/tok1234567890');

      // QR → the share sheet: title, QR, full link, copy / share / open, PDF.
      await _tap(tester, const ValueKey('job-link-qr'));
      expect(find.text('ลิงก์สำหรับลงนาม'), findsWidgets);
      expect(find.byKey(const ValueKey('public-link-qr')), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('public-link-url'))).data, endsWith('/public/job/tok1234567890'));
      for (final k in ['public-link-copy', 'public-link-share', 'public-link-open', 'public-link-pdf']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      shared = null;
      await tester.tap(find.byKey(const ValueKey('public-link-share')));
      await _frames(tester, 4);
      expect(shared, contains('/public/job/tok1234567890'));
    });

    testWidgets('an existing public_token shows on open — no POST; Accepted / Signed labels', (tester) async {
      final a = await _pump(tester, {
        'GET /api/entity/job/9': {..._job, 'public_token': 'existing99887766', 'customer_ack_status': 'Accepted'},
        'GET /api/field-service/jobs/9/overview': {..._overview, 'customer_ack_status': 'Accepted'},
      });
      expect(_text(tester, const ValueKey('job-link-short')), endsWith('/…/existing…'));
      expect(find.descendant(of: find.byKey(const ValueKey('job-link-status')), matching: find.text('ลูกค้ารับทราบแล้ว')), findsOneWidget);
      expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/public-link')));
    });

    testWidgets('Signed: "ลูกค้าลงนามแล้ว", no regenerate', (tester) async {
      await _pump(tester, {
        'GET /api/entity/job/9': {..._job, 'public_token': 'existing99887766'},
        'GET /api/field-service/jobs/9/overview': {..._overview, 'customer_ack_status': 'Signed'},
      });
      expect(find.descendant(of: find.byKey(const ValueKey('job-link-status')), matching: find.text('ลูกค้าลงนามแล้ว')), findsOneWidget);
      expect(find.byKey(const ValueKey('job-link-regenerate')), findsNothing);
    });

    testWidgets('สร้างลิงก์ใหม่ asks first: cancel keeps the link, confirm replaces it', (tester) async {
      final a = await _pump(tester, {
        'GET /api/entity/job/9': {..._job, 'public_token': 'oldtoken1234567'},
        'GET /api/field-service/jobs/9/overview': _overview,
        'POST /api/field-service/jobs/9/public-link': {'token': 'newtoken7654321', 'path': '/public/job/newtoken7654321'},
      });
      await _tap(tester, const ValueKey('job-link-regenerate'));
      expect(find.text('สร้างลิงก์ใหม่?'), findsOneWidget);
      expect(find.byKey(const ValueKey('regen-link-warning')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await _frames(tester);
      expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/public-link')));
      expect(_text(tester, const ValueKey('job-link-short')), endsWith('oldtoken…'));

      await _tap(tester, const ValueKey('job-link-regenerate'));
      await tester.tap(find.byKey(const ValueKey('regen-link-confirm')));
      await _frames(tester);
      expect(a.callKeys.where((k) => k == 'POST /api/field-service/jobs/9/public-link').length, 1);
      expect(_text(tester, const ValueKey('job-link-short')), endsWith('newtoken…'));
      expect(find.text('สร้างลิงก์ใหม่แล้ว — ลิงก์เดิมใช้ไม่ได้แล้ว'), findsOneWidget);
    });
  });

  group('งานสนาม by permission', () {
    final replies = {'GET /api/entity/job/9': _job, 'GET /api/field-service/jobs/9/overview': _overview};

    testWidgets('no Workspace and no Inspection menu → the whole box is hidden; นัดหมาย still goes somewhere', (tester) async {
      final a = await _pump(tester, replies);
      expect(find.byKey(const ValueKey('job-field-ops')), findsNothing);
      expect(find.text('งานสนาม'), findsNothing);
      expect(a.callKeys.any((k) => k.contains('/workspace')), isFalse);
      // KPI นัดหมาย scrolls to the activities instead of a missing section.
      await tester.tap(find.byKey(const ValueKey('kpi-schedule')));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('job-activities')), findsOneWidget);
    });

    testWidgets('Inspection only → box with ใบตรวจรับ, no ส่งเข้า Workspace', (tester) async {
      await _pump(tester, replies, menus: [..._baseMenus, 'inspection']);
      expect(find.byKey(const ValueKey('job-field-ops')), findsOneWidget);
      expect(find.byKey(const ValueKey('job-inspection-cta')), findsOneWidget);
      expect(find.byType(JobWorkspaceButton), findsNothing);
      expect(find.byKey(const ValueKey('job-ops-schedule')), findsOneWidget, reason: 'the rest of the box stays');
    });

    testWidgets('Workspace only → box with ส่งเข้า Workspace, no ใบตรวจรับ', (tester) async {
      await _pump(tester, replies, menus: [..._baseMenus, 'workspace']);
      expect(find.byKey(const ValueKey('job-field-ops')), findsOneWidget);
      expect(find.byType(JobWorkspaceButton), findsOneWidget);
      expect(find.byKey(const ValueKey('job-inspection-cta')), findsNothing);
    });
  });

  group('Gen Activity', () {
    test('preview follows the server: offsets, item times, all-day, owner rules, missing keys; body carries exact overrides', () {
      final items = jobGenItems(_template['items']);
      expect(items.map((i) => i.key), ['a1', 'a2', 'a3'], reason: 'server names a missing key a{i+1}');
      final base = jobGenBaseDate(_job);
      expect(base, DateTime(2026, 11, 20, 9));
      final o = JobGenOptions(start: base);
      final rows = planJobActivities(items, o, job: _job, jobOwnerId: '2', meId: '7');
      expect(rows.map((r) => r.subject), ['สำรวจหน้างาน JOB-9', 'ติดตั้ง', 'ส่งมอบงาน']);
      expect(rows.map(genWhen), ['ศ. 20 พ.ย. 2569 · 09:00–10:00', 'ส. 21 พ.ย. 2569 · 13:00–15:00', 'อา. 22 พ.ย. 2569 · ทั้งวัน']);
      expect(rows.map((r) => r.ownerId), ['2', '5', '7'], reason: 'job_owner / user / creator');

      final chain = planJobActivities(items, JobGenOptions(start: DateTime(2026, 11, 20, 8), spacing: 'chain', durationMin: 30), job: _job, jobOwnerId: '2', meId: '7');
      expect(chain.take(2).map(genWhen), ['ศ. 20 พ.ย. 2569 · 08:00–08:30', 'ศ. 20 พ.ย. 2569 · 08:30–09:00']);
      final weekly = planJobActivities(items, JobGenOptions(start: DateTime(2026, 11, 20, 8), spacing: 'days', gapDays: 7, ownerAll: '5'), job: _job, jobOwnerId: '2', meId: '7', skipped: {'a2'});
      expect(weekly.map((r) => genDay(r.start)), ['ศ. 20 พ.ย. 2569', 'ศ. 27 พ.ย. 2569', 'ศ. 27 พ.ย. 2569'], reason: 'a skipped row takes no slot');
      expect(weekly.map((r) => r.ownerId).toSet(), {'5'});

      final body = jobGenBody(templateId: 3, items: items, rows: planJobActivities(items, o, job: _job, jobOwnerId: '2', meId: '7', skipped: {'a3'}), prefix: '[JOB-9] ');
      expect(body, {
        'template_id': 3,
        'overrides': {
          'a1': {'date_start': '2026-11-20 09:00:00', 'date_end': '2026-11-20 10:00:00', 'owner_user_id': 2, 'subject': '[JOB-9] สำรวจหน้างาน {{job_no}}'},
          'a2': {'date_start': '2026-11-21 13:00:00', 'date_end': '2026-11-21 15:00:00', 'owner_user_id': 5, 'subject': '[JOB-9] ติดตั้ง'},
          'a3': {'skip': true},
        },
      });
    });

    testWidgets('template → options → confirm preview (subjects, Thai dates, owners) → POST → result → activities reload', (tester) async {
      final a = await _pump(tester, {
        'GET /api/entity/job/9': _job,
        'GET /api/field-service/jobs/9/overview': _overview,
        'GET /api/settings/job/activity-templates': {'templates': [_template], 'owner_rules': ['job_owner']},
        'POST /api/field-service/jobs/9/generate-activities': {'created': 2, 'activity_ids': [501, 502]},
      });
      await _tap(tester, const ValueKey('next-action-gen_activity'));
      // Step 1: template cards with their step count, and the single visit.
      expect(find.byKey(const ValueKey('gen-pick-single')), findsOneWidget);
      expect(find.text('ติดตั้งแอร์ 3 ขั้น'), findsOneWidget);
      expect(find.text('3 กิจกรรม'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('act-template-3')));
      await _frames(tester);
      // Step 2: start from the job date; job number prefix.
      expect(_text(tester, const ValueKey('gen-start-day')), 'ศ. 20 พ.ย. 2569');
      expect(_text(tester, const ValueKey('gen-start-time')), '09:00');
      await tester.ensureVisible(find.byKey(const ValueKey('gen-prefix-jobno')));
      await tester.tap(find.byKey(const ValueKey('gen-prefix-jobno')));
      await _frames(tester, 4);
      await tester.tap(find.byKey(const ValueKey('gen-next')));
      await _frames(tester);
      // Step 3: the exact preview.
      expect(find.text('จะสร้าง 3 กิจกรรม'), findsOneWidget);
      expect(_text(tester, const ValueKey('gen-row-subject-a1')), '[JOB-9] สำรวจหน้างาน JOB-9');
      expect(_text(tester, const ValueKey('gen-row-when-a1')), 'ศ. 20 พ.ย. 2569 · 09:00–10:00');
      expect(_text(tester, const ValueKey('gen-row-when-a2')), 'ส. 21 พ.ย. 2569 · 13:00–15:00');
      expect(_text(tester, const ValueKey('gen-row-when-a3')), 'อา. 22 พ.ย. 2569 · ทั้งวัน');
      expect([for (final k in ['a1', 'a2', 'a3']) _text(tester, ValueKey('gen-row-owner-name-$k'))], ['QA Me', 'QA Tech', 'QA Me']);
      // Per-activity owner and skip.
      await tester.tap(find.byKey(const ValueKey('gen-row-owner-a1')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('user-pick-5')));
      await _frames(tester);
      expect(_text(tester, const ValueKey('gen-row-owner-name-a1')), 'QA Tech');
      await tester.ensureVisible(find.byKey(const ValueKey('gen-row-skip-a3')));
      await tester.tap(find.byKey(const ValueKey('gen-row-skip-a3')));
      await _frames(tester, 4);
      expect(find.text('สร้าง 2 กิจกรรม'), findsOneWidget);
      expect(a.callKeys, isNot(contains('POST /api/field-service/jobs/9/generate-activities')), reason: 'nothing before confirm');

      final gets = a.callKeys.where((k) => k == 'GET /api/entity/job/9').length;
      await tester.tap(find.byKey(const ValueKey('gen-confirm')));
      await _frames(tester);
      final b = _body(a, 'POST /api/field-service/jobs/9/generate-activities');
      expect(b['template_id'], 3);
      expect(b['overrides'], {
        'a1': {'date_start': '2026-11-20 09:00:00', 'date_end': '2026-11-20 10:00:00', 'owner_user_id': 5, 'subject': '[JOB-9] สำรวจหน้างาน {{job_no}}'},
        'a2': {'date_start': '2026-11-21 13:00:00', 'date_end': '2026-11-21 15:00:00', 'owner_user_id': 5, 'subject': '[JOB-9] ติดตั้ง'},
        'a3': {'skip': true},
      });
      expect(_text(tester, const ValueKey('gen-done-title')), 'สร้าง 2 กิจกรรมแล้ว');
      await tester.tap(find.byKey(const ValueKey('gen-done')));
      await _frames(tester);
      expect(find.byType(JobActivityGenScreen), findsNothing);
      expect(a.callKeys.where((k) => k == 'GET /api/entity/job/9').length, greaterThan(gets), reason: 'job + activities reload');
    });

    testWidgets('single visit: subject, type, time, duration, owner → items + override; server error stays on confirm', (tester) async {
      final a = await _pump(tester, {
        'GET /api/entity/job/9': _job,
        'GET /api/field-service/jobs/9/overview': _overview,
        'GET /api/settings/job/activity-templates': {'templates': <Object>[]},
        'POST /api/field-service/jobs/9/generate-activities': {'created': 1},
      });
      a.errorsFor['POST /api/field-service/jobs/9/generate-activities'] = {'error_code': 'FORBIDDEN', 'message': 'ไม่มีสิทธิ์สร้างกิจกรรมในใบสั่งงานนี้'};
      await _tap(tester, const ValueKey('next-action-gen_activity'));
      expect(find.byKey(const ValueKey('gen-templates-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gen-pick-single')));
      await _frames(tester);
      await tester.enterText(find.byKey(const ValueKey('gen-subject')), 'ตรวจเช็คแอร์');
      await tester.tap(find.byKey(const ValueKey('gen-type-Meeting')));
      await tester.tap(find.byKey(const ValueKey('gen-time-13')));
      await _frames(tester, 4);
      await tester.ensureVisible(find.byKey(const ValueKey('gen-duration-120')));
      await tester.tap(find.byKey(const ValueKey('gen-duration-120')));
      await tester.ensureVisible(find.byKey(const ValueKey('gen-owner-pick')));
      await tester.tap(find.byKey(const ValueKey('gen-owner-pick')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('user-pick-5')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('gen-next')));
      await _frames(tester);
      expect(_text(tester, const ValueKey('gen-row-subject-k1')), 'ตรวจเช็คแอร์');
      expect(_text(tester, const ValueKey('gen-row-when-k1')), 'ศ. 20 พ.ย. 2569 · 13:00–15:00');
      expect(_text(tester, const ValueKey('gen-row-owner-name-k1')), 'QA Tech');
      expect(find.text('สร้าง 1 กิจกรรม'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gen-confirm')));
      await _frames(tester);
      expect(find.text('ไม่มีสิทธิ์สร้างกิจกรรมในใบสั่งงานนี้'), findsOneWidget);
      expect(find.byKey(const ValueKey('gen-confirm')), findsOneWidget, reason: 'still on confirm');

      a.errorsFor.clear();
      await tester.tap(find.byKey(const ValueKey('gen-confirm')));
      await _frames(tester);
      final b = _body(a, 'POST /api/field-service/jobs/9/generate-activities');
      expect(b['items'], [
        {'key': 'k1', 'subject': 'ตรวจเช็คแอร์', 'activitytype': 'Meeting', 'offset_days': 0, 'start_time': '13:00', 'duration_min': 120, 'all_day': false, 'owner_rule': 'job_owner'},
      ]);
      expect(b['overrides'], {
        'k1': {'date_start': '2026-11-20 13:00:00', 'date_end': '2026-11-20 15:00:00', 'owner_user_id': 5},
      });
      expect(b.containsKey('template_id'), isFalse);
      expect(_text(tester, const ValueKey('gen-done-title')), 'สร้าง 1 กิจกรรมแล้ว');
    });
  });
}
