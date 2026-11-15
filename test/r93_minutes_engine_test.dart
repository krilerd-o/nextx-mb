// ไอแซคบันทึกประชุม (AI Minute Meeting): recorder engine, upload queue "minute" target, resumable uploader,
// room session captions / chat / waiting room.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:nextx_mobile/core/minutes/minutes.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/audio/pcm.dart';
import 'package:nextx_mobile/services/audio/recording_upload_queue.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart' show CommAiDevice;
import 'package:nextx_mobile/services/minutes/minute_recorder.dart';
import 'package:nextx_mobile/services/minutes/minute_room_session.dart';
import 'package:nextx_mobile/services/minutes/minute_uploader.dart';
import 'package:nextx_mobile/services/notebook/notebook_recorder.dart' show LiveState, MicPermission, RecordStart;
import 'package:nextx_mobile/services/notebook/recording_foreground.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';
import 'support/recorder_fakes.dart';

class FakeMinuteTransport extends FakeNotebookTransport implements MinuteSttTransport {
  final minuteAudio = <(String, int)>[];
  @override
  void sendMinuteAudio(String meetingId, Uint8List pcm) => minuteAudio.add((meetingId, pcm.length));
}

Map<String, dynamic> _json(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});

void main() {
  late Directory tmp;
  late FakeMinuteTransport t;
  late FakePausableMic mic;
  late NoopRecordingForeground fg;
  late FakeNextxAdapter http;
  late ApiClient api;
  late RecordingUploadQueue q;
  late MinuteRecorder r;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'phone-1'});
    CommAiDevice.reset();
    tmp = Directory.systemTemp.createTempSync('minrec');
    t = FakeMinuteTransport();
    mic = FakePausableMic();
    fg = NoopRecordingForeground();
    http = FakeNextxAdapter({
      'POST /api/ai/minutes': {'item': {'id': 55, 'title': 'ประชุมทีม', 'status': 'live'}},
      'POST /api/ai/minutes/55/parts': {'received': true},
      'POST /api/ai/minutes/55/pause': {'status': 'paused'},
      'POST /api/ai/minutes/55/resume': {'status': 'live'},
      'POST /api/ai/minutes/55/stop': {'status': 'processing'},
      'DELETE /api/ai/minutes/55': {'deleted': true},
    });
    api = ApiClient()..debugSetHttpAdapter(http);
    q = RecordingUploadQueue(dir: () async => tmp)..api = api;
    now = DateTime(2026, 11, 15, 10);
    r = MinuteRecorder(transport: t, mic: () => mic, queue: q, foreground: fg, now: () => now, permission: () async => MicPermission.granted)
      ..api = api
      ..businessId = '1'
      ..partBytes = kPcmBytesPerSecond;
  });

  tearDown(() {
    q.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> idle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await q.pump();
      await idle(10);
    }
  }

  test('start → stt:start (minute) → live audio, captions and live translation', () async {
    expect(await r.start(title: 'ประชุมทีม', locale: 'th', languages: ['th', 'en'], template: 'sales'), RecordStart.started);
    final body = _json(http.calls.firstWhere((c) => c.method == 'POST' && c.path == '/api/ai/minutes'));
    expect(body['title'], 'ประชุมทีม');
    expect(body['languages'], ['th', 'en']);
    expect(body['template'], 'sales');
    expect('${body['client_session_id']}', startsWith('minute-'));
    final st = t.sent('stt:start').single;
    expect(st['session_kind'], 'minute');
    expect(st['meeting_id'], 55);
    expect(st['business_id'], 1);
    expect(r.live, LiveState.live);

    mic.feed(100);
    await idle();
    expect(t.minuteAudio.single, ('55', 4800));

    await r.setTranslate('en');
    expect(t.sent('minute:translate').last, {'meeting_id': 55, 'lang': 'en', 'on': true});
    t.push('stt:segment', {'meeting_id': 55, 'seq': 1, 'text': 'สวัสดี', 'partial': true});
    t.push('stt:segment', {'meeting_id': 55, 'seq': 1, 'text': 'สวัสดีครับ', 'partial': false, 'start_ms': 0});
    t.push('stt:segment', {'meeting_id': 9, 'seq': 1, 'text': 'อื่น'});
    t.push('minute:segment_tr', {'meeting_id': 55, 'lang': 'en', 'seq': 1, 'text': 'Hello'});
    t.push('minute:segment_tr', {'meeting_id': 55, 'lang': 'ja', 'seq': 1, 'text': 'こんにちは'});
    await idle(5);
    expect([for (final l in r.lines.value) l.text], ['สวัสดีครับ']);
    expect(r.translated.value, {1: 'Hello'});
    await r.stop();
  });

  test('pause / resume follow the server; stop queues the last part + stop with the finish choices', () async {
    await r.start(title: 'x');
    now = now.add(const Duration(seconds: 5));
    await r.pause();
    await idle();
    expect(t.sent('stt:pause').single, {'meeting_id': 55});
    expect(http.callKeys, contains('POST /api/ai/minutes/55/pause'));
    expect(await r.resume(), isTrue);
    mic.feed(1500);
    await idle();
    final done = await r.stop(const MinuteFinish(summarizeNow: false, template: 'project', translate: ['en'], tasks: false));
    expect(done?.meetingId, '55');
    expect(done?.summarizeNow, isFalse);
    await drain();
    final stop = _json(http.calls.lastWhere((c) => c.path == '/api/ai/minutes/55/stop'));
    expect(stop['summary_mode'], 'later');
    expect(stop['template'], 'project');
    expect((stop['features'] as Map)['translate'], ['en']);
    expect(stop['parts'], greaterThanOrEqualTo(1));
    expect(http.calls.where((c) => c.path == '/api/ai/minutes/55/parts').length, greaterThanOrEqualTo(1));
    expect(r.phase, MinuteRecPhase.idle);
    expect(fg.calls.last, 'stop');
  });

  test('a camera file on the way: stop says expect_video', () async {
    await r.start(title: 'v');
    await r.stop(const MinuteFinish().withVideo());
    await drain();
    final stop = _json(http.calls.lastWhere((c) => c.path == '/api/ai/minutes/55/stop'));
    expect((stop['features'] as Map)['expect_video'], isTrue);
  });

  test('discard deletes the meeting and drops queued parts', () async {
    await r.start(title: 'x');
    mic.feed(1200);
    await idle();
    await r.discard();
    await idle();
    expect(http.callKeys, contains('DELETE /api/ai/minutes/55'));
    expect(q.pendingFor(clientSessionId: r.clientSessionId).where((p) => p.target == RecordingTarget.minute), isEmpty);
  });

  test('queue: minute items survive JSON and the notification ignores an idle notebook', () {
    const p = RecordingPart.minuteStop(meetingId: '7', clientSessionId: 'c1', durationMs: 900, parts: 2, extra: {'summary_mode': 'now'});
    final back = RecordingPart.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
    expect(back.target, RecordingTarget.minute);
    expect(back.op, RecordingOp.stop);
    expect(back.recordingId, '7');
    expect(back.extra, {'summary_mode': 'now'});
    expect(back.group, 'min:c1');
    expect(RecordingPart.fromJson({'target': 'minute', 'op': 'part', 'path': '/x'}), isNull, reason: 'no meeting and no session');
  });

  test('uploader: asks what is missing, sends only those parts, completes, survives a restart', () async {
    final file = File('${tmp.path}/meeting.mp3')..writeAsBytesSync(Uint8List(2500));
    var missing = <int>[0, 1, 2];
    final replies = <String, Object?>{
      'POST /api/ai/minutes/uploads': {'upload': {'upload_id': 'u1', 'meeting_id': 9, 'part_size': 1000, 'parts_total': 3, 'missing': [0, 1, 2]}, 'item': {'id': 9, 'title': 'meeting'}},
      'POST /api/ai/minutes/uploads/u1/complete': {'upload': {'status': 'done'}, 'item': {'id': 9}},
      for (final n in [0, 1, 2]) 'PUT /api/ai/minutes/uploads/u1/parts/$n': {'received': n},
    };
    final h = FakeNextxAdapter(replies);
    h.onRequest = (o) {
      if (o.method == 'PUT') {
        final n = int.parse(o.path.split('/').last);
        missing = missing.where((x) => x != n).toList();
      }
      replies['GET /api/ai/minutes/uploads/u1'] = {'upload': {'status': 'open', 'missing': missing}};
    };
    final up = MinuteUploader(prefsKey: 'test.uploads')..backoff = (_) => const Duration(milliseconds: 5);
    final apiU = ApiClient()..debugSetHttpAdapter(h);
    await up.bind(apiU);
    missing = [1, 2]; // part 0 was sent before (e.g. the app closed)
    final done = up.done.first;
    await up.add(path: file.path, filename: 'meeting.mp3', mime: 'audio/mpeg', body: {'title': 'meeting'}, complete: {'features': {'summarize': true}});
    await done.timeout(const Duration(seconds: 5));
    final puts = [for (final c in h.calls) if (c.method == 'PUT') c.path.split('/').last];
    expect(puts, ['1', '2']);
    final lens = [for (final c in h.calls) if (c.method == 'PUT') c.headers['content-length']];
    expect(lens, [1000, 500]);
    expect(h.callKeys, contains('POST /api/ai/minutes/uploads/u1/complete'));
    expect(_json(h.calls.firstWhere((c) => c.path == '/api/ai/minutes/uploads')).containsKey('client_session_id'), isTrue);
    expect(up.jobs, isEmpty);
  });

  test('room session: joins captions with the ticket, gates silence, captions + translation, chat, waiting room', () async {
    final rt = _FakeRealtime();
    final media = _FakeMedia();
    final mic2 = FakePausableMic();
    final s = MinuteRoomSession(meetingId: '5', roomCode: 'abc-defg-hij', ticket: 'T', identity: 'u1', role: 'host', name: 'สมชาย', media: media, realtime: rt, mic: () => mic2);
    await s.start(url: 'wss://lk', token: 'tok', micOn: true);
    expect(media.connectedWith, ('wss://lk', 'tok'));
    expect(rt.acks.map((e) => e.$1), containsAll(['minute:room_join', 'minute:room_stt']));
    expect(s.transcribing, isTrue);
    mic2.feed(100, amplitude: 0); // silence: not sent
    await idle(5);
    expect(rt.roomAudio, 0);
    mic2.feed(100, amplitude: 8000);
    await idle(5);
    expect(rt.roomAudio, 1);

    rt.push('minute:caption', {'seq': 3, 'speaker': 'แขก A', 'text': 'สวัส', 'partial': true});
    rt.push('minute:caption', {'seq': 3, 'speaker': 'แขก A', 'text': 'สวัสดีครับ', 'partial': false});
    await idle(5);
    expect(s.captions.value.single.text, 'สวัสดีครับ');
    await s.setCaptionLang('en');
    rt.push('minute:caption_tr', {'seq': 3, 'lang': 'en', 'text': 'Hello'});
    await idle(5);
    expect(s.translated.value, {3: 'Hello'});

    rt.push('minute:room_waiting', {'identity': 'g1', 'name': 'Guest'});
    await idle(5);
    expect(s.waiting.value.single.$2, 'Guest');
    s.admitted('g1');
    expect(s.waiting.value, isEmpty);

    await s.sendChat('สวัสดีทุกคน');
    expect(media.sent.single.$2['text'], 'สวัสดีทุกคน');
    media.data0.add(('คุณบี', 'chat', {'type': 'chat', 'text': 'ครับ', 'name': 'คุณบี'}));
    await idle(5);
    expect([for (final m in s.chat.value) m.text], ['สวัสดีทุกคน', 'ครับ']);

    await s.toggleMic(); // mute → captions stop
    expect(s.transcribing, isFalse);
    expect(rt.emits.last.$1, 'minute:room_stt');
    expect(rt.emits.last.$2, {'ticket': 'T', 'on': false});
    await s.leave();
    expect(media.disconnected, isTrue);
  });

  test('helpers: consent text, initials, MinuteFinish body', () {
    expect(roomConsentText(transcribe: true, record: 'video'), contains('บันทึกภาพและเสียง'));
    expect(roomConsentText(transcribe: false, record: 'none'), '');
    expect(roomInitials('สมชาย ใจดี').length, 2);
    expect(const MinuteFinish(emailTo: ['a@x.com'], tasks: true).toStopBody(), {
      'summary_mode': 'now',
      'template': 'general',
      'features': {'summarize': true, 'translate': <String>[], 'email_to': ['a@x.com'], 'tasks': true},
    });
    expect(minuteClock(3725000), '1:02:05');
  });
}

