import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a notebook recording alive with the screen off / the app in the background.
///
/// Android: a foreground service of type `microphone` (`NotebookRecordingService.kt`) with an
/// ongoing notification — elapsed time (a chronometer) and the actions หยุดชั่วคราว / อัดต่อ / จบ.
/// Taps on the actions come back on [actions] (`pause`, `resume`, `stop`, `open`).
/// iOS: background audio is on in Info.plist and the recorder owns the audio session, so nothing
/// native is needed; the calls are no-ops.
abstract class RecordingForeground {
  Future<void> start({required String title, required int elapsedMs});
  Future<void> update({required bool paused, required int elapsedMs, String? title});
  Future<void> stop();
  Stream<String> get actions;
}

class NativeRecordingForeground implements RecordingForeground {
  NativeRecordingForeground({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('nextx/notebook_recorder') {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) _actions.add(call.arguments as String);
      return null;
    });
  }

  final MethodChannel _ch;
  final _actions = StreamController<String>.broadcast();

  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  Stream<String> get actions => _actions.stream;

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[notebook-recorder] $method: $e');
    }
  }

  @override
  Future<void> start({required String title, required int elapsedMs}) => _call('start', {'title': title, 'elapsedMs': elapsedMs, 'labels': _labels});

  @override
  Future<void> update({required bool paused, required int elapsedMs, String? title}) => _call('update', {'paused': paused, 'elapsedMs': elapsedMs, 'title': ?title});

  @override
  Future<void> stop() => _call('stop');

  /// Notification texts (Thai; the service has no access to the app's i18n).
  static const _labels = {
    'channel': 'บันทึกเสียงในสมุดโน้ต',
    'recording': 'กำลังบันทึกเสียง',
    'paused': 'หยุดชั่วคราว',
    'pause': 'หยุดชั่วคราว',
    'resume': 'อัดต่อ',
    'stop': 'จบ',
  };
}

/// Tests / desktop: does nothing.
class NoopRecordingForeground implements RecordingForeground {
  final _actions = StreamController<String>.broadcast();
  final calls = <String>[];

  /// Simulates a tap on a notification action.
  void tap(String action) => _actions.add(action);

  @override
  Stream<String> get actions => _actions.stream;
  @override
  Future<void> start({required String title, required int elapsedMs}) async => calls.add('start');
  @override
  Future<void> update({required bool paused, required int elapsedMs, String? title}) async => calls.add(paused ? 'update:paused' : 'update:live');
  @override
  Future<void> stop() async => calls.add('stop');
}
