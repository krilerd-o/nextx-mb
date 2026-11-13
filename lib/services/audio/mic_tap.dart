import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'pcm.dart';

/// Microphone → PCM16 mono 24 kHz in ~100 ms chunks.
///
/// In a call WebRTC keeps using the mic, so a native tap can replace the recorder on devices where
/// a second recorder is refused (see `call_mic_tap_native.dart`).
abstract class CallMicTap {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

/// Any microphone source (same contract as [CallMicTap]).
typedef MicTap = CallMicTap;

/// A microphone that can pause / resume without closing the stream (notebook recordings).
abstract class PausableMicTap implements CallMicTap {
  Future<void> pause();
  Future<void> resume();

  /// `true` when the system paused the recorder by itself (iOS: a phone call / Siri took the
  /// audio session), `false` when it let it go again. Never fires for our own [pause] / [resume].
  Stream<bool> get interruptions;
}

/// The `record` plugin as a microphone.
///
/// - Call mode (default): keeps WebRTC's audio session on iOS and uses the voice-communication
///   source on Android (echo cancelled against the call), as live captions always did.
/// - [RecordMicTap.standalone]: for recording a meeting on its own (no call). Manages its own audio
///   session on iOS (playAndRecord, Bluetooth allowed, default to the speaker) and pauses on
///   interruptions; Android uses the plain `mic` source with gain control, not voiceCommunication
///   (which is tuned for a handset at the ear and cuts people across the table).
class RecordMicTap implements PausableMicTap {
  RecordMicTap() : standalone = false;
  RecordMicTap.standalone() : standalone = true;

  final bool standalone;
  AudioRecorder? _rec;
  StreamSubscription<RecordState>? _stateSub;
  final _interruptions = StreamController<bool>.broadcast();
  bool _selfPaused = false;
  bool _systemPaused = false;

  @override
  Stream<bool> get interruptions => _interruptions.stream;

  RecordConfig get _config => standalone
      ? const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kPcmSampleRate,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic, manageBluetooth: false),
          iosConfig: IosRecordConfig(categoryOptions: [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
            IosAudioCategoryOption.allowBluetoothA2DP,
          ]),
          audioInterruption: AudioInterruptionMode.pause,
        )
      : const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kPcmSampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication, manageBluetooth: false),
        );

  @override
  Future<Stream<Uint8List>> start() async {
    final rec = AudioRecorder();
    _rec = rec;
    // Call mode: keep WebRTC's audio session (playAndRecord) — do not let the recorder change it.
    // Standalone: the recorder owns the session (category playAndRecord with the options above).
    if (Platform.isIOS) await rec.ios?.manageAudioSession(standalone);
    if (standalone) {
      _stateSub = rec.onStateChanged().listen((s) {
        if (s == RecordState.pause && !_selfPaused && !_systemPaused) {
          _systemPaused = true;
          _interruptions.add(true);
        } else if (s == RecordState.record && _systemPaused) {
          _systemPaused = false;
          _interruptions.add(false);
        }
      });
    }
    final raw = await rec.startStream(_config);
    return rechunk(raw, 4800);
  }

  @override
  Future<void> pause() async {
    _selfPaused = true;
    await _rec?.pause();
  }

  @override
  Future<void> resume() async {
    _selfPaused = false;
    _systemPaused = false;
    await _rec?.resume();
  }

  @override
  Future<void> stop() async {
    final rec = _rec;
    _rec = null;
    await _stateSub?.cancel();
    _stateSub = null;
    if (rec == null) return;
    try {
      await rec.stop();
    } catch (_) {}
    await rec.dispose();
  }
}
