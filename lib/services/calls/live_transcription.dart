import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../realtime_service.dart';
import 'call_mic_tap_native.dart';
import 'call_service.dart';
import 'recording_upload_queue.dart';

/// One line of live captions.
class LiveCaption {
  const LiveCaption({required this.key, required this.userId, required this.name, required this.text, required this.isFinal});
  final String key;
  final String userId;
  final String name;
  final String text;
  final bool isFinal;
}

/// Who is being transcribed in the call (everyone sees this).
class SttSpeaker {
  const SttSpeaker({required this.userId, required this.name, required this.enabled, required this.share, required this.status});
  final String userId;
  final String name;
  final bool enabled;
  final bool share;
  final String status;
}

/// The user's choice for one call.
class SttDecision {
  const SttDecision({required this.callId, required this.enabled, this.share = true, this.record = false});
  final String callId;
  final bool enabled;
  final bool share;
  final bool record;
  SttDecision withCall(String id) => SttDecision(callId: id, enabled: enabled, share: share, record: record);
}

/// Stable id of this install (`app-<uuid>`, generated once, kept in SharedPreferences): goes with
/// `stt:start` and every recording upload so one account on several devices keeps one recording per device.
class CommAiDevice {
  static const key = 'commAi.deviceId';
  static String? _id;

  static Future<String> id() async {
    if (_id != null) return _id!;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(key);
      if (saved != null && RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(saved)) return _id = saved;
      final fresh = 'app-${_uuid()}';
      await p.setString(key, fresh);
      return _id = fresh;
    } catch (_) {
      return _id ??= 'app-${_uuid()}'; // storage unavailable: stable for this run at least
    }
  }

  @visibleForTesting
  static void reset() => _id = null;

  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Microphone → PCM16 mono 24 kHz in ~100 ms chunks while WebRTC keeps using the mic.
/// Separate so a native tap can replace it on devices where a second recorder is refused.
abstract class CallMicTap {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

class RecordMicTap implements CallMicTap {
  AudioRecorder? _rec;

  @override
  Future<Stream<Uint8List>> start() async {
    final rec = AudioRecorder();
    _rec = rec;
    // iOS: keep WebRTC's audio session (playAndRecord) — do not let the recorder change it.
    if (Platform.isIOS) await rec.ios?.manageAudioSession(false);
    final raw = await rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 24000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication, manageBluetooth: false),
    ));
    return rechunk(raw, 4800);
  }

  @override
  Future<void> stop() async {
    final rec = _rec;
    _rec = null;
    if (rec == null) return;
    try {
      await rec.stop();
    } catch (_) {}
    await rec.dispose();
  }
}

/// Re-slices a byte stream into fixed-size packets (the server expects even-length PCM16 frames).
Stream<Uint8List> rechunk(Stream<Uint8List> input, int size) async* {
  final buf = BytesBuilder(copy: false);
  await for (final part in input) {
    buf.add(part);
    while (buf.length >= size) {
      final all = buf.takeBytes();
      yield Uint8List.sublistView(all, 0, size);
      if (all.length > size) buf.add(Uint8List.sublistView(all, size));
    }
  }
  final rest = buf.takeBytes();
  if (rest.length >= 2) yield Uint8List.sublistView(rest, 0, rest.length - rest.length % 2);
}

/// Writes PCM16 mono 24 kHz into WAV parts of [partBytes] (~5 minutes) and hands each finished part
/// to the upload queue, so a long call is never one huge file and nothing is lost if the app dies.
class _WavParts {
  _WavParts(this.dir, this.callId, {this.businessId, this.deviceId = ''});
  final Directory dir;
  final String callId;
  final String? businessId;
  final String deviceId;
  static const partBytes = 48000 * 300; // 5 minutes of PCM16 24 kHz
  IOSink? _sink;
  File? _file;
  int _bytes = 0; // in the current part
  int _total = 0;
  int _part = 0;

  int get durationMs => _total ~/ 48;

  void add(Uint8List pcm) {
    if (_sink == null) {
      _file = File('${dir.path}/call-${callId.replaceAll(RegExp(r'[^\w-]'), '')}-${DateTime.now().millisecondsSinceEpoch}-$_part.wav');
      _sink = _file!.openWrite()..add(Uint8List(44));
      _bytes = 0;
    }
    _sink!.add(pcm);
    _bytes += pcm.length;
    _total += pcm.length;
    if (_bytes >= partBytes) unawaited(_closePart(isFinal: false));
  }

