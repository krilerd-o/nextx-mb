import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/app_alice.dart';
import 'api_exceptions.dart';

export 'api_exceptions.dart';

/// Default production CRM API. Override with `--dart-define=API_BASE_URL=` or Settings.
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://moainext.moai-crm.com',
);

/// Flutter web on localhost cannot call production (CORS). Debug preview uses this proxy.
const String kWebDebugApiProxyUrl = 'http://127.0.0.1:8787';

String resolveApiBaseUrl([String? configured]) {
  final raw = (configured ?? kDefaultApiBaseUrl).trim().replaceAll(RegExp(r'/+$'), '');
  final base = raw.isEmpty ? kDefaultApiBaseUrl : raw;
  if (kIsWeb && kDebugMode && base.contains('moainext.moai-crm.com')) {
    return kWebDebugApiProxyUrl;
  }
  return base;
}

@Deprecated('Use kDefaultApiBaseUrl')
const String apiBaseUrl = kDefaultApiBaseUrl;

List<Map<String, dynamic>> extractMapList(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (raw is Map) {
    for (final key in ['list', 'items', 'businesses', 'rooms', 'data', 'users', 'packages']) {
      final v = raw[key];
      if (v is List) return extractMapList(v);
    }
  }
  return [];
}

Map<String, dynamic>? asStringKeyedMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

class ModuleFieldSchema {
  ModuleFieldSchema({
    required this.fields,
    Map<String, List<Map<String, dynamic>>>? picklists,
  }) : picklists = picklists ?? {};

  final List<Map<String, dynamic>> fields;
  final Map<String, List<Map<String, dynamic>>> picklists;
}

class EntityListPage {
  EntityListPage({
    required this.items,
    required this.limit,
    required this.offset,
    this.page = 1,
    this.total,
  });
  final List<Map<String, dynamic>> items;
  final int limit;
  final int offset;
  final int page;
  final int? total;
  bool get hasMore {
    if (total != null) return offset + items.length < total!;
    return items.length >= limit;
  }
}

