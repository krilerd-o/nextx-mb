import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show MultipartFile, DioMediaType;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'photo_pipeline.dart';

/// One photo waiting to be sent, kept on disk until the server has it.
@immutable
class QueuedPhoto {
  const QueuedPhoto({
    required this.clientId,
    required this.scope,
    required this.module,
    required this.recordId,
    required this.path,
    required this.filename,
    required this.takenAt,
    this.title,
    this.lat,
    this.lng,
    this.failed = false,
  });

  final String clientId;

  /// Server + user + business — only sent while that Space is signed in.
  final String scope;
  final String module;
  final String recordId;
  final String? title;
  final String path;
  final String filename;
  final DateTime takenAt;
  final double? lat;
  final double? lng;

  /// Tried and refused for a reason retrying won't fix soon (kept for "ลองใหม่").
  final bool failed;

  PhotoTarget get target => PhotoTarget(module, recordId, title: title);

  QueuedPhoto copyWith({bool? failed}) => QueuedPhoto(
        clientId: clientId,
        scope: scope,
        module: module,
        recordId: recordId,
        title: title,
        path: path,
        filename: filename,
        takenAt: takenAt,
        lat: lat,
        lng: lng,
        failed: failed ?? this.failed,
      );

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'scope': scope,
        'module': module,
        'record_id': recordId,
        if (title != null) 'title': title,
        'path': path,
        'filename': filename,
        'taken_at': takenAt.toIso8601String(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (failed) 'failed': true,
      };

  static QueuedPhoto? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['taken_at']}');
    if (j['client_id'] == null || j['path'] == null || at == null) return null;
    return QueuedPhoto(
      clientId: '${j['client_id']}',
      scope: '${j['scope'] ?? ''}',
      module: '${j['module']}',
      recordId: '${j['record_id']}',
      title: j['title']?.toString(),
      path: '${j['path']}',
      filename: '${j['filename'] ?? 'photo.jpg'}',
      takenAt: at,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      failed: j['failed'] == true,
    );
  }
}

/// Live numbers for the floating upload pill shown on every screen.
@immutable
class UploadCenterState {
  const UploadCenterState({this.active = 0, this.sent = 0, this.total = 0, this.waiting = 0, this.failed = 0, this.offline = false});

  /// Photos being prepared / sent right now (all batches + background drain).
  final int active;
  final int sent;
  final int total;

  /// Saved on the phone, not yet sent (app was closed, no signal, other Space…).
  final int waiting;

  /// Refused by the server; can be retried.
  final int failed;
  final bool offline;

  bool get visible => active > 0 || waiting > 0 || failed > 0;
  double get fraction => total == 0 ? 0 : (sent / total).clamp(0, 1);
}

/// Every photo upload in the app goes through here:
/// - each prepared photo is written to `photo_queue/` **before** it is sent,
///   and removed once the server has it → nothing is lost when the app is
///   closed or the network drops;
/// - [drain] sends what is left (on start, resume, sign-in, back online);
/// - [state] feeds the floating progress pill on every screen.
class PhotoUploadCenter extends ValueNotifier<UploadCenterState> {
  PhotoUploadCenter._() : super(const UploadCenterState());
  static final PhotoUploadCenter instance = PhotoUploadCenter._();

  /// Test hook: where the queue lives (null = app documents folder).
  @visibleForTesting
  static Directory? debugDir;

  /// Current signed-in Space (set by AppConfig) — batches tag photos with it.
  String scope = '';

  final List<QueuedPhoto> _items = [];
  final Set<PhotoBatch> _batches = {};
  bool _loaded = false;
  bool _draining = false;
  Directory? _dir;
  int _drainSent = 0, _drainTotal = 0;
  bool _offline = false;

  /// Called when a record got new photos (e.g. to refresh an open page).
  final StreamController<PhotoTarget> _uploaded = StreamController.broadcast();
  Stream<PhotoTarget> get uploaded => _uploaded.stream;

  List<QueuedPhoto> get items => List.unmodifiable(_items);

  Future<Directory?> _folder() async {
    if (_dir != null) return _dir;
    if (kIsWeb) return null;
    try {
      final base = debugDir ?? await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/photo_queue');
      if (!d.existsSync()) d.createSync(recursive: true);
      return _dir = d;
    } catch (_) {
      return null; // no storage (tests without a folder): photos are only kept in memory
    }
  }

