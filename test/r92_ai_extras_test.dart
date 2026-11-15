import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_commands.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_speaker.dart';
import 'package:nextx_mobile/services/device_push_service.dart';

import 'support/fake_api.dart';

/// 👍/👎, read aloud, search inside messages, "ไอแซคตอบแล้ว" when you leave
/// mid-answer, deep links (chat / cmd / share_text), Home command usage.

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

String _sse(List<Map<String, dynamic>> frames) => [for (final f in frames) 'data: ${jsonEncode(f)}\n\n'].join();

final _base = <String, Object?>{
  'GET /api/ai/conversations': [
    {'id': 7, 'title': '[QA] แชทเก่า', 'updated_at': '2026-11-08T03:00:00Z'},
  ],
  'GET /api/ai/projects': {'items': <Object>[]},
  'GET /api/ai/usage': {'meters_cloud': false},
  'GET /api/ai/suggested-prompts': <Object>[],
  'GET /api/ai/quick-prompts': {'items': <Object>[]},
  'GET /api/ai/my-prompts': {'items': <Object>[]},
  'GET /api/ai/conversations/7': {
    'id': 7,
    'title': '[QA] แชทเก่า',
    'messages': [
      {'id': 1, 'role': 'user', 'content': '[QA] ยอดขาย'},
      {'id': 2, 'role': 'assistant', 'content': '**ยอดขาย** เดือนนี้ 10 รายการ', 'feedback': {'rating': 1}},
    ],
  },
  'POST /api/ai/conversations/7/messages/2/feedback': {'rating': -1},
  'POST /api/ai/conversations': {'id': 'c1', 'title': 'x'},
  'POST /api/ai/conversations/c1/messages': {'id': 301},
  'POST /api/ai/reply-suggestions': <Object>[],
  'POST /api/ai/tts': {'downloadUrl': '/api/ai/exports/tok'},
  'GET /api/ai/exports/tok': Uint8List.fromList([1, 2, 3]),
};

Future<FakeNextxAdapter> _pump(WidgetTester tester, {Widget? screen, Map<String, Object?> extra = const {}, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'ai.slash_hint_seen': true, ...prefs});
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_member);
  final adapter = FakeNextxAdapter(
    {..._base, ...extra},
    sseFor: {
      'POST /api/ai/chat': _sse([
        {'type': 'token', 'content': 'ตอบแล้วนะ'},
        {'type': 'done'},
      ]),
    },
  );
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen ?? const AiAssistantScreen())));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

Future<void> _settle(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _openChat7(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-recent-7')));
  await _settle(tester, 6);
}

void main() {
  testWidgets('👍 shows as chosen from the server; 👎 asks why and sends the reason', (tester) async {
    final a = await _pump(tester);
    await _openChat7(tester);
    final up = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('ai-thumb-up')), matching: find.byType(Icon)));
    expect(up.color, isNot(null));
    await tester.tap(find.byKey(const ValueKey('ai-thumb-down')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-thumb-down-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-thumb-reason-ตอบไม่ครบ')));
    await _settle(tester);
    final body = Map<String, dynamic>.from(a.calls.lastWhere((c) => c.path == '/api/ai/conversations/7/messages/2/feedback').data as Map);
    expect(body['rating'], -1);
    expect(body['note'], 'ตอบไม่ครบ');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('อ่านออกเสียง: server TTS then playback; tap again stops', (tester) async {
    Uint8List? played;
    AiSpeaker.debugPlay = (b) async => played = b;
    addTearDown(() {
      AiSpeaker.debugPlay = null;
      AiSpeaker.instance.speaking.value = null;
    });
    final a = await _pump(tester);
    await _openChat7(tester);
    await tester.tap(find.byKey(const ValueKey('ai-speak')));
    await _settle(tester);
    final tts = Map<String, dynamic>.from(a.calls.lastWhere((c) => c.path == '/api/ai/tts').data as Map);
    expect(tts['text'], contains('ยอดขาย'));
    expect(played, [1, 2, 3]);
    expect(find.byTooltip('หยุดอ่าน'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-speak')));
    await tester.pump();
    expect(AiSpeaker.instance.speaking.value, isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('search finds words inside a chat and shows the snippet', (tester) async {
    final a = await _pump(tester, extra: {
      'GET /api/ai/conversations': [
        {'id': 7, 'title': '[QA] แชทเก่า', 'updated_at': '2026-11-08T03:00:00Z', 'snippet': '…ยอดขายไตรมาสสาม 1.2 ล้าน'},
      ],
    });
    await tester.tap(find.byKey(const ValueKey('ai-open-chats')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-chat-search')), 'ไตรมาส');
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester, 4);
    expect(a.calls.lastWhere((c) => c.path == '/api/ai/conversations').queryParameters['q'], 'ไตรมาส');
    expect(find.byKey(const ValueKey('ai-snippet-7')), findsOneWidget);
  });

  testWidgets('leaving mid-answer: Isaac finishes, saves, and notifies "ไอแซคตอบแล้ว" that opens the chat', (tester) async {
    final shown = <(String, String, String?)>[];
    debugShowLocal = (t, b, p) async => shown.add((t, b, p));
    addTearDown(() => debugShowLocal = null);
    final a = await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '[QA] ถามยาว');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox())); // user leaves
    await _settle(tester, 20);
    expect(a.calls.where((c) => c.path == '/api/ai/conversations/c1/messages').length, 2, reason: 'question and answer saved');
    expect(shown.single.$1, 'ไอแซคตอบแล้ว');
    expect(shown.single.$2, contains('ตอบแล้วนะ'));
    expect(shown.single.$3, AppRoutes.aiOpenChat('c1'));
  });

  testWidgets('deep links: chat opens that conversation; cmd waits in the composer', (tester) async {
    await _pump(tester, screen: const AiAssistantScreen(initialChatId: '7'));
    await _settle(tester, 6);
    expect(find.text('**ยอดขาย** เดือนนี้ 10 รายการ'), findsNothing);
    expect(find.textContaining('เดือนนี้ 10 รายการ'), findsOneWidget);
    await _pump(tester, screen: const AiAssistantScreen(initialCommand: 'lead', key: ValueKey('cmd')));
    await _settle(tester, 6);
    expect(find.byKey(const ValueKey('ai-create-chip')), findsOneWidget);
    expect(AppRoutes.aiCommand('lead'), '/ai?cmd=lead');
  });

  test('Home shortcuts: most used commands first, then lead / นัด / สรุป', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await aiTopCommands(), ['lead', 'นัด', 'สรุป']);
    await aiCountCommandUse('excel');
    await aiCountCommandUse('excel');
    await aiCountCommandUse('case');
    expect(await aiTopCommands(), ['excel', 'case', 'lead']);
  });
}