  Future<void> _closePart({required bool isFinal}) async {
    final sink = _sink;
    final file = _file;
    final bytes = _bytes;
    _sink = null;
    _file = null;
    if (sink != null && file != null) {
      await sink.flush();
      await sink.close();
      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      await raf.setPosition(0);
      await raf.writeFrom(wavHeader(bytes));
      await raf.close();
    }
    if (file == null && !isFinal) return;
    if (isFinal && _total < 48000) {
      // < 1 s in total: nothing worth keeping.
      if (file != null) file.delete().ignore();
      return;
    }
    if (file == null) return; // final part already rolled; nothing new (handled by caller)
    final n = _part++;
    await RecordingUploadQueue.instance.add(RecordingPart(
      callId: callId,
      path: file.path,
      part: n,
      parts: isFinal ? _part : 0,
      isFinal: isFinal,
      durationMs: durationMs,
      businessId: businessId,
      deviceId: deviceId,
    ));
  }

  /// Throws the unsent recording away (parts already queued stay queued).
  Future<void> discard() async {
    final sink = _sink;
    final file = _file;
    _sink = null;
    _file = null;
    await sink?.close();
    file?.delete().ignore();
  }

  /// Closes the last part (marked final, with the total part count).
  Future<void> close() async {
    if (_sink == null && _part > 0) {
      // The last part was just rolled over: send a tiny closing part so the server knows the total.
      add(Uint8List(4800));
    }
    await _closePart(isFinal: true);
  }
}

Uint8List wavHeader(int dataBytes, {int sampleRate = 24000}) {
  final b = ByteData(44);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

/// Socket + upload seams so tests run without a server or a microphone.
abstract class SttTransport {
  Stream<RealtimeEvent> get events;
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data);
  void emit(String event, Map<String, dynamic> data);
  void emitAudio(String callId, Uint8List pcm);
}

class RealtimeSttTransport implements SttTransport {
  @override
  Stream<RealtimeEvent> get events => RealtimeService.instance.events;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) => RealtimeService.instance.emitAck(event, data);
  @override
  void emit(String event, Map<String, dynamic> data) => RealtimeService.instance.emit(event, data);
  @override
  void emitAudio(String callId, Uint8List pcm) => RealtimeService.instance.emitAudio(callId, pcm);
}

/// Live captions for the current call (mobile).
///
/// Each phone sends only its own microphone; captions of everyone come back as `stt:segment`.
/// Captions live in [captions] (a ValueNotifier) so the call screen does not rebuild for every word.
class LiveTranscription extends ChangeNotifier {
  LiveTranscription({SttTransport? transport, CallMicTap Function()? micTap}) : _t = transport ?? RealtimeSttTransport(), _micFactory = micTap {
    _sub = _t.events.listen(_onEvent);
  }

  static LiveTranscription? _instance;
  static LiveTranscription get instance => _instance ??= LiveTranscription();
  @visibleForTesting
  static set instance(LiveTranscription v) => _instance = v;

  final SttTransport _t;
  final CallMicTap Function()? _micFactory;

  /// Default: WebRTC's own captured audio (no second recorder); falls back to `record` when the
  /// native tap is missing or silent on this device.
  CallMicTap _defaultMic() => WebRtcMicTap.supported ? FallbackMicTap(WebRtcMicTap(_localAudioTrackId), RecordMicTap()) : RecordMicTap();

  String? _localAudioTrackId() {
    final s = _call?.media?.localStream;
    if (s is! MediaStream) return null;
    final tracks = s.getAudioTracks();
    return tracks.isEmpty ? null : tracks.first.id;
  }
  StreamSubscription<RealtimeEvent>? _sub;
  ApiClient? api;
  String? businessId;
  String? myUserId;

  Map<String, dynamic>? settings;
  SttDecision? decision;
  String? activeCallId;
  bool running = false;
  bool _starting = false;
  String status = 'idle';
  String? error;

