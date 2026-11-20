import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/minutes/minute_board.dart';
import '../../core/minutes/minutes.dart';
import '../audio/mic_tap.dart';
import '../audio/pcm.dart';
import '../calls/call_mic_tap_native.dart';
import '../realtime_service.dart';
import 'minute_board_controller.dart';

/// One live caption line in a room.
class RoomCaption {
  const RoomCaption({required this.seq, required this.speaker, required this.text, this.identity = '', this.partial = false, this.startMs = 0});
  final int seq;
  final String speaker;
  final String identity;
  final String text;
  final bool partial;
  final int startMs;
}

class RoomChatMessage {
  const RoomChatMessage({required this.from, required this.text, required this.at, this.mine = false, this.id});
  final int? id;
  final String from;
  final String text;
  final DateTime at;
  final bool mine;
}

/// The LiveKit side of a room (tests replace it).
abstract class RoomMedia extends ChangeNotifier {
  Future<void> connect(String url, String token, {required bool micOn, required bool camOn});
  Future<void> disconnect();
  Future<void> setMic(bool on);
  Future<void> setCamera(bool on);
  Future<void> flipCamera();
  Future<void> setScreenShare(bool on);
  bool get micOn;
  bool get camOn;
  bool get screenOn;
  List<lk.Participant> get participants;
  lk.Participant? get speaker;
  String? get localAudioTrackId;
  Future<void> sendData(Map<String, dynamic> data, {String topic});
  Stream<(String from, String topic, Map<String, dynamic> data)> get data;

  /// LiveKit room metadata (JSON): `{stage:{pin, by}}` when the host pinned something for everyone.
  String? get roomMetadata => null;
}

class LivekitRoomMedia extends RoomMedia {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final _data = StreamController<(String, String, Map<String, dynamic>)>.broadcast();
  bool _screen = false;

  @override
  Future<void> connect(String url, String token, {required bool micOn, required bool camOn}) async {
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultVideoPublishOptions: lk.VideoPublishOptions(simulcast: true),
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(noiseSuppression: true, echoCancellation: true),
      ),
    );
    _room = room;
    room.addListener(notifyListeners);
    _listener = room.createListener()
      ..on<lk.ParticipantEvent>((_) => notifyListeners())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => notifyListeners())
      ..on<lk.RoomMetadataChangedEvent>((_) => notifyListeners())
      ..on<lk.DataReceivedEvent>((e) {
        try {
          final m = jsonDecode(utf8.decode(e.data));
          if (m is Map) _data.add((e.participant?.name ?? e.participant?.identity ?? '', e.topic ?? '', Map<String, dynamic>.from(m)));
        } catch (_) {}
      });
    await room.connect(url, token, connectOptions: const lk.ConnectOptions(autoSubscribe: true));
    await room.localParticipant?.setMicrophoneEnabled(micOn);
    if (camOn) await room.localParticipant?.setCameraEnabled(true);
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    await _listener?.dispose();
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }

  @override
  Future<void> setMic(bool on) async => _room?.localParticipant?.setMicrophoneEnabled(on);
  @override
  Future<void> setCamera(bool on) async => _room?.localParticipant?.setCameraEnabled(on);
  @override
  Future<void> flipCamera() async {
    final pub = _room?.localParticipant?.videoTrackPublications.where((p) => p.source == lk.TrackSource.camera).firstOrNull;
    final t = pub?.track;
    if (t is lk.LocalVideoTrack) {
      final pos = t.currentOptions is lk.CameraCaptureOptions ? (t.currentOptions as lk.CameraCaptureOptions).cameraPosition : lk.CameraPosition.front;
      await t.setCameraPosition(pos == lk.CameraPosition.front ? lk.CameraPosition.back : lk.CameraPosition.front);
    }
  }

  @override
  Future<void> setScreenShare(bool on) async {
    await _room?.localParticipant?.setScreenShareEnabled(on);
    _screen = on;
    notifyListeners();
  }

  @override
  bool get micOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;
  @override
  bool get camOn => _room?.localParticipant?.isCameraEnabled() ?? false;
  @override
  bool get screenOn => _screen;

  @override
  List<lk.Participant> get participants {
    final r = _room;
    if (r == null) return const [];
    final list = <lk.Participant>[?r.localParticipant, ...r.remoteParticipants.values];
    // Speaking / camera-on people first, so the visible grid shows them.
    list.sort((a, b) {
      int score(lk.Participant p) => (p.isSpeaking ? 4 : 0) + (p.isCameraEnabled() ? 2 : 0) + (p is lk.LocalParticipant ? 1 : 0);
      return score(b).compareTo(score(a));
    });
    return list;
  }

  @override
  lk.Participant? get speaker => _room?.activeSpeakers.firstOrNull;

  @override
  String? get localAudioTrackId =>
      _room?.localParticipant?.audioTrackPublications.where((p) => p.source == lk.TrackSource.microphone).firstOrNull?.track?.mediaStreamTrack.id;

  @override
  Future<void> sendData(Map<String, dynamic> data, {String topic = 'chat'}) async =>
      _room?.localParticipant?.publishData(utf8.encode(jsonEncode(data)), reliable: true, topic: topic);

  @override
  Stream<(String, String, Map<String, dynamic>)> get data => _data.stream;

  @override
  String? get roomMetadata => _room?.metadata;

  @override
  void dispose() {
    _room?.removeListener(notifyListeners);
    _data.close();
    super.dispose();
  }
}

