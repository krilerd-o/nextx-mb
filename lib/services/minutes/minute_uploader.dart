import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';

/// One upload of a meeting file (persisted, so it continues after the app closes).
class MinuteUploadJob {
  MinuteUploadJob({
    required this.uploadId,
    required this.meetingId,
    required this.path,
    required this.filename,
    required this.size,
    required this.partSize,
    required this.title,
    this.complete = const {},
    this.sentBytes = 0,
    this.state = 'uploading',
    this.error,
    this.businessId,
    this.userId,
  });

  factory MinuteUploadJob.fromJson(Map<String, dynamic> j) => MinuteUploadJob(
    uploadId: '${j['upload_id']}',
    meetingId: '${j['meeting_id']}',
    path: '${j['path']}',
    filename: '${j['filename'] ?? ''}',
    size: (j['size'] as num).toInt(),
    partSize: (j['part_size'] as num).toInt(),
    title: '${j['title'] ?? ''}',
    complete: j['complete'] is Map ? Map<String, dynamic>.from(j['complete'] as Map) : const {},
    sentBytes: (j['sent_bytes'] as num?)?.toInt() ?? 0,
    state: '${j['state'] ?? 'uploading'}',
    error: j['error']?.toString(),
    businessId: j['business_id']?.toString(),
    userId: j['user_id']?.toString(),
  );

  final String uploadId;
  final String meetingId;
  final String path;
  final String filename;
  final int size;
  final int partSize;
  final String title;

  /// The business the meeting belongs to (parts keep going there after a business switch) and who uploads.
  final String? businessId;
  final String? userId;

  /// Body of `POST …/complete` (features chosen before uploading).
  final Map<String, dynamic> complete;
  int sentBytes;

  /// uploading | paused (no network / error, retried) | done | failed
  String state;
  String? error;

  int get partsTotal => size <= 0 ? 1 : (size + partSize - 1) ~/ partSize;
  double get progress => size <= 0 ? 0 : (sentBytes / size).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'upload_id': uploadId,
    'meeting_id': meetingId,
    'path': path,
    'filename': filename,
    'size': size,
    'part_size': partSize,
    'title': title,
    'complete': complete,
    'sent_bytes': sentBytes,
    'state': state,
    'error': ?error,
    'business_id': ?businessId,
    'user_id': ?userId,
  };
}

/// Uploads large meeting files (up to several GB) in parts to `/api/ai/minutes/uploads`:
/// asks the server which parts it already has, sends only the missing ones, one at a time, retries with
/// back-off, and continues when the app starts again. The file is read part by part (never all in memory).
class MinuteUploader extends ChangeNotifier {
  MinuteUploader({this.prefsKey = 'minutes.uploads'});

  static MinuteUploader? _instance;
  static MinuteUploader get instance => _instance ??= MinuteUploader();
  @visibleForTesting
  static set instance(MinuteUploader v) => _instance = v;

  final String prefsKey;
  ApiClient? api;
  final List<MinuteUploadJob> jobs = [];
  bool _loaded = false;
  bool _running = false;
  Timer? _retry;
  int _failures = 0;

  /// Tests shorten the back-off.
  @visibleForTesting
  Duration Function(int failures) backoff = (n) => Duration(seconds: [5, 15, 30, 60, 120][n.clamp(0, 4)]);

  final _done = StreamController<MinuteUploadJob>.broadcast();

  /// A file finished uploading (the server is processing it now).
  Stream<MinuteUploadJob> get done => _done.stream;

  String? _userId;

  /// After sign-in / switching business. Only this user's uploads run (another account on the same phone
  /// never sends or sees them); each upload talks to its own business.
  Future<void> bind(ApiClient api, {String? userId}) async {
    this.api = api;
    _userId = userId;
    await _load();
    notifyListeners();
    unawaited(_pump());
  }

  bool _isMine(MinuteUploadJob j) => j.userId == null || _userId == null || j.userId == _userId;

  /// This user's uploads (all businesses).
  List<MinuteUploadJob> get mine => [for (final j in jobs) if (_isMine(j)) j];

  /// This user's uploads into [businessId] (what a business's meeting list shows).
  List<MinuteUploadJob> forBusiness(String? businessId) =>
      [for (final j in mine) if (j.businessId == null || businessId == null || j.businessId == businessId) j];

