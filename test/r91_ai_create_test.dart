import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_fill.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';

import 'support/fake_api.dart';

/// "/" create commands make real records: a full form (owner = me, changeable),
/// Isaac fills it from text, required fields block saving, the result card
/// joins the chat; Isaac's own proposals can be finished in the form.

SessionState _session(List<String> menus) =>
    SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: 'QA Me', menusLoaded: true, menuKeys: ['ai-assistant', ...menus]);

String _sse(List<Map<String, dynamic>> frames) => [for (final f in frames) 'data: ${jsonEncode(f)}\n\n'].join();

const _leadFields = {
  'list': [
    {'name': 'lead_firstname', 'label_th': 'ชื่อ', 'uitype': 'Text', 'required': true},
    {'name': 'lead_lastname', 'label_th': 'นามสกุล', 'uitype': 'Text'},
    {'name': 'company_name', 'label_th': 'บริษัท', 'uitype': 'Text'},
    {'name': 'mobile_1st', 'label_th': 'มือถือ', 'uitype': 'Phone'},
    {'name': 'smownerid', 'label_th': 'ผู้รับผิดชอบ', 'uitype': 'PicklistUser', 'required': true},
  ],
  'picklists': <String, Object>{},
};

const _activityFields = {
  'list': [
    {'name': 'subject', 'label_th': 'หัวข้อ', 'uitype': 'Text', 'required': true},
    {'name': 'date_start', 'label_th': 'เริ่ม', 'uitype': 'DateTime'},
    {'name': 'smownerid', 'label_th': 'ผู้รับผิดชอบ', 'uitype': 'PicklistUser'},
  ],
  'picklists': <String, Object>{},
};

final _base = <String, Object?>{
  'GET /api/ai/conversations': <Object>[],
  'GET /api/ai/projects': {'items': <Object>[]},
  'GET /api/ai/usage': {'meters_cloud': false},
  'GET /api/ai/suggested-prompts': <Object>[],
  'GET /api/ai/quick-prompts': {'items': <Object>[]},
  'GET /api/ai/my-prompts': {'items': <Object>[]},
  'GET /api/fields/lead': _leadFields,
  'GET /api/fields/activity': _activityFields,
  'POST /api/ai/conversations': {'id': 'c1', 'title': 'x'},
  'POST /api/ai/conversations/c1/messages': {'id': 201},
  'POST /api/ai/reply-suggestions': <Object>[],
  'POST /api/entity/lead': {'id': 77},
  'POST /api/entity/activity': {'id': 88},
  'POST /api/ai/extract-fields': {
    'fields': {
      'lead_firstname': {'value': 'สมชาย', 'confidence': 'high', 'source': 'ai'},
      'company_name': {'value': 'ABC', 'confidence': 'high', 'source': 'ai'},
      'mobile_1st': {'value': '0812345678', 'confidence': 'high', 'source': 'ai'},
      'smownerid': {
        'value': null,
        'hint': 'คุณเอ',
        'candidates': [
          {'id': 5, 'label': 'A One'},
          {'id': 6, 'label': 'A Two'},
        ],
        'confidence': 'low',
      },
    },
    'missing_required': <Object>[],
    'duplicates': [
      {'module': 'lead', 'id': 9, 'name': 'สมชาย เดิม', 'reason': 'เบอร์โทร'},
    ],
  },
};

Future<FakeNextxAdapter> _pump(
  WidgetTester tester, {
  List<String> menus = const ['lead'],
  Map<String, Object?> extra = const {},
  Map<String, String> sse = const {},
}) async {
  SharedPreferences.setMockInitialValues({'ai.slash_hint_seen': true});
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_session(menus));
  final adapter = FakeNextxAdapter({..._base, ...extra}, sseFor: sse);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: AiAssistantScreen()),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

Future<void> _settle(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Map<String, dynamic> _body(FakeNextxAdapter a, String method, String path) =>
    Map<String, dynamic>.from(a.calls.lastWhere((c) => c.method.toUpperCase() == method && c.path == path).data as Map);

Future<void> _pickSlash(WidgetTester tester, String query, String key) async {
  await tester.enterText(find.byKey(const ValueKey('ai-input')), '/$query');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('entity-save')));
  await tester.tap(find.byKey(const ValueKey('entity-save')));
  await _settle(tester);
}