class _FakeRealtime implements RealtimeService {
  final _ctrl = StreamController<RealtimeEvent>.broadcast();
  final acks = <(String, Map<String, dynamic>)>[];
  final emits = <(String, Map<String, dynamic>)>[];
  int roomAudio = 0;
  void push(String type, Map<String, dynamic> d) => _ctrl.add(RealtimeEvent(type, d));
  @override
  Stream<RealtimeEvent> get events => _ctrl.stream;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 10)}) async {
    acks.add((event, data));
    if (event == 'minute:room_join') return {'ok': true, 'captions': true, 'transcribe': true, 'langs': ['en']};
    return {'ok': true};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emits.add((event, data));
  @override
  void emitRoomAudio(Uint8List pcm) => roomAudio++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMedia extends RoomMedia {
  (String, String)? connectedWith;
  bool _mic = false;
  bool disconnected = false;
  final sent = <(String, Map<String, dynamic>)>[];
  final data0 = StreamController<(String, String, Map<String, dynamic>)>.broadcast();
  @override
  Future<void> connect(String url, String token, {required bool micOn, required bool camOn}) async {
    connectedWith = (url, token);
    _mic = micOn;
  }

  @override
  Future<void> disconnect() async => disconnected = true;
  @override
  Future<void> setMic(bool on) async => _mic = on;
  @override
  Future<void> setCamera(bool on) async {}
  @override
  Future<void> flipCamera() async {}
  @override
  Future<void> setScreenShare(bool on) async {}
  @override
  bool get micOn => _mic;
  @override
  bool get camOn => false;
  @override
  bool get screenOn => false;
  @override
  List<lk.Participant> get participants => const [];
  @override
  lk.Participant? get speaker => null;
  @override
  String? get localAudioTrackId => null;
  @override
  Future<void> sendData(Map<String, dynamic> data, {String topic = 'chat'}) async => sent.add((topic, data));
  @override
  Stream<(String, String, Map<String, dynamic>)> get data => data0.stream;
}

