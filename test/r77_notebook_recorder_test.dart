// ISAAC Notebook recordings (phase 2): recorder engine, upload queue targets, call conflicts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/notebook/notebook_recording.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/audio/pcm.dart';
import 'package:nextx_mobile/services/audio/recording_upload_queue.dart';
import 'package:nextx_mobile/services/audio/wav_parts.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart' show CommAiDevice;
import 'package:nextx_mobile/services/notebook/notebook_recorder.dart';
import 'package:nextx_mobile/services/notebook/recording_foreground.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';
import 'support/recorder_fakes.dart';

const _rec = 'POST /api/ai/notebooks/3/recordings';
const _parts = 'POST /api/ai/notebooks/3/recordings/77/parts';
const _stop = 'POST /api/ai/notebooks/3/recordings/77/stop';

Map<String, Object?> _replies() => {
      _rec: {'item': {'id': 77, 'notebook_id': 3, 'title': 'ประชุมทีม', 'status': 'recording', 'started_at': '2026-11-13T10:00:00Z', 'locale': 'th'}},
      _parts: {'received': true},
      'POST /api/ai/notebooks/3/recordings/77/pause': {'status': 'paused'},
      'POST /api/ai/notebooks/3/recordings/77/resume': {'status': 'recording'},
      _stop: {'status': 'processing'},
      'DELETE /api/ai/notebooks/3/recordings/77': {'ok': true},
    };

Map<String, dynamic> _json(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});
Map<String, String> _fields(RequestOptions o) => {for (final e in (o.data as FormData).fields) e.key: e.value};

