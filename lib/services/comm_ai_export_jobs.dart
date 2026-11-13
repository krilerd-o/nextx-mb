import 'dart:async';

import 'api_client.dart';
import 'realtime_service.dart';

/// A background export (ZIP with audio, the call tape, e-mail with audio) that failed on the server.
class CommAiExportJobFailed implements Exception {
  CommAiExportJobFailed(this.message, {this.errorCode});
  final String message;
  final String? errorCode;

  @override
  String toString() => message;
}

/// Starts `POST /api/comm-ai/export-jobs` and follows the job until it is done: `ai:export_job` socket events
/// (to every device of mine) move the progress right away; polling `GET /export-jobs/:id` every [interval]
/// keeps it going when the socket is off. [onProgress] gets each new state. Returns the finished job;
/// throws [CommAiExportJobFailed] when the job fails, [TimeoutException] after [timeout].
/// [isCancelled] stops following (the job itself keeps running on the server).
Future<Map<String, dynamic>> runCommAiExportJob(
  ApiClient api,
  Map<String, dynamic> body, {
  void Function(Map<String, dynamic> job)? onProgress,
  bool Function()? isCancelled,
  Duration interval = const Duration(milliseconds: 1500),
  Duration timeout = const Duration(minutes: 15),
  Stream<RealtimeEvent>? events,
}) async {
  final started = await api.startCommAiExportJob(body);
  final jobId = '${started['job_id'] ?? started['id'] ?? ''}';
  if (jobId.isEmpty) throw ApiException(500, 'no job id');
  var job = {...started, 'job_id': started['job_id'] ?? jobId};
  onProgress?.call(job);
  final done = Completer<Map<String, dynamic>>();
  final end = DateTime.now().add(timeout);
  var polling = false;

  void finish(Map<String, dynamic> j) {
    if (done.isCompleted) return;
    if (j['status'] == 'failed') {
      done.completeError(CommAiExportJobFailed('${j['error'] ?? 'failed'}', errorCode: j['error_code']?.toString()));
    } else {
      done.complete(j);
    }
  }

  Future<void> poll() async {
    if (done.isCompleted || polling) return;
    if (isCancelled?.call() == true) {
      done.completeError(const _Cancelled());
      return;
    }
    polling = true;
    try {
      final j = await api.getCommAiExportJob(jobId);
      job = {...job, ...j};
      if (!done.isCompleted) onProgress?.call(job);
      if (j['status'] == 'done' || j['status'] == 'failed') finish(job);
    } catch (e) {
      if (!done.isCompleted && (e is ApiEnvelopeException && e.statusCode == 404)) done.completeError(e);
    } finally {
      polling = false;
    }
    if (!done.isCompleted && DateTime.now().isAfter(end)) done.completeError(TimeoutException('export job', timeout));
  }

  final sub = (events ?? RealtimeService.instance.on('ai:export_job')).listen((e) {
    if ('${e.data['job_id']}' != jobId || done.isCompleted) return;
    job = {...job, ...e.data};
    onProgress?.call(job);
    // The finished state (download url, e-mail result) always comes from GET, the event only says "now".
    if (e.data['status'] == 'done' || e.data['status'] == 'failed') unawaited(poll());
  });
  final timer = Timer.periodic(interval, (_) => unawaited(poll()));
  if (job['status'] == 'done' || job['status'] == 'failed') unawaited(poll());
  try {
    return await done.future;
  } on _Cancelled {
    throw const CommAiExportCancelled();
  } finally {
    timer.cancel();
    // Not awaited: the shared socket stream may live in another zone (and nothing waits on the cancel).
    unawaited(sub.cancel());
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// The sheet was closed while waiting (the job keeps running on the server).
class CommAiExportCancelled implements Exception {
  const CommAiExportCancelled();
}
