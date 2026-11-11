import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/services/calls/call_mic_tap_native.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart';

class _FakeTap implements CallMicTap {
  _FakeTap({this.fail = false, this.silent = false});
  final bool fail;
  final bool silent;
  bool started = false;
  bool stopped = false;
  final ctl = StreamController<Uint8List>();

  @override
  Future<Stream<Uint8List>> start() async {
    if (fail) throw StateError('nope');
    started = true;
    if (!silent) scheduleMicrotask(() => ctl.add(Uint8List(4800)));
    return ctl.stream;
  }

  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the WebRTC tap when it delivers audio', () async {
    final p = _FakeTap();
    final f = _FakeTap();
    final tap = FallbackMicTap(p, f, firstAudio: const Duration(milliseconds: 200));
    final s = await tap.start();
    expect(tap.active, same(p));
    expect(f.started, isFalse);
    final got = <int>[];
    final sub = s.listen((b) => got.add(b.length));
    p.ctl.add(Uint8List(4800));
    await Future<void>.delayed(Duration.zero);
    expect(got, isNotEmpty);
    await sub.cancel();
    await tap.stop();
    expect(p.stopped, isTrue);
  });

  test('falls back to the recorder when the tap cannot start', () async {
    final p = _FakeTap(fail: true);
    final f = _FakeTap();
    final tap = FallbackMicTap(p, f, firstAudio: const Duration(milliseconds: 200));
    await tap.start();
    expect(tap.active, same(f));
    expect(f.started, isTrue);
  });

  test('falls back when the tap stays silent', () async {
    final p = _FakeTap(silent: true);
    final f = _FakeTap();
    final tap = FallbackMicTap(p, f, firstAudio: const Duration(milliseconds: 100));
    await tap.start();
    expect(tap.active, same(f));
    expect(p.stopped, isTrue);
  });

  test('WebRtcMicTap starts the native tap with the local track id', () async {
    const method = MethodChannel('test/call_mic_tap');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(method, (c) async {
      calls.add(c);
      return true;
    });
    final tap = WebRtcMicTap(() => 'track-1', method: method, events: const EventChannel('test/call_mic_tap/pcm'));
    await tap.start();
    await tap.stop();
    expect(calls.map((c) => c.method), ['start', 'stop']);
    expect((calls.first.arguments as Map)['trackId'], 'track-1');
  });
}
