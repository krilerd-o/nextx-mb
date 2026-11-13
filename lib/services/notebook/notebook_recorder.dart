import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' show AudioRecorder;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notebook/notebook_recording.dart';
import '../api_client.dart';
import '../audio/mic_tap.dart';
import '../audio/pcm.dart';
import '../audio/recording_upload_queue.dart';
import '../audio/wav_parts.dart';
import '../calls/call_service.dart';
import '../calls/live_transcription.dart' show CommAiDevice;
import '../realtime_service.dart';
import 'recording_foreground.dart';

/// Socket seam of a notebook recording (tests run without a server).
abstract class NotebookSttTransport {
  Stream<RealtimeEvent> get events;
  bool get connected;

  /// Fires when [connected] changes.
  Listenable get connection;
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data);
  void emit(String event, Map<String, dynamic> data);

  /// One ~100 ms PCM16 frame (see `notebookAudioArgs` for the key format).
  void sendAudio(String recordingId, Uint8List pcm);
}

class RealtimeNotebookTransport implements NotebookSttTransport {
  RealtimeService get _rt => RealtimeService.instance;
  @override
  Stream<RealtimeEvent> get events => _rt.events;
  @override
  bool get connected => _rt.connected;
  @override
  Listenable get connection => _rt;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) => _rt.emitAck(event, data);
  @override
  void emit(String event, Map<String, dynamic> data) => _rt.emit(event, data);
  @override
  void sendAudio(String recordingId, Uint8List pcm) => _rt.emitNotebookAudio(recordingId, pcm);
}

enum RecorderPhase { idle, starting, recording, paused, finishing }

/// Live transcription state shown on the recorder.
enum LiveState {
  /// Asking the server to start.
  connecting,
  live,
  paused,

  /// The server lost its transcriber and is reconnecting.
  reconnecting,

  /// No network / socket: audio is still recorded and uploaded later (transcribed from the file).
  offline,

  /// The server cannot transcribe live (not configured, busy, quota): transcribed from the file later.
  unavailable,
}

enum MicPermission { granted, denied, permanentlyDenied }

enum RecordStart { started, busy, inCall, denied, permanentlyDenied, unsupported, failed }

/// A recording that was just finished on this phone (the notebook shows it as "กำลังประมวลผล…").
class FinishedRecording {
  const FinishedRecording({required this.notebookId, required this.clientSessionId, required this.title, this.recordingId, this.durationMs = 0});
  final String notebookId;
  final String clientSessionId;
  final String? recordingId;
  final String title;
  final int durationMs;
}

/// Records a meeting into an ISAAC Notebook: one recording at a time, app-wide.
///
/// start → `POST /recordings` → `stt:start {session_kind:'notebook'}` → microphone; audio goes live to
/// the socket and into ~5-minute WAV parts queued in [RecordingUploadQueue] (so going offline loses
/// nothing: the server transcribes the file afterwards). Pause / resume pause the microphone, the
/// server session and the live transcriber; paused time is not counted. stop → final part → `stop`
/// (queued behind the parts) → the server makes a `recording` source + summary note and sends
/// `ai:notebook_recording_ready`.
class NotebookRecorder extends ChangeNotifier {
  NotebookRecorder({
    NotebookSttTransport? transport,
    PausableMicTap Function()? mic,
    RecordingUploadQueue? queue,
    RecordingForeground? foreground,
    DateTime Function()? now,
    Future<MicPermission> Function()? permission,
  }) : _t = transport ?? RealtimeNotebookTransport(),
       _micFactory = mic ?? RecordMicTap.standalone,
       _queueOverride = queue,
       _fg = foreground ?? NativeRecordingForeground(),
       _now = now ?? DateTime.now,
       _permission = permission ?? defaultMicPermission {
    _sub = _t.events.listen(_onEvent);
    _t.connection.addListener(_onConnection);
    _fgSub = _fg.actions.listen(_onAction);
  }

  static NotebookRecorder? _instance;
  static NotebookRecorder get instance => _instance ??= NotebookRecorder();
  @visibleForTesting
  static set instance(NotebookRecorder v) => _instance = v;
  static bool get hasInstance => _instance != null;

  final NotebookSttTransport _t;
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

  RecorderPhase phase = RecorderPhase.idle;
  LiveState live = LiveState.connecting;
  String? notebookId;
  String? notebookTitle;
  String? recordingId;
  String? clientSessionId;
  String title = '';
  String locale = 'th';
  String? error;

