// AI การสื่อสาร (mobile): consent before answering, live captions, caller-decides request, audio packets.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/calls/call_overlay.dart';
import 'package:nextx_mobile/screens/comm_ai/chat_summary_sheet.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSignaling implements CallSignaling {
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
  List<Map<String, dynamic>> sent(String event) => [for (final e in emitted) if (e.$1 == event) e.$2];
}

class FakeStt implements SttTransport {
  FakeStt(this.events);
  @override
  final Stream<RealtimeEvent> events;
  final emitted = <(String, Map<String, dynamic>)>[];
  final audio = <(String, int)>[];
  Map<String, dynamic> startAck = {'ok': true, 'settings': {'share': true, 'record': false, 'sample_rate': 24000}, 'speakers': []};
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async {
    emitted.add((event, data));
    return event == 'stt:start' ? startAck : {'ok': true};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emitted.add((event, data));
  @override
  void emitAudio(String callId, Uint8List pcm) => audio.add((callId, pcm.length));
  List<Map<String, dynamic>> sent(String event) => [for (final e in emitted) if (e.$1 == event) e.$2];
}

class FakeMic implements CallMicTap {
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

const _settings = {'stt_enabled': true, 'consent_mode': 'individual', 'ask_every_call': true, 'share_captions_default': true, 'record_audio': false};

Map<String, dynamic> _ring({String id = 'c1'}) => {
      'call_id': id,
      'chat_room_id': 9,
      'room_name': 'ทีม',
      'media': 'audio',
      'group': false,
      'caller_id': 2,
      'caller_name': 'วิภา',
      'invitees': [
        {'user_id': 1, 'name': 'สมชาย', 'status': 'ringing'},
      ],
      'peers': [],
    };

void main() {
  late FakeSignaling sig;
  late CallService service;
  late FakeStt stt;
  late FakeMic mic;
  late LiveTranscription lt;

  void init() {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'app-test-1'});
    sig = FakeSignaling();
    service = CallService(signaling: sig, myUserId: '1');
    stt = FakeStt(sig.events);
    mic = FakeMic();
    lt = LiveTranscription(transport: stt, micTap: () => mic)
      ..settings = Map<String, dynamic>.from(_settings)
      ..myUserId = '1'
      ..businessId = '5';
    LiveTranscription.instance = lt;
    lt.attach(service);
    sig.acks['rtc:accept'] = {'ok': true, 'call': {..._ring(), 'state': 'active'}, 'peers': []};
  }

  setUp(init);

