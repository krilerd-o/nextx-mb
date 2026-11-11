import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_record_actions.dart';

import 'support/fake_api.dart';

Map<String, Object?> _schema(String statusKey, List<(String, String)> statuses) => {
      'list': [
        {'name': 'lead_name', 'label_th': 'ชื่อ'},
        {'name': 'subject', 'label_th': 'หัวข้อ'},
        {'name': statusKey, 'label_th': 'สถานะ', 'uitype': '15'},
      ],
      'picklists': {
        statusKey: [for (final (v, l) in statuses) {'value': v, 'label': l}],
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      platformCalls.add(c);
      return null;
    });
  });

  Future<(FakeNextxAdapter, AppConfig)> pumpList(
    WidgetTester tester, {
    required String module,
    required Map<String, dynamic> row,
    Map<String, Object?> extra = const {},
    String statusKey = 'lead_status',
    bool hintSeen = true,
  }) async {
    SharedPreferences.setMockInitialValues({if (hintSeen) 'nx_crm_row_actions_hint_v1': true});
    final id = row['id'];
    final adapter = FakeNextxAdapter({
      'GET /api/modules': [],
      'GET /api/customviews': {'list': [], 'default_id': null},
      'GET /api/fields/$module': _schema(statusKey, const [('New', '[QA] ใหม่'), ('Qualified', '[QA] ผ่านเกณฑ์'), ('Lost', '[QA] ไม่สำเร็จ')]),
      'GET /api/entity/$module': {'list': [row], 'total': 1},
      'GET /api/entity/$module/$id': row,
      'GET /api/entity/$module/$id/comments': {'list': [
        {'id': 1, 'user_name': '[QA] Second', 'body': '[QA] คอมเมนต์เดิม', 'created_at': '2026-11-01T10:00:00Z'},
      ]},
      'POST /api/entity/$module/$id/comments': {'id': 2},
      'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
      'PUT /api/entity/$module/$id': {'id': id},
      'DELETE /api/entity/$module/$id': {'ok': true},
      ...extra,
    });
    final config = AppConfig();
    config.debugOverrideSession(SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: [module]));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(home: EntityListScreen(module: module, title: '[QA] รายการ')),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (adapter, config);
  }

  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> longPressRow(WidgetTester tester, String title) async {
    await tester.longPress(find.textContaining(title).first);
    await settle(tester);
  }

  const lead = {'id': 5, 'lead_no': 'LD-QA-1', 'lead_name': '[QA] ลูกค้าทดสอบ R43', 'lead_status': 'New'};

  testWidgets('long-press vibrates and shows the icon grid with every command', (tester) async {
    await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    expect(platformCalls.any((c) => c.method == 'HapticFeedback.vibrate'), isTrue);
    for (final k in ['convert', 'status', 'comment', 'edit', 'duplicate', 'delete', 'select']) {
      expect(find.byKey(ValueKey('row-act-$k')), findsOneWidget, reason: k);
    }
    expect(find.text('ปรับสถานะ'), findsOneWidget);
    expect(find.text('อัปเดตคอมเมนต์'), findsOneWidget);
    // Header names the record and its current status.
    expect(find.byKey(const ValueKey('row-act-title')), findsOneWidget);
    expect(find.text('LD-QA-1'), findsOneWidget);
    expect(find.text('[QA] ใหม่'), findsWidgets);
    // Not multi-select any more.
    expect(find.text('เลือก 1 รายการ'), findsNothing);
  });

  testWidgets('status: pick a pill → PUT status, card updates, undo sends the old value', (tester) async {
    final (adapter, _) = await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-status')));
    await settle(tester);
    expect(find.byKey(const ValueKey('status-opt-Qualified')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-opt-Qualified')));
    await settle(tester);
    final puts = adapter.calls.where((c) => c.method == 'PUT' && c.path == '/api/entity/lead/5').toList();
    expect(puts, hasLength(1));
    expect(puts.first.data, {'lead_status': 'Qualified'});
    expect(find.textContaining('เปลี่ยนสถานะเป็น [QA] ผ่านเกณฑ์'), findsOneWidget);
    await tester.tap(find.text('เลิกทำ'));
    await settle(tester);
    final puts2 = adapter.calls.where((c) => c.method == 'PUT' && c.path == '/api/entity/lead/5').toList();
    expect(puts2, hasLength(2));
    expect(puts2.last.data, {'lead_status': 'New'});
  });

  testWidgets('comment: sheet loads the thread and posts a new comment', (tester) async {
    final (adapter, _) = await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-comment')));
    await settle(tester);
    expect(adapter.callKeys, contains('GET /api/entity/lead/5/comments'));
    expect(find.textContaining('[QA] คอมเมนต์เดิม'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '[QA] อัปเดตจากรายการ');
    await tester.tap(find.byTooltip('ส่ง'));
    await settle(tester);
    final post = adapter.calls.where((c) => c.method == 'POST' && c.path == '/api/entity/lead/5/comments').toList();
    expect(post, hasLength(1));
    expect('${post.first.data}', contains('[QA] อัปเดตจากรายการ'));
  });

  testWidgets('edit: loads the full record and opens the edit form for it', (tester) async {
    final (adapter, _) = await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-edit')));
    await settle(tester, 20);
    expect(adapter.callKeys, contains('GET /api/entity/lead/5'));
    final form = tester.widget<EntityCreateScreen>(find.byType(EntityCreateScreen));
    expect(form.recordId, '5');
    expect(form.initialValues?['lead_name'], '[QA] ลูกค้าทดสอบ R43');
  });

  testWidgets('duplicate (lead): pre-filled copy form without a record id', (tester) async {
    await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-duplicate')));
    await settle(tester, 20);
    final form = tester.widget<EntityCreateScreen>(find.byType(EntityCreateScreen));
    expect(form.recordId, isNull);
    expect(form.title, startsWith('ทำซ้ำ'));
  });

  testWidgets('duplicate (quotation): confirm → server duplicate', (tester) async {
    const q = {'id': 9, 'quotation_no': 'QT-QA-9', 'subject': '[QA] ใบเสนอราคา R43', 'quotation_status': 'Draft'};
    final (adapter, _) = await pumpList(
      tester,
      module: 'quotation',
      row: q,
      statusKey: 'quotation_status',
      extra: {
        'POST /api/entity/quotation/9/duplicate': {'id': 10},
        'GET /api/entity/quotation/10': {'id': 10, 'subject': '[QA] ใบเสนอราคา R43 (copy)'},
      },
    );
    await longPressRow(tester, '[QA] ใบเสนอราคา R43');
    await tester.tap(find.byKey(const ValueKey('row-act-duplicate')));
    await settle(tester);
    expect(find.text('ทำซ้ำรายการนี้?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'ทำซ้ำ'));
    await settle(tester);
    expect(adapter.callKeys, contains('POST /api/entity/quotation/9/duplicate'));
  });

  testWidgets('delete: confirm → row hidden with undo → DELETE after 5 s', (tester) async {
    final (adapter, _) = await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-delete')));
    await settle(tester);
    expect(find.text('ลบรายการนี้?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await settle(tester);
    expect(find.text('[QA] ลูกค้าทดสอบ R43'), findsNothing, reason: 'hidden while the undo window is open');
    expect(adapter.callKeys, isNot(contains('DELETE /api/entity/lead/5')));
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(adapter.callKeys, contains('DELETE /api/entity/lead/5'));
  });

  testWidgets('select: enters the old multi-select mode', (tester) async {
    await pumpList(tester, module: 'lead', row: lead);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    await tester.tap(find.byKey(const ValueKey('row-act-select')));
    await settle(tester);
    expect(find.text('เลือก 1 รายการ'), findsOneWidget);
  });

  testWidgets('read-only shared record: only comment + select', (tester) async {
    await pumpList(tester, module: 'lead', row: {...lead, '_shared_permission': 'read_only'});
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    expect(find.byKey(const ValueKey('row-act-comment')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-act-select')), findsOneWidget);
    for (final k in ['status', 'edit', 'duplicate', 'delete']) {
      expect(find.byKey(ValueKey('row-act-$k')), findsNothing, reason: k);
    }
  });

  testWidgets('case: status opens the web-like case actions (no plain PUT)', (tester) async {
    const c = {'id': 7, 'case_no': 'CS-QA-7', 'case_name': '[QA] เคส R43', 'case_status': 'เปิดเคส'};
    final (adapter, _) = await pumpList(tester, module: 'case', row: c, statusKey: 'case_status', extra: {'GET /api/tags': {'list': []}});
    await longPressRow(tester, '[QA] เคส R43');
    await tester.tap(find.byKey(const ValueKey('row-act-status')));
    await settle(tester);
    expect(find.byKey(const ValueKey('case-action-accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('case-action-forward')), findsOneWidget);
    expect(find.byKey(const ValueKey('case-action-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('case-action-close')), findsNothing);
    expect(adapter.calls.where((x) => x.method == 'PUT'), isEmpty);
  });

  testWidgets('FSM job list uses the same sheet', (tester) async {
    const j = {'id': 11, 'job_no': 'JB-QA-11', 'subject': '[QA] งานช่าง R43', 'job_status': 'New'};
    await pumpList(tester, module: 'job', row: j, statusKey: 'job_status');
    await longPressRow(tester, '[QA] งานช่าง R43');
    expect(find.byKey(const ValueKey('row-act-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-act-edit')), findsOneWidget);
  });

  testWidgets('one-time tip under the toolbar, gone after the first long-press', (tester) async {
    await pumpList(tester, module: 'lead', row: lead, hintSeen: false);
    expect(find.byKey(const ValueKey('crm-row-hint')), findsOneWidget);
    await longPressRow(tester, '[QA] ลูกค้าทดสอบ R43');
    expect(find.byKey(const ValueKey('crm-row-hint')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('nx_crm_row_actions_hint_v1'), isTrue);
  });

  test('permissions follow the web rules', () {
    expect(EntityRowPerms.of('lead', {'_shared_permission': 'edit'}).canDelete, isFalse);
    expect(EntityRowPerms.of('lead', {'_shared_permission': 'edit'}).canEdit, isTrue);
    expect(EntityRowPerms.of('lead', {'lead_status': 'Converted'}).canEdit, isFalse);
    expect(EntityRowPerms.of('lead', {'convert_account_id': 3}).canStatus, isFalse);
    expect(EntityRowPerms.of('case', {}).canStatus, isTrue);
    expect(EntityRowPerms.of('deal', {}).canStatus, isTrue);
    expect(EntityRecordActions.webStatusColumn('service_contract'), 'contract_status');
    expect(
      EntityRecordActions.statusKey('deal', {
        'deal_stage': [
          {'value': 'Prospecting'},
        ],
      }),
      'deal_stage',
    );
  });
}
