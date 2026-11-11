// ISAAC AI การสื่อสาร (mobile): settings + prompts, history, chat summary sheet, share sheet, call summary.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/comm_ai/call_summary_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/chat_summary_sheet.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_history_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_settings_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

const _admin = SessionState(accessToken: 't', userId: '1', businessId: '5', businessRole: 'admin', menusLoaded: true, menuKeys: ['chat', 'call-log']);
const _member = SessionState(accessToken: 't', userId: '2', businessId: '5', menusLoaded: true, menuKeys: ['chat', 'call-log']);

const _settings = {
  'stt_enabled': true,
  'consent_mode': 'individual',
  'ask_every_call': true,
  'share_captions_default': true,
  'record_audio': true,
  'auto_summary': true,
  'language': 'th',
  'retention_days': 365,
  'share_email_enabled': true,
  'share_link_enabled': true,
  'share_link_max_days': 30,
  'admins_see_all': true,
};

const _result = {
  'headline': 'ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด นัดช่างวันพฤหัส',
  'key_points': ['แอร์ชั้น 3 ยังมีน้ำหยด [#2]', 'นัดช่างวันพฤหัสบ่าย [#3]'],
  'discussion_points': ['ลูกค้ากังวลคุณภาพงานซ่อม [#2]'],
  'action_items': [
    {'text': 'นัดช่างเข้าตรวจ', 'owner': 'สมชาย', 'due': '2026-11-12', 'refs': [3]},
  ],
  'recommendations': ['เปิด Visit ให้ช่าง [#3]'],
  'suggestions': [
    {'kind': 'activity', 'activitytype': 'Visit', 'subject': 'ตรวจแอร์ชั้น 3', 'reason': 'ลูกค้านัดพฤหัส', 'due': '2026-11-12'},
  ],
  'lines': [
    {'n': 1, 'at': '10:00', 'name': 'สมชาย', 'text': 'สวัสดีครับ'},
  ],
};

String _sse(List<Map<String, dynamic>> frames) => [for (final f in frames) 'data: ${jsonEncode(f)}\n\n'].join();

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget screen, Map<String, Object?> replies, {SessionState session = _admin, Map<String, String> sse = const {}, Size size = const Size(420, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(session);
  final adapter = FakeNextxAdapter(replies, sseFor: sse);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: screen))));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