  testWidgets('answering asks first; "รับสาย + เริ่มจดบทสนทนา" answers and starts captions', (tester) async {
    init(); // inside the test zone so stream events are delivered by pump()
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [Positioned.fill(child: CallOverlay(service: service))]))));
    sig.push('rtc:ring', _ring());
    await tester.pump();
    expect(find.byKey(const ValueKey('call-incoming')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('call-accept')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-stt-consent')), findsOneWidget, reason: 'consent before answering');
    expect(sig.sent('rtc:accept'), isEmpty, reason: 'not answered yet');

    await tester.tap(find.byKey(const ValueKey('call-stt-accept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sig.sent('rtc:accept').single['call_id'], 'c1');
    expect(service.phase, CallPhase.active);
    final start = stt.sent('stt:start').single;
    expect(start['call_id'], 'c1');
    expect(start['share'], isTrue);
    expect(start['business_id'], 5);
    expect(lt.running, isTrue);

    // Microphone → 100 ms packets go to the server.
    mic.ctrl.add(Uint8List(4800));
    await tester.pump();
    expect(stt.audio.single, ('c1', 4800));

    // Captions from the server (partial then final) show without rebuilding the whole call screen.
    sig.push('stt:state', {'call_id': 'c1', 'user_id': 2, 'name': 'วิภา', 'enabled': true, 'share': true, 'status': 'open'});
    sig.push('stt:segment', {'call_id': 'c1', 'user_id': 2, 'name': 'วิภา', 'item_id': 'a', 'text': 'แอร์ชั้น', 'final': false});
    sig.push('stt:segment', {'call_id': 'c1', 'user_id': 2, 'name': 'วิภา', 'item_id': 'a', 'text': 'แอร์ชั้น 3 น้ำหยด', 'final': true});
    sig.push('stt:segment', {'call_id': 'c1', 'user_id': 2, 'name': 'วิภา', 'item_id': 'a', 'text': 'แอร์', 'final': false});
    await tester.pump();
    expect(lt.captions.value.single.text, 'แอร์ชั้น 3 น้ำหยด', reason: 'late partial never replaces a final line');
    expect(find.byKey(const ValueKey('call-captions')), findsOneWidget);
    expect(find.textContaining('แอร์ชั้น 3 น้ำหยด'), findsOneWidget);

    // Hide my captions from the other side.
    lt.setShare(false);
    expect(stt.sent('stt:share').single, {'call_id': 'c1', 'share': false});

    // Call ends → microphone released, captions cleared.
    sig.push('rtc:ended', {'call_id': 'c1', 'reason': 'completed'});
    await tester.pump(const Duration(milliseconds: 500));
    expect(mic.stopped, isTrue);
    expect(lt.running, isFalse);
    expect(lt.captions.value, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"รับสายอย่างเดียว" answers without captions', (tester) async {
    init();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [Positioned.fill(child: CallOverlay(service: service))]))));
    sig.push('rtc:ring', _ring(id: 'c2'));
    sig.acks['rtc:accept'] = {'ok': true, 'call': {..._ring(id: 'c2'), 'state': 'active'}, 'peers': []};
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('call-accept')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('call-stt-skip')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.phase, CallPhase.active);
    expect(stt.sent('stt:start'), isEmpty);
    expect(lt.decision?.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('feature off → answering is not delayed', () async {
    lt.settings = {'stt_enabled': false};
    expect(await lt.needsConsent('c3'), isFalse);
  });

  test('caller decides: stt:request starts my captions with requested=true', () async {
    sig.push('rtc:ring', _ring(id: 'c4'));
    sig.acks['rtc:accept'] = {'ok': true, 'call': {..._ring(id: 'c4'), 'state': 'active'}, 'peers': []};
    await Future<void>.delayed(Duration.zero);
    await service.accept();
    await Future<void>.delayed(Duration.zero);
    expect(stt.sent('stt:start'), isEmpty);
    sig.push('stt:request', {'call_id': 'c4', 'by_user_id': 2, 'by_name': 'วิภา', 'share': true});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final start = stt.sent('stt:start').single;
    expect(start['requested'], isTrue);
    expect(lt.request?['by_name'], 'วิภา');
  });

  test('server refuses (no API key) → call continues, error shown', () async {
    stt.startAck = {'ok': false, 'error': 'stt_not_configured'};
    sig.push('rtc:ring', _ring(id: 'c5'));
    sig.acks['rtc:accept'] = {'ok': true, 'call': {..._ring(id: 'c5'), 'state': 'active'}, 'peers': []};
    await Future<void>.delayed(Duration.zero);
    await lt.decide('c5', enabled: true);
    await service.accept();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.phase, CallPhase.active);
    expect(lt.error, 'stt_not_configured');
    expect(lt.running, isFalse);
  });

  test('rechunk makes fixed even-sized packets; WAV header is valid', () async {
    final out = await rechunk(Stream.fromIterable([Uint8List(3000), Uint8List(3000), Uint8List(4001)]), 4800).toList();
    expect(out.map((p) => p.length).toList(), [4800, 4800, 400]);
    final h = wavHeader(48000);
    expect(String.fromCharCodes(h.sublist(0, 4)), 'RIFF');
    expect(ByteData.sublistView(h).getUint32(24, Endian.little), 24000);
    expect(ByteData.sublistView(h).getUint32(40, Endian.little), 48000);
  });

  test('chat summary ranges are Thai wall-clock', () {
    final now = DateTime(2026, 11, 11, 14, 5);
    expect(chatSummaryRange('today', now: now), ('2026-11-11 00:00', '2026-11-11 14:05'));
    expect(chatSummaryRange('yesterday', now: now), ('2026-11-10 00:00', '2026-11-10 23:59'));
    expect(chatSummaryRange('7d', now: now), ('2026-11-05 00:00', '2026-11-11 14:05'));
    expect(chatSummaryRange('3h', now: now), ('2026-11-11 11:05', '2026-11-11 14:05'));
  });
}
