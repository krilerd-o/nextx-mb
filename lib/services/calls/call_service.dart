import 'dart:async';

import 'package:flutter/foundation.dart';

import '../realtime_service.dart';
import 'call_media.dart';

/// Signaling transport (Socket.io `rtc:*`) — [RealtimeService] in the app, a fake in tests.
abstract class CallSignaling {
  Stream<RealtimeEvent> get events;
  String? get socketId;
  bool get connected;
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data);
  void emit(String event, Map<String, dynamic> data);
}

class RealtimeCallSignaling implements CallSignaling {
  @override
  Stream<RealtimeEvent> get events => RealtimeService.instance.events;
  @override
  String? get socketId => RealtimeService.instance.socketId;
  @override
  bool get connected => RealtimeService.instance.connected;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) => RealtimeService.instance.emitAck(event, data);
  @override
  void emit(String event, Map<String, dynamic> data) => RealtimeService.instance.emit(event, data);
}

/// Phone-level call UI (CallKit / Android full-screen) — no-op in tests.
abstract class CallSystemUi {
  Future<void> showIncoming(Map<String, dynamic> call);
  Future<void> startOutgoing(Map<String, dynamic> call);
  Future<void> connected(String callId);
  Future<void> end(String callId);
}

class NoopCallSystemUi implements CallSystemUi {
  @override
  Future<void> showIncoming(Map<String, dynamic> call) async {}
  @override
  Future<void> startOutgoing(Map<String, dynamic> call) async {}
  @override
  Future<void> connected(String callId) async {}
  @override
  Future<void> end(String callId) async {}
}

enum CallPhase { idle, incoming, outgoing, active }

/// One remote person in the call (one peer connection per remote socket).
class CallParticipant {
  CallParticipant({required this.socketId, required this.peer, this.userId, this.name = '', this.avatar});
  final String socketId;
  final CallPeer peer;
  String? userId;
  String name;
  String? avatar;
  Object? stream;
  bool audio = true;
  bool video = false;
  bool screen = false;
  bool connected = true;
  String state = 'new';
  bool answerer = false;
  bool answered = false;
  bool makingOffer = false;
  bool ignoreOffer = false;
  bool polite = false;
  final pendingIce = <Map<String, dynamic>>[];
}

/// Text for server error codes (same as the web).
String callErrorText(String? code, {int max = 4}) => switch (code) {
      'already_in_call' => 'คุณอยู่ในสายอื่นอยู่',
      'not_member' => 'คุณไม่ได้อยู่ในห้องนี้',
      'no_one_to_call' => 'ไม่มีสมาชิกให้โทรหา',
      'too_many' => 'โทรกลุ่มได้สูงสุด $max คน — เลือกคนที่จะโทร',
      'call_full' => 'สายนี้มีผู้เข้าร่วมครบ $max คนแล้ว',
      'ended' => 'สายนี้จบไปแล้ว',
      'not_invited' => 'คุณไม่ได้รับเชิญในสายนี้',
      'no_socket' => 'ยังไม่ได้เชื่อมต่อ — ลองใหม่อีกครั้ง',
      'timeout' => 'เซิร์ฟเวอร์ไม่ตอบ ลองใหม่อีกครั้ง',
      'media' => 'เปิดไมค์/กล้องไม่ได้ — ตรวจสอบสิทธิ์ของแอป',
      _ => 'เซิร์ฟเวอร์ขัดข้อง ลองใหม่อีกครั้ง',
    };

/// Voice / video calls, 1:1 and mesh up to 4, same protocol as the NEXTX web (`rtc:*`).
///
/// The person who joins sends offers to everyone already in the call; existing people answer
/// (no glare). Later renegotiation (camera on, ICE restart) uses the perfect-negotiation rules.
class CallService extends ChangeNotifier {
  CallService({CallSignaling? signaling, CallMedia Function()? media, CallSystemUi? systemUi, this.myUserId})
      : _signal = signaling ?? RealtimeCallSignaling(),
        _mediaFactory = media,
        _system = systemUi ?? NoopCallSystemUi() {
    _sub = _signal.events.listen(_onEvent);
  }

  /// The app's instance (set in main when WebRTC is available).
  static CallService? instance;

