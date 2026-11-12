// ISAAC AI การสื่อสาร (mobile) — operations features of the backend: quotas (usage panel, notice, stt:start ack,
// 429 QUOTA_EXCEEDED), AI health (admins), personal digest prefs, CRM record suggestions, share history (admins),
// delete my data (PDPA) with realtime refresh / close, and background export jobs with progress.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calls/live_captions.dart';
import 'package:nextx_mobile/screens/comm_ai/call_summary_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/chat_summary_sheet.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_errors.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_history_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_settings_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_widgets.dart';
import 'package:nextx_mobile/services/api_exceptions.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart';
import 'package:nextx_mobile/services/comm_ai_export_jobs.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

const _admin = SessionState(accessToken: 't', userId: '1', businessId: '5', businessRole: 'admin', menusLoaded: true, menuKeys: ['chat', 'comm-ai-history']);

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
};

const _usage = {
  'month': '2026-11',
  'items': [
    {'kind': 'stt_minutes', 'used': 85.5, 'limit': 100, 'unlimited': false, 'percent': 86, 'exceeded': false, 'warn': true},
    {'kind': 'summaries', 'used': 12, 'limit': null, 'unlimited': true, 'percent': null, 'exceeded': false, 'warn': false},
    {'kind': 'translations', 'used': 5, 'limit': 200, 'unlimited': false, 'percent': 3, 'exceeded': false, 'warn': false},
  ],
};

const _result = {
  'headline': 'ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด',
  'key_points': ['แอร์ชั้น 3 ยังมีน้ำหยด'],
  'action_items': [
    {'text': 'นัดช่างเข้าตรวจ'},
  ],
};

Map<String, Object?> _call({Map<String, Object?>? viewer, Object? summary, List<Object?> recordings = const []}) => {
      'call_id': 'c1',
      'media': 'audio',
      'started_at': '2026-11-11T03:00:00Z',
      'participants': [
        {'user_id': 1, 'name': 'สมชาย'},
        {'user_id': 2, 'name': 'วิภา'},
      ],
      'summary': summary,
      'transcript': [
        {'seq': 1, 'user_id': 1, 'name': 'สมชาย', 'start_ms': 0, 'end_ms': 2000, 'text': 'สวัสดีครับ', 'can_edit': false},
        {'seq': 2, 'user_id': 2, 'name': 'วิภา', 'start_ms': 3000, 'end_ms': 5000, 'text': 'แอร์ชั้นสามน้ำหยด', 'can_edit': true},
      ],
      'recordings': recordings,
      'viewer': ?viewer,
    };

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget screen, Map<String, Object?> replies,
    {Size size = const Size(420, 1000), Map<String, int> statusFor = const {}, Map<String, Map<String, Object?>>? errorsFor}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_admin);
  final adapter = FakeNextxAdapter(replies, statusFor: statusFor, errorsFor: errorsFor);
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

Future<void> _show(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 250, scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
  }
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pump();
}

Map<String, dynamic> _body(FakeNextxAdapter api, String key) {
  final c = api.calls.lastWhere((c) => '${c.method} ${c.path}' == key);
  return Map<String, dynamic>.from(c.data as Map);
}

class _Stt implements SttTransport {
  _Stt([this.ack = const {'ok': true}]);
  final Map<String, dynamic> ack;
  @override
  final Stream<RealtimeEvent> events = const Stream.empty();
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async => ack;
  @override
  void emit(String event, Map<String, dynamic> data) {}
  @override
  void emitAudio(String callId, Uint8List pcm) {}
}

