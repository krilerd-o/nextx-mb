part of '../api_client.dart';

/// ISAAC Notebook — NEXTX `/api/ai/notebooks*` (same endpoints as the web
/// `aiApi.notebooks`), plus the background job poll and file downloads.
extension NotebookApi on ApiClient {
  Map<String, dynamic> _item(Map<String, dynamic> env) {
    final d = _dataMap(env);
    final item = d['item'];
    return item is Map ? Map<String, dynamic>.from(item) : d;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> env) {
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  static Object _id(String id) => int.tryParse(id) ?? id;

  Future<List<Map<String, dynamic>>> getNotebooks() async => _items(await _send('GET', '/api/ai/notebooks'));

  /// [appearance] `{color, icon, cover, pinned}` (notebook v6; older servers ignore it).
  Future<Map<String, dynamic>> createNotebook({required String title, String description = '', String visibility = 'private', String? conversationId, Map<String, dynamic>? appearance}) async =>
      _item(await _send('POST', '/api/ai/notebooks', data: {
        'title': title,
        'description': description,
        'visibility': visibility,
        if (conversationId != null) 'conversation_id': _id(conversationId),
        'appearance': ?appearance,
      }));

  /// Notebook with `sources[]` and `notes[]`.
  Future<Map<String, dynamic>> getNotebook(String id) async => _item(await _send('GET', '/api/ai/notebooks/$id'));

  Future<Map<String, dynamic>> updateNotebook(String id, Map<String, dynamic> body) async =>
      _item(await _send('PATCH', '/api/ai/notebooks/$id', data: body));

  /// `{chat_settings: {goal, custom_prompt, persona, length}}` (merged by the server);
  /// [settings] null resets to the defaults. 400 `SYS_400_VALIDATION` when a custom goal has no prompt.
  Future<Map<String, dynamic>> updateNotebookChatSettings(String id, Map<String, dynamic>? settings) async =>
      _item(await _send('PATCH', '/api/ai/notebooks/$id', data: {'chat_settings': settings}));

  Future<void> deleteNotebook(String id) async => _send('DELETE', '/api/ai/notebooks/$id');

  /// "ลบข้อมูลของฉัน": every Notebook recording this user made in the business (audio, transcript,
  /// its recording source and summary note). Returns counts {recordings, segments, files, sources, notes, notebook_ids}.
  Future<Map<String, dynamic>> deleteMyNotebookRecordings() async =>
      _dataMap(await _send('DELETE', '/api/comm-ai/me/notebook-recordings'));

  // ── sources

  /// `{source_kind, title, content, url, source_config}`; with `knowledge_ids`
  /// the server imports library entries and answers `{items}`.
  Future<List<Map<String, dynamic>>> addNotebookSource(String id, Map<String, dynamic> body) async {
    final env = await _send('POST', '/api/ai/notebooks/$id/sources', data: body);
    final d = _dataMap(env);
    if (d['items'] is List) return extractMapList(d['items']);
    final item = d['item'];
    return item is Map ? [Map<String, dynamic>.from(item)] : const [];
  }

  Future<Map<String, dynamic>> updateNotebookSource(String id, String sourceId, Map<String, dynamic> body) async =>
      _item(await _send('PATCH', '/api/ai/notebooks/$id/sources/$sourceId', data: body));

  /// Returns the notebook (with sources) in the new order.
  Future<Map<String, dynamic>> reorderNotebookSources(String id, List<String> ids) async =>
      _item(await _send('POST', '/api/ai/notebooks/$id/sources/reorder', data: {'ids': [for (final s in ids) _id(s)]}));

  Future<Map<String, dynamic>> selectNotebookSources(String id, List<String> ids, {required bool enabled}) async =>
      _item(await _send('POST', '/api/ai/notebooks/$id/sources/select', data: {'ids': [for (final s in ids) _id(s)], 'enabled': enabled}));

  Future<void> deleteNotebookSource(String id, String sourceId) async => _send('DELETE', '/api/ai/notebooks/$id/sources/$sourceId');

  Future<Map<String, dynamic>> refreshNotebookSource(String id, String sourceId) async =>
      _item(await _send('POST', '/api/ai/notebooks/$id/sources/$sourceId/refresh'));

  // ── notes

  Future<Map<String, dynamic>> addNotebookNote(String id, Map<String, dynamic> body) async =>
      _item(await _send('POST', '/api/ai/notebooks/$id/notes', data: body));

  Future<Map<String, dynamic>> updateNotebookNote(String id, String noteId, Map<String, dynamic> body) async =>
      _item(await _send('PATCH', '/api/ai/notebooks/$id/notes/$noteId', data: body));

  Future<void> deleteNotebookNote(String id, String noteId) async => _send('DELETE', '/api/ai/notebooks/$id/notes/$noteId');

  // ── studio

  /// Sync: the new note (`item`). Async: `{queued: true, jobId}`.
  Future<Map<String, dynamic>> runNotebookStudio(
    String id, {
    required String kind,
    required List<String> sourceIds,
    String locale = 'th',
    String? templateId,
    bool async = false,
    Map<String, dynamic>? options,
  }) async {
    final d = _dataMap(await _send(
      'POST',
      '/api/ai/notebooks/$id/studio',
      data: {
        'kind': kind,
        'source_ids': [for (final s in sourceIds) _id(s)],
        'locale': locale,
        'auto': true,
        'provider': 'auto',
        'template_id': ?templateId,
        if (async) 'async': true,
        if (options != null && options.isNotEmpty) 'options': options,
      },
      options: Options(receiveTimeout: const Duration(minutes: 4)),
    ));
    return d;
  }

  /// `{enabled, worker_seen_recently}` — background studio jobs available.
  Future<Map<String, dynamic>> getAiJobsStatus() async => _dataMap(await _send('GET', '/api/ai/jobs-status'));

  /// `{id, state, progress: {phase}, returnvalue, failedReason}`.
  Future<Map<String, dynamic>> getAiJob(String jobId) async => _dataMap(await _send('GET', '/api/ai/jobs/$jobId'));

  // ── guide (NEXTX notebook v2; 404 on older servers)

  /// `{summary, topics[], questions[], generated_at, stale}`.
  Future<Map<String, dynamic>> getNotebookGuide(String id, {String locale = 'th'}) async =>
      _dataMap(await _send('GET', '/api/ai/notebooks/$id/guide', query: {'locale': locale}));

  Future<Map<String, dynamic>> refreshNotebookGuide(String id, {String locale = 'th'}) async => _dataMap(await _send(
        'POST',
        '/api/ai/notebooks/$id/guide/refresh',
        query: {'locale': locale},
        options: Options(receiveTimeout: const Duration(minutes: 2)),
      ));

  // ── recordings (NEXTX notebook v2; 404 on older servers)

  /// `{item:{id, notebook_id, title, status:'recording', started_at, locale}}` — idempotent on [clientSessionId].
  Future<Map<String, dynamic>> createNotebookRecording(String id, {String? title, String? locale, String? deviceId, String? clientSessionId}) async =>
      _item(await _send('POST', '/api/ai/notebooks/$id/recordings', data: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'locale': ?locale,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (clientSessionId != null && clientSessionId.isNotEmpty) 'client_session_id': clientSessionId,
      }));

