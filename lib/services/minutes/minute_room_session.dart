import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/minutes/minutes.dart';
import '../audio/mic_tap.dart';
import '../audio/pcm.dart';
import '../calls/call_mic_tap_native.dart';
import '../realtime_service.dart';

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
  const RoomChatMessage({required this.from, required this.text, required this.at, this.mine = false});
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
  }) : media = media ?? LivekitRoomMedia(),
       _rt = realtime ?? RealtimeService.instance,
       _micFactory = mic {
    this.media.addListener(notifyListeners);
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

  Future<void> start({required String url, required String token, bool micOn = false, bool camOn = false}) async {
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
    final ack = await _rt.emitAck('minute:room_join', {'ticket': ticket});
    if (ack['ok'] == true) {
      captionsOn = ack['captions'] == true;
      translateLangs = [for (final l in (ack['langs'] as List? ?? const [])) '$l'];
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

  Future<void> sendChat(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await media.sendData({'type': 'chat', 'text': t, 'name': name}, topic: 'chat');
    chat.value = [...chat.value, RoomChatMessage(from: name, text: t, at: DateTime.now(), mine: true)];
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
        chat.value = [...chat.value, RoomChatMessage(from: '${d['name'] ?? from}', text: '${d['text'] ?? ''}', at: DateTime.now())];
      case 'reaction':
        reactions.add(('${d['name'] ?? from}', '${d['emoji'] ?? '👍'}'));
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
      case RealtimeService.connectedEvent:
        unawaited(_rt.emitAck('minute:room_join', {'ticket': ticket, 'lang': captionLang}));
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

  @override
  void dispose() {
    media.removeListener(notifyListeners);
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
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.length == 1 ? p.first.characters.take(2).toString() : '${p.first.characters.first}${p[1].characters.first}').toUpperCase();
}

String minuteRoomLangLabel(String code) => minuteLangLabel(code);
