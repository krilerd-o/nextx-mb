import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech → text with the phone's own recogniser (Thai / English).
abstract class NxSpeech {
  Future<bool> start({required String localeId, required void Function(String text, bool done) onText, void Function()? onStop});
  Future<void> stop();
  bool get listening;

  static NxSpeech instance = _DeviceSpeech();
}

class _DeviceSpeech implements NxSpeech {
  final _stt = SpeechToText();
  bool _ready = false;
  void Function()? _onStop;

  @override
  bool get listening => _stt.isListening;

  @override
  Future<bool> start({required String localeId, required void Function(String text, bool done) onText, void Function()? onStop}) async {
    _onStop = onStop;
    try {
      _ready = _ready ||
          await _stt.initialize(
            onStatus: (s) {
              if (s == 'done' || s == 'notListening') _onStop?.call();
            },
            onError: (_) => _onStop?.call(),
          );
      if (!_ready) return false;
      await _stt.listen(
        localeId: localeId,
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation),
        onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
