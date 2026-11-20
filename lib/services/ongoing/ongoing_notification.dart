import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One running call / meeting room shown in the device's notification bar like a music player:
/// title, status line, a running clock and buttons (mute ⇄ unmute, hang up / leave, open).
@immutable
class OngoingNotice {
  const OngoingNotice({required this.kind, required this.title, this.subtitle = '', this.micOn = true, this.video = false, this.startedAt});

  /// call | room
  final String kind;
  final String title;
  final String subtitle;
  final bool micOn;

  /// Camera in use (Android foreground service type camera; Picture-in-Picture when leaving the app).
  final bool video;
  final DateTime? startedAt;

  Map<String, Object?> toMap() => {
        'kind': kind,
        'title': title,
        'subtitle': subtitle,
        'micOn': micOn,
        'video': video,
        'startedAt': (startedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'labels': kind == 'call' ? callLabels : roomLabels,
      };

  @override
  bool operator ==(Object o) => o is OngoingNotice && o.kind == kind && o.title == title && o.subtitle == subtitle && o.micOn == micOn && o.video == video && o.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(kind, title, subtitle, micOn, video, startedAt);

  /// Notification texts (Thai; the service has no access to the app's i18n).
  static const callLabels = {'channel': 'สายที่กำลังคุย', 'muted': 'ไมค์ปิดอยู่', 'mute': 'ปิดไมค์', 'unmute': 'เปิดไมค์', 'hangup': 'วางสาย', 'open': 'เปิด'};
  static const roomLabels = {'channel': 'ห้องประชุม', 'muted': 'ไมค์ปิดอยู่', 'mute': 'ปิดไมค์', 'unmute': 'เปิดไมค์', 'hangup': 'ออกจากห้อง', 'open': 'กลับเข้าห้อง'};
}

/// Device side of [OngoingNotice] (Android: `NxOngoingService`; iOS: CallKit, see ongoing_binder.dart).
abstract class OngoingNotifier {
  Future<void> show(OngoingNotice n);
  Future<void> hide(String kind);

  /// Android Picture-in-Picture when the user leaves the app during a video call / room.
  Future<void> setPip({required bool enabled, double aspect = 9 / 16});

  /// Button taps: (kind, action) with action mute | unmute | hangup | open.
  Stream<(String, String)> get actions;

  /// The app is shown in a Picture-in-Picture window.
  ValueListenable<bool> get inPip;
}

class NativeOngoingNotifier implements OngoingNotifier {
  NativeOngoingNotifier({MethodChannel? channel, bool? android}) : _ch = channel ?? const MethodChannel('nextx/ongoing'), _android = android ?? (!kIsWeb && Platform.isAndroid) {
    _ch.setMethodCallHandler((call) async {
      final a = call.arguments;
      if (call.method == 'action' && a is Map) _actions.add(('${a['kind']}', '${a['action']}'));
      if (call.method == 'pip' && a is bool) _pip.value = a;
      return null;
    });
  }

  static OngoingNotifier? _shared;
  static OngoingNotifier get shared => _shared ??= NativeOngoingNotifier();
  @visibleForTesting
  static set shared(OngoingNotifier v) => _shared = v;

  final MethodChannel _ch;
  final bool _android;
  final _actions = StreamController<(String, String)>.broadcast();
  final _pip = ValueNotifier<bool>(false);

  @override
  Stream<(String, String)> get actions => _actions.stream;
  @override
  ValueListenable<bool> get inPip => _pip;

  Future<void> _call(String method, Object? args) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[ongoing] $method: $e');
    }
  }

  @override
  Future<void> show(OngoingNotice n) => _call('show', n.toMap());
  @override
  Future<void> hide(String kind) => _call('hide', {'kind': kind});
  @override
  Future<void> setPip({required bool enabled, double aspect = 9 / 16}) => _call('pip', {'enabled': enabled, 'aspect': aspect});
}

/// Tests / desktop.
class FakeOngoingNotifier implements OngoingNotifier {
  final shown = <OngoingNotice>[];
  final hidden = <String>[];
  final pip = <bool>[];
  final _actions = StreamController<(String, String)>.broadcast();
  final _pip = ValueNotifier<bool>(false);

  /// What the notification bar shows now (kind → notice).
  final current = <String, OngoingNotice>{};

  void tap(String kind, String action) => _actions.add((kind, action));
  void setInPip(bool v) => _pip.value = v;

  @override
  Stream<(String, String)> get actions => _actions.stream;
  @override
  ValueListenable<bool> get inPip => _pip;

  @override
  Future<void> show(OngoingNotice n) async {
    shown.add(n);
    current[n.kind] = n;
  }

  @override
  Future<void> hide(String kind) async {
    hidden.add(kind);
    current.remove(kind);
  }

  @override
  Future<void> setPip({required bool enabled, double aspect = 9 / 16}) async => pip.add(enabled);
}
