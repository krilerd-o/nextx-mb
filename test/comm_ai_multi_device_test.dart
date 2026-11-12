// ISAAC AI การสื่อสาร — one account signed in on several devices: device_id on stt:start and uploads,
// hand-off without asking again, stt:moved, the remembered choice on the server, live summary events.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/comm_ai/call_summary_screen.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_widgets.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart';
import 'package:nextx_mobile/services/calls/recording_upload_queue.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

class _Sig implements CallSignaling {
  final ctrl = StreamController<RealtimeEvent>.broadcast();
  final emitted = <(String, Map<String, dynamic>)>[];
  final acks = <String, Map<String, dynamic>>{};
  @override
  Stream<RealtimeEvent> get events => ctrl.stream;
  @override
  String? socketId = 'sA';
  @override
  bool connected = true;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async {
    emitted.add((event, data));
    return acks[event] ?? {'ok': false, 'error': 'server_error'};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emitted.add((event, data));
  void push(String type, Map<String, dynamic> data) => ctrl.add(RealtimeEvent(type, data));
}

class _Stt implements SttTransport {
  _Stt(this.events);
  @override
  final Stream<RealtimeEvent> events;
  final emitted = <(String, Map<String, dynamic>)>[];
  final acks = <String, Map<String, dynamic>>{};
  Map<String, dynamic> startAck = {'ok': true, 'settings': {'share': true, 'record': false}, 'speakers': []};
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async {
    emitted.add((event, data));
    return event == 'stt:start' ? startAck : (acks[event] ?? {'ok': true});
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emitted.add((event, data));
  @override
  void emitAudio(String callId, Uint8List pcm) {}
  List<Map<String, dynamic>> sent(String event) => [for (final e in emitted) if (e.$1 == event) e.$2];
}

class _Mic implements CallMicTap {
  final ctrl = StreamController<Uint8List>();
  bool stopped = false;
  @override
  Future<Stream<Uint8List>> start() async => ctrl.stream;
  @override
  Future<void> stop() async {
    stopped = true;
    await ctrl.close();
  }
}

class _UploadApi extends ApiClient {
  final sent = <Map<String, Object?>>[];
  int failNext = 0;
  @override
  Future<Map<String, dynamic>> uploadCallRecordingPart(String callId, String filePath,
      {required int part, int parts = 0, bool isFinal = false, int durationMs = 0, String mime = 'audio/wav', String deviceId = ''}) async {
    if (failNext > 0) {
      failNext--;
      throw Exception('offline');
    }
    sent.add({'call_id': callId, 'part': part, 'final': isFinal, 'device_id': deviceId});
    return {'ok': true};
  }
}

const _settings = {'stt_enabled': true, 'consent_mode': 'individual', 'ask_every_call': true, 'share_captions_default': true, 'record_audio': true};

Map<String, dynamic> _ring(String id) => {
      'call_id': id,
      'chat_room_id': 9,
      'media': 'audio',
      'group': false,
      'caller_id': 2,
      'caller_name': 'วิภา',
      'invitees': [
        {'user_id': 1, 'name': 'สมชาย', 'status': 'ringing'},
      ],
      'peers': [],
    };

Future<void> _until(bool Function() ok, {Duration max = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(max);
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Sig sig;
  late CallService service;
  late _Stt stt;
  late _Mic mic;
  late LiveTranscription lt;
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'app-phone-1'});
    CommAiDevice.reset();
    tmp = Directory.systemTemp.createTempSync('mdev');
    sig = _Sig();
    service = CallService(signaling: sig, myUserId: '1');
    stt = _Stt(sig.events);
    mic = _Mic();
    lt = LiveTranscription(transport: stt, micTap: () => mic)
      ..settings = Map<String, dynamic>.from(_settings)
      ..myUserId = '1'
      ..businessId = '5'
      ..resumeDelay = const Duration(milliseconds: 5);
    lt.attach(service);
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Rings, answers (the call becomes active here) with [decision] already made.
  Future<void> answer(String id, {bool enabled = true, bool record = false}) async {
    sig.acks['rtc:accept'] = {'ok': true, 'call': {..._ring(id), 'state': 'active'}, 'peers': []};
    sig.push('rtc:ring', _ring(id));
    await Future<void>.delayed(Duration.zero);
    if (enabled) await lt.decide(id, enabled: true, record: record);
    await service.accept();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('device id', () {
    test('generated once as app-<uuid> and kept', () async {
      SharedPreferences.setMockInitialValues({});
      CommAiDevice.reset();
      final a = await CommAiDevice.id();
      expect(a, matches(RegExp(r'^app-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(a.length, lessThanOrEqualTo(64));
      CommAiDevice.reset();
      expect(await CommAiDevice.id(), a, reason: 'read back from SharedPreferences');
    });

    test('stt:start carries device_id', () async {
      await answer('c1');
      expect(stt.sent('stt:start').single['device_id'], 'app-phone-1');
      expect(lt.running, isTrue);
    });

    test('uploads send device_id as a multipart field (single and parts)', () async {
      final api = ApiClient();
      final http = FakeNextxAdapter({'POST /api/comm-ai/calls/c1/recording': {'ok': true}});
      api.debugSetHttpAdapter(http);
      final f = File('${tmp.path}/a.wav')..writeAsBytesSync(List.filled(64, 1));
      await api.uploadCallRecordingPart('c1', f.path, part: 0, parts: 1, isFinal: true, deviceId: 'app-phone-1');
      await api.uploadCallRecording('c1', f.path, deviceId: 'app-phone-1');
      await api.uploadCallRecordingPart('c1', f.path, part: 1); // old queued part: no id
      Map<String, String> fields(int i) => {for (final e in (http.calls[i].data as FormData).fields) e.key: e.value};
      expect(fields(0)['device_id'], 'app-phone-1');
      expect(fields(0)['final'], '1');
      expect(fields(1)['device_id'], 'app-phone-1');
      expect(fields(2)['device_id'], '');
    });

    test('queued parts keep device_id across a restart; older entries send ""', () async {
      final api = _UploadApi()..failNext = 1;
      final q = RecordingUploadQueue(dir: () async => tmp)..api = api;
      final a = File('${tmp.path}/a.wav')..writeAsBytesSync(List.filled(100, 1));
      await q.add(RecordingPart(callId: 'c2', path: a.path, part: 0, parts: 1, isFinal: true, deviceId: 'app-phone-1'));
      await q.pump();
      expect(api.sent, isEmpty);
      final saved = jsonDecode(File('${(await q.folder()).path}/queue.json').readAsStringSync()) as List;
      expect((saved.single as Map)['device_id'], 'app-phone-1');
      expect(RecordingPart.fromJson({'call_id': 'x', 'path': '/p'})!.deviceId, '', reason: 'queued by an older version');

      final api2 = _UploadApi();
      final q2 = RecordingUploadQueue(dir: () async => tmp)..api = api2;
      await q2.pump();
      expect(api2.sent.single['device_id'], 'app-phone-1');
      q.dispose();
      q2.dispose();
    });
  });

  group('hand-off', () {
    test('picked up from another device: stt:sync says I am transcribed → no consent, same choice', () async {
      await answer('c3', enabled: false);
      stt.acks['stt:sync'] = {
        'ok': true,
        'speakers': [
          {'user_id': 2, 'enabled': true, 'share': true},
          {'user_id': 1, 'enabled': true, 'share': false, 'record': true},
        ],
      };
      stt.startAck = {'ok': true, 'handoff': true, 'settings': {'share': false, 'record': true}, 'speakers': []};
      expect(await lt.needsConsent('c3'), isFalse);
      expect(stt.sent('stt:sync').single, {'call_id': 'c3'});
      await _until(() => lt.running);
      expect(lt.decision?.share, isFalse);
      expect(lt.decision?.record, isTrue);
      final start = stt.sent('stt:start').single;
      expect(start['share'], isFalse);
      expect(start['device_id'], 'app-phone-1');
    });

    test('not transcribed elsewhere → the consent sheet is still shown', () async {
      await answer('c4', enabled: false);
      stt.acks['stt:sync'] = {'ok': true, 'speakers': []};
      expect(await lt.needsConsent('c4'), isTrue);
      expect(lt.decision?.callId, isNot('c4'));
    });

    test('ack handoff=true takes share/record from ack.settings', () async {
      stt.startAck = {'ok': true, 'handoff': true, 'settings': {'share': false, 'record': false}, 'speakers': []};
      await answer('c5'); // decided share=true locally
      expect(lt.running, isTrue);
      expect(lt.decision?.share, isFalse, reason: 'the other device chose private captions');
      expect(lt.decision?.enabled, isTrue);
    });
  });

  group('stt:moved', () {
    test('stops mic + recorder, uploads the final part with device_id, no stt:stop, notice shown', () async {
      final api = _UploadApi();
      RecordingUploadQueue.instance = RecordingUploadQueue(dir: () async => tmp)..api = api;
      stt.startAck = {'ok': true, 'settings': {'share': true, 'record': true}, 'speakers': []};
      await answer('c6', record: true);
      expect(lt.running, isTrue);
      mic.ctrl.add(Uint8List(96000)); // 2 s
      await Future<void>.delayed(const Duration(milliseconds: 20));

      sig.push('stt:moved', {'call_id': 'c6', 'reason': 'moved'});
      await _until(() => api.sent.isNotEmpty);
      expect(mic.stopped, isTrue);
      expect(lt.running, isFalse);
      expect(api.sent.single, {'call_id': 'c6', 'part': 0, 'final': true, 'device_id': 'app-phone-1'});
      expect(stt.sent('stt:stop'), isEmpty, reason: 'the other device keeps transcribing');
      expect(service.notice, callMovedNotice);

      // The call screen updating does not take the transcription back.
      service.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stt.sent('stt:start'), hasLength(1));

      // rtc:ended {reason:'moved'} ends the call here with the same notice.
      sig.push('rtc:ended', {'call_id': 'c6', 'reason': 'moved'});
      await _until(() => service.phase == CallPhase.idle);
      expect(service.notice, callMovedNotice);
      expect(stt.sent('stt:stop'), isEmpty);
    });
  });

  group('reconnect', () {
    test('re-sends stt:start with device_id, up to 3 tries', () async {
      sig.acks['rtc:rejoin'] = {'ok': true, 'peers': []};
      await answer('c7');
      expect(lt.running, isTrue);
      stt.startAck = {'ok': false, 'error': 'timeout'};
      sig.push(RealtimeService.connectedEvent, const {});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final starts = stt.sent('stt:start');
      expect(starts, hasLength(4), reason: 'first start + 3 tries');
      expect(starts.last['requested'], isTrue);
      expect(starts.last['device_id'], 'app-phone-1');
    });

    test('stops after the first success', () async {
      sig.acks['rtc:rejoin'] = {'ok': true, 'peers': []};
      await answer('c8');
      sig.push(RealtimeService.connectedEvent, const {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stt.sent('stt:start'), hasLength(2));
    });
  });

  group('remembered choice on the server', () {
    late FakeNextxAdapter http;
    ApiClient api(Map<String, Object?> replies) {
      final a = ApiClient();
      http = FakeNextxAdapter(replies);
      a.debugSetHttpAdapter(http);
      return a;
    }

    final noAsk = {'settings': {..._settings, 'ask_every_call': false}};

    test('server choice applies (no ask) and replaces the local cache', () async {
      SharedPreferences.setMockInitialValues({'commAi.sttChoice': 'off'});
      lt
        ..settings = null
        ..api = api({
          'GET /api/comm-ai/settings': noAsk,
          'GET /api/comm-ai/consent-choice': {'choice': {'enabled': true, 'share': false, 'record': true}, 'updated_at': '2026-11-12T00:00:00Z'},
        });
      expect(await lt.needsConsent('c9'), isFalse);
      expect(http.callKeys, contains('GET /api/comm-ai/consent-choice'));
      expect(lt.decision?.enabled, isTrue);
      expect(lt.decision?.share, isFalse);
      expect(lt.decision?.record, isTrue);
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), 'on,private,rec');
    });

    test('forgotten on the server (null) → ask again, even with an old cached value', () async {
      SharedPreferences.setMockInitialValues({'commAi.sttChoice': 'on'});
      lt
        ..settings = null
        ..api = api({'GET /api/comm-ai/settings': noAsk, 'GET /api/comm-ai/consent-choice': {'choice': null}});
      expect(await lt.needsConsent('c10'), isTrue);
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), isNull);
    });

    test('server unreachable → the cached choice still applies', () async {
      SharedPreferences.setMockInitialValues({'commAi.sttChoice': 'on,rec'});
      lt
        ..settings = null
        ..api = api({'GET /api/comm-ai/settings': noAsk});
      expect(await lt.needsConsent('c11'), isFalse);
      expect(lt.decision?.record, isTrue);
    });

    test('"จำการเลือกนี้" → PUT to the server + cache', () async {
      SharedPreferences.setMockInitialValues({});
      lt.api = api({'PUT /api/comm-ai/consent-choice': {'choice': {'enabled': true, 'share': false, 'record': false}}});
      await lt.decide('c12', enabled: true, share: false, remember: true);
      final put = http.calls.singleWhere((c) => c.method == 'PUT' && c.path == '/api/comm-ai/consent-choice');
      expect(put.data, {
        'choice': {'enabled': true, 'share': false, 'record': false},
      });
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), 'on,private');
    });

