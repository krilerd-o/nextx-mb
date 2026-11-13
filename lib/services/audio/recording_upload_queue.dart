import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/nx_network.dart';
import '../api_client.dart';

/// Where a queued recording item goes.
enum RecordingTarget {
  /// A call tape part: `POST /api/comm-ai/calls/:id/recording`.
  call,

  /// A notebook recording: `POST /api/ai/notebooks/:id/recordings[/:rid/parts|/stop]`.
  notebook,
}

/// What a queued item does (notebook recordings also queue their create / stop so they keep their
/// order with the audio when the phone is offline).
enum RecordingOp { part, create, stop }

/// One item waiting to be uploaded: usually a WAV part (~5 minutes) of a call or notebook recording.
///
/// JSON written by older versions (call parts only: no `target` / `op`) still reads as call parts.
@immutable
class RecordingPart {
  const RecordingPart({
    this.callId = '',
    required this.path,
    required this.part,
    this.parts = 0,
    this.isFinal = false,
    this.durationMs = 0,
    this.businessId,
    this.deviceId = '',
    this.mime = 'audio/wav',
    this.attempts = 0,
    this.createdAt,
    this.target = RecordingTarget.call,
    this.op = RecordingOp.part,
    this.notebookId = '',
    this.recordingId = '',
    this.clientSessionId = '',
    this.title,
    this.locale,
    this.bookmarks = const [],
  });

  /// A part of a notebook recording ([recordingId] may still be '' while its create is queued).
  const RecordingPart.notebook({
    required this.notebookId,
    required this.recordingId,
    required this.clientSessionId,
    required this.path,
    required this.part,
    this.isFinal = false,
    this.parts = 0,
    this.durationMs = 0,
    this.businessId,
    this.deviceId = '',
    this.createdAt,
  })  : callId = '',
        mime = 'audio/wav',
        attempts = 0,
        target = RecordingTarget.notebook,
        op = RecordingOp.part,
        title = null,
        locale = null,
        bookmarks = const [];

  /// "Create the recording" — queued when starting offline (idempotent on [clientSessionId]).
  const RecordingPart.notebookCreate({
    required this.notebookId,
    required this.clientSessionId,
    this.title,
    this.locale,
    this.businessId,
    this.deviceId = '',
    this.createdAt,
  })  : callId = '',
        path = '',
        part = 0,
        parts = 0,
        isFinal = false,
        durationMs = 0,
        mime = 'audio/wav',
        attempts = 0,
        target = RecordingTarget.notebook,
        op = RecordingOp.create,
        recordingId = '',
        bookmarks = const [];

  /// "Stop the recording" — after the final part, so the server starts processing with every part.
  const RecordingPart.notebookStop({
    required this.notebookId,
    required this.recordingId,
    required this.clientSessionId,
    required this.durationMs,
    this.parts = 0,
    this.bookmarks = const [],
    this.businessId,
    this.deviceId = '',
    this.createdAt,
  })  : callId = '',
        path = '',
        part = 0,
        isFinal = true,
        mime = 'audio/wav',
        attempts = 0,
        target = RecordingTarget.notebook,
        op = RecordingOp.stop,
        title = null,
        locale = null;

  final String callId;
  final String path;
  final int part;

  /// Total number of parts; only known (and sent) on the final part.
  final int parts;
  final bool isFinal;

  /// Total duration of the whole recording (sent with the final part / stop).
  final int durationMs;
  final String? businessId;

  /// Install id of the phone that recorded it (sent with every part; '' for parts queued by older versions).
  final String deviceId;
  final String mime;
  final int attempts;
  final DateTime? createdAt;

  final RecordingTarget target;
  final RecordingOp op;
  final String notebookId;
  final String recordingId;
  final String clientSessionId;
  final String? title;
  final String? locale;

  /// `[{at_ms, label?}]` (stop only).
  final List<Map<String, dynamic>> bookmarks;

  bool get hasFile => op == RecordingOp.part;

  /// Items of one recording (sent in order).
  String get group => target == RecordingTarget.call ? 'call:$callId' : 'nb:${clientSessionId.isNotEmpty ? clientSessionId : recordingId}';

