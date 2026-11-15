import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_assistant.dart';
import 'package:nextx_mobile/core/ai_commands.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/nx_network.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_controller.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';

import 'support/fake_api.dart';

/// AI Assistant redesign: slash commands, `@` records, answer modes, edit and
/// resend, retry, remembered proposals, folders, smooth streaming.

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

String _sse(List<Map<String, dynamic>> frames) => [for (final f in frames) 'data: ${jsonEncode(f)}\n\n'].join();

final _okStream = _sse([
  {'type': 'auto_route', 'provider': 'claude', 'model': 'claude-x', 'steps': []},
  {'type': 'tool_start', 'name': 'search_entities'},
  {'type': 'tool_done', 'name': 'search_entities'},
  {'type': 'token', 'content': 'ได้เลย'},
  {'type': 'done', 'provider': 'claude', 'model': 'claude-x'},
]);

final _base = <String, Object?>{
  'GET /api/ai/conversations': [
    {'id': 7, 'title': '[QA] แชทเก่า', 'updated_at': '2026-11-08T03:00:00Z'},
  ],
  'GET /api/ai/projects': {'items': <Object>[]},
  'GET /api/ai/usage': {'meters_cloud': false},
  'GET /api/ai/suggested-prompts': <Map<String, dynamic>>[],
  'GET /api/ai/quick-prompts': {
    'items': [
      {'id': 1, 'code': 'weekly-sales', 'name_th': '[QA] ยอดขายรายสัปดาห์', 'prompt_th': 'สรุปยอดขายสัปดาห์นี้'},
    ],
  },
  'GET /api/ai/my-prompts': {
    'items': [
      {'id': 4, 'command': 'myday', 'title': '[QA] วันของฉัน', 'prompt': 'สรุปวันของฉัน [ทีม]'},
    ],
  },
  'POST /api/ai/conversations': {'id': 'c1', 'title': 'x'},
  'POST /api/ai/conversations/c1/messages': {'id': 101},
  'POST /api/ai/conversations/7/messages': {'id': 102},
  'POST /api/ai/reply-suggestions': <Object>[],
};

Future<(FakeNextxAdapter, AppConfig)> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 860),
  Map<String, Object?> extra = const {},
  Map<String, String> sse = const {},
  Map<String, int> status = const {},
  Map<String, Object> prefs = const {},
  AiAssistantController Function(AppConfig)? controller,
}) async {
  SharedPreferences.setMockInitialValues({'ai.slash_hint_seen': true, ...prefs});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_member);
  final adapter = FakeNextxAdapter({..._base, ...extra}, sseFor: {'POST /api/ai/chat': _okStream, ...sse}, statusFor: status);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(home: AiAssistantScreen(controller: controller?.call(config))),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (adapter, config);
}

