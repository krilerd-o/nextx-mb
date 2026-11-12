// ISAAC AI การสื่อสาร (mobile) — parity with the web: summarise now, notification links, history filters,
// share (recipients / tape / CRM log / ZIP, DM to colleagues, CRM timeline), AI provider settings,
// transcript + live caption translation, insights, transcript edits, persisted follow-ups, Package off.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/menu_access.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calls/live_captions.dart';
import 'package:nextx_mobile/screens/comm_ai/call_summary_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/chat_summary_sheet.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_access.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_history_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_insights_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_settings_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_widgets.dart';
import 'package:nextx_mobile/screens/deep_link_loaders.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

const _admin = SessionState(accessToken: 't', userId: '1', businessId: '5', businessRole: 'admin', menusLoaded: true, menuKeys: ['chat', 'comm-ai-history', 'comm-ai-insights']);
const _member = SessionState(accessToken: 't', userId: '2', businessId: '5', menusLoaded: true, menuKeys: ['chat', 'comm-ai-history']);

const _settings = {
  'stt_enabled': true,
  'consent_mode': 'individual',
  'record_audio': true,
  'auto_summary': true,
  'language': 'th',
  'retention_days': 365,
  'share_email_enabled': true,
  'share_link_enabled': true,
  'share_link_max_days': 30,
  'admins_see_all': true,
  'stt_model': 'gpt-4o-transcribe',
  'summary_provider': '',
  'summary_model': '',
};

const _result = {
  'headline': 'ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด',
  'key_points': ['แอร์ชั้น 3 ยังมีน้ำหยด'],
  'discussion_points': <String>[],
  'action_items': [
    {'text': 'นัดช่างเข้าตรวจ', 'owner': 'สมชาย'},
    {'text': 'ส่งใบเสนอราคา'},
  ],
  'action_done': [0],
  'recommendations': <String>[],
  'sentiment': {'label': 'negative', 'reason': 'น้ำหยดซ้ำเป็นครั้งที่สอง'},
  'topics': ['แอร์', 'ซ่อมบำรุง'],
};

Map<String, Object?> _call({Object? summary, bool canEdit = true}) => {
      'call_id': 'c1',
      'media': 'audio',
      'started_at': '2026-11-11T03:00:00Z',
      'participants': [
        {'user_id': 1, 'name': 'สมชาย'},
        {'user_id': 2, 'name': 'วิภา'},
      ],
      'summary': summary,
      'transcript': [
        {'seq': 1, 'user_id': 1, 'name': 'สมชาย', 'start_ms': 0, 'end_ms': 2000, 'text': 'สวัสดีครับ', 'edited': false, 'can_edit': canEdit},
        {'seq': 2, 'user_id': 2, 'name': 'วิภา', 'start_ms': 3000, 'end_ms': 5000, 'text': 'แอร์ชั้นสามน้ำหยด', 'edited': false, 'can_edit': false},
      ],
      'recordings': [],
    };

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget screen, Map<String, Object?> replies, {SessionState session = _admin, Size size = const Size(420, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(session);
  final adapter = FakeNextxAdapter(replies);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: KeyedSubtree(key: UniqueKey(), child: screen)))));
  await _settle(tester);
  return adapter;
}

Future<void> _settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls [f] into the middle of the nearest list (lazily built items included).
Future<void> _show(WidgetTester tester, Finder f, {Finder? list}) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 250, scrollable: find.descendant(of: list ?? find.byType(ListView).first, matching: find.byType(Scrollable)).first);
  }
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pump();
}

Map<String, dynamic> _body(FakeNextxAdapter api, String key) {
  final c = api.calls.lastWhere((c) => '${c.method} ${c.path}' == key);
  return Map<String, dynamic>.from(c.data as Map);
}