  final CallSignaling _signal;
  final CallMedia Function()? _mediaFactory;
  final CallSystemUi _system;
  String? myUserId;
  StreamSubscription<RealtimeEvent>? _sub;

  CallPhase phase = CallPhase.idle;
  Map<String, dynamic>? call; // server call object
  Map<String, dynamic>? incoming;
  final participants = <String, CallParticipant>{};
  CallMedia? media;
  List<Map<String, dynamic>> _ice = const [
    {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
  ];
  bool muted = false;
  bool videoOn = false;
  bool speakerOn = false;
  bool minimized = false;
  DateTime? startedAt;
  String? notice;
  String? error;
  Timer? _noticeTimer;

  String? get callId => call?['call_id']?.toString() ?? incoming?['call_id']?.toString();
  bool get isVideo => call?['media'] == 'video' || videoOn;
  bool get group => call?['group'] == true;

  @override
  void dispose() {
    _sub?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _setNotice(String text) {
    notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Title shown for the current call (other person for 1:1, room for groups).
  String get title {
    final c = call ?? incoming;
    if (c == null) return '';
    if (c['group'] == true) return c['room_name']?.toString() ?? '';
    if ('${c['caller_id']}' != myUserId) return c['caller_name']?.toString() ?? '';
    final others = (c['invitees'] is List ? c['invitees'] as List : const []).whereType<Map>().where((i) => '${i['user_id']}' != myUserId);
    return others.isEmpty ? (c['room_name']?.toString() ?? '') : others.first['name']?.toString() ?? '';
  }

  void _loadIce(dynamic ice) {
    final list = ice is Map ? ice['ice_servers'] : null;
    if (list is List && list.isNotEmpty) _ice = [for (final s in list) if (s is Map) Map<String, dynamic>.from(s)];
    if (ice is Map) _relayOnly = ice['ice_transport_policy'] == 'relay' && ice['turn'] == true;
  }

  /// Settings → การโทร "ผ่าน TURN เสมอ".
  bool _relayOnly = false;

  Future<bool> _openMedia({required bool video}) async {
    final f = _mediaFactory;
    if (f == null) return true;
    final m = f();
    try {
      final cameraOk = await m.openLocal(video: video);
      media = m;
      videoOn = video && m.hasVideo;
      speakerOn = videoOn;
      if (video && !cameraOk) _setNotice('เปิดกล้องไม่ได้ — เข้าร่วมด้วยเสียง');
      await m.setMuted(muted);
      return true;
    } catch (e) {
      error = callErrorText('media');
      notifyListeners();
      return false;
    }
  }

  // ---- peers --------------------------------------------------------------

  void _sendSignal(String toSocket, Map<String, dynamic> data) {
    final id = call?['call_id'];
    if (id == null) return;
    _signal.emit('rtc:signal', {'call_id': id, 'to_socket_id': toSocket, 'data': data});
  }

  Future<CallParticipant?> _ensurePeer(String sid, Map<String, dynamic> info, {required bool answerer}) async {
    final existing = participants[sid];
    if (existing != null) {
      _applyInfo(existing, info);
      return existing;
    }
    final m = media;
    if (m == null) return null;
    final peer = await m.createPeer(_ice, relayOnly: _relayOnly);
    final p = CallParticipant(socketId: sid, peer: peer)
      ..answerer = answerer
      ..polite = (_signal.socketId ?? '').compareTo(sid) < 0;
    _applyInfo(p, info);
    participants[sid] = p;
    peer.onCandidate = (c) => _sendSignal(sid, {'type': 'candidate', 'candidate': c});
    peer.onStream = (s) {
      p.stream = s;
      notifyListeners();
    };
    peer.onState = (s) {
      p.state = s;
      if (s == 'failed' && !p.polite) _restart(p);
      if (s == 'connected' && startedAt == null) startedAt = DateTime.now();
      notifyListeners();
    };
    peer.onNegotiationNeeded = () => _negotiate(p);
    if (!answerer) {
      await peer.addLocalTracks();
      await _negotiate(p); // flutter_webrtc may not fire negotiationneeded before the listener is set
    }
    notifyListeners();
    return p;
  }

  void _applyInfo(CallParticipant p, Map<String, dynamic> info) {
    if (info['user_id'] != null) p.userId = '${info['user_id']}';
    if ((info['name']?.toString() ?? '').isNotEmpty) p.name = info['name'].toString();
    if (info['avatar'] != null) p.avatar = info['avatar'].toString();
    if (info.containsKey('audio')) p.audio = info['audio'] != false;
    if (info.containsKey('video')) p.video = info['video'] == true;
    if (info.containsKey('screen')) p.screen = info['screen'] == true;
    if (info.containsKey('connected')) p.connected = info['connected'] != false;
  }

  Future<void> _negotiate(CallParticipant p) async {
    if (p.answerer && !p.answered) return;
    if (p.makingOffer) return;
    try {
      p.makingOffer = true;
      final offer = await p.peer.createOffer();
      _sendSignal(p.socketId, offer);
    } catch (e) {
      debugPrint('[call] offer: $e');
    } finally {
      p.makingOffer = false;
    }
  }

  Future<void> _restart(CallParticipant p) async {
    try {
      final offer = await p.peer.createOffer(iceRestart: true);
      _sendSignal(p.socketId, offer);
    } catch (_) {}
  }

  Future<void> _onSignal(Map<String, dynamic> d) async {
    if (call == null || d['call_id'] != call!['call_id']) return;
    final sid = d['from_socket_id']?.toString();
    final data = d['data'] is Map ? Map<String, dynamic>.from(d['data'] as Map) : null;
    if (sid == null || data == null) return;
    final p = await _ensurePeer(sid, {'user_id': d['from_user_id']}, answerer: true);
    if (p == null) return;
    final type = data['type'];
    try {
      if (type == 'offer' || type == 'answer') {
        final collision = type == 'offer' && (p.makingOffer || p.peer.signalingState != 'stable');
        p.ignoreOffer = !p.polite && collision;
        if (p.ignoreOffer) return;
        if (collision) await p.peer.rollback();
        await p.peer.setRemote(data);
        for (final c in [...p.pendingIce]) {
          await p.peer.addCandidate(c).catchError((_) {});
        }
        p.pendingIce.clear();
        if (type == 'offer') {
          if (p.answerer && !p.answered) await p.peer.attachLocalToOffered();
          final answer = await p.peer.createAnswer();
          p.answered = true;
          _sendSignal(sid, answer);
        }
      } else if (type == 'candidate' && data['candidate'] is Map) {
        final c = Map<String, dynamic>.from(data['candidate'] as Map);
        if (!p.peer.hasRemoteDescription) {
          p.pendingIce.add(c);
        } else {
          await p.peer.addCandidate(c).catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('[call] signal: $e');
    }
  }

  Future<void> _connectTo(List peers) async {
    for (final raw in peers) {
      if (raw is! Map) continue;
      final peer = Map<String, dynamic>.from(raw);
      if ('${peer['user_id']}' == myUserId) continue;
      final sid = peer['socket_id']?.toString();
      if (sid == null) continue;
      await _ensurePeer(sid, peer, answerer: false);
    }
  }

  Future<void> _closePeer(String sid) async {
    final p = participants.remove(sid);
    await p?.peer.close();
  }

  Future<void> _cleanup() async {
    final id = callId;
    for (final sid in [...participants.keys]) {
      await _closePeer(sid);
    }
    await media?.closeLocal();
    media = null;
    call = null;
    phase = incoming != null ? CallPhase.incoming : CallPhase.idle;
    muted = false;
    videoOn = false;
    speakerOn = false;
    minimized = false;
    startedAt = null;
    if (id != null) await _system.end(id);
    notifyListeners();
  }

  // ---- public API ---------------------------------------------------------

  /// Start a call in a chat room. Returns null on success, or the server error code
  /// (`too_many` → let the user pick up to 3 people and call again with [userIds]).
  Future<String?> start({required String roomId, required String roomTitle, required bool video, List<String>? userIds}) async {
    error = null;
    if (phase == CallPhase.active || phase == CallPhase.outgoing) {
      error = callErrorText('already_in_call');
      notifyListeners();
      return 'already_in_call';
    }
    if (!_signal.connected) {
      error = callErrorText('no_socket');
      notifyListeners();
      return 'no_socket';
    }
    phase = CallPhase.outgoing;
    call = {'media': video ? 'video' : 'audio', 'room_name': roomTitle, 'chat_room_id': roomId, 'caller_id': myUserId, 'invitees': const []};
    notifyListeners();
    if (!await _openMedia(video: video)) {
      phase = CallPhase.idle;
      call = null;
      notifyListeners();
      return 'media';
    }
    final res = await _signal.emitAck('rtc:start', {
      'chat_room_id': int.tryParse(roomId) ?? roomId,
      'media': video ? 'video' : 'audio',
      if (userIds != null && userIds.isNotEmpty) 'user_ids': [for (final u in userIds) int.tryParse(u) ?? u],
    });
    if (res['ok'] != true) {
      final code = res['error']?.toString();
      if (code == 'call_in_progress' && res['call'] is Map) {
        // Someone is already talking in this room → join that call.
        call = Map<String, dynamic>.from(res['call'] as Map);
        final joined = await _signal.emitAck('rtc:accept', {'call_id': call!['call_id']});
        if (joined['ok'] == true) {
          await _becomeActive(joined);
          return null;
        }
      }
      await media?.closeLocal();
      media = null;
      call = null;
      phase = CallPhase.idle;
      if (code != 'too_many') error = callErrorText(code, max: (res['max'] as num?)?.toInt() ?? 4);
      notifyListeners();
      return code ?? 'server_error';
    }
    _loadIce(res['ice']);
    call = Map<String, dynamic>.from(res['call'] as Map);
    if (res['busy'] == true) {
      await _cleanup();
      _setNotice('สายไม่ว่าง');
      return null;
    }
    await _system.startOutgoing(call!);
    notifyListeners();
    return null;
  }

  Future<void> _becomeActive(Map<String, dynamic> res) async {
    _loadIce(res['ice']);
    call = Map<String, dynamic>.from(res['call'] as Map);
    incoming = null;
    phase = CallPhase.active;
    startedAt ??= DateTime.now();
    notifyListeners();
    await _system.connected('${call!['call_id']}');
    await _connectTo(res['peers'] is List ? res['peers'] as List : const []);
  }

  Future<void> accept({bool? video}) async {
    final inc = incoming;
    if (inc == null) return;
    final withVideo = video ?? inc['media'] == 'video';
    if (!await _openMedia(video: withVideo)) return;
    final res = await _signal.emitAck('rtc:accept', {'call_id': inc['call_id']});
    incoming = null;
    if (res['ok'] != true) {
      await media?.closeLocal();
      media = null;
      phase = call == null ? CallPhase.idle : phase;
      error = callErrorText(res['error']?.toString());
      notifyListeners();
      return;
    }
    await _becomeActive(res);
  }

  /// Accept a call that rang while the app was closed (CallKit / notification). Waits for the socket.
  Future<void> acceptById(String id, {Map<String, dynamic>? hint, bool? video}) async {
    for (var i = 0; i < 40 && !_signal.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (incoming?['call_id'] != id) {
      final sync = await _signal.emitAck('rtc:sync', const {});
      final ringing = (sync['ringing'] is List ? sync['ringing'] as List : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e));
      incoming = ringing.where((c) => c['call_id'] == id).firstOrNull ?? (hint == null ? null : {...hint, 'call_id': id});
    }
    if (incoming == null) return;
    await accept(video: video);
  }

  Future<void> decline() async {
    final inc = incoming;
    if (inc == null) return;
    incoming = null;
    if (phase == CallPhase.incoming) phase = CallPhase.idle;
    notifyListeners();
    _signal.emit('rtc:decline', {'call_id': inc['call_id']});
    await _system.end('${inc['call_id']}');
  }

  Future<void> hangUp() async {
    final id = call?['call_id'];
    if (id != null) _signal.emit('rtc:leave', {'call_id': id});
    await _cleanup();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await media?.setMuted(muted);
    _announce({'audio': !muted});
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    final m = media;
    if (m == null) return;
    videoOn = await m.setVideo(!videoOn);
    if (videoOn && call != null) call = {...call!, 'media': 'video'};
    _announce({'video': videoOn});
    notifyListeners();
  }

  Future<void> switchCamera() async => media?.switchCamera();

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await media?.setSpeaker(speakerOn);
    notifyListeners();
  }

  void setMinimized(bool v) {
    minimized = v;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void _announce(Map<String, dynamic> patch) {
    final id = call?['call_id'];
    if (id != null) _signal.emit('rtc:media', {'call_id': id, ...patch});
  }

  // ---- socket events ------------------------------------------------------

  Future<void> _onEvent(RealtimeEvent e) async {
    final d = e.data;
    switch (e.type) {
      case RealtimeService.connectedEvent:
        await _onConnected();
      case 'rtc:ring':
        if ('${d['caller_id']}' == myUserId || d['call_id'] == call?['call_id']) return;
        if (phase == CallPhase.active || phase == CallPhase.outgoing) return; // busy here
        incoming = d;
        phase = CallPhase.incoming;
        notifyListeners();
        await _system.showIncoming(d);
      case 'rtc:ring_stop':
        if (incoming?['call_id'] != d['call_id']) return;
        incoming = null;
        if (phase == CallPhase.incoming) phase = call == null ? CallPhase.idle : phase;
        if (d['reason'] == 'cancelled' || d['reason'] == 'timeout') _setNotice('สายที่ไม่ได้รับ');
        await _system.end('${d['call_id']}');
        notifyListeners();
      case 'rtc:joined':
        if (call == null || d['call_id'] != call!['call_id'] || '${d['user_id']}' == myUserId) return;
        final replaced = d['replaced_socket_id']?.toString();
        if (replaced != null && replaced != d['socket_id']) await _closePeer(replaced);
        await _ensurePeer('${d['socket_id']}', d, answerer: true);
        if (phase == CallPhase.outgoing) {
          phase = CallPhase.active;
          startedAt = DateTime.now();
          await _system.connected('${call!['call_id']}');
        }
        notifyListeners();
      case 'rtc:left':
        if (call?['call_id'] != d['call_id']) return;
        await _closePeer('${d['socket_id']}');
        notifyListeners();
      case 'rtc:declined':
        if (call?['call_id'] != d['call_id'] || !group) return;
        final who = (call!['invitees'] is List ? call!['invitees'] as List : const [])
            .whereType<Map>()
            .where((i) => '${i['user_id']}' == '${d['user_id']}')
            .firstOrNull?['name'];
        _setNotice(d['reason'] == 'timeout' ? '${who ?? ''} ไม่ได้รับสาย' : '${who ?? ''} ปฏิเสธสาย');
      case 'rtc:updated':
        if (call?['call_id'] == d['call_id']) {
          call = {...call!, ...d};
          notifyListeners();
        } else if (incoming?['call_id'] == d['call_id']) {
          incoming = {...incoming!, ...d};
          notifyListeners();
        }
      case 'rtc:media':
        if (call?['call_id'] != d['call_id']) return;
        final p = participants['${d['socket_id']}'];
        if (p == null) return;
        _applyInfo(p, d);
        notifyListeners();
      case 'rtc:signal':
        await _onSignal(d);
      case 'rtc:ended':
        if (incoming?['call_id'] == d['call_id']) {
          incoming = null;
          if (phase == CallPhase.incoming) phase = CallPhase.idle;
        }
        if (call?['call_id'] != d['call_id']) {
          notifyListeners();
          return;
        }
        final wasOutgoing = phase == CallPhase.outgoing;
        await _cleanup();
        if (wasOutgoing) {
          final reason = d['reason'];
          if (reason == 'declined') _setNotice('ปลายสายปฏิเสธสาย');
          if (reason == 'no_answer') _setNotice('ไม่มีผู้รับสาย');
          if (reason == 'busy') _setNotice('สายไม่ว่าง');
        }
    }
  }

  Future<void> _onConnected() async {
    final c = call;
    if (c != null && phase == CallPhase.active) {
      // Network came back → take my seat again and reconnect to everyone.
      final res = await _signal.emitAck('rtc:rejoin', {'call_id': c['call_id']});
      if (res['ok'] != true) {
        await _cleanup();
        return;
      }
      for (final sid in [...participants.keys]) {
        await _closePeer(sid);
      }
      _loadIce(res['ice']);
      await _connectTo(res['peers'] is List ? res['peers'] as List : const []);
      return;
    }
    if (incoming == null && phase == CallPhase.idle) {
      final sync = await _signal.emitAck('rtc:sync', const {});
      final ringing = sync['ringing'];
      if (ringing is List && ringing.isNotEmpty && ringing.first is Map) {
        await _onEvent(RealtimeEvent('rtc:ring', Map<String, dynamic>.from(ringing.first as Map)));
      }
    }
  }
}