Future<void> _settle(WidgetTester tester, [int frames = 14]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _body(FakeNextxAdapter a, String path, {bool last = true}) {
  final calls = a.calls.where((c) => c.path == path && c.method.toUpperCase() != 'GET').toList();
  final c = last ? calls.last : calls.first;
  return Map<String, dynamic>.from(c.data as Map);
}

void main() {
  group('commands', () {
    test('slash query only while typing the command at the start', () {
      expect(aiSlashQuery('/'), '');
      expect(aiSlashQuery('/le'), 'le');
      expect(aiSlashQuery('/lead x'), isNull);
      expect(aiSlashQuery('hi /lead'), isNull);
      expect(aiSlashQuery('/สรุ'), 'สรุ');
    });

    test('mention query after @ at a word start, up to 3 words', () {
      expect(aiMentionQuery('ดู @AB'), 'AB');
      expect(aiMentionQuery('@บริษัท เอ บี'), 'บริษัท เอ บี');
      expect(aiMentionQuery('mail a@b'), isNull);
      expect(aiMentionQuery('ไม่มี'), isNull);
      final r = aiStripMention('ดู @AB ด่วน', 6);
      expect(r.text, 'ดู  ด่วน');
      expect(r.cursor, 3);
    });

    test('template selects the first [ ] placeholder', () {
      final s = aiTemplateSelection('นัด [ลูกค้า] วัน [วัน]');
      expect('นัด [ลูกค้า] วัน [วัน]'.substring(s.start, s.end), '[ลูกค้า]');
      expect(aiTemplateSelection('ไม่มีช่อง').baseOffset, 'ไม่มีช่อง'.length);
    });

    test('filter: command prefix first, then title matches; slug keeps Thai', () {
      final r = aiFilterCommands(kAiBuiltinCommands, 'ส');
      expect(r.first.command.startsWith('ส'), isTrue);
      expect(aiFilterCommands(kAiBuiltinCommands, 'excel').first.command, 'excel');
      expect(aiCommandSlug('/Weekly Report'), 'weekly-report');
      expect(aiCommandSlug('สรุป งาน!'), 'สรุป-งาน');
    });

    test('chat body carries the answer mode only with Auto', () {
      final b = aiChatBody(history: const [], conversationId: '1', autoMode: 'deep', temperature: 0.3, injectContext: false);
      expect(b['auto_mode'], 'deep');
      expect(b['temperature'], 0.3);
      expect(b['inject_context'], false);
      expect(aiChatBody(history: const [], conversationId: '1', provider: 'gemini', model: 'g', autoMode: 'deep').containsKey('auto_mode'), isFalse);
      expect(aiChatBody(history: const [], conversationId: '1').containsKey('auto_mode'), isFalse);
    });
  });

  testWidgets('typing / shows built-in, business and my commands; picking one fills the template', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-slash-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-lead')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/my');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-cmd-mine-myday')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-cmd-builtin-lead')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/weekly');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-cmd-business-weekly-sales')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/อีเ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ai-cmd-builtin-อีเมล')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('ai-input')));
    expect(field.controller!.text, startsWith('ร่างอีเมลติดตามถึง'));
    final sel = field.controller!.selection;
    expect(field.controller!.text.substring(sel.start, sel.end), '[ลูกค้า]');
    await tester.pump(const Duration(milliseconds: 300)); // menu slides away
    expect(find.byKey(const ValueKey('ai-slash-menu')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('/วิเคราะห์ sends that one message in Deep mode', (tester) async {
    final (adapter, _) = await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/วิเคราะห์');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ai-cmd-builtin-วิเคราะห์')));
    await tester.pump();
    expect(find.text('คิดลึก (ครั้งนี้)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(_body(adapter, '/api/ai/chat')['auto_mode'], 'deep');
    expect(find.text('คิดลึก (ครั้งนี้)'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('mode sheet: Fast is sent as auto_mode and remembered', (tester) async {
    final (adapter, _) = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('ai-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-mode-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-mode-fast')));
    await tester.pumpAndSettle();
    expect(find.text('เร็ว'), findsOneWidget); // chip label
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ทดสอบ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    final body = _body(adapter, '/api/ai/chat');
    expect(body['auto'], true);
    expect(body['auto_mode'], 'fast');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai.mode'), 'fast');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('CRM data switch turns inject_context off', (tester) async {
    final (adapter, _) = await _pump(tester, prefs: {'ai.inject_context': false});
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ไม่ใช้ข้อมูล');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(_body(adapter, '/api/ai/chat')['inject_context'], false);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('@ finds a record, it becomes a chip and the chat context', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      extra: {
        'GET /api/entity/lead': [
          {'id': 55, 'lead_name': '[QA] ลูกค้า บี', 'lead_firstname': '[QA] ลูกค้า บี'},
        ],
      },
    );
    await tester.enterText(find.byKey(const ValueKey('ai-input')), 'สรุป @ลู');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-mention-picker')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.calls.where((c) => c.path == '/api/entity/lead').single.queryParameters['q'], 'ลู');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ai-mention-lead-55')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-context')), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('ai-input')));
    expect(field.controller!.text, 'สรุป ');
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    final body = _body(adapter, '/api/ai/chat');
    expect(body['context_module'], 'lead');
    expect(body['context_id'], '55');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tool steps show under the reply; badge names the model family', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] หา');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('ai-tool-steps')), findsOneWidget);
    expect(find.textContaining('ค้นหาข้อมูล ✓'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('edit a sent message: history replaced up to it, then answered again', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      extra: {
        'GET /api/ai/conversations/7': {
          'id': 7,
          'title': '[QA] แชทเก่า',
          'messages': [
            {'id': 1, 'role': 'user', 'content': '[QA] คำถามแรก'},
            {'id': 2, 'role': 'assistant', 'content': 'คำตอบแรก'},
            {'id': 3, 'role': 'user', 'content': '[QA] คำถามสอง'},
            {'id': 4, 'role': 'assistant', 'content': 'คำตอบสอง'},
          ],
        },
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-recent-7')));
    await _settle(tester, 6);
    await tester.longPress(find.text('[QA] คำถามแรก'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-act-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-dialog-field')), '[QA] คำถามแก้แล้ว');
    await tester.tap(find.byKey(const ValueKey('ai-dialog-ok')));
    await _settle(tester);
    final replace = adapter.calls.firstWhere((c) => c.path == '/api/ai/conversations/7/messages' && (c.data as Map)['replace'] == true);
    final msgs = (replace.data as Map)['messages'] as List;
    expect(msgs.length, 1);
    expect((msgs.single as Map)['content'], '[QA] คำถามแก้แล้ว');
    final chat = _body(adapter, '/api/ai/chat');
    expect((chat['messages'] as List).last['content'], '[QA] คำถามแก้แล้ว');
    expect(find.text('[QA] คำถามสอง'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('retry after a failed first reply streams again (no regenerate call)', (tester) async {
    final (adapter, _) = await _pump(tester, status: {'POST /api/ai/chat': 503});
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ลองใหม่');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('ai-error')), findsOneWidget);
    adapter.statusFor.remove('POST /api/ai/chat');
    await tester.tap(find.text('ลองใหม่'));
    await _settle(tester);
    expect(adapter.calls.where((c) => c.path == '/api/ai/chat').length, 2);
    expect(adapter.callKeys, isNot(contains('POST /api/ai/conversations/c1/regenerate')));
    expect(find.byKey(const ValueKey('ai-error')), findsNothing);
    expect(find.text('ได้เลย'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a proposal done on the server stays done; confirm sends conversation + message', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      extra: {
        'GET /api/ai/conversations/7': {
          'id': 7,
          'title': '[QA] แชทเก่า',
          'messages': [
            {'id': 1, 'role': 'user', 'content': '[QA] สร้าง lead'},
            {
              'id': 2,
              'role': 'assistant',
              'content': 'พร้อม',
              'proposals': [
                {'proposalId': 'done1', 'tool': 'create_lead', 'preview': {}, 'status': 'done', 'link': '/modules/lead/view/9'},
                {'proposalId': 'new1', 'tool': 'create_case', 'preview': {}},
              ],
            },
          ],
        },
        'POST /api/ai/tools/confirm': {'ok': true},
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-recent-7')));
    await _settle(tester, 6);
    expect(find.byKey(const ValueKey('ai-proposal-open')), findsOneWidget); // done one: open record
    expect(find.byKey(const ValueKey('ai-proposal-confirm')), findsOneWidget); // only the new one
    await tester.ensureVisible(find.byKey(const ValueKey('ai-proposal-confirm')));
    await tester.tap(find.byKey(const ValueKey('ai-proposal-confirm')));
    await _settle(tester, 4);
    final body = _body(adapter, '/api/ai/tools/confirm');
    expect(body['proposalId'], 'new1');
    expect(body['conversation_id'], 7);
    expect(body['message_id'], 2);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('folder: create from the history with name, colour and instructions', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      size: const Size(1200, 900),
      extra: {
        'POST /api/ai/projects': {'id': 12, 'name': '[QA] ทีมขาย'},
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-folder-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-folder-name')), '[QA] ทีมขาย');
    await tester.enterText(find.byKey(const ValueKey('ai-folder-instructions')), '[QA] ตอบเป็นข้อ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-folder-save')));
    await tester.pumpAndSettle();
    final body = _body(adapter, '/api/ai/projects');
    expect(body['name'], '[QA] ทีมขาย');
    expect(body['instructions'], '[QA] ตอบเป็นข้อ');
    expect(body['color'], kAiFolderColors.first);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('new chat from a folder page is filed in that folder', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      size: const Size(1200, 900),
      extra: {
        'GET /api/ai/projects': {
          'items': [
            {'id': 3, 'name': '[QA] โฟลเดอร์', 'chat_count': 0},
          ],
        },
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-folder-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-folder-new-chat')));
    await tester.pumpAndSettle();
    expect(find.text('แชทใหม่ในโฟลเดอร์ [QA] โฟลเดอร์'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ในโฟลเดอร์');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(_body(adapter, '/api/ai/conversations', last: false)['project_id'], 3);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tokens do not rebuild the whole screen: listeners fire far fewer times than tokens', (tester) async {
    final tokens = [
      for (var i = 0; i < 60; i++) {'type': 'token', 'content': 'ก'},
    ];
    late AiAssistantController c;
    await _pump(
      tester,
      sse: {
        'POST /api/ai/chat': _sse([
          ...tokens,
          {'type': 'done', 'provider': 'claude', 'model': 'claude-x'},
        ]),
      },
      controller: (config) => c = AiAssistantController(config.apiClient),
    );
    var notifies = 0;
    var ticks = 0;
    c.addListener(() => notifies++);
    c.streamTick.addListener(() => ticks++);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ยาว');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester);
    expect(c.messages.last.content.length, 60);
    expect(notifies, lessThan(30), reason: 'screen-level rebuilds');
    expect(ticks, lessThan(60));
    await tester.pump(const Duration(seconds: 4));
    c.dispose();
  });

  testWidgets('scrolled up: no jump to the bottom, a ↓ button brings you back', (tester) async {
    final long = 'บรรทัดยาว\n' * 40;
    await _pump(
      tester,
      extra: {
        'GET /api/ai/conversations/7': {
          'id': 7,
          'title': '[QA] แชทเก่า',
          'messages': [
            for (var i = 0; i < 6; i++) ...[
              {'role': 'user', 'content': '[QA] ถาม $i'},
              {'role': 'assistant', 'content': long},
            ],
          ],
        },
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-recent-7')));
    await _settle(tester, 8);
    final list = find.byKey(const ValueKey('ai-messages'));
    // The list's own Scrollable (answers may hold sideways scrollers too).
    final scrollable = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first);
    final max = scrollable.position.maxScrollExtent;
    expect(scrollable.position.pixels, closeTo(max, 1)); // opened at the bottom
    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();
    final up = scrollable.position.pixels;
    expect(up, lessThan(max - 200));
    expect(find.byKey(const ValueKey('ai-jump-bottom')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, up); // stays where the user is
    await tester.tap(find.byKey(const ValueKey('ai-jump-bottom')));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(scrollable.position.maxScrollExtent, 1));
    expect(find.byKey(const ValueKey('ai-jump-bottom')), findsNothing);
  });

  testWidgets('first run shows the "/ and @" hint once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = AppConfig()..debugOverrideSession(_member);
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter(_base));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: AiAssistantScreen()),
      ),
    );
    await _settle(tester, 6);
    expect(find.byKey(const ValueKey('ai-slash-hint')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '/');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-slash-hint')), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('ai.slash_hint_seen'), isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('quick action "สร้าง" lists only what the user may create', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('ai-quick-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-create-lead')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-create-case')), findsNothing); // no case menu
    expect(find.byKey(const ValueKey('ai-create-contact')), findsNothing);
  });

  testWidgets('a message the server failed to save shows "ยังไม่บันทึก" and can be saved again', (tester) async {
    final (adapter, _) = await _pump(tester, status: {'POST /api/ai/conversations/c1/messages': 500});
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] บันทึกไม่ได้');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester, 30);
    expect(find.text('ยังไม่บันทึก · ลองอีกครั้ง'), findsWidgets);
    adapter.statusFor.remove('POST /api/ai/conversations/c1/messages');
    await tester.tap(find.text('ยังไม่บันทึก · ลองอีกครั้ง').first);
    await _settle(tester, 6);
    expect(find.text('ยังไม่บันทึก · ลองอีกครั้ง'), findsNWidgets(1)); // one left (the reply)
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('offline: banner shows and send does not call the server', (tester) async {
    final (adapter, _) = await _pump(tester);
    NxNetwork.instance.online.value = false;
    addTearDown(() => NxNetwork.instance.online.value = true);
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-offline')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ออฟไลน์');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await _settle(tester, 4);
    expect(adapter.callKeys, isNot(contains('POST /api/ai/chat')));
    expect(find.text('[QA] ออฟไลน์'), findsOneWidget, reason: 'text kept in the box');
    NxNetwork.instance.online.value = true;
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('an archived chat says so and can be brought back', (tester) async {
    final (adapter, _) = await _pump(
      tester,
      extra: {
        'GET /api/ai/conversations/7': {
          'id': 7,
          'title': '[QA] แชทเก่า',
          'archived': 1,
          'messages': [
            {'role': 'user', 'content': '[QA] เก่า'},
          ],
        },
        'PATCH /api/ai/conversations/7': {'id': 7},
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-recent-7')));
    await _settle(tester, 6);
    expect(find.byKey(const ValueKey('ai-archived-banner')), findsOneWidget);
    await tester.tap(find.text('นำกลับ'));
    await _settle(tester, 6);
    expect(_body(adapter, '/api/ai/conversations/7')['archived'], false);
    expect(find.byKey(const ValueKey('ai-archived-banner')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
}