/// A meeting room session: LiveKit media + ไอแซค live captions / translation over Socket.IO + chat,
/// reactions and raised hands on the LiveKit data channel.
class MinuteRoomSession extends ChangeNotifier {
  MinuteRoomSession({
    required this.meetingId,
    required this.roomCode,
    required this.ticket,
    required this.identity,
    required this.role,
    required this.name,
    RoomMedia? media,
    RealtimeService? realtime,
    CallMicTap Function()? mic,
    Map<String, dynamic>? stage,
    this.boardMode = 'all',
  }) : media = media ?? LivekitRoomMedia(),
       _rt = realtime ?? RealtimeService.instance,
       _micFactory = mic,
       stagePin = StagePin.fromJson(stage) {
    this.media.addListener(_onMedia);
    board = MinuteBoardController(meetingId: meetingId, ticket: ticket, realtime: _rt);
  }

  /// Room setting `board`: all | host | off.
  final String boardMode;
  bool get boardOn => boardMode != 'off' && meetingId.isNotEmpty;

  /// Notes / checklist / board / sketch of this meeting (live, also for guests).
  late final MinuteBoardController board;

  /// Pin for everyone (host) — from the join answer, room metadata and `stage` data messages.
  StagePin? stagePin;

  /// My own pin (only my screen).
  StagePin? localPin;

  /// I chose my own view while the host pinned something.
  bool stageOverride = false;
  String? _lastMeta;

  void _onMedia() {
    final meta = media.roomMetadata;
    if (meta != null && meta != _lastMeta) {
      _lastMeta = meta;
      try {
        final m = jsonDecode(meta);
        if (m is Map) _setStage(StagePin.fromJson(m['stage']));
      } catch (_) {}
    }
    notifyListeners();
  }

  void _setStage(StagePin? pin) {
    final changed = pin?.identity != stagePin?.identity || pin?.source != stagePin?.source;
    stagePin = pin;
    if (changed) stageOverride = false;
  }

  /// After the host's pin call (or a stage message).
  void applyStage(Map<String, dynamic>? stage) {
    _setStage(StagePin.fromJson(stage));
    notifyListeners();
  }

  void pinForMe(StagePin? pin) {
    localPin = pin;
    notifyListeners();
  }

  void setStageOverride(bool on) {
    stageOverride = on;
    notifyListeners();
  }

  final String meetingId;
  final String roomCode;
  final String ticket;
  final String identity;
  final String role;
  final String name;
  final RoomMedia media;
  final RealtimeService _rt;
  final CallMicTap Function()? _micFactory;

  bool get isHost => role == 'host' || role == 'cohost';

