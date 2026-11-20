// Switching business must not move a running recording / upload, and another account never sends them.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/audio/pcm.dart';
import 'package:nextx_mobile/services/audio/recording_upload_queue.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart' show CommAiDevice;
import 'package:nextx_mobile/services/minutes/minute_recorder.dart';
import 'package:nextx_mobile/services/minutes/minute_uploader.dart';
import 'package:nextx_mobile/services/notebook/notebook_recorder.dart' show MicPermission, RecordStart;
import 'package:nextx_mobile/services/notebook/recording_foreground.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';
import 'support/recorder_fakes.dart';

class _T extends FakeNotebookTransport implements MinuteSttTransport {
  @override
  void sendMinuteAudio(String meetingId, Uint8List pcm) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FakeNextxAdapter http;
  late ApiClient api;
  late RecordingUploadQueue q;

  setUp(() {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'phone-1'});
    CommAiDevice.reset();
    tmp = Directory.systemTemp.createTempSync('bizsw');
    http = FakeNextxAdapter({
      'POST /api/ai/minutes': {'item': {'id': 55, 'title': 'x', 'status': 'live'}},
      'POST /api/ai/minutes/55/parts': {'received': true},
      'POST /api/ai/minutes/55/pause': {'status': 'paused'},
      'POST /api/ai/minutes/55/resume': {'status': 'live'},
      'POST /api/ai/minutes/55/stop': {'status': 'processing'},
    });
    api = ApiClient()..debugSetHttpAdapter(http);
    api.attachSession(baseUrl: 'https://x.test', accessToken: 't', userId: '2', businessId: '1');
    q = RecordingUploadQueue(dir: () async => tmp)..api = api;
  });

  tearDown(() {
    q.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String? bizOf(String path) => http.calls.lastWhere((c) => c.path == path).headers['X-Business-Id']?.toString();

  test('ApiClient.inBusiness pins X-Business-Id for everything inside it', () async {
    expect(api.effectiveBusinessId, '1');
    await ApiClient.inBusiness('7', () async {
      expect(api.effectiveBusinessId, '7');
      await api.pauseMinuteMeeting('55');
    });
    expect(bizOf('/api/ai/minutes/55/pause'), '7');
    await api.resumeMinuteMeeting('55');
    expect(bizOf('/api/ai/minutes/55/resume'), '1');
    await ApiClient.inBusiness(null, () => api.pauseMinuteMeeting('55'));
    expect(bizOf('/api/ai/minutes/55/pause'), '1');
  });

  test('recorder keeps its business through a switch; the next one uses the new business', () async {
    final mic = FakePausableMic();
    final r = MinuteRecorder(transport: _T(), mic: () => mic, queue: q, foreground: NoopRecordingForeground(), permission: () async => MicPermission.granted)
      ..partBytes = kPcmBytesPerSecond;
    r.bind(api: api, businessId: '1');
    expect(await r.start(title: 'x'), RecordStart.started);
    // The user switches business while recording.
    api.attachSession(baseUrl: 'https://x.test', accessToken: 't', userId: '2', businessId: '9');
    r.bind(api: api, businessId: '9');
    expect(r.businessId, '1');
    await r.pause();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bizOf('/api/ai/minutes/55/pause'), '1');
    await r.resume();
    mic.feed(1500);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await r.stop();
    for (var i = 0; i < 8; i++) {
      await q.pump();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(bizOf('/api/ai/minutes/55/stop'), '1', reason: 'queued stop goes to the meeting business');
    expect(http.calls.where((c) => c.path == '/api/ai/minutes/55/parts').every((c) => c.headers['X-Business-Id'] == '1'), isTrue);
    expect(r.businessId, '9', reason: 'idle again: follows the open business');
  });

  test('upload queue sends parts of the old business too (not stuck until switching back)', () async {
    q.start(api: api, businessId: '9');
    final f = File('${tmp.path}/p.pcm')..writeAsBytesSync(Uint8List(10));
    await q.add(RecordingPart.minute(meetingId: '55', clientSessionId: 'c1', part: 0, path: f.path, businessId: '1'));
    for (var i = 0; i < 4; i++) {
      await q.pump();
    }
    expect(q.pending, isEmpty);
    expect(bizOf('/api/ai/minutes/55/parts'), '1');
  });

  test('uploads: per user and per business', () async {
    final up = MinuteUploader(prefsKey: 'test.up2');
    up.jobs.addAll([
      MinuteUploadJob(uploadId: 'a', meetingId: '1', path: '/nope', filename: 'a', size: 1, partSize: 1, title: 'a', businessId: '1', userId: '2'),
      MinuteUploadJob(uploadId: 'b', meetingId: '2', path: '/nope', filename: 'b', size: 1, partSize: 1, title: 'b', businessId: '9', userId: '2'),
      MinuteUploadJob(uploadId: 'c', meetingId: '3', path: '/nope', filename: 'c', size: 1, partSize: 1, title: 'c', businessId: '1', userId: '3', state: 'paused'),
    ]);
    await up.bind(api, userId: '2');
    expect([for (final j in up.mine) j.uploadId], ['a', 'b']);
    expect([for (final j in up.forBusiness('1')) j.uploadId], ['a']);
    final back = MinuteUploadJob.fromJson(up.jobs.first.toJson());
    expect([back.businessId, back.userId], ['1', '2']);
    up.signOut();
    expect(up.api, isNull);
  });
}