void main() {
  late Directory tmp;
  late FakeNotebookTransport t;
  late FakePausableMic mic;
  late NoopRecordingForeground fg;
  late FakeNextxAdapter http;
  late ApiClient api;
  late RecordingUploadQueue q;
  late NotebookRecorder r;
  late DateTime now;
  var perm = MicPermission.granted;

  setUp(() {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'app-phone-9'});
    CommAiDevice.reset();
    tmp = Directory.systemTemp.createTempSync('nbrec');
    t = FakeNotebookTransport();
    mic = FakePausableMic();
    fg = NoopRecordingForeground();
    http = FakeNextxAdapter(_replies());
    api = ApiClient()..debugSetHttpAdapter(http);
    q = RecordingUploadQueue(dir: () async => tmp)..api = api;
    now = DateTime(2026, 11, 13, 10);
    perm = MicPermission.granted;
    r = NotebookRecorder(transport: t, mic: () => mic, queue: q, foreground: fg, now: () => now, permission: () async => perm)
      ..api = api
      ..businessId = '1'
      ..resumeDelay = const Duration(milliseconds: 5)
      ..partBytes = kPcmBytesPerSecond; // 1 s parts
  });

  tearDown(() {
    q.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> idle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> drain() async {
    for (var i = 0; i < 6; i++) {
      await q.pump();
      await idle(10);
    }
  }

  test('start: creates the recording, stt:start (notebook), live audio keyed by recording', () async {
    expect(await r.start(notebookId: '3', notebookTitle: 'ทีมขาย', title: 'ประชุมทีม'), RecordStart.started);
    final body = _json(http.calls.firstWhere((c) => c.path.endsWith('/recordings')));
    expect(body['title'], 'ประชุมทีม');
    expect(body['device_id'], 'app-phone-9');
    expect('${body['client_session_id']}', startsWith('nbrec-'));
    expect(r.recordingId, '77');
    final st = t.sent('stt:start').single;
    expect(st['session_kind'], 'notebook');
    expect(st['notebook_id'], 3);
    expect(st['recording_id'], 77);
    expect(st['business_id'], 1);
    expect(st['device_id'], 'app-phone-9');
    expect(st['locale'], 'th');
    expect(st['offset_ms'], 0, reason: 'the server audio clock starts where the WAV starts');
    expect(r.live, LiveState.live);
    expect(fg.calls, contains('start'));

    mic.feed(100);
    await idle();
    expect(t.audio.single, ('77', 4800));
    expect(r.levels.value.single, greaterThan(0.5));

    // Partial → final for the same seq; other recordings / calls are ignored.
    t.push('stt:segment', {'recording_id': 77, 'seq': 1, 'text': 'สวัสดี', 'partial': true, 'start_ms': 0, 'end_ms': 900});
    t.push('stt:segment', {'recording_id': 12, 'seq': 1, 'text': 'อื่น', 'partial': false});
    await idle(5);
    expect(r.segments.value.single.partial, isTrue);
    t.push('stt:segment', {'recording_id': 77, 'seq': 1, 'text': 'สวัสดีครับทุกคน', 'partial': false, 'start_ms': 0, 'end_ms': 1500});
    t.push('stt:segment', {'recording_id': 77, 'seq': 1, 'text': 'สวัส', 'partial': true}); // late partial
    t.push('stt:segment', {'recording_id': 77, 'seq': 2, 'text': 'เริ่มกันเลย', 'partial': false, 'start_ms': 1600, 'end_ms': 2600});
    await idle(5);
    expect([for (final s in r.segments.value) s.text], ['สวัสดีครับทุกคน', 'เริ่มกันเลย']);
    expect(r.segments.value.every((s) => !s.partial), isTrue);

    t.push('stt:state', {'recording_id': 77, 'state': 'reconnecting'});
    await idle(5);
    expect(r.live, LiveState.reconnecting);
    await r.stop();
  });

  test('pause / resume: elapsed excludes paused time; server + socket + mic all follow', () async {
    await r.start(notebookId: '3');
    now = now.add(const Duration(seconds: 10));
    expect(r.elapsed, const Duration(seconds: 10));
    await r.pause();
    await idle();
    expect(r.phase, RecorderPhase.paused);
    expect(mic.paused, isTrue);
    expect(t.sent('stt:pause').single, {'recording_id': 77});
    expect(http.callKeys, contains('POST /api/ai/notebooks/3/recordings/77/pause'));
    expect(fg.calls.last, 'update:paused');

    now = now.add(const Duration(seconds: 30)); // paused: not counted
    expect(r.elapsed, const Duration(seconds: 10));
    mic.feed(100); // a late packet while paused is neither sent nor recorded
    await idle();
    expect(t.audio, isEmpty);

    expect(await r.resume(), isTrue);
    await idle();
    expect(mic.paused, isFalse);
    expect(t.sent('stt:resume').single, {'recording_id': 77, 'offset_ms': 0});
    expect(http.callKeys, contains('POST /api/ai/notebooks/3/recordings/77/resume'));
    now = now.add(const Duration(seconds: 5));
    expect(r.elapsed, const Duration(seconds: 15));
    expect(fg.calls.last, 'update:live');

    // The notification's buttons drive the same actions.
    fg.tap('pause');
    await idle();
    expect(r.paused, isTrue);
    fg.tap('resume');
    await idle();
    expect(r.recording, isTrue);
    await r.stop();
  });

  test('stop: final part, then stop {duration_ms, bookmarks}; stt:stop; finished', () async {
    await r.start(notebookId: '3');
    final finished = r.finished.first;
    mic.feed(1000); // exactly one 1 s part
    mic.feed(500);
    await idle();
    now = now.add(const Duration(milliseconds: 700));
    final b = r.addBookmark('ราคา');
    expect(b.atMs, 700);
    await r.stop();
    expect(r.phase, RecorderPhase.idle);
    expect(mic.stopped, isTrue);
    expect(t.names, contains('stt:stop'));
    expect(fg.calls.last, 'stop');
    final f = await finished;
    expect(f.recordingId, '77');
    await drain();
    final keys = http.callKeys.where((k) => k == _parts || k == _stop).toList();
    expect(keys, [_parts, _parts, _stop], reason: 'parts in order, the stop after the final part');
    final partCalls = http.calls.where((c) => '${c.method} ${c.path}' == _parts).toList();
    expect([for (final c in partCalls) _fields(c)['part']], ['0', '1']);
    expect([for (final c in partCalls) _fields(c)['final']], ['false', 'true']);
    expect(_fields(partCalls.last)['duration_ms'], '1500');
    expect(_fields(partCalls.last)['device_id'], 'app-phone-9');
    final stop = _json(http.calls.lastWhere((c) => '${c.method} ${c.path}' == _stop));
    expect(stop['duration_ms'], 1500);
    expect(stop['parts'], 2, reason: 'the server waits for every part');
    expect(stop['bookmarks'], [
      {'at_ms': 700, 'label': 'ราคา'},
    ]);
    expect(q.pending, isEmpty);
    expect(tmp.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.wav')), isEmpty, reason: 'sent parts are deleted');
  });

  test('offline mid-recording: keeps recording, parts wait in order and go when back online', () async {
    await r.start(notebookId: '3');
    http.offline.addAll({_parts, _stop});
    t.online.value = false;
    await idle(5);
    expect(r.live, LiveState.offline);
    expect(r.notice.value, NotebookRecorder.offlineNotice);
    mic.feed(1000);
    mic.feed(1000);
    mic.feed(300);
    await idle();
    expect(t.audio.length, 0, reason: 'nothing live while offline');
    await r.stop();
    await drain();
    expect(q.pending.map((p) => '${p.op.name}:${p.part}${p.isFinal ? 'F' : ''}'), ['part:0', 'part:1', 'part:2F', 'stop:0F']);
    expect(q.pending.first.attempts, greaterThan(0));

    // Back online.
    http.offline.clear();
    await drain();
    final sent = [
      for (final c in http.calls)
        if ('${c.method} ${c.path}' == _parts) 'part ${_fields(c)['part']}' else if ('${c.method} ${c.path}' == _stop) 'stop',
    ];
    // Each part was tried once while offline (the first failure blocks the rest), then all in order.
    expect(sent.sublist(sent.length - 4), ['part 0', 'part 1', 'part 2', 'stop']);
    expect(q.pending, isEmpty);
  });

  test('starting offline: create is queued first (idempotent), parts wait for its id, captions start after', () async {
    http.offline.add(_rec);
    t.online.value = false;
    expect(await r.start(notebookId: '3', title: 'ห้องประชุมชั้น 3'), RecordStart.started);
    expect(r.recordingId, isNull);
    expect(r.live, LiveState.offline);
    mic.feed(1000);
    mic.feed(200);
    await idle();
    expect(q.pending.first.op, RecordingOp.create);
    final csid = r.clientSessionId!;

    // Network back: the queue creates the recording, then sends the parts with its id.
    http.offline.clear();
    t.online.value = true;
    await drain();
    expect(r.recordingId, '77');
    expect(t.sent('stt:start').single['resume'], isTrue);
    expect(t.sent('stt:start').single['offset_ms'], greaterThan(0), reason: 'audio recorded offline comes first on the clock');
    final create = _json(http.calls.lastWhere((c) => '${c.method} ${c.path}' == _rec));
    expect(create['client_session_id'], csid);
    expect(http.callKeys.where((k) => k == _parts).length, 1, reason: 'the first rolled part went with the new id');
    await r.stop();
    await drain();
    expect(http.callKeys.where((k) => k == _parts).length, 2);
    expect(http.callKeys.last, _stop);
  });

  test('reconnect: stt:start again with resume; a paused recording is paused again live', () async {
    await r.start(notebookId: '3');
    await r.pause();
    t.online.value = false;
    await idle(5);
    expect(r.live, LiveState.offline);
    t.online.value = true;
    t.push(RealtimeService.connectedEvent, const {});
    await idle(40);
    expect(t.sent('stt:start').length, 2);
    expect(t.sent('stt:start').last['resume'], isTrue);
    expect(t.sent('stt:pause').length, 2);
    expect(r.live, LiveState.paused);
    await r.stop();
  });

  test('live transcription refused by the server: still records (transcribed from the file)', () async {
    t.startAck = {'ok': false, 'error': 'stt_not_configured'};
    expect(await r.start(notebookId: '3'), RecordStart.started);
    expect(r.live, LiveState.unavailable);
    expect(r.notice.value, NotebookRecorder.offlineNotice);
    mic.feed(100);
    await idle();
    expect(t.audio, isEmpty);
    await r.stop();
    await drain();
    expect(http.callKeys.last, _stop);
  });

  test('one recording app-wide; a call pauses it; no resume / start during a call', () async {
    final call = TestCallService();
    r.attachCall(call);
    await r.start(notebookId: '3');
    expect(await r.start(notebookId: '4'), RecordStart.busy);
    call.setPhase(CallPhase.active);
    await idle();
    expect(r.paused, isTrue);
    expect(mic.paused, isTrue);
    expect(r.notice.value, NotebookRecorder.callNotice);
    expect(await r.resume(), isFalse, reason: 'still in the call');
    expect(r.notice.value, NotebookRecorder.inCallText);
    call.setPhase(CallPhase.idle);
    expect(await r.resume(), isTrue);
    await r.stop();
    call.setPhase(CallPhase.outgoing);
    expect(await r.start(notebookId: '3'), RecordStart.inCall);
    expect(mic.log.where((l) => l == 'start').length, 1);
    call.dispose();
  });

  test('system interruption (iOS call) auto-pauses', () async {
    await r.start(notebookId: '3');
    mic.interrupt();
    await idle();
    expect(r.paused, isTrue);
    expect(r.notice.value, NotebookRecorder.interruptNotice);
    await r.stop();
  });

  test('permission denied / older server / mic failure', () async {
    perm = MicPermission.permanentlyDenied;
    expect(await r.start(notebookId: '3'), RecordStart.permanentlyDenied);
    perm = MicPermission.denied;
    expect(await r.start(notebookId: '3'), RecordStart.denied);
    expect(http.calls, isEmpty, reason: 'nothing created without the mic');
    perm = MicPermission.granted;

    final old = FakeNextxAdapter({}); // no /recordings: 404
    api.debugSetHttpAdapter(old);
    expect(await r.start(notebookId: '3'), RecordStart.unsupported);
    expect(r.phase, RecorderPhase.idle);
    expect(mic.started, isFalse);

    api.debugSetHttpAdapter(http);
    mic.failStart = true;
    expect(await r.start(notebookId: '3'), RecordStart.failed);
    expect(r.phase, RecorderPhase.idle);
    await idle();
    expect(http.callKeys, contains('DELETE /api/ai/notebooks/3/recordings/77'), reason: 'the empty recording is removed');
  });

  test('ready event is exposed for the app toast', () async {
    t.push('ai:notebook_recording_ready', {'notebook_id': 3, 'recording_id': 77, 'source_id': 40, 'note_id': 41, 'title': 'ประชุมทีม'});
    await idle(5);
    expect(r.ready.value?['note_id'], 41);
  });

  group('upload queue targets', () {
    test('old queue entries (call parts, no target) still read and upload as call parts', () async {
      final calls = <String>[];
      final saved = RecordingUploadQueue.senders[RecordingTarget.call]!;
      RecordingUploadQueue.senders[RecordingTarget.call] = (api, p) async {
        calls.add('call ${p.callId}:${p.part}${p.isFinal ? ' final/${p.parts}' : ''}');
        return null;
      };
      addTearDown(() => RecordingUploadQueue.senders[RecordingTarget.call] = saved);
      final dir = Directory('${tmp.path}/comm_ai_recordings')..createSync(recursive: true);
      final a = File('${dir.path}/old.wav')..writeAsBytesSync(List.filled(80, 1));
      final b = File('${dir.path}/nb.wav')..writeAsBytesSync(List.filled(80, 1));
      // queue.json as written by the previous version (call parts only) + a notebook part from this one.
      File('${dir.path}/queue.json').writeAsStringSync(jsonEncode([
        {'call_id': 'c9', 'path': a.path, 'part': 0, 'parts': 1, 'final': true, 'duration_ms': 4000, 'device_id': '', 'mime': 'audio/wav', 'attempts': 2, 'created_at': DateTime.now().toIso8601String()},
        RecordingPart.notebook(notebookId: '3', recordingId: '77', clientSessionId: 'nbrec-x', path: b.path, part: 0, isFinal: true, parts: 1, durationMs: 2000, createdAt: DateTime.now()).toJson(),
        {'target': 'hologram', 'path': '/x'}, // from a future version: skipped
      ]));
      final q2 = RecordingUploadQueue(dir: () async => tmp)..api = api;
      await q2.load();
      expect(q2.pending.map((p) => p.target), [RecordingTarget.call, RecordingTarget.notebook]);
      expect(q2.pending.first.attempts, 2);
      await q2.pump();
      expect(calls, ['call c9:0 final/1']);
      expect(http.callKeys, [_parts]);
      expect(_fields(http.calls.single)['final'], 'true');
      expect(q2.pending, isEmpty);
      q2.dispose();
    });

    test('notebook entries round-trip through JSON (create / part / stop)', () {
      const c = RecordingPart.notebookCreate(notebookId: '3', clientSessionId: 's1', title: 'ก', locale: 'th', deviceId: 'd');
      const p = RecordingPart.notebook(notebookId: '3', recordingId: '', clientSessionId: 's1', path: '/a.wav', part: 2);
      const s = RecordingPart.notebookStop(notebookId: '3', recordingId: '77', clientSessionId: 's1', durationMs: 9000, bookmarks: [
        {'at_ms': 10},
      ]);
      for (final x in [c, p, s]) {
        final back = RecordingPart.fromJson(jsonDecode(jsonEncode(x.toJson())))!;
        expect(back.target, RecordingTarget.notebook);
        expect(back.op, x.op);
        expect(back.group, 'nb:s1');
        expect(back.notebookId, '3');
      }
      expect(RecordingPart.fromJson(jsonDecode(jsonEncode(s.toJson())))!.bookmarks, [
        {'at_ms': 10},
      ]);
      expect(RecordingPart.fromJson(jsonDecode(jsonEncode(c.toJson())))!.title, 'ก');
      expect(RecordingPart.fromJson({'call_id': 'x', 'path': '/p'})!.target, RecordingTarget.call);
      expect(RecordingPart.fromJson({'target': 'notebook', 'path': '/p'}), isNull, reason: 'no notebook id');
    });

    test('a create refused for good (404) drops its parts', () async {
      final dropped = <String>[];
      q.dropped.listen((p) => dropped.add(p.op.name));
      final f = File('${tmp.path}/p.wav')..writeAsBytesSync(List.filled(80, 1));
      api.debugSetHttpAdapter(FakeNextxAdapter({}));
      await q.add(const RecordingPart.notebookCreate(notebookId: '3', clientSessionId: 's2'));
      await q.add(RecordingPart.notebook(notebookId: '3', recordingId: '', clientSessionId: 's2', path: f.path, part: 0, isFinal: true));
      await drain();
      expect(q.pending, isEmpty);
      expect(dropped, ['create', 'part']);
      expect(f.existsSync(), isFalse);
    });
  });

  group('engine', () {
    test('WAV parts: ordered, valid headers, tiny closing part after a roll-over', () async {
      final got = <WavPart>[];
      final w = WavPartWriter(tmp, prefix: 'x', partBytes: 9600, minTotalBytes: 0, onPart: (p) async => got.add(p));
      w.add(Uint8List(9600)); // rolls exactly
      await idle(20);
      await w.close();
      expect([for (final p in got) (p.part, p.isFinal, p.parts)], [(0, false, 0), (1, true, 2)]);
      final h = File(got.first.path).readAsBytesSync().sublist(0, 44);
      expect(String.fromCharCodes(h.sublist(0, 4)), 'RIFF');
      expect(ByteData.sublistView(Uint8List.fromList(h)).getUint32(40, Endian.little), 9600);
      expect(got.last.durationMs, 300);
    });

    test('call tapes still drop a recording under 1 s', () async {
      final got = <WavPart>[];
      final w = WavPartWriter(tmp, prefix: 'call-c1', onPart: (p) async => got.add(p));
      w.add(Uint8List(4800));
      await w.close();
      expect(got, isEmpty);
    });

    test('levels, clock, default title, summary detection, deep links', () {
      expect(pcmLevel(Uint8List(4800)), 0);
      expect(recordingClock(65000), '01:05');
      expect(recordingClock(3725000), '1:02:05');
      expect(defaultRecordingTitle(DateTime(2026, 11, 13, 9, 5)), 'บันทึกเสียง 13 พ.ย. 09:05');
      expect(meetingSummaryOf(meta: {'summary': {'key_points': ['a']}}, content: ''), isNotNull);
      expect(meetingSummaryOf(meta: const {}, content: '```json\n{"headline":"x","action_items":[]}\n```')?['headline'], 'x');
      expect(meetingSummaryOf(meta: const {}, content: '# สรุป\n- ข้อ 1'), isNull);
      expect(notificationDeepLink('/ai/notebook/3?recording_id=77'), '/notebook/3?recording=77');
      expect(notificationDeepLink('/ai/notebook/3', linkId: '77', extra: 'notebook_recording'), '/notebook/3?recording=77');
      // What NEXTX sends: link_id = notebook, link_extra = recording.
      expect(notificationDeepLinkFromData({'link_path': '/ai/notebook/3', 'link_id': '3', 'link_extra': '16'}), '/notebook/3?recording=16');
      expect(notificationDeepLink('/ai/notebook/3'), '/notebook/3');
      expect(RealtimeService.forwardedEvents, containsAll(['stt:segment', 'stt:state', 'ai:notebook_recording_ready']));
      final args = notebookAudioArgs('77', Uint8List(4)) as Map;
      expect(args['recording_id'], 77);
      expect(args['pcm'], isA<Uint8List>());
      // socket_io_client sends a binary's whole `.buffer`: a frame cut out of a bigger chunk goes as a copy.
      final chunk = Uint8List.fromList(List.generate(9600, (i) => i % 251));
      final frame = (notebookAudioArgs('77', Uint8List.sublistView(chunk, 4800, 9600)) as Map)['pcm'] as Uint8List;
      expect(frame.buffer.lengthInBytes, 4800);
      expect(frame.first, 4800 % 251);
      final own = Uint8List(4800);
      expect(identical(socketBytes(own), own), isTrue, reason: 'no copy when it already is its own buffer');
    });
  });
}