    test('ai:consent_choice from another device updates the cache (own Space only)', () async {
      SharedPreferences.setMockInitialValues({});
      sig.push('ai:consent_choice', {'business_id': 6, 'choice': {'enabled': true}});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), isNull, reason: 'other Space');
      sig.push('ai:consent_choice', {'business_id': 5, 'choice': {'enabled': true, 'share': true, 'record': true}});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), 'on,rec');
      sig.push('ai:consent_choice', {'business_id': 5, 'choice': null});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await SharedPreferences.getInstance()).getString('commAi.sttChoice'), isNull);
    });
  });

  group('live summary events', () {
    const result = {
      'headline': 'แอร์น้ำหยด',
      'key_points': ['แอร์ชั้น 3'],
      'action_items': [
        {'text': 'นัดช่าง'},
        {'text': 'ส่งใบเสนอราคา'},
      ],
      'action_done': [0],
    };
    Map<String, Object?> call({Object? summary}) => {
          'call_id': 'c1',
          'media': 'audio',
          'started_at': '2026-11-11T03:00:00Z',
          'participants': [
            {'user_id': 1, 'name': 'สมชาย'},
          ],
          'summary': summary,
          'transcript': [
            {'seq': 1, 'user_id': 1, 'name': 'สมชาย', 'start_ms': 0, 'end_ms': 2000, 'text': 'สวัสดีครับ', 'edited': false, 'can_edit': true},
            {'seq': 2, 'user_id': 1, 'name': 'สมชาย', 'start_ms': 3000, 'end_ms': 5000, 'text': 'แอร์ชั้นสาม', 'edited': false, 'can_edit': true},
          ],
          'recordings': [],
        };

    Future<FakeNextxAdapter> pump(WidgetTester tester, Widget screen, Map<String, Object?> replies) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final config = AppConfig()..debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '5', menusLoaded: true, menuKeys: ['comm-ai-history']));
      final adapter = FakeNextxAdapter(replies);
      config.apiClient.debugSetHttpAdapter(adapter);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: screen))));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return adapter;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a line fixed on another device shows right away', (tester) async {
      await pump(tester, const CallSummaryScreen(callId: 'c1'), {'GET /api/comm-ai/calls/c1': call(summary: {'id': 41, 'status': 'done', 'result': result})});
      await tester.tap(find.textContaining('บทสนทนา (2)'));
      await settle(tester);
      expect(find.textContaining('แอร์ชั้นสาม', findRichText: true), findsOneWidget);
      RealtimeService.instance.dispatchForTest('ai:call_segment_edited', {'call_id': 'other', 'seq': 2, 'text': 'ไม่ใช่สายนี้', 'edited_by': 1});
      RealtimeService.instance.dispatchForTest('ai:call_segment_edited', {'call_id': 'c1', 'seq': 2, 'text': 'แอร์ชั้น 3 น้ำหยด', 'edited_by': 1});
      await settle(tester);
      expect(find.textContaining('แอร์ชั้น 3 น้ำหยด', findRichText: true), findsOneWidget);
      expect(find.textContaining('ไม่ใช่สายนี้', findRichText: true), findsNothing);
      expect(find.textContaining('(แก้ไขแล้ว)', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('summary started on another device → the screen reloads and follows it', (tester) async {
      final replies = <String, Object?>{'GET /api/comm-ai/calls/c1': call(summary: {'id': 40, 'status': 'failed'})};
      final api = await pump(tester, const CallSummaryScreen(callId: 'c1'), replies);
      expect(find.byKey(const ValueKey('call-summary-busy')), findsNothing);
      replies['GET /api/comm-ai/calls/c1'] = call(summary: {'id': 41, 'status': 'running'});
      final before = api.callKeys.where((k) => k == 'GET /api/comm-ai/calls/c1').length;
      RealtimeService.instance.dispatchForTest('ai:call_summary_status', {'call_id': 'c1', 'summary_id': 41, 'status': 'running'});
      await settle(tester);
      expect(api.callKeys.where((k) => k == 'GET /api/comm-ai/calls/c1').length, before + 1);
      expect(find.byKey(const ValueKey('call-summary-busy')), findsOneWidget);
      replies['GET /api/comm-ai/calls/c1'] = call(summary: {'id': 41, 'status': 'done', 'result': result});
      RealtimeService.instance.dispatchForTest('ai:call_summary_ready', {'call_id': 'c1', 'summary_id': 41, 'headline': 'x'});
      await settle(tester);
      expect(find.byKey(const ValueKey('call-summary-view')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('follow-up ticked on another device updates the open summary (call or chat)', (tester) async {
      await pump(tester, const SingleChildScrollView(child: CommAiSummaryView(result: result, summaryId: '41')), {});
      Icon icon(int i) => tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey('comm-ai-action-$i')), matching: find.byType(Icon)).first);
      expect(icon(1).icon, Icons.check_box_outline_blank_rounded);
      RealtimeService.instance.dispatchForTest('ai:summary_actions', {'summary_id': 99, 'source': 'chat', 'source_id': 9, 'action_done': [0, 1]});
      await settle(tester);
      expect(icon(1).icon, Icons.check_box_outline_blank_rounded, reason: 'another summary');
      RealtimeService.instance.dispatchForTest('ai:summary_actions', {'summary_id': 41, 'source': 'call', 'source_id': 'c1', 'action_done': [1]});
      await settle(tester);
      expect(icon(1).icon, isNot(Icons.check_box_outline_blank_rounded));
      expect(icon(0).icon, Icons.check_box_outline_blank_rounded);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