  bool connected = false;
  String? error;
  bool captionsOn = false;
  bool transcribing = false;
  List<String> translateLangs = const [];
  String? captionLang;
  final captions = ValueNotifier<List<RoomCaption>>(const []);
  final translated = ValueNotifier<Map<int, String>>(const {});
  final chat = ValueNotifier<List<RoomChatMessage>>(const []);
  final reactions = StreamController<(String, String)>.broadcast();
  final hands = ValueNotifier<Set<String>>(const {});
  final waiting = ValueNotifier<List<(String identity, String name)>>(const []);
  bool handUp = false;

  StreamSubscription<RealtimeEvent>? _evSub;
  StreamSubscription<(String, String, Map<String, dynamic>)>? _dataSub;
  CallMicTap? _mic;
  StreamSubscription<Uint8List>? _micSub;
  DateTime _lastVoice = DateTime.fromMillisecondsSinceEpoch(0);

  /// Energy gate: only speech (plus 1.2 s after it) is sent for captions.
  static const _voiceLevel = 0.035;
  static const _hangover = Duration(milliseconds: 1200);

  // ── one live room in the app (back only minimises it; Leave / End close it)

  /// The room the app is in now (a floating bubble shows it while its screen is closed).
  static final active = ValueNotifier<MinuteRoomSession?>(null);

  /// Title / LiveKit address for reopening the screen from the bubble.
  String title = '';
  String url = '';
  String token = '';
  DateTime? startedAt;

  /// Business the room belongs to (requests about it go there after a business switch).
  String? businessId;

  /// Open room screens (0 → the bubble shows).
  int screens = 0;
  bool get screenOpen => screens > 0;
  // Called from a screen's initState / dispose (inside a build): tell listeners right after it.
  void screenShown() {
    screens++;
    _notifySoon();
  }

  void screenHidden() {
    if (screens > 0) screens--;
    _notifySoon();
  }

