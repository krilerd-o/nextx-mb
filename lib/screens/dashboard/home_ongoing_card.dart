import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/business_switch_reload.dart';
import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../services/api_client.dart';
import '../../services/calls/call_service.dart';
import '../../services/minutes/minute_recorder.dart';
import '../../services/minutes/minute_room_session.dart';
import '../../services/minutes/minute_uploader.dart';
import '../../services/notebook/notebook_recorder.dart';
import '../../widgets/nx_icons.dart';
import '../minutes/minute_join_sheet.dart' show joinMinuteRoomAsMember;
import '../minutes/minute_record_flow.dart' show openMinuteRecorder;
import '../minutes/minute_room_screen.dart' show reopenMinuteRoom;

/// One row of the Home card "กำลังทำอยู่".
class OngoingRow {
  const OngoingRow({required this.id, required this.icon, required this.title, required this.subtitle, required this.action, required this.onTap, this.color = const Color(0xFF16A34A)});
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
  final Color color;
}

/// Home card "กำลังทำอยู่": the call / meeting room / recording / upload running now, and open meeting rooms of
/// this business I may join. Hidden when there is nothing; rooms only with the AI Minute Meeting menu.
class HomeOngoingCard extends StatefulWidget {
  const HomeOngoingCard({super.key, this.revision = 0, this.call, this.recorder, this.notebook, this.uploader});
  final int revision;
  final CallService? call;
  final MinuteRecorder? recorder;
  final NotebookRecorder? notebook;
  final MinuteUploader? uploader;

  @override
  State<HomeOngoingCard> createState() => _HomeOngoingCardState();
}

class _HomeOngoingCardState extends State<HomeOngoingCard> with ReloadOnBusinessSwitch {
  List<MinuteMeeting> _open = const [];
  Timer? _tick;

  CallService? get _call => widget.call ?? CallService.instance;
  MinuteRecorder get _rec => widget.recorder ?? MinuteRecorder.instance;
  NotebookRecorder get _nb => widget.notebook ?? NotebookRecorder.instance;
  MinuteUploader get _up => widget.uploader ?? MinuteUploader.instance;

  bool get _minutesAllowed {
    final s = context.read<AppConfig>().session;
    return s.isSuperadmin || s.canAccess('ai-minute-meeting');
  }

  @override
  void initState() {
    super.initState();
    watchBusiness();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didUpdateWidget(HomeOngoingCard old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  void onBusinessSwitched() {
    setState(() => _open = const []);
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_minutesAllowed) return;
    try {
      final rows = await context.read<AppConfig>().apiClient.getMinuteMeetings(source: 'room', open: true, limit: 5);
      if (mounted) setState(() => _open = [for (final r in rows) MinuteMeeting.fromJson(r)]);
    } catch (_) {}
  }

  List<OngoingRow> _rows() {
    final out = <OngoingRow>[];
    final call = _call;
    if (call != null && (call.phase == CallPhase.active || call.phase == CallPhase.outgoing)) {
      out.add(OngoingRow(id: 'call', icon: NxI.phone, title: call.title.isEmpty ? tr('สายที่กำลังคุย') : call.title, subtitle: tr(call.isVideo ? 'วิดีโอคอล' : 'กำลังคุยสาย'), action: tr('เปิด'), onTap: () => call.setMinimized(false)));
    }
    final room = MinuteRoomSession.active.value;
    if (room != null && !room.closed) {
      out.add(OngoingRow(
        id: 'room',
        icon: NxI.videoCamera,
        title: room.title.isEmpty ? tr('ห้องประชุม') : room.title,
        subtitle: tr('คุณอยู่ในห้องประชุมนี้'),
        action: tr('กลับเข้าห้อง'),
        onTap: () => reopenMinuteRoom(Navigator.of(context, rootNavigator: true), room),
      ));
    }
    if (_rec.active) {
      out.add(OngoingRow(id: 'minute_recording', icon: NxI.microphone, color: const Color(0xFFDC2626), title: _rec.title, subtitle: tr(_rec.paused ? 'บันทึกประชุม · หยุดชั่วคราว' : 'กำลังบันทึกประชุม'), action: tr('เปิด'), onTap: () => openMinuteRecorder(context, _rec)));
    }
    if (_nb.active) {
      out.add(OngoingRow(id: 'notebook_recording', icon: NxI.microphone, color: const Color(0xFFDB2777), title: _nb.title, subtitle: tr('กำลังบันทึกเสียงในสมุดโน้ต'), action: tr('เปิด'), onTap: () => _nb.onOpenRequest?.call()));
    }
    final bid = context.read<AppConfig>().session.businessId;
    final ups = _up.forBusiness(bid).where((j) => j.state == 'uploading' || j.state == 'paused').toList();
    if (ups.isNotEmpty) {
      final j = ups.first;
      out.add(OngoingRow(
        id: 'upload',
        icon: NxI.cloud,
        color: const Color(0xFF2563EB),
        title: ups.length == 1 ? j.title : tr('อัปโหลดไฟล์ประชุม ${ups.length} ไฟล์'),
        subtitle: tr('กำลังอัปโหลด ${(j.progress * 100).round()}%'),
        action: tr('ดู'),
        onTap: () => context.push('/ai-minutes'),
      ));
    }
    if (_minutesAllowed) {
      for (final m in _open) {
        if (m.roomCode == null || (room != null && !room.closed && room.roomCode == m.roomCode)) continue;
        out.add(OngoingRow(
          id: 'open-${m.id}',
          icon: NxI.users,
          title: m.title,
          subtitle: tr('ห้องประชุมเปิดอยู่'),
          action: tr('เข้าร่วม'),
          onTap: () => joinMinuteRoomAsMember(context, meetingId: m.id, code: m.roomCode!, title: m.title),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return ListenableBuilder(
      listenable: Listenable.merge([MinuteRoomSession.active, _rec, _nb, _up, ?call]),
      builder: (context, _) {
        final rows = _rows();
        if (rows.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            key: const ValueKey('home-ongoing'),
            color: const Color(0xFF16A34A).withValues(alpha: theme.brightness == Brightness.dark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(NxI.videoCamera, size: 16, color: Color(0xFF16A34A)),
                    const SizedBox(width: 6),
                    Text(tr('กำลังทำอยู่'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF15803D))),
                  ]),
                  const SizedBox(height: 4),
                  for (final r in rows)
                    ListTile(
                      key: ValueKey('home-ongoing-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: CircleAvatar(radius: 17, backgroundColor: r.color, child: Icon(r.icon, size: 16, color: Colors.white)),
                      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                      trailing: FilledButton(
                        key: ValueKey('home-ongoing-${r.id}-go'),
                        style: FilledButton.styleFrom(backgroundColor: r.color, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: r.onTap,
                        child: Text(r.action),
                      ),
                      onTap: r.onTap,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