void main() {
  test('extract-fields result: people as {id,label}, hints with candidates, missing, duplicates', () {
    final r = AiFillResult.fromJson({
      'fields': {
        'smownerid': {'value': 5, 'label': 'A One'},
        'lead_firstname': {'value': 'สมชาย'},
        'related_account_id': {'value': null, 'hint': 'XYZ'},
      },
      'missing_required': [
        {'field': 'lead_status', 'label': 'สถานะ'},
      ],
      'duplicates': [
        {'id': 1},
      ],
    });
    expect(r.values['smownerid'], {'id': '5', 'label': 'A One'});
    expect(r.values['lead_firstname'], 'สมชาย');
    expect(r.filled, ['smownerid', 'lead_firstname']);
    expect(r.hints['related_account_id']!.text, 'XYZ');
    expect(r.missing.single['field'], 'lead_status');
    expect(r.duplicates.length, 1);
  });

  testWidgets('/lead + text → Isaac fills the form (owner = me), pick the real assignee, save → card in chat', (tester) async {
    final a = await _pump(tester);
    await _pickSlash(tester, 'le', 'ai-cmd-builtin-lead');
    expect(find.byKey(const ValueKey('ai-create-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-slash-menu')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), 'คุณสมชาย ABC 081-234-5678 ให้คุณเอดูแล');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester, 16);

    // No chat message went out: the form opened instead, and Isaac filled it.
    expect(a.callKeys, isNot(contains('POST /api/ai/chat')));
    final ex = _body(a, 'POST', '/api/ai/extract-fields');
    expect(ex['module'], 'lead');
    expect(ex['text'], contains('ABC'));
    expect(find.byKey(const ValueKey('ai-fill-box')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-filled-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-filled-lead_firstname')), findsOneWidget);
    expect(find.textContaining('อาจซ้ำกับ สมชาย เดิม'), findsOneWidget);
    expect(find.text('QA Me'), findsWidgets, reason: 'owner defaults to me');

    // Isaac read "คุณเอ" but two users match: pick one.
    await tester.ensureVisible(find.byKey(const ValueKey('ai-hint-smownerid-6')));
    await tester.tap(find.byKey(const ValueKey('ai-hint-smownerid-6')));
    await tester.pump();
    await _save(tester);

    final saved = _body(a, 'POST', '/api/entity/lead');
    expect(saved['lead_firstname'], 'สมชาย');
    expect(saved['company_name'], 'ABC');
    expect('${saved['smownerid']}', '6');
    // Back in the chat: a done card with the link, saved to the conversation.
    expect(find.byKey(const ValueKey('ai-proposal-open')), findsOneWidget);
    expect(find.textContaining('สร้าง Lead'), findsWidgets); // message + card title
    final msg = Map<String, dynamic>.from(_body(a, 'POST', '/api/ai/conversations/c1/messages')['message'] as Map);
    final p = Map<String, dynamic>.from((msg['proposals'] as List).single as Map);
    expect(p['status'], 'done');
    expect(p['link'], '/modules/lead/view/77');
    expect((p['preview'] as Map)['owner'], {'id': '6', 'label': 'A Two'});
    expect(find.byKey(const ValueKey('ai-followup-appt-77')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a required field left empty blocks saving', (tester) async {
    final a = await _pump(tester);
    await _pickSlash(tester, 'le', 'ai-cmd-builtin-lead');
    await tester.tap(find.byKey(const ValueKey('ai-send'))); // no text: plain form
    await _settle(tester);
    expect(a.callKeys, isNot(contains('POST /api/ai/extract-fields')));
    await _save(tester);
    expect(a.callKeys, isNot(contains('POST /api/entity/lead')));
    expect(find.textContaining('ยังไม่ได้กรอก'), findsOneWidget);
  });

  testWidgets('create commands follow menu access', (tester) async {
    await _pump(tester); // lead only
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('ai-cmd-builtin-lead')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-contact')), findsNothing);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-นัด')), findsNothing);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-งาน')), findsNothing);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-สรุป')), findsOneWidget, reason: 'non-create commands stay');
  });

  testWidgets('typing "/นัด …" and sending opens the appointment form linked to the @record', (tester) async {
    final a = await _pump(
      tester,
      menus: const ['lead', 'calendar'],
      extra: {
        'GET /api/entity/lead': [
          {'id': 55, 'lead_firstname': '[QA] ลูกค้า บี'},
        ],
        'POST /api/ai/extract-fields': {
          'fields': {
            'subject': {'value': 'คุยงาน'},
            'date_start': {'value': '2026-11-16 10:00:00'},
          },
          'missing_required': <Object>[],
        },
      },
    );
    // @ the customer first.
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '@ลู');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('ai-mention-lead-55')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/นัด คุยงานพรุ่งนี้ 10 โมง');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester, 16);
    final ex = _body(a, 'POST', '/api/ai/extract-fields');
    expect(ex['module'], 'activity');
    expect((ex['context'] as Map)['id'], 55);
    await _save(tester);
    final saved = _body(a, 'POST', '/api/entity/activity');
    expect(saved['subject'], 'คุยงาน');
    expect(saved['related_module'], 'lead');
    expect(saved['related_id'], '55');
    expect('${saved['smownerid']}', '2'); // me
    expect(find.byKey(const ValueKey('ai-proposal-open')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('/งาน: pick the board, Isaac fills, assignee defaults to me → task created', (tester) async {
    final a = await _pump(
      tester,
      menus: const ['workspace'],
      extra: {
        'GET /api/boards': [
          {'id': 11, 'name': '[QA] บอร์ด 1'},
          {'id': 12, 'name': '[QA] บอร์ด 2'},
        ],
        'GET /api/boards/12/statuses': [
          {'id': 1, 'name': 'To do', 'is_initial': true},
        ],
        'GET /api/boards/12/epics': <Object>[],
        'GET /api/boards/12': {'id': 12, 'name': '[QA] บอร์ด 2'},
        'GET /api/users': [
          {'id': 2, 'first_name': 'QA', 'last_name': 'Me'},
        ],
        'POST /api/ai/extract-fields': {
          'fields': {
            'title': {'value': 'ทำสไลด์ขาย'},
            'priority': {'value': 'high'},
          },
        },
        'POST /api/boards/12/tasks': {'id': 301, 'title': 'ทำสไลด์ขาย', 'assignee_id': 2},
      },
    );
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/งาน ทำสไลด์ขาย ด่วน');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-board-12')));
    await _settle(tester, 16);
    expect(find.byKey(const ValueKey('ai-fill-box')), findsOneWidget, reason: 'Isaac box in the task form too');
    expect(find.byKey(const ValueKey('ai-filled-title')), findsOneWidget);
    expect(_body(a, 'POST', '/api/ai/extract-fields')['module'], 'workspace_item');
    expect(find.text('ทำสไลด์ขาย'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('ws-save')));
    await tester.tap(find.byKey(const ValueKey('ws-save')));
    await _settle(tester, 16);
    final body = _body(a, 'POST', '/api/boards/12/tasks');
    final msgP = Map<String, dynamic>.from(_body(a, 'POST', '/api/ai/conversations/c1/messages')['message'] as Map);
    expect((((msgP['proposals'] as List).single as Map)['preview'] as Map)['fields']['priority'], 'สูง', reason: 'Thai label on the card');
    expect(body['title'], 'ทำสไลด์ขาย');
    expect('${body['assignee_id']}', '2');
    final msg = Map<String, dynamic>.from(_body(a, 'POST', '/api/ai/conversations/c1/messages')['message'] as Map);
    expect(((msg['proposals'] as List).single as Map)['link'], '/workspace?board=12&task=301');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets("Isaac's proposal missing data → \"กรอกให้ครบ\" opens the form; saving cancels the proposal", (tester) async {
    final a = await _pump(
      tester,
      sse: {
        'POST /api/ai/chat': _sse([
          {
            'type': 'tool_proposal',
            'proposal': {
              'proposalId': 'p9',
              'tool': 'create_lead',
              'preview': {
                'module': 'lead',
                'fields': {'company_name': 'ABC'},
                'owner': {'id': 2, 'label': 'QA Me'},
                'missing_required': [
                  {'field': 'lead_firstname', 'label': 'ชื่อ'},
                ],
              },
            },
          },
          {'type': 'token', 'content': 'เตรียมสร้าง Lead ให้แล้ว'},
          {'type': 'done'},
        ]),
      },
      extra: {
        'POST /api/ai/tools/cancel': {'cancelled': true},
      },
    );
    await tester.enterText(find.byKey(const ValueKey('ai-input')), 'สร้าง lead บริษัท ABC');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('ai-proposal-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-proposal-confirm')), findsNothing);
    expect(find.text('QA Me'), findsOneWidget, reason: 'owner shown by name');
    await tester.ensureVisible(find.byKey(const ValueKey('ai-proposal-complete')));
    await tester.tap(find.byKey(const ValueKey('ai-proposal-complete')));
    await _settle(tester, 16);
    final firstName = find.descendant(
      of: find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.endsWith('-lead_firstname')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(firstName.first);
    await tester.enterText(firstName.first, 'สมหญิง');
    await tester.pump();
    await _save(tester);
    final saved = _body(a, 'POST', '/api/entity/lead');
    expect(saved['company_name'], 'ABC');
    expect(saved['lead_firstname'], 'สมหญิง');
    expect(_body(a, 'POST', '/api/ai/tools/cancel')['proposalId'], 'p9');
    expect(find.text('บันทึกผ่านฟอร์มแล้ว'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('/quotation: Isaac fills the customer and product lines, the form says so', (tester) async {
    final a = await _pump(
      tester,
      menus: const ['quotation'],
      extra: {
        'GET /api/fields/quotation': {'list': <Object>[], 'picklists': <String, Object>{}},
        'GET /api/quotation/context': <String, Object>{},
        'POST /api/ai/extract-fields': {
          'fields': {
            'customer_name': {'value': 'ABC Co., Ltd.'},
            'subject': {'value': 'ใบเสนอราคา CRM'},
          },
          'lines': [
            {'description': 'ระบบ CRM', 'quantity': 10, 'unit': 'ผู้ใช้', 'unit_price': 1500},
          ],
        },
      },
    );
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/quotation CRM 10 ผู้ใช้ คนละ 1500 ให้ ABC');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester, 20);
    expect(_body(a, 'POST', '/api/ai/extract-fields')['module'], 'quotation');
    expect(find.byKey(const ValueKey('docform-ai-banner')), findsOneWidget);
    expect(find.textContaining('1 รายการสินค้า'), findsOneWidget);
    expect(find.text('ABC Co., Ltd.'), findsWidgets);
  });
}
