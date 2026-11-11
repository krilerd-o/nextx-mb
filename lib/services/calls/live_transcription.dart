import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../realtime_service.dart';
import 'call_service.dart';

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

/// Builds a WAV file from PCM16 mono 24 kHz chunks (kept when the user agreed to recording).
class _WavWriter {
  _WavWriter(this.file) : _sink = file.openWrite();
  final File file;
  final IOSink _sink;
  int _bytes = 0;
  bool _headerWritten = false;

  void add(Uint8List pcm) {
    if (!_headerWritten) {
      _sink.add(Uint8List(44)); // placeholder, rewritten on close
      _headerWritten = true;
    }
    _sink.add(pcm);
    _bytes += pcm.length;
  }

  int get durationMs => _bytes ~/ 48;

  Future<File?> close() async {
    await _sink.flush();
    await _sink.close();
    if (_bytes < 48000) return null; // < 1 s
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    await raf.setPosition(0);
    await raf.writeFrom(wavHeader(_bytes));
    await raf.close();
    return file;
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
  LiveTranscription({SttTransport? transport, CallMicTap Function()? micTap}) : _t = transport ?? RealtimeSttTransport(), _micFactory = micTap ?? RecordMicTap.new {
    _sub = _t.events.listen(_onEvent);
  }

  static LiveTranscription? _instance;
  static LiveTranscription get instance => _instance ??= LiveTranscription();
  @visibleForTesting
  static set instance(LiveTranscription v) => _instance = v;

  final SttTransport _t;
  final CallMicTap Function() _micFactory;
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
  Map<String, dynamic>? request; // caller-decides notice
  final speakers = <String, SttSpeaker>{};
  final captions = ValueNotifier<List<LiveCaption>>(const []);
  final summaryReady = ValueNotifier<Map<String, dynamic>?>(null);

  CallMicTap? _mic;
  StreamSubscription<Uint8List>? _micSub;
  _WavWriter? _wav;
  CallService? _call;

  static const _choiceKey = 'commAi.sttChoice';

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
    notifyListeners();
  }

  /// Follow the call: start when the call is live and the user agreed; clean up when it ends.
  void attach(CallService call) {
    if (_call == call) return;
    _call?.removeListener(_onCall);
    _call = call;
    call.addListener(_onCall);
  }

  Future<SttDecision?> savedChoice() async {
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
    if (settings?['ask_every_call'] == false) {
      final saved = await savedChoice();
      if (saved != null) {
        decide(callId, enabled: saved.enabled, share: saved.share, record: saved.record);
        return false;
      }
    }
    return true;
  }

  Future<void> decide(String callId, {required bool enabled, bool share = true, bool record = false, bool remember = false}) async {
    decision = SttDecision(callId: callId, enabled: enabled, share: share, record: record);
    if (remember) {
      final p = await SharedPreferences.getInstance();
      await p.setString(_choiceKey, [enabled ? 'on' : 'off', if (!share) 'private', if (record) 'rec'].join(','));
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
    if (id != null && !running && !_starting && decision?.callId == id && decision!.enabled && error == null) {
      start();
    }
  }

  Future<void> start({bool requested = false}) async {
    final id = activeCallId;
    if (id == null || running || _starting) return;
    _starting = true;
    error = null;
    try {
      final ack = await _t.emitAck('stt:start', {
        'call_id': id,
        if (businessId != null) 'business_id': int.tryParse(businessId!) ?? businessId,
        'share': decision?.share ?? true,
        'record': decision?.record ?? false,
        'requested': requested,
      });
      if (ack['ok'] != true) {
        error = '${ack['error'] ?? 'error'}';
        notifyListeners();
        return;
      }
      final mic = _micFactory();
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
      final record = serverAllows && (decision?.record ?? false);
      if (record) {
        try {
          final dir = await getTemporaryDirectory();
          _wav = _WavWriter(File('${dir.path}/call-$id.wav'));
        } catch (_) {
          _wav = null;
        }
      }
      _micSub = stream.listen((pcm) {
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
      final file = await wav.close();
      if (upload && file != null && callId != null && api != null) {
        unawaited(api!.uploadCallRecording(callId, file.path, durationMs: wav.durationMs, mime: 'audio/wav').whenComplete(() {
          file.delete().ignore();
        }).catchError((_) {}));
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
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _call?.removeListener(_onCall);
    captions.dispose();
    summaryReady.dispose();
    super.dispose();
  }
}
