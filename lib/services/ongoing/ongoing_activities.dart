import 'dart:async';

import '../audio/recording_upload_queue.dart';
import '../calls/call_service.dart';
import '../minutes/minute_recorder.dart';
import '../minutes/minute_room_session.dart';
import '../minutes/minute_uploader.dart';
import '../notebook/notebook_recorder.dart';

/// Something running in the background that a business switch or sign-out must not cut silently.
class OngoingActivity {
  const OngoingActivity(this.kind, this.label);

  /// call | room | minute_recording | notebook_recording | upload
  final String kind;
  final String label;
}

/// Extra sources (the meeting room session registers itself here).
final List<OngoingActivity? Function()> ongoingSources = [];

/// What is running now, most important first.
List<OngoingActivity> ongoingActivities() {
  final out = <OngoingActivity>[];
  final call = CallService.instance;
  if (call != null && call.phase != CallPhase.idle) out.add(const OngoingActivity('call', 'กำลังอยู่ในสาย'));
  final room = MinuteRoomSession.active.value;
  if (room != null && !room.closed) out.add(OngoingActivity('room', room.title.isEmpty ? 'อยู่ในห้องประชุม' : 'อยู่ในห้องประชุม: ${room.title}'));
  for (final s in ongoingSources) {
    final a = s();
    if (a != null) out.add(a);
  }
  if (MinuteRecorder.instance.active) out.add(const OngoingActivity('minute_recording', 'กำลังบันทึกประชุม'));
  if (NotebookRecorder.instance.active) out.add(const OngoingActivity('notebook_recording', 'กำลังบันทึกเสียงในสมุดโน้ต'));
  if (MinuteUploader.instance.mine.any((j) => j.state == 'uploading' || j.state == 'paused')) {
    out.add(const OngoingActivity('upload', 'กำลังอัปโหลดไฟล์ประชุม'));
  }
  return out;
}

/// Before signing out: end what needs the account, and give the last recording parts a moment to reach
/// the server while the token is still valid.
Future<void> wrapUpBeforeSignOut({Duration flushFor = const Duration(seconds: 12)}) async {
  final call = CallService.instance;
  if (call != null && call.phase != CallPhase.idle) {
    try {
      await call.hangUp();
    } catch (_) {}
  }
  final room = MinuteRoomSession.active.value;
  if (room != null && !room.closed) {
    try {
      await room.close();
    } catch (_) {}
  }
  for (final s in signOutHooks) {
    try {
      await s();
    } catch (_) {}
  }
  if (MinuteRecorder.instance.active) {
    try {
      await MinuteRecorder.instance.stop();
    } catch (_) {}
  }
  if (NotebookRecorder.instance.active) {
    try {
      await NotebookRecorder.instance.stop();
    } catch (_) {}
  }
  try {
    await RecordingUploadQueue.instance.pump().timeout(flushFor);
  } catch (_) {}
  MinuteUploader.instance.signOut();
}

/// Extra clean-up on sign-out (the meeting room leaves its room).
final List<Future<void> Function()> signOutHooks = [];
