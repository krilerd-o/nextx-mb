import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../services/api_client.dart';

/// "อ่านออกเสียง": one answer at a time, read by the business's server TTS.
class AiSpeaker {
  AiSpeaker._();
  static final instance = AiSpeaker._();

  /// The answer being read (or loaded), null when quiet.
  final ValueNotifier<Object?> speaking = ValueNotifier(null);

  /// Tests replace playback (no audio plugin there).
  @visibleForTesting
  static Future<void> Function(Uint8List bytes)? debugPlay;

  AudioPlayer? _player;

  /// Reads [text] aloud for [key]; the same key again stops it.
  Future<void> toggle(ApiClient api, Object key, String text) async {
    if (speaking.value == key) return stop();
    await stop();
    speaking.value = key;
    try {
      final bytes = Uint8List.fromList(await api.aiSpeech(text));
      if (speaking.value != key) return;
      if (debugPlay != null) {
        await debugPlay!(bytes);
        return;
      }
      final p = _player ??= AudioPlayer(playerId: 'ai-speaker');
      p.onPlayerComplete.first.then((_) {
        if (speaking.value == key) speaking.value = null;
      });
      await p.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } catch (e) {
      if (speaking.value == key) speaking.value = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    speaking.value = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