  RecordingPart copyWith({int? attempts, String? recordingId, String? businessId, DateTime? createdAt}) => RecordingPart(
        callId: callId,
        path: path,
        part: part,
        parts: parts,
        isFinal: isFinal,
        durationMs: durationMs,
        businessId: businessId ?? this.businessId,
        deviceId: deviceId,
        mime: mime,
        attempts: attempts ?? this.attempts,
        createdAt: createdAt ?? this.createdAt,
        target: target,
        op: op,
        notebookId: notebookId,
        recordingId: recordingId ?? this.recordingId,
        clientSessionId: clientSessionId,
        title: title,
        locale: locale,
        bookmarks: bookmarks,
      );

  RecordingPart retried() => copyWith(attempts: attempts + 1);

  Map<String, dynamic> toJson() => {
        if (target == RecordingTarget.call) 'call_id': callId,
        'path': path,
        'part': part,
        'parts': parts,
        'final': isFinal,
        'duration_ms': durationMs,
        if (businessId != null) 'business_id': businessId,
        'device_id': deviceId,
        'mime': mime,
        'attempts': attempts,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        if (target != RecordingTarget.call) 'target': target.name,
        if (op != RecordingOp.part) 'op': op.name,
        if (target == RecordingTarget.notebook) ...{
          'notebook_id': notebookId,
          'recording_id': recordingId,
          'client_session_id': clientSessionId,
          'title': ?title,
          'locale': ?locale,
          if (bookmarks.isNotEmpty) 'bookmarks': bookmarks,
        },
      };

  static RecordingPart? fromJson(Object? j) {
    if (j is! Map) return null;
    final target = RecordingTarget.values.where((t) => t.name == '${j['target'] ?? 'call'}').firstOrNull;
    final op = RecordingOp.values.where((o) => o.name == '${j['op'] ?? 'part'}').firstOrNull;
    if (target == null || op == null) return null; // written by a newer version: leave it alone
    final callId = '${j['call_id'] ?? ''}';
    final path = '${j['path'] ?? ''}';
    final notebookId = '${j['notebook_id'] ?? ''}';
    final recordingId = '${j['recording_id'] ?? ''}';
    final clientSessionId = '${j['client_session_id'] ?? ''}';
    if (op == RecordingOp.part && path.isEmpty) return null;
    if (target == RecordingTarget.call && (callId.isEmpty || op != RecordingOp.part)) return null;
    if (target == RecordingTarget.notebook && (notebookId.isEmpty || (recordingId.isEmpty && clientSessionId.isEmpty))) return null;
    final bm = j['bookmarks'];
    return RecordingPart(
      callId: callId,
      path: path,
      part: (j['part'] as num?)?.toInt() ?? 0,
      parts: (j['parts'] as num?)?.toInt() ?? 0,
      isFinal: j['final'] == true,
      durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
      businessId: j['business_id']?.toString(),
      deviceId: '${j['device_id'] ?? ''}',
      mime: '${j['mime'] ?? 'audio/wav'}',
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      target: target,
      op: op,
      notebookId: notebookId,
      recordingId: recordingId,
      clientSessionId: clientSessionId,
      title: j['title']?.toString(),
      locale: j['locale']?.toString(),
      bookmarks: bm is List ? [for (final b in bm) if (b is Map) Map<String, dynamic>.from(b)] : const [],
    );
  }
}

/// Sends one queued item. Returns the recording id for a notebook create (else null).
typedef RecordingSender = Future<String?> Function(ApiClient api, RecordingPart p);

/// Uploads recordings so they are not lost: parts are saved on the phone (not in the temp
/// folder) and in a small JSON queue, sent one by one in order (the final part last, so the server
/// can join them), and retried with back-off, when the app starts and when the network returns.
///
/// Targets are pluggable ([senders]): call tapes and notebook recordings share the queue.
/// Errors the server will keep giving (403 recording turned off, 404 gone, 400) drop the item.
class RecordingUploadQueue extends ChangeNotifier {
  RecordingUploadQueue({Future<Directory> Function()? dir, this.now = DateTime.now}) : _dirFn = dir;

  static RecordingUploadQueue? _instance;
  static RecordingUploadQueue get instance => _instance ??= RecordingUploadQueue();
  @visibleForTesting
  static set instance(RecordingUploadQueue v) => _instance = v;