class _Stt implements SttTransport {
  @override
  final Stream<RealtimeEvent> events = const Stream.empty();
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async => {'ok': true};
  @override
  void emit(String event, Map<String, dynamic> data) {}
  @override
  void emitAudio(String callId, Uint8List pcm) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#3 summarise now', () {
    testWidgets('no summary → "ให้ ISAAC สรุปตอนนี้" posts, then follows the new summary until done', (tester) async {
      final replies = <String, Object?>{
        'GET /api/comm-ai/calls/c1': _call(),
        'POST /api/comm-ai/calls/c1/summarize': {'summary_id': 41, 'status': 'pending'},
      };
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), replies);
      expect(find.text('ยังไม่มีสรุปของสายนี้'), findsOneWidget);
      expect(find.byTooltip('แชร์'), findsOneWidget);
      replies['GET /api/comm-ai/calls/c1'] = _call(summary: {'id': 41, 'status': 'running'});
      await tester.tap(find.byKey(const ValueKey('call-summary-summarize')));
      await _settle(tester);
      expect(api.callKeys, contains('POST /api/comm-ai/calls/c1/summarize'));
      expect(find.byKey(const ValueKey('call-summary-busy')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3)); // poll: still running
      await _settle(tester);
      expect(find.byKey(const ValueKey('call-summary-busy')), findsOneWidget);
      replies['GET /api/comm-ai/calls/c1'] = _call(summary: {'id': 41, 'status': 'done', 'result': _result});
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(find.byKey(const ValueKey('call-summary-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('call-summary-resummarize')), findsOneWidget);
    });

    testWidgets('failed → "ลองสรุปอีกครั้ง"; done → "ให้ ISAAC สรุปใหม่" posts again', (tester) async {
      final replies = <String, Object?>{
        'GET /api/comm-ai/calls/c1': _call(summary: {'id': 40, 'status': 'failed'}),
        'POST /api/comm-ai/calls/c1/summarize': {'summary_id': 41, 'status': 'pending'},
      };
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), replies);
      expect(find.text('ลองสรุปอีกครั้ง'), findsOneWidget);
      replies['GET /api/comm-ai/calls/c1'] = _call(summary: {'id': 41, 'status': 'done', 'result': _result});
      await tester.tap(find.byKey(const ValueKey('call-summary-summarize')));
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(find.byKey(const ValueKey('call-summary-view')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-summary-resummarize')));
      await _settle(tester);
      expect(api.callKeys.where((k) => k == 'POST /api/comm-ai/calls/c1/summarize'), hasLength(2));
    });
  });

  group('#6 notification → call summary', () {
    test('link_path /comm-ai/history?call= and ?summary= open the right screen', () {
      expect(notificationDeepLink('/comm-ai/history?call=abc-1', linkId: 'abc-1', extra: 'comm_ai_call'), '/comm-ai/calls/abc-1');
      expect(notificationDeepLink('/comm-ai/history?summary=12'), '/comm-ai/summaries/12');
      expect(notificationDeepLink('/comm-ai/history'), AppRoutes.commAi);
      expect(notificationDeepLink('', linkId: 'abc-2', extra: 'comm_ai_call'), '/comm-ai/calls/abc-2');
      expect(notificationDeepLinkFromData({'url': '/comm-ai/history?call=abc-3', 'id': 'abc-3', 'extra': 'comm_ai_call'}), '/comm-ai/calls/abc-3');
      expect(commAiHistoryRedirect(Uri.parse('/comm-ai/history?call=x%20y')), '/comm-ai/calls/x%20y');
      expect(commAiHistoryRedirect(Uri.parse('/comm-ai?user=3')), isNull);
    });

    test('routes: menu gates and tablet panes', () {
      expect(requiredMenusFor(AppRoutes.commAiInsights), [MenuAccess.commAiInsights]);
      expect(requiredMenusFor(AppRoutes.commAiCall('c1')), [MenuAccess.commAi]);
      expect(nxPaneForRoute('/comm-ai/calls/c1'), isA<CallSummaryScreen>());
      expect((nxPaneForRoute('/comm-ai/calls/c1')! as CallSummaryScreen).callId, 'c1');
      expect(nxPaneForRoute('/comm-ai/summaries/7'), isA<ChatSummaryDetailScreen>());
    });
  });

  group('#8 history filters', () {
    final replies = <String, Object?>{
      'GET /api/comm-ai/history': {'list': [], 'next_before': null},
      'GET /api/comm-ai/history/filters': {
        'people': [
          {'user_id': 3, 'name': 'นที'},
          {'user_id': 4, 'name': 'วิภา'},
        ],
        'rooms': [
          {'id': 9, 'name': 'ทีมบริการ'},
        ],
      },
    };

    testWidgets('scope, person, room and has-audio go to GET /history', (tester) async {
      final api = await _pump(tester, const CommAiHistoryScreen(), replies);
      final filters = find.byTooltip('ตัวกรอง').evaluate().isNotEmpty ? find.byTooltip('ตัวกรอง') : find.text('ตัวกรอง');
      await tester.tap(filters.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('filter-group-person')), findsOneWidget);
      final sheet = find.byType(ListView).last;
      for (final label in ['กลุ่ม', 'นที', 'ทีมบริการ', 'มีเสียง']) {
        await tester.dragUntilVisible(find.text(label), sheet, const Offset(0, -120));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.textContaining('ใช้ตัวกรอง'));
      await tester.pumpAndSettle();
      final q = api.calls.lastWhere((c) => c.path == '/api/comm-ai/history').queryParameters;
      expect(q['scope'], 'group');
      expect(q['user_id'], '3');
      expect(q['room_id'], '9');
      expect(q['has_audio'], 1);
    });

    testWidgets('?user= from insights preselects the person', (tester) async {
      final api = await _pump(tester, const CommAiHistoryScreen(initialUserId: '4'), replies);
      expect(api.calls.firstWhere((c) => c.path == '/api/comm-ai/history').queryParameters['user_id'], '4');
    });
  });

  group('#9 / #10 / #12 share', () {
    final base = <String, Object?>{
      'GET /api/comm-ai/settings': {'settings': _settings, 'available': true},
      'GET /api/comm-ai/share/call/c1/links': {'list': []},
      'GET /api/comm-ai/share/call/c1/recipients': {
        'list': [
          {'user_id': 2, 'name': 'วิภา', 'email': 'wipa@x.co'},
          {'user_id': 3, 'name': 'นที', 'email': null},
        ],
      },
      'GET /api/entity/account': {
        'list': [
          {'id': 7, 'name': 'บริษัท เอ'},
        ],
      },
      'POST /api/comm-ai/share/call/c1/email': {'sent': true, 'audio': 'attached', 'activity': {'activity_id': 55}},
      'POST /api/comm-ai/export-jobs': {'job_id': 9, 'type': 'email', 'status': 'pending', 'progress': 0},
      'GET /api/comm-ai/export-jobs/9': {
        'job_id': 9,
        'type': 'email',
        'status': 'done',
        'progress': 100,
        'result': {'sent': true, 'audio': 'attached', 'activity': {'activity_id': 55}},
      },
      'GET /api/users': {
        'list': [
          {'id': 1, 'first_name': 'ฉัน'},
          {'id': 3, 'first_name': 'นที', 'last_name': 'ทอง'},
        ],
      },
      'POST /api/comm-ai/share/call/c1/chat': {
        'sent': [
          {'user_id': 3, 'room_id': 90},
        ],
      },
      'POST /api/comm-ai/share/call/c1/crm': {'activity_id': 66, 'link': '/calendar/66'},
    };
    const sheet = SingleChildScrollView(child: CommAiShareSheet(kind: 'call', id: 'c1', title: 'สรุป', hasAudio: true));

    testWidgets('#9 e-mail: recipient chip, attach tape, ZIP option, log as CRM Activity', (tester) async {
      final api = await _pump(tester, sheet, base, size: const Size(420, 1400));
      await tester.tap(find.text('อีเมล'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('comm-ai-share-recipient-3')), findsNothing, reason: 'no e-mail, no chip');
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-recipient-2')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('comm-ai-share-to'))).controller!.text, 'wipa@x.co');

      await tester.tap(find.byKey(const ValueKey('comm-ai-share-format')));
      await _settle(tester);
      expect(find.text('ZIP (PDF + Word + ข้อความ + เสียง)'), findsWidgets);
      await tester.tap(find.text('PDF').last);
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('comm-ai-share-attach-audio')));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-log-crm')));
      await _settle(tester);
      final send = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('comm-ai-share-email')));
      expect(send.onPressed, isNull, reason: 'pick the record first');
      await tester.tap(find.byKey(const ValueKey('comm-ai-email-crm-record')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('บริษัท เอ'));
      await tester.pumpAndSettle();
      CommAiShareSheet.jobPollInterval = const Duration(milliseconds: 50);
      addTearDown(() => CommAiShareSheet.jobPollInterval = const Duration(milliseconds: 1500));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-email')));
      await _settle(tester);
      // With the tape attached the e-mail goes out as a background job (the server prepares the audio first).
      expect(api.callKeys, isNot(contains('POST /api/comm-ai/share/call/c1/email')));
      final body = _body(api, 'POST /api/comm-ai/export-jobs');
      expect(body['type'], 'email');
      expect(body['kind'], 'call');
      expect(body['id'], 'c1');
      expect(body['to'], ['wipa@x.co']);
      expect(body['attach_audio'], true);
      expect(body['log_to'], {'module': 'account', 'record_id': 7});
      expect(find.textContaining('แนบไฟล์เสียงแล้ว'), findsOneWidget);
    });

    testWidgets('#10 to colleagues: pick people, message, direct message', (tester) async {
      final api = await _pump(tester, sheet, base, size: const Size(420, 1400));
      await tester.tap(find.text('ทีม'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-pick-mates')));
      await tester.pumpAndSettle();
      expect(find.text('ฉัน'), findsNothing, reason: 'not myself');
      await tester.tap(find.text('นที ทอง'));
      await tester.pump();
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comm-ai-share-mate-3')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('comm-ai-share-chat-note')), 'ฝากดูครับ');
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-chat')));
      await _settle(tester);
      final body = _body(api, 'POST /api/comm-ai/share/call/c1/chat');
      expect(body['user_ids'], [3]);
      expect(body['message'], 'ฝากดูครับ');
      expect(find.text('ส่งให้ 1 คนในแชทแล้ว'), findsOneWidget);
    });

    testWidgets('#12 save to the CRM timeline: module + record, type, note', (tester) async {
      final api = await _pump(tester, sheet, base, size: const Size(420, 1400));
      await tester.tap(find.text('CRM'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('comm-ai-crm-record')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('บริษัท เอ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comm-ai-crm-type')));
      await _settle(tester);
      await tester.tap(find.text('ประชุม').last);
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('comm-ai-crm-note')), 'ลูกค้าโทรแจ้ง');
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-crm')));
      await _settle(tester);
      final body = _body(api, 'POST /api/comm-ai/share/call/c1/crm');
      expect(body, {'module': 'account', 'record_id': 7, 'activitytype': 'Meeting', 'note': 'ลูกค้าโทรแจ้ง'});
      expect(find.text('บันทึกลงไทม์ไลน์ลูกค้าแล้ว'), findsOneWidget);
      expect(find.byKey(const ValueKey('comm-ai-crm-open-activity')), findsOneWidget);
    });
  });

  group('#11 AI provider settings', () {
    final replies = <String, Object?>{
      'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': true, 'available': true},
      'PUT /api/comm-ai/settings': {'settings': {..._settings, 'summary_provider': 'openai', 'summary_model': 'gpt-4.1-mini'}},
      'GET /api/comm-ai/prompts': {'prompts': {}, 'max_chars': 8000},
      'GET /api/comm-ai/providers': {
        'providers': [
          {'id': 'claude', 'label': 'Claude (Anthropic)', 'models': ['claude-sonnet-5-5'], 'configured': true},
          {'id': 'openai', 'label': 'OpenAI', 'models': ['gpt-4.1-mini', 'gpt-4.1'], 'configured': false},
        ],
        'default_provider': 'claude',
        'stt_models': ['gpt-4o-transcribe', 'gpt-4o-mini-transcribe', 'whisper-1'],
        'stt_ready': true,
      },
    };

    testWidgets('admin picks provider + suggested model and saves', (tester) async {
      final api = await _pump(tester, const CommAiSettingsScreen(), replies);
      await _show(tester, find.byKey(const ValueKey('comm-ai-summary-provider')));
      await tester.tap(find.byKey(const ValueKey('comm-ai-summary-provider')));
      await _settle(tester);
      await tester.tap(find.text('OpenAI — ยังไม่ได้ตั้งค่า key').last);
      await _settle(tester);
      await _show(tester, find.byKey(const ValueKey('comm-ai-summary-model-pick')));
      await tester.tap(find.byKey(const ValueKey('comm-ai-summary-model-pick')));
      await _settle(tester);
      await tester.tap(find.text('gpt-4.1-mini').last);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('comm-ai-settings-save')));
      await _settle(tester);
      final put = _body(api, 'PUT /api/comm-ai/settings');
      expect(put['summary_provider'], 'openai');
      expect(put['summary_model'], 'gpt-4.1-mini');
      expect(put['stt_model'], 'gpt-4o-transcribe');
    });

    testWidgets('members do not see the AI panel', (tester) async {
      final api = await _pump(tester, const CommAiSettingsScreen(), {...replies, 'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': false}}, session: _member);
      expect(find.byKey(const ValueKey('comm-ai-summary-provider')), findsNothing);
      expect(api.callKeys, isNot(contains('GET /api/comm-ai/providers')));
    });
  });

  group('#13 translation', () {
    testWidgets('transcript: pick English → translated lines under the originals', (tester) async {
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), {
        'GET /api/comm-ai/calls/c1': _call(summary: {'id': 41, 'status': 'done', 'result': _result}),
        'POST /api/comm-ai/translate': {'list': ['Hello', 'The 3rd-floor AC is dripping'], 'to': 'en'},
      });
      await tester.tap(find.textContaining('บทสนทนา (2)'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('comm-ai-transcript-lang')));
      await _settle(tester);
      expect(find.text('Tiếng Việt'), findsOneWidget);
      await tester.tap(find.text('English'));
      await _settle(tester);
      expect(_body(api, 'POST /api/comm-ai/translate'), {'texts': ['สวัสดีครับ', 'แอร์ชั้นสามน้ำหยด'], 'to': 'en'});
      expect(find.byKey(const ValueKey('call-transcript-tr-2')), findsOneWidget);
      expect(find.text('The 3rd-floor AC is dripping'), findsOneWidget);
      expect(find.text('แอร์ชั้นสามน้ำหยด', findRichText: true), findsNothing, reason: 'original is a rich text span');
    });

    testWidgets('live captions: off → EN → TH; only final lines are translated', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig()..debugOverrideSession(_admin);
      final adapter = FakeNextxAdapter({'POST /api/comm-ai/translate': {'list': ['The AC is dripping'], 'to': 'en'}});
      config.apiClient.debugSetHttpAdapter(adapter);
      final lt = LiveTranscription(transport: _Stt())
        ..api = config.apiClient
        ..myUserId = '1'
        ..running = true;
      addTearDown(lt.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: LiveCaptionsPanel(lt: lt)))));
      await tester.tap(find.byKey(const ValueKey('call-captions-translate')));
      await tester.pump();
      expect(find.text('EN'), findsOneWidget);
      lt.captions.value = const [
        LiveCaption(key: '2:a', userId: '2', name: 'วิภา', text: 'แอร์น้ำหยด', isFinal: true),
        LiveCaption(key: '2:b', userId: '2', name: 'วิภา', text: 'แล้วก็', isFinal: false),
      ];
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(_body(adapter, 'POST /api/comm-ai/translate'), {'texts': ['แอร์น้ำหยด'], 'to': 'en'});
      expect(find.text('The AC is dripping'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-captions-translate')));
      await tester.pump();
      expect(find.text('TH'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-captions-translate')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('The AC is dripping'), findsNothing, reason: 'off again');
      expect(kCaptionLangCycle, ['', 'en', 'th']);
    });
  });

  group('#14 insights', () {
    final insights = <String, Object?>{
      'GET /api/comm-ai/insights': {
        'from': '2026-10-13',
        'to': '2026-11-12',
        'scope': 'business',
        'totals': {'calls': 12, 'video_calls': 3, 'chat_summaries': 4, 'summaries': 15, 'minutes_transcribed': 1250, 'with_audio': 6, 'open_actions': 2},
        'sentiment': {'positive': 6, 'neutral': 3, 'negative': 1},
        'negative_examples': [
          {'kind': 'call', 'ref': 'c1', 'headline': 'ลูกค้าไม่พอใจงานซ่อม', 'reason': 'ซ่อมซ้ำ'},
        ],
        'topics': [
          {'topic': 'แอร์', 'count': 5},
          {'topic': 'ราคา', 'count': 2},
        ],
        'open_actions': [
          {'summary_id': 41, 'index': 1, 'kind': 'call', 'ref': 'c1', 'text': 'ส่งใบเสนอราคา', 'owner': 'สมชาย', 'due': '2026-11-14', 'headline': 'แอร์น้ำหยด'},
          {'summary_id': 42, 'index': 0, 'kind': 'chat', 'ref': '42', 'text': 'โทรกลับลูกค้า', 'headline': 'สรุปแชททีม'},
        ],
        'people': [
          {'user_id': 3, 'name': 'นที', 'count': 7},
        ],
        'daily': [
          {'date': '2026-11-10', 'count': 2},
          {'date': '2026-11-11', 'count': 5},
        ],
      },
      'PATCH /api/comm-ai/summaries/41/actions/1': {'action_done': [1]},
    };

    testWidgets('tiles, labelled sentiment, topics, tick a follow-up, values on tap', (tester) async {
      final api = await _pump(tester, const CommAiInsightsScreen(), insights);
      expect(find.text('1,250'), findsOneWidget);
      expect(find.byKey(const ValueKey('comm-ai-insights-tile-open_actions')), findsOneWidget);
      await _show(tester, find.byKey(const ValueKey('comm-ai-insights-tick-41-1')));
      expect(find.textContaining('ส่งใบเสนอราคา', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('comm-ai-insights-tick-41-1')));
      await _settle(tester);
      expect(_body(api, 'PATCH /api/comm-ai/summaries/41/actions/1'), {'done': true});
      expect(find.textContaining('ส่งใบเสนอราคา', findRichText: true), findsNothing);

      final day = find.byKey(const ValueKey('comm-ai-insights-day-2026-11-11'));
      await _show(tester, day);
      await tester.tap(day);
      await tester.pump();
      expect(find.text('11/11/2569 · 5 รายการ'), findsOneWidget);

      final neg = find.byKey(const ValueKey('comm-ai-insights-sentiment-negative'));
      await _show(tester, neg);
      expect(find.text('6 · 60%'), findsOneWidget, reason: 'every segment labelled with count and share');
      await tester.tap(neg);
      await tester.pump();
      expect(find.text('ไม่พอใจ: 1 (10%)'), findsOneWidget);

      await _show(tester, find.byKey(const ValueKey('comm-ai-insights-topic-แอร์')));
      expect(find.byKey(const ValueKey('comm-ai-insights-person-3')), findsOneWidget);
    });

    testWidgets('history header opens insights only with the menu and the package', (tester) async {
      final history = {'GET /api/comm-ai/history': {'list': [], 'next_before': null}};
      await _pump(tester, const CommAiHistoryScreen(), {...history, 'GET /api/comm-ai/settings': {'settings': _settings, 'available': true, 'insights_available': true}});
      expect(find.byTooltip('แดชบอร์ด ISAAC'), findsOneWidget);
      await _pump(tester, const CommAiHistoryScreen(), {...history, 'GET /api/comm-ai/settings': {'settings': _settings, 'available': true, 'insights_available': false}});
      expect(find.byTooltip('แดชบอร์ด ISAAC'), findsNothing);
      await _pump(tester, const CommAiHistoryScreen(), {...history, 'GET /api/comm-ai/settings': {'settings': _settings, 'available': true, 'insights_available': true}}, session: _member);
      expect(find.byTooltip('แดชบอร์ด ISAAC'), findsNothing);
    });
  });

  group('#15 transcript edits, follow-ups, sentiment', () {
    testWidgets('edit my misheard line → PATCH, "(แก้ไขแล้ว)", banner "สรุปใหม่"', (tester) async {
      final replies = <String, Object?>{
        'GET /api/comm-ai/calls/c1': _call(summary: {'id': 41, 'status': 'done', 'result': _result}),
        'PATCH /api/comm-ai/calls/c1/segments/1': {'seq': 1, 'text': 'สวัสดีค่ะ', 'edited': true},
        'POST /api/comm-ai/calls/c1/summarize': {'summary_id': 42, 'status': 'pending'},
      };
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), replies);
      await tester.tap(find.textContaining('บทสนทนา (2)'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('call-transcript-edit-btn-2')), findsNothing, reason: 'not my line');
      await tester.tap(find.byKey(const ValueKey('call-transcript-edit-btn-1')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('call-transcript-edit')), 'สวัสดีค่ะ');
      await tester.tap(find.byKey(const ValueKey('call-transcript-save')));
      await _settle(tester);
      expect(_body(api, 'PATCH /api/comm-ai/calls/c1/segments/1'), {'text': 'สวัสดีค่ะ'});
      expect(find.textContaining('(แก้ไขแล้ว)', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('call-transcript-edited-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-transcript-resummarize')));
      await _settle(tester);
      expect(api.callKeys, contains('POST /api/comm-ai/calls/c1/summarize'));
      expect(find.byKey(const ValueKey('call-summary-busy')), findsOneWidget, reason: 'back on the summary tab');
    });

    testWidgets('follow-up ticks start from action_done and are saved; sentiment + topic chips', (tester) async {
      final api = await _pump(tester, const SingleChildScrollView(child: CommAiSummaryView(result: _result, summaryId: '41')), {
        'PATCH /api/comm-ai/summaries/41/actions/0': {'action_done': []},
        'PATCH /api/comm-ai/summaries/41/actions/1': {'action_done': [0, 1]},
      });
      expect(find.byKey(const ValueKey('comm-ai-sentiment-negative')), findsOneWidget);
      expect(find.text('😟 ลูกค้าไม่พอใจ'), findsOneWidget);
      expect(find.text('#แอร์'), findsOneWidget);
      expect(find.text('น้ำหยดซ้ำเป็นครั้งที่สอง'), findsOneWidget);
      Icon icon(int i) => tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey('comm-ai-action-$i')), matching: find.byType(Icon)).first);
      expect(icon(0).icon, isNot(Icons.check_box_outline_blank_rounded), reason: 'ticked on the server');
      expect(icon(1).icon, Icons.check_box_outline_blank_rounded);
      await tester.tap(find.byKey(const ValueKey('comm-ai-action-1')));
      await _settle(tester);
      expect(_body(api, 'PATCH /api/comm-ai/summaries/41/actions/1'), {'done': true});
      expect(icon(1).icon, isNot(Icons.check_box_outline_blank_rounded));
      await tester.tap(find.byKey(const ValueKey('comm-ai-action-0')));
      await _settle(tester);
      expect(_body(api, 'PATCH /api/comm-ai/summaries/41/actions/0'), {'done': false});
    });

    testWidgets('a failed save puts the tick back', (tester) async {
      await _pump(tester, const SingleChildScrollView(child: CommAiSummaryView(result: _result, summaryId: '41')), {});
      await tester.tap(find.byKey(const ValueKey('comm-ai-action-1')));
      await _settle(tester);
      final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('comm-ai-action-1')), matching: find.byType(Icon)).first);
      expect(icon.icon, Icons.check_box_outline_blank_rounded);
    });
  });

  group('Package off (available == false)', () {
    const off = {'settings': _settings, 'available': false, 'insights_available': false};

    testWidgets('call summary hides summarise, edit and share', (tester) async {
      await _pump(tester, const CallSummaryScreen(callId: 'c1'), {'GET /api/comm-ai/settings': off, 'GET /api/comm-ai/calls/c1': _call()});
      expect(find.text('ยังไม่มีสรุปของสายนี้'), findsOneWidget);
      expect(find.byKey(const ValueKey('call-summary-summarize')), findsNothing);
      expect(find.byTooltip('แชร์'), findsNothing);
      await tester.tap(find.textContaining('บทสนทนา (2)'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('call-transcript-edit-btn-1')), findsNothing);
      expect(find.byKey(const ValueKey('comm-ai-transcript-lang')), findsNothing);
    });

    testWidgets('history explains; chat summary sheet has no run button', (tester) async {
      await _pump(tester, const CommAiHistoryScreen(), {'GET /api/comm-ai/settings': off, 'GET /api/comm-ai/history': {'list': [], 'next_before': null}});
      expect(find.byKey(const ValueKey('comm-ai-unavailable')), findsOneWidget);
      expect(find.byTooltip('แดชบอร์ด ISAAC'), findsNothing);
      await _pump(tester, const SingleChildScrollView(child: ChatSummaryPanel(roomId: '9', roomName: 'ทีม')), {'GET /api/comm-ai/settings': off, 'GET /api/comm-ai/chat/rooms/9/summaries': {'list': []}});
      expect(find.byKey(const ValueKey('chat-summary-run')), findsNothing);
      expect(find.byKey(const ValueKey('comm-ai-unavailable')), findsOneWidget);
    });
  });

  test('access flags: older servers read as on; no Package turns everything off', () {
    expect(CommAiAccess.fromSettings({}).available, isTrue);
    expect(CommAiAccess.fromSettings({}).insights, isTrue);
    expect(CommAiAccess.fromSettings({'available': false, 'insights_available': true}).insights, isFalse);
    expect(CommAiAccess.fromSettings({'available': true, 'insights_available': false, 'can_edit': true}).canEdit, isTrue);
  });
}
