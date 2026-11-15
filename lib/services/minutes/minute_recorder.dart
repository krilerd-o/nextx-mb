import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/minutes/minutes.dart';
import '../../core/notebook/notebook_recording.dart' show RecordingBookmark, defaultRecordingTitle;
import '../api_client.dart';
import '../audio/mic_tap.dart';
import '../audio/pcm.dart';
import '../audio/recording_upload_queue.dart';
import '../audio/wav_parts.dart';
import '../calls/call_service.dart';
import '../calls/live_transcription.dart' show CommAiDevice;
import '../notebook/notebook_recorder.dart' show LiveState, MicPermission, NotebookRecorder, NotebookSttTransport, RealtimeNotebookTransport, RecordStart;
import '../notebook/recording_foreground.dart';
import '../realtime_service.dart';

/// Socket seam of a minute recording (tests run without a server).
abstract class MinuteSttTransport implements NotebookSttTransport {
  void sendMinuteAudio(String meetingId, Uint8List pcm);
}

class RealtimeMinuteTransport extends RealtimeNotebookTransport implements MinuteSttTransport {
  @override
  void sendMinuteAudio(String meetingId, Uint8List pcm) => RealtimeService.instance.emitMinuteAudio(meetingId, pcm);
}

enum MinuteRecPhase { idle, starting, recording, paused, finishing }

/// A meeting that was just stopped on this phone (the list shows it as "กำลังประมวลผล…").
class FinishedMinute {
  const FinishedMinute({required this.clientSessionId, required this.title, this.meetingId, this.durationMs = 0, this.summarizeNow = true});
  final String clientSessionId;
  final String? meetingId;
  final String title;
  final int durationMs;
  final bool summarizeNow;
}

/// Records a meeting on this phone for ไอแซคบันทึกประชุม: one recording at a time, app-wide, and never
/// at the same time as a notebook recording (one microphone).
///
/// start → `POST /api/ai/minutes` → `stt:start {session_kind:'minute'}` → microphone. Audio goes live to
/// the socket (live captions; [translateTo] adds a live translation) and into ~5-minute WAV parts in the
/// shared [RecordingUploadQueue], so going offline loses nothing. Keeps recording with the screen locked
/// (Android foreground service shared with notebook recordings; iOS `audio` background mode).
/// stop([MinuteFinish]) → final part → `stop` with "summarise now / later", template and follow-ups.
class MinuteRecorder extends ChangeNotifier {
  MinuteRecorder({
    MinuteSttTransport? transport,
    PausableMicTap Function()? mic,
    RecordingUploadQueue? queue,
    RecordingForeground? foreground,
    DateTime Function()? now,
    Future<MicPermission> Function()? permission,
  }) : _t = transport ?? RealtimeMinuteTransport(),
       _micFactory = mic ?? RecordMicTap.standalone,
       _queueOverride = queue,
       _fg = foreground ?? NativeRecordingForeground.shared,
       _now = now ?? DateTime.now,
       _permission = permission ?? NotebookRecorder.defaultMicPermission {
    _sub = _t.events.listen(_onEvent);
    _t.connection.addListener(_onConnection);
    _fgSub = _fg.actions.listen(_onAction);
  }

  static MinuteRecorder? _instance;
  static MinuteRecorder get instance => _instance ??= MinuteRecorder();
  @visibleForTesting
  static set instance(MinuteRecorder v) => _instance = v;
  static bool get hasInstance => _instance != null;

  final MinuteSttTransport _t;
  final PausableMicTap Function() _micFactory;
  final RecordingUploadQueue? _queueOverride;
  final RecordingForeground _fg;
  final DateTime Function() _now;
  final Future<MicPermission> Function() _permission;
  RecordingUploadQueue get _queue => _queueOverride ?? RecordingUploadQueue.instance;

  StreamSubscription<RealtimeEvent>? _sub;
  StreamSubscription<String>? _fgSub;
  StreamSubscription<RecordingPart>? _sentSub;

  ApiClient? api;
  String? businessId;