  static const maxAge = Duration(days: 7);
  static const _backoff = [Duration(seconds: 5), Duration(seconds: 20), Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15)];

  /// How each target is sent (tests and new targets can add their own).
  static final Map<RecordingTarget, RecordingSender> senders = {
    RecordingTarget.call: _sendCall,
    RecordingTarget.notebook: _sendNotebook,
  };

  static Future<String?> _sendCall(ApiClient api, RecordingPart p) async {
    await api.uploadCallRecordingPart(p.callId, p.path, part: p.part, parts: p.parts, isFinal: p.isFinal, durationMs: p.durationMs, mime: p.mime, deviceId: p.deviceId);
    return null;
  }

  static Future<String?> _sendNotebook(ApiClient api, RecordingPart p) async {
    switch (p.op) {
      case RecordingOp.create:
        final item = await api.createNotebookRecording(p.notebookId, title: p.title, locale: p.locale, deviceId: p.deviceId, clientSessionId: p.clientSessionId);
        return '${item['id'] ?? ''}';
      case RecordingOp.part:
        await api.uploadNotebookRecordingPart(p.notebookId, p.recordingId, p.path, part: p.part, isFinal: p.isFinal, durationMs: p.durationMs, deviceId: p.deviceId);
        return null;
      case RecordingOp.stop:
        await api.stopNotebookRecording(p.notebookId, p.recordingId, durationMs: p.durationMs, parts: p.parts, bookmarks: p.bookmarks);
        return null;
    }
  }

  final Future<Directory> Function()? _dirFn;
  final DateTime Function() now;
  ApiClient? api;
  String? businessId;

  final List<RecordingPart> _items = [];
  bool _loaded = false;
  Timer? _retry;
  VoidCallback? _netListener;

  final _sent = StreamController<RecordingPart>.broadcast();
  final _dropped = StreamController<RecordingPart>.broadcast();

  /// Every item the server accepted (a notebook create carries its new `recordingId`).
  Stream<RecordingPart> get sent => _sent.stream;

  /// Items given up on (the server refused them for good).
  Stream<RecordingPart> get dropped => _dropped.stream;

  List<RecordingPart> get pending => List.unmodifiable(_items);

  /// Items still waiting for one notebook recording (by client session id or recording id).
  List<RecordingPart> pendingFor({String? clientSessionId, String? recordingId}) => [
        for (final p in _items)
          if (p.target == RecordingTarget.notebook &&
              ((clientSessionId != null && clientSessionId.isNotEmpty && p.clientSessionId == clientSessionId) || (recordingId != null && recordingId.isNotEmpty && p.recordingId == recordingId)))
            p,
      ];

  Directory? _dir;
  Future<Directory> folder() async {
    if (_dir != null) return _dir!;
    final base = _dirFn != null ? await _dirFn() : await getApplicationSupportDirectory();
    final d = Directory('${base.path}/comm_ai_recordings');
    if (!d.existsSync()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _store() async => File('${(await folder()).path}/queue.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _store();
      if (f.existsSync()) {
        final list = jsonDecode(await f.readAsString());
        if (list is List) {
          for (final j in list) {
            final p = RecordingPart.fromJson(j);
            if (p != null && !_items.any((x) => _same(x, p))) _items.add(p);
          }
        }
      }
    } catch (_) {
      // A broken queue file must not stop recordings; start empty.
    }
    await _dropExpired();
  }

  static bool _same(RecordingPart a, RecordingPart b) =>
      a.hasFile ? (b.hasFile && a.path == b.path) : (!b.hasFile && a.op == b.op && a.group == b.group);

  Future<void> _save() async {
    try {
      final f = await _store();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<void> _dropExpired() async {
    final cutoff = now().subtract(maxAge);
    final old = _items.where((p) => (p.createdAt ?? now()).isBefore(cutoff) || (p.hasFile && !File(p.path).existsSync())).toList();
    if (old.isEmpty) return;
    for (final p in old) {
      _items.remove(p);
      if (p.hasFile) _deleteFile(p.path);
    }
    await _save();
  }

  /// Call once the API client of the current Space is known (and again when it changes).
  void start({required ApiClient api, String? businessId}) {
    this.api = api;
    this.businessId = businessId;
    if (_netListener == null) {
      NxNetwork.instance.ensureStarted();
      _netListener = () {
        if (NxNetwork.instance.online.value) pump();
      };
      NxNetwork.instance.online.addListener(_netListener!);
    }
    unawaited(load().then((_) => pump()));
  }

  Future<void> add(RecordingPart p) async {
    await load();
    // A notebook part queued after its create went through already knows the recording id.
    var item = p.copyWith(businessId: p.businessId ?? businessId, createdAt: p.createdAt ?? now());
    if (item.target == RecordingTarget.notebook && item.recordingId.isEmpty) {
      final known = _created[item.clientSessionId];
      if (known != null) item = item.copyWith(recordingId: known);
    }
    _items.add(item);
    await _save();
    notifyListeners();
    unawaited(pump());
  }

  /// Recording ids learned from queued creates (client session id → recording id).
  final Map<String, String> _created = {};

  /// Sends what can be sent now. Items of one recording go in order; a failing item waits (and
  /// blocks the items after it) until the next retry.
  Future<void> pump() {
    if (api == null) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void>? _running;
  bool _again = false;

  Future<void> _loop() async {
    do {
      _again = false;
      await _pumpOnce();
    } while (_again && _retry?.isActive != true);
  }

  /// Drops a queued item (and its file) — e.g. the recording was deleted on the server.
  Future<void> remove(RecordingPart p) => _remove(p);

  Future<void> _remove(RecordingPart p, {bool deleteFile = true}) async {
    _items.remove(p);
    if (deleteFile && p.hasFile) _deleteFile(p.path);
    await _save();
    notifyListeners();
  }

  Future<void> _pumpOnce() async {
    _retry?.cancel();
    await load();
    while (true) {
      final next = _items.where((p) => p.businessId == null || businessId == null || p.businessId == businessId).firstOrNull;
      if (next == null) break;
      if (next.hasFile && !File(next.path).existsSync()) {
        _items.remove(next);
        await _save();
        continue;
      }
      if (next.target == RecordingTarget.notebook && next.op != RecordingOp.create && next.recordingId.isEmpty) {
        // Its create is gone (refused for good): nowhere to send it.
        await _remove(next);
        _dropped.add(next);
        continue;
      }
      try {
        final sender = senders[next.target];
        if (sender == null) throw StateError('no sender for ${next.target}');
        final rid = await sender(api!, next);
        await _remove(next);
        if (next.op == RecordingOp.create && rid != null && rid.isNotEmpty) {
          _created[next.clientSessionId] = rid;
          for (var i = 0; i < _items.length; i++) {
            final p = _items[i];
            if (p.target == RecordingTarget.notebook && p.clientSessionId == next.clientSessionId && p.recordingId.isEmpty) _items[i] = p.copyWith(recordingId: rid);
          }
          await _save();
          _sent.add(next.copyWith(recordingId: rid));
        } else {
          _sent.add(next);
        }
      } catch (e) {
        if (_permanent(e)) {
          await _remove(next);
          _dropped.add(next);
          if (next.op == RecordingOp.create) {
            // The recording can never be created: its parts have nowhere to go.
            for (final p in [..._items.where((p) => p.group == next.group)]) {
              await _remove(p);
              _dropped.add(p);
            }
          }
          continue;
        }
        final i = _items.indexOf(next);
        final again = next.retried();
        if (i >= 0) _items[i] = again;
        await _save();
        final wait = _backoff[(again.attempts - 1).clamp(0, _backoff.length - 1)];
        _retry = Timer(wait, () => unawaited(pump()));
        break;
      }
    }
  }

  static bool _permanent(Object e) {
    final code = e is ApiException ? e.statusCode : e is ApiEnvelopeException ? e.statusCode : 0;
    return code == 400 || code == 403 || code == 404 || code == 413 || code == 415;
  }

  static void _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  void dispose() {
    _retry?.cancel();
    if (_netListener != null) NxNetwork.instance.online.removeListener(_netListener!);
    _sent.close();
    _dropped.close();
    super.dispose();
  }
}
