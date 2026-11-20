import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../calls/call_service.dart';
import '../minutes/minute_room_session.dart';
import 'ongoing_notification.dart';

/// Shows the running team call and meeting room in the device's notification bar (Android foreground
/// service with buttons, Picture-in-Picture for video) and reports meeting rooms to iOS CallKit so they
/// look like a call (green pill, lock screen). Recordings have their own notification
/// (`NativeRecordingForeground`).
class OngoingSessionsBinder {
  OngoingSessionsBinder({required this.notifier, this.call, this.leaveRoom, RoomCallKit? callKit})
      : _callKit = callKit ?? RoomCallKit.platform();

  static OngoingSessionsBinder? _instance;
  static OngoingSessionsBinder? get instance => _instance;

  /// App start-up (call_setup.dart).
  static OngoingSessionsBinder start({CallService? call, Future<void> Function(MinuteRoomSession room)? leaveRoom}) {
    _instance?.dispose();
    return _instance = OngoingSessionsBinder(notifier: NativeOngoingNotifier.shared, call: call, leaveRoom: leaveRoom)..bind();
  }

  final OngoingNotifier notifier;
  final CallService? call;

  /// Leave the room for real (server + media), from the notification's "ออกจากห้อง".
  final Future<void> Function(MinuteRoomSession room)? leaveRoom;

  /// Show the room / call screen (set by the overlay, which has the navigator).
  static void Function(MinuteRoomSession room)? openRoom;
  static VoidCallback? openCall;

  final RoomCallKit _callKit;
  RoomCallKit get callKit => _callKit;
  StreamSubscription<(String, String)>? _sub;
  MinuteRoomSession? _room;
  OngoingNotice? _callShown;
  OngoingNotice? _roomShown;
  bool _pipOn = false;

  void bind() {
    call?.addListener(_syncCall);
    MinuteRoomSession.active.addListener(_roomChanged);
    _sub = notifier.actions.listen(_onAction);
    _callKit.onToggleMute = (id) {
      final r = _room;
      if (r != null && id == _callKit.idFor(r)) unawaited(r.toggleMic());
    };
    _callKit.onEnded = (id) {
      final r = _room;
      if (r != null && !r.closed && id == _callKit.idFor(r)) unawaited(_leave(r));
    };
    _roomChanged();
    _syncCall();
  }

  void dispose() {
    call?.removeListener(_syncCall);
    MinuteRoomSession.active.removeListener(_roomChanged);
    _room?.removeListener(_syncRoom);
    _room?.media.removeListener(_syncRoom);
    _sub?.cancel();
    if (_instance == this) _instance = null;
  }

  // ── team call

  void _syncCall() {
    final c = call;
    final on = c != null && (c.phase == CallPhase.active || c.phase == CallPhase.outgoing);
    if (!on) {
      if (_callShown != null) {
        _callShown = null;
        unawaited(notifier.hide('call'));
      }
      _syncPip();
      return;
    }
    final n = OngoingNotice(
      kind: 'call',
      title: c.title.isEmpty ? 'สายที่กำลังคุย' : c.title,
      subtitle: c.phase == CallPhase.outgoing ? 'กำลังโทร…' : (c.isVideo ? 'วิดีโอคอล' : 'กำลังคุย'),
      micOn: !c.muted,
      video: c.isVideo,
      startedAt: c.startedAt,
    );
    if (n != _callShown) {
      _callShown = n;
      unawaited(notifier.show(n));
    }
    _syncPip();
  }

  // ── meeting room

  void _roomChanged() {
    final r = MinuteRoomSession.active.value;
    if (r == _room) return;
    final old = _room;
    if (old != null) {
      old.removeListener(_syncRoom);
      if (!old.disposed) old.media.removeListener(_syncRoom);
      _roomShown = null;
      unawaited(notifier.hide('room'));
      unawaited(_callKit.end(old));
    }
    _room = r;
    if (r != null) {
      r.addListener(_syncRoom);
      r.media.addListener(_syncRoom);
    }
    _syncRoom();
  }