  MinuteRecPhase phase = MinuteRecPhase.idle;
  LiveState live = LiveState.connecting;
  String? meetingId;
  String? clientSessionId;
  String title = '';
  String locale = 'th';
  String? error;

  final notice = ValueNotifier<String?>(null);
  final bookmarks = <RecordingBookmark>[];

  /// Live transcript (partial lines replaced by their final text).
  final lines = ValueNotifier<List<MinuteLine>>(const []);

  /// Live translation: seq → text in [translateTo].
  final translated = ValueNotifier<Map<int, String>>(const {});
  String? translateTo;

  final levels = ValueNotifier<List<double>>(const []);
  static const levelHistory = 64;

  final _finished = StreamController<FinishedMinute>.broadcast();
  Stream<FinishedMinute> get finished => _finished.stream;

  int _screens = 0;
  bool get screenOpen => _screens > 0;
  void screenShown() {
    _screens++;
    _notifyOutsideBuild();
  }

  void screenHidden() {
    _screens = max(0, _screens - 1);
    _notifyOutsideBuild();
  }

  bool _disposed = false;
  bool _notifyQueued = false;
  void _notifyOutsideBuild() {
    final p = SchedulerBinding.instance.schedulerPhase;
    if (p == SchedulerPhase.idle || p == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyQueued) return;
    _notifyQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  VoidCallback? onOpenRequest;

  bool get active => phase == MinuteRecPhase.starting || phase == MinuteRecPhase.recording || phase == MinuteRecPhase.paused;
  bool get recording => phase == MinuteRecPhase.recording;
  bool get paused => phase == MinuteRecPhase.paused;

  PausableMicTap? _mic;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<bool>? _interruptSub;
  WavPartWriter? _wav;
  String? _deviceId;
  bool _sttOn = false;
  Duration _accum = Duration.zero;
  DateTime? _runningSince;
  Duration get elapsed => _accum + (_runningSince == null ? Duration.zero : _now().difference(_runningSince!));

  @visibleForTesting
  Duration resumeDelay = const Duration(seconds: 1);
  @visibleForTesting
  int partBytes = WavPartWriter.defaultPartBytes;

  static const offlineNotice = 'ถอดสดหยุดชั่วคราว — ยังบันทึกเสียงอยู่ และจะถอดจากไฟล์ให้ภายหลัง';
  static const callNotice = 'มีสายโทร — หยุดบันทึกไว้ชั่วคราว กด "บันทึกต่อ" เมื่อวางสาย';
  static const interruptNotice = 'ระบบใช้ไมโครโฟน — หยุดบันทึกไว้ชั่วคราว';
  static const movedNotice = 'ถอดสดย้ายไปอุปกรณ์อื่นแล้ว — เครื่องนี้ยังบันทึกเสียงต่อ';
  static const inCallText = 'กำลังอยู่ในสาย — วางสายก่อนจึงเริ่มบันทึกประชุมได้';
  static const notebookBusyText = 'กำลังบันทึกเสียงในสมุดโน้ตอยู่ — หยุดอันนั้นก่อน';

  void _notify() => notifyListeners();

  void bind({required ApiClient api, String? businessId}) {
    this.api = api;
    this.businessId = businessId;
  }

  CallService? _call;
  void attachCall(CallService call) {
    if (_call == call) return;
    _call?.removeListener(_onCall);
    _call = call;
    call.addListener(_onCall);
  }

  bool get _inCall {
    final p = (_call ?? CallService.instance)?.phase;
    return p == CallPhase.active || p == CallPhase.outgoing;
  }

  void _onCall() {
    if (phase == MinuteRecPhase.recording && _inCall) unawaited(pause(reason: callNotice));
  }

  // ── start

  /// [languages]: spoken languages (first = transcription language); [ref]: CRM record `{module, id}`.
  Future<RecordStart> start({String? title, String locale = 'th', List<String> languages = const [], Map<String, dynamic>? ref, String template = 'general'}) async {
    if (active || phase == MinuteRecPhase.finishing) return RecordStart.busy;
    if (NotebookRecorder.hasInstance && NotebookRecorder.instance.active) {
      error = notebookBusyText;
      _notify();
      return RecordStart.busy;
    }
    if (_inCall) {
      error = inCallText;
      _notify();
      return RecordStart.inCall;
    }
    final perm = await _permission();
    if (perm != MicPermission.granted) return perm == MicPermission.permanentlyDenied ? RecordStart.permanentlyDenied : RecordStart.denied;
    final a = api;
    if (a == null) return RecordStart.failed;
    phase = MinuteRecPhase.starting;
    live = LiveState.connecting;
    error = null;
    notice.value = null;
    this.locale = locale;
    this.title = (title == null || title.trim().isEmpty) ? 'ประชุม ${defaultRecordingTitle(_now()).replaceFirst('บันทึกเสียง ', '')}' : title.trim();
    meetingId = null;
    clientSessionId = 'minute-${_uuid()}';
    bookmarks.clear();
    lines.value = const [];
    translated.value = const {};
    levels.value = const [];
    _accum = Duration.zero;
    _runningSince = null;
    _notify();
    final csid = clientSessionId!;
    final createBody = <String, dynamic>{
      'languages': languages.isEmpty ? [locale] : languages,
      'template': template,
      'ref': ?ref,
    };
    try {
      _deviceId = await CommAiDevice.id();
      var offline = false;
      try {
        final item = await a.createMinuteMeeting({...createBody, 'title': this.title, 'locale': locale, 'device_id': _deviceId, 'client_session_id': csid});
        final id = '${item['id'] ?? ''}';
        if (id.isEmpty) throw ApiEnvelopeException(500, 'NO_ID', 'no meeting id');
        meetingId = id;
      } catch (e) {
        final st = _statusOf(e);
        if (st != 0) {
          _reset();
          error = st == 404 ? 'เซิร์ฟเวอร์นี้ยังไม่รองรับไอแซคบันทึกประชุม' : (e is ApiEnvelopeException ? e.message : 'เริ่มบันทึกไม่สำเร็จ');
          _notify();
          return st == 404 ? RecordStart.unsupported : RecordStart.failed;
        }
        offline = true;
      }
      final dir = await _queue.folder();
      if (offline) {
        await _queue.add(RecordingPart.minuteCreate(clientSessionId: csid, title: this.title, locale: locale, businessId: businessId, deviceId: _deviceId ?? '', extra: createBody));
      }
      _sentSub?.cancel();
      _sentSub = _queue.sent.listen(_onQueueSent);
      _wav = WavPartWriter(
        dir,
        prefix: 'min-$csid',
        minTotalBytes: 0,
        partBytes: partBytes,
        onPart: (p) => _queue.add(
          RecordingPart.minute(
            meetingId: meetingId ?? '',
            clientSessionId: csid,
            path: p.path,
            part: p.part,
            isFinal: p.isFinal,
            parts: p.parts,
            durationMs: p.durationMs,
            businessId: businessId,
            deviceId: _deviceId ?? '',
          ),
        ),
      );
      final mic = _micFactory();
      _mic = mic;
      final Stream<Uint8List> stream;
      try {
        stream = await mic.start();
      } catch (_) {
        await _abandon();
        error = 'เปิดไมโครโฟนไม่ได้';
        _notify();
        return RecordStart.failed;
      }
      _interruptSub = mic.interruptions.listen((on) {
        if (on && phase == MinuteRecPhase.recording) unawaited(pause(reason: interruptNotice));
      });
      _micSub = stream.listen(_onPcm);
      phase = MinuteRecPhase.recording;
      _runningSince = _now();
      live = offline || !_t.connected ? LiveState.offline : LiveState.connecting;
      if (live == LiveState.offline) notice.value = offlineNotice;
      _notify();
      unawaited(_fg.start(title: this.title, elapsedMs: 0));
      _startTicker();
      if (!offline) await _startStt();
      return RecordStart.started;
    } catch (_) {
      await _abandon();
      error = 'เริ่มบันทึกไม่สำเร็จ';
      _notify();
      return RecordStart.failed;
    }
  }

  static int _statusOf(Object e) => e is ApiException
      ? e.statusCode
      : e is ApiEnvelopeException
      ? (e.errorCode == 'NOT_MOCKED' ? 404 : e.statusCode)
      : 0;

  void _onPcm(Uint8List pcm) {
    if (phase != MinuteRecPhase.recording) return;
    _wav?.add(pcm);
    final id = meetingId;
    if (id != null && _sttOn && live == LiveState.live) _t.sendMinuteAudio(id, pcm);
    final next = [...levels.value, pcmLevel(pcm)];
    levels.value = next.length > levelHistory ? next.sublist(next.length - levelHistory) : next;
  }

  int get _recordedMs => _wav?.durationMs ?? elapsed.inMilliseconds;
  Map<String, dynamic> get _idBody => {'meeting_id': int.tryParse(meetingId ?? '') ?? meetingId};

  Future<bool> _startStt({bool resume = false}) async {
    final id = meetingId;
    if (id == null || !active) return false;
    if (!_t.connected) {
      _setLive(LiveState.offline);
      return false;
    }
    final ack = await _t.emitAck('stt:start', {
      'session_kind': 'minute',
      ..._idBody,
      if (businessId != null) 'business_id': int.tryParse(businessId!) ?? businessId,
      'device_id': _deviceId,
      'locale': locale,
      'offset_ms': _recordedMs,
    });
    if (!active || meetingId != id) return false;
    if (ack['ok'] == true) {
      _sttOn = true;
      if (phase == MinuteRecPhase.paused) {
        if (ack['state'] != 'paused') _t.emit('stt:pause', _idBody);
        _setLive(LiveState.paused);
      } else {
        if (ack['state'] == 'paused') _t.emit('stt:resume', {..._idBody, 'offset_ms': _recordedMs});
        _setLive(LiveState.live);
      }
      if (notice.value == offlineNotice) notice.value = null;
      final tr = translateTo;
      if (tr != null) unawaited(_t.emitAck('minute:translate', {..._idBody, 'lang': tr, 'on': true}));
      return true;
    }
    _sttOn = false;
    final err = '${ack['error'] ?? ''}';
    _setLive(err == 'no_socket' || err == 'timeout' ? LiveState.offline : LiveState.unavailable);
    notice.value = offlineNotice;
    return false;
  }

  void _setLive(LiveState s) {
    if (live == s) return;
    live = s;
    _notify();
  }

  void _onQueueSent(RecordingPart p) {
    if (p.target == RecordingTarget.minute && p.op == RecordingOp.create && p.clientSessionId == clientSessionId && meetingId == null && p.recordingId.isNotEmpty) {
      meetingId = p.recordingId;
      _notify();
      if (active) unawaited(_startStt(resume: true));
    }
  }

  // ── live translation

  /// Translate the live captions into [lang] (null = off).
  Future<void> setTranslate(String? lang) async {
    final prev = translateTo;
    translateTo = lang;
    translated.value = const {};
    _notify();
    if (meetingId == null || !_t.connected) return;
    if (prev != null) unawaited(_t.emitAck('minute:translate', {..._idBody, 'lang': prev, 'on': false}));
    if (lang != null) await _t.emitAck('minute:translate', {..._idBody, 'lang': lang, 'on': true});
  }

  // ── pause / resume

  Future<void> pause({String? reason}) async {
    if (phase != MinuteRecPhase.recording) return;
    phase = MinuteRecPhase.paused;
    final since = _runningSince;
    if (since != null) _accum += _now().difference(since);
    _runningSince = null;
    if (reason != null) notice.value = reason;
    if (live == LiveState.live) live = LiveState.paused;
    _notify();
    try {
      await _mic?.pause();
    } catch (_) {}
    final id = meetingId;
    if (id != null) {
      _t.emit('stt:pause', _idBody);
      unawaited(api?.pauseMinuteMeeting(id).then((_) {}, onError: (_) {}));
    }
    unawaited(_fg.update(paused: true, elapsedMs: elapsed.inMilliseconds));
  }

  Future<bool> resume() async {
    if (phase != MinuteRecPhase.paused) return false;
    if (_inCall) {
      notice.value = inCallText;
      return false;
    }
    phase = MinuteRecPhase.recording;
    _runningSince = _now();
    if (notice.value == callNotice || notice.value == interruptNotice || notice.value == inCallText) notice.value = null;
    if (live == LiveState.paused) live = LiveState.live;
    _notify();
    try {
      await _mic?.resume();
    } catch (_) {}
    final id = meetingId;
    if (id != null) {
      _t.emit('stt:resume', {..._idBody, 'offset_ms': _recordedMs});
      unawaited(api?.resumeMinuteMeeting(id).then((_) {}, onError: (_) {}));
    }
    unawaited(_fg.update(paused: false, elapsedMs: elapsed.inMilliseconds));
    return true;
  }

  Future<void> togglePause() => paused ? resume() : pause();

  RecordingBookmark addBookmark([String? label]) {
    final b = RecordingBookmark(atMs: elapsed.inMilliseconds, label: (label == null || label.trim().isEmpty) ? null : label.trim());
    bookmarks.add(b);
    _notify();
    return b;
  }

  void rename(String t) {
    if (t.trim().isEmpty) return;
    title = t.trim();
    _notify();
    final id = meetingId;
    if (id != null) unawaited(api?.updateMinuteMeeting(id, {'title': title}).then((_) {}, onError: (_) {}));
    unawaited(_fg.update(paused: paused, elapsedMs: elapsed.inMilliseconds, title: title));
  }

  // ── stop

  /// Ends the recording; [finish] = what the "จบการประชุม" sheet chose (summarise now / later, …).
  Future<FinishedMinute?> stop([MinuteFinish finish = const MinuteFinish()]) async {
    if (phase != MinuteRecPhase.recording && phase != MinuteRecPhase.paused) return null;
    final since = _runningSince;
    if (since != null) _accum += _now().difference(since);
    _runningSince = null;
    phase = MinuteRecPhase.finishing;
    _notify();
    _ticker?.cancel();
    final mic = _mic;
    _mic = null;
    await _interruptSub?.cancel();
    _interruptSub = null;
    try {
      await mic?.stop();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    final id = meetingId;
    if (id != null) _t.emit('stt:stop', _idBody);
    _sttOn = false;
    final wav = _wav;
    _wav = null;
    var durationMs = elapsed.inMilliseconds;
    var parts = 0;
    if (wav != null) {
      if (wav.totalBytes == 0) wav.add(Uint8List(4800));
      await wav.close();
      durationMs = wav.durationMs;
      parts = wav.partsStarted;
    }
    final csid = clientSessionId!;
    await _queue.add(
      RecordingPart.minuteStop(
        meetingId: id ?? '',
        clientSessionId: csid,
        durationMs: durationMs,
        parts: parts,
        bookmarks: [for (final b in bookmarks) b.toJson()],
        businessId: businessId,
        deviceId: _deviceId ?? '',
        extra: finish.toStopBody(),
      ),
    );
    unawaited(_fg.stop());
    final done = FinishedMinute(clientSessionId: csid, meetingId: id, title: title, durationMs: durationMs, summarizeNow: finish.summarizeNow);
    _reset();
    _notify();
    _finished.add(done);
    return done;
  }

  /// Throw the recording away (nothing is uploaded; the meeting is deleted on the server).
  Future<void> discard() async {
    final csid = clientSessionId, id = meetingId;
    await _abandon();
    for (final p in _queue.pendingFor(clientSessionId: csid, recordingId: id)) {
      await _queue.remove(p);
    }
    _notify();
  }

  Future<void> _abandon() async {
    _ticker?.cancel();
    final mic = _mic;
    _mic = null;
    try {
      await mic?.stop();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    await _interruptSub?.cancel();
    _interruptSub = null;
    await _wav?.discard();
    _wav = null;
    final id = meetingId;
    if (id != null) {
      _t.emit('stt:stop', _idBody);
      unawaited(api?.deleteMinuteMeeting(id).then((_) {}, onError: (_) {}));
    }
    unawaited(_fg.stop());
    _reset();
  }

  void _reset() {
    phase = MinuteRecPhase.idle;
    live = LiveState.connecting;
    _sttOn = false;
    _runningSince = null;
    _ticker?.cancel();
  }

  Timer? _ticker;
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (active) unawaited(_fg.update(paused: paused, elapsedMs: elapsed.inMilliseconds));
    });
  }