  /// A one-off message for the user (a call paused the recording, the system took the mic, …).
  final notice = ValueNotifier<String?>(null);

  final bookmarks = <RecordingBookmark>[];

  /// Live transcript (partial lines are replaced by their final text).
  final segments = ValueNotifier<List<RecordingSegment>>(const []);

  /// Recent microphone levels (0…1), newest last — the waveform.
  final levels = ValueNotifier<List<double>>(const []);
  static const levelHistory = 64;

  /// `ai:notebook_recording_ready` payload (the app shows "ไอแซคสรุปบันทึกเสียงเสร็จแล้ว").
  final ready = ValueNotifier<Map<String, dynamic>?>(null);

  final _finished = StreamController<FinishedRecording>.broadcast();

  /// Recordings stopped on this phone.
  Stream<FinishedRecording> get finished => _finished.stream;

  /// The full-screen recorder is open (the floating bubble hides).
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

  /// [screenShown] / [screenHidden] run from a State's initState / dispose — i.e. while the tree is
  /// building or being finalized — so listeners (the floating bubble) are told after the frame.
  void _notifyOutsideBuild() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
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

  /// Asked to show the recorder (notification tapped).
  VoidCallback? onOpenRequest;

  bool get active => phase == RecorderPhase.starting || phase == RecorderPhase.recording || phase == RecorderPhase.paused;
  bool get recording => phase == RecorderPhase.recording;
  bool get paused => phase == RecorderPhase.paused;

  PausableMicTap? _mic;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<bool>? _interruptSub;
  WavPartWriter? _wav;
  String? _deviceId;
  bool _sttOn = false;

  // Elapsed recording time (paused time excluded).
  Duration _accum = Duration.zero;
  DateTime? _runningSince;

  Duration get elapsed => _accum + (_runningSince == null ? Duration.zero : _now().difference(_runningSince!));

  /// Pause between re-sending `stt:start` after a reconnect (tests shorten it).
  @visibleForTesting
  Duration resumeDelay = const Duration(seconds: 1);

  /// Size of one WAV part (~5 minutes; tests make it tiny).
  @visibleForTesting
  int partBytes = WavPartWriter.defaultPartBytes;

  static const offlineNotice = 'ถอดสดหยุดชั่วคราว — จะถอดจากไฟล์ให้ภายหลัง';
  static const callNotice = 'มีสายโทร — หยุดบันทึกเสียงไว้ชั่วคราว กด "อัดต่อ" เมื่อวางสาย';
  static const interruptNotice = 'ระบบใช้ไมโครโฟน (เช่น มีสายเข้า) — หยุดบันทึกเสียงไว้ชั่วคราว';
  static const movedNotice = 'ถอดสดย้ายไปอุปกรณ์อื่นแล้ว — เครื่องนี้ยังบันทึกเสียงต่อ และจะถอดจากไฟล์ให้ภายหลัง';
  static const deletedNotice = 'บันทึกเสียงนี้ถูกลบแล้ว';
  static const inCallText = 'กำลังอยู่ในสาย — วางสายก่อนจึงบันทึกเสียงในสมุดโน้ตได้';

  void _notify() => notifyListeners();

  void bind({required ApiClient api, String? businessId}) {
    this.api = api;
    this.businessId = businessId;
  }

  // ── call conflict

  CallService? _call;

