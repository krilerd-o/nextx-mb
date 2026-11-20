part of '../api_client.dart';

/// ISAAC AI Minute Meeting (ไอแซคบันทึกประชุม) — NEXTX `/api/ai/minutes*` and the public room / share routes.
extension MinutesApi on ApiClient {
  Map<String, dynamic> _mItem(Map<String, dynamic> env) {
    final d = _dataMap(env);
    final item = d['item'];
    return item is Map ? Map<String, dynamic>.from(item) : d;
  }

  /// What the server supports: `{rooms, languages:[{code,name}], templates:[{key,th,en}], upload:{part_size,max_bytes}, …}`.
  Future<Map<String, dynamic>> getMinutesConfig() async => _dataMap(await _send('GET', '/api/ai/minutes/config'));

  Future<List<Map<String, dynamic>>> getMinuteMeetings({String? q, String? source, String? status, int limit = 30, int offset = 0}) async {
    final env = await _send('GET', '/api/ai/minutes', query: {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'source': ?source,
      'status': ?status,
      'limit': '$limit',
      if (offset > 0) 'offset': '$offset',
    });
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  /// Live recording on this phone: `{title, locale, languages, client_session_id, device_id, …}` → the meeting.
  Future<Map<String, dynamic>> createMinuteMeeting(Map<String, dynamic> body) async => _mItem(await _send('POST', '/api/ai/minutes', data: body));

  /// `{item, segments, summaries, translations, room}`.
  Future<Map<String, dynamic>> getMinuteMeeting(String id) async => _dataMap(await _send('GET', '/api/ai/minutes/$id'));

  Future<Map<String, dynamic>> updateMinuteMeeting(String id, Map<String, dynamic> body) async => _mItem(await _send('PATCH', '/api/ai/minutes/$id', data: body));

  Future<void> deleteMinuteMeeting(String id) async => _send('DELETE', '/api/ai/minutes/$id');

  Future<Map<String, dynamic>> uploadMinutePart(String id, String filePath, {required int part, bool isFinal = false, int durationMs = 0}) async {
    final form = FormData.fromMap({
      'part': '$part',
      'final': isFinal ? 'true' : 'false',
      if (isFinal) 'duration_ms': '$durationMs',
      'audio': await MultipartFile.fromFile(filePath, filename: 'part-$part.wav', contentType: DioMediaType.parse('audio/wav')),
    });
    return _dataMap(await _send('POST', '/api/ai/minutes/$id/parts', data: form, options: Options(sendTimeout: const Duration(minutes: 5))));
  }

  Future<Map<String, dynamic>> pauseMinuteMeeting(String id) async => _dataMap(await _send('POST', '/api/ai/minutes/$id/pause'));
  Future<Map<String, dynamic>> resumeMinuteMeeting(String id) async => _dataMap(await _send('POST', '/api/ai/minutes/$id/resume'));

  /// `{duration_ms, parts, bookmarks, summary_mode:'now'|'later', template, features, languages}`.
  Future<Map<String, dynamic>> stopMinuteMeeting(String id, Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/ai/minutes/$id/stop', data: body));

  Future<Map<String, dynamic>> retryMinuteMeeting(String id) async => _dataMap(await _send('POST', '/api/ai/minutes/$id/retry'));

  Future<Map<String, dynamic>> editMinuteSegment(String id, int seq, {String? text, String? speaker}) async =>
      _dataMap(await _send('PATCH', '/api/ai/minutes/$id/segments/$seq', data: {'text': ?text, 'speaker': ?speaker}));

  Future<Map<String, dynamic>> summarizeMinuteMeeting(String id, {String? template, String? lang}) async {
    final d = _dataMap(await _send('POST', '/api/ai/minutes/$id/summarize', data: {'template': ?template, 'lang': ?lang}, options: Options(receiveTimeout: const Duration(minutes: 6))));
    final s = d['summary'];
    return s is Map ? Map<String, dynamic>.from(s) : d;
  }

  /// Starts a whole-meeting translation (socket `ai:minute_translation` when done).
  Future<void> translateMinuteMeeting(String id, String lang) async => _send('POST', '/api/ai/minutes/$id/translate', data: {'lang': lang});

  /// `{answer, refs:[{at, at_ms}]}`.
  Future<Map<String, dynamic>> askMinuteMeeting(String id, String question) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/$id/ask', data: {'question': question}, options: Options(receiveTimeout: const Duration(minutes: 3))));

  Future<List<Map<String, dynamic>>> createMinuteTasks(String id, {List<int>? items, Map<String, int>? owners}) async {
    final d = _dataMap(await _send('POST', '/api/ai/minutes/$id/actions/create-tasks', data: {'items': ?items, 'owners': ?owners}));
    return extractMapList(d['results']);
  }

  Future<List<int>> downloadMinuteExport(String id, {String format = 'pdf', String? lang, List<String> include = const ['summary', 'actions', 'transcript']}) => _downloadBytes(
        '/api/ai/minutes/$id/export?format=$format&include=${include.join(',')}${lang != null ? '&lang=$lang' : ''}',
        receiveTimeout: const Duration(minutes: 3),
      );

  Future<List<int>> downloadMinuteMedia(String id) => _downloadBytes('/api/ai/minutes/$id/media?download=1', receiveTimeout: const Duration(minutes: 15));

  Future<List<Map<String, dynamic>>> getMinuteLinks(String id) async {
    final d = _dataMap(await _send('GET', '/api/ai/minutes/$id/share/links'));
    return extractMapList(d['items']);
  }

  /// `{days, password, include, allow_download, allowed_emails, lang}` → `{token, url, expires_at, …}`.
  Future<Map<String, dynamic>> createMinuteLink(String id, Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/ai/minutes/$id/share/links', data: body));

  Future<void> revokeMinuteLink(String linkId) async => _send('DELETE', '/api/ai/minutes/share/links/$linkId');

  /// Shared inside the business (read only): `[{id, type: user|role|business, target_id, name}]`.
  Future<List<Map<String, dynamic>>> getMinuteShares(String id) async {
    final d = _dataMap(await _send('GET', '/api/ai/minutes/$id/shares'));
    return [for (final x in (d['items'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
  }

  Future<Map<String, dynamic>> addMinuteShare(String id, {required String type, int? targetId}) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/$id/shares', data: {'type': type, 'target_id': ?targetId}));

  Future<void> removeMinuteShare(String id, String shareId) async => _send('DELETE', '/api/ai/minutes/$id/shares/$shareId');

  /// PDPA "ลบข้อมูลของฉัน": my meetings here + my lines / chat in other people's rooms.
  Future<Map<String, dynamic>> deleteMyMinuteData() async => _dataMap(await _send('DELETE', '/api/ai/minutes/me/data'));

  Future<Map<String, dynamic>> emailMinutes(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/$id/share/email', data: body, options: Options(receiveTimeout: const Duration(minutes: 3))));

  // ── workspace: notes · checklist · board · sketch

  /// `{items:[{uid, kind, data, pos, version, author…}], can_edit}`.
  Future<Map<String, dynamic>> getMinuteBoard(String id) async => _dataMap(await _send('GET', '/api/ai/minutes/$id/board'));

  /// Ops `{t:'put'|'del'|'clear', …}` → `{items, errors, cleared}` (when the socket is down).
  Future<Map<String, dynamic>> postMinuteBoardOps(String id, List<Map<String, dynamic>> ops) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/$id/board/ops', data: {'ops': ops}));

  /// Open checklist items → CRM tasks; `[{uid, activity_id, owner_id, error?}]`.
  Future<List<Map<String, dynamic>>> createMinuteBoardTasks(String id, {List<String>? uids}) async {
    final d = _dataMap(await _send('POST', '/api/ai/minutes/$id/board/tasks', data: {'uids': ?uids}));
    return extractMapList(d['results']);
  }

  // ── resumable upload

  /// `{upload:{upload_id, part_size, parts_total, missing}, item}`.
  Future<Map<String, dynamic>> startMinuteUpload(Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/ai/minutes/uploads', data: body));

  Future<Map<String, dynamic>> getMinuteUpload(String uploadId) async {
    final d = _dataMap(await _send('GET', '/api/ai/minutes/uploads/$uploadId'));
    final u = d['upload'];
    return u is Map ? Map<String, dynamic>.from(u) : d;
  }

  Future<void> putMinuteUploadPart(String uploadId, int n, Uint8List bytes, {CancelToken? cancel, ProgressCallback? onSendProgress}) async {
    await _send(
      'PUT',
      '/api/ai/minutes/uploads/$uploadId/parts/$n',
      data: Stream<List<int>>.value(bytes),
      cancel: cancel,
      onSendProgress: onSendProgress,
      options: Options(
        contentType: 'application/octet-stream',
        headers: {Headers.contentLengthHeader: bytes.length},
        sendTimeout: const Duration(minutes: 5),
      ),
    );
  }

  Future<Map<String, dynamic>> completeMinuteUpload(String uploadId, Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/ai/minutes/uploads/$uploadId/complete', data: body));

  Future<void> abortMinuteUpload(String uploadId) async => _send('DELETE', '/api/ai/minutes/uploads/$uploadId');

  // ── rooms

  /// `{title, settings}` → `{room:{id, code, link, settings…}, item}`.
  Future<Map<String, dynamic>> createMinuteRoom(Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/ai/minutes/rooms', data: body));

  Future<Map<String, dynamic>> getMinuteRoom(String meetingId) async => _dataMap(await _send('GET', '/api/ai/minutes/rooms/$meetingId'));

  Future<Map<String, dynamic>> updateMinuteRoomSettings(String meetingId, Map<String, dynamic> settings) async =>
      _dataMap(await _send('PATCH', '/api/ai/minutes/rooms/$meetingId/settings', data: {'settings': settings}));

  /// Signed-in join → `{status:'joined'|'waiting', token, livekit_url, ticket, identity, role}`.
  Future<Map<String, dynamic>> joinMinuteRoom(String meetingId, {String? password, String? ticket}) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/rooms/$meetingId/join', data: {'password': ?password, 'ticket': ?ticket}));

  /// Join by link code (works for any room the rules allow).
  Future<Map<String, dynamic>> joinMinuteRoomByCode(String code, {String? name, String? email, String? password, String? ticket}) async =>
      _dataMap(await _send('POST', '/api/public/minutes/rooms/$code/join', data: {'name': ?name, 'email': ?email, 'password': ?password, 'ticket': ?ticket}));

  /// Lobby info of a link code.
  Future<Map<String, dynamic>> getMinuteRoomLobby(String code) async => _dataMap(await _send('GET', '/api/public/minutes/rooms/$code'));

  Future<void> leaveMinuteRoom(String code, String ticket) async => _send('POST', '/api/public/minutes/rooms/$code/leave', data: {'ticket': ticket});

  Future<Map<String, dynamic>> endMinuteRoom(String meetingId) async => _dataMap(await _send('POST', '/api/ai/minutes/rooms/$meetingId/end'));

  Future<List<Map<String, dynamic>>> getMinuteRoomParticipants(String meetingId) async {
    final d = _dataMap(await _send('GET', '/api/ai/minutes/rooms/$meetingId/participants'));
    return extractMapList(d['items']);
  }

  Future<void> admitMinuteGuest(String meetingId, String identity, {bool allow = true}) async =>
      _send('POST', '/api/ai/minutes/rooms/$meetingId/admit', data: {'identity': identity, 'allow': allow});

  Future<void> removeMinuteParticipant(String meetingId, String identity) async => _send('POST', '/api/ai/minutes/rooms/$meetingId/remove', data: {'identity': identity});

  /// Host: stop someone's screen share.
  Future<void> stopMinuteShare(String meetingId, String identity) async => _send('POST', '/api/ai/minutes/rooms/$meetingId/stop-share', data: {'identity': identity});

  /// Pin a camera / screen / the shared board on everyone's stage (`null` = unpin) → `{pin, by, at}`.
  Future<Map<String, dynamic>> setMinuteRoomStage(String meetingId, Map<String, dynamic>? pin) async {
    final d = _dataMap(await _send('POST', '/api/ai/minutes/rooms/$meetingId/stage', data: {'pin': pin}));
    final st = d['stage'];
    return st is Map ? Map<String, dynamic>.from(st) : const {};
  }

  Future<void> setMinuteCohost(String meetingId, String identity, {bool on = true}) async =>
      _send('POST', '/api/ai/minutes/rooms/$meetingId/cohost', data: {'identity': identity, 'on': on});

  Future<Map<String, dynamic>> inviteToMinuteRoom(String meetingId, List<String> emails, {String? message}) async =>
      _dataMap(await _send('POST', '/api/ai/minutes/rooms/$meetingId/invite', data: {'emails': emails, 'message': ?message}));
}