  void _syncRoom() {
    final r = _room;
    if (r == null || r.closed || !r.connected) {
      if (_roomShown != null) {
        _roomShown = null;
        unawaited(notifier.hide('room'));
        if (r != null) unawaited(_callKit.end(r));
      }
      _syncPip();
      return;
    }
    final n = OngoingNotice(
      kind: 'room',
      title: r.title.isEmpty ? 'ห้องประชุม' : r.title,
      subtitle: '${r.media.participants.length} คน · ${r.roomCode}',
      micOn: r.media.micOn,
      video: r.media.camOn,
      startedAt: r.startedAt,
    );
    if (n != _roomShown) {
      final first = _roomShown == null;
      _roomShown = n;
      unawaited(notifier.show(n));
      if (first) unawaited(_callKit.start(r));
    }
    _syncPip();
  }

  /// PiP when leaving the app is offered only while a video call / room is on.
  void _syncPip() {
    final want = (_callShown?.video ?? false) || (_roomShown != null && _roomHasVideo());
    if (want == _pipOn) return;
    _pipOn = want;
    unawaited(notifier.setPip(enabled: want));
  }

  bool _roomHasVideo() {
    final r = _room;
    if (r == null) return false;
    return r.media.camOn || r.media.participants.any((p) => p.isCameraEnabled() || p.isScreenShareEnabled());
  }

  // ── buttons

  Future<void> _onAction((String, String) a) async {
    final (kind, action) = a;
    if (kind == 'call') {
      final c = call;
      if (c == null) return;
      switch (action) {
        case 'mute' || 'unmute':
          if ((action == 'mute') != c.muted) await c.toggleMute();
        case 'hangup':
          await c.hangUp();
        case 'open':
          c.setMinimized(false);
          openCall?.call();
      }
      return;
    }
    if (kind == 'room') {
      final r = _room;
      if (r == null || r.closed) return;
      switch (action) {
        case 'mute' || 'unmute':
          if ((action == 'mute') == r.media.micOn) await r.toggleMic();
        case 'hangup':
          await _leave(r);
        case 'open':
          openRoom?.call(r);
      }
    }
  }

  Future<void> _leave(MinuteRoomSession r) async {
    final l = leaveRoom;
    if (l != null) {
      await l(r);
    } else {
      await r.close();
    }
  }
}

/// iOS: a meeting room is reported to CallKit as an outgoing call (audio keeps going in the background,
/// the green call pill and the lock screen show it). Android: nothing (the notification does this).
class RoomCallKit {
  RoomCallKit({required this.enabled});
  factory RoomCallKit.platform() => RoomCallKit(enabled: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final bool enabled;
  final _ids = <MinuteRoomSession, String>{};
  void Function(String id)? onToggleMute;
  void Function(String id)? onEnded;
  StreamSubscription<CallEvent?>? _sub;

  /// CallKit wants a UUID per call.
  String idFor(MinuteRoomSession r) => _ids[r] ??= _uuidV4();

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Called by CallKitBridge for events it does not own (rooms). True when handled.
  bool handle(CallEvent? e) {
    switch (e) {
      case CallEventActionCallToggleMute(:final id) when _ids.containsValue(id):
        onToggleMute?.call(id);
        return true;
      case CallEventActionCallEnded(:final callKitParams) when _ids.containsValue(callKitParams.id):
        onEnded?.call(callKitParams.id);
        return true;
      default:
        return false;
    }
  }

  Future<void> start(MinuteRoomSession r) async {
    if (!enabled) return;
    final id = idFor(r);
    activeRoomCallIds.add(id);
    await FlutterCallkitIncoming.startCall(
      CallKitParams(
        id: id,
        nameCaller: r.title.isEmpty ? 'ห้องประชุม' : r.title,
        handle: r.roomCode,
        type: r.media.camOn ? 1 : 0,
        extra: {'kind': 'minute_room', 'room_code': r.roomCode},
        ios: const IOSParams(handleType: 'generic', supportsVideo: true, maximumCallGroups: 1, maximumCallsPerCallGroup: 1, configureAudioSession: false, supportsHolding: false, supportsDTMF: false),
      ),
    ).catchError((_) {});
    await FlutterCallkitIncoming.setCallConnected(id).catchError((_) {});
  }

  Future<void> end(MinuteRoomSession r) async {
    final id = _ids.remove(r);
    if (id == null) return;
    activeRoomCallIds.remove(id);
    if (!enabled) return;
    await FlutterCallkitIncoming.endCall(id).catchError((_) {});
  }

  void dispose() => _sub?.cancel();
}

/// CallKit ids that belong to meeting rooms (CallKitBridge leaves those to [RoomCallKit]).
final Set<String> activeRoomCallIds = {};