  void _onAction(String a) {
    if (!active) return; // a notebook recording owns the notification
    switch (a) {
      case 'pause':
        unawaited(pause());
      case 'resume':
        unawaited(resume());
      case 'stop':
        unawaited(stop());
      case 'open':
        onOpenRequest?.call();
    }
  }

  // ── socket

  bool _mine(Map<String, dynamic> d) {
    final id = meetingId;
    return id != null && '${d['meeting_id']}' == id;
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    switch (e.type) {
      case 'stt:segment':
        if (!_mine(d)) return;
        _upsertLine(MinuteLine.fromJson(d));
      case 'minute:segment_tr':
        if (!_mine(d) || d['lang'] != translateTo) return;
        final seq = (d['seq'] as num?)?.toInt();
        if (seq == null) return;
        translated.value = {...translated.value, seq: '${d['text'] ?? ''}'};
      case 'stt:state':
        if (!_mine(d)) return;
        switch ('${d['state'] ?? ''}') {
          case 'live':
            _sttOn = true;
            _setLive(paused ? LiveState.paused : LiveState.live);
            if (notice.value == offlineNotice) notice.value = null;
          case 'paused':
            _setLive(LiveState.paused);
          case 'reconnecting':
            _setLive(LiveState.reconnecting);
          case 'stopped':
            if (!active) return;
            _sttOn = false;
            _setLive(LiveState.unavailable);
            notice.value = d['reason'] == 'moved' ? movedNotice : offlineNotice;
        }
      case RealtimeService.connectedEvent:
        _resumeAfterReconnect();
    }
  }

