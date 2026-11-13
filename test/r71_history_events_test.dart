// R71 — the record history tab (ประวัติ) reads in plain Thai / English for
// every event the backend writes, never raw keys like "activity.photo_upload".
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/history_events.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/i18n_en.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/status_labels.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/workspace/ws_activity_panel.dart';

import 'support/fake_api.dart';

final _thai = RegExp(r'[฀-๿]');

HistoryLine audit(String action, [Map<String, dynamic> details = const {}, String? module]) =>
    describeHistoryEvent({'type': 'audit', 'action': action, 'details': details}, module: module);

void main() {
  tearDown(() => L10n.set('th'));

  group('every known event key', () {
    test('Thai: readable Thai title, never the raw key', () {
      L10n.set('th');
      expect(kHistoryEvents.length, greaterThan(100));
      for (final key in kHistoryEvents.keys) {
        final l = audit(key);
        expect(l.title, isNot(contains(key)), reason: key);
        expect(l.title, isNot(contains('_')), reason: key);
        expect(l.title, isNot(matches(RegExp(r'[a-z]+\.[a-z]'))), reason: key);
        expect(_thai.hasMatch(l.title), isTrue, reason: '$key → ${l.title}');
        expect(l.title, kHistoryEvents[key]!.$1, reason: key);
      }
    });

    test('English: every label has a past-tense English line, no Thai left', () {
      L10n.set('en');
      for (final key in kHistoryEvents.keys) {
        final l = audit(key);
        expect(_thai.hasMatch(l.title), isFalse, reason: '$key → ${l.title}');
        if (key.contains('.')) expect(l.title, isNot(contains(key)), reason: key);
        expect(l.title, isNot(contains('_')), reason: key);
        expect(l.title.trim(), isNotEmpty, reason: key);
      }
      for (final m in [kEngagementLabels.values.map((v) => v.$1), kTagActionLabels.values].expand((x) => x)) {
        expect(enHistory.containsKey(m), isTrue, reason: m);
      }
    });

    test('enHistory templates keep their holes', () {
      for (final e in enHistory.entries) {
        expect('{}'.allMatches(e.value).length, '{}'.allMatches(e.key).length, reason: e.key);
      }
    });
  });

  group('wording table', () {
    test('audit events with details', () {
      L10n.set('th');
      final table = <(String, Map<String, dynamic>, String, String?)>[
        ('activity.photo_upload', {'count': 3, 'names': ['a.jpg', 'b.jpg', 'c.jpg']}, 'อัปโหลดรูป 3 รูป', null),
        ('activity.photo_delete', {'photo_id': 'x'}, 'ลบรูป', null),
        ('activity.checkin', {'location': '13.7563, 100.5018', 'status': 'In Progress', 'distance': 42.4}, 'เช็คอินที่ 13.7563, 100.5018', 'ห่างจุดนัดหมาย 42 ม.'),
        ('activity.checkout', {'location': '13.7, 100.5', 'time_tracking': '1h 5m', 'status': 'Completed'}, 'เช็คเอาท์ที่ 13.7, 100.5', 'ใช้เวลา 1h 5m'),
        ('activity.rsvp', {'response': 'accepted'}, 'ตอบรับคำเชิญ', 'เข้าร่วม'),
        ('activity.approval_reject', {'note': 'ข้อมูลไม่ครบ'}, 'ไม่อนุมัติกิจกรรม', '“ข้อมูลไม่ครบ”'),
        ('quotation.email_sent', {'to': 'a@b.co', 'quotation_no': 'Q1'}, 'ส่งอีเมลใบเสนอราคา', 'ถึง a@b.co'),
        ('quotation.lines_updated', {'line_count': 4}, 'อัปเดตรายการสินค้า/บริการ', '4 บรรทัด'),
        ('quotation.revise', {'new_quotation_id': 9, 'revision_no': 2}, 'สร้างใบแก้ไข (Revise)', 'ฉบับใหม่ #9 (R2)'),
        ('quotation.approval_advance', {'from_level': 1, 'to_level': 2, 'via': 'email'}, 'อนุมัติขั้นกลาง', 'ขั้น 1 → 2 · (ผ่านอีเมล)'),
        ('quotation.saved', {'line_count': 2, 'created': true}, 'สร้างใบเสนอราคา', '2 บรรทัด'),
        ('job.forward', {'from': 'Open', 'to': 'Waiting', 'to_owner_name': 'สมชาย'}, 'ส่งต่องาน', 'จาก เปิดงาน เป็น รอการตอบรับ · ส่งต่อให้ สมชาย'),
        ('job.signature_sign', {'slot_key': 'customer', 'signer_name': 'ลูกค้า ก'}, 'ลงลายเซ็น', 'ผู้เซ็น: ลูกค้า ก'),
        ('job.email_sent', {'to': 'x@y.co'}, 'ส่งอีเมลใบสั่งงาน', 'ถึง x@y.co'),
        ('case.accept', {'from_status': 'เปิดเคส', 'to_status': 'กำลังดำเนินการ'}, 'รับเคส', 'จาก เปิดเคส เป็น กำลังดำเนินการ'),
        ('deal.contacts_updated', {'count': 2}, 'อัปเดตผู้ติดต่อของดีล', '2 คน'),
        ('service_contract.renew', {'child_id': 77}, 'ต่ออายุสัญญา', 'ฉบับต่ออายุ #77'),
        ('link.create', {'to_module': 'quotation', 'to_id': 12}, 'ผูกเอกสาร', 'ใบเสนอราคา #12'),
        ('create', const {}, 'สร้างรายการ', null),
      ];
      for (final (key, d, title, detail) in table) {
        final l = audit(key, d);
        expect(l.title, title, reason: key);
        if (detail != null) expect(l.detail, detail, reason: key);
      }
      // Details are a JSON string in some rows.
      expect(audit('activity.photo_upload', const {}).title, 'อัปโหลดรูป');
      expect(describeHistoryEvent({'type': 'audit', 'action': 'activity.photo_upload', 'details': '{"count":2}'}).title, 'อัปโหลดรูป 2 รูป');
    });

    test('field changes use field labels, picklist / status labels, names', () {
      L10n.set('th');
      final name = describeHistoryEvent({'type': 'field_change', 'field_name': 'subject', 'old_value': 'A', 'new_value': 'B'}, fieldLabel: (f) => f == 'subject' ? 'ชื่องาน' : '');
      expect((name.title, name.detail, name.kind), ('แก้ไข ชื่องาน', 'A → B', HistoryKind.edit));
      final st = describeHistoryEvent({'type': 'field_change', 'field_name': 'status', 'field_label_th': 'สถานะ', 'old_value': 'Planned', 'new_value': 'In Progress'}, module: 'activity');
      expect((st.title, st.detail, st.kind), ('เปลี่ยนสถานะ', 'จาก วางแผน เป็น กำลังดำเนินการ', HistoryKind.status));
      final job = describeHistoryEvent({'type': 'field_change', 'field_name': 'job_status', 'field_label_th': 'สถานะงาน', 'old_value': 'In Progress', 'new_value': 'Completed'}, module: 'job');
      expect((job.title, job.detail), ('เปลี่ยนสถานะงาน', 'จาก กำลังดำเนินการ เป็น ปิดงาน'));
      final owner = describeHistoryEvent({'type': 'field_change', 'field_name': 'smownerid', 'field_label_th': 'ผู้รับผิดชอบ', 'old_value': 'สมหญิง', 'new_value': 'สมชาย'});
      expect((owner.title, owner.detail, owner.kind), ('มอบหมายให้ สมชาย', 'จาก สมหญิง', HistoryKind.assign));
      final pick = describeHistoryEvent(
        {'type': 'field_change', 'field_name': 'industry', 'field_label_th': 'อุตสาหกรรม', 'old_value': 'Retail', 'new_value': 'Bank'},
        valueLabel: (f, v) => {'Retail': 'ค้าปลีก', 'Bank': 'ธนาคาร'}[v] ?? v,
      );
      expect(pick.detail, 'ค้าปลีก → ธนาคาร');
      final html = describeHistoryEvent({'type': 'field_change', 'field_name': 'description', 'field_label_th': 'รายละเอียด', 'old_value': '<p>เก่า</p>', 'new_value': '<p>ใหม่</p>'});
      expect(html.detail, 'เก่า → ใหม่');
      // A raw field name without labels is made readable, never shown as-is.
      final raw = describeHistoryEvent({'type': 'field_change', 'field_name': 'cf_site_code', 'old_value': '1', 'new_value': '2'});
      expect(raw.title, 'แก้ไข Cf site code');
    });

    test('status events, tags, engagement, 360 rows', () {
      L10n.set('th');
      final ev = describeHistoryEvent({'type': 'status_event', 'action': 'accept', 'from_status': 'Open', 'to_status': 'In Progress', 'source': 'workflow'}, module: 'job');
      expect((ev.title, ev.detail), ('รับงาน', 'จาก เปิดงาน เป็น กำลังดำเนินการ'));
      final fw = describeHistoryEvent({'type': 'status_event', 'action': 'forward', 'from_status': 'เปิดเคส', 'to_status': 'รอการตอบรับ', 'details': {'to_owner_name': 'ช่างเอ', 'note': 'ด่วน'}}, module: 'case');
      expect((fw.title, fw.detail), ('ส่งต่อเคส', 'จาก เปิดเคส เป็น รอการตอบรับ · ส่งต่อให้ ช่างเอ · “ด่วน”'));
      expect(describeHistoryEvent({'type': 'status_event', 'action': 'admin_set', 'to_status': 'Completed'}, module: 'job').title, 'ผู้ดูแลเปลี่ยนสถานะ');
      final tag = describeHistoryEvent({'type': 'tag', 'action': 'detach', 'tag_name': 'VIP'});
      expect((tag.title, tag.detail, tag.kind), ('ถอนแท็ก', 'VIP', HistoryKind.tag));
      expect(describeHistoryEvent({'type': 'engagement', 'event_type': 'email_open'}).title, 'ลูกค้าเปิดอีเมล');
      final act = describeHistoryEvent({'type': 'activity', 'title': 'เยี่ยมลูกค้า', 'summary': 'Visit · Planned'});
      expect((act.title, act.detail), ('กิจกรรม: เยี่ยมลูกค้า', 'เข้าพบลูกค้า · วางแผน'));
    });

    test('unknown keys are humanised and logged in debug', () {
      L10n.set('th');
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = old);
      final a = audit('activity.photo_rotate_r71');
      expect(a.title, isNot(contains('.')));
      expect(a.title, isNot(contains('_')));
      expect(a.title, 'อัปเดตรูป');
      expect(audit('job.part_delete_r71').title, 'ลบรายการ');
      final weird = audit('zz.frobnicate_widget');
      expect(weird.title, 'Frobnicate widget');
      expect(logs.where((l) => l.contains('activity.photo_rotate_r71')), isNotEmpty);
      expect(logs.where((l) => l.contains('zz.frobnicate_widget')), isNotEmpty);
      // Unknown event types fall back to the row's own title / a humanised type.
      expect(describeHistoryEvent({'type': 'mystery_kind'}).title, 'Mystery kind');
      // Workspace history too.
      final ws = wsDescribeActivity({'action': 'label_bulk_add'}, const WsLookups());
      expect(ws.text, isNot(contains('_')));
      expect(wsDescribeActivity({'action': 'trash_delete', 'new_value': '[QA] งาน'}, const WsLookups()).text, 'ย้ายไปถังขยะ');
    });

    test('English mode', () {
      L10n.set('en');
      expect(audit('activity.photo_upload', {'count': 3}).title, 'Uploaded 3 photo(s)');
      expect(audit('activity.checkin', {'location': '13.7, 100.5'}).title, 'Checked in at 13.7, 100.5');
      expect(audit('quotation.email_sent', {'to': 'a@b.co'}).detail, 'to a@b.co');
      final st = describeHistoryEvent({'type': 'field_change', 'field_name': 'status', 'field_label_th': 'สถานะ', 'field_label_en': 'Status', 'old_value': 'Planned', 'new_value': 'In Progress'}, module: 'activity');
      expect((st.title, st.detail), ('Changed status', 'from Planned to In Progress'));
      final f = describeHistoryEvent({'type': 'field_change', 'field_name': 'subject', 'field_label_th': 'ชื่องาน', 'field_label_en': 'Title', 'old_value': 'A', 'new_value': 'B'});
      expect((f.title, f.detail), ('Changed Title', 'A → B'));
      expect(describeHistoryEvent({'type': 'status_event', 'action': 'accept', 'from_status': 'Open', 'to_status': 'In Progress'}, module: 'job').detail, 'from Open to In progress');
      expect(describeHistoryEvent({'type': 'engagement', 'event_type': 'comment'}).title, 'Added a comment');
      expect(audit('job.forward', {'to_owner_name': 'Somchai'}).detail, 'Forwarded to Somchai');
    });
  });

  group('status values', () {
    test('Thai labels by module, English in English mode', () {
      L10n.set('th');
      expect(statusValueLabel('Planned', module: 'activity'), 'วางแผน');
      expect(statusValueLabel('In Progress', module: 'activity'), 'กำลังดำเนินการ');
      expect(statusValueLabel('Completed', module: 'activity'), 'เสร็จสิ้น');
      expect(statusValueLabel('Completed', module: 'job'), 'ปิดงาน');
      expect(statusValueLabel('Planned', module: 'job'), 'เปิดงาน');
      expect(statusValueLabel('Pending_Approval', module: 'service_contract'), 'รออนุมัติ');
      expect(statusValueLabel('Active'), 'มีผล');
      expect(statusValueLabel('Closed Won', module: 'deal'), 'ปิดการขาย (ชนะ)');
      expect(statusValueLabel('approved', module: 'quotation', field: 'quotation_status'), 'อนุมัติใบเสนอราคา');
      expect(statusValueLabel('เปิดเคส', module: 'case'), 'เปิดเคส');
      expect(statusValueLabel('Something custom'), 'Something custom');
      L10n.set('en');
      expect(statusValueLabel('Planned', module: 'activity'), 'Planned');
      expect(statusValueLabel('เปิดเคส', module: 'case'), isNot(matches(_thai)));
    });
  });

  testWidgets('history panel: Thai lines, colours, time · name chip, no raw keys', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: EntityHistoryPanel(
            loading: false,
            module: 'activity',
            events: const [
              {'type': 'audit', 'id': 1, 'action': 'activity.photo_upload', 'details': {'count': 3}, 'at': '2026-11-11T03:37:00.000Z', 'user_name': 'สมชาย ใจดี'},
              {'type': 'audit', 'id': 2, 'action': 'activity.checkin', 'details': {'location': '13.75, 100.50'}, 'at': '2026-11-11T02:00:00.000Z', 'user_name': 'สมชาย ใจดี'},
              {'type': 'field_change', 'id': 3, 'field_name': 'status', 'field_label_th': 'สถานะ', 'old_value': 'Planned', 'new_value': 'In Progress', 'at': '2026-11-10T02:00:00.000Z'},
            ],
          ),
        ),
      ),
    ));
    expect(find.text('อัปโหลดรูป 3 รูป'), findsOneWidget);
    expect(find.text('เช็คอินที่ 13.75, 100.50'), findsOneWidget);
    expect(find.text('เปลี่ยนสถานะ'), findsOneWidget);
    expect(find.text('จาก วางแผน เป็น กำลังดำเนินการ'), findsOneWidget);
    expect(find.text('10:37 · สมชาย ใจดี'), findsOneWidget);
    expect(find.textContaining('activity.'), findsNothing);
    expect(find.textContaining('photo_upload'), findsNothing);
    final icon = tester.widget<Icon>(find.byIcon(kHistoryKindStyle[HistoryKind.photo]!.$1).first);
    expect(icon.color, kHistoryKindStyle[HistoryKind.photo]!.$2);
  });

  testWidgets('activity detail header shows the Thai status, not "Planned"', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    SharedPreferences.setMockInitialValues({});
    const row = {'id': 71, 'subject': '[QA] R71 นัดหมาย', 'status': 'Planned'};
    final adapter = FakeNextxAdapter({
      'GET /api/fields/activity': {'list': [{'name': 'subject', 'label_th': 'หัวข้อ'}], 'picklists': {}},
      'GET /api/entity/activity/71': row,
      'GET /api/entity/activity/71/comments': {'list': []},
      'GET /api/entity/activity/71/timeline': {'list': []},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['activity']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'activity', row: row)),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('วางแผน'), findsWidgets);
    // Header chip + subtitle (field values in the info tab are SelectableText).
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('Planned')), findsNothing);
  });
}