  /// Follow the call service: a call starting pauses the notebook recording (one microphone user at a time).
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
    if (phase == RecorderPhase.recording && _inCall) unawaited(pause(reason: callNotice));
  }

  // ── consent

  static const _consentKey = 'notebook.recordConsent';

  static Future<bool> consentRemembered() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_consentKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> rememberConsent(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      v ? await p.setBool(_consentKey, true) : await p.remove(_consentKey);
    } catch (_) {}
  }

  static Future<MicPermission> defaultMicPermission() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        // iOS asks once; after a "no" only Settings can change it (permission_handler's iOS
        // microphone strategy is compiled out without a Podfile macro, so ask through `record`).
        final rec = AudioRecorder();
        try {
          return await rec.hasPermission() ? MicPermission.granted : MicPermission.permanentlyDenied;
        } finally {
          unawaited(rec.dispose());
        }
      }
      var s = await Permission.microphone.status;
      if (!s.isGranted) s = await Permission.microphone.request();
      if (s.isGranted) {
        // Android 13+: the recording notification (with its pause / stop buttons) needs this.
        if (!kIsWeb && Platform.isAndroid) unawaited(Permission.notification.request().then((_) {}, onError: (_) {}));
        return MicPermission.granted;
      }
      return s.isPermanentlyDenied || s.isRestricted ? MicPermission.permanentlyDenied : MicPermission.denied;
    } catch (_) {
      return MicPermission.granted; // no plugin (desktop): the recorder reports a mic error itself
    }
  }

  // ── start

  Future<RecordStart> start({required String notebookId, String? notebookTitle, String? title, String locale = 'th'}) async {
    if (active || phase == RecorderPhase.finishing) return RecordStart.busy;
    if (_inCall) {
      error = inCallText;
      _notify();
      return RecordStart.inCall;
    }
    final perm = await _permission();
    if (perm != MicPermission.granted) return perm == MicPermission.permanentlyDenied ? RecordStart.permanentlyDenied : RecordStart.denied;
    final a = api;
    if (a == null) return RecordStart.failed;
    phase = RecorderPhase.starting;
    live = LiveState.connecting;
    error = null;
    notice.value = null;
    this.notebookId = notebookId;
    this.notebookTitle = notebookTitle;
    this.locale = locale;
    this.title = (title == null || title.trim().isEmpty) ? defaultRecordingTitle(_now()) : title.trim();
    recordingId = null;
    clientSessionId = 'nbrec-${_uuid()}';
    bookmarks.clear();
    segments.value = const [];
    levels.value = const [];
    _accum = Duration.zero;
    _runningSince = null;
    _notify();
    final csid = clientSessionId!;
    try {
      _deviceId = await CommAiDevice.id();
      var offline = false;
      try {
        final item = await a.createNotebookRecording(notebookId, title: this.title, locale: locale, deviceId: _deviceId, clientSessionId: csid);
        final rid = '${item['id'] ?? ''}';
        if (rid.isEmpty) throw ApiEnvelopeException(500, 'NO_ID', 'no recording id');
        recordingId = rid;
      } catch (e) {
        if (_statusOf(e) == 404) {
          _reset();
          error = 'เซิร์ฟเวอร์นี้ยังไม่รองรับการบันทึกเสียงในสมุดโน้ต';
          _notify();
          return RecordStart.unsupported;
        }
        if (_statusOf(e) != 0) {
          _reset();
          error = e is ApiEnvelopeException ? e.message : 'เริ่มบันทึกไม่สำเร็จ';
          _notify();
          return RecordStart.failed;
        }
        // No network: record anyway; the create goes first in the upload queue (idempotent).
        offline = true;
      }
      final dir = await _queue.folder();
      if (offline) {
        await _queue.add(RecordingPart.notebookCreate(notebookId: notebookId, clientSessionId: csid, title: this.title, locale: locale, businessId: businessId, deviceId: _deviceId ?? ''));
      }
      _sentSub?.cancel();
      _sentSub = _queue.sent.listen(_onQueueSent);
      _wav = WavPartWriter(
        dir,
        prefix: 'nb-$csid',
        minTotalBytes: 0,
        partBytes: partBytes,
        onPart: (p) => _queue.add(
          RecordingPart.notebook(
            notebookId: notebookId,
            recordingId: recordingId ?? '',
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
        if (on && phase == RecorderPhase.recording) unawaited(pause(reason: interruptNotice));
      });
      _micSub = stream.listen(_onPcm);
      phase = RecorderPhase.recording;
      _runningSince = _now();
      live = offline || !_t.connected ? LiveState.offline : LiveState.connecting;
      if (live == LiveState.offline) notice.value = offlineNotice;
      _notify();
      unawaited(_fg.start(title: this.title, elapsedMs: 0));
      _startTicker();
      if (!offline) await _startStt();
      return RecordStart.started;
    } catch (e) {
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
    if (phase != RecorderPhase.recording) return;
    _wav?.add(pcm);
    final rid = recordingId;
    if (rid != null && _sttOn && live == LiveState.live) _t.sendAudio(rid, pcm);
    final next = [...levels.value, pcmLevel(pcm)];
    levels.value = next.length > levelHistory ? next.sublist(next.length - levelHistory) : next;
  }

  Map<String, dynamic> _sttStartBody({bool resume = false}) => {
    'session_kind': 'notebook',
    'notebook_id': int.tryParse(notebookId ?? '') ?? notebookId,
    'recording_id': int.tryParse(recordingId ?? '') ?? recordingId,
    if (businessId != null) 'business_id': int.tryParse(businessId!) ?? businessId,
    'device_id': _deviceId,
    'locale': locale,
    if (resume) 'resume': true,
    // Where the live audio continues on the recording's audio clock (the WAV parts' clock): ~0 on the
    // first start, the audio recorded so far after a reconnect / an offline start.
    'offset_ms': _recordedMs,
  };

  /// Audio recorded so far (paused time excluded) — the position of the next live packet.
  int get _recordedMs => _wav?.durationMs ?? elapsed.inMilliseconds;

  Map<String, dynamic> get _ridBody => {'recording_id': int.tryParse(recordingId ?? '') ?? recordingId};

  Future<bool> _startStt({bool resume = false}) async {
    final rid = recordingId;
    if (rid == null || !active) return false;
    if (!_t.connected) {
      _setLive(LiveState.offline);
      return false;
    }
    final ack = await _t.emitAck('stt:start', _sttStartBody(resume: resume));
    if (!active || recordingId != rid) return false;
    if (ack['ok'] == true) {
      _sttOn = true;
      if (phase == RecorderPhase.paused) {
        if (ack['state'] != 'paused') _t.emit('stt:pause', _ridBody);
        _setLive(LiveState.paused);
      } else {
        // The server still had the session paused (a pause from before the reconnect): continue it.
        if (ack['state'] == 'paused') _t.emit('stt:resume', {..._ridBody, 'offset_ms': _recordedMs});
        _setLive(LiveState.live);
      }
      if (notice.value == offlineNotice) notice.value = null;
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
    // Started offline: the create went through, so live captions can start now.
    if (p.op == RecordingOp.create && p.clientSessionId == clientSessionId && recordingId == null && p.recordingId.isNotEmpty) {
      recordingId = p.recordingId;
      _notify();
      if (active) unawaited(_startStt(resume: true));
    }
  }

  // ── pause / resume

  Future<void> pause({String? reason}) async {
    if (phase != RecorderPhase.recording) return;
    phase = RecorderPhase.paused;
    final since = _runningSince;
    if (since != null) _accum += _now().difference(since);
    _runningSince = null;
    if (reason != null) notice.value = reason;
    if (live == LiveState.live) live = LiveState.paused;
    _notify();
    try {
      await _mic?.pause();
    } catch (_) {}
    final rid = recordingId;
    if (rid != null) {
      _t.emit('stt:pause', _ridBody); // also on the socket: REST may land on another server instance
      unawaited(api?.pauseNotebookRecording(notebookId!, rid).then((_) {}, onError: (_) {}));
    }
    unawaited(_fg.update(paused: true, elapsedMs: elapsed.inMilliseconds));
  }

  /// False when it cannot resume now (in a call).
  Future<bool> resume() async {
    if (phase != RecorderPhase.paused) return false;
    if (_inCall) {
      notice.value = inCallText;
      return false;
    }
    phase = RecorderPhase.recording;
    _runningSince = _now();
    if (notice.value == callNotice || notice.value == interruptNotice || notice.value == inCallText) notice.value = null;
    if (live == LiveState.paused) live = LiveState.live;
    _notify();
    try {
      await _mic?.resume();
    } catch (_) {}
    final rid = recordingId;
    if (rid != null) {
      _t.emit('stt:resume', {..._ridBody, 'offset_ms': _recordedMs});
      unawaited(api?.resumeNotebookRecording(notebookId!, rid).then((_) {}, onError: (_) {}));
    }
    unawaited(_fg.update(paused: false, elapsedMs: elapsed.inMilliseconds));
    return true;
  }

  Future<void> togglePause() => paused ? resume() : pause();

  // ── bookmarks / title

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
    unawaited(_fg.update(paused: paused, elapsedMs: elapsed.inMilliseconds, title: title));
  }

  // ── stop

  /// Ends the recording: the last part and the stop go to the upload queue (sent now when online).
  Future<FinishedRecording?> stop() async {
    if (phase != RecorderPhase.recording && phase != RecorderPhase.paused) return null;
    final since = _runningSince;
    if (since != null) _accum += _now().difference(since);
    _runningSince = null;
    phase = RecorderPhase.finishing;
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
    final rid = recordingId;
    if (rid != null) _t.emit('stt:stop', _ridBody); // flushes the live lines; the REST stop finalises
    _sttOn = false;
    final wav = _wav;
    _wav = null;
    var durationMs = elapsed.inMilliseconds;
    var parts = 0;
    if (wav != null) {
      if (wav.totalBytes == 0) wav.add(Uint8List(4800)); // always a final part, so the server can close the session
      await wav.close();
      durationMs = wav.durationMs;
      parts = wav.partsStarted;
    }
    final nb = notebookId!;
    final csid = clientSessionId!;
    await _queue.add(
      RecordingPart.notebookStop(
        notebookId: nb,
        recordingId: rid ?? '',
        clientSessionId: csid,
        durationMs: durationMs,
        parts: parts,
        bookmarks: [for (final b in bookmarks) b.toJson()],
        businessId: businessId,
        deviceId: _deviceId ?? '',
      ),
    );
    unawaited(_fg.stop());
    final done = FinishedRecording(notebookId: nb, clientSessionId: csid, recordingId: rid, title: title, durationMs: durationMs);
    _reset();
    _notify();
    _finished.add(done);
    return done;
  }

  /// The server deleted the recording: stop the mic and drop what is still queued for it.
  Future<void> _discardDeleted() async {
    final csid = clientSessionId, rid = recordingId;
    recordingId = null; // nothing to delete on the server any more
    await _abandon();
    for (final p in _queue.pendingFor(clientSessionId: csid, recordingId: rid)) {
      await _queue.remove(p);
    }
    error = deletedNotice;
    notice.value = deletedNotice;
    _notify();
  }

  /// Something failed while starting: drop what was made.
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
    final rid = recordingId, nb = notebookId;
    if (rid != null && nb != null) unawaited(api?.deleteNotebookRecording(nb, rid).then((_) {}, onError: (_) {}));
    unawaited(_fg.stop());
    _reset();
  }

  void _reset() {
    phase = RecorderPhase.idle;
    live = LiveState.connecting;
    _sttOn = false;
    _runningSince = null;
    _ticker?.cancel();
  }

  // ── timer for the notification (Android shows its own chronometer; this keeps it honest)

  Timer? _ticker;
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (active) unawaited(_fg.update(paused: paused, elapsedMs: elapsed.inMilliseconds));
    });
  }

  void _onAction(String a) {
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
    final rid = recordingId;
    return rid != null && '${d['recording_id']}' == rid;
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    switch (e.type) {
      case 'stt:segment':
        if (!_mine(d) || d['call_id'] != null) return;
        _upsertSegment(
          RecordingSegment(
            seq: (d['seq'] as num?)?.toInt() ?? 0,
            text: '${d['text'] ?? ''}',
            startMs: (d['start_ms'] as num?)?.toInt() ?? 0,
            endMs: (d['end_ms'] as num?)?.toInt() ?? 0,
            speaker: d['speaker']?.toString(),
            partial: d['partial'] == true || d['final'] == false,
          ),
        );
      case 'stt:state':
        if (!_mine(d)) return;
        final s = '${d['state'] ?? ''}';
        switch (s) {
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
            if (d['reason'] == 'deleted') {
              // Deleted (e.g. from the web): nothing to keep recording into.
              unawaited(_discardDeleted());
              return;
            }
            _setLive(LiveState.unavailable);
            notice.value = d['reason'] == 'moved' ? movedNotice : offlineNotice;
        }
      case 'ai:notebook_recording_ready':
        ready.value = d;
      case RealtimeService.connectedEvent:
        _resumeAfterReconnect();
    }
  }

  void _upsertSegment(RecordingSegment s) {
    if (s.text.trim().isEmpty && s.partial) return;
    final list = [...segments.value];
    final i = list.indexWhere((x) => x.seq == s.seq);
    if (i >= 0) {
      if (!list[i].partial && s.partial) return; // a late partial never replaces the final text
      list[i] = s;
    } else {
      list.add(s);
      list.sort((a, b) => a.seq.compareTo(b.seq));
      if (list.length > 600) list.removeRange(0, list.length - 600);
    }
    segments.value = list;
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

  /// Socket came back: take the live transcription again (up to 3 tries); the recording never stopped.
  void _resumeAfterReconnect() {
    if (!active || recordingId == null) return;
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
    segments.dispose();
    levels.dispose();
    ready.dispose();
    super.dispose();
  }
}

/// After sign-in / switching Space (mobile only, like calls).
void bindNotebookRecorder({required ApiClient api, String? businessId}) {
  final r = NotebookRecorder.instance..bind(api: api, businessId: businessId);
  final call = CallService.instance;
  if (call != null) r.attachCall(call);
  RecordingUploadQueue.instance.start(api: api, businessId: businessId);
}