  void _upsertLine(MinuteLine s) {
    if (s.text.trim().isEmpty && s.partial) return;
    final list = [...lines.value];
    final i = list.indexWhere((x) => x.seq == s.seq);
    if (i >= 0) {
      if (!list[i].partial && s.partial) return;
      list[i] = s;
    } else {
      list.add(s);
      list.sort((a, b) => a.seq.compareTo(b.seq));
      if (list.length > 800) list.removeRange(0, list.length - 800);
    }
    lines.value = list;
  }

  void _onConnection() {
    if (!active) return;
    if (!_t.connected && (live == LiveState.live || live == LiveState.connecting || live == LiveState.paused || live == LiveState.reconnecting)) {
      _sttOn = false;
      _setLive(LiveState.offline);
      notice.value = offlineNotice;
    }
  }

  Timer? _resumeTimer;
  void _resumeAfterReconnect() {
    if (!active || meetingId == null) return;
    _resumeTimer?.cancel();
    var tries = 0;
    Future<void> again() async {
      if (!active) return;
      tries++;
      final ok = await _startStt(resume: true);
      if (ok || tries >= 3) return;
      _resumeTimer = Timer(resumeDelay, () => unawaited(again()));
    }

    _resumeTimer = Timer(resumeDelay, () => unawaited(again()));
  }

  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _disposed = true;
    _resumeTimer?.cancel();
    _ticker?.cancel();
    _sub?.cancel();
    _fgSub?.cancel();
    _sentSub?.cancel();
    _t.connection.removeListener(_onConnection);
    _call?.removeListener(_onCall);
    _finished.close();
    notice.dispose();
    lines.dispose();
    translated.dispose();
    levels.dispose();
    super.dispose();
  }
}

/// After sign-in / switching Space (mobile only).
void bindMinuteRecorder({required ApiClient api, String? businessId}) {
  final r = MinuteRecorder.instance..bind(api: api, businessId: businessId);
  final call = CallService.instance;
  if (call != null) r.attachCall(call);
}
