import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nextx_mobile/services/audio/mic_tap.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/notebook/notebook_recorder.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

/// Socket of a notebook recording without a server.
class FakeNotebookTransport implements NotebookSttTransport {
  final ctrl = StreamController<RealtimeEvent>.broadcast();
  final online = ValueNotifier<bool>(true);
  final emitted = <(String, Map<String, dynamic>)>[];
  final audio = <(String, int)>[];
  Map<String, dynamic> startAck = {'ok': true};

  @override
  Stream<RealtimeEvent> get events => ctrl.stream;
  @override
  bool get connected => online.value;
  @override
  Listenable get connection => online;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async {
    emitted.add((event, data));
    if (!online.value) return {'ok': false, 'error': 'no_socket'};
    return event == 'stt:start' ? startAck : {'ok': true};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emitted.add((event, data));
  @override
  void sendAudio(String recordingId, Uint8List pcm) => audio.add((recordingId, pcm.length));

  void push(String type, Map<String, dynamic> data) => ctrl.add(RealtimeEvent(type, data));
  List<Map<String, dynamic>> sent(String event) => [for (final e in emitted) if (e.$1 == event) e.$2];
  List<String> get names => [for (final e in emitted) e.$1];
}

/// A microphone the test feeds by hand.
class FakePausableMic implements PausableMicTap {
  final ctrl = StreamController<Uint8List>();
  final _int = StreamController<bool>.broadcast();
  bool started = false;
  bool stopped = false;
  bool paused = false;
  bool failStart = false;
  final log = <String>[];

  @override
  Future<Stream<Uint8List>> start() async {
    if (failStart) throw StateError('no mic');
    started = true;
    log.add('start');
    return ctrl.stream;
  }

  @override
  Future<void> pause() async {
    paused = true;
    log.add('pause');
  }

  @override
  Future<void> resume() async {
    paused = false;
    log.add('resume');
  }

  @override
  Future<void> stop() async {
    stopped = true;
    log.add('stop');
    unawaited(ctrl.close()); // never listened when start failed: do not wait for "done"
  }

  @override
  Stream<bool> get interruptions => _int.stream;

  /// The system took the audio session (iOS phone call).
  void interrupt() => _int.add(true);

  /// [ms] of a loud-ish tone (PCM16 24 kHz).
  void feed(int ms, {int amplitude = 6000}) {
    final n = 24 * ms;
    final b = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      b.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
    }
    ctrl.add(b.buffer.asUint8List());
  }
}

/// A call service whose phase the test sets.
class TestCallService extends CallService {
  TestCallService() : super(signaling: _NoSignaling());

  void setPhase(CallPhase p, {bool minimized = false}) {
    phase = p;
    this.minimized = minimized;
    notifyListeners();
  }
}

class _NoSignaling implements CallSignaling {
  final _c = StreamController<RealtimeEvent>.broadcast();
  @override
  Stream<RealtimeEvent> get events => _c.stream;
  @override
  String? get socketId => 's1';
  @override
  bool get connected => true;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async => {'ok': false};
  @override
  void emit(String event, Map<String, dynamic> data) {}
}
