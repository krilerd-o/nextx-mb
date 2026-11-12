import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'live_transcription.dart';

/// Reads the microphone audio WebRTC already captures (native `CallMicTap` in MainActivity /
/// AppDelegate), so captions never open a second recorder next to the call. PCM16 mono 24 kHz, 100 ms packets.
class WebRtcMicTap implements CallMicTap {
  WebRtcMicTap(this.trackId, {MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel('nextx/call_mic_tap'),
        _events = events ?? const EventChannel('nextx/call_mic_tap/pcm');

  /// The call's local audio track (Android looks the track up by id; iOS taps the capture pipeline).
  final String? Function() trackId;
  final MethodChannel _method;
  final EventChannel _events;
  bool _on = false;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<Stream<Uint8List>> start() async {
    final id = trackId();
    if (Platform.isAndroid && id == null) throw StateError('no_track');
    final stream = _events.receiveBroadcastStream().map((e) => e is Uint8List ? e : Uint8List.fromList(List<int>.from(e as List)));
    await _method.invokeMethod<bool>('start', {'trackId': id});
    _on = true;
    return stream;
  }

  @override
  Future<void> stop() async {
    if (!_on) return;
    _on = false;
    try {
      await _method.invokeMethod<bool>('stop');
    } catch (_) {}
  }
}

/// Tries [primary]; when it fails to start or sends no audio within [firstAudio], switches to [fallback].
class FallbackMicTap implements CallMicTap {
  FallbackMicTap(this.primary, this.fallback, {this.firstAudio = const Duration(milliseconds: 1500)});
  final CallMicTap primary;
  final CallMicTap fallback;
  final Duration firstAudio;
  CallMicTap? active;
  StreamSubscription<Uint8List>? _sub;
  StreamController<Uint8List>? _out;

  @override
  Future<Stream<Uint8List>> start() async {
    try {
      final src = await primary.start();
      final out = StreamController<Uint8List>();
      final first = Completer<bool>();
      _sub = src.listen(
        (b) {
          if (!first.isCompleted) first.complete(true);
          out.add(b);
        },
        onError: (Object e) {
          if (!first.isCompleted) first.complete(false);
        },
        onDone: () {
          if (!first.isCompleted) first.complete(false);
          out.close();
        },
      );
      if (await first.future.timeout(firstAudio, onTimeout: () => false)) {
        active = primary;
        _out = out;
        return out.stream;
      }
      await _sub?.cancel();
      _sub = null;
      unawaited(out.close());
    } catch (_) {}
    try {
      await primary.stop();
    } catch (_) {}
    active = fallback;
    return fallback.start();
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    unawaited(_out?.close());
    _out = null;
    final a = active;
    active = null;
    await a?.stop();
  }
}
