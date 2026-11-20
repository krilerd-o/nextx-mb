import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../services/calls/call_service.dart';
import '../../services/minutes/minute_recorder.dart';
import '../../services/minutes/minute_room_session.dart';
import '../../services/notebook/notebook_recorder.dart';
import '../../services/ongoing/ongoing_binder.dart';
import '../../services/ongoing/ongoing_notification.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_ongoing_bubble.dart';
import '../minutes/minute_record_flow.dart';
import '../minutes/minute_room_screen.dart';

/// Floating bubbles over the whole app for what keeps running when its screen is closed — a meeting room
/// and an AI Minute recording (the call and the notebook recording have their own overlays). One bubble
/// at a time: call > room > meeting recording > notebook recording. Dropped on the × → hidden (still in
/// the notification bar) with a small pill at the top to bring it back.
class OngoingSessionsOverlay extends StatefulWidget {
  OngoingSessionsOverlay({super.key, required this.navigatorKey, this.call, MinuteRecorder? recorder, NotebookRecorder? notebook, ValueListenable<bool>? pip})
      : _recorder = recorder,
        _notebook = notebook,
        pip = pip ?? NativeOngoingNotifier.shared.inPip;

  /// Android Picture-in-Picture: the whole app is a small window → a compact view of the room.
  final ValueListenable<bool> pip;
  final GlobalKey<NavigatorState> navigatorKey;
  final CallService? call;
  final MinuteRecorder? _recorder;
  final NotebookRecorder? _notebook;

  MinuteRecorder get recorder => _recorder ?? MinuteRecorder.instance;
  NotebookRecorder get notebook => _notebook ?? NotebookRecorder.instance;

  @override
  State<OngoingSessionsOverlay> createState() => _OngoingSessionsOverlayState();
}

class _OngoingSessionsOverlayState extends State<OngoingSessionsOverlay> {
  Timer? _tick;
  MinuteRoomSession? _room;

  @override
  void initState() {
    super.initState();
    MinuteRoomSession.active.addListener(_roomChanged);
    _roomChanged();
    widget.recorder.onOpenRequest ??= _openRecorder;
    // Notification "กลับเข้าห้อง" / tap → the room screen.
    OngoingSessionsBinder.openRoom = (r) {
      final nav = widget.navigatorKey.currentState;
      if (nav != null) unawaited(reopenMinuteRoom(nav, r));
    };
    widget.pip.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_room != null || widget.recorder.active)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    MinuteRoomSession.active.removeListener(_roomChanged);
    _room?.removeListener(_changed);
    if (widget.recorder.onOpenRequest == _openRecorder) widget.recorder.onOpenRequest = null;
    OngoingSessionsBinder.openRoom = null;
    widget.pip.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  void _roomChanged() {
    final r = MinuteRoomSession.active.value;
    if (r == _room) return;
    _room?.removeListener(_changed);
    _room = r;
    r?.addListener(_changed);
    if (r == null) OngoingBubbles.instance.forget('room');
    _changed();
  }

  void _openRoom() {
    final nav = widget.navigatorKey.currentState;
    final r = _room;
    if (nav == null || r == null) return;
    unawaited(reopenMinuteRoom(nav, r));
  }