  /// With [error] `quota_exceeded`: `{kind, used, limit}` of the month's transcription minutes.
  Map<String, dynamic>? quota;
  Map<String, dynamic>? request; // caller-decides notice
  final speakers = <String, SttSpeaker>{};
  final captions = ValueNotifier<List<LiveCaption>>(const []);
  final summaryReady = ValueNotifier<Map<String, dynamic>?>(null);

  CallMicTap? _mic;
  StreamSubscription<Uint8List>? _micSub;
  _WavParts? _wav;
  CallService? _call;

  static const _choiceKey = 'commAi.sttChoice';

  /// Remembered choice comes from the server (same on all my devices); SharedPreferences is only a cache.
  bool _choiceLoaded = false;
  bool _choiceTried = false; // one request per Space / reconnect, so an offline phone is not slowed down

  /// Pause between re-sending `stt:start` after a reconnect (tests shorten it).
  @visibleForTesting
  Duration resumeDelay = const Duration(seconds: 1);

  bool get enabled => settings?['stt_enabled'] == true;
  bool get callerMode => settings?['consent_mode'] == 'caller';
  bool get anyoneTranscribed => speakers.values.any((s) => s.enabled);

  /// Loads settings once (cheap; cached on the server).
  Future<void> ensureSettings() async {
    if (settings != null || api == null) return;
    try {
      final r = await api!.getCommAiSettings();
      settings = r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : {'stt_enabled': false};
    } catch (_) {
      settings = {'stt_enabled': false};
    }
    _choiceLoaded = false;
    _choiceTried = false;
    if (enabled) await _loadServerChoice();
    notifyListeners();
  }

  /// Server value of "จำการเลือกนี้" → local cache. Offline: the cached value keeps working.
  Future<void> _loadServerChoice() async {
    if (_choiceLoaded || _choiceTried || api == null) return;
    _choiceTried = true;
    try {
      final r = await api!.getCommAiConsentChoice();
      if (r.containsKey('choice')) {
        _choiceLoaded = true;
        await _cacheChoice(r['choice'] is Map ? Map<String, dynamic>.from(r['choice'] as Map) : null);
      }
    } catch (_) {}
  }

