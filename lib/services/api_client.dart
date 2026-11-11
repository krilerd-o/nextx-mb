import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/ai_assistant.dart';
import 'package:flutter/foundation.dart';

import '../core/app_alice.dart';
import 'api_exceptions.dart';

export 'api_exceptions.dart';

part 'api_journey.dart';

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

/// A connected Gmail / Outlook mailbox (`/api/mail/connections` row).
class MailAccount {
  const MailAccount({required this.id, required this.provider, required this.email, this.status, this.readOnly = false});

  final String id;

  /// `gmail` or `outlook`.
  final String provider;
  final String email;
  final String? status;
  final bool readOnly;

  /// Query the mail API needs to address this mailbox.
  Map<String, String> get query => {'source': provider, 'connectionId': id};

  String get providerLabel => provider == 'outlook' ? 'Outlook' : 'Gmail';

  static MailAccount? fromMap(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    final provider = (m['provider'] ?? m['source'])?.toString().toLowerCase();
    if (id == null || id.isEmpty || (provider != 'gmail' && provider != 'outlook')) return null;
    return MailAccount(
      id: id,
      provider: provider!,
      email: (m['email'] ?? m['email_address'] ?? m['account_email'] ?? m['display_name'] ?? '').toString(),
      status: m['status']?.toString(),
      readOnly: m['read_only'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is MailAccount && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

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
          // Tells NEXTX this is the app: Bearer wins over any stray cookie (backend mobileSupport.js).
          options.headers['X-Nextx-Client'] = 'mobile';
          // Device list on the server (Settings → devices): name / platform / app version.
          options.headers.addAll(deviceHeaders);
          // A one-off token for this request only (OTP-proven password change).
          final token = options.extra['nx_token'] as String? ?? _accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final bid = _businessId;
          if (bid != null && bid.isNotEmpty) {
            options.headers['X-Business-Id'] = bid;
          }
          // NEXTX menu/permission checks read the package from this header (like the web).
          final pkg = _packageCode;
          if (pkg != null && pkg.isNotEmpty) {
            options.headers['X-Package-Code'] = pkg;
          }
          handler.next(options);
        },
        onResponse: (res, handler) {
          // Sliding session (NEXTX middleware/jwt.js): signed in and in use → a fresh
          // 90-day token arrives here; 90 days without any request → sign in again.
          final fresh = res.headers.value('x-session-token');
          final current = _accessToken;
          if (fresh != null && fresh.isNotEmpty && current != null && current.isNotEmpty && fresh != current) {
            _accessToken = fresh;
            _onSessionToken?.call(fresh);
          }
          handler.next(res);
        },
        onError: (err, handler) {
          final code = err.response?.statusCode;
          final path = err.requestOptions.path;
          // Any /api/auth/* call (login, OTP, link, Google, register) may return 401
          // for bad credentials — that must not log the current session out.
          final isAuthCall = path.contains('/api/auth/');
          // A one-off OTP token was refused: the signed-in session itself is fine.
          final oneOffToken = err.requestOptions.extra['nx_token'] != null;
          if (code == 401 && !isAuthCall && !oneOffToken) {
            // Signed out from another device (NEXTX X-Session-Revoked) vs token simply expired.
            lastUnauthorizedRevoked = err.response?.headers.value('x-session-revoked') == '1';
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

  /// Sent with every request (set once at startup): X-Device-Name (URL-encoded),
  /// X-Device-Platform, X-App-Version.
  static Map<String, String> deviceHeaders = const {};

  /// The last 401 said this session was signed out from another device.
  bool lastUnauthorizedRevoked = false;
  String? _accessToken;
  String? _businessId;
  String? _packageCode;

  void setOnUnauthorized(VoidCallback? cb) => _onUnauthorized = cb;

  void Function(String token)? _onSessionToken;

  /// Called with the renewed token from `X-Session-Token`.
  void setOnSessionToken(void Function(String token)? cb) => _onSessionToken = cb;

  /// Widget tests route requests to a fake adapter instead of the network.
  @visibleForTesting
  void debugSetHttpAdapter(HttpClientAdapter adapter) => _dio.httpClientAdapter = adapter;

  void attachSession({
    required String baseUrl,
    String? accessToken,
    String? userId,
    String? businessId,
    String? packageCode,
  }) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = resolveApiBaseUrl(trimmed);
    _accessToken = accessToken;
    _businessId = businessId;
    _packageCode = packageCode;
  }

  String get baseUrl => _dio.options.baseUrl;
  String? get accessToken => _accessToken;
  String? get businessId => _businessId;
  String? get packageCode => _packageCode;

  /// Entry URL for LINE login, opened in an in-app WebView (see LineLoginScreen).
  String get lineLoginUrl => '${_dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/auth/line';

  /// `?app=1`: the server sends the browser back to `moainext://app/login?token=`.
  String lineLoginUrlFor({required bool app}) => app ? '$lineLoginUrl?app=1' : lineLoginUrl;

  /// Raw `GET /api/health` body (envelope) — server fingerprint + `data.mobile`.
  Future<Object?> getHealthRaw() async {
    final res = await _dio.get<dynamic>('/api/health', options: Options(validateStatus: (_) => true));
    return res.data;
  }


  /// Saves the app's roles / bottom tabs on the account (feature `prefs_mobile`); `null` clears.
  Future<void> saveMobileShell(Map<String, dynamic>? shell) async {
    await _send('PATCH', '/api/me/preferences', data: {'mobile_shell': shell});
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    Options? options,
    CancelToken? cancel,
  }) async {
    try {
      final isForm = data is FormData;
      final res = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: data,
        cancelToken: cancel,
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

  /// `{channel_id|null, redirect_uri}` — LINE login is configured when channel_id is set.
  Future<Map<String, dynamic>> getLineCheck() async {
    return _dataMap(await _send('GET', '/api/auth/line/check'));
  }

  /// `{client_id, enabled, sign_in_ready, ...}` — Google sign-in availability.
  Future<Map<String, dynamic>> getGoogleOneTapConfig() async {
    return _dataMap(await _send('GET', '/api/auth/google/one-tap-config'));
  }

  /// Google ID token → `{token,user,business}` or `{need_merge, merge_intent}`.
  Future<Map<String, dynamic>> googleOneTap(String idToken) async {
    return _dataMap(await _send('POST', '/api/auth/google/one-tap', data: {'credential': idToken}));
  }

  /// QR login: one-time code from the web → `{token, user, business}`.
  Future<Map<String, dynamic>> qrRedeem(String code) async {
    return _dataMap(await _send('POST', '/api/auth/qr/redeem', data: {'code': code}));
  }

  /// Browser Google sign-in that returns to the app (`moainext://app/login`).
  String get googleAppLoginUrl => '${_dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/auth/google?app=1';

  /// Sign in with Apple (iOS): session, or `{needLinkConfirm, intentToken}`.
  Future<Map<String, dynamic>> appleLogin(String identityToken) async {
    return _dataMap(await _send('POST', '/api/auth/apple', data: {'identity_token': identityToken, 'remember': true}));
  }

  Future<Map<String, dynamic>> googleMergePreview(String intent) async {
    return _dataMap(await _send('GET', '/api/auth/google/merge/preview', query: {'intent_token': intent}));
  }

  Future<Map<String, dynamic>> googleMergeConfirm(String intent) async {
    return _dataMap(await _send('POST', '/api/auth/google/merge/confirm', data: {'intent_token': intent}));
  }

  /// Sign-in method linking (OTP etc. returns `needLinkConfirm` + `intentToken`).
  Future<Map<String, dynamic>> linkPreview(String intent) async {
    return _dataMap(await _send('GET', '/api/auth/link/preview', query: {'intent_token': intent}));
  }

  Future<Map<String, dynamic>> linkConfirm(String intent) async {
    return _dataMap(await _send('POST', '/api/auth/link/confirm', data: {'intent_token': intent, 'remember': true}));
  }

  /// `signupType`: `with_key` (serial key) or `without_key` (needs admin approval).
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    required String signupType,
    String? serialKey,
    String? businessName,
    String? businessCode,
    String? inviteToken,
  }) async {
    return _dataMap(await _send('POST', '/api/auth/register', data: {
      'fullName': fullName,
      'email': email,
      'password': password,
      'signup_type': signupType,
      if (serialKey != null && serialKey.isNotEmpty) 'serialKey': serialKey,
      if (businessName != null && businessName.isNotEmpty) 'businessName': businessName,
      if (businessCode != null && businessCode.isNotEmpty) 'businessCode': businessCode,
      if (inviteToken != null && inviteToken.isNotEmpty) 'invite_token': inviteToken,
    }));
  }

  /// `POST /api/me/request-join` — join a business with an invite link token.
  Future<Map<String, dynamic>> requestJoin({String? inviteToken, String? businessCode}) async {
    return _dataMap(await _send('POST', '/api/me/request-join', data: {
      if (inviteToken != null && inviteToken.isNotEmpty) 'invite_token': inviteToken,
      if (businessCode != null && businessCode.isNotEmpty) 'business_code': businessCode,
    }));
  }

  Future<void> requestSmsOtp(String phone) async {
    await _send('POST', '/api/auth/otp/sms/request', data: {'phone': phone});
  }

  Future<Map<String, dynamic>> verifySmsOtp({required String phone, required String code}) async {
    return _dataMap(await _send('POST', '/api/auth/otp/sms/verify', data: {
      'phone': phone,
      'code': code,
      'remember': true,
    }));
  }

  /// Devices signed in to this account (`GET /api/me/sessions`, feature `device_sessions`).
  Future<({List<Map<String, dynamic>> list, String? currentSid})> getDeviceSessions() async {
    final env = await _send('GET', '/api/me/sessions');
    final data = env['data'];
    return (
      list: extractMapList(data),
      currentSid: data is Map ? data['current_sid']?.toString() : null,
    );
  }

  Future<void> revokeDeviceSession(String sid) async {
    await _send('DELETE', '/api/me/sessions/${Uri.encodeComponent(sid)}');
  }

  /// Signs out every other device (this one stays signed in).
  Future<void> revokeOtherDeviceSessions() async {
    await _send('POST', '/api/me/sessions/revoke-others');
  }

  /// Signs out every device including this one.
  Future<void> revokeAllDeviceSessions() async {
    await _send('POST', '/api/me/sessions/revoke-all');
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

  ({DateTime at, String biz, Map<String, (String, String?)> labels})? _moduleLabels;

  /// Menu names as set up in NEXTX (`aicrm_tab`): module → (tablabel, tablabel_en).
  /// Cached 10 minutes per business.
  Future<Map<String, (String, String?)>> getModuleLabels() async {
    final c = _moduleLabels;
    if (c != null && c.biz == (_businessId ?? '') && DateTime.now().difference(c.at) < const Duration(minutes: 10)) {
      return c.labels;
    }
    final out = <String, (String, String?)>{};
    for (final m in await getModules()) {
      if (m is! Map) continue;
      final name = '${m['name'] ?? m['module'] ?? ''}'.trim();
      final th = '${m['tablabel'] ?? m['label_th'] ?? m['label'] ?? ''}'.trim();
      if (name.isEmpty || th.isEmpty) continue;
      final en = '${m['tablabel_en'] ?? m['label_en'] ?? ''}'.trim();
      out[name.toLowerCase()] = (th, en.isEmpty ? null : en);
    }
    _moduleLabels = (at: DateTime.now(), biz: _businessId ?? '', labels: out);
    return out;
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
    CancelToken? cancel,
  }) async {
    final p = page ?? ((offset ~/ (limit == 0 ? 30 : limit)) + 1);
    final query = <String, dynamic>{
      'limit': '$limit',
      'page': '$p',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      ...?extra,
    };
    final env = await _send('GET', '/api/entity/$module', query: query, cancel: cancel);
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
    // Job photos are appended by the photo endpoint; a full PUT of the list
    // would overwrite uploads still in progress (NEXTX Service Journey).
    final body = module == 'job' && payload.containsKey('evidence_photos')
        ? ({...payload}..remove('evidence_photos'))
        : payload;
    return _dataMap(await _send('PUT', '/api/entity/$module/$id', data: body));
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

  /// Field schemas change rarely; keep each for a few minutes per business.
  final Map<String, ({DateTime at, ModuleFieldSchema schema})> _schemaCache = {};

  Future<ModuleFieldSchema> getFieldSchema(String module, {bool fresh = false}) async {
    final key = '${_businessId ?? ''}|$module';
    final hit = _schemaCache[key];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 5)) return hit.schema;
    final schema = await _fetchFieldSchema(module);
    _schemaCache[key] = (at: DateTime.now(), schema: schema);
    return schema;
  }

  Future<ModuleFieldSchema> _fetchFieldSchema(String module) async {
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

  /// `POST /api/entity/:m/bulk-update` — same fields on many records.
  /// Sends in chunks of 100 (the server's per-request cap).
  /// Returns how many records were really updated (the server skips records
  /// without permission or fields that must go through a workflow).
  Future<int> bulkUpdateEntities(String module, List<String> ids, Map<String, dynamic> fields) async {
    var updated = 0;
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final env = await _send('POST', '/api/entity/$module/bulk-update', data: {
        'ids': [for (final id in chunk) int.tryParse(id) ?? id],
        ...fields,
      });
      final d = env['data'];
      final n = d is Map ? d['updated'] : null;
      updated += n is num ? n.toInt() : (int.tryParse('${n ?? ''}') ?? chunk.length);
    }
    return updated;
  }

  /// Who a record is shared with (users / roles).
  Future<List<Map<String, dynamic>>> getEntityShares(String module, String id) async {
    final env = await _send('GET', '/api/entity/$module/$id/shares');
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
  }

  /// Replaces all shares of a record: `[{share_to_type, share_to_id, permission}]`.
  Future<void> saveEntityShares(String module, String id, List<Map<String, dynamic>> shares) async {
    await _send('PUT', '/api/entity/$module/$id/shares', data: {'shares': shares});
  }

  /// Roles of the current business.
  Future<List<Map<String, dynamic>>> getRoles() async {
    final env = await _send('GET', '/api/roles', query: {if (_businessId != null) 'business_id': _businessId!});
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
  }

  /// Case watchers: `{list, following}` (only cases support following).
  Future<Map<String, dynamic>> getCaseWatchers(String id) async =>
      _dataMap(await _send('GET', '/api/entity/case/$id/watchers'));

  Future<void> setCaseFollow(String id, bool follow) async {
    await _send(follow ? 'POST' : 'DELETE', '/api/entity/case/$id/follow');
  }

  /// Link an external (Gmail/Outlook) message to a CRM record.
  Future<void> linkMailToEntity({
    required String connectionId,
    required String messageId,
    required String module,
    required String entityId,
    String? email,
    String? name,
  }) async {
    await _send('POST', '/api/mail/entity-link', data: {
      'connectionId': int.tryParse(connectionId) ?? connectionId,
      'messageId': messageId,
      'module': module,
      'entity_id': int.tryParse(entityId) ?? entityId,
      if (email != null) 'email': email,
      if (name != null) 'name': name,
    });
  }

  /// CRM records already known for an e-mail address.
  Future<List<Map<String, dynamic>>> lookupEntityByEmail(String email) async {
    final data = _dataMap(await _send('GET', '/api/mail/entity-lookup', query: {'email': email}));
    return extractMapList(data['links']);
  }

  /// All messages of an external mail thread.
  Future<List<Map<String, dynamic>>> getMailThreadMessages(String threadId, {required String connectionId}) async {
    final env = await _send('GET', '/api/mail/threads/$threadId', query: {'connectionId': connectionId});
    final data = env['data'];
    return extractMapList(data is Map ? data['list'] : data);
  }

  // ── Custom Views (มุมมอง CV) — same API as the NEXTX web list.

  /// `{list, groups, default_id}`; each view carries can_edit / can_delete / can_duplicate.
  Future<Map<String, dynamic>> getCustomViews(String module) async {
    return _dataMap(await _send('GET', '/api/customviews', query: {'module': module}));
  }

  /// Fields (+operators), period presets, date fields, users and roles for the editor.
  Future<Map<String, dynamic>> getCustomViewMeta(String module) async {
    return _dataMap(await _send('GET', '/api/customviews/meta', query: {'module': module}));
  }

  Map<String, dynamic> _cvOf(Map<String, dynamic> m) =>
      m['customview'] is Map ? Map<String, dynamic>.from(m['customview'] as Map) : m;

  Future<Map<String, dynamic>> createCustomView(Map<String, dynamic> body) async {
    return _cvOf(_dataMap(await _send('POST', '/api/customviews', data: body)));
  }

  Future<Map<String, dynamic>> updateCustomView(String id, Map<String, dynamic> body) async {
    return _cvOf(_dataMap(await _send('PUT', '/api/customviews/$id', data: body)));
  }

  Future<Map<String, dynamic>> duplicateCustomView(String id) async {
    return _cvOf(_dataMap(await _send('POST', '/api/customviews/$id/duplicate')));
  }

  Future<void> deleteCustomView(String id) async {
    await _send('DELETE', '/api/customviews/$id');
  }

  Future<List<Map<String, dynamic>>> getPicklists() async {
    final env = await _send('GET', '/api/picklists');
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getPicklistValues(String name) async {
    final env = await _send('GET', '/api/picklists/values/$name');
    return extractMapList(env['data']);
  }

  ({DateTime at, String biz, List<Map<String, dynamic>> users})? _usersCache;

  /// Business users for id → name labels; cached 10 minutes per business.
  Future<List<Map<String, dynamic>>> getUsersCached() async {
    final c = _usersCache;
    if (c != null && c.biz == (_businessId ?? '') && DateTime.now().difference(c.at) < const Duration(minutes: 10)) {
      return c.users;
    }
    final users = await getUsers(limit: 500);
    _usersCache = (at: DateTime.now(), biz: _businessId ?? '', users: users);
    return users;
  }

  Future<List<Map<String, dynamic>>> getUsers({String? q, int limit = 80}) async {
    final env = await _send('GET', '/api/users', query: {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'limit': '$limit',
    });
    return extractMapList(env['data']);
  }

  /// Enabled packages of [businessId] (`{packages:[{id, code, name, ..., enabled}]}`).
  Future<List<Map<String, dynamic>>> getPackagesFor(String businessId) async {
    final env = await _send('GET', '/api/businesses/$businessId/packages');
    return extractMapList(env['data']);
  }

  Future<void> setDefaultPackage({required String packageId, required String businessId}) async {
    await _send('PUT', '/api/me/default-package', data: {
      'package_id': int.tryParse(packageId) ?? packageId,
      'business_id': int.tryParse(businessId) ?? businessId,
    });
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
    String body, {
    List<Map<String, dynamic>> attachments = const [],
    Object? parentId,
  }) async {
    return _dataMap(await _send(
      'POST',
      '/api/entity/$module/$id/comments',
      data: {
        'body': body,
        if (attachments.isNotEmpty) 'attachments': attachments,
        if (parentId != null) 'parent_id': parentId,
      },
    ));
  }

  /// Unified history (`audit` / `field_change` / status / engagement events,
  /// newest first) — `GET /api/entity/:module/:id/timeline`.
  Future<List<Map<String, dynamic>>> getEntityTimeline(String module, String id, {int limit = 100}) async {
    final env = await _send('GET', '/api/entity/$module/$id/timeline', query: {'limit': '$limit'});
    return extractMapList(env['data']);
  }

  /// Copies a record; returns the new id.
  Future<String> duplicateEntity(String module, String id) async {
    final m = _dataMap(await _send('POST', '/api/entity/$module/$id/duplicate'));
    return m['id']?.toString() ?? '';
  }

  Future<void> bulkDeleteEntities(String module, List<String> ids) async {
    await _send('POST', '/api/entity/$module/bulk-delete', data: {
      'ids': [for (final i in ids) int.tryParse(i) ?? i],
    });
  }

  /// Uploads to File Manager and returns comment-attachment maps
  /// (`{url, name, mime, size, file_id}`), the same shape the web sends.
  Future<List<Map<String, dynamic>>> uploadCommentAttachments(List<MultipartFile> files) async {
    final res = await uploadFiles(files);
    final rows = extractMapList(res['list'] ?? res['files'] ?? res);
    return [
      for (final r in rows)
        if ((r['storage_path'] ?? r['url'])?.toString().isNotEmpty == true)
          {
            'url': r['storage_path'] != null ? '/uploads/${r['storage_path'].toString().replaceFirst(RegExp(r'^/+'), '')}' : r['url'].toString(),
            'name': r['file_name'] ?? r['name'] ?? 'file',
            'mime': r['mime_type'] ?? r['mime'] ?? 'application/octet-stream',
            if ((r['file_size'] ?? r['size']) != null) 'size': r['file_size'] ?? r['size'],
            if (r['id'] != null) 'file_id': r['id'],
          },
    ];
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

  /// [offlineAt]: the punch was made without network at this device time and is
  /// sent later (servers with feature `offline_attendance`).
  Future<Map<String, dynamic>> clockIn({
    required double latitude,
    required double longitude,
    String? address,
    DateTime? offlineAt,
  }) async {
    return _dataMap(await _send('POST', '/api/hr/attendance/clock-in', data: {
      'source': 'app',
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
      if (offlineAt != null) ...{'offline': true, 'client_time': offlineAt.toUtc().toIso8601String()},
    }));
  }

  Future<Map<String, dynamic>> clockOut({
    required double latitude,
    required double longitude,
    String? address,
    DateTime? offlineAt,
  }) async {
    return _dataMap(await _send('POST', '/api/hr/attendance/clock-out', data: {
      'source': 'app',
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
      if (offlineAt != null) ...{'offline': true, 'client_time': offlineAt.toUtc().toIso8601String()},
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

  /// Attach images / PDF to the caller's own Pending leave request (feature `leave_attachments`).
  Future<List<Map<String, dynamic>>> uploadLeaveAttachments(String requestId, List<({List<int> bytes, String name})> files) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('files[]', MultipartFile.fromBytes(f.bytes, filename: f.name)));
    }
    final data = _dataMap(await _send('POST', '/api/hr/leave-requests/$requestId/attachments', data: form));
    return extractMapList(data['attachments']);
  }

  /// Removes it from the request (the server keeps the file — nothing is destroyed).
  Future<List<Map<String, dynamic>>> removeLeaveAttachment(String requestId, String fileId) async {
    final data = _dataMap(await _send('DELETE', '/api/hr/leave-requests/$requestId/attachments/${Uri.encodeComponent(fileId)}'));
    return extractMapList(data['attachments']);
  }

  /// Bytes of an attachment (`url` from the list: `/api/hr/leave-requests/:id/attachments/:fileId`).
  Future<List<int>> downloadLeaveAttachment(String url) => _downloadBytes(url);

  /// `{pending_leave_count, today_clocked_in_count, date}` for HR.
  Future<Map<String, dynamic>> getHrDashboard() async {
    return _dataMap(await _send('GET', '/api/hr/dashboard'));
  }

  /// Everyone's punches for one day (`yyyy-MM-dd`).
  Future<List<Map<String, dynamic>>> getAttendanceReport(String date) async {
    final env = await _send('GET', '/api/hr/attendance/report', query: {'date': date});
    return extractMapList(env['data']);
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
    String? imagename,
  }) async {
    return _dataMap(await _send('POST', '/api/activity/$id/checkin', data: {
      'location': '$lat,$lng',
      if (imagename != null && imagename.isNotEmpty) 'imagename': imagename,
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

  /// `GET /api/me/signatures` — TH/EN signature paths + public URLs.
  Future<Map<String, dynamic>> getMySignatures() async => _dataMap(await _send('GET', '/api/me/signatures'));

  /// `POST /api/uploads/signature` (PNG/JPEG ≤ 2 MB) → stored path `signatures/...`.
  Future<String> uploadSignatureImage(List<int> bytes, String filename) async {
    final form = FormData()..files.add(MapEntry('file', MultipartFile.fromBytes(bytes, filename: filename)));
    final data = _dataMap(await _send('POST', '/api/uploads/signature', data: form));
    final path = data['path']?.toString() ?? '';
    if (path.isEmpty) throw ApiException(500, 'อัปโหลดลายเซ็นไม่สำเร็จ');
    return path;
  }

  /// `PUT /api/me/signatures` — set a path or clear a slot.
  Future<Map<String, dynamic>> saveMySignatures({String? th, String? en, bool clearTh = false, bool clearEn = false}) async =>
      _dataMap(await _send('PUT', '/api/me/signatures', data: {
        if (th != null) 'upload_signature_th': th,
        if (en != null) 'upload_signature_en': en,
        if (clearTh) 'clear_th': true,
        if (clearEn) 'clear_en': true,
      }));

  /// `POST /api/me/phone/otp/request` — SMS code to bind/verify a mobile number.
  Future<Map<String, dynamic>> requestPhoneBindOtp(String phone) async =>
      _dataMap(await _send('POST', '/api/me/phone/otp/request', data: {'phone': phone}));

  Future<Map<String, dynamic>> verifyPhoneBindOtp(String phone, String code) async =>
      _dataMap(await _send('POST', '/api/me/phone/otp/verify', data: {'phone': phone, 'code': code}));

  /// `POST /api/activity/:id/photos` — multer field is `files` (not `files[]`).
  /// Returns the stored photos (`{id, name, path, url?, mime, size}`).
  /// `POST /api/crm/business-card/scan` — read a business card into Lead /
  /// Contact / Account fields (nothing is saved). [ocrText] is the phone's own
  /// OCR, used by the server only when it has no AI vision key.
  Future<Map<String, dynamic>> scanBusinessCard(
    String module, {
    List<int>? front,
    List<int>? back,
    String? ocrText,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('module', module));
    if (ocrText != null && ocrText.trim().isNotEmpty) form.fields.add(MapEntry('ocr_text', ocrText));
    if (front != null) {
      form.files.add(MapEntry('front', MultipartFile.fromBytes(front, filename: 'card_front.jpg', contentType: DioMediaType('image', 'jpeg'))));
    }
    if (back != null) {
      form.files.add(MapEntry('back', MultipartFile.fromBytes(back, filename: 'card_back.jpg', contentType: DioMediaType('image', 'jpeg'))));
    }
    return _dataMap(await _send('POST', '/api/crm/business-card/scan', data: form));
  }

  Future<List<Map<String, dynamic>>> uploadActivityPhotos(String id, List<MultipartFile> files) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('files', f));
    }
    final env = await _send('POST', '/api/activity/$id/photos', data: form);
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getBoards({String? q, bool writable = false}) async {
    final env = await _send('GET', '/api/boards', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (writable) 'writable': 1,
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
    String? assigneeId,
    bool excludeDone = false,
    bool excludeEpic = false,
    int limit = 200,
    String? dueFrom,
    String? dueTo,
    String? types,
    CancelToken? cancel,
  }) async {
    final env = await _send('GET', '/api/workspace/items', cancel: cancel, query: {
      if (dueFrom != null) 'due_from': dueFrom,
      if (dueTo != null) 'due_to': dueTo,
      if (types != null && types.isNotEmpty) 'type': types,
      if (boardIds != null && boardIds.isNotEmpty) 'board_ids': boardIds,
      if (q != null && q.isNotEmpty) 'q': q,
      if (assigneeId != null && assigneeId.isNotEmpty) 'assignee_id': assigneeId,
      if (excludeDone) 'exclude_done': '1',
      if (excludeEpic) 'exclude_epic': '1',
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

  /// Uploads files to a board; returns `[{url, name, size, mime}]` to store on a task.
  Future<List<Map<String, dynamic>>> uploadBoardAttachments(String boardId, List<MultipartFile> files) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('files', f));
    }
    final env = await _send('POST', '/api/boards/$boardId/attachments', data: form);
    return extractMapList(env['data']);
  }

  /// Absolute URL for a relative upload path such as `/uploads/boards/1/a.png`.
  String absoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base${url.startsWith('/') ? '' : '/'}$url';
  }

  // ── Workspace (boards / epics / tasks) — same endpoints as the NEXTX web.

  /// `kind`: `task` (task/bug/story/subtask/checklist) or `epic`.
  String _wsPath(String boardId, String kind, String id) =>
      '/api/boards/$boardId/${kind == 'epic' ? 'epics' : 'tasks'}/$id';

  Future<Map<String, dynamic>> getBoard(String boardId) async => _dataMap(await _send('GET', '/api/boards/$boardId'));

  Future<List<Map<String, dynamic>>> getBoardTasks(String boardId, {bool lite = true, String? epicId, String? ids}) async {
    final env = await _send('GET', '/api/boards/$boardId/tasks', query: {
      if (lite) 'fields': 'lite',
      if (epicId != null) 'epic_id': epicId,
      if (epicId != null) 'include_children': '1',
      if (ids != null) 'ids': ids,
    });
    return extractMapList(env['data']);
  }

  Future<List<Map<String, dynamic>>> getBoardEpics(String boardId, {bool lite = true, String? ids}) async {
    final env = await _send('GET', '/api/boards/$boardId/epics', query: {
      if (lite) 'fields': 'lite',
      if (ids != null) 'ids': ids,
    });
    return extractMapList(env['data']);
  }

  /// One task or epic with every field (description, attachments…).
  Future<Map<String, dynamic>?> getWorkspaceItem(String boardId, String kind, String id) async {
    final list = kind == 'epic'
        ? await getBoardEpics(boardId, lite: false, ids: id)
        : await getBoardTasks(boardId, lite: false, ids: id);
    return list.where((e) => '${e['id']}' == id).firstOrNull ?? (list.isEmpty ? null : list.first);
  }

  Future<Map<String, dynamic>> createWorkspaceItem(String boardId, String kind, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/boards/$boardId/${kind == 'epic' ? 'epics' : 'tasks'}', data: body));

  Future<Map<String, dynamic>> updateWorkspaceItem(String boardId, String kind, String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('PUT', _wsPath(boardId, kind, id), data: body));

  Future<void> deleteWorkspaceItem(String boardId, String kind, String id) async {
    await _send('DELETE', _wsPath(boardId, kind, id));
  }

  Future<Map<String, dynamic>> moveWorkspaceItem(String boardId, String kind, String id, String targetBoardId) async =>
      _dataMap(await _send('POST', '${_wsPath(boardId, kind, id)}/move', data: {'target_board_id': targetBoardId}));

  /// New order of sibling tasks (e.g. one Kanban column).
  Future<void> reorderBoardTasks(String boardId, List<String> orderedIds) async {
    await _send('PUT', '/api/boards/$boardId/tasks/reorder', data: {
      'ordered_ids': [for (final id in orderedIds) int.tryParse(id) ?? id],
    });
  }

  /// `items`: `[(kind, id)]`; `updates`: status_id / assignee_id / priority / dates…
  Future<void> bulkUpdateWorkspaceItems(String boardId, List<(String, String)> items, Map<String, dynamic> updates) async {
    await _send('PUT', '/api/boards/$boardId/bulk-update', data: {
      'item_ids': [for (final (k, id) in items) {'type': k, 'id': int.tryParse(id) ?? id}],
      'updates': updates,
    });
  }

  /// Moves the items to the trash; returns the trash ids (for undo with [restoreWorkspaceTrashBulk]).
  Future<List<String>> bulkDeleteWorkspaceItems(String boardId, List<(String, String)> items) async {
    final res = await _send('POST', '/api/boards/$boardId/bulk-delete', data: {
      'item_ids': [for (final (k, id) in items) {'type': k, 'id': int.tryParse(id) ?? id}],
    });
    final data = res['data'] is Map ? res['data'] as Map : res;
    final ids = data['trash_ids'];
    return ids is List ? [for (final i in ids) '$i'] : const [];
  }

  /// Copies Task / Subtask rows (title + " (สำเนา)"); returns the new rows. Epics are skipped by the server.
  Future<List<Map<String, dynamic>>> bulkDuplicateWorkspaceItems(String boardId, List<(String, String)> items) async {
    final res = await _send('POST', '/api/boards/$boardId/bulk-duplicate', data: {
      'item_ids': [for (final (k, id) in items) {'type': k, 'id': int.tryParse(id) ?? id}],
    });
    final data = res['data'] is Map ? res['data'] as Map : res;
    return extractMapList(data['items']);
  }

  /// Undo for a bulk delete.
  Future<void> restoreWorkspaceTrashBulk(List<String> trashIds) async {
    await _send('POST', '/api/workspace/trash/bulk-restore', data: {
      'ids': [for (final id in trashIds) int.tryParse(id) ?? id],
    });
  }

  // Worklogs (ลงเวลา)
  Future<Map<String, dynamic>> addWorklog(
    String boardId,
    String taskId, {
    required int minutes,
    String? description,
    int? remainingMinutes,
    String? startedAt,
  }) async =>
      _dataMap(await _send('POST', '/api/boards/$boardId/tasks/$taskId/worklogs', data: {
        'time_spent_minutes': minutes,
        if (description != null && description.isNotEmpty) 'work_description': description,
        if (remainingMinutes != null) 'time_remaining_minutes': remainingMinutes,
        if (startedAt != null) 'started_at': startedAt,
      }));

  Future<Map<String, dynamic>> updateWorklog(
    String boardId,
    String taskId,
    String worklogId, {
    required int minutes,
    String? description,
    int? remainingMinutes,
    String? startedAt,
  }) async =>
      _dataMap(await _send('PUT', '/api/boards/$boardId/tasks/$taskId/worklogs/$worklogId', data: {
        'time_spent_minutes': minutes,
        'work_description': description ?? '',
        if (remainingMinutes != null) 'time_remaining_minutes': remainingMinutes,
        if (startedAt != null) 'started_at': startedAt,
      }));

  Future<void> deleteWorklog(String boardId, String taskId, String worklogId) async {
    await _send('DELETE', '/api/boards/$boardId/tasks/$taskId/worklogs/$worklogId');
  }

  // Comments (tasks and epics)
  Future<List<Map<String, dynamic>>> getItemComments(String boardId, String kind, String id) async {
    final env = await _send('GET', '${_wsPath(boardId, kind, id)}/comments');
    return extractMapList(env['data']);
  }

  Future<Map<String, dynamic>> addItemComment(
    String boardId,
    String kind,
    String id,
    String body, {
    String? parentId,
    List<Map<String, dynamic>> attachments = const [],
  }) async =>
      _dataMap(await _send('POST', '${_wsPath(boardId, kind, id)}/comments', data: {
        'body': body,
        if (parentId != null) 'parent_id': int.tryParse(parentId) ?? parentId,
        if (attachments.isNotEmpty) 'attachments': attachments,
      }));

  Future<void> updateItemComment(String boardId, String kind, String id, String commentId, String body) async {
    await _send('PUT', '${_wsPath(boardId, kind, id)}/comments/$commentId', data: {'body': body});
  }

  Future<void> deleteItemComment(String boardId, String kind, String id, String commentId) async {
    await _send('DELETE', '${_wsPath(boardId, kind, id)}/comments/$commentId');
  }

  /// Toggles my like; returns `{liked, like_count}`.
  Future<Map<String, dynamic>> toggleItemCommentLike(String boardId, String kind, String id, String commentId) async =>
      _dataMap(await _send('POST', '${_wsPath(boardId, kind, id)}/comments/$commentId/like'));

  /// Change history of one item (status, assignee, fields, comments, worklogs…).
  Future<List<Map<String, dynamic>>> getItemActivity(String boardId, String kind, String id, {int limit = 100}) async {
    final env = await _send('GET', '/api/boards/$boardId/activity', query: {
      kind == 'epic' ? 'epic_id' : 'task_id': id,
      'limit': '$limit',
      'fields': 'lite',
    });
    return extractMapList(env['data']);
  }

  // Watchers / links
  Future<List<Map<String, dynamic>>> getItemWatchers(String boardId, String kind, String id) async =>
      extractMapList((await _send('GET', '/api/boards/$boardId/items/$kind/$id/watchers'))['data']);

  Future<void> addItemWatcher(String boardId, String kind, String id, String userId) async {
    await _send('POST', '/api/boards/$boardId/items/$kind/$id/watchers', data: {'user_id': int.tryParse(userId) ?? userId});
  }

  Future<void> removeItemWatcher(String boardId, String kind, String id, String userId) async {
    await _send('DELETE', '/api/boards/$boardId/items/$kind/$id/watchers/$userId');
  }

  Future<List<Map<String, dynamic>>> getItemLinks(String boardId, String kind, String id) async =>
      extractMapList((await _send('GET', '/api/boards/$boardId/items/$kind/$id/links'))['data']);

  Future<void> addItemLink(String boardId, String kind, String id,
      {required String toKind, required String toId, String linkType = 'relates_to'}) async {
    await _send('POST', '/api/boards/$boardId/items/$kind/$id/links', data: {
      'to_type': toKind,
      'to_id': int.tryParse(toId) ?? toId,
      'link_type': linkType,
    });
  }

  Future<void> deleteItemLink(String boardId, String linkId) async {
    await _send('DELETE', '/api/boards/$boardId/item-links/$linkId');
  }

  // Board-level
  Future<Map<String, dynamic>> duplicateBoard(String boardId) async =>
      _dataMap(await _send('POST', '/api/boards/$boardId/duplicate'));

  Future<List<Map<String, dynamic>>> getBoardItemTags(String boardId) async =>
      extractMapList((await _send('GET', '/api/boards/$boardId/item-tags'))['data']);

  Future<List<Map<String, dynamic>>> getBoardReleases(String boardId) async =>
      extractMapList((await _send('GET', '/api/boards/$boardId/releases'))['data']);

  // Trash
  Future<Map<String, dynamic>> getWorkspaceTrash({int limit = 50, int offset = 0}) async =>
      _dataMap(await _send('GET', '/api/workspace/trash', query: {'limit': '$limit', 'offset': '$offset'}));

  Future<void> restoreWorkspaceTrash(String id) async {
    await _send('POST', '/api/workspace/trash/$id/restore');
  }

  Future<void> purgeWorkspaceTrash(String id) async {
    await _send('DELETE', '/api/workspace/trash/$id');
  }

  /// Soft-deletes a task (moved to the workspace trash on the server).
  Future<void> deleteBoardTask(String boardId, String taskId) async {
    await _send('DELETE', '/api/boards/$boardId/tasks/$taskId');
  }

  /// Smart checklist rows of a task (`{checklist, items, progress}` → items).
  Future<List<Map<String, dynamic>>> getSmartChecklist(String boardId, String taskId) async {
    final env = await _send('GET', '/api/boards/$boardId/items/task/$taskId/smart-checklist');
    final data = env['data'];
    return extractMapList(data is Map ? data['items'] : data);
  }

  Future<Map<String, dynamic>> addSmartChecklistItem(String boardId, String taskId, String title) async =>
      _dataMap(await _send('POST', '/api/boards/$boardId/items/task/$taskId/smart-checklist/items',
          data: {'title': title, 'item_kind': 'item', 'status': 'todo'}));

  Future<Map<String, dynamic>> updateSmartChecklistItem(String boardId, String itemId, Map<String, dynamic> patch) async =>
      _dataMap(await _send('PATCH', '/api/boards/$boardId/smart-checklist/items/$itemId', data: patch));

  Future<void> deleteSmartChecklistItem(String boardId, String itemId) async {
    await _send('DELETE', '/api/boards/$boardId/smart-checklist/items/$itemId');
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

  /// `GET /api/dashboard/sales` — deal + quotation pipeline (this year by default).
  /// [dateFrom]/[dateTo] are YYYY-MM-DD (Thai days); none = the server's default.
  /// [userId] = only that owner's deals/quotes (the server checks it is visible).
  Future<Map<String, dynamic>> getSalesDashboard({String? dateFrom, String? dateTo, String? userId}) async => _dataMap(await _send(
        'GET',
        '/api/dashboard/sales',
        query: {if (dateFrom != null) 'dateFrom': dateFrom, if (dateTo != null) 'dateTo': dateTo, if (userId != null) 'userId': userId},
      ));

  /// `GET /api/dashboard/case` — case counts by status / type / priority.
  Future<Map<String, dynamic>> getCaseDashboard({String? dateFrom, String? dateTo, String? userId}) async => _dataMap(await _send(
        'GET',
        '/api/dashboard/case',
        query: {if (dateFrom != null) 'dateFrom': dateFrom, if (dateTo != null) 'dateTo': dateTo, if (userId != null) 'userId': userId},
      ));

  /// Service dashboard (menu `svc-dash-case-summary`): kpis open/closed/overdue + by_status.
  /// [owner] = only cases of that owner (`owners=`).
  Future<Map<String, dynamic>> getCaseSummary({required String dateFrom, required String dateTo, String? owner}) async =>
      _dataMap(await _send('GET', '/api/service-dashboard/case-summary',
          query: {'dateFrom': dateFrom, 'dateTo': dateTo, if (owner != null) 'owners': owner}));

  /// Service dashboard (menu `svc-dash-case-performance`): SLA met / missed / %.
  Future<Map<String, dynamic>> getCasePerformance({required String dateFrom, required String dateTo, String? owner}) async =>
      _dataMap(await _send('GET', '/api/service-dashboard/case-performance',
          query: {'dateFrom': dateFrom, 'dateTo': dateTo, if (owner != null) 'owners': owner}));

  /// `GET /api/dashboard/customer` — lead/contact/account by status, source, funnel, kpis.
  Future<Map<String, dynamic>> getCustomerDashboard({String? dateFrom, String? dateTo, String? userId}) async => _dataMap(await _send(
        'GET',
        '/api/dashboard/customer',
        query: {if (dateFrom != null) 'dateFrom': dateFrom, if (dateTo != null) 'dateTo': dateTo, if (userId != null) 'userId': userId},
      ));

  /// `GET /api/dashboard/activity` — activities by type / status + monthly trend.
  Future<Map<String, dynamic>> getActivityDashboard({String? dateFrom, String? dateTo, String? userId}) async => _dataMap(await _send(
        'GET',
        '/api/dashboard/activity',
        query: {if (dateFrom != null) 'dateFrom': dateFrom, if (dateTo != null) 'dateTo': dateTo, if (userId != null) 'userId': userId},
      ));

  /// Sales dashboard pipeline (menu `sales-dash-pipeline`): kpis, funnel, close_window …
  /// [owner] = only that owner's deals; none = everyone the user may see.
  Future<Map<String, dynamic>> getSalesPipeline({required String dateFrom, required String dateTo, String? owner}) async =>
      _dataMap(await _send('GET', '/api/sales-dashboard/pipeline',
          query: {'dateFrom': dateFrom, 'dateTo': dateTo, if (owner != null) 'owners': owner}));

  /// Sales dashboard activities (menu `sales-dash-activity`): kpis + trend of done / missed / upcoming.
  Future<Map<String, dynamic>> getSalesActivity({required String dateFrom, required String dateTo, String? owner}) async =>
      _dataMap(await _send('GET', '/api/sales-dashboard/activity',
          query: {'dateFrom': dateFrom, 'dateTo': dateTo, if (owner != null) 'owners': owner}));

  /// My Workspace insights: `work_weeks [{week, created, cleared}]`, `case_weeks`.
  Future<Map<String, dynamic>> getHomeWorkInsights({int days = 30}) async =>
      _dataMap(await _send('GET', '/api/home/work', query: {'scope': 'insights', 'days': '$days'}));

  /// Light SLA summary for Home (any user with cases): `counts{open_ok, open_overdue, met, missed}`.
  Future<Map<String, dynamic>> getCaseSlaSummary({int days = 30}) async =>
      _dataMap(await _send('GET', '/api/home/case-sla-summary', query: {'period': '$days'}));

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

  Future<List<Map<String, dynamic>>> getMyJobs({int limit = 50, bool includeDone = false}) async {
    final env = await _send('GET', '/api/field-service/me/jobs', query: {
      'limit': '$limit',
      if (includeDone) 'include_done': '1',
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

  // ── AI Assistant (same endpoints as the web `/ai` page)

  /// Streams `POST /api/ai/chat` (server-sent events). Errors before the
  /// stream starts come back as JSON and are thrown like other API errors.
  Stream<AiStreamEvent> streamAiChat(Map<String, dynamic> body, {CancelToken? cancel}) async* {
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        '/api/ai/chat',
        data: {...body, 'stream': true},
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(minutes: 6),
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    final Stream<String> stream = res.data!.stream.cast<List<int>>().transform(utf8.decoder);
    if ((res.statusCode ?? 200) >= 400) {
      final text = await stream.join();
      dynamic raw;
      try {
        raw = jsonDecode(text);
      } catch (_) {
        raw = text;
      }
      throw _envelopeError(res.statusCode ?? 500, raw);
    }
    yield* parseAiSse(stream);
  }

  Future<List<Map<String, dynamic>>> getAiConversations({String? q}) async {
    final env = await _send('GET', '/api/ai/conversations', query: {if (q != null && q.trim().isNotEmpty) 'q': q.trim()});
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  Future<Map<String, dynamic>> createAiConversation(Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/ai/conversations', data: body));

  /// Conversation with `messages` (up to 500).
  Future<Map<String, dynamic>> getAiConversation(String id) async => _dataMap(await _send('GET', '/api/ai/conversations/$id'));

  Future<Map<String, dynamic>> updateAiConversation(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('PATCH', '/api/ai/conversations/$id', data: body));

  Future<void> deleteAiConversation(String id) async => _send('DELETE', '/api/ai/conversations/$id');

  Future<Map<String, dynamic>> appendAiMessage(String conversationId, Map<String, dynamic> message) async =>
      _dataMap(await _send('POST', '/api/ai/conversations/$conversationId/messages', data: {'message': message}));

  /// Drops the last assistant reply; the client then streams again.
  Future<Map<String, dynamic>> regenerateAi(String conversationId) async =>
      _dataMap(await _send('POST', '/api/ai/conversations/$conversationId/regenerate'));

  /// [accessMode]: `business` (members, signed in) or `public` (anyone with the link).
  Future<Map<String, dynamic>> createAiShare(String conversationId, {String accessMode = 'business'}) async =>
      _dataMap(await _send('POST', '/api/ai/conversations/$conversationId/shares', data: {'access_mode': accessMode}));

  /// Shared chat snapshot `{share: {title, owner_display, ...}, snapshot: {messages}}` (signed in).
  Future<Map<String, dynamic>> getAiSharedChat(String token) async => _dataMap(await _send('GET', '/api/ai/shared/${Uri.encodeComponent(token)}'));

  Future<List<Map<String, dynamic>>> getAiProjects() async {
    final env = await _send('GET', '/api/ai/projects');
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  /// `{id, url, original_name, kind, extract_status?, extracted_text?, ...}`.
  Future<Map<String, dynamic>> uploadAiAttachment(MultipartFile file, {String? conversationId}) async {
    final form = FormData()..files.add(MapEntry('file', file));
    if (conversationId != null) form.fields.add(MapEntry('conversation_id', conversationId));
    return _dataMap(await _send('POST', '/api/ai/attachments', data: form));
  }

  Future<Map<String, dynamic>> confirmAiTool(String proposalId, {String? boardId}) async =>
      _dataMap(await _send('POST', '/api/ai/tools/confirm', data: {'proposalId': proposalId, 'board_id': ?(boardId == null ? null : int.tryParse(boardId) ?? boardId)}));

  Future<Map<String, dynamic>> cancelAiTool(String proposalId) async =>
      _dataMap(await _send('POST', '/api/ai/tools/cancel', data: {'proposalId': proposalId}));

  Future<List<Map<String, dynamic>>> getAiSuggestedPrompts({String? module}) async {
    final env = await _send('GET', '/api/ai/suggested-prompts', query: {'module': ?module});
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  /// Follow-up chips after a reply: `{items:[{label, prompt, kind}]}`.
  Future<List<Map<String, dynamic>>> postAiReplySuggestions({required String lastReply, required String lastUserMessage, String locale = 'th'}) async {
    final env = await _send('POST', '/api/ai/reply-suggestions', data: {'last_reply': lastReply, 'last_user_message': lastUserMessage, 'locale': locale});
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }

  /// Plan, quota, used, remaining, modelDaily, alternatives.
  Future<Map<String, dynamic>> getAiUsage({String? provider, String? model}) async =>
      _dataMap(await _send('GET', '/api/ai/usage', query: {'provider': ?provider, 'model': ?model}));

  /// `{policies: {provider: {provider_enabled, enabled_models}}, catalogs: {provider: {configured, models}}}`.
  Future<Map<String, dynamic>> getAiModelPolicy() async => _dataMap(await _send('GET', '/api/ai/model-policy'));

  Future<Map<String, dynamic>> getAiModels({String? provider}) async =>
      _dataMap(await _send('GET', '/api/ai/models', query: {'provider': ?provider}));

  // ── ISAAC AI (web menu group "ISAAC AI")

  /// `{settings:{ai_chat,...}, keys}` — per-business AI feature flags.
  Future<Map<String, dynamic>> getAiSettings() async => _dataMap(await _send('GET', '/api/ai/settings'));

  /// `{config:{enabled, audience, menus{...}, minute_auto{...}}, source, connection}`.
  Future<Map<String, dynamic>> getIsaacPluginEffective() async =>
      _dataMap(await _send('GET', '/api/settings/isaac-plugin/effective'));

  /// ISAAC key-login: `{next_step:'EXCHANGE', launch_url, app_origin, ...}` or
  /// `{next_step:'PASSWORD_SETUP_EMAILED', email}`. `menu`: `bot` | `minute_auto`.
  Future<Map<String, dynamic>> isaacLaunch(String menu) async =>
      _dataMap(await _send('POST', '/api/integrations/isaac/launch', data: {'menu': menu}));

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

  /// `{ok, stock_returned: {quantity, balance_after}?}` on new servers.
  Future<Map<String, dynamic>> deleteJobPart(String jobId, String partId) async {
    final env = await _send('DELETE', '/api/field-service/jobs/$jobId/parts/$partId');
    final d = env['data'];
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  }

  /// Products to use as parts, with stock on hand when tracked (new servers;
  /// throws on older ones → free-text parts only).
  Future<List<Map<String, dynamic>>> searchPartCatalog(String q) async {
    final env = await _send('GET', '/api/field-service/parts/catalog', query: {'q': q});
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
  }

  /// Recompute the asset's PM / calibration due dates.
  Future<Map<String, dynamic>> recomputeAssetCycles(String assetId) async =>
      _dataMap(await _send('POST', '/api/field-service/assets/$assetId/recompute-cycles'));

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

  /// Quotation PDF in a language (th / en) and colour (color / bw), like the
  /// web menu: BIRT template first, then the built-in PDF.
  Future<List<int>> getQuotationPdfVariant(String id, {String lang = 'th', String color = 'color', String? template}) async {
    final q = 'lang=$lang&color=$color${template == null || template.isEmpty ? '' : '&template=${Uri.encodeQueryComponent(template)}'}';
    try {
      return await _downloadBytes('/api/quotation/$id/birt-pdf?$q');
    } catch (_) {
      try {
        return await _downloadBytes('/api/quotation/$id/pdf?lang=$lang&color=$color');
      } catch (_) {
        return getQuotationPdf(id); // older servers: the default PDF
      }
    }
  }

  // --- Documents: the exact endpoints the web preview uses ---------------
  // BIRT = the business's report template; "standard" = built-in jsPDF.

  String _qs(Map<String, String?> q) {
    final parts = [for (final e in q.entries) if (e.value != null && e.value!.isNotEmpty) '${e.key}=${Uri.encodeQueryComponent(e.value!)}'];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  Future<List<int>> getJobBirtPdf(String id) => _downloadBytes('/api/field-service/jobs/$id/birt-pdf');
  Future<List<int>> getJobStandardPdf(String id) => _downloadBytes('/api/field-service/jobs/$id/pdf');
  Future<List<int>> getInspectionBirtPdf(String id) => _downloadBytes('/api/field-service/inspections/$id/birt-pdf');
  Future<List<int>> getQuotationBirtPdf(String id, {String? lang, String? color, String? template}) =>
      _downloadBytes('/api/quotation/$id/birt-pdf${_qs({'template': template, 'lang': lang, 'color': color})}');
  Future<List<int>> getQuotationStandardPdf(String id, {String? lang, String? color}) =>
      _downloadBytes('/api/quotation/$id/pdf${_qs({'lang': lang, 'color': color})}');

  /// Quotation document templates (incl. inactive, like the web preview).
  Future<List<Map<String, dynamic>>> getQuotationTemplates() async {
    final env = await _send('GET', '/api/quotation/templates', query: {'all': '1'});
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
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

  /// Messages plus `read_receipts` ({messageId: [{user_id, read_at}]}).
  Future<({List<Map<String, dynamic>> items, Map<String, List<String>> readers})> getChatMessagesPage(
    String roomId, {
    int limit = 50,
    String? before,
  }) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/messages', query: {
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    });
    final data = env['data'];
    final readers = <String, List<String>>{};
    final rr = data is Map ? data['read_receipts'] : null;
    if (rr is Map) {
      rr.forEach((k, v) {
        if (v is List) {
          readers['$k'] = [for (final r in v) if (r is Map && r['user_id'] != null) '${r['user_id']}'];
        }
      });
    }
    return (items: extractMapList(data), readers: readers);
  }

  /// Full-text search across the rooms I belong to (`GET /api/chat/search`).
  Future<List<Map<String, dynamic>>> searchChat(String q, {int limit = 30, CancelToken? cancel}) async {
    final env = await _send('GET', '/api/chat/search', query: {'q': q, 'limit': '$limit'}, cancel: cancel);
    return extractMapList(env['data']);
  }

  /// Creates a group room with [memberIds] (the creator is added by the server).
  Future<Map<String, dynamic>> createChatRoom({required String name, required List<String> memberIds, String? description}) async {
    return _dataMap(await _send('POST', '/api/chat/rooms', data: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'member_ids': memberIds.map(int.tryParse).whereType<int>().toList(),
      'room_type': 'channel',
      'visibility': 'private',
    }));
  }

  Future<Map<String, dynamic>> postChatMessage(
    String roomId,
    String body, {
    List<Map<String, dynamic>>? attachments,
    String? replyToId,
    String? threadRootId,
    List<int>? mentionIds,
  }) async {
    return _dataMap(await _send(
      'POST',
      '/api/chat/rooms/$roomId/messages',
      data: {
        'body': body,
        if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
        if (replyToId != null) 'reply_to_id': int.tryParse(replyToId) ?? replyToId,
        if (threadRootId != null) 'thread_root_id': int.tryParse(threadRootId) ?? threadRootId,
        if (mentionIds != null && mentionIds.isNotEmpty) 'mention_user_ids': mentionIds,
        'source_ui': 'camp',
      },
    ));
  }

  /// Replies of a thread (root message included first).
  Future<List<Map<String, dynamic>>> getChatThread(String roomId, String rootId, {int limit = 100}) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/messages', query: {'thread_root': rootId, 'limit': '$limit'});
    return extractMapList(env['data']);
  }

  /// Forward a message to rooms (`{sent: [{room_id, message_id}], skipped}`), optional note.
  Future<Map<String, dynamic>> forwardChatMessage(String roomId, String messageId, List<String> roomIds, {String? comment}) async {
    return _dataMap(await _send('POST', '/api/chat/rooms/$roomId/messages/$messageId/forward', data: {
      'room_ids': roomIds.map((e) => int.tryParse(e) ?? e).toList(),
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    }));
  }

  /// Mute / unmute notifications of a room for me.
  Future<void> setChatRoomMuted(String roomId, bool muted) async {
    await _send('PATCH', '/api/chat/rooms/$roomId/me', data: {'muted': muted});
  }

  Future<void> setChatRoomStarred(String roomId, bool starred) async {
    await _send(starred ? 'POST' : 'DELETE', '/api/chat/stars/$roomId');
  }

  Future<void> saveChatMessage(String roomId, String messageId) async {
    await _send('POST', '/api/chat/rooms/$roomId/messages/$messageId/save');
  }

  Future<List<Map<String, dynamic>>> getChatRoomMembers(String roomId) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/members');
    final data = env['data'];
    return extractMapList(data is Map ? (data['list'] ?? data) : data);
  }

  Future<void> addChatRoomMember(String roomId, String userId) async {
    await _send('POST', '/api/chat/rooms/$roomId/members', data: {'user_id': int.tryParse(userId) ?? userId});
  }

  /// Files shared in a room, newest first.
  Future<List<Map<String, dynamic>>> getChatRoomFiles(String roomId) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/files');
    final data = env['data'];
    return extractMapList(data is Map ? (data['list'] ?? data) : data);
  }

  /// Decline a ringing call without a socket (phone call screen while the app was closed).
  Future<void> declineCall(String callId) async {
    await _send('POST', '/api/calls/${Uri.encodeComponent(callId)}/decline');
  }

  /// STUN / TURN for calls (`{ice_servers: [...], turn, max_participants}`).
  Future<Map<String, dynamic>> getIceServers() async => _dataMap(await _send('GET', '/api/calls/ice-servers'));

  /// Open Graph preview `{url, title, description, image, siteName}` (cached by the server).
  Future<Map<String, dynamic>> unfurlChatLink(String url) async {
    return _dataMap(await _send('GET', '/api/chat/unfurl', query: {'url': url}));
  }

  Future<Map<String, dynamic>> editChatMessage(String roomId, String messageId, String body) async {
    return _dataMap(await _send('PATCH', '/api/chat/rooms/$roomId/messages/$messageId', data: {'body': body}));
  }

  Future<void> deleteChatMessage(String roomId, String messageId) async {
    await _send('DELETE', '/api/chat/rooms/$roomId/messages/$messageId');
  }

  /// Pinned messages of a room: `[{message_id, pinned_by, pinned_at, message}]`.
  Future<List<Map<String, dynamic>>> getChatPins(String roomId) async {
    final env = await _send('GET', '/api/chat/rooms/$roomId/pins');
    final data = env['data'];
    return extractMapList(data is Map ? data['list'] : data);
  }

  Future<void> setChatPin(String roomId, String messageId, {required bool pinned}) async {
    await _send(pinned ? 'POST' : 'DELETE', '/api/chat/rooms/$roomId/pins/$messageId');
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

  /// Password change proven by an OTP (no current password): [otpToken] is the
  /// session the OTP check returned for this same user. Afterwards that extra
  /// session is signed out so it does not linger in the device list.
  Future<void> changePasswordWithOtpToken(String otpToken, String newPassword) async {
    try {
      await _send('PUT', '/api/me/password',
          data: {'new_password': newPassword}, options: Options(extra: {'nx_token': otpToken}));
    } finally {
      try {
        await _send('POST', '/api/auth/logout', options: Options(extra: {'nx_token': otpToken}));
      } catch (_) {}
    }
  }

  /// Closes the signed-in user's own account (App Store / Google Play rule).
  /// [otpToken] is the fresh session from an OTP check (NEXTX accepts tokens
  /// issued in the last 10 minutes only). Returns false when this server has
  /// no in-app deletion yet (older NEXTX) so the app can point to the web page.
  Future<bool> deleteMyAccount(String otpToken) async {
    try {
      await _send('POST', '/api/me/delete-account',
          data: {'confirm': 'DELETE'}, options: Options(extra: {'nx_token': otpToken}));
      return true;
    } on ApiException catch (e) {
      // Route missing (plain 404, not a NEXTX error envelope) → older server.
      if (e.statusCode == 404) return false;
      rethrow;
    }
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

  Future<Map<String, dynamic>> getMailItem(String id, {MailAccount? account}) async {
    return _dataMap(await _send('GET', '/api/mail/$id', query: account?.query));
  }

  /// Gmail / Outlook accounts the user connected on the web (`GET /api/mail/connections`).
  Future<List<MailAccount>> getMailAccounts() async {
    final env = await _send('GET', '/api/mail/connections');
    return [
      for (final c in extractMapList(env['data']))
        if (MailAccount.fromMap(c) case final a?) a,
    ];
  }

  /// One page of a box. Internal mail when [account] is null.
  Future<({List<Map<String, dynamic>> items, String? nextCursor, bool syncing})> getMailPage({
    String box = 'inbox',
    MailAccount? account,
    String? cursor,
    int limit = 50,
  }) async {
    final env = await _send('GET', '/api/mail', query: {
      'box': box,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      ...?account?.query,
    });
    final data = env['data'];
    return (
      items: extractMapList(data),
      nextCursor: data is Map ? data['nextCursor']?.toString() : null,
      syncing: data is Map && data['syncing'] == true,
    );
  }

  Future<void> markMailUnread(String id, {MailAccount? account}) async {
    await _send('PUT', '/api/mail/$id/unread', query: account?.query);
  }

  /// Gmail / Outlook only (the server rejects star on internal mail).
  Future<void> setMailStarred(String id, bool starred, {required MailAccount account}) async {
    await _send('PUT', '/api/mail/$id/star', query: account.query, data: {'starred': starred});
  }

  Future<void> archiveMail(String id, {required MailAccount account, bool undo = false}) async {
    await _send('PUT', '/api/mail/$id/archive', query: account.query, data: {if (undo) 'undo': true});
  }

  Future<List<Map<String, dynamic>>> getMailAttachments(String id, {required MailAccount account}) async {
    final env = await _send('GET', '/api/mail/$id/attachments', query: account.query);
    return extractMapList(env['data']);
  }

  Future<List<int>> downloadMailAttachment(String id, String fileId, {required MailAccount account}) {
    final q = Uri(queryParameters: account.query).query;
    return _downloadBytes('/api/mail/$id/attachments/$fileId/download?$q');
  }

  /// Sends through a connected Gmail / Outlook account. [attachments] are
  /// File Manager ids (`{file_id}`), resolved by the server like the web.
  Future<Map<String, dynamic>> sendExternalMail({
    required MailAccount account,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? action,
    String? replyToId,
    String? threadId,
    List<Map<String, dynamic>> attachments = const [],
    bool isDraft = false,
  }) async {
    return _dataMap(await _send('POST', '/api/mail', data: {
      'source': account.provider,
      'connectionId': int.tryParse(account.id) ?? account.id,
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'subject': subject,
      'body': bodyHtml.replaceAll(RegExp(r'<[^>]*>'), ''),
      'body_html': bodyHtml,
      if (action != null) 'action': action,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (threadId != null) 'thread_id': threadId,
      if (attachments.isNotEmpty) 'attachments': attachments,
      'is_draft': isDraft,
    }));
  }
  /// Search internal mail (subject / body / sender) — `GET /api/mail/search?q=`.
  Future<List<Map<String, dynamic>>> searchMail(String q, {CancelToken? cancel}) async {
    final env = await _send('GET', '/api/mail/search', query: {'q': q}, cancel: cancel);
    return extractMapList(env['data']);
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

  Future<void> markMailRead(String id, {MailAccount? account}) async {
    await _send('PUT', '/api/mail/$id/read', query: account?.query);
  }

  /// Moves to trash; with [permanent] removes a message that is already in trash.
  Future<void> deleteMail(String id, {bool permanent = false, MailAccount? account}) async {
    await _send('DELETE', '/api/mail/$id', query: {if (permanent) 'permanent': '1', ...?account?.query});
  }

  Future<void> restoreMail(String id, {MailAccount? account}) async {
    await _send('PUT', '/api/mail/$id/restore', query: account?.query);
  }


  /// Published release / feature announcements (`GET /api/whats-new`).
  Future<List<Map<String, dynamic>>> getWhatsNew() async {
    final env = await _send('GET', '/api/whats-new');
    return extractMapList(env['data']);
  }

  Future<int> getWhatsNewUnread() async {
    final m = _dataMap(await _send('GET', '/api/whats-new/unread-count'));
    return (m['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markWhatsNewViewed(List<int> ids) async {
    if (ids.isEmpty) return;
    await _send('POST', '/api/whats-new/views/batch', data: {'ids': ids});
  }

  /// "รับทราบ" — hides the item for this user.
  Future<void> ackWhatsNew(int id) async {
    await _send('POST', '/api/whats-new/$id/ack');
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

  /// Receipt PDF for a store order.
  Future<List<int>> downloadOrderReceipt(String id) => _downloadBytes('/api/commercial/orders/$id/receipt');

  /// Shipping label PDF (needs a booked delivery job).
  Future<List<int>> downloadShippingLabel(String id) => _downloadBytes('/api/commercial/orders/$id/shipping-label');

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

  /// New sign link for a pending request (optionally re-emailing it).
  Future<Map<String, dynamic>> resendCaseMandaySign(String requestId, {bool skipEmail = true}) async {
    return _dataMap(await _send('POST', '/api/entity/case/manday-requests/$requestId/resend-sign', data: {'skip_email': skipEmail}));
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

  // ───────────── AI การสื่อสาร (/api/comm-ai) ─────────────

  /// `{settings, defaults, can_edit, max_range_days}`
  Future<Map<String, dynamic>> getCommAiSettings() async => _dataMap(await _send('GET', '/api/comm-ai/settings'));

  /// Chat summary of a room for a Thai-time range (`YYYY-MM-DD HH:mm`). Streams token / status / done / error.
  Stream<AiStreamEvent> streamChatSummary(String roomId, {required String from, required String to, bool force = false, CancelToken? cancel}) async* {
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        '/api/comm-ai/chat/rooms/$roomId/summary',
        data: {'from': from, 'to': to, 'force': force, 'stream': true},
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(minutes: 6),
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    final Stream<String> stream = res.data!.stream.cast<List<int>>().transform(utf8.decoder);
    if ((res.statusCode ?? 200) >= 400) {
      final text = await stream.join();
      dynamic raw;
      try {
        raw = jsonDecode(text);
      } catch (_) {
        raw = text;
      }
      throw _envelopeError(res.statusCode ?? 500, raw);
    }
    yield* parseAiSse(stream);
  }

  Future<List<Map<String, dynamic>>> getChatSummaries(String roomId) async {
    final d = _dataMap(await _send('GET', '/api/comm-ai/chat/rooms/$roomId/summaries'));
    return extractMapList(d['list']);
  }

  Future<Map<String, dynamic>> getCommAiSummary(String id) async => _dataMap(await _send('GET', '/api/comm-ai/summaries/$id'));

  /// Call: transcript (filtered by sharing), summary, recordings.
  Future<Map<String, dynamic>> getCommAiCall(String callId) async => _dataMap(await _send('GET', '/api/comm-ai/calls/${Uri.encodeComponent(callId)}'));

  Future<void> uploadCallRecording(String callId, String filePath, {int durationMs = 0, String mime = 'audio/mp4'}) async {
    final form = FormData.fromMap({
      'duration_ms': '$durationMs',
      'audio': await MultipartFile.fromFile(filePath, filename: 'call.${mime.contains('ogg') ? 'ogg' : mime.contains('wav') ? 'wav' : 'm4a'}', contentType: DioMediaType.parse(mime)),
    });
    await _send('POST', '/api/comm-ai/calls/${Uri.encodeComponent(callId)}/recording', data: form, options: Options(sendTimeout: const Duration(minutes: 5)));
  }

  /// One part of a long call recording (parts are joined on the server when the final one arrives).
  Future<Map<String, dynamic>> uploadCallRecordingPart(String callId, String filePath,
      {required int part, int parts = 0, bool isFinal = false, int durationMs = 0, String mime = 'audio/wav'}) async {
    final form = FormData.fromMap({
      'part': '$part',
      if (isFinal) 'final': '1',
      if (isFinal) 'parts': '$parts',
      'duration_ms': '$durationMs',
      'audio': await MultipartFile.fromFile(filePath, filename: 'call.${mime.contains('wav') ? 'wav' : 'm4a'}', contentType: DioMediaType.parse(mime)),
    });
    return _dataMap(await _send('POST', '/api/comm-ai/calls/${Uri.encodeComponent(callId)}/recording', data: form, options: Options(sendTimeout: const Duration(minutes: 5))));
  }

  Future<List<int>> downloadCallRecording(String path) => _downloadBytes(path);

  /// `{list, next_before}` — type all|call|video|chat, from/to YYYY-MM-DD (Thai), q, before (ISO).
  Future<Map<String, dynamic>> getCommAiHistory({String type = 'all', String? from, String? to, String? q, String? before, int limit = 30}) async =>
      _dataMap(await _send('GET', '/api/comm-ai/history', query: {
        'type': type,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (before != null) 'before': before,
        'limit': limit,
      }));

  /// kind 'call' (id = call id) or 'chat' (id = summary id). format pdf|docx|md|txt.
  Future<List<int>> exportConversation(String kind, String id, {String format = 'pdf', List<String> include = const ['summary', 'actions', 'transcript'], String lang = 'th'}) =>
      _downloadBytes('/api/comm-ai/export/$kind/${Uri.encodeComponent(id)}?format=$format&include=${include.join(',')}&lang=$lang');

  Future<Map<String, dynamic>> shareConversationEmail(String kind, String id, {required List<String> to, List<String> cc = const [], String message = '', List<String> include = const ['summary', 'actions', 'transcript'], String format = 'pdf', String lang = 'th'}) async =>
      _dataMap(await _send('POST', '/api/comm-ai/share/$kind/${Uri.encodeComponent(id)}/email', data: {'to': to, 'cc': cc, 'message': message, 'include': include, 'format': format, 'lang': lang}));

  /// `{token, url_path, expires_at}`
  Future<Map<String, dynamic>> createConversationLink(String kind, String id, {List<String> include = const ['summary', 'actions', 'transcript'], int days = 7, String? password}) async =>
      _dataMap(await _send('POST', '/api/comm-ai/share/$kind/${Uri.encodeComponent(id)}/link', data: {'include': include, 'days': days, if (password != null && password.isNotEmpty) 'password': password}));

  /// Links this user created for a conversation: `[{id, expires_at, revoked_at, view_count, has_password, ...}]`.
  Future<List<Map<String, dynamic>>> listConversationLinks(String kind, String id) async =>
      extractMapList(_dataMap(await _send('GET', '/api/comm-ai/share/$kind/${Uri.encodeComponent(id)}/links'))['list']);

  Future<void> revokeConversationLink(int linkId) async => _send('DELETE', '/api/comm-ai/share/links/$linkId');

  /// Admin: partial update → `{settings}`.
  Future<Map<String, dynamic>> saveCommAiSettings(Map<String, dynamic> patch) async => _dataMap(await _send('PUT', '/api/comm-ai/settings', data: patch));

  /// `{prompts: {call: {prompt, is_default, version, ...}, chat: {...}}, max_chars}`
  Future<Map<String, dynamic>> getCommAiPrompts() async => _dataMap(await _send('GET', '/api/comm-ai/prompts'));

  Future<Map<String, dynamic>> saveCommAiPrompt(String kind, {String? prompt, bool reset = false}) async =>
      _dataMap(await _send('PUT', '/api/comm-ai/prompts/$kind', data: reset ? {'reset': true} : {'prompt': prompt ?? ''}));

  /// Runs the prompt on a sample conversation (or [sample] lines "name: text") → `{result, ms}`. Not saved.
  Future<Map<String, dynamic>> testCommAiPrompt(String kind, {String? prompt, String? sample}) async => _dataMap(await _send(
        'POST',
        '/api/comm-ai/prompts/$kind/test',
        data: {if (prompt != null) 'prompt': prompt, if (sample != null && sample.trim().isNotEmpty) 'sample': sample},
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      ));

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
