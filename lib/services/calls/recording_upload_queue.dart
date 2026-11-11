import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/nx_network.dart';
import '../api_client.dart';

/// One file waiting to be uploaded: a part of a call recording (WAV, ~5 minutes).
@immutable
class RecordingPart {
  const RecordingPart({
    required this.callId,
    required this.path,
    required this.part,
    this.parts = 0,
    this.isFinal = false,
    this.durationMs = 0,
    this.businessId,
    this.mime = 'audio/wav',
    this.attempts = 0,
    this.createdAt,
  });

  final String callId;
  final String path;
  final int part;

  /// Total number of parts; only known (and sent) on the final part.
  final int parts;
  final bool isFinal;

  /// Total duration of the whole recording (sent with the final part).
  final int durationMs;
  final String? businessId;
  final String mime;
  final int attempts;
  final DateTime? createdAt;

  RecordingPart retried() => RecordingPart(
        callId: callId,
        path: path,
        part: part,
        parts: parts,
        isFinal: isFinal,
        durationMs: durationMs,
        businessId: businessId,
        mime: mime,
        attempts: attempts + 1,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'call_id': callId,
        'path': path,
        'part': part,
        'parts': parts,
        'final': isFinal,
        'duration_ms': durationMs,
        if (businessId != null) 'business_id': businessId,
        'mime': mime,
        'attempts': attempts,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };

  static RecordingPart? fromJson(Object? j) {
    if (j is! Map) return null;
    final callId = '${j['call_id'] ?? ''}';
    final path = '${j['path'] ?? ''}';
    if (callId.isEmpty || path.isEmpty) return null;
    return RecordingPart(
      callId: callId,
      path: path,
      part: (j['part'] as num?)?.toInt() ?? 0,
      parts: (j['parts'] as num?)?.toInt() ?? 0,
      isFinal: j['final'] == true,
      durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
      businessId: j['business_id']?.toString(),
      mime: '${j['mime'] ?? 'audio/wav'}',
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
    );
  }
}

/// Uploads call recordings so they are not lost: parts are saved on the phone (not in the temp
/// folder) and in a small JSON queue, sent one by one in order (the final part last, so the server
/// can join them), and retried with back-off, when the app starts and when the network returns.
///
/// Errors the server will keep giving (403 recording turned off, 404 call gone, 400) drop the part.
class RecordingUploadQueue extends ChangeNotifier {
  RecordingUploadQueue({Future<Directory> Function()? dir, this.now = DateTime.now}) : _dirFn = dir;

  static RecordingUploadQueue? _instance;
  static RecordingUploadQueue get instance => _instance ??= RecordingUploadQueue();
  @visibleForTesting
  static set instance(RecordingUploadQueue v) => _instance = v;

  static const maxAge = Duration(days: 7);
  static const _backoff = [Duration(seconds: 5), Duration(seconds: 20), Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15)];

  final Future<Directory> Function()? _dirFn;
  final DateTime Function() now;
  ApiClient? api;
  String? businessId;

  final List<RecordingPart> _items = [];
  bool _loaded = false;
  Timer? _retry;
  VoidCallback? _netListener;

  List<RecordingPart> get pending => List.unmodifiable(_items);

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
            if (p != null && !_items.any((x) => x.path == p.path)) _items.add(p);
          }
        }
      }
    } catch (_) {
      // A broken queue file must not stop calls; start empty.
    }
    await _dropExpired();
  }

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
    final old = _items.where((p) => (p.createdAt ?? now()).isBefore(cutoff) || !File(p.path).existsSync()).toList();
    if (old.isEmpty) return;
    for (final p in old) {
      _items.remove(p);
      _deleteFile(p.path);
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
    _items.add(RecordingPart(
      callId: p.callId,
      path: p.path,
      part: p.part,
      parts: p.parts,
      isFinal: p.isFinal,
      durationMs: p.durationMs,
      businessId: p.businessId ?? businessId,
      mime: p.mime,
      createdAt: p.createdAt ?? now(),
    ));
    await _save();
    notifyListeners();
    unawaited(pump());
  }

  /// Sends what can be sent now. Parts of one call go in order; a failing part waits (and blocks
  /// the parts after it) until the next retry.
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

  Future<void> _pumpOnce() async {
    _retry?.cancel();
    {
      await load();
      while (true) {
        final next = _items.where((p) => p.businessId == null || businessId == null || p.businessId == businessId).firstOrNull;
        if (next == null) break;
        final file = File(next.path);
        if (!file.existsSync()) {
          _items.remove(next);
          await _save();
          continue;
        }
        try {
          await api!.uploadCallRecordingPart(next.callId, next.path,
              part: next.part, parts: next.parts, isFinal: next.isFinal, durationMs: next.durationMs, mime: next.mime);
          _items.remove(next);
          _deleteFile(next.path);
          await _save();
          notifyListeners();
        } catch (e) {
          if (_permanent(e)) {
            _items.remove(next);
            _deleteFile(next.path);
            await _save();
            notifyListeners();
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
    super.dispose();
  }
}