const _quota429 = {
  'error_code': 'QUOTA_EXCEEDED',
  'message': 'ใช้การสรุปครบโควตาของเดือนนี้แล้ว',
  'details': {'kind': 'summaries', 'used': 50, 'limit': 50},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => L10n.set('th'));

  group('1 quotas', () {
    testWidgets('settings: usage vs limit per kind and a compact notice at ≥ 80 %', (tester) async {
      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': false, 'available': true},
        'GET /api/comm-ai/ops/overview': {'usage': _usage, 'prefs': {'digest': true, 'digest_email': false}, 'is_admin': false, 'health': null},
      });
      expect(find.byKey(const ValueKey('comm-ai-quota-notice')), findsOneWidget);
      expect(find.textContaining('ใช้โควตา ISAAC ไปเกิน 80% แล้ว', findRichText: true), findsOneWidget);
      expect(find.textContaining('นาทีถอดเสียง 85.5/100 (86%)', findRichText: true), findsOneWidget);
      await _show(tester, find.byKey(const ValueKey('comm-ai-usage')));
      expect(find.text('85.5 / 100 นาที'), findsOneWidget);
      expect(find.text('12 · ไม่จำกัด'), findsOneWidget, reason: 'no limit set → unlimited, no bar');
      expect(find.text('5 / 200 ครั้ง'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('comm-ai-usage')), matching: find.byType(LinearProgressIndicator)), findsNWidgets(2));
    });

    testWidgets('settings: under 80 % → no notice; old server without /ops → page works as before', (tester) async {
      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': false, 'available': true},
        'GET /api/comm-ai/ops/overview': {
          'usage': {
            'month': '2026-11',
            'items': [
              {'kind': 'summaries', 'used': 1, 'limit': 50, 'percent': 2, 'warn': false, 'exceeded': false},
            ],
          },
          'prefs': {},
          'is_admin': false,
        },
      });
      expect(find.byKey(const ValueKey('comm-ai-quota-notice')), findsNothing);
      await _pump(tester, const CommAiSettingsScreen(), {'GET /api/comm-ai/settings': {'settings': _settings, 'available': true}});
      expect(find.byKey(const ValueKey('comm-ai-usage')), findsNothing);
      expect(find.text('ISAAC AI การสื่อสาร'), findsWidgets);
    });

    testWidgets('captions: stt:start quota_exceeded → minutes used up with the numbers (not a generic error)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final lt = LiveTranscription(
        transport: _Stt({
          'ok': false,
          'error': 'quota_exceeded',
          'quota': {'kind': 'stt_minutes', 'used': 600.4, 'limit': 600},
        }),
      )
        ..myUserId = '1'
        ..activeCallId = 'c1'
        ..decision = const SttDecision(callId: 'c1', enabled: true, share: true, record: false);
      addTearDown(lt.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: LiveCaptionsPanel(lt: lt)))));
      await tester.runAsync(() => lt.start());
      await tester.pump();
      expect(lt.error, 'quota_exceeded');
      expect(lt.quota, {'kind': 'stt_minutes', 'used': 600.4, 'limit': 600});
      expect(find.text('ใช้นาทีถอดเสียงของแพ็กเกจครบแล้วในเดือนนี้ (600/600 นาที) — สายยังคุยต่อได้ตามปกติ'), findsOneWidget);
      expect(find.textContaining('เริ่มถอดข้อความไม่สำเร็จ'), findsNothing);
    });

    testWidgets('captions: translation quota used up → message, translation turns off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig()..debugOverrideSession(_admin);
      final adapter = FakeNextxAdapter({}, statusFor: {'POST /api/comm-ai/translate': 429}, errorsFor: {
        'POST /api/comm-ai/translate': {
          'error_code': 'QUOTA_EXCEEDED',
          'message': 'x',
          'details': {'kind': 'translations', 'used': 200, 'limit': 200},
        },
      });
      config.apiClient.debugSetHttpAdapter(adapter);
      final lt = LiveTranscription(transport: _Stt())
        ..api = config.apiClient
        ..myUserId = '1'
        ..running = true;
      addTearDown(lt.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: LiveCaptionsPanel(lt: lt)))));
      await tester.tap(find.byKey(const ValueKey('call-captions-translate')));
      await tester.pump();
      lt.captions.value = const [LiveCaption(key: '2:a', userId: '2', name: 'วิภา', text: 'แอร์น้ำหยด', isFinal: true)];
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(find.text('ใช้การแปลคำบรรยายครบโควตาของเดือนนี้แล้ว (200/200 ครั้ง) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'), findsOneWidget);
      expect(find.text('EN'), findsNothing, reason: 'translation off again');
    });

    testWidgets('summarise a call → 429 QUOTA_EXCEEDED → friendly Thai text with the numbers', (tester) async {
      await _pump(
        tester,
        const CallSummaryScreen(callId: 'c1'),
        {'GET /api/comm-ai/calls/c1': _call(summary: {'id': 40, 'status': 'failed'})},
        statusFor: {'POST /api/comm-ai/calls/c1/summarize': 429},
        errorsFor: {'POST /api/comm-ai/calls/c1/summarize': _quota429},
      );
      await tester.tap(find.byKey(const ValueKey('call-summary-summarize')));
      await _settle(tester);
      expect(find.text('ใช้การสรุปของ ISAAC ครบโควตาของเดือนนี้แล้ว (50/50 ครั้ง) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'), findsOneWidget);
    });

    testWidgets('a summary that failed on the quota says so', (tester) async {
      await _pump(tester, const CallSummaryScreen(callId: 'c1'), {'GET /api/comm-ai/calls/c1': _call(summary: {'id': 40, 'status': 'failed', 'error': 'quota_exceeded'})});
      expect(find.text('ใช้โควตาการสรุปของแพ็กเกจครบแล้วในเดือนนี้ — ยังดูบทสนทนาและฟังเสียงได้ตามปกติ'), findsOneWidget);
    });

    testWidgets('chat summary → 429 before the stream → quota text', (tester) async {
      await _pump(
        tester,
        const SingleChildScrollView(child: ChatSummaryPanel(roomId: 'r1', roomName: 'ทีมขาย')),
        {'GET /api/comm-ai/chat/rooms/r1/summaries': {'list': []}},
        statusFor: {'POST /api/comm-ai/chat/rooms/r1/summary': 429},
        errorsFor: {'POST /api/comm-ai/chat/rooms/r1/summary': _quota429},
      );
      await tester.tap(find.byKey(const ValueKey('chat-summary-run')));
      await _settle(tester);
      expect(find.text('ใช้การสรุปของ ISAAC ครบโควตาของเดือนนี้แล้ว (50/50 ครั้ง) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'), findsOneWidget);
    });

    test('commAiErrorText: kinds, English UI, other errors unchanged', () {
      final e = ApiEnvelopeException(429, 'QUOTA_EXCEEDED', 'server text', details: {'kind': 'stt_minutes', 'used': 61.7, 'limit': 60});
      expect(commAiErrorText(e), 'ใช้นาทีถอดเสียงครบโควตาของเดือนนี้แล้ว (61/60 นาที) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ');
      L10n.set('en');
      expect(commAiErrorText(e), 'This month’s transcription minutes are used up (61/60 min) — ask an admin to upgrade the package');
      expect(commAiSttErrorText('quota_exceeded', quota: {'used': 5, 'limit': 5}), 'This month’s transcription minutes are used up (5/5 min) — the call continues normally');
      L10n.set('th');
      expect(commAiErrorText(ApiEnvelopeException(400, 'BAD', 'ข้อความจากเซิร์ฟเวอร์')), 'ข้อความจากเซิร์ฟเวอร์');
      expect(isCommAiQuotaError(ApiEnvelopeException(400, 'BAD', 'x')), isFalse);
    });
  });

  group('2 AI health (admins)', () {
    testWidgets('admin: problems with level and since; all good otherwise; members: no panel', (tester) async {
      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': true, 'available': true},
        'GET /api/comm-ai/ops/overview': {
          'usage': _usage,
          'prefs': {'digest': true},
          'is_admin': true,
          'health': [
            {'code': 'stt_key_invalid', 'level': 'error', 'message': 'key ถอดเสียงใช้ไม่ได้', 'message_en': 'Transcription key refused', 'since': '2026-11-11T03:00:00Z'},
            {'code': 'stt_failures', 'level': 'warning', 'message': 'ถอดเสียงล้มเหลวบ่อย', 'message_en': 'Frequent failures', 'since': null},
          ],
        },
      });
      await _show(tester, find.byKey(const ValueKey('comm-ai-health')));
      expect(find.text('key ถอดเสียงใช้ไม่ได้'), findsOneWidget);
      expect(find.text('เริ่มเมื่อ ${commAiWhen('2026-11-11T03:00:00Z')}'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('comm-ai-health-stt_key_invalid')), matching: find.byIcon(Icons.cancel_outlined)), findsNothing);
      expect(find.byKey(const ValueKey('comm-ai-health-stt_failures')), findsOneWidget);

      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'can_edit': true, 'available': true},
        'GET /api/comm-ai/ops/overview': {'usage': _usage, 'prefs': {}, 'is_admin': true, 'health': []},
      });
      await _show(tester, find.byKey(const ValueKey('comm-ai-health')));
      expect(find.byKey(const ValueKey('comm-ai-health-ok')), findsOneWidget);

      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'available': true},
        'GET /api/comm-ai/ops/overview': {'usage': _usage, 'prefs': {}, 'is_admin': false, 'health': null},
      });
      await _show(tester, find.byKey(const ValueKey('comm-ai-personal')));
      expect(find.byKey(const ValueKey('comm-ai-health')), findsNothing);
    });
  });

  group('3 personal digest', () {
    testWidgets('"ส่วนตัว": e-mail follows the digest switch; saved right away; a failed save goes back', (tester) async {
      final api = await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'available': true},
        'GET /api/comm-ai/ops/overview': {'usage': _usage, 'prefs': {'digest': true, 'digest_email': false}, 'is_admin': false},
        'PUT /api/comm-ai/me/prefs': {'prefs': {'digest': true, 'digest_email': true}},
      });
      await _show(tester, find.byKey(const ValueKey('comm-ai-pref-digest-email')));
      expect(find.text('ส่วนตัว'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comm-ai-pref-digest-email')));
      await _settle(tester);
      expect(_body(api, 'PUT /api/comm-ai/me/prefs'), {'digest_email': true});
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('comm-ai-pref-digest-email'))).value, isTrue);

      api.errorsFor['PUT /api/comm-ai/me/prefs'] = {'error_code': 'ERR', 'message': 'บันทึกไม่ได้'};
      await tester.tap(find.byKey(const ValueKey('comm-ai-pref-digest')));
      await _settle(tester);
      expect(_body(api, 'PUT /api/comm-ai/me/prefs'), {'digest': false});
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('comm-ai-pref-digest'))).value, isTrue, reason: 'put back');
      expect(find.text('บันทึกไม่ได้'), findsOneWidget);
    });

    testWidgets('digest off → the e-mail switch is disabled', (tester) async {
      await _pump(tester, const CommAiSettingsScreen(), {
        'GET /api/comm-ai/settings': {'settings': _settings, 'available': true},
        'GET /api/comm-ai/ops/overview': {'usage': _usage, 'prefs': {'digest': false, 'digest_email': false}, 'is_admin': false},
      });
      await _show(tester, find.byKey(const ValueKey('comm-ai-pref-digest-email')));
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('comm-ai-pref-digest-email'))).onChanged, isNull);
    });
  });

  final shareBase = <String, Object?>{
    'GET /api/comm-ai/settings': {'settings': _settings, 'available': true},
    'GET /api/comm-ai/share/call/c1/links': {'list': []},
    'GET /api/comm-ai/share/call/c1/recipients': {'list': []},
    'GET /api/comm-ai/share/call/c1/crm-suggestions': {
      'list': [
        {'module': 'account', 'id': 7, 'name': 'บริษัท เอ', 'reason': 'ชื่อถูกพูดถึงในสาย', 'score': 9},
        {'module': 'deal', 'id': 3, 'name': 'ดีลที่แอปไม่รองรับ', 'reason': 'x', 'score': 5},
        {'module': 'contact', 'id': 12, 'name': 'คุณบี', 'reason': 'อยู่ในห้องแชท', 'score': 4},
      ],
    },
    'POST /api/comm-ai/share/call/c1/crm': {'activity_id': 66},
    'POST /api/comm-ai/share/call/c1/email': {'sent': true, 'activity': {'activity_id': 70}},
  };
  const sheet = SingleChildScrollView(child: CommAiShareSheet(kind: 'call', id: 'c1', title: 'สรุป', hasAudio: true));

  group('4 CRM suggestions', () {
    testWidgets('CRM tab: chips (supported modules only), best guess preselected, another chip switches the record', (tester) async {
      final api = await _pump(tester, sheet, shareBase, size: const Size(420, 1400));
      await tester.tap(find.text('CRM'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('comm-ai-crm-suggestion-account-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('comm-ai-crm-suggestion-contact-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('comm-ai-crm-suggestion-deal-3')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('comm-ai-crm-suggestion-account-7'))).selected, isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('comm-ai-crm-record')), matching: find.text('บริษัท เอ')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comm-ai-crm-suggestion-contact-12')));
      await _settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('comm-ai-crm-record')), matching: find.text('คุณบี')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-crm')));
      await _settle(tester);
      expect(_body(api, 'POST /api/comm-ai/share/call/c1/crm'), containsPair('module', 'contact'));
      expect(_body(api, 'POST /api/comm-ai/share/call/c1/crm'), containsPair('record_id', 12));
    });

    testWidgets('e-mail "log as activity": the best guess is picked, so sending is ready', (tester) async {
      final api = await _pump(tester, sheet, shareBase, size: const Size(420, 1600));
      await tester.tap(find.text('อีเมล'));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('comm-ai-share-to')), 'a@x.co');
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-log-crm')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('comm-ai-crm-suggestion-account-7')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('comm-ai-email-crm-record')), matching: find.text('บริษัท เอ')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-email')));
      await _settle(tester);
      expect(_body(api, 'POST /api/comm-ai/share/call/c1/email')['log_to'], {'module': 'account', 'record_id': 7});
      expect(api.callKeys.where((k) => k.endsWith('/crm-suggestions')), hasLength(1), reason: 'loaded once');
    });
  });

  group('5 share history (admins)', () {
    testWidgets('admin: "ประวัติ" tab lists who shared / exported; members (403): no tab', (tester) async {
      await _pump(tester, sheet, {
        ...shareBase,
        'GET /api/comm-ai/share/call/c1/history': {
          'list': [
            {'id': 3, 'at': '2026-11-11T04:00:00Z', 'action': 'comm_ai.share.email', 'channel': 'email', 'user_id': 1, 'user_name': 'สมชาย', 'details': {'format': 'pdf', 'recipients': 2}},
            {'id': 2, 'at': '2026-11-11T03:30:00Z', 'action': 'comm_ai.share.view', 'channel': 'view', 'user_id': null, 'user_name': null, 'details': {'public': true}},
          ],
        },
      }, size: const Size(420, 1400));
      await tester.tap(find.text('ประวัติ'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('comm-ai-share-history')), findsOneWidget);
      expect(find.text('ประวัติการแชร์'), findsOneWidget);
      expect(find.textContaining('PDF · 2 ผู้รับ', findRichText: true), findsOneWidget);
      expect(find.text('สมชาย'), findsOneWidget);
      expect(find.text('บุคคลภายนอก (ลิงก์)'), findsOneWidget);

      await _pump(tester, sheet, shareBase, size: const Size(420, 1400), statusFor: {'GET /api/comm-ai/share/call/c1/history': 403}, errorsFor: {
        'GET /api/comm-ai/share/call/c1/history': {'error_code': 'AUTH_403_FORBIDDEN', 'message': 'เฉพาะผู้ดูแลธุรกิจ'},
      });
      expect(find.text('ประวัติ'), findsNothing);
    });
  });

  group('6 delete my data', () {
    testWidgets('participant: "ลบข้อมูลของฉัน" → recording + my lines → DELETE /calls/:id/mine?recording=1&transcript=1, then reload', (tester) async {
      final replies = <String, Object?>{
        'GET /api/comm-ai/calls/c1': _call(viewer: {'user_id': 2, 'participant': true, 'admin': false}, recordings: [
          {'user_id': 2, 'name': 'วิภา', 'url': '/api/x', 'duration_ms': 5000},
        ]),
        'DELETE /api/comm-ai/calls/c1/mine': {'recordings': 1, 'segments': 1, 'summaries_marked': 1},
      };
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), replies);
      expect(find.byTooltip('ลบข้อมูลของฉัน'), findsOneWidget);
      await tester.tap(find.byTooltip('ลบข้อมูลของฉัน'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comm-ai-delete-all')), findsNothing, reason: 'not an admin');
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('comm-ai-delete-recording'))).value, isTrue, reason: 'my recording preselected');
      await tester.tap(find.byKey(const ValueKey('comm-ai-delete-transcript')));
      await tester.pump();
      final before = api.callKeys.where((k) => k == 'GET /api/comm-ai/calls/c1').length;
      await tester.tap(find.byKey(const ValueKey('comm-ai-delete-submit')));
      await _settle(tester);
      final del = api.calls.lastWhere((c) => c.method == 'DELETE');
      expect(del.path, '/api/comm-ai/calls/c1/mine');
      expect(del.queryParameters, {'recording': 1, 'transcript': 1});
      expect(api.callKeys.where((k) => k == 'GET /api/comm-ai/calls/c1').length, before + 1);
      expect(find.text('ลบข้อมูลของคุณแล้ว — สรุปเดิมจะขึ้นว่าแหล่งข้อมูลถูกแก้'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('admin: "ลบการสนทนาทั้งหมด" needs "ลบ" typed → DELETE /calls/:id → screen closes', (tester) async {
      var closed = 0;
      final api = await _pump(tester, CallSummaryScreen(callId: 'c1', onDeleted: () => closed++), {
        'GET /api/comm-ai/calls/c1': _call(viewer: {'user_id': 9, 'participant': false, 'admin': true}),
        'DELETE /api/comm-ai/calls/c1': {'deleted': true, 'summaries': 1},
      });
      await tester.tap(find.byTooltip('ลบการสนทนาทั้งหมด'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comm-ai-delete-transcript')), findsNothing, reason: 'not in the call');
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('comm-ai-delete-all'))).value, isTrue);
      final submit = find.byKey(const ValueKey('comm-ai-delete-submit'));
      expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNull, reason: 'type ลบ first');
      await tester.enterText(find.byKey(const ValueKey('comm-ai-delete-confirm-text')), 'ลบ');
      await tester.pump();
      await tester.tap(submit);
      await _settle(tester);
      expect(api.callKeys, contains('DELETE /api/comm-ai/calls/c1'));
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no viewer rights (old server / not in the call) → no delete button', (tester) async {
      await _pump(tester, const CallSummaryScreen(callId: 'c1'), {'GET /api/comm-ai/calls/c1': _call()});
      expect(find.byTooltip('ลบข้อมูลของฉัน'), findsNothing);
      expect(find.byTooltip('ลบการสนทนาทั้งหมด'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('source_edited → "แหล่งข้อมูลถูกแก้ — สรุปใหม่ได้" with summarise again', (tester) async {
      final api = await _pump(tester, const CallSummaryScreen(callId: 'c1'), {
        'GET /api/comm-ai/calls/c1': _call(summary: {
          'id': 41,
          'status': 'done',
          'result': {
            ..._result,
            'source_edited': {'at': '2026-11-11T05:00:00Z', 'by': 2, 'what': ['recording']},
          },
        }),
        'POST /api/comm-ai/calls/c1/summarize': {'summary_id': 42, 'status': 'pending'},
      });
      expect(find.text('แหล่งข้อมูลถูกแก้ — สรุปใหม่ได้'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-summary-source-edited-resummarize')));
      await _settle(tester);
      expect(api.callKeys, contains('POST /api/comm-ai/calls/c1/summarize'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('realtime: someone deleted their lines → reload; the whole call deleted → close', (tester) async {
      var closed = 0;
      final api = await _pump(tester, CallSummaryScreen(callId: 'c1', onDeleted: () => closed++), {'GET /api/comm-ai/calls/c1': _call(summary: {'id': 41, 'status': 'done', 'result': _result})});
      int loads() => api.callKeys.where((k) => k == 'GET /api/comm-ai/calls/c1').length;
      final before = loads();
      RealtimeService.instance.dispatchForTest('ai:call_data_deleted', {'call_id': 'other', 'user_id': 2, 'what': ['transcript']});
      await _settle(tester);
      expect(loads(), before);
      RealtimeService.instance.dispatchForTest('ai:call_data_deleted', {'call_id': 'c1', 'user_id': 2, 'what': ['transcript']});
      await _settle(tester);
      expect(loads(), before + 1);
      RealtimeService.instance.dispatchForTest('ai:summary_deleted', {'summary_id': 41, 'source': 'call', 'source_id': 'c1'});
      await _settle(tester);
      expect(loads(), before + 2);
      expect(closed, 0);
      RealtimeService.instance.dispatchForTest('ai:call_data_deleted', {'call_id': 'c1', 'user_id': null, 'what': ['call']});
      await _settle(tester);
      expect(closed, 1);
      expect(find.text('การสนทนานี้ถูกลบแล้ว'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chat summary with can_delete → DELETE /summaries/:id; without it no button; deleted elsewhere → closes', (tester) async {
      var closed = 0;
      final api = await _pump(tester, ChatSummaryDetailScreen(id: '5', onDeleted: () => closed++), {
        'GET /api/comm-ai/summaries/5': {'id': 5, 'source': 'chat', 'result': _result, 'can_delete': true},
        'DELETE /api/comm-ai/summaries/5': {'deleted': true},
      });
      await tester.tap(find.byTooltip('ลบสรุปแชทนี้'));
      await tester.pumpAndSettle();
      expect(find.text('สรุปนี้และลิงก์แชร์ของสรุปจะถูกลบถาวร ข้อความในห้องแชทยังอยู่ตามเดิม'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comm-ai-delete-submit')));
      await _settle(tester);
      expect(api.callKeys, contains('DELETE /api/comm-ai/summaries/5'));
      expect(closed, 1);

      await _pump(tester, ChatSummaryDetailScreen(id: '6', onDeleted: () => closed++), {
        'GET /api/comm-ai/summaries/6': {'id': 6, 'source': 'chat', 'result': _result, 'can_delete': false},
      });
      expect(find.byTooltip('ลบสรุปแชทนี้'), findsNothing);
      RealtimeService.instance.dispatchForTest('ai:summary_deleted', {'summary_id': 6, 'source': 'chat', 'source_id': 9});
      await _settle(tester);
      expect(closed, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('history: rows deleted on any device go away (a call\'s own lines only → stays)', (tester) async {
      await _pump(tester, const CommAiHistoryScreen(), {
        'GET /api/comm-ai/history': {
          'list': [
            {'type': 'call', 'id': 'c1', 'at': '2026-11-11T03:00:00Z', 'headline': 'สายลูกค้า', 'participants': []},
            {'type': 'chat', 'id': 7, 'at': '2026-11-11T02:00:00Z', 'headline': 'สรุปแชททีม'},
          ],
          'next_before': null,
        },
      });
      expect(find.text('สายลูกค้า'), findsOneWidget);
      RealtimeService.instance.dispatchForTest('ai:call_data_deleted', {'call_id': 'c1', 'user_id': 2, 'what': ['recording']});
      RealtimeService.instance.dispatchForTest('ai:summary_deleted', {'summary_id': 7, 'source': 'chat', 'source_id': 3});
      await _settle(tester);
      expect(find.text('สายลูกค้า'), findsOneWidget);
      expect(find.text('สรุปแชททีม'), findsNothing);
      RealtimeService.instance.dispatchForTest('ai:call_data_deleted', {'call_id': 'c1', 'user_id': null, 'what': ['call']});
      await _settle(tester);
      expect(find.text('สายลูกค้า'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chat summary sheet: an earlier summary I made can be deleted; it leaves the list', (tester) async {
      final api = await _pump(tester, const SingleChildScrollView(child: ChatSummaryPanel(roomId: 'r1', roomName: 'ทีมขาย')), {
        'GET /api/comm-ai/chat/rooms/r1/summaries': {
          'list': [
            {'id': 5, 'status': 'done', 'headline': 'สรุปเมื่อวาน', 'range_from': '2026-11-10 09:00', 'range_to': '2026-11-10 18:00'},
          ],
        },
        'GET /api/comm-ai/summaries/5': {'id': 5, 'source': 'chat', 'result': _result, 'can_delete': true},
        'DELETE /api/comm-ai/summaries/5': {'deleted': true},
      }, size: const Size(420, 1400));
      await tester.tap(find.text('สรุปเมื่อวาน'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-summary-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comm-ai-delete-submit')));
      await _settle(tester);
      expect(api.callKeys, contains('DELETE /api/comm-ai/summaries/5'));
      expect(find.text('สรุปเมื่อวาน'), findsNothing);
      expect(find.byKey(const ValueKey('chat-summary-view-5')), findsNothing);
    });
  });

  group('7 background export jobs', () {
    late List<(List<int>, String)> shared;
    setUp(() {
      shared = [];
      CommAiShareSheet.shareFile = (bytes, name) async => shared.add((bytes, name));
      CommAiShareSheet.jobPollInterval = const Duration(milliseconds: 200);
    });
    tearDown(() {
      CommAiShareSheet.shareFile = (bytes, name) async {};
      CommAiShareSheet.jobPollInterval = const Duration(milliseconds: 1500);
    });

    testWidgets('ZIP with audio → job: progress from ai:export_job, then download and the share sheet', (tester) async {
      final replies = <String, Object?>{
        ...shareBase,
        'POST /api/comm-ai/export-jobs': {'job_id': 9, 'type': 'file', 'status': 'pending', 'progress': 0, 'stage': 'queued'},
        'GET /api/comm-ai/export-jobs/9': {'job_id': 9, 'status': 'running', 'progress': 10, 'stage': 'render'},
        'GET /api/comm-ai/export-jobs/9/download': Uint8List.fromList([80, 75, 3, 4]),
      };
      final api = await _pump(tester, sheet, replies, size: const Size(420, 1400));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-format')));
      await _settle(tester);
      await tester.tap(find.text('ZIP (PDF + Word + ข้อความ + เสียง)').last);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-include-audio')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-device')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_body(api, 'POST /api/comm-ai/export-jobs'), {'kind': 'call', 'id': 'c1', 'type': 'file', 'format': 'zip', 'include': ['summary', 'actions', 'transcript', 'audio'], 'lang': 'th'});
      expect(api.callKeys, isNot(contains('GET /api/comm-ai/export/call/c1')), reason: 'not the direct endpoint');
      expect(find.byKey(const ValueKey('comm-ai-export-job')), findsOneWidget);
      expect(find.text('รอคิว…'), findsOneWidget);

      RealtimeService.instance.dispatchForTest('ai:export_job', {'job_id': 8, 'status': 'running', 'progress': 90, 'stage': 'zip'});
      RealtimeService.instance.dispatchForTest('ai:export_job', {'job_id': 9, 'status': 'running', 'progress': 55, 'stage': 'audio'});
      await tester.pump();
      expect(find.text('55%'), findsOneWidget, reason: 'only my job');
      expect(find.text('เตรียมเสียง…'), findsOneWidget);

      replies['GET /api/comm-ai/export-jobs/9'] = {'job_id': 9, 'status': 'done', 'progress': 100, 'filename': 'สรุป.zip', 'download_url': '/api/comm-ai/export-jobs/9/download'};
      RealtimeService.instance.dispatchForTest('ai:export_job', {'job_id': 9, 'status': 'done', 'progress': 100});
      await _settle(tester);
      expect(api.callKeys, contains('GET /api/comm-ai/export-jobs/9/download'));
      expect(shared, hasLength(1));
      expect(shared.single.$1, [80, 75, 3, 4]);
      expect(shared.single.$2, 'isaac-call-c1.zip', reason: 'Thai server name → ASCII file name');
      expect(find.byKey(const ValueKey('comm-ai-export-job')), findsNothing);
    });

    testWidgets('PDF stays on the direct endpoint (no job)', (tester) async {
      final api = await _pump(tester, sheet, {...shareBase, 'GET /api/comm-ai/export/call/c1': Uint8List.fromList([37, 80])}, size: const Size(420, 1400));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-device')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.callKeys.where((k) => k.startsWith('GET /api/comm-ai/export/call/c1')), hasLength(1));
      expect(api.callKeys, isNot(contains('POST /api/comm-ai/export-jobs')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('call audio (tape) → job polled until done → file shared', (tester) async {
      final replies = <String, Object?>{
        ...shareBase,
        'POST /api/comm-ai/export-jobs': {'job_id': 11, 'type': 'tape', 'status': 'pending', 'progress': 0},
        'GET /api/comm-ai/export-jobs/11': {'job_id': 11, 'status': 'done', 'progress': 100, 'filename': 'call-c1.m4a'},
        'GET /api/comm-ai/export-jobs/11/download': Uint8List.fromList([1, 2, 3]),
      };
      final api = await _pump(tester, sheet, replies, size: const Size(420, 1400));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-tape')));
      await _settle(tester, 12);
      expect(_body(api, 'POST /api/comm-ai/export-jobs'), {'kind': 'call', 'id': 'c1', 'type': 'tape'});
      expect(shared.single.$2, 'call-c1.m4a');
    });

    testWidgets('a failed job shows why', (tester) async {
      final replies = <String, Object?>{
        ...shareBase,
        'POST /api/comm-ai/export-jobs': {'job_id': 12, 'type': 'tape', 'status': 'pending', 'progress': 0},
        'GET /api/comm-ai/export-jobs/12': {'job_id': 12, 'status': 'failed', 'progress': 30, 'error': 'ยังไม่มีเสียงของสายนี้'},
      };
      await _pump(tester, sheet, replies, size: const Size(420, 1400));
      await tester.tap(find.byKey(const ValueKey('comm-ai-share-tape')));
      await _settle(tester, 12);
      expect(find.text('งานส่งออกไม่สำเร็จ: ยังไม่มีเสียงของสายนี้'), findsOneWidget);
      expect(shared, isEmpty);
    });

    testWidgets('runCommAiExportJob: socket progress, GET for the final state, failure, cancel', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig()..debugOverrideSession(_admin);
      final replies = <String, Object?>{
        'POST /api/comm-ai/export-jobs': {'job_id': 3, 'status': 'pending', 'progress': 0},
        'GET /api/comm-ai/export-jobs/3': {'job_id': 3, 'status': 'running', 'progress': 20},
      };
      final adapter = FakeNextxAdapter(replies);
      config.apiClient.debugSetHttpAdapter(adapter);
      final events = StreamController<RealtimeEvent>.broadcast();
      addTearDown(events.close);
      final seen = <int>[];
      Map<String, dynamic>? out;
      Object? err;
      runCommAiExportJob(config.apiClient, {'type': 'file', 'kind': 'call', 'id': 'c1'}, events: events.stream, interval: const Duration(seconds: 5), onProgress: (j) => seen.add((j['progress'] as num).toInt()))
          .then<void>((j) {
        out = j;
      }, onError: (Object e) {
        err = e;
      });
      await tester.pump(const Duration(milliseconds: 10));
      events.add(const RealtimeEvent('ai:export_job', {'job_id': 3, 'status': 'running', 'progress': 70, 'stage': 'zip'}));
      await tester.pump(const Duration(milliseconds: 10));
      expect(seen, [0, 70]);
      replies['GET /api/comm-ai/export-jobs/3'] = {'job_id': 3, 'status': 'done', 'progress': 100, 'filename': 'a.zip'};
      events.add(const RealtimeEvent('ai:export_job', {'job_id': 3, 'status': 'done', 'progress': 100}));
      await tester.pump(const Duration(milliseconds: 10));
      expect(err, isNull);
      expect(out?['filename'], 'a.zip');
      expect(adapter.callKeys.where((k) => k == 'GET /api/comm-ai/export-jobs/3'), hasLength(1), reason: 'no poll before the 5 s interval');

      replies['GET /api/comm-ai/export-jobs/3'] = {'job_id': 3, 'status': 'failed', 'error': 'boom', 'error_code': 'X'};
      runCommAiExportJob(config.apiClient, {'type': 'tape'}, events: events.stream, interval: const Duration(milliseconds: 100)).then<void>((j) {
        out = j;
      }, onError: (Object e) {
        err = e;
      });
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 10));
      expect(err, isA<CommAiExportJobFailed>());
      expect('$err', 'boom');

      err = null;
      var cancelled = false;
      replies['GET /api/comm-ai/export-jobs/3'] = {'job_id': 3, 'status': 'running', 'progress': 5};
      runCommAiExportJob(config.apiClient, {'type': 'tape'}, events: events.stream, interval: const Duration(milliseconds: 100), isCancelled: () => cancelled)
          .then<void>((j) {
        out = j;
      }, onError: (Object e) {
        err = e;
      });
      await tester.pump(const Duration(milliseconds: 10));
      cancelled = true;
      await tester.pump(const Duration(milliseconds: 150));
      expect(err, isA<CommAiExportCancelled>());
    });
  });
}
