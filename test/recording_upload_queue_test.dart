import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/api_exceptions.dart';
import 'package:nextx_mobile/services/calls/recording_upload_queue.dart';

class _Api extends ApiClient {
  final sent = <String>[];
  int failNext = 0;
  int failCode = 0;
  @override
  Future<Map<String, dynamic>> uploadCallRecordingPart(String callId, String filePath,
      {required int part, int parts = 0, bool isFinal = false, int durationMs = 0, String mime = 'audio/wav', String deviceId = ''}) async {
    if (failNext > 0) {
      failNext--;
      throw ApiException(failCode, 'x');
    }
    sent.add('$callId:$part${isFinal ? ' final/$parts' : ''}');
    return {'ok': true};
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('rq'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File part(String name) => File('${tmp.path}/$name')..writeAsBytesSync(List.filled(100, 1));

  test('uploads parts in order, final last, and deletes the files', () async {
    final api = _Api();
    final q = RecordingUploadQueue(dir: () async => tmp)..api = api;
    final a = part('a.wav'), b = part('b.wav');
    await q.add(RecordingPart(callId: 'c1', path: a.path, part: 0));
    await q.add(RecordingPart(callId: 'c1', path: b.path, part: 1, parts: 2, isFinal: true, durationMs: 9000));
    await q.pump();
    expect(api.sent, ['c1:0', 'c1:1 final/2']);
    expect(a.existsSync() || b.existsSync(), isFalse);
    expect(q.pending, isEmpty);
  });

  test('a network error keeps the part (and the queue survives a restart)', () async {
    final api = _Api()..failNext = 1..failCode = 0;
    final q = RecordingUploadQueue(dir: () async => tmp)..api = api;
    final a = part('a.wav');
    await q.add(RecordingPart(callId: 'c2', path: a.path, part: 0, parts: 1, isFinal: true));
    await q.pump();
    expect(api.sent, isEmpty);
    expect(q.pending.single.attempts, 1);
    // App restarted: a new queue reads the saved list and sends it.
    final api2 = _Api();
    final q2 = RecordingUploadQueue(dir: () async => tmp)..api = api2;
    await q2.pump();
    expect(api2.sent, ['c2:0 final/1']);
    q.dispose();
  });

  test('403 (recording turned off) drops the part', () async {
    final api = _Api()..failNext = 1..failCode = 403;
    final q = RecordingUploadQueue(dir: () async => tmp)..api = api;
    final a = part('a.wav');
    await q.add(RecordingPart(callId: 'c3', path: a.path, part: 0, parts: 1, isFinal: true));
    await q.pump();
    expect(q.pending, isEmpty);
    expect(a.existsSync(), isFalse);
  });
}