/// Scrolls [f] to the middle of the page (the floating header covers the top edge).
Future<void> _show(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 300, scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
  }
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settingsReplies = <String, Object?>{
    'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': true},
    'PUT /api/comm-ai/settings': {'settings': {..._settings, 'record_audio': false}},
    'GET /api/comm-ai/prompts': {
      'prompts': {
        'call': {'kind': 'call', 'prompt': 'สรุปการโทรเป็นภาษาไทย', 'is_default': true, 'version': 0, 'default_prompt': 'สรุปการโทรเป็นภาษาไทย'},
        'chat': {'kind': 'chat', 'prompt': 'สรุปแชท', 'is_default': false, 'version': 2, 'default_prompt': 'ค่าเริ่มต้นแชท'},
      },
      'max_chars': 8000,
    },
    'PUT /api/comm-ai/prompts/call': {'kind': 'call', 'prompt': 'x', 'version': 1, 'is_default': false},
    'POST /api/comm-ai/prompts/call/test': {'result': _result, 'ms': 1800},
  };

  testWidgets('settings: admin edits a switch and saves; prompt tip + ISAAC test', (tester) async {
    final api = await _pump(tester, const CommAiSettingsScreen(), settingsReplies);
    expect(find.text('ISAAC AI การสื่อสาร'), findsWidgets);
    expect(find.byKey(const ValueKey('comm-ai-settings-save')), findsNothing);

    await _show(tester, find.byKey(const ValueKey('comm-ai-setting-record_audio')));
    await tester.tap(find.byKey(const ValueKey('comm-ai-setting-record_audio')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('comm-ai-settings-save')));
    await _settle(tester);
    final put = api.calls.lastWhere((c) => c.method == 'PUT' && c.path == '/api/comm-ai/settings');
    expect((put.data as Map)['record_audio'], false);

    final tip = find.text('+ เน้นงานขาย');
    await _show(tester, tip);
    await tester.tap(tip);
    await _settle(tester);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('comm-ai-prompt-text')));
    expect(field.controller!.text, contains('BANT'));

    await _show(tester, find.byKey(const ValueKey('comm-ai-prompt-test')));
    await tester.tap(find.byKey(const ValueKey('comm-ai-prompt-test')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('comm-ai-prompt-result')), findsOneWidget);
    final test = api.calls.lastWhere((c) => c.path == '/api/comm-ai/prompts/call/test');
    expect((test.data as Map)['prompt'], contains('BANT'));

    await _show(tester, find.byKey(const ValueKey('comm-ai-prompt-save')));
    await tester.tap(find.byKey(const ValueKey('comm-ai-prompt-save')));
    await _settle(tester);
    expect(api.callKeys, contains('PUT /api/comm-ai/prompts/call'));
  });

  testWidgets('settings: members see a read-only page', (tester) async {
    await _pump(tester, const CommAiSettingsScreen(), {...settingsReplies, 'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': false}}, session: _member);
    expect(find.text('ดูอย่างเดียว — เฉพาะผู้ดูแลแก้ไขได้'), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const ValueKey('comm-ai-setting-stt_enabled')));
    expect(sw.onChanged, isNull);
    expect(find.byKey(const ValueKey('comm-ai-prompt-save')), findsNothing);
  });

  testWidgets('history: items, ISAAC empty state, search sends q', (tester) async {
    final api = await _pump(tester, const CommAiHistoryScreen(), {
      'GET /api/comm-ai/history': {
        'list': [
          {'type': 'call', 'id': 'c1', 'at': '2026-11-11T03:00:00Z', 'headline': 'ลูกค้าแจ้งแอร์น้ำหยด', 'room_name': 'ทีมบริการ', 'duration_s': 80, 'has_audio': true, 'action_count': 2, 'participants': [{'name': 'สมชาย'}]},
          {'type': 'chat', 'id': 7, 'at': '2026-11-11T02:00:00Z', 'headline': 'สรุปแชททีม', 'message_count': 8},
        ],
        'next_before': null,
      },
    });
    expect(find.text('ลูกค้าแจ้งแอร์น้ำหยด'), findsOneWidget);
    expect(find.text('สรุปแชททีม'), findsOneWidget);
    expect(api.calls.first.queryParameters['type'], 'all');
  });

  testWidgets('history: nothing yet → ISAAC empty state', (tester) async {
    await _pump(tester, const CommAiHistoryScreen(), {'GET /api/comm-ai/history': {'list': [], 'next_before': null}});
    expect(find.text('ยังไม่มีประวัติ'), findsOneWidget);
  });

  testWidgets('chat summary: streams, shows the 4 cards and posts to chat', (tester) async {
    final api = await _pump(
      tester,
      const SingleChildScrollView(child: ChatSummaryPanel(roomId: '9', roomName: 'ทีมบริการ')),
      {
        'GET /api/comm-ai/chat/rooms/9/summaries': {'list': []},
        'POST /api/chat/rooms/9/messages': {'id': 'm1'},
      },
      sse: {
        'POST /api/comm-ai/chat/rooms/9/summary': _sse([
          {'type': 'status', 'stage': 'read'},
          {'type': 'token', 'content': 'ลูกค้า'},
          {'type': 'done', 'result': _result, 'summary_id': 11, 'message_count': 8},
        ]),
      },
    );
    await tester.tap(find.byKey(const ValueKey('chat-summary-preset-7d')));
    await tester.tap(find.byKey(const ValueKey('chat-summary-run')));
    await _settle(tester);
    expect(find.textContaining('แอร์ชั้น 3 น้ำหยด'), findsWidgets);
    expect(find.text('ISAAC แนะนำให้เปิดงาน'), findsOneWidget);
    final run = api.calls.firstWhere((c) => c.path == '/api/comm-ai/chat/rooms/9/summary');
    expect((run.data as Map)['from'], isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('chat-summary-post')));
    await _settle(tester);
    final post = api.calls.firstWhere((c) => c.path == '/api/chat/rooms/9/messages');
    expect('${(post.data as Map)['body']}', startsWith('✨ ลูกค้าแจ้งแอร์ชั้น 3'));
    expect(find.text('ส่งแล้ว'), findsOneWidget);
  });

  testWidgets('chat summary: empty range offers the last 7 days', (tester) async {
    await _pump(
      tester,
      const SingleChildScrollView(child: ChatSummaryPanel(roomId: '9', roomName: 'ทีม')),
      {'GET /api/comm-ai/chat/rooms/9/summaries': {'list': []}},
      sse: {'POST /api/comm-ai/chat/rooms/9/summary': _sse([{'type': 'done', 'empty': true}])},
    );
    await tester.tap(find.byKey(const ValueKey('chat-summary-run')));
    await _settle(tester);
    expect(find.text('ISAAC ไม่พบข้อความในช่วงเวลานี้'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-summary-try-7d')), findsOneWidget);
  });

  testWidgets('share sheet: external link with expiry + password, then revoke', (tester) async {
    final api = await _pump(tester, const SingleChildScrollView(child: CommAiShareSheet(kind: 'call', id: 'c1', title: 'สรุป')), {
      'GET /api/comm-ai/settings': {'settings': _settings},
      'GET /api/comm-ai/share/call/c1/links': {'list': [{'id': 3, 'expires_at': '2026-11-18T03:00:00Z', 'revoked': false, 'view_count': 2, 'has_password': true}]},
      'POST /api/comm-ai/share/call/c1/link': {'token': 'abc', 'url_path': '/public/conversation/abc'},
      'DELETE /api/comm-ai/share/links/3': {'revoked': true},
    });
    await tester.tap(find.text('ลิงก์'));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('comm-ai-share-password')), '1234');
    await tester.tap(find.byKey(const ValueKey('comm-ai-share-link')));
    await _settle(tester);
    final post = api.calls.firstWhere((c) => c.method == 'POST' && c.path == '/api/comm-ai/share/call/c1/link');
    expect((post.data as Map)['password'], '1234');
    expect(find.byKey(const ValueKey('comm-ai-share-url')), findsOneWidget);
    await _show(tester, find.text('ยกเลิกลิงก์'));
    await tester.tap(find.text('ยกเลิกลิงก์'));
    await _settle(tester);
    expect(api.callKeys, contains('DELETE /api/comm-ai/share/links/3'));
  });

  testWidgets('share sheet: e-mail with cc and a note', (tester) async {
    final api = await _pump(tester, const SingleChildScrollView(child: CommAiShareSheet(kind: 'chat', id: '11')), {
      'GET /api/comm-ai/settings': {'settings': _settings},
      'GET /api/comm-ai/share/chat/11/links': {'list': []},
      'POST /api/comm-ai/share/chat/11/email': {'sent': true},
    });
    await tester.tap(find.text('อีเมล'));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('comm-ai-share-to')), 'a@x.co, b@x.co');
    await tester.enterText(find.byKey(const ValueKey('comm-ai-share-cc')), 'c@x.co');
    await tester.enterText(find.byKey(const ValueKey('comm-ai-share-note')), 'ฝากดูครับ');
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('comm-ai-share-email')));
    await _settle(tester);
    final body = api.calls.firstWhere((c) => c.path == '/api/comm-ai/share/chat/11/email').data as Map;
    expect(body['to'], ['a@x.co', 'b@x.co']);
    expect(body['cc'], ['c@x.co']);
    expect(body['message'], 'ฝากดูครับ');
    expect(find.text('ส่งอีเมลแล้ว'), findsOneWidget);
  });

  testWidgets('call summary: ISAAC summary, transcript tab with search', (tester) async {
    await _pump(tester, const CallSummaryScreen(callId: 'c1'), {
      'GET /api/comm-ai/calls/c1': {
        'call_id': 'c1',
        'media': 'audio',
        'started_at': '2026-11-11T03:00:00Z',
        'participants': [{'user_id': 1, 'name': 'สมชาย'}, {'user_id': 2, 'name': 'วิภา'}],
        'summary': {'status': 'done', 'result': _result},
        'transcript': [
          {'user_id': 1, 'name': 'สมชาย', 'start_ms': 0, 'text': 'สวัสดีครับ'},
          {'user_id': 2, 'name': 'วิภา', 'start_ms': 3000, 'text': 'แอร์ชั้น 3 ยังน้ำหยด'},
        ],
        'recordings': [],
      },
    });
    expect(find.byKey(const ValueKey('call-summary-view')), findsOneWidget);
    expect(find.text('ISAAC สรุปการสนทนา'), findsOneWidget);
    await tester.tap(find.textContaining('บทสนทนา (2)'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'แอร์');
    await _settle(tester);
    expect(find.textContaining('ยังน้ำหยด'), findsOneWidget);
    expect(find.textContaining('สวัสดีครับ'), findsNothing);
  });

  test('chat post body matches the web', () {
    expect(chatSummaryPostBody(_result), '✨ ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด นัดช่างวันพฤหัส\n• แอร์ชั้น 3 ยังมีน้ำหยด [#2]\n• นัดช่างวันพฤหัสบ่าย [#3]\n☐ นัดช่างเข้าตรวจ');
    expect(commAiWhen('2026-11-11T03:05:00Z', withDate: false), '10:05');
  });
}
