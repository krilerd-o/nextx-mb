import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/i18n.dart';
import '../../services/calls/call_service.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_icons.dart';

/// Shows the call on top of the whole app: incoming, calling…, in call (full screen or a
/// floating bubble). Put it in `MaterialApp.builder` above the navigator.
class CallOverlay extends StatelessWidget {
  const CallOverlay({super.key, required this.service});
  final CallService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final s = service;
        final children = <Widget>[];
        if (s.incoming != null && s.phase != CallPhase.active && s.phase != CallPhase.outgoing) {
          children.add(Positioned.fill(child: _IncomingView(service: s)));
        } else if (s.phase == CallPhase.outgoing || s.phase == CallPhase.active) {
          children.add(s.minimized ? _Bubble(service: s) : Positioned.fill(child: _CallView(service: s)));
        }
        final msg = s.error ?? s.notice;
        if (msg != null) {
          children.add(Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: Center(
              child: Material(
                key: const ValueKey('call-notice'),
                color: s.error != null ? Colors.red.shade700 : const Color(0xE6111827),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: s.clearError,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(NxI.phone, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tr(msg), style: const TextStyle(color: Colors.white))),
                    ]),
                  ),
                ),
              ),
            ),
          ));
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Stack(children: children);
      },
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onTap, this.active = false, this.color, this.size = 58});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = color != null ? Colors.white : (active ? const Color(0xFF0F172A) : Colors.white);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(width: size, height: size, child: Icon(icon, color: fg, size: size * 0.42)),
        ),
      ),
      const SizedBox(height: 6),
      Text(tr(label), style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

class _IncomingView extends StatelessWidget {
  const _IncomingView({required this.service});
  final CallService service;

  @override
  Widget build(BuildContext context) {
    final inc = service.incoming!;
    final video = inc['media'] == 'video';
    final group = inc['group'] == true;
    final caller = inc['caller_name']?.toString() ?? '';
    final title = group ? (inc['room_name']?.toString() ?? caller) : caller;
    final inCall = (inc['peers'] is List) ? (inc['peers'] as List).length : 0;
    return Material(
      key: const ValueKey('call-incoming'),
      color: const Color(0xFF0B1220),
      child: SafeArea(
        child: Column(children: [
          const Spacer(flex: 2),
          _Pulse(child: NxAvatar(label: caller, size: 112)),
          const SizedBox(height: 22),
          Text(tr(video ? 'วิดีโอคอลเข้า' : 'สายเรียกเข้า'), style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          if (group)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('$caller เริ่มโทรกลุ่ม${inCall > 1 ? ' · อยู่ในสาย $inCall คน' : ''}'), style: const TextStyle(color: Colors.white70)),
            ),
          const Spacer(flex: 3),
          Padding(
            padding: const EdgeInsets.only(bottom: 36),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _RoundButton(key: const ValueKey('call-decline'), icon: NxI.phoneX, label: 'ปฏิเสธ', color: const Color(0xFFEF4444), size: 68, onTap: service.decline),
              if (video) _RoundButton(key: const ValueKey('call-accept-audio'), icon: NxI.phone, label: 'รับด้วยเสียง', size: 58, onTap: () => service.accept(video: false)),
              _RoundButton(
                key: const ValueKey('call-accept'),
                icon: video ? NxI.videoCamera : NxI.phone,
                label: 'รับสาย',
                color: const Color(0xFF22C55E),
                size: 68,
                onTap: () => service.accept(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Stack(alignment: Alignment.center, children: [
        Container(
          width: 112 + 60 * _c.value,
          height: 112 + 60 * _c.value,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withValues(alpha: 0.25 * (1 - _c.value))),
        ),
        child!,
      ]),
      child: widget.child,
    );
  }
}

/// Live video for one stream (or an avatar when the camera is off).
class CallVideoTile extends StatefulWidget {
  const CallVideoTile({super.key, required this.stream, required this.name, required this.videoOn, this.mirror = false, this.audioOn = true, this.compact = false, this.connecting = false});
  final Object? stream;
  final String name;
  final bool videoOn;
  final bool mirror;
  final bool audioOn;
  final bool compact;
  final bool connecting;

  @override
  State<CallVideoTile> createState() => _CallVideoTileState();
}

class _CallVideoTileState extends State<CallVideoTile> {
  RTCVideoRenderer? _r;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final r = RTCVideoRenderer();
    try {
      await r.initialize();
    } catch (_) {
      return; // no WebRTC (tests)
    }
    if (!mounted) {
      await r.dispose();
      return;
    }
    _r = r;
    _bind();
    setState(() => _ready = true);
  }

  void _bind() {
    final s = widget.stream;
    if (_r != null && s is MediaStream && _r!.srcObject != s) _r!.srcObject = s;
  }

  @override
  void didUpdateWidget(covariant CallVideoTile old) {
    super.didUpdateWidget(old);
    if (old.stream != widget.stream) _bind();
  }

  @override
  void dispose() {
    _r?.srcObject = null;
    _r?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showVideo = widget.videoOn && _ready && widget.stream is MediaStream;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.compact ? 12 : 18),
      child: Container(
        color: const Color(0xFF1E293B),
        child: Stack(fit: StackFit.expand, children: [
          if (showVideo)
            RTCVideoView(_r!, mirror: widget.mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                NxAvatar(label: widget.name, size: widget.compact ? 44 : 84),
                if (widget.connecting && !widget.compact)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(tr('กำลังเชื่อมต่อ…'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
              ]),
            ),
          if (!widget.compact || !widget.audioOn)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!widget.audioOn) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(NxI.microphoneSlash, size: 13, color: Color(0xFFFCA5A5))),
                  if (!widget.compact) Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _CallView extends StatefulWidget {
  const _CallView({required this.service});
  final CallService service;

  @override
  State<_CallView> createState() => _CallViewState();
}

class _CallViewState extends State<_CallView> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final people = s.participants.values.toList();
    final outgoing = s.phase == CallPhase.outgoing;
    final elapsed = s.startedAt == null ? Duration.zero : DateTime.now().difference(s.startedAt!);
    final group = s.group && people.length > 1;
    final self = CallVideoTile(stream: s.media?.localStream, name: tr('คุณ'), videoOn: s.videoOn, mirror: true, audioOn: !s.muted, compact: !group);
    Widget main;
    if (outgoing || people.isEmpty) {
      final invitees = (s.call?['invitees'] is List ? s.call!['invitees'] as List : const []).whereType<Map>().toList();
      main = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Pulse(child: NxAvatar(label: s.title, size: 108)),
        const SizedBox(height: 20),
        Text(s.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(tr(outgoing ? (s.group ? 'กำลังโทรกลุ่ม…' : 'กำลังโทร…') : 'กำลังเชื่อมต่อ…'), style: const TextStyle(color: Colors.white70)),
        if (s.group && invitees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final i in invitees)
                Chip(
                  avatar: NxAvatar(label: '${i['name']}', size: 22),
                  label: Text('${i['name']} · ${tr(switch ('${i['status']}') {
                    'joined' => 'อยู่ในสาย',
                    'declined' => 'ปฏิเสธ',
                    'missed' => 'ไม่รับสาย',
                    'busy' => 'สายไม่ว่าง',
                    _ => 'กำลังเรียก',
                  })}'),
                ),
            ]),
          ),
      ]);
    } else if (!group) {
      final p = people.first;
      main = CallVideoTile(stream: p.stream, name: p.name, videoOn: p.video || p.screen, audioOn: p.audio, connecting: p.state != 'connected');
    } else {
      final tiles = [
        for (final p in people) CallVideoTile(stream: p.stream, name: p.name, videoOn: p.video || p.screen, audioOn: p.audio, connecting: p.state != 'connected'),
        self,
      ];
      main = GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
      );
    }
    return Material(
      key: const ValueKey('call-screen'),
      color: const Color(0xFF020617),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              IconButton(
                key: const ValueKey('call-minimize'),
                tooltip: tr('ย่อ'),
                onPressed: () => s.setMinimized(true),
                icon: const Icon(NxI.minimize, color: Colors.white),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    outgoing ? tr('กำลังเรียก…') : '${_fmt(elapsed)}${s.group ? ' · ${tr('${people.length + 1} คน')}' : ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Stack(children: [
                Positioned.fill(child: main),
                if (!group && !outgoing && people.isNotEmpty && s.videoOn)
                  Positioned(right: 10, top: 10, width: 110, height: 160, child: self),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 22),
            child: Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 14, children: [
              _RoundButton(key: const ValueKey('call-mute'), icon: s.muted ? NxI.microphoneSlash : NxI.microphone, label: s.muted ? 'เปิดไมค์' : 'ปิดไมค์', active: s.muted, onTap: s.toggleMute),
              _RoundButton(key: const ValueKey('call-camera'), icon: s.videoOn ? NxI.videoCamera : NxI.videoCameraSlash, label: s.videoOn ? 'ปิดกล้อง' : 'เปิดกล้อง', active: !s.videoOn, onTap: s.toggleVideo),
              if (s.videoOn) _RoundButton(key: const ValueKey('call-flip'), icon: NxI.cameraRotate, label: 'สลับกล้อง', onTap: s.switchCamera),
              _RoundButton(key: const ValueKey('call-speaker'), icon: s.speakerOn ? NxI.speakerHigh : NxI.speakerLow, label: 'ลำโพง', active: s.speakerOn, onTap: s.toggleSpeaker),
              _RoundButton(key: const ValueKey('call-end'), icon: NxI.phoneX, label: 'วางสาย', color: const Color(0xFFEF4444), onTap: s.hangUp),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Floating, draggable call bubble while the user keeps using the app.
class _Bubble extends StatefulWidget {
  const _Bubble({required this.service});
  final CallService service;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  Offset? _pos;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const w = 96.0, h = 132.0;
    final pos = _pos ?? Offset(size.width - w - 12, pad.top + 72);
    final s = widget.service;
    final p = s.participants.values.firstOrNull;
    final elapsed = s.startedAt == null ? Duration.zero : DateTime.now().difference(s.startedAt!);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: w,
      height: h,
      child: GestureDetector(
        key: const ValueKey('call-bubble'),
        onTap: () => s.setMinimized(false),
        onPanUpdate: (d) => setState(() {
          final n = (_pos ?? pos) + d.delta;
          _pos = Offset(n.dx.clamp(4, size.width - w - 4), n.dy.clamp(pad.top + 4, size.height - h - pad.bottom - 4));
        }),
        child: Material(
          elevation: 10,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            CallVideoTile(stream: p?.stream, name: p?.name ?? s.title, videoOn: p != null && (p.video || p.screen), audioOn: p?.audio ?? true, compact: true),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                child: Text(s.phase == CallPhase.outgoing ? tr('กำลังเรียก') : _fmt(elapsed), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                onTap: s.hangUp,
                child: const CircleAvatar(radius: 12, backgroundColor: Color(0xFFEF4444), child: Icon(NxI.phoneX, size: 13, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
