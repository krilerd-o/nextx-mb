import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/device_push_service.dart';
import '../services/offline_queue.dart';
import '../services/realtime_service.dart';
import 'session_state.dart';

const String _keyApiBaseUrl = 'api_base_url';
const String _keyThemeMode = 'theme_mode';
const String _keyUserId = 'session_user_id';
const String _keyBusinessId = 'session_business_id';
const String _keyBusinessName = 'session_business_name';
const String _keyEmail = 'session_email';
const String _keyDisplayName = 'session_display_name';
const String _keyPackageCode = 'session_package_code';
const String _keyMenuKeys = 'session_menu_keys';
const String _keyGettingStartedDone = 'getting_started_done';
const String _keySearchHistory = 'search_history_json';
const String _keyAccentIndex = 'accent_index';
const String _keyUiLocale = 'ui_locale';
const String _keyDateFormat = 'date_format_pattern';
const String _keyProfileAvatarB64 = 'profile_avatar_base64';

const _secureTokenKey = 'access_token';
const int _maxAvatarBytes = 400000;

class AppConfig extends ChangeNotifier {
  AppConfig() {
    _api.setOnUnauthorized(_handleUnauthorized);
    _load();
  }

  static const List<Color> accentOptions = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
  ];

  final ApiClient _api = ApiClient();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final OfflineQueue _offlineQueue = OfflineQueue();

  String _apiBaseUrl = resolveApiBaseUrl();
  ThemeMode _themeMode = ThemeMode.system;
  SessionState _session = const SessionState();
  bool _gettingStartedDone = false;
  List<String> _searchHistory = [];
  bool _ready = false;
  int _accentIndex = 0;
  String _uiLocaleCode = 'th';
  String _dateFormatPattern = 'dd/MM/yyyy HH:mm';
  String? _profileAvatarBase64;
  bool _loggingOut = false;

  String get apiBaseUrl => _apiBaseUrl;
  ThemeMode get themeMode => _themeMode;
  bool get isReady => _ready;
  SessionState get session => _session;
  bool get isLoggedIn => _session.isLoggedIn;
  bool get hasBusinessContext => _session.hasBusinessContext;
  bool get gettingStartedDone => _gettingStartedDone;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  int get accentIndex => _accentIndex;
  Color get accentColor =>
      accentOptions[_accentIndex.clamp(0, accentOptions.length - 1)];
  String get uiLocaleCode => _uiLocaleCode;
  String get dateFormatPattern => _dateFormatPattern;
  String? get profileAvatarBase64 => _profileAvatarBase64;

  @visibleForTesting
  void debugOverrideSession(SessionState session) {
    _session = session;
    notifyListeners();
  }

  ApiClient get apiClient {
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: _session.businessId,
    );
    return _api;
  }

  String get initialRouteName {
    if (!_ready) return 'splash';
    if (!_session.isLoggedIn) return 'login';
    if (!_session.hasBusinessContext) return 'hub';
    if (!_gettingStartedDone) return 'gettingStarted';
    return 'main';
  }

  bool _isLegacyLocalUrl(String url) {
    final u = url.trim();
    return u.contains('localhost:4000') ||
        u.contains('127.0.0.1:4000') ||
        u.contains('10.0.2.2:4000');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_keyApiBaseUrl);
    final loaded = (savedUrl == null || savedUrl.isEmpty || _isLegacyLocalUrl(savedUrl))
        ? kDefaultApiBaseUrl
        : savedUrl;
    _apiBaseUrl = resolveApiBaseUrl(loaded);
    final modeIndex = prefs.getInt(_keyThemeMode);
    if (modeIndex != null && modeIndex >= 0 && modeIndex <= 2) {
      _themeMode = ThemeMode.values[modeIndex];
    }
    _gettingStartedDone = prefs.getBool(_keyGettingStartedDone) ?? false;
    final rawAccent = prefs.getInt(_keyAccentIndex) ?? 0;
    final maxA = accentOptions.length - 1;
    _accentIndex = rawAccent < 0 ? 0 : (rawAccent > maxA ? maxA : rawAccent);
    _uiLocaleCode = prefs.getString(_keyUiLocale) ?? 'th';
    _dateFormatPattern = prefs.getString(_keyDateFormat) ?? 'dd/MM/yyyy HH:mm';
    var token = await _secure.read(key: _secureTokenKey);
    if (token == 'demo-token') {
      token = null;
      await _secure.delete(key: _secureTokenKey);
    }
    final uid = prefs.getString(_keyUserId);
    final bid = prefs.getString(_keyBusinessId);
    final bname = prefs.getString(_keyBusinessName);
    final email = prefs.getString(_keyEmail);
    final display = prefs.getString(_keyDisplayName);
    final pkg = prefs.getString(_keyPackageCode);
    final menusRaw = prefs.getString(_keyMenuKeys);
    List<String>? menus;
    if (menusRaw != null && menusRaw.isNotEmpty) {
      menus = menusRaw.split(',').where((e) => e.isNotEmpty).toList();
    }
    _jsonSearchHistory(prefs.getString(_keySearchHistory));
    _profileAvatarBase64 = prefs.getString(_keyProfileAvatarB64);
    _session = SessionState(
      accessToken: token,
      userId: uid,
      businessId: bid,
      businessName: bname,
      email: email,
      displayName: display,
      packageCode: pkg,
      menuKeys: menus,
      menusLoaded: menus != null,
    );
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: token,
      userId: uid,
      businessId: bid,
    );
    _ready = true;
    notifyListeners();
    if (_session.isLoggedIn) {
      try {
        await refreshSession();
        _connectRealtime();
        await flushOfflineQueue();
        await DevicePushService.instance.sync(this);
        notifyListeners();
      } catch (_) {}
    }
  }

  void _jsonSearchHistory(String? raw) {
    if (raw == null || raw.isEmpty) {
      _searchHistory = [];
      return;
    }
    _searchHistory = raw.split('|||').where((e) => e.isNotEmpty).toList();
  }

  void _handleUnauthorized() {
    if (_loggingOut || !_session.isLoggedIn) return;
    logout();
  }

  void _connectRealtime() {
    final token = _session.accessToken;
    if (token == null || token.isEmpty) return;
    RealtimeService.instance.connect(
      baseUrl: _apiBaseUrl,
      token: token,
      businessId: _session.businessId,
    );
  }

  Future<void> setApiBaseUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return;
    _apiBaseUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, trimmed);
    _api.attachSession(
      baseUrl: trimmed,
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: _session.businessId,
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setAccentIndex(int index) async {
    final maxI = accentOptions.length - 1;
    _accentIndex = index < 0 ? 0 : (index > maxI ? maxI : index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccentIndex, _accentIndex);
    notifyListeners();
  }

  Future<void> setUiLocaleCode(String code) async {
    _uiLocaleCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUiLocale, code);
    notifyListeners();
  }

  Future<void> setDateFormatPattern(String pattern) async {
    _dateFormatPattern = pattern;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDateFormat, pattern);
    notifyListeners();
  }

  Future<void> uploadProfileAvatarToServer() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 82,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await apiClient.uploadAvatar(
      MultipartFile.fromBytes(bytes, filename: x.name),
    );
    _profileAvatarBase64 = base64Encode(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfileAvatarB64, _profileAvatarBase64!);
    notifyListeners();
  }

  Future<String?> pickAndStoreProfileAvatar() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 82,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    if (bytes.length > _maxAvatarBytes) {
      return 'รูปใหญ่เกินไป (จำกัด ~${_maxAvatarBytes ~/ 1000} KB หลังบีบอัด)';
    }
    final b64 = base64Encode(bytes);
    _profileAvatarBase64 = b64;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfileAvatarB64, b64);
    notifyListeners();
    return null;
  }

  Future<void> clearProfileAvatar() async {
    _profileAvatarBase64 = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProfileAvatarB64);
    notifyListeners();
  }

  String _displayFromUser(Map<String, dynamic>? user, String email) {
    if (user == null) return email;
    final first = user['first_name'] ?? user['first_name_th'];
    final last = user['last_name'] ?? user['last_name_th'];
    final name = [first, last].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    if (name.isNotEmpty) return name;
    return user['user_name']?.toString() ?? email;
  }

  Future<void> loginWithPassword({
    required String email,
    required String password,
  }) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.login(email: email, password: password, remember: true);
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'ไม่พบ token จากเซิร์ฟเวอร์');
    }
    final user = asStringKeyedMap(data['user']);
    final business = asStringKeyedMap(data['business']);
    final uid = user?['id']?.toString() ?? '';
    final emailOut = user?['email1']?.toString() ?? email;
    await _secure.write(key: _secureTokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, uid);
    await prefs.setString(_keyEmail, emailOut);
    await prefs.setString(_keyDisplayName, _displayFromUser(user, emailOut));
    final bid = business?['id']?.toString();
    if (bid != null && bid.isNotEmpty) {
      await prefs.setString(_keyBusinessId, bid);
      await prefs.setString(_keyBusinessName, business?['business_name']?.toString() ?? '');
    } else {
      await prefs.remove(_keyBusinessId);
      await prefs.remove(_keyBusinessName);
    }
    _session = SessionState(
      accessToken: token,
      userId: uid,
      businessId: bid,
      businessName: business?['business_name']?.toString(),
      email: emailOut,
      displayName: _displayFromUser(user, emailOut),
    );
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: token,
      userId: uid,
      businessId: bid,
    );
    notifyListeners();
    await refreshSession();
    _connectRealtime();
    await flushOfflineQueue();
    await DevicePushService.instance.sync(this);
    notifyListeners();
  }

  Future<void> syncPushToken() async {
    await DevicePushService.instance.sync(this);
    notifyListeners();
  }

  Future<void> refreshSession() async {
    if (!_session.isLoggedIn) return;
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: _session.businessId,
    );
    final me = await _api.getMe();
    final user = asStringKeyedMap(me['user']);
    final business = asStringKeyedMap(me['business']);
    final uid = user?['id']?.toString() ?? me['userId']?.toString() ?? _session.userId;
    final email = user?['email1']?.toString() ?? _session.email;
    final bid = business?['id']?.toString() ?? me['businessId']?.toString() ?? _session.businessId;
    final bname = business?['business_name']?.toString() ?? _session.businessName;
    List<String>? menus;
    final allowed = me['allowed_menu_keys'];
    if (allowed is List) {
      menus = allowed.map((e) => e.toString()).toList();
    }
    final superadmin = me['is_superadmin'] == true ||
        user?['is_superadmin'] == true ||
        user?['is_superadmin'] == 1;
    final pkg = _session.packageCode ??
        business?['default_package_code']?.toString();
    if (menus == null && pkg != null && pkg.isNotEmpty && bid != null) {
      try {
        final keys = await _api.getMenuKeys(packageCode: pkg);
        if (keys.isNotEmpty) menus = keys;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    if (uid != null) await prefs.setString(_keyUserId, uid);
    if (email != null) await prefs.setString(_keyEmail, email);
    if (bid != null && bid.isNotEmpty) {
      await prefs.setString(_keyBusinessId, bid);
      await prefs.setString(_keyBusinessName, bname ?? '');
    }
    if (pkg != null) await prefs.setString(_keyPackageCode, pkg);
    if (menus != null) await prefs.setString(_keyMenuKeys, menus.join(','));
    final display = _displayFromUser(user, email ?? '');
    await prefs.setString(_keyDisplayName, display);
    _session = _session.copyWith(
      userId: uid,
      businessId: bid,
      businessName: bname,
      email: email,
      displayName: display,
      packageCode: pkg,
      menuKeys: menus,
      isSuperadmin: superadmin,
      menusLoaded: true,
    );
    notifyListeners();
  }

  Future<void> selectBusiness({
    required String businessId,
    required String businessName,
    String? packageCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBusinessId, businessId);
    await prefs.setString(_keyBusinessName, businessName);
    if (packageCode != null) {
      await prefs.setString(_keyPackageCode, packageCode);
    }
    _session = _session.copyWith(
      businessId: businessId,
      businessName: businessName,
      packageCode: packageCode ?? _session.packageCode,
    );
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: businessId,
    );
    notifyListeners();
    try {
      await refreshSession();
    } catch (_) {}
    try {
      await apiClient.setDefaultBusiness(businessId);
    } catch (_) {}
    _connectRealtime();
  }

  Future<void> completeGettingStarted() async {
    _gettingStartedDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGettingStartedDone, true);
    notifyListeners();
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      await DevicePushService.instance.unregister(this);
    } catch (_) {}
    try {
      await _api.logoutRemote();
    } catch (_) {}
    RealtimeService.instance.disconnect();
    await _secure.delete(key: _secureTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyBusinessId);
    await prefs.remove(_keyBusinessName);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyPackageCode);
    await prefs.remove(_keyMenuKeys);
    _session = const SessionState();
    _api.attachSession(baseUrl: _apiBaseUrl);
    _loggingOut = false;
    notifyListeners();
  }

  Future<void> addSearchHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _searchHistory = [
      q,
      ..._searchHistory.where((e) => e != q),
    ].take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySearchHistory, _searchHistory.join('|||'));
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySearchHistory);
    notifyListeners();
  }

  Future<void> persistOAuthToken(String token) async {
    await _secure.write(key: _secureTokenKey, value: token);
    _session = _session.copyWith(accessToken: token);
    notifyListeners();
  }

  Future<void> flushOfflineQueue() async {
    final pending = await _offlineQueue.load();
    if (pending.isEmpty) return;
    final remain = <Map<String, dynamic>>[];
    for (final item in pending) {
      try {
        final type = item['type']?.toString();
        final id = item['id']?.toString() ?? '';
        final lat = (item['lat'] as num?)?.toDouble();
        final lng = (item['lng'] as num?)?.toDouble();
        if (type != 'checkin' || id.isEmpty) continue;
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;
        await apiClient.activityCheckin(id, lat: lat, lng: lng);
      } catch (_) {
        remain.add(item);
      }
    }
    await _offlineQueue.save(remain);
  }

  Future<void> queueFieldAction(Map<String, dynamic> item) {
    if (item['type']?.toString() != 'checkin') return Future.value();
    final lat = (item['lat'] as num?)?.toDouble() ?? 0;
    final lng = (item['lng'] as num?)?.toDouble() ?? 0;
    if (lat == 0 && lng == 0) return Future.value();
    return _offlineQueue.enqueue(item);
  }

  String get devicePlatform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'unknown';
    }
  }
}