  Future<void> _cacheChoice(Map<String, dynamic>? c) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (c == null) {
        await p.remove(_choiceKey);
      } else {
        await p.setString(_choiceKey, [c['enabled'] == true ? 'on' : 'off', if (c['share'] == false) 'private', if (c['record'] == true) 'rec'].join(','));
      }
    } catch (_) {}
  }

  /// Follow the call: start when the call is live and the user agreed; clean up when it ends.
  void attach(CallService call) {
    if (_call == call) return;
    _call?.removeListener(_onCall);
    _call = call;
    call.addListener(_onCall);
  }

  Future<SttDecision?> savedChoice() async {
    await _loadServerChoice();
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_choiceKey);
    if (v == null) return null;
    final parts = v.split(',');
    return SttDecision(callId: '', enabled: parts.contains('on'), share: !parts.contains('private'), record: parts.contains('rec'));
  }

  /// Should the app ask the user for this call?
  Future<bool> needsConsent(String callId) async {
    await ensureSettings();
    if (!enabled || decision?.callId == callId) return false;
    // Picked up from another device of mine while I was being transcribed → continue, do not ask again.
    final mine = callId == activeCallId ? await _syncMine(callId) : null;
    if (decision?.callId == callId) return false;
    if (mine != null) {
      await decide(callId, enabled: true, share: mine['share'] != false, record: mine['record'] == true);
      return false;
    }
    if (settings?['ask_every_call'] == false) {
      final saved = await savedChoice();
      if (saved != null) {
        decide(callId, enabled: saved.enabled, share: saved.share, record: saved.record);
        return false;
      }
    }
    return true;
  }

  /// My speaker entry from `stt:sync` when I am already transcribed in this call (from another device).
  Future<Map<String, dynamic>?> _syncMine(String callId) async {
    try {
      final r = await _t.emitAck('stt:sync', {'call_id': callId});
      final list = r['speakers'];
      if (r['ok'] != true || list is! List) return null;
      for (final s in list.whereType<Map>()) {
        if ('${s['user_id']}' == myUserId && s['enabled'] == true) return Map<String, dynamic>.from(s);
      }
    } catch (_) {}
    return null;
  }

  Future<void> decide(String callId, {required bool enabled, bool share = true, bool record = false, bool remember = false}) async {
    decision = SttDecision(callId: callId, enabled: enabled, share: share, record: record);
    if (remember) {
      final choice = {'enabled': enabled, 'share': share, 'record': record};
      await _cacheChoice(choice);
      try {
        await api?.saveCommAiConsentChoice(choice);
      } catch (_) {} // the cache still applies on this phone
    }
    notifyListeners();
    _onCall();
  }

  void _onCall() {
    final c = _call;
    if (c == null) return;
    final id = c.phase == CallPhase.active ? (c.call?['call_id'])?.toString() : null;
    if (id != activeCallId) {
      final ended = activeCallId;
      activeCallId = id;
      if (ended != null) _finish(ended);
    }
    if (id != null && decision != null && decision!.callId != id && c.call?['call_id']?.toString() == decision!.callId) {
      decision = decision!.withCall(id);
    }
    if (id != null && !running && !_starting && decision?.callId == id && decision!.enabled && error == null && id != _movedCallId) {
      start();
    }
  }

  Future<void> start({bool requested = false}) async {
    final id = activeCallId;
    if (id == null || running || _starting) return;
    if (_movedCallId == id) _movedCallId = null; // asked again on this device → take it back
    _starting = true;
    error = null;
    quota = null;
    try {
      final deviceId = await CommAiDevice.id();
      final ack = await _t.emitAck('stt:start', {
        'call_id': id,
        if (businessId != null) 'business_id': int.tryParse(businessId!) ?? businessId,
        'share': decision?.share ?? true,
        'record': decision?.record ?? false,
        'requested': requested,
        'device_id': deviceId,
      });
      if (ack['ok'] != true) {
        error = '${ack['error'] ?? 'error'}';
        quota = ack['quota'] is Map ? Map<String, dynamic>.from(ack['quota'] as Map) : null;
        notifyListeners();
        return;
      }
      final mic = (_micFactory ?? _defaultMic)();
      _mic = mic;
      Stream<Uint8List> stream;
      try {
        stream = await mic.start();
      } catch (_) {
        error = 'mic';
        _t.emit('stt:stop', {'call_id': id});
        notifyListeners();
        return;
      }
      final ackSettings = ack['settings'];
      final serverAllows = ackSettings is Map && ackSettings['record'] == true;
      if (ack['handoff'] == true) {
        // Taken over from another device of mine: keep that device's choice (no consent sheet again).
        decision = SttDecision(callId: id, enabled: true, share: ackSettings is Map ? ackSettings['share'] != false : (decision?.share ?? true), record: serverAllows);
      }
      final record = serverAllows && (decision?.record ?? false);
      if (record) {
        try {
          _wav = _WavParts(await RecordingUploadQueue.instance.folder(), id, businessId: businessId, deviceId: deviceId);
        } catch (_) {
          _wav = null;
        }
      }
      _micSub = stream.listen((pcm) {
        // Muted in the call → nothing leaves the phone (and nothing is recorded).
        // Muted in the call → nothing leaves the phone; the recording gets silence so the
        // meeting tape stays in sync with everyone else.
        if (_call?.muted == true) {
          _wav?.add(Uint8List(pcm.length));
          return;
        }
        _t.emitAudio(id, pcm);
        _wav?.add(pcm);
      });
      final list = ack['speakers'];
      if (list is List) {
        for (final s in list.whereType<Map>()) {
          _setSpeaker(Map<String, dynamic>.from(s));
        }
      }
      running = true;
      status = 'open';
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final id = activeCallId;
    await _stopMic(upload: true, callId: id);
    if (id != null) _t.emit('stt:stop', {'call_id': id});
    running = false;
    notifyListeners();
  }

  void setShare(bool share) {
    final id = activeCallId;
    if (id == null) return;
    _t.emit('stt:share', {'call_id': id, 'share': share});
    if (decision != null) decision = SttDecision(callId: decision!.callId, enabled: decision!.enabled, share: share, record: decision!.record);
    notifyListeners();
  }

  Future<void> _stopMic({required bool upload, String? callId}) async {
    // Release the microphone first (the call may already be over), then drop the subscription.
    final mic = _mic;
    _mic = null;
    final sub = _micSub;
    _micSub = null;
    await mic?.stop();
    await sub?.cancel();
    final wav = _wav;
    _wav = null;
    if (wav != null) {
      if (upload) {
        await wav.close();
      } else {
        await wav.discard();
      }
    }
  }

  void _finish(String callId) {
    _stopMic(upload: true, callId: callId);
    running = false;
    status = 'idle';
    request = null;
    error = null;
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (activeCallId == null) {
        captions.value = const [];
        speakers.clear();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void _setSpeaker(Map<String, dynamic> s) {
    final uid = '${s['user_id']}';
    speakers[uid] = SttSpeaker(userId: uid, name: '${s['name'] ?? ''}', enabled: s['enabled'] == true, share: s['share'] == true, status: '${s['status'] ?? ''}');
    if (uid == myUserId && s['status'] != null) status = '${s['status']}';
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    switch (e.type) {
      case 'stt:segment':
        if ('${d['call_id']}' != activeCallId) return;
        final key = '${d['user_id']}:${d['item_id']}';
        final item = LiveCaption(key: key, userId: '${d['user_id']}', name: '${d['name'] ?? ''}', text: '${d['text'] ?? ''}', isFinal: d['final'] == true);
        final list = [...captions.value];
        final i = list.indexWhere((c) => c.key == key);
        if (i >= 0) {
          if (list[i].isFinal && !item.isFinal) return;
          list[i] = item;
        } else {
          list.add(item);
          if (list.length > 200) list.removeRange(0, list.length - 200);
        }
        captions.value = list;
      case 'stt:state':
        if ('${d['call_id']}' != activeCallId) return;
        _setSpeaker(d);
        notifyListeners();
      case 'stt:request':
        if ('${d['call_id']}' != activeCallId) return;
        request = d;
        decision = SttDecision(callId: activeCallId!, enabled: true, share: d['share'] != false, record: settings?['record_audio'] == true);
        notifyListeners();
        start(requested: true);
      case 'ai:call_summary_ready':
        summaryReady.value = d;
      case 'stt:moved':
        _onMoved(d);
      case 'ai:consent_choice':
        if (businessId != null && d['business_id'] != null && '${d['business_id']}' != businessId) return;
        if (!d.containsKey('choice')) return;
        _choiceLoaded = true;
        unawaited(_cacheChoice(d['choice'] is Map ? Map<String, dynamic>.from(d['choice'] as Map) : null));
      case RealtimeService.connectedEvent:
        _resumeAfterReconnect();
        if (!_choiceLoaded && enabled) {
          _choiceTried = false;
          unawaited(_loadServerChoice());
        }
    }
  }

  /// My call / captions moved to another device of mine: stop the mic + recorder here and upload what
  /// was recorded (final part). No `stt:stop` — the other device continues the transcription.
  void _onMoved(Map<String, dynamic> d) {
    final id = '${d['call_id'] ?? ''}';
    if (id.isEmpty || (id != activeCallId && !running)) return;
    final wasActive = running || _mic != null || _wav != null;
    _movedCallId = id; // do not start again here by itself (the other device has it now)
    unawaited(_stopMic(upload: true, callId: id));
    running = false;
    _resumeTimer?.cancel();
    if (wasActive) _call?.showNotice(callMovedNotice);
    notifyListeners();
  }

  Timer? _resumeTimer;
  String? _movedCallId;

  /// Socket came back while transcribing (new socket id): take my transcription seat again, up to 3 tries.
  void _resumeAfterReconnect() {
    final id = activeCallId;
    if (id == null || !running || decision?.enabled != true) return;
    _resumeTimer?.cancel();
    var tries = 0;
    Future<void> again() async {
      if (activeCallId != id || !running) return;
      tries++;
      final res = await _t.emitAck('stt:start', {
        'call_id': id,
        if (businessId != null) 'business_id': int.tryParse(businessId!) ?? businessId,
        'requested': true,
        'device_id': await CommAiDevice.id(),
      });
      if (res['ok'] == true || tries >= 3) return;
      _resumeTimer = Timer(resumeDelay, () => unawaited(again()));
    }

    _resumeTimer = Timer(resumeDelay, () => unawaited(again()));
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _sub?.cancel();
    _call?.removeListener(_onCall);
    captions.dispose();
    summaryReady.dispose();
    super.dispose();
  }
}