class ApiClient {
  ApiClient({VoidCallback? onUnauthorized, Dio? dio}) : _onUnauthorized = onUnauthorized {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: resolveApiBaseUrl(),
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 45),
          ),
        );
    if (_dio.options.baseUrl.isEmpty) {
      _dio.options.baseUrl = resolveApiBaseUrl();
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final bid = _businessId;
          if (bid != null && bid.isNotEmpty) {
            options.headers['X-Business-Id'] = bid;
          }
          handler.next(options);
        },
        onError: (err, handler) {
          final code = err.response?.statusCode;
          final path = err.requestOptions.path;
          final isAuthCall = path.contains('/api/auth/login') ||
              path.contains('/api/auth/register') ||
              path.contains('/api/auth/otp/');
          if (code == 401 && !isAuthCall) {
            _onUnauthorized?.call();
          }
          handler.next(err);
        },
      ),
    );
    final alice = appAliceDioInterceptor;
    if (alice != null) {
      _dio.interceptors.add(alice);
    }
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          error: true,
        ),
      );
    }
  }

  late final Dio _dio;
  VoidCallback? _onUnauthorized;
  String? _accessToken;
  String? _businessId;

  void setOnUnauthorized(VoidCallback? cb) => _onUnauthorized = cb;

  /// Widget tests route requests to a fake adapter instead of the network.
  @visibleForTesting
  void debugSetHttpAdapter(HttpClientAdapter adapter) => _dio.httpClientAdapter = adapter;

  void attachSession({
    required String baseUrl,
    String? accessToken,
    String? userId,
    String? businessId,
  }) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = resolveApiBaseUrl(trimmed);
    _accessToken = accessToken;
    _businessId = businessId;
  }

  String get baseUrl => _dio.options.baseUrl;
  String? get accessToken => _accessToken;
  String? get businessId => _businessId;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    Options? options,
  }) async {
    try {
      final isForm = data is FormData;
      final res = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: data,
        options: (options ?? Options()).copyWith(
          method: method,
          contentType: isForm ? null : options?.contentType,
        ),
      );
      return _decodeEnvelope(res);
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Exception _fromDio(DioException e) {
    final res = e.response;
    if (res != null) {
      try {
        return _envelopeError(res.statusCode ?? 0, res.data);
      } catch (err) {
        if (err is ApiEnvelopeException || err is ApiException) return err as Exception;
      }
      return ApiException(res.statusCode ?? 0, '${res.data}');
    }
    return ApiException(0, e.message ?? 'network');
  }

  Map<String, dynamic> _decodeEnvelope(Response<dynamic> res) {
    final raw = res.data;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final status = map['status']?.toString();
      if (status == 'E') {
        throw ApiEnvelopeException(
          res.statusCode ?? 400,
          map['error_code']?.toString() ?? 'ERROR',
          map['message']?.toString() ?? res.statusMessage ?? 'Error',
        );
      }
      if ((res.statusCode ?? 200) >= 400) {
        throw ApiException(res.statusCode ?? 400, '$raw');
      }
      return map;
    }
    if ((res.statusCode ?? 200) >= 400) {
      throw ApiException(res.statusCode ?? 400, '${res.data}');
    }
    return {'status': 'S', 'data': res.data};
  }

  Exception _envelopeError(int statusCode, dynamic raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      if (map['status']?.toString() == 'E') {
        return ApiEnvelopeException(
          statusCode,
          map['error_code']?.toString() ?? 'ERROR',
          map['message']?.toString() ?? 'Error',
        );
      }
    }
    return ApiException(statusCode, '$raw');
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    return asStringKeyedMap(data) ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getHealth() async {
    try {
      return _dataMap(await _send('GET', '/api/health'));
    } catch (_) {
      return _dataMap(await _send('GET', '/health'));
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    final env = await _send('POST', '/api/auth/login', data: {
      'email': email,
      'password': password,
      'remember': remember,
    });
    return _dataMap(env);
  }

  Future<void> requestEmailOtp(String email) async {
    await _send('POST', '/api/auth/otp/email/request', data: {'email': email, 'locale': 'th'});
  }

  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String code}) async {
    return _dataMap(await _send('POST', '/api/auth/otp/email/verify', data: {
      'email': email,
      'code': code,
      'remember': true,
    }));
  }

  Future<void> logoutRemote() async {
    try {
      await _send('POST', '/api/auth/logout');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getMe() async {
    return _dataMap(await _send('GET', '/api/me'));
  }

  Future<List<Map<String, dynamic>>> getBusinesses() async {
    final env = await _send('GET', '/api/me/businesses');
    final data = env['data'];
    return extractMapList(data);
  }

  Future<List<String>> getMenuKeys({String? packageCode}) async {
    final env = await _send(
      'GET',
      '/api/me/menus',
      query: {
        if (packageCode != null && packageCode.isNotEmpty) 'package': packageCode,
      },
    );
    final data = env['data'];
    if (data is Map && data['menu_keys'] is List) {
      return (data['menu_keys'] as List).map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<List<dynamic>> getModules() async {
    final env = await _send('GET', '/api/modules');
    final data = env['data'];
    if (data is List) return data;
    if (data is Map && data['list'] is List) return data['list'] as List;
    return [];
  }

  Future<EntityListPage> getEntityList(
    String module, {
    int limit = 30,
    int offset = 0,
    int? page,
    String? q,
    Map<String, String>? extra,
  }) async {
    final p = page ?? ((offset ~/ (limit == 0 ? 30 : limit)) + 1);
    final query = <String, dynamic>{
      'limit': '$limit',
      'page': '$p',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      ...?extra,
    };
    final env = await _send('GET', '/api/entity/$module', query: query);
    final data = env['data'];
    final items = extractMapList(data);
    int? total;
    int usedLimit = limit;
    int usedPage = p;
    if (data is Map) {
      final meta = data['meta'];
      if (meta is Map) {
        if (meta['total'] is num) total = (meta['total'] as num).toInt();
        if (meta['limit'] is num) usedLimit = (meta['limit'] as num).toInt();
        if (meta['page'] is num) usedPage = (meta['page'] as num).toInt();
      }
      if (data['limit'] is num) usedLimit = (data['limit'] as num).toInt();
      if (data['page'] is num) usedPage = (data['page'] as num).toInt();
      if (data['total'] is num) total = (data['total'] as num).toInt();
    }
    return EntityListPage(
      items: items,
      limit: usedLimit,
      offset: (usedPage - 1) * usedLimit,
      page: usedPage,
      total: total,
    );
  }

  Future<Map<String, dynamic>> getEntity(String module, String id) async {
    return _dataMap(await _send('GET', '/api/entity/$module/$id'));
  }

  Future<Map<String, dynamic>> putEntity(
    String module,
    String id,
    Map<String, dynamic> payload, {
    String? accessToken,
    String? userId,
    String? businessId,
  }) async {
    if (accessToken != null) _accessToken = accessToken;
    if (businessId != null) _businessId = businessId;
    return _dataMap(await _send('PUT', '/api/entity/$module/$id', data: payload));
  }

  Future<Map<String, dynamic>> postEntity(
    String module,
    Map<String, dynamic> payload,
  ) async {
    return _dataMap(await _send('POST', '/api/entity/$module', data: payload));
  }

  Future<List<Map<String, dynamic>>> getFields(String module) async {
    final schema = await getFieldSchema(module);
    return schema.fields;
  }

  Future<ModuleFieldSchema> getFieldSchema(String module) async {
    final env = await _send(
      'GET',
      '/api/fields/$module',
      query: {'include_picklists': '1'},
    );
    final data = env['data'];
    final fields = extractMapList(data);
    final picklists = <String, List<Map<String, dynamic>>>{};
    if (data is Map && data['picklists'] is Map) {
      (data['picklists'] as Map).forEach((key, value) {
        picklists[key.toString()] = extractMapList(value);
      });
    }
    return ModuleFieldSchema(fields: fields, picklists: picklists);
  }

  Future<List<Map<String, dynamic>>> getPicklists() async {
    final env = await _send('GET', '/api/picklists');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getPicklistValues(String name) async {
    final env = await _send('GET', '/api/picklists/values/$name');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getUsers({String? q, int limit = 80}) async {
    final env = await _send('GET', '/api/users', query: {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'limit': '$limit',
    });
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getBusinessPackages() async {
    final bid = _businessId;
    if (bid == null || bid.isEmpty) return [];
    final env = await _send('GET', '/api/businesses/$bid/packages');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getEntityComments(String module, String id) async {
    final env = await _send('GET', '/api/entity/$module/$id/comments');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postEntityComment(
    String module,
    String id,
    String body,
  ) async {
    return _dataMap(await _send(
      'POST',
      '/api/entity/$module/$id/comments',
      data: {'body': body},
    ));
  }

  Future<List<Map<String, dynamic>>> getEntityTags(String module, String id) async {
    final env = await _send('GET', '/api/entity/$module/$id/tags');
    return extractMapList(env['data']);
  }

  Future<void> assignEntityTag(String module, String id, int tagId) async {
    await _send('POST', '/api/entity/$module/$id/tags', data: {'tag_id': tagId});
  }

  Future<void> removeEntityTag(String module, String id, int tagId) async {
    await _send('DELETE', '/api/entity/$module/$id/tags/$tagId');
  }

  Future<List<Map<String, dynamic>>> getTags({String? module, String? q}) async {
    final env = await _send('GET', '/api/tags', query: {
      if (module != null) 'module': module,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>?> getAttendanceSummary() async {
    final data = _dataMap(await _send('GET', '/api/hr/attendance/summary'));
    return asStringKeyedMap(data['summary']);
  }

  Future<List<Map<String, dynamic>>> getAttendance({String? dateFrom, String? dateTo}) async {
    final env = await _send('GET', '/api/hr/attendance', query: {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> clockIn({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    return _dataMap(await _send('POST', '/api/hr/attendance/clock-in', data: {
      'source': 'app',
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
    }));
  }

  Future<Map<String, dynamic>> clockOut({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    return _dataMap(await _send('POST', '/api/hr/attendance/clock-out', data: {
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
    }));
  }

  Future<List<Map<String, dynamic>>> getLeaveTypes() async {
    final env = await _send('GET', '/api/hr/leave-types');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getLeaveBalance({int? year}) async {
    final env = await _send('GET', '/api/hr/leave-balance', query: {
      if (year != null) 'year': '$year',
    });
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getLeaveRequests({bool all = false, String? status}) async {
    final env = await _send('GET', '/api/hr/leave-requests', query: {
      if (all) 'all': '1',
      if (status != null) 'status': status,
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postLeaveRequest({
    required int leaveTypeId,
    required String startDate,
    required String endDate,
    String? reason,
  }) async {
    return _dataMap(await _send('POST', '/api/hr/leave-requests', data: {
      'leave_type_id': leaveTypeId,
      'start_date': startDate,
      'end_date': endDate,
      if (reason != null) 'reason': reason,
    }));
  }

  /// Requester cancels their own Pending request (NEXTX `PUT /leave-requests/:id/cancel`).
  Future<void> cancelLeave(String id) async {
    await _send('PUT', '/api/hr/leave-requests/$id/cancel');
  }

  Future<Map<String, dynamic>> approveLeave(String id, {required bool approve, String? reason}) async {
    return _dataMap(await _send('PUT', '/api/hr/leave-requests/$id/approve', data: {
      'action': approve ? 'approve' : 'reject',
      if (reason != null) 'reject_reason': reason,
    }));
  }

  Future<Map<String, dynamic>> getActivityVisit(String id) async {
    return _dataMap(await _send('GET', '/api/activity/$id/visit'));
  }

  Future<Map<String, dynamic>> validateCheckin(String id, {required double lat, required double lng}) async {
    return _dataMap(await _send(
      'GET',
      '/api/activity/$id/checkin/validate',
      query: {'location': '$lat,$lng'},
    ));
  }

  Future<Map<String, dynamic>> activityCheckin(
    String id, {
    required double lat,
    required double lng,
  }) async {
    return _dataMap(await _send('POST', '/api/activity/$id/checkin', data: {
      'location': '$lat,$lng',
    }));
  }

  Future<Map<String, dynamic>> activityCheckout(
    String id, {
    required double lat,
    required double lng,
  }) async {
    return _dataMap(await _send('POST', '/api/activity/$id/checkout', data: {
      'location': '$lat,$lng',
    }));
  }

  Future<void> uploadActivityPhotos(String id, List<MultipartFile> files) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('files[]', f));
    }
    await _send('POST', '/api/activity/$id/photos', data: form);
  }

  Future<List<Map<String, dynamic>>> getBoards({String? q}) async {
    final env = await _send('GET', '/api/boards', query: {
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getBoardStatuses(String boardId) async {
    final env = await _send('GET', '/api/boards/$boardId/statuses');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getWorkspaceItems({
    String? boardIds,
    String? q,
    int limit = 200,
  }) async {
    final env = await _send('GET', '/api/workspace/items', query: {
      if (boardIds != null && boardIds.isNotEmpty) 'board_ids': boardIds,
      if (q != null && q.isNotEmpty) 'q': q,
      'limit': '$limit',
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> putBoardTask(
    String boardId,
    String taskId,
    Map<String, dynamic> body,
  ) async {
    return _dataMap(await _send('PUT', '/api/boards/$boardId/tasks/$taskId', data: body));
  }

  /// Soft-deletes a task (moved to the workspace trash on the server).
  Future<void> deleteBoardTask(String boardId, String taskId) async {
    await _send('DELETE', '/api/boards/$boardId/tasks/$taskId');
  }

  Future<List<Map<String, dynamic>>> getTaskComments(String boardId, String taskId) async {
    final env = await _send('GET', '/api/boards/$boardId/tasks/$taskId/comments');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postTaskComment(String boardId, String taskId, String body) async {
    return _dataMap(await _send('POST', '/api/boards/$boardId/tasks/$taskId/comments', data: {'body': body}));
  }

  Future<List<Map<String, dynamic>>> getTaskWorklogs(String boardId, String taskId) async {
    final env = await _send('GET', '/api/boards/$boardId/tasks/$taskId/worklogs');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postTaskWorklog(
    String boardId,
    String taskId, {
    required int minutes,
    String? description,
  }) async {
    return _dataMap(await _send(
      'POST',
      '/api/boards/$boardId/tasks/$taskId/worklogs',
      data: {
        'time_spent_minutes': minutes,
        if (description != null) 'work_description': description,
      },
    ));
  }

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    return (await getNotificationsPage(limit: limit)).items;
  }

  /// Cursor-paged notifications. [category] matches NEXTX categories
  /// (work, case, calendar, chat, sales, quotation, job, mail, …).
  Future<({List<Map<String, dynamic>> items, String? nextCursor})> getNotificationsPage({
    int limit = 30,
    String? cursor,
    String? category,
    bool unreadOnly = false,
  }) async {
    final env = await _send('GET', '/api/notifications', query: {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (category != null && category != 'all') 'category': category,
      if (unreadOnly) 'unread': '1',
    });
    final data = env['data'];
    final next = data is Map ? data['next_cursor']?.toString() : null;
    return (items: extractMapList(data), nextCursor: (next == null || next.isEmpty || next == 'null') ? null : next);
  }

  Future<void> deleteNotification(String id) async {
    await _send('DELETE', '/api/notifications/$id');
  }

  /// Module counts, recent records and upcoming activities for the home screen
  /// (`GET /api/dashboard/home-summary`, already scoped to the user's menus).
  Future<Map<String, dynamic>> getHomeSummary() async {
    return _dataMap(await _send('GET', '/api/dashboard/home-summary'));
  }

  /// My workspace items grouped by due bucket (`GET /api/home/work`).
  /// `counts` holds overdue / today / upcoming / nodue.
  Future<Map<String, dynamic>> getHomeWork({String bucket = 'all', int limit = 10}) async {
    return _dataMap(await _send('GET', '/api/home/work', query: {'bucket': bucket, 'limit': '$limit'}));
  }

  Future<Map<String, dynamic>> getNotificationSummary() async {
    return _dataMap(await _send('GET', '/api/notifications/summary'));
  }

  Future<void> markNotificationRead(String id) async {
    await _send('PATCH', '/api/notifications/$id/read');
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceName,
  }) async {
    await _send('POST', '/api/notifications/device-token', data: {
      'token': token,
      'platform': platform,
      if (deviceName != null) 'device_name': deviceName,
    });
  }

  Future<List<Map<String, dynamic>>> getChatRooms() async {
    final env = await _send('GET', '/api/chat/rooms');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getCallLogWork({int limit = 50}) async {
    final env = await _send('GET', '/api/call-log/work', query: {
      'limit': '$limit',
      'scope': 'mine',
    });
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getMyJobs({int limit = 50}) async {
    final env = await _send('GET', '/api/field-service/me/jobs', query: {
      'limit': '$limit',
    });
    return extractMapList(env['data']);
  }

  /// Multi-turn chat: send the conversation so far in [messages].
  Future<Map<String, dynamic>> postAiChat({
    required List<Map<String, dynamic>> messages,
    bool auto = true,
    String? conversationId,
  }) async {
    return _dataMap(await _send('POST', '/api/ai/chat', data: {
      'messages': messages,
      'auto': auto,
      if (conversationId != null && conversationId.isNotEmpty) 'conversation_id': conversationId,
    }));
  }

  Future<Map<String, dynamic>> activityRsvp(String id, String response) async {
    return _dataMap(await _send('POST', '/api/activity/$id/rsvp', data: {
      'response': response,
    }));
  }

  Future<Map<String, dynamic>> createJobInspection(String jobId, {String? templateKey}) async {
    return _dataMap(await _send('POST', '/api/field-service/jobs/$jobId/inspection', data: {
      if (templateKey != null) 'template_key': templateKey,
    }));
  }

  Future<List<Map<String, dynamic>>> getInspectionLines(String inspectionId) async {
    final env = await _send('GET', '/api/field-service/inspections/$inspectionId/lines');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> putInspectionLines(
    String inspectionId,
    List<Map<String, dynamic>> lines,
  ) async {
    final env = await _send('PUT', '/api/field-service/inspections/$inspectionId/lines', data: {
      'lines': lines,
    });
    return extractMapList(env['data']);
  }

  Future<List<int>> getInspectionPdf(String inspectionId) =>
      _downloadBytes('/api/field-service/inspections/$inspectionId/pdf');

  Future<Map<String, dynamic>> postBoardTask(String boardId, {required String title, String? description}) async {
    return _dataMap(await _send('POST', '/api/boards/$boardId/tasks', data: {
      'title': title,
      if (description != null) 'description': description,
    }));
  }

  Future<Map<String, dynamic>> postCallLogResult(
    String id, {
    String? outcome,
    String? notes,
    int? durationSec,
  }) async {
    return _dataMap(await _send('POST', '/api/call-log/$id/result', data: {
      if (outcome != null) 'outcome': outcome,
      if (notes != null) 'notes': notes,
      if (durationSec != null) 'duration_sec': durationSec,
    }));
  }

  Future<Map<String, dynamic>> getCallLogWorkItem(String id) async {
    return _dataMap(await _send('GET', '/api/call-log/work/$id'));
  }

  Future<List<Map<String, dynamic>>> getQuotationLines(String id) async {
    final env = await _send('GET', '/api/quotation/$id/lines');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> putQuotationLines(
    String id,
    List<Map<String, dynamic>> lines,
  ) async {
    final env = await _send('PUT', '/api/quotation/$id/lines', data: {'lines': lines});
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> convertQuotationToOrder(String id) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/convert-to-order'));
  }

  Future<Map<String, dynamic>> convertQuotationToContract(String id) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/convert-to-contract'));
  }

  Future<List<Map<String, dynamic>>> getDealLines(String id) async {
    final env = await _send('GET', '/api/entity/deal/$id/lines');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> putDealLines(
    String id,
    List<Map<String, dynamic>> lines,
  ) async {
    final env = await _send('PUT', '/api/entity/deal/$id/lines', data: {'lines': lines});
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getDealContacts(String id) async {
    final env = await _send('GET', '/api/entity/deal/$id/contacts');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> createDealQuotation(String id) async {
    return _dataMap(await _send('POST', '/api/entity/deal/$id/quotations'));
  }

  Future<Map<String, dynamic>> previewLeadConvert(String id) async {
    return _dataMap(await _send('GET', '/api/entity/lead/$id/convert/preview'));
  }

  Future<Map<String, dynamic>> convertLead(String id, [Map<String, dynamic>? body]) async {
    return _dataMap(await _send('POST', '/api/entity/lead/$id/convert', data: body ?? const {}));
  }

  Future<void> deleteEntity(String module, String id) async {
    await _send('DELETE', '/api/entity/$module/$id');
  }

  Future<List<int>> downloadJobPdf(String id) async {
    try {
      return await _downloadBytes('/api/field-service/jobs/$id/pdf');
    } catch (_) {
      return _downloadBytes('/api/field-service/jobs/$id/birt-pdf');
    }
  }

  Future<Map<String, dynamic>> scheduleJob(String id, {String? when}) async {
    return _dataMap(await _send('POST', '/api/field-service/jobs/$id/schedule', data: {
      if (when != null) 'scheduled_at': when,
    }));
  }

  Future<List<Map<String, dynamic>>> getJobSkills(String id) async {
    final env = await _send('GET', '/api/field-service/jobs/$id/skills');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> setJobSkills(String id, List<dynamic> skillIds) async {
    final env = await _send('PUT', '/api/field-service/jobs/$id/skills', data: {'skill_ids': skillIds});
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> matchJobUsers(String id) async {
    return _dataMap(await _send('GET', '/api/field-service/jobs/$id/match-users'));
  }

  Future<List<Map<String, dynamic>>> getJobParts(String id) async {
    final env = await _send('GET', '/api/field-service/jobs/$id/parts');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> addJobPart(String id, Map<String, dynamic> body) async {
    return _dataMap(await _send('POST', '/api/field-service/jobs/$id/parts', data: body));
  }

  Future<void> deleteJobPart(String jobId, String partId) async {
    await _send('DELETE', '/api/field-service/jobs/$jobId/parts/$partId');
  }

  Future<Map<String, dynamic>> generateJobsFromAsset(String assetId) async {
    return _dataMap(await _send('POST', '/api/field-service/assets/$assetId/generate-jobs'));
  }

  Future<Map<String, dynamic>> createJobFromCase(String caseId) async {
    return _dataMap(await _send('POST', '/api/field-service/cases/$caseId/create-job'));
  }

  Future<Map<String, dynamic>> createJobFromContract(String contractId) async {
    return _dataMap(await _send('POST', '/api/field-service/contracts/$contractId/create-job'));
  }

  Future<Map<String, dynamic>> getContractMandayLedger(String id) async {
    return _dataMap(await _send('GET', '/api/entity/service_contract/$id/manday/ledger'));
  }

  Future<Map<String, dynamic>> addContractManday(String id, Map<String, dynamic> body) async {
    return _dataMap(await _send('POST', '/api/entity/service_contract/$id/manday/add', data: body));
  }

  Future<Map<String, dynamic>> adjustContractManday(String id, Map<String, dynamic> body) async {
    return _dataMap(await _send('POST', '/api/entity/service_contract/$id/manday/adjust', data: body));
  }

  Future<Map<String, dynamic>> getCaseMandaySummary(String caseId) async {
    return _dataMap(await _send('GET', '/api/entity/case/$caseId/manday-summary'));
  }

  Future<List<Map<String, dynamic>>> getCaseMandayRequests(String caseId) async {
    final env = await _send('GET', '/api/entity/case/$caseId/manday-requests');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postCaseMandayRequest(String caseId, Map<String, dynamic> body) async {
    return _dataMap(await _send('POST', '/api/entity/case/$caseId/manday-requests', data: body));
  }

  Future<List<int>> getQuotationPdf(String id) async {
    try {
      return await _downloadBytes('/api/quotation/$id/pdf');
    } catch (_) {
      return _downloadBytes('/api/quotation/$id/birt-pdf');
    }
  }

  Future<void> markAllNotificationsRead() async {
    await _send('PATCH', '/api/notifications/read-all');
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _send('DELETE', '/api/notifications/device-token', data: {'token': token});
  }

  Future<List<Map<String, dynamic>>> getChatMessages(
    String roomId, {
    int limit = 50,
    String? before,
  }) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/messages', query: {
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> postChatMessage(
    String roomId,
    String body, {
    List<Map<String, dynamic>>? attachments,
  }) async {
    return _dataMap(await _send(
      'POST',
      '/api/chat/rooms/$roomId/messages',
      data: {
        'body': body,
        if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
      },
    ));
  }

  Future<Map<String, dynamic>> editChatMessage(String roomId, String messageId, String body) async {
    return _dataMap(await _send('PATCH', '/api/chat/rooms/$roomId/messages/$messageId', data: {'body': body}));
  }

  Future<void> deleteChatMessage(String roomId, String messageId) async {
    await _send('DELETE', '/api/chat/rooms/$roomId/messages/$messageId');
  }

  Future<void> reactChatMessage(String roomId, String messageId, String emoji, {bool remove = false}) async {
    await _send(
      remove ? 'DELETE' : 'POST',
      '/api/chat/rooms/$roomId/messages/$messageId/reactions',
      data: {'emoji': emoji},
      query: remove ? {'emoji': emoji} : null,
    );
  }

  /// Public URL of an uploaded chat file (`file_path` like `chat/abc.png`).
  String chatFileUrl(String? filePath) {
    final urls = chatFileUrls(filePath);
    return urls.isEmpty ? '' : urls.first;
  }

  /// Candidate URLs for a chat file: static `/uploads/...` first, then the
  /// web app's `/api/chat/upload/...` route (`buildChatFileUrl` in NEXTX).
  List<String> chatFileUrls(String? filePath) {
    final p = (filePath ?? '').trim().replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'^uploads/+', caseSensitive: false), '');
    if (p.isEmpty) return const [];
    if (p.startsWith('http://') || p.startsWith('https://')) return [p];
    final base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final enc = p.split('/').map(Uri.encodeComponent).join('/');
    return ['$base/uploads/$enc', '$base/api/chat/upload/$enc'];
  }

  Future<Map<String, dynamic>> uploadChatFile(String roomId, MultipartFile file) async {
    final form = FormData.fromMap({'file': file});
    return _dataMap(await _send('POST', '/api/chat/rooms/$roomId/upload', data: form));
  }

  Future<void> markChatRead(String roomId, String messageId) async {
    await _send('POST', '/api/chat/rooms/$roomId/read', data: {'message_id': messageId});
  }

  Future<Map<String, dynamic>> createChatDm(String userId) async {
    return _dataMap(await _send('POST', '/api/chat/rooms/dm', data: {'user_id': userId}));
  }

  Future<void> forgotPassword(String email) async {
    await _send('POST', '/api/auth/forgot', data: {'email': email, 'locale': 'th'});
  }

  /// `current_password` is sent so the server can verify it (NEXTX should reject
  /// a wrong current password once its `/api/me/password` check is in place).
  Future<void> changePassword(String newPassword, {String? currentPassword}) async {
    await _send('PUT', '/api/me/password', data: {
      'new_password': newPassword,
      if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
    });
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    final data = _dataMap(await _send('GET', '/api/me/profile'));
    return asStringKeyedMap(data['profile']) ?? data;
  }

  Future<Map<String, dynamic>> updateMyProfile(Map<String, dynamic> changes) async {
    return _dataMap(await _send('PUT', '/api/me/profile', data: changes));
  }

  Future<Map<String, dynamic>> uploadAvatar(MultipartFile file) async {
    final form = FormData.fromMap({'file': file});
    return _dataMap(await _send('POST', '/api/me/avatar', data: form));
  }

  Future<void> setDefaultBusiness(String businessId) async {
    await _send('PUT', '/api/me/default-business', data: {
      'business_id': int.tryParse(businessId) ?? businessId,
    });
  }

  /// Files in the business root. `/api/files` returns `{folders, files, breadcrumb}`.
  Future<List<Map<String, dynamic>>> getFiles({int limit = 40, String? q}) async {
    final listing = await getFolderListing();
    return listing.files;
  }

  /// One folder level (root when [folderId] is null).
  Future<({List<Map<String, dynamic>> folders, List<Map<String, dynamic>> files, List<Map<String, dynamic>> breadcrumb})>
      getFolderListing({String? folderId}) async {
    final env = await _send('GET', '/api/files', query: {
      if (folderId != null && folderId.isNotEmpty) 'folder_id': folderId,
    });
    final data = env['data'];
    if (data is! Map) return (folders: <Map<String, dynamic>>[], files: extractMapList(data), breadcrumb: <Map<String, dynamic>>[]);
    return (
      folders: extractMapList(data['folders']),
      files: extractMapList(data['files']),
      breadcrumb: extractMapList(data['breadcrumb']),
    );
  }

  Future<Map<String, dynamic>> createFolder(String name, {String? parentId}) async {
    return _dataMap(await _send('POST', '/api/files/folders', data: {
      'name': name,
      if (parentId != null && parentId.isNotEmpty) 'parent_id': int.tryParse(parentId) ?? parentId,
    }));
  }

  Future<void> renameFolder(String id, String name) async {
    await _send('PUT', '/api/files/folders/$id', data: {'name': name});
  }

  Future<void> deleteFolder(String id) async {
    await _send('DELETE', '/api/files/folders/$id');
  }

  Future<void> renameFile(String id, String name) async {
    await _send('PUT', '/api/files/$id', data: {'name': name});
  }

  Future<void> deleteFile(String id) async {
    await _send('DELETE', '/api/files/$id');
  }

  Future<List<int>> downloadFile(String id) => _downloadBytes('/api/files/$id/download');

  Future<Map<String, dynamic>> uploadFiles(List<MultipartFile> files, {String? folderId}) async {
    final form = FormData();
    if (folderId != null && folderId.isNotEmpty) form.fields.add(MapEntry('folder_id', folderId));
    for (final f in files) {
      form.files.add(MapEntry('files', f));
    }
    return _dataMap(await _send('POST', '/api/files/upload', data: form));
  }

  Future<List<Map<String, dynamic>>> getMail({String box = 'inbox', int limit = 40}) async {
    final env = await _send('GET', '/api/mail', query: {
      'box': box,
      'limit': '$limit',
    });
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> getMailItem(String id) async {
    return _dataMap(await _send('GET', '/api/mail/$id'));
  }
  /// Internal NEXTX mail recipients (members of the current business).
  Future<List<Map<String, dynamic>>> getMailUsers() async {
    final env = await _send('GET', '/api/mail/users');
    return extractMapList(env['data']);
  }

  /// Sends (or saves as draft) an internal mail. Recipients are NEXTX user ids.
  Future<Map<String, dynamic>> sendMail({
    required List<String> toUserIds,
    List<String> ccUserIds = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    bool isDraft = false,
  }) async {
    return _dataMap(await _send('POST', '/api/mail', data: {
      'to_user_ids': toUserIds.map(int.tryParse).whereType<int>().toList(),
      'cc_user_ids': ccUserIds.map(int.tryParse).whereType<int>().toList(),
      'subject': subject,
      'body': body,
      if (bodyHtml != null) 'body_html': bodyHtml,
      'is_draft': isDraft,
    }));
  }

  /// Updates a draft. The server sends it when [isDraft] is false, so pass
  /// `true` to keep it as a draft.
  Future<Map<String, dynamic>> updateMailDraft(
    String id, {
    required List<String> toUserIds,
    List<String> ccUserIds = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    required bool isDraft,
  }) async {
    return _dataMap(await _send('PUT', '/api/mail/$id', data: {
      'to_user_ids': toUserIds.map(int.tryParse).whereType<int>().toList(),
      'cc_user_ids': ccUserIds.map(int.tryParse).whereType<int>().toList(),
      'subject': subject,
      'body': body,
      if (bodyHtml != null) 'body_html': bodyHtml,
      'is_draft': isDraft,
    }));
  }

  Future<void> markMailRead(String id) async {
    await _send('PUT', '/api/mail/$id/read');
  }

  /// Moves to trash; with [permanent] removes a message that is already in trash.
  Future<void> deleteMail(String id, {bool permanent = false}) async {
    await _send('DELETE', '/api/mail/$id', query: {if (permanent) 'permanent': '1'});
  }

  Future<void> restoreMail(String id) async {
    await _send('PUT', '/api/mail/$id/restore');
  }


  Future<Map<String, dynamic>> getEntityRelated(String module, String id) async {
    return _dataMap(await _send('GET', '/api/entity/$module/$id/related'));
  }

  /// Store orders for one queue (all, new_today, awaiting_payment, awaiting_label,
  /// awaiting_pickup, in_transit, delivered, cancelled). `meta.queue_counts` per queue.
  Future<({List<Map<String, dynamic>> items, Map<String, dynamic> meta})> getCommercialOrders({
    String queue = 'new_today',
    int page = 1,
    int limit = 25,
    String? q,
  }) async {
    final env = await _send('GET', '/api/commercial/orders', query: {
      'queue': queue,
      'page': '$page',
      'limit': '$limit',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    });
    final data = env['data'];
    final meta = data is Map && data['meta'] is Map ? Map<String, dynamic>.from(data['meta'] as Map) : <String, dynamic>{};
    return (items: extractMapList(data), meta: meta);
  }

  Future<void> markCommercialOrderPaid(String id) async {
    await _send('POST', '/api/commercial/orders/$id/mark-paid');
  }

  /// Product stock (each with `variants`). Requires store admin rights.
  Future<List<Map<String, dynamic>>> getStockBalance({String? q}) async {
    final env = await _send('GET', '/api/commercial/stock/balance', query: {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    });
    return extractMapList(env['data']);
  }

  /// [kind] is `in`, `out` (quantity > 0) or `adjust` (signed delta).
  Future<void> moveStock({
    required String kind,
    required String productId,
    String? variantId,
    required num amount,
    String? notes,
  }) async {
    await _send('POST', '/api/commercial/stock/$kind', data: {
      'product_id': int.tryParse(productId) ?? productId,
      if (variantId != null) 'variant_id': int.tryParse(variantId) ?? variantId,
      if (kind == 'adjust') 'delta': amount else 'quantity': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  Future<Map<String, dynamic>> getCommercialOrder(String id) async {
    return _dataMap(await _send('GET', '/api/commercial/orders/$id'));
  }

  Future<Map<String, dynamic>> sendQuotationEmail(
    String id, {
    required String to,
    String? message,
  }) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/send-email', data: {
      'to': to,
      if (message != null && message.isNotEmpty) 'message': message,
    }));
  }

  Future<Map<String, dynamic>> submitQuotationApproval(String id, [Map<String, dynamic>? body]) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/approval/submit', data: body ?? const {}));
  }

  Future<Map<String, dynamic>> approveQuotation(String id) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/approval/approve'));
  }

  Future<Map<String, dynamic>> rejectQuotation(String id, {String? reason}) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/approval/reject', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }));
  }
  /// Quotations in `approval_state = pending`. Narrow to the current approver
  /// with `isAwaitingMyApproval` (lib/core/approval_queue.dart).
  Future<List<Map<String, dynamic>>> getPendingQuotationApprovals({int limit = 100}) async {
    final page = await getEntityList(
      'quotation',
      limit: limit,
      extra: const {'filter_approval_state': 'pending', 'sort': 'id', 'order': 'desc'},
    );
    return page.items;
  }

  /// Requests to join a business the current user owns/administers.
  Future<List<Map<String, dynamic>>> getJoinRequests() async {
    final env = await _send('GET', '/api/pending-approvals/join-requests');
    final data = env['data'];
    if (data is Map && data['join_requests'] is List) return extractMapList(data['join_requests']);
    return extractMapList(data);
  }

  Future<void> decideJoinRequest(String id, {required bool approve}) async {
    await _send('POST', '/api/pending-approvals/join-requests/$id/${approve ? 'approve' : 'reject'}');
  }


  Future<Map<String, dynamic>> reviseQuotation(String id) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/revise'));
  }

  Future<List<Map<String, dynamic>>> putDealContacts(
    String id,
    List<Map<String, dynamic>> contacts,
  ) async {
    final env = await _send('PUT', '/api/entity/deal/$id/contacts', data: {'contacts': contacts});
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getDealQuotations(String id) async {
    final env = await _send('GET', '/api/entity/deal/$id/quotations');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> setDealPrimaryQuotation(String dealId, String quotationId) async {
    return _dataMap(await _send('PUT', '/api/entity/deal/$dealId/primary-quotation', data: {
      'quotation_id': int.tryParse(quotationId) ?? quotationId,
    }));
  }

  Future<Map<String, dynamic>> getJobSla(String id) async {
    return _dataMap(await _send('GET', '/api/field-service/jobs/$id/sla'));
  }

  Future<Map<String, dynamic>> getJobSkillMismatch(String id, {String? userId}) async {
    return _dataMap(await _send(
      'GET',
      '/api/field-service/jobs/$id/skill-mismatch',
      query: {if (userId != null && userId.isNotEmpty) 'user_id': userId},
    ));
  }

  Future<List<Map<String, dynamic>>> getJobWorkspaceItems(String id) async {
    final env = await _send('GET', '/api/field-service/jobs/$id/workspace-items');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> approveMandayRequest(String requestId, [Map<String, dynamic>? body]) async {
    return _dataMap(await _send('POST', '/api/entity/case/manday-requests/$requestId/approve', data: body ?? const {}));
  }

  Future<Map<String, dynamic>> rejectMandayRequest(String requestId, {String? reason}) async {
    return _dataMap(await _send('POST', '/api/entity/case/manday-requests/$requestId/reject', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }));
  }

  Future<Map<String, dynamic>> cancelMandayRequest(String requestId) async {
    return _dataMap(await _send('POST', '/api/entity/case/manday-requests/$requestId/cancel'));
  }

  Future<Map<String, dynamic>> getAccountMandaySummary(String id) async {
    return _dataMap(await _send('GET', '/api/entity/account/$id/manday/summary'));
  }

  Future<Map<String, dynamic>> addAccountManday(String id, Map<String, dynamic> body) async {
    return _dataMap(await _send('POST', '/api/entity/account/$id/manday/add', data: body));
  }

  Future<List<int>> _downloadBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes, method: 'GET'),
      );
      return res.data ?? <int>[];
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }
}