  /// One WAV part (PCM16 mono 24 kHz) — `{received, part}`.
  Future<Map<String, dynamic>> uploadNotebookRecordingPart(String id, String recordingId, String filePath,
      {required int part, bool isFinal = false, int durationMs = 0, String deviceId = ''}) async {
    final form = FormData.fromMap({
      'part': '$part',
      'final': isFinal ? 'true' : 'false',
      if (isFinal) 'duration_ms': '$durationMs',
      if (deviceId.isNotEmpty) 'device_id': deviceId,
      'audio': await MultipartFile.fromFile(filePath, filename: 'part-$part.wav', contentType: DioMediaType.parse('audio/wav')),
    });
    return _dataMap(await _send('POST', '/api/ai/notebooks/$id/recordings/$recordingId/parts', data: form, options: Options(sendTimeout: const Duration(minutes: 5))));
  }

  Future<Map<String, dynamic>> pauseNotebookRecording(String id, String recordingId) async => _dataMap(await _send('POST', '/api/ai/notebooks/$id/recordings/$recordingId/pause'));

  Future<Map<String, dynamic>> resumeNotebookRecording(String id, String recordingId) async => _dataMap(await _send('POST', '/api/ai/notebooks/$id/recordings/$recordingId/resume'));

  /// `{status:'processing'}`. [parts]: how many parts were recorded (0 = no audio; the server waits for all).
  Future<Map<String, dynamic>> stopNotebookRecording(String id, String recordingId, {required int durationMs, int parts = 0, List<Map<String, dynamic>> bookmarks = const []}) async =>
      _dataMap(await _send('POST', '/api/ai/notebooks/$id/recordings/$recordingId/stop', data: {'duration_ms': durationMs, if (parts > 0) 'parts': parts, 'bookmarks': bookmarks}));

  /// The recording with `segments[]`, `status`, `source_id`, `note_id`.
  Future<Map<String, dynamic>> getNotebookRecording(String id, String recordingId) async => _item(await _send('GET', '/api/ai/notebooks/$id/recordings/$recordingId'));

  Future<List<Map<String, dynamic>>> getNotebookRecordings(String id) async => _items(await _send('GET', '/api/ai/notebooks/$id/recordings'));

  Future<void> deleteNotebookRecording(String id, String recordingId) async => _send('DELETE', '/api/ai/notebooks/$id/recordings/$recordingId');

  Future<Map<String, dynamic>> retryNotebookRecording(String id, String recordingId) async => _dataMap(await _send('POST', '/api/ai/notebooks/$id/recordings/$recordingId/retry'));

  /// The joined audio of a finished recording (needs the session).
  Future<List<int>> downloadNotebookRecordingAudio(String id, String recordingId) =>
      _downloadBytes('/api/ai/notebooks/$id/recordings/$recordingId/audio', receiveTimeout: const Duration(minutes: 3));

  // ── shares

  Future<List<Map<String, dynamic>>> getNotebookShares(String id) async => _items(await _send('GET', '/api/ai/notebooks/$id/shares'));

  /// [mode]: read_only | users | roles | business. `{item, path, public_path}`.
  Future<Map<String, dynamic>> createNotebookShare(String id, {required String mode, List<({String type, String id})> targets = const []}) async =>
      _dataMap(await _send('POST', '/api/ai/notebooks/$id/shares', data: {
        'share_mode': mode,
        if (targets.isNotEmpty) 'targets': [for (final t in targets) {'share_to_type': t.type, 'share_to_id': _id(t.id)}],
      }));

  Future<void> revokeNotebookShare(String id, String shareId) async => _send('DELETE', '/api/ai/notebooks/$id/shares/$shareId');

  // ── library (business knowledge) for "คลังความรู้"

  Future<List<Map<String, dynamic>>> getAiKnowledge() async => _items(await _send('GET', '/api/ai/knowledge'));

  /// Bytes of a studio export (`/api/ai/exports/:token`, needs the session).
  Future<List<int>> downloadNotebookExport(String url) => _downloadBytes(url, receiveTimeout: const Duration(minutes: 2));
}
