import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/api_client.dart';
import '../../services/minutes/minute_room_session.dart';
import '../../widgets/nx_icons.dart';
import 'minutes_widgets.dart';

/// Tests inject the session (no LiveKit server here).
@visibleForTesting
MinuteRoomSession Function(Map<String, dynamic> join, String code)? debugRoomSession;

Future<void> openMinuteRoomScreen(BuildContext context, {required Map<String, dynamic> join, required String code, required String title, bool micOn = false, bool camOn = false}) {
  final s = debugRoomSession?.call(join, code) ??
      MinuteRoomSession(
        meetingId: '${join['meeting_id'] ?? ''}',
        roomCode: code,
        ticket: '${join['ticket'] ?? ''}',
        identity: '${join['identity'] ?? ''}',
        role: '${join['role'] ?? 'member'}',
        name: '${join['name'] ?? ''}',
      );
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => MinuteRoomScreen(session: s, url: '${join['livekit_url'] ?? ''}', token: '${join['token'] ?? ''}', title: title, micOn: micOn, camOn: camOn)),
  );
}

/// The meeting room: video grid (active speaker first), captions with a language switch, chat,
/// reactions, raise hand, participants (host: admit / remove / co-host), and end / leave.
class MinuteRoomScreen extends StatefulWidget {
  const MinuteRoomScreen({super.key, required this.session, required this.url, required this.token, required this.title, this.micOn = false, this.camOn = false});
  final MinuteRoomSession session;
  final String url;
  final String token;
  final String title;
  final bool micOn;
  final bool camOn;

  @override
  State<MinuteRoomScreen> createState() => _MinuteRoomScreenState();
}

class _MinuteRoomScreenState extends State<MinuteRoomScreen> {
  MinuteRoomSession get s => widget.session;
  bool _showCaptions = true;
  final _reactions = <(String, String, int)>[];
  StreamSubscription<(String, String)>? _rx;
  int _rxId = 0;
  final _started = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    _rx = s.reactions.stream.listen((r) {
      final id = ++_rxId;
      setState(() => _reactions.add((r.$1, r.$2, id)));
      Timer(const Duration(seconds: 3), () => mounted ? setState(() => _reactions.removeWhere((x) => x.$3 == id)) : null);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    unawaited(s.start(url: widget.url, token: widget.token, micOn: widget.micOn, camOn: widget.camOn));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rx?.cancel();
    s.removeListener(_changed);
    unawaited(s.leave().whenComplete(s.dispose));
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  Future<void> _leave({bool end = false}) async {
    if (end) {
      try {
        await _api.endMinuteRoom(s.meetingId);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiEnvelopeException ? e.message : tr('จบการประชุมไม่สำเร็จ'))));
        return;
      }
    } else {
      unawaited(_api.leaveMinuteRoom(s.roomCode, s.ticket).then((_) {}, onError: (_) {}));
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (end && s.meetingId.isNotEmpty) {
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(SnackBar(content: Text(tr('จบการประชุมแล้ว — ไอแซคกำลังทำบันทึกการประชุม'))));
      GoRouter.maybeOf(nav.context)?.push(AppRoutes.aiMinute(s.meetingId));
    }
  }

