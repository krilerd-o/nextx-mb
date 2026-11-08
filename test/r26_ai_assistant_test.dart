import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_assistant.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_states.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_controller.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_cards.dart';
import 'package:nextx_mobile/services/api_exceptions.dart';
import 'package:nextx_mobile/widgets/nx_markdown.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

String _sse(List<Map<String, dynamic>> frames) => [
      ': heartbeat\n\n',
      for (final f in frames) 'data: ${jsonEncode(f)}\n\n',
    ].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SSE parser', () {
    test('frames split across chunks, heartbeats skipped, tokens join', () async {
      final raw = _sse([
        {'type': 'status', 'phase': 'thinking'},
        {'type': 'token', 'content': 'สวัส'},
        {'type': 'token', 'content': 'ดี'},
        {'type': 'done', 'provider': 'gemini', 'model': 'gemini-2.5-flash'},
      ]);
      // Cut the bytes at odd places like a real network.
      final chunks = <String>[for (var i = 0; i < raw.length; i += 7) raw.substring(i, i + 7 > raw.length ? raw.length : i + 7)];
      final evs = await parseAiSse(Stream.fromIterable(chunks)).toList();
      expect(evs.map((e) => e.type), ['status', 'token', 'token', 'done']);
      expect(evs.where((e) => e.type == 'token').map((e) => e.token).join(), 'สวัสดี');
      expect(evs.last.data['model'], 'gemini-2.5-flash');
    });

    test('bad json and [DONE] are ignored; last frame without blank line kept', () async {
      final evs = await parseAiSse(Stream.fromIterable([
        'data: {oops\n\n',
        'data: [DONE]\n\n',
        'data: {"type":"error","error_code":"AI_QUOTA_EXHAUSTED","message":"หมด"}',
      ])).toList();
      expect(evs.single.type, 'error');
      expect(evs.single.data['error_code'], 'AI_QUOTA_EXHAUSTED');
    });
  });

  test('chats grouped: starred, today, yesterday, earlier (Thai time)', () {
    final now = DateTime.utc(2026, 11, 8, 5); // 12:00 Bangkok
    final g = groupAiChats([
      const AiConversation(id: '1', title: 'a', updatedAt: '2026-11-08T03:00:00Z'),
      const AiConversation(id: '2', title: 'b', updatedAt: '2026-11-07T03:00:00Z'),
      const AiConversation(id: '3', title: 'c', updatedAt: '2026-10-01T03:00:00Z'),
      const AiConversation(id: '4', title: 'd', starred: true, updatedAt: '2026-10-01T03:00:00Z'),
    ], now: now);
    expect([for (final x in g) x.label], ['ติดดาว', 'วันนี้', 'เมื่อวาน', 'ก่อนหน้า']);
    expect(g.first.items.single.id, '4');
  });

  test('Isaac mood follows the chat', () {
    expect(resolveIsaacState(welcome: true), 'hello');
    expect(resolveIsaacState(composerFocused: true, draftLength: 3), 'listening');
    expect(resolveIsaacState(streaming: true), 'speaking');
    expect(resolveIsaacState(error: true, loading: true), 'error');
    expect(resolveIsaacState(hasDownloads: true), 'celebrate');
    expect(resolveIsaacState(finishedAgoMs: 100), 'done');
    expect(kIsaacStates.length, 60);
    expect(kIsaacLabels.keys.toSet(), kIsaacStates.toSet());
  });

  test('in-app links: workspace/modules open in the app, others outside', () {
    expect(aiInAppRoute('/workspace/BAFCSI-3'), isNotNull);
    expect(aiInAppRoute('/modules/lead/view/12'), isNotNull);
    expect(aiInAppRoute('https://qa.example.com/workspace/KF-1', serverOrigin: 'https://qa.example.com'), isNotNull);
    expect(aiInAppRoute('https://google.com/workspace/x', serverOrigin: 'https://qa.example.com'), isNull);
    expect(aiInAppRoute('/uploads/a.pdf'), isNull);
  });

  Future<(FakeNextxAdapter, AppConfig)> pump(WidgetTester tester, Widget screen, Map<String, Object?> replies,
      {Map<String, String> sse = const {}, Map<String, int> status = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig()..debugOverrideSession(_member);
    final adapter = FakeNextxAdapter(replies, sseFor: sse, statusFor: status);
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (adapter, config);
  }

  final base = <String, Object?>{
    'GET /api/ai/conversations': <Map<String, dynamic>>[],
    'GET /api/ai/usage': {'meters_cloud': false},
    'GET /api/ai/suggested-prompts': <Map<String, dynamic>>[],
    'POST /api/ai/conversations': {'id': 'c1', 'title': '[QA] สรุปลูกค้า'},
    'POST /api/ai/conversations/c1/messages': {'ok': true},
    'POST /api/ai/reply-suggestions': [
      {'label': 'ดูรายละเอียดเพิ่ม', 'prompt': 'ขอรายละเอียดเพิ่ม'},
    ],
  };

  testWidgets('send: create chat → save user → stream → save reply, then follow-ups', (tester) async {
    final (adapter, _) = await pump(tester, const AiAssistantScreen(), base, sse: {
      'POST /api/ai/chat': _sse([
        {'type': 'auto_route', 'provider': 'gemini', 'model': 'gemini-2.5-flash', 'steps': []},
        {'type': 'token', 'content': '| ชื่อ | สถานะ |\n|---|---|\n| [QA] ลูกค้า | Open |\n'},
        {'type': 'done', 'provider': 'gemini', 'model': 'gemini-2.5-flash'},
      ]),
    });
    expect(find.byKey(const ValueKey('ai-welcome')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] สรุปลูกค้า');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final keys = adapter.callKeys.where((k) => !k.startsWith('GET')).toList();
    expect(keys.take(4), [
      'POST /api/ai/conversations',
      'POST /api/ai/conversations/c1/messages',
      'POST /api/ai/chat',
      'POST /api/ai/conversations/c1/messages',
    ]);
    final chat = adapter.calls.firstWhere((c) => c.path == '/api/ai/chat');
    final body = Map<String, dynamic>.from(chat.data as Map);
    expect(body['stream'], true);
    expect(body['conversation_id'], 'c1');
    final saves = adapter.calls.where((c) => c.path == '/api/ai/conversations/c1/messages').toList();
    final reply = Map<String, dynamic>.from((saves.last.data as Map)['message'] as Map);
    expect(reply['role'], 'assistant');
    expect(reply['model'], 'gemini-2.5-flash');

    expect(find.byType(NxMarkdown), findsOneWidget);
    expect(find.text('[QA] ลูกค้า'), findsOneWidget); // GFM table cell
    expect(find.text('gemini-2.5-flash'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-followups')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('stream error shows the banner, message kept', (tester) async {
    await pump(tester, const AiAssistantScreen(), base, sse: {
      'POST /api/ai/chat': _sse([
        {'type': 'error', 'error_code': 'AI_PROVIDER_NOT_CONFIGURED', 'message': 'ยังไม่ได้ตั้งค่า AI'},
      ]),
    });
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ทดสอบ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('ai-error')), findsOneWidget);
    expect(find.text('[QA] ทดสอบ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('HTTP error before the stream (503 AI_AUTO_NO_MODEL) shows Thai text', (tester) async {
    await pump(tester, const AiAssistantScreen(), base, status: {'POST /api/ai/chat': 503});
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] สวัสดี');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('ai-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-stop')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  test('error text for the QA server reply', () {
    expect(aiErrorText(ApiEnvelopeException(503, 'AI_AUTO_NO_MODEL', 'x')), contains('ยังไม่มีโมเดล AI'));
  });

  testWidgets('proposal card: confirm calls /tools/confirm and shows done', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig()..debugOverrideSession(_member);
    final adapter = FakeNextxAdapter({
      'POST /api/ai/tools/confirm': {'ok': true, 'link_path': '/modules/lead/view/99'},
    });
    config.apiClient.debugSetHttpAdapter(adapter);
    final c = AiAssistantController(config.apiClient);
    final p = {
      'proposalId': 'p1',
      'summary': 'สร้าง Lead [QA] ทดสอบ',
      'preview': {
        'fields': {'lastname': '[QA] ทดสอบ'},
      },
    };
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => AiProposalCard(proposal: p, state: c.proposalState['p1'], onConfirm: () => c.confirmProposal(p), onCancel: () => c.cancelProposal(p)),
          ),
        ),
      ),
    ));
    expect(find.text('[QA] ทดสอบ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-proposal-confirm')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.callKeys, contains('POST /api/ai/tools/confirm'));
    expect(Map<String, dynamic>.from(adapter.calls.last.data as Map)['proposalId'], 'p1');
    expect(find.byKey(const ValueKey('ai-proposal-confirm')), findsNothing);
    c.dispose();
  });

  testWidgets('markdown: code block has copy, tables render as rows', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NxMarkdown(data: '# หัวข้อ\n\n```json\n{"a":1}\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |\n'),
        ),
      ),
    ));
    expect(find.text('หัวข้อ'), findsOneWidget);
    expect(find.byType(NxCodeBlock), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-code-copy')), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
  });
}
