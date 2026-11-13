// Manual live check (demo backend on :4000, NEXTX notebook recordings): the app's API client lists the
// recordings of notebook 3, opens one with its transcript, downloads its audio and opens its summary note.
// With PCM_WAV=<24 kHz mono WAV> it also runs a live-caption session over the socket exactly as the app
// sends it (stt:start ack, `stt:audio ({recording_id, pcm})` frames, stt:pause / resume / stop) and then
// deletes that recording again (needs the server's realtime STT, e.g. the fake OpenAI of the demo box).
//   QA_TOKEN_FILE=… [NB=3] [PCM_WAV=…] flutter test test_live/r77_notebook_recording_live_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/notebook/notebook_models.dart';
import 'package:nextx_mobile/core/notebook/notebook_recording.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/realtime_service.dart' show notebookAudioArgs;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _base = 'http://127.0.0.1:4000';

void main() {
  final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
  final nb = Platform.environment['NB'] ?? '3';

  test('notebook recordings against the live server', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = null;
    final config = AppConfig();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    config.debugOverrideSession(SessionState(accessToken: token, userId: '1', businessId: '1', menusLoaded: true, menuKeys: const ['ai-assistant']));
    await config.setApiBaseUrl(_base);
    final api = config.apiClient;

    // 1. list
    final rows = await api.getNotebookRecordings(nb);
    final list = [for (final r in rows) NotebookRecording.fromJson(r)];
    final ready = list.where((r) => r.status == RecordingStatus.ready && r.noteId != null).toList();
    // ignore: avoid_print
    print('recordings: ${[for (final r in list) '${r.id}:${r.status.name}:src=${r.sourceId}:note=${r.noteId}']}');
    expect(ready, isNotEmpty);

    // 2. one recording + transcript
    final rec = NotebookRecording.fromJson(await api.getNotebookRecording(nb, ready.first.id));
    expect(rec.segments, isNotEmpty);
    expect(rec.durationMs, greaterThan(0));
    // ignore: avoid_print
    print('recording ${rec.id} "${rec.title}" ${recordingClock(rec.durationMs)} segments=${rec.segments.length} bookmarks=${rec.bookmarks.length} '
        'first="${rec.segments.first.text}" @${recordingClock(rec.segments.first.startMs)}');

    // 3. audio bytes (the player's source)
    final bytes = await api.downloadNotebookRecordingAudio(nb, rec.id);
    expect(bytes.length, greaterThan(1000));
    final head = String.fromCharCodes(bytes.sublist(4, 8));
    // ignore: avoid_print
    print('audio ${bytes.length} bytes, box "$head"');

    // 4. the notebook: the recording is a source (config → recording id) and the summary note is structured
    final detail = await api.getNotebook(nb);
    final sources = [for (final s in (detail['sources'] as List? ?? const [])) NotebookSource.fromJson(Map<String, dynamic>.from(s as Map))];
    final src = sources.firstWhere((s) => s.id == rec.sourceId);
    expect(src.kind, 'recording');
    expect('${src.config['recording_id']}', rec.id);
    expect(src.config['audio_path'], '/api/ai/notebooks/$nb/recordings/${rec.id}/audio');
    final notes = [for (final n in (detail['notes'] as List? ?? const [])) NotebookNote.fromJson(Map<String, dynamic>.from(n as Map))];
    final note = notes.firstWhere((n) => n.id == rec.noteId);
    expect(note.kind, 'meeting_summary');
    expect(note.studio, StudioKind.meetingSummary);
    final summary = meetingSummaryOf(meta: note.meta, content: note.content);
    expect(summary, isNotNull);
    expect(summary!['key_points'], isA<List>());
    // ignore: avoid_print
    print('note ${note.id} "${note.title}" headline="${summary['headline']}" key_points=${(summary['key_points'] as List).length} '
        'actions=${(summary['action_items'] as List? ?? const []).length} meta.recording_id=${note.meta['recording_id']}');
  });

  test('live captions over the socket in the app packet format', () async {
    final wav = Platform.environment['PCM_WAV'];
    if (wav == null) return;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = null;
    final config = AppConfig();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    config.debugOverrideSession(SessionState(accessToken: token, userId: '1', businessId: '1', menusLoaded: true, menuKeys: const ['ai-assistant']));
    await config.setApiBaseUrl(_base);
    final api = config.apiClient;
    final item = await api.createNotebookRecording(nb, title: 'ทดสอบ socket จากแอป', locale: 'th', deviceId: 'app-smoke', clientSessionId: 'nbrec-smoke-${DateTime.now().millisecondsSinceEpoch}');
    final rid = '${item['id']}';
    final socket = io.io(_base, io.OptionBuilder().setPath('/api/socket.io').setTransports(['websocket']).setAuth({'token': token}).disableAutoConnect().build());
    final connected = Completer<void>();
    socket.onConnect((_) => connected.isCompleted ? null : connected.complete());
    final segments = <Map<String, dynamic>>[];
    final states = <String>[];
    socket.on('stt:segment', (d) => segments.add(Map<String, dynamic>.from(d as Map)));
    socket.on('stt:state', (d) => states.add('${(d as Map)['state']}${d['reason'] != null ? ':${d['reason']}' : ''}'));
    socket.connect();
    await connected.future.timeout(const Duration(seconds: 10));
    Future<Map<String, dynamic>> ack(String ev, Map<String, dynamic> body) {
      final c = Completer<Map<String, dynamic>>();
      socket.emitWithAck(ev, body, ack: (d) => c.complete(Map<String, dynamic>.from(d as Map)));
      return c.future.timeout(const Duration(seconds: 10));
    }

    try {
      final start = await ack('stt:start', {'session_kind': 'notebook', 'notebook_id': int.parse(nb), 'recording_id': int.parse(rid), 'business_id': 1, 'device_id': 'app-smoke', 'locale': 'th', 'offset_ms': 0});
      // ignore: avoid_print
      print('stt:start ack $start');
      expect(start['ok'], isTrue);
      expect(start['state'], 'live');
      expect(start['sample_rate'], 24000);
      final pcm = File(wav).readAsBytesSync().sublist(44);
      var off = 0;
      Future<void> send(int frames) async {
        for (var i = 0; i < frames && off + 4800 <= pcm.length; i++) {
          // A view into the file, like the app's `rechunk` frames (notebookAudioArgs sends it as its own buffer).
          socket.emit('stt:audio', notebookAudioArgs(rid, Uint8List.sublistView(pcm, off, off + 4800)));
          off += 4800;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      }

      await send(95);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final pause = await ack('stt:pause', {'recording_id': int.parse(rid)});
      final resume = await ack('stt:resume', {'recording_id': int.parse(rid), 'offset_ms': off ~/ 48});
      await send(15);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final stop = await ack('stt:stop', {'recording_id': int.parse(rid)});
      // ignore: avoid_print
      print('pause $pause / resume $resume / stop $stop\nstates $states');
      for (final s in segments) {
        // ignore: avoid_print
        print('segment seq=${s['seq']} partial=${s['partial']} ${s['start_ms']}–${s['end_ms']} "${s['text']}"');
      }
      expect(pause['state'], 'paused');
      expect(resume['ok'], isTrue);
      expect(segments.where((s) => s['partial'] == false && '${s['recording_id']}' == rid), isNotEmpty, reason: 'the server heard the app-format frames');
    } finally {
      socket.dispose();
      await api.deleteNotebookRecording(nb, rid);
    }
  });
}