  Future<void> _confirmLeave() async {
    if (!s.isHost) return _leave();
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const ValueKey('room-end-all'), leading: const Icon(NxI.phoneX, color: kMinuteRecord), title: Text(tr('จบการประชุมสำหรับทุกคน')), subtitle: Text(tr('ไอแซคจะสรุปตามที่ตั้งค่าไว้')), onTap: () => Navigator.pop(ctx, 'end')),
          ListTile(leading: const Icon(NxI.signOut), title: Text(tr('ออกจากห้อง (ห้องยังเปิดอยู่)')), onTap: () => Navigator.pop(ctx, 'leave')),
        ]),
      ),
    );
    if (r != null) await _leave(end: r == 'end');
  }

  @override
  Widget build(BuildContext context) {
    final parts = s.media.participants;
    final elapsed = DateTime.now().difference(_started);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: const ValueKey('minute-room'),
        backgroundColor: const Color(0xFF0B1020),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(elapsed),
                  if (s.error != null) Padding(padding: const EdgeInsets.all(16), child: Text(tr(s.error!), style: const TextStyle(color: Colors.white70))),
                  Expanded(child: _grid(parts)),
                  if (_showCaptions && s.captionsOn) _captions(),
                  _controls(),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 120,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final r in _reactions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                        child: Text('${r.$2}  ${r.$1}', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(Duration elapsed) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Row(children: [
      IconButton(tooltip: tr('ย่อ'), icon: const Icon(NxI.caretDown, color: Colors.white70), onPressed: _confirmLeave),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Row(children: [
            if (s.transcribing || s.captionsOn) ...[const Icon(NxI.sparkle, size: 12, color: Color(0xFFA5B4FC)), const SizedBox(width: 4)],
            Text('${minuteClock(elapsed.inMilliseconds)} · ${s.media.participants.length} ${tr('คน')} · ${s.roomCode}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ]),
      ),
      if (s.isHost)
        ValueListenableBuilder<List<(String, String)>>(
          valueListenable: s.waiting,
          builder: (_, w, _) => w.isEmpty
              ? const SizedBox.shrink()
              : TextButton.icon(
                  key: const ValueKey('room-waiting'),
                  onPressed: _people,
                  icon: const Icon(NxI.userPlus, size: 16, color: Color(0xFFFDE68A)),
                  label: Text('${tr('รอเข้า')} ${w.length}', style: const TextStyle(color: Color(0xFFFDE68A))),
                ),
        ),
      IconButton(key: const ValueKey('room-people'), tooltip: tr('ผู้เข้าร่วม'), icon: const Icon(NxI.users, color: Colors.white), onPressed: _people),
    ]),
  );

  /// Someone presenting (screen share / whiteboard / slides from the web): big stage + a strip of people.
  Widget _stage(lk.Participant presenter, List<lk.Participant> parts) {
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Stack(children: [
            Positioned.fill(child: _Tile(key: const ValueKey('room-stage'), p: presenter, hand: false, stage: true)),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                child: Text('${presenter.name.isEmpty ? presenter.identity : presenter.name} ${tr('กำลังแชร์หน้าจอ')}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            if (s.isHost && presenter is! lk.LocalParticipant)
              Positioned(
                right: 8,
                top: 8,
                child: FilledButton.tonal(
                  key: const ValueKey('room-stop-share'),
                  style: FilledButton.styleFrom(backgroundColor: kMinuteRecord, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: () async {
                    await s.media.sendData({'type': 'stop_share', 'identity': presenter.identity}, topic: 'share');
                    try {
                      await _api.stopMinuteShare(s.meetingId, presenter.identity);
                    } catch (_) {}
                  },
                  child: Text(tr('หยุดการแชร์นี้')),
                ),
              ),
          ]),
        ),
      ),
      SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [for (final p in parts.take(12)) Padding(padding: const EdgeInsets.only(right: 6), child: SizedBox(width: 76, child: _Tile(p: p, hand: s.hands.value.contains(p.name), cameraOnly: true)))],
        ),
      ),
    ]);
  }

  Widget _grid(List<lk.Participant> parts) {
    final presenter = parts.where((p) => p.videoTrackPublications.any((t) => t.source == lk.TrackSource.screenShareVideo && t.track != null && !t.muted)).firstOrNull;
    if (presenter != null) return _stage(presenter, parts);
    if (parts.isEmpty) return Center(child: Text(tr(s.connected ? 'รอผู้เข้าร่วม…' : 'กำลังเชื่อมต่อ…'), style: const TextStyle(color: Colors.white54)));
    final visible = parts.take(9).toList();
    final cols = visible.length <= 1 ? 1 : visible.length <= 4 ? 2 : 3;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: cols,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: cols == 1 ? 3 / 4 : 3 / 4,
        children: [for (final p in visible) _Tile(p: p, hand: s.hands.value.contains(p.name))],
      ),
    );
  }

  Widget _captions() => Container(
    key: const ValueKey('room-captions'),
    constraints: const BoxConstraints(minHeight: 64, maxHeight: 150),
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(16)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: ValueListenableBuilder<List<RoomCaption>>(
          valueListenable: s.captions,
          builder: (_, caps, _) => ValueListenableBuilder<Map<int, String>>(
            valueListenable: s.translated,
            builder: (_, tr0, _) {
              final last = caps.length > 3 ? caps.sublist(caps.length - 3) : caps;
              if (last.isEmpty) return Text(tr('คำบรรยายสดจะแสดงที่นี่'), style: const TextStyle(color: Colors.white38));
              return ListView(reverse: true, shrinkWrap: true, children: [
                for (final c in last.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${c.speaker}: ', style: const TextStyle(color: Color(0xFFA5B4FC), fontWeight: FontWeight.w700)),
                      TextSpan(text: s.captionLang != null && tr0[c.seq] != null ? tr0[c.seq] : c.text, style: TextStyle(color: c.partial ? Colors.white60 : Colors.white)),
                    ])),
                  ),
              ]);
            },
          ),
        ),
      ),
      if (s.translateLangs.isNotEmpty)
        PopupMenuButton<String>(
          key: const ValueKey('room-caption-lang'),
          tooltip: tr('ภาษาคำบรรยาย'),
          icon: const Icon(NxI.languages, color: Colors.white70, size: 20),
          onSelected: (v) => s.setCaptionLang(v.isEmpty ? null : v),
          itemBuilder: (_) => [
            PopupMenuItem(value: '', child: Text(tr('ภาษาต้นฉบับ'))),
            for (final l in s.translateLangs) PopupMenuItem(value: l, child: Text(tr(minuteRoomLangLabel(l)))),
          ],
        ),
    ]),
  );

  Widget _btn(Key key, IconData icon, String label, VoidCallback onTap, {bool active = true, Color? bg}) => Column(mainAxisSize: MainAxisSize.min, children: [
    IconButton.filled(
      key: key,
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(backgroundColor: bg ?? (active ? Colors.white24 : Colors.white), foregroundColor: active ? Colors.white : Colors.black87, minimumSize: const Size(50, 50)),
    ),
    const SizedBox(height: 3),
    Text(tr(label), style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
  ]);

  Widget _controls() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _btn(const ValueKey('room-mic'), s.media.micOn ? NxI.microphone : NxI.microphoneSlash, s.media.micOn ? 'ไมค์' : 'ปิดไมค์', s.toggleMic, active: s.media.micOn),
      _btn(const ValueKey('room-cam'), s.media.camOn ? NxI.videoCamera : NxI.videoCameraSlash, s.media.camOn ? 'กล้อง' : 'ปิดกล้อง', s.toggleCamera, active: s.media.camOn),
      _btn(const ValueKey('room-cc'), NxI.textAlignLeft, 'คำบรรยาย', () => setState(() => _showCaptions = !_showCaptions), active: _showCaptions),
      _btn(const ValueKey('room-more'), NxI.dotsThree, 'เพิ่มเติม', _moreSheet),
      _btn(const ValueKey('room-leave'), NxI.phoneX, s.isHost ? 'จบ' : 'ออก', _confirmLeave, bg: kMinuteRecord),
    ]),
  );

  Future<void> _moreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final e in const ['👍', '👏', '😂', '❤️', '🎉', '🙏'])
                ActionChip(label: Text(e, style: const TextStyle(fontSize: 20)), onPressed: () {
                  Navigator.pop(ctx);
                  s.react(e);
                }),
            ]),
            ListTile(leading: const Icon(NxI.handPointing), title: Text(tr(s.handUp ? 'เอามือลง' : 'ยกมือ')), onTap: () {
              Navigator.pop(ctx);
              s.toggleHand();
            }),
            ListTile(leading: const Icon(NxI.chatCircle), title: Text(tr('แชทในห้อง')), onTap: () {
              Navigator.pop(ctx);
              _chat();
            }),
            ListTile(leading: const Icon(NxI.cameraRotate), title: Text(tr('สลับกล้องหน้า / หลัง')), onTap: () {
              Navigator.pop(ctx);
              s.flipCamera();
            }),
            // Presenting from the phone needs a native screen-capture service (next app build). People on the
            // web can share a tab / window / the whole screen, a whiteboard, slides or a second camera.
            ListTile(
              enabled: false,
              leading: const Icon(NxI.screencast),
              title: Text(tr('แชร์หน้าจอ')),
              subtitle: Text(tr('ใช้ได้บนเว็บตอนนี้ (แท็บ / หน้าต่าง / ทั้งหน้าจอ / ไวท์บอร์ด / ไฟล์) — มือถือจะตามมาในแอปเวอร์ชันถัดไป')),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _chat() async {
    final c = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(14), child: Text(tr('แชทในห้อง'), style: Theme.of(ctx).textTheme.titleMedium)),
            Expanded(
              child: ValueListenableBuilder<List<RoomChatMessage>>(
                valueListenable: s.chat,
                builder: (_, msgs, _) => ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
                  for (final m in msgs)
                    Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: m.mine ? Theme.of(ctx).colorScheme.primaryContainer : Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!m.mine) Text(m.from, style: Theme.of(ctx).textTheme.labelSmall),
                          Text(m.text),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Expanded(child: TextField(key: const ValueKey('room-chat-input'), controller: c, decoration: InputDecoration(hintText: tr('พิมพ์ข้อความ…'), isDense: true, border: const OutlineInputBorder()))),
                  IconButton(icon: const Icon(NxI.paperPlaneTilt), onPressed: () {
                    s.sendChat(c.text);
                    c.clear();
                  }),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
  }

  Future<void> _people() async {
    List<Map<String, dynamic>> list = const [];
    try {
      list = await _api.getMinuteRoomParticipants(s.meetingId);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> refresh() async {
            try {
              final l = await _api.getMinuteRoomParticipants(s.meetingId);
              set(() => list = l);
            } catch (_) {}
          }

          final waiting = list.where((p) => p['state'] == 'waiting').toList();
          final inRoom = list.where((p) => p['state'] == 'joined' || p['state'] == 'admitted').toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.7,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (s.isHost && waiting.isNotEmpty) ...[
                  MinuteSectionTitle('รอเข้าห้อง (${waiting.length})', icon: NxI.userPlus),
                  for (final p in waiting)
                    ListTile(
                      key: ValueKey('room-wait-${p['identity']}'),
                      leading: CircleAvatar(child: Text(roomInitials('${p['name']}'))),
                      title: Text('${p['name']}'),
                      subtitle: Text('${p['email'] ?? tr('แขก')}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: tr('ไม่รับ'), icon: const Icon(NxI.x), onPressed: () async {
                          await _api.admitMinuteGuest(s.meetingId, '${p['identity']}', allow: false);
                          s.admitted('${p['identity']}');
                          await refresh();
                        }),
                        FilledButton(key: ValueKey('room-admit-${p['identity']}'), onPressed: () async {
                          await _api.admitMinuteGuest(s.meetingId, '${p['identity']}');
                          s.admitted('${p['identity']}');
                          await refresh();
                        }, child: Text(tr('รับเข้า'))),
                      ]),
                    ),
                ],
                MinuteSectionTitle('ในห้อง (${inRoom.length})', icon: NxI.users),
                for (final p in inRoom)
                  ListTile(
                    leading: CircleAvatar(child: Text(roomInitials('${p['name']}'))),
                    title: Text('${p['name']}${p['guest'] == true ? ' · ${tr('แขก')}' : ''}'),
                    subtitle: Text(tr(switch ('${p['role']}') { 'host' => 'ผู้จัด', 'cohost' => 'ผู้ช่วยจัด', 'guest' => 'แขก', _ => 'ผู้เข้าร่วม' })),
                    trailing: s.isHost && p['role'] != 'host'
                        ? PopupMenuButton<String>(
                            onSelected: (a) async {
                              if (a == 'remove') await _api.removeMinuteParticipant(s.meetingId, '${p['identity']}');
                              if (a == 'cohost') await _api.setMinuteCohost(s.meetingId, '${p['identity']}', on: p['role'] != 'cohost');
                              await refresh();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'cohost', child: Text(tr(p['role'] == 'cohost' ? 'ยกเลิกผู้ช่วยจัด' : 'ตั้งเป็นผู้ช่วยจัด'))),
                              PopupMenuItem(value: 'remove', child: Text(tr('นำออกจากห้อง'))),
                            ],
                          )
                        : null,
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.p, required this.hand, this.stage = false, this.cameraOnly = false});
  final lk.Participant p;
  final bool hand;
  final bool stage;
  final bool cameraOnly;

  @override
  Widget build(BuildContext context) {
    final pub = p.videoTrackPublications
        .where((t) => stage ? t.source == lk.TrackSource.screenShareVideo : cameraOnly ? t.source == lk.TrackSource.camera : (t.source == lk.TrackSource.screenShareVideo || t.source == lk.TrackSource.camera))
        .firstOrNull;
    final track = pub?.track;
    final showVideo = track is lk.VideoTrack && !(pub?.muted ?? true);
    final name = p.name.isEmpty ? p.identity : p.name;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: p.isSpeaking ? const Color(0xFF818CF8) : Colors.transparent, width: 3)),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (showVideo) lk.VideoTrackRenderer(track, fit: stage ? lk.VideoViewFit.contain : lk.VideoViewFit.cover) else Center(child: CircleAvatar(radius: 28, child: Text(roomInitials(name)))),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          child: Row(children: [
            if (!p.isMicrophoneEnabled()) const Icon(NxI.microphoneSlash, size: 14, color: Colors.white70),
            if (hand) const Text(' ✋'),
            const SizedBox(width: 4),
            Expanded(
              child: Text(p is lk.LocalParticipant ? '$name (${tr('คุณ')})' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 4)])),
            ),
          ]),
        ),
      ]),
    );
  }
}