  /// Signed out: stop sending (the files stay queued for when this user signs in again).
  void signOut() {
    _retry?.cancel();
    api = null;
    _userId = null;
    notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
      if (raw == null) return;
      for (final j in (jsonDecode(raw) as List)) {
        if (j is Map) jobs.add(MinuteUploadJob.fromJson(Map<String, dynamic>.from(j)));
      }
      jobs.removeWhere((j) => j.state == 'done' || !File(j.path).existsSync());
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(prefsKey, jsonEncode([for (final j in jobs) if (j.state != 'done') j.toJson()]));
    } catch (_) {}
  }

  MinuteUploadJob? jobFor(String meetingId) => jobs.where((j) => j.meetingId == meetingId).firstOrNull;

  /// Start uploading [path]. [body] = title, languages, template, ref …; [complete] = features for processing.
  Future<MinuteUploadJob> add({required String path, required String filename, required String mime, Map<String, dynamic> body = const {}, Map<String, dynamic> complete = const {}}) async {
    final a = api;
    if (a == null) throw StateError('not bound');
    await _load();
    final size = await File(path).length();
    final bid = a.effectiveBusinessId;
    final r = await a.startMinuteUpload({...body, 'filename': filename, 'mime': mime, 'size': size, 'client_session_id': 'upl-${path.hashCode}-$size'});
    final up = Map<String, dynamic>.from(r['upload'] as Map);
    final item = Map<String, dynamic>.from((r['item'] as Map?) ?? const {});
    final job = MinuteUploadJob(
      uploadId: '${up['upload_id']}',
      meetingId: '${up['meeting_id'] ?? item['id']}',
      path: path,
      filename: filename,
      size: size,
      partSize: (up['part_size'] as num).toInt(),
      title: '${item['title'] ?? filename}',
      complete: complete,
      businessId: bid,
      userId: _userId,
    );
    jobs.removeWhere((j) => j.uploadId == job.uploadId);
    jobs.add(job);
    await _save();
    notifyListeners();
    unawaited(_pump());
    return job;
  }

  Future<void> cancel(MinuteUploadJob job) async {
    jobs.remove(job);
    await _save();
    notifyListeners();
    try {
      await ApiClient.inBusiness(job.businessId, () async => api?.abortMinuteUpload(job.uploadId));
    } catch (_) {}
  }

  /// Try now (after an error / when the network is back).
  void retryNow() {
    _retry?.cancel();
    _failures = 0;
    for (final j in jobs) {
      if (j.state == 'paused') j.state = 'uploading';
    }
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) return;
    final a = api;
    if (a == null) return;
    _running = true;
    try {
      while (true) {
        final job = jobs.where((j) => j.state == 'uploading' && _isMine(j)).firstOrNull;
        if (job == null) break;
        try {
          await ApiClient.inBusiness(job.businessId, () => _run(a, job));
          _failures = 0;
        } on ApiEnvelopeException catch (e) {
          if (e.statusCode == 404 || e.statusCode == 409 && e.errorCode == 'UPLOAD_CLOSED' || e.statusCode == 413 || e.statusCode == 415) {
            job
              ..state = 'failed'
              ..error = e.message;
          } else {
            _pause(job, e.message);
          }
        } catch (e) {
          _pause(job, 'การเชื่อมต่อขัดข้อง — จะลองต่อให้อัตโนมัติ');
        }
        await _save();
        notifyListeners();
        if (job.state == 'paused') break;
      }
    } finally {
      _running = false;
    }
  }

  void _pause(MinuteUploadJob job, String message) {
    job
      ..state = 'paused'
      ..error = message;
    _retry?.cancel();
    _retry = Timer(backoff(_failures++), () {
      job.state = 'uploading';
      unawaited(_pump());
    });
  }

  Future<void> _run(ApiClient a, MinuteUploadJob job) async {
    final status = await a.getMinuteUpload(job.uploadId);
    if (status['status'] == 'done') {
      job.state = 'done';
      _done.add(job);
      jobs.remove(job);
      return;
    }
    final missing = [for (final n in (status['missing'] as List? ?? const [])) (n as num).toInt()];
    final have = job.partsTotal - missing.length;
    job.sentBytes = (have * job.partSize).clamp(0, job.size);
    job.error = null;
    notifyListeners();
    final raf = await File(job.path).open();
    try {
      for (final n in missing) {
        final start = n * job.partSize;
        final len = (job.size - start).clamp(0, job.partSize);
        await raf.setPosition(start);
        final bytes = await raf.read(len);
        final base = job.sentBytes;
        await a.putMinuteUploadPart(job.uploadId, n, bytes, onSendProgress: (sent, _) {
          job.sentBytes = (base + sent).clamp(0, job.size);
          notifyListeners();
        });
        job.sentBytes = (base + len).clamp(0, job.size);
        await _save();
        notifyListeners();
      }
    } finally {
      await raf.close();
    }
    await a.completeMinuteUpload(job.uploadId, job.complete);
    job.state = 'done';
    job.sentBytes = job.size;
    jobs.remove(job);
    _done.add(job);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _done.close();
    super.dispose();
  }
}