  void _notifySoon() => scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });

  bool _started = false;
  bool get started => _started;
  bool closed = false;

  /// Why the room closed by itself (removed by the host / ended), for the UI.
  String? closedReason;

  /// Server-side room chat (saved with the meeting); old servers: LiveKit data messages.
  bool serverChat = false;

  Future<void> start({required String url, required String token, bool micOn = false, bool camOn = false}) async {
    if (_started) return;
    _started = true;
    this.url = url;
    this.token = token;
    startedAt ??= DateTime.now();
    if (active.value != this) active.value = this;
    try {
      await media.connect(url, token, micOn: micOn, camOn: camOn);
      connected = true;
    } catch (e) {
      error = 'เชื่อมต่อห้องประชุมไม่ได้';
      notifyListeners();
      return;
    }
    _dataSub = media.data.listen(_onData);
    _evSub = _rt.events.listen(_onEvent);
    if (boardOn) unawaited(board.start());
    final ack = await _rt.emitAck('minute:room_join', {'ticket': ticket});
    if (ack['ok'] == true) {
      captionsOn = ack['captions'] == true;
      translateLangs = [for (final l in (ack['langs'] as List? ?? const [])) '$l'];
      _applyChatHistory(ack);
      if (ack['transcribe'] == true && micOn) await _startCaptions();
    }
    notifyListeners();
  }

  // ── my microphone → captions (only while unmuted)

  Future<void> _startCaptions() async {
    if (transcribing) return;
    final ack = await _rt.emitAck('minute:room_stt', {'ticket': ticket, 'on': true});
    if (ack['ok'] != true) return;
    final mic = _micFactory?.call() ?? FallbackMicTap(WebRtcMicTap(() => media.localAudioTrackId), RecordMicTap());
    try {
      final stream = await mic.start();
      _mic = mic;
      _micSub = stream.listen(_onPcm);
      transcribing = true;
    } catch (_) {
      _rt.emit('minute:room_stt', {'ticket': ticket, 'on': false});
    }
    notifyListeners();
  }

  Future<void> _stopCaptions() async {
    if (!transcribing) return;
    transcribing = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic?.stop();
    _mic = null;
    _rt.emit('minute:room_stt', {'ticket': ticket, 'on': false});
    notifyListeners();
  }

  void _onPcm(Uint8List pcm) {
    final now = DateTime.now();
    if (pcmLevel(pcm) >= _voiceLevel) _lastVoice = now;
    if (now.difference(_lastVoice) <= _hangover) _rt.emitRoomAudio(pcm);
  }

  // ── controls

  Future<void> toggleMic() async {
    final on = !media.micOn;
    await media.setMic(on);
    on ? await _startCaptions() : await _stopCaptions();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    await media.setCamera(!media.camOn);
    notifyListeners();
  }

  Future<void> flipCamera() => media.flipCamera();

  Future<void> toggleScreen() => media.setScreenShare(!media.screenOn);

  Future<void> setCaptionLang(String? lang) async {
    captionLang = lang;
    translated.value = const {};
    notifyListeners();
    await _rt.emitAck('minute:room_lang', {'ticket': ticket, 'lang': lang});
  }

  void _applyChatHistory(Map<String, dynamic> ack) {
    if (!ack.containsKey('chat_enabled')) return;
    serverChat = ack['chat_enabled'] == true;
    final items = ack['chat'];
    if (items is! List) return;
    final hist = [for (final c in items) if (c is Map) _chatOf(Map<String, dynamic>.from(c))];
    // Keep lines that arrived before the history (same id → once).
    final known = {for (final m in hist) if (m.id != null) m.id};
    chat.value = [...hist, ...chat.value.where((m) => m.id == null || !known.contains(m.id))];
  }

  RoomChatMessage _chatOf(Map<String, dynamic> c) => RoomChatMessage(
        id: (c['id'] as num?)?.toInt(),
        from: '${c['name'] ?? ''}',
        text: '${c['text'] ?? ''}',
        at: DateTime.tryParse('${c['at'] ?? ''}')?.toLocal() ?? DateTime.now(),
        mine: '${c['identity'] ?? ''}' == identity,
      );

  /// Sends a chat line. Saved with the meeting (server chat); false when it was refused.
  Future<bool> sendChat(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (serverChat) {
      final ack = await _rt.emitAck('minute:chat_send', {'ticket': ticket, 'text': t});
      if (ack['ok'] != true) {
        error = switch ('${ack['error'] ?? ''}') {
          'chat_off' => 'ผู้จัดปิดแชทในห้องนี้',
          'rate_limited' => 'ส่งเร็วเกินไป — รอสักครู่',
          _ => 'ส่งข้อความไม่สำเร็จ',
        };
        notifyListeners();
        return false;
      }
      final item = ack['item'];
      chat.value = [...chat.value, item is Map ? _chatOf(Map<String, dynamic>.from(item)) : RoomChatMessage(from: name, text: t, at: DateTime.now(), mine: true)];
      return true;
    }
    await media.sendData({'type': 'chat', 'text': t, 'name': name}, topic: 'chat');
    chat.value = [...chat.value, RoomChatMessage(from: name, text: t, at: DateTime.now(), mine: true)];
    return true;
  }

  Future<void> react(String emoji) async {
    await media.sendData({'type': 'reaction', 'emoji': emoji, 'name': name}, topic: 'reaction');
    reactions.add((name, emoji));
  }

  Future<void> toggleHand() async {
    handUp = !handUp;
    await media.sendData({'type': 'hand', 'up': handUp, 'identity': identity, 'name': name}, topic: 'hand');
    final h = {...hands.value};
    handUp ? h.add(name) : h.remove(name);
    hands.value = h;
    notifyListeners();
  }

  void _onData((String, String, Map<String, dynamic>) e) {
    final (from, topic, d) = e;
    switch (d['type'] ?? topic) {
      case 'chat':
        // Server chat: every line arrives over the socket (and is saved); ignore the LiveKit copy.
        if (serverChat) return;
        chat.value = [...chat.value, RoomChatMessage(from: '${d['name'] ?? from}', text: '${d['text'] ?? ''}', at: DateTime.now())];
      case 'reaction':
        reactions.add(('${d['name'] ?? from}', '${d['emoji'] ?? '👍'}'));
      case 'stop_share':
      case 'share_takeover':
        // Phones do not present yet; nothing to stop here.
        break;
      case 'stage':
        applyStage(d['stage'] is Map ? Map<String, dynamic>.from(d['stage'] as Map) : null);
      case 'hand':
        final h = {...hands.value};
        d['up'] == true ? h.add('${d['name'] ?? from}') : h.remove('${d['name'] ?? from}');
        hands.value = h;
    }
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    switch (e.type) {
      case 'minute:caption':
        final c = RoomCaption(
          seq: (d['seq'] as num?)?.toInt() ?? 0,
          speaker: '${d['speaker'] ?? ''}',
          identity: '${d['identity'] ?? ''}',
          text: '${d['text'] ?? ''}',
          partial: d['partial'] == true,
          startMs: (d['start_ms'] as num?)?.toInt() ?? 0,
        );
        final list = [...captions.value];
        final i = list.indexWhere((x) => x.seq == c.seq);
        if (i >= 0) {
          if (!list[i].partial && c.partial) return;
          list[i] = c;
        } else {
          list.add(c);
          if (list.length > 300) list.removeRange(0, list.length - 300);
        }
        captions.value = list;
      case 'minute:caption_tr':
        if (d['lang'] != captionLang) return;
        final seq = (d['seq'] as num?)?.toInt();
        if (seq != null) translated.value = {...translated.value, seq: '${d['text'] ?? ''}'};
      case 'minute:room_waiting':
        if (!isHost) return;
        waiting.value = [...waiting.value.where((w) => w.$1 != '${d['identity']}'), ('${d['identity']}', '${d['name'] ?? ''}')];
      case 'minute:chat':
        final item = d['item'];
        if (item is! Map) return;
        final m = _chatOf(Map<String, dynamic>.from(item));
        if (m.id != null && chat.value.any((x) => x.id == m.id)) return;
        chat.value = [...chat.value, m];
      case 'minute:room_removed':
        if ('${d['identity'] ?? ''}' != identity) return;
        closedReason = 'removed';
        unawaited(close());
      case RealtimeService.connectedEvent:
        unawaited(_rt.emitAck('minute:room_join', {'ticket': ticket, 'lang': captionLang}).then((ack) {
          // Back online: lines sent meanwhile come with the history.
          if (ack['ok'] == true) _applyChatHistory(ack);
        }));
    }
  }

  void admitted(String identity) => waiting.value = waiting.value.where((w) => w.$1 != identity).toList();

  Future<void> leave() async {
    await _stopCaptions();
    await _evSub?.cancel();
    await _dataSub?.cancel();
    await media.disconnect();
    connected = false;
  }

  /// Leave for real (Leave / End / removed / sign-out): media off, the bubble goes, then dispose.
  Future<void> close() async {
    if (closed) return;
    closed = true;
    try {
      await leave();
    } catch (_) {}
    if (active.value == this) active.value = null;
    notifyListeners();
    // Screens still showing it close themselves on `closed`; dispose after they have.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (screens == 0) dispose();
    });
  }

  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (active.value == this) active.value = null;
    media.removeListener(_onMedia);
    board.dispose();
    unawaited(_micSub?.cancel());
    unawaited(_mic?.stop());
    _evSub?.cancel();
    _dataSub?.cancel();
    captions.dispose();
    translated.dispose();
    chat.dispose();
    hands.dispose();
    waiting.dispose();
    reactions.close();
    media.dispose();
    super.dispose();
  }
}

/// "ห้องนี้มีการบันทึก…" text of the consent notice.
String roomConsentText({required bool transcribe, required String record}) {
  final parts = [if (record != 'none') record == 'video' ? 'บันทึกภาพและเสียง' : 'บันทึกเสียง', if (transcribe) 'ถอดข้อความด้วยไอแซค'];
  return parts.isEmpty ? '' : 'ห้องนี้มีการ${parts.join(' และ')} เพื่อทำบันทึกการประชุม การเข้าร่วมถือว่ายินยอม';
}

/// Two-letter initials of a name for the avatar tile.
String roomInitials(String name) {
  // "ธนา (ฝ่ายขาย)" → "ธ": skip bracketed / symbol words.
  final p = name.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ').trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty && RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(x)).toList();
  if (p.isEmpty) return '?';
  return (p.length == 1 ? p.first.characters.take(2).toString() : '${p.first.characters.first}${p[1].characters.first}').toUpperCase();
}

String minuteRoomLangLabel(String code) => minuteLangLabel(code);