  void _openRecorder() {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || widget.recorder.screenOpen || !widget.recorder.active) return;
    unawaited(openMinuteRecorder(ctx, widget.recorder));
  }

  void _hint() {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr('ยังทำงานอยู่ — ดูได้ที่แถบแจ้งเตือนหรือแถบด้านบน')), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.recorder, OngoingBubbles.instance, widget.pip, ?call]),
      builder: (context, _) {
        final callShown = call != null && (call.phase != CallPhase.idle || call.incoming != null);
        final hidden = OngoingBubbles.instance;
        final room = _room;
        final roomOn = room != null && !room.closed;
        final recOn = widget.recorder.active;
        if (!recOn) hidden.forget('minute_recording');
        // Picture-in-Picture (Android, video room): only the active speaker, nothing to tap.
        if (widget.pip.value && roomOn) return _PipRoomView(room: room);
        final children = <Widget>[];
        // One bubble at a time (the call has its own, above everything).
        if (!callShown && roomOn && !room.screenOpen) {
          if (!hidden.isHidden('room')) {
            children.add(_roomBubble(room));
          } else {
            children.add(NxOngoingRestorePill(kind: 'room', label: tr('กำลังประชุม'), color: const Color(0xFF22C55E)));
          }
        } else if (!callShown && !roomOn && recOn && !widget.recorder.screenOpen) {
          if (!hidden.isHidden('minute_recording')) {
            children.add(_recorderBubble());
          } else {
            children.add(NxOngoingRestorePill(kind: 'minute_recording', label: tr('กำลังบันทึกประชุม')));
          }
        }
        return Stack(children: children);
      },
    );
  }

  Widget _roomBubble(MinuteRoomSession r) {
    final started = r.startedAt ?? DateTime.now();
    final mic = r.media.micOn;
    final speaker = r.media.speaker;
    final who = speaker == null ? r.title : (speaker.name.isNotEmpty ? speaker.name : speaker.identity);
    return NxOngoingBubble(
      key: const ValueKey('room-bubble'),
      kind: 'room',
      semanticsLabel: tr('ห้องประชุม — แตะเพื่อกลับเข้าห้อง'),
      onTap: _openRoom,
      onHidden: _hint,
      child: NxOngoingPill(
        border: const Color(0x8022C55E),
        leading: CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xFF312E81),
          child: Text(roomInitials(who.isEmpty ? '?' : who), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        title: minuteClock(DateTime.now().difference(started).inMilliseconds),
        subtitle: speaker != null && speaker.identity != r.identity ? '${tr('กำลังพูด')}: $who' : tr('ห้องประชุม · ${r.media.participants.length} คน'),
        action: NxOngoingPillButton(
          key: const ValueKey('room-bubble-mic'),
          icon: mic ? NxI.microphone : LucideIcons300.micOff,
          active: !mic,
          onTap: () => unawaited(r.toggleMic()),
        ),
      ),
    );
  }

  Widget _recorderBubble() {
    final r = widget.recorder;
    final paused = r.paused;
    return NxOngoingBubble(
      key: const ValueKey('minute-recorder-bubble'),
      kind: 'minute_recording',
      semanticsLabel: tr('บันทึกประชุม — แตะเพื่อเปิด'),
      onTap: _openRecorder,
      onHidden: _hint,
      child: NxOngoingPill(
        border: (paused ? Colors.white : const Color(0xFFDC2626)).withValues(alpha: paused ? 0.14 : 0.45),
        leading: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: paused ? 0.25 : 0.9), shape: BoxShape.circle),
          child: const Icon(NxI.microphone, size: 16, color: Colors.white),
        ),
        title: minuteClock(r.elapsed.inMilliseconds),
        subtitle: tr(paused ? 'หยุดชั่วคราว' : 'กำลังบันทึกประชุม'),
        action: NxOngoingPillButton(
          key: const ValueKey('minute-recorder-bubble-toggle'),
          icon: paused ? NxI.microphone : LucideIcons300.pause,
          active: paused,
          onTap: () => unawaited(r.togglePause()),
        ),
      ),
    );
  }
}

/// The room in a Picture-in-Picture window: the speaker's video (or initials), the clock.
class _PipRoomView extends StatelessWidget {
  const _PipRoomView({required this.room});
  final MinuteRoomSession room;

  @override
  Widget build(BuildContext context) {
    final parts = room.media.participants;
    final p = room.media.speaker ?? (parts.isEmpty ? null : parts.firstWhere((x) => x.isCameraEnabled() || x.isScreenShareEnabled(), orElse: () => parts.first));
    lk.VideoTrack? track;
    if (p != null) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t is lk.VideoTrack && !pub.muted) {
          track = t;
          if (pub.source == lk.TrackSource.screenShareVideo) break;
        }
      }
    }
    final name = p == null ? room.title : (p.name.isNotEmpty ? p.name : p.identity);
    return ColoredBox(
      key: const ValueKey('room-pip'),
      color: const Color(0xFF0B1020),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null)
            lk.VideoTrackRenderer(track, fit: lk.VideoViewFit.cover)
          else
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF312E81),
                child: Text(roomInitials(name.isEmpty ? '?' : name), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(
              '${minuteClock(DateTime.now().difference(room.startedAt ?? DateTime.now()).inMilliseconds)} · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 4)]),
            ),
          ),
        ],
      ),
    );
  }
}