  File _manifest(Directory d) => File('${d.path}/queue.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final d = await _folder();
    if (d == null) return;
    try {
      final f = _manifest(d);
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString());
      if (list is List) {
        for (final j in list) {
          final q = QueuedPhoto.fromJson(j);
          if (q != null && File(q.path).existsSync() && !_items.any((e) => e.clientId == q.clientId)) _items.add(q);
        }
      }
    } catch (e) {
      debugPrint('[photo-queue] load: $e');
    }
    _emit();
  }

  Future<void> _save() async {
    final d = await _folder();
    if (d == null) return;
    try {
      await _manifest(d).writeAsString(jsonEncode([for (final q in _items) q.toJson()]), flush: true);
    } catch (e) {
      debugPrint('[photo-queue] save: $e');
    }
  }

  /// Keeps [p] on disk until [done] is called for its client id.
  Future<void> keep(PhotoTarget target, PreparedPhoto p) async {
    await load();
    final d = await _folder();
    if (d == null) return;
    try {
      final f = File('${d.path}/${p.clientId}.jpg');
      await f.writeAsBytes(p.bytes, flush: true);
      _items.removeWhere((e) => e.clientId == p.clientId);
      _items.add(QueuedPhoto(
        clientId: p.clientId,
        scope: scope,
        module: target.module,
        recordId: target.id,
        title: target.title,
        path: f.path,
        filename: p.filename,
        takenAt: p.takenAt,
        lat: p.lat,
        lng: p.lng,
      ));
      await _save();
    } catch (e) {
      debugPrint('[photo-queue] keep: $e');
    }
  }

  /// The server has it: forget the copy.
  Future<void> done(String clientId) async {
    final i = _items.indexWhere((e) => e.clientId == clientId);
    if (i < 0) return;
    final q = _items.removeAt(i);
    try {
      final f = File(q.path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    await _save();
    _emit();
  }

  Future<void> markFailed(String clientId) async {
    final i = _items.indexWhere((e) => e.clientId == clientId);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(failed: true);
    await _save();
    _emit();
  }

  /// Removes a photo the user gave up on.
  Future<void> discard(String clientId) => done(clientId);

  void register(PhotoBatch b) {
    if (_batches.add(b)) b.addListener(_emit);
    _emit();
  }

  void unregister(PhotoBatch b) {
    if (_batches.remove(b)) b.removeListener(_emit);
    _emit();
  }

  set offline(bool v) {
    if (v == _offline) return;
    _offline = v;
    _emit();
  }

  void _emit() {
    var active = 0, sent = 0, total = 0;
    for (final b in _batches) {
      final v = b.value;
      if (!v.busy) continue;
      active += v.total - v.uploaded - v.failed;
      sent += v.uploaded;
      total += v.total;
    }
    if (_draining) {
      active += _drainTotal - _drainSent;
      sent += _drainSent;
      total += _drainTotal;
    }
    final inBatch = {for (final b in _batches) ...b.clientIds};
    final idle = _items.where((q) => !inBatch.contains(q.clientId)).toList();
    final waiting = _draining ? 0 : idle.where((q) => !q.failed).length;
    final failed = idle.where((q) => q.failed).length;
    value = UploadCenterState(active: active, sent: sent, total: total, waiting: waiting, failed: failed, offline: _offline);
  }

  /// Sends saved photos of the signed-in Space. Comment-style records get one
  /// comment with their photos (like a normal batch).
  Future<int> drain(ApiClient api, {bool includeFailed = false, PhotoUploader? uploader}) async {
    await load();
    if (_draining || scope.isEmpty) return 0;
    final inBatch = {for (final b in _batches) ...b.clientIds};
    final todo = _items.where((q) => q.scope == scope && !inBatch.contains(q.clientId) && (includeFailed || !q.failed)).toList();
    if (todo.isEmpty) return 0;
    _draining = true;
    _drainSent = 0;
    _drainTotal = todo.length;
    _emit();
    final send = uploader ?? defaultPhotoUploader(api);
    final comments = <String, List<Map<String, dynamic>>>{};
    var ok = 0;
    try {
      for (final q in todo) {
        final f = File(q.path);
        if (!f.existsSync()) {
          await done(q.clientId);
          continue;
        }
        final p = PreparedPhoto(bytes: await f.readAsBytes(), filename: q.filename, clientId: q.clientId, takenAt: q.takenAt, lat: q.lat, lng: q.lng);
        try {
          final r = await send(q.target, p);
          if (r != null && q.module != 'job' && q.module != 'activity') {
            comments.putIfAbsent('${q.module}|${q.recordId}', () => []).add(r);
          }
          await done(q.clientId);
          ok++;
          _drainSent++;
          _offline = false;
          _uploaded.add(q.target);
          _emit();
        } catch (e) {
          final code = e is ApiException ? e.statusCode : e is ApiEnvelopeException ? e.statusCode : 0;
          if (code == 0 || code == 408 || code >= 500) {
            _offline = code == 0;
            break; // no signal / server down: try again later, keep order
          }
          await markFailed(q.clientId);
          _drainSent++;
        }
      }
      for (final e in comments.entries) {
        final parts = e.key.split('|');
        try {
          await api.postEntityComment(parts[0], parts[1], 'รูปถ่าย ${e.value.length} รูป', attachments: e.value);
        } catch (_) {}
      }
    } finally {
      _draining = false;
      _emit();
    }
    return ok;
  }

  @visibleForTesting
  Future<void> debugReset() async {
    for (final b in List.of(_batches)) {
      unregister(b);
    }
    _items.clear();
    _loaded = false;
    _draining = false;
    _dir = null;
    _offline = false;
    scope = '';
    value = const UploadCenterState();
  }
}

/// Builds a multipart part from queued bytes (kept for callers outside the pipeline).
MultipartFile queuedPart(Uint8List bytes, String filename) => MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType('image', 'jpeg'));
