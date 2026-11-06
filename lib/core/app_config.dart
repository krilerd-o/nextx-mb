import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/app_lock.dart';
import '../services/device_push_service.dart';
import '../services/offline_queue.dart';
import '../services/realtime_service.dart';
import '../services/unread_service.dart';
import 'app_version.dart';
import 'auth_errors.dart';
import 'auth_redirect.dart';
import 'menu_access.dart';
import 'invite_link.dart';
import 'recent_accounts.dart';
import 'server_profile.dart';
import 'session_state.dart';
import 'shell_tabs.dart';

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
const String _keyServerConfirmed = 'server_confirmed';
const String _keyRecentServers = 'recent_servers';
const String _keyPackageId = 'session_package_id';
const String _keySessionExpired = 'session_expired_notice';
const String _keyRecentAccounts = 'recent_accounts_v1';
const String _keyServerInfo = 'server_mobile_info_v1';
const String _keyPunchFailed = 'offline_punch_failed_v1';

const _secureTokenKey = 'access_token';
const int _maxAvatarBytes = 400000;

class AppConfig extends ChangeNotifier {
  AppConfig() {
    _api.setOnUnauthorized(_handleUnauthorized);
    _api.setOnSessionToken(_adoptSessionToken);
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
  bool _serverConfirmed = false;
  List<String> _recentServers = [];
  String? _packageId;
  ShellTabsConfig? _shell;
  bool _sessionExpiredNotice = false;
  bool _manualBusinessPick = false;
  bool _manualPackagePick = false;

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

  /// The user picked/confirmed a NEXTX server (first-run step).
  bool get serverConfirmed => _serverConfirmed;
  List<String> get recentServers => List.unmodifiable(_recentServers);

  List<RecentAccount> _recentAccounts = const [];

  /// Accounts signed in on this server before (most recent first).
  List<RecentAccount> get recentAccounts => recentAccountsFor(_recentAccounts, _apiBaseUrl);

  Future<void> forgetRecentAccount(RecentAccount a) async {
    _recentAccounts = removeRecentAccount(_recentAccounts, a);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRecentAccounts, encodeRecentAccounts(_recentAccounts));
    notifyListeners();
  }

  InviteLink? _pendingInvite;

  /// Invite link opened before sign-in / setup finished; used by the
  /// register screen (signed out) or the "join business" prompt (signed in).
  InviteLink? get pendingInvite => _pendingInvite;

  /// Called from the router redirect — no notify (would re-enter routing).
  void stashInvite(InviteLink invite) => _pendingInvite = invite;

  void clearPendingInvite() => _pendingInvite = null;

  MobileServerInfo? _serverInfo;
  DateTime? _serverInfoAt;

  /// What this server offers the app (`/api/health` → `mobile`); null on older servers.
  MobileServerInfo? get serverInfo => _serverInfo;

  UpdateNeed get updateNeed => updateNeedFor(_serverInfo, AppVersion.value);

  String get _serverInfoKey => '${_keyServerInfo}_${serverLabel(_apiBaseUrl)}';

  /// Re-reads the server's mobile info (at most every 30 minutes unless [force]).
  Future<void> refreshServerInfo({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _serverInfoAt != null && now.difference(_serverInfoAt!) < const Duration(minutes: 30)) return;
    _serverInfoAt = now;
    Object? body;
    try {
      body = await apiClient.getHealthRaw();
    } catch (_) {
      return; // offline / unreachable: keep the cached value
    }
    if (!isNextxHealth(body)) return;
    final info = MobileServerInfo.fromJson(((body as Map)['data'] as Map)['mobile']);
    final before = jsonEncode(_serverInfo?.toJson());
    _serverInfo = info;
    final prefs = await SharedPreferences.getInstance();
    if (info == null) {
      await prefs.remove(_serverInfoKey);
    } else {
      await prefs.setString(_serverInfoKey, jsonEncode(info.toJson()));
    }
    if (before != jsonEncode(_serverInfo?.toJson())) notifyListeners();
  }

  void _loadServerInfo(SharedPreferences prefs) {
    final raw = prefs.getString(_serverInfoKey);
    try {
      _serverInfo = raw == null ? null : MobileServerInfo.fromJson(jsonDecode(raw));
    } catch (_) {
      _serverInfo = null;
    }
  }

  /// Renewed token from the server (`X-Session-Token`): keep it so the session
  /// only ends after 90 days without use (NEXTX sliding session).
  Future<void> _adoptSessionToken(String fresh) async {
    if (!_session.isLoggedIn || _session.accessToken == fresh) return;
    _session = _session.copyWith(accessToken: fresh);
    try {
      await _secure.write(key: _secureTokenKey, value: fresh);
    } catch (e) {
      debugPrint('save renewed token: $e');
    }
  }

  String? _authLinkError;

  /// Error from a `moainext://app/login?error=` return (LINE in the system browser).
  String? get authLinkError => _authLinkError;

  void clearAuthLinkError() => _authLinkError = null;

  bool _authLinkBusy = false;
  bool get authLinkBusy => _authLinkBusy;

  /// `moainext://app/login?token=…` from the LINE flow started with `?app=1`.
  /// Called from the router redirect, so the work runs after the current frame.
  void handleAuthDeepLink(AuthRedirect r) {
    if (_session.isLoggedIn) return;
    Future.microtask(() async {
      if (r.token != null) {
        _authLinkBusy = true;
        _authLinkError = null;
        notifyListeners();
        try {
          await loginWithToken(r.token!);
        } catch (e) {
          _authLinkError = authErrorMessage(e);
        } finally {
          _authLinkBusy = false;
          notifyListeners();
        }
      } else if (r.error != null) {
        _authLinkError = authRedirectErrorText(r.error!);
        notifyListeners();
      }
    });
  }

  /// Joins the business of an invite link with the signed-in account.
  Future<Map<String, dynamic>> joinWithInvite(String token) async {
    final data = await apiClient.requestJoin(inviteToken: token);
    _pendingInvite = null;
    return data;
  }

  /// Package chosen for the current business (`''` = business has no packages).
  bool get hasPackage => _session.packageCode != null;
  String? get packageId => _packageId;

  /// User went back on purpose → show the list instead of auto-selecting.
  bool get manualBusinessPick => _manualBusinessPick;
  bool get manualPackagePick => _manualPackagePick;

  /// Roles + bottom tabs for this user on this server (null = not set up yet).
  ShellTabsConfig? get shellConfig => _shell;
  bool get roleSetupDone => _shell != null;

  /// Set when a 401 logged the user out, so the login screen can explain why.
  bool get sessionExpiredNotice => _sessionExpiredNotice;
  void clearSessionExpiredNotice() {
    if (!_sessionExpiredNotice) return;
    _sessionExpiredNotice = false;
    SharedPreferences.getInstance().then((p) => p.remove(_keySessionExpired));
    notifyListeners();
  }

  /// `host_userId` — keeps per-user settings apart across servers and accounts.
  String get _userScope => '${serverLabel(_apiBaseUrl)}_${_session.userId ?? ''}';
  String get _shellKey => 'shell_v1_$_userScope';
  String get _lastTabKey => 'last_tab_$_userScope';
  String? _lastTab;
  DateTime? _lastRefreshAt;

  /// Bottom tab open when the app was last used (per user/server).
  String? get lastTab => _lastTab;

  Future<void> setLastTab(String id) async {
    if (_lastTab == id) return;
    _lastTab = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTabKey, id);
  }

  /// Re-reads /api/me + menus when coming back to the app, at most every
  /// [minGap] — an admin's permission change then shows up without logout.
  Future<void> refreshSessionIfStale({Duration minGap = const Duration(minutes: 5)}) async {
    if (!_session.isLoggedIn || !_session.hasBusinessContext) return;
    final now = DateTime.now();
    if (!shouldRefreshSession(_lastRefreshAt, now, minGap)) return;
    _lastRefreshAt = now;
    try {
      await refreshServerInfo();
      await refreshSession();
    } catch (_) {}
  }
  String _lastPackageKey(String businessId) => 'last_package_${serverLabel(_apiBaseUrl)}_${_session.userId ?? ''}_$businessId';

  /// Bottom tabs for the current permissions (fixed "เมนู" tab not included).
  List<String> get shellTabs => resolveShellTabs(
        roles: _shell?.roles ?? const [],
        custom: _shell?.tabs,
        allowed: (keys) => MenuAccess.any(_session, keys),
      );

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
      packageCode: _session.packageCode,
    );
    return _api;
  }

  String get initialRouteName {
    if (!_ready) return 'splash';
    if (!_session.isLoggedIn) return 'login';
    if (!_session.hasBusinessContext) return 'hub';
    if (!hasPackage) return 'package';
    if (!roleSetupDone) return 'roleSetup';
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
    _recentServers = prefs.getStringList(_keyRecentServers) ?? const [];
    _recentAccounts = decodeRecentAccounts(prefs.getString(_keyRecentAccounts));
    _sessionExpiredNotice = prefs.getBool(_keySessionExpired) ?? false;
    _packageId = prefs.getString(_keyPackageId);
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
      packageCode: pkg,
    );
    // Existing installs were already on a server: don't make them pick again.
    _serverConfirmed = (prefs.getBool(_keyServerConfirmed) ?? false) || (token != null && token.isNotEmpty);
    await _loadUserScoped(prefs);
    await AppLock.instance.load(loggedIn: _session.isLoggedIn);
    _loadServerInfo(prefs);
    _ready = true;
    notifyListeners();
    refreshServerInfo().catchError((Object e) {
      debugPrint('server info: $e');
    });
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
    _sessionExpiredNotice = true;
    SharedPreferences.getInstance().then((p) => p.setBool(_keySessionExpired, true));
    logout();
  }

  Future<void> _loadUserScoped([SharedPreferences? p]) async {
    final prefs = p ?? await SharedPreferences.getInstance();
    final uid = _session.userId;
    if (uid == null || uid.isEmpty) {
      _shell = null;
      return;
    }
    _shell = ShellTabsConfig.decode(prefs.getString(_shellKey));
    _lastTab = prefs.getString(_lastTabKey);
    // Users who finished the old "getting started" keep a working default bar.
    if (_shell == null && _gettingStartedDone) {
      _shell = const ShellTabsConfig(roles: ['general']);
      await prefs.setString(_shellKey, _shell!.encode());
    }
  }

  /// Saves roles/tabs for this user on this server.
  Future<void> saveShellConfig(ShellTabsConfig config) async {
    _shell = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shellKey, config.encode());
    notifyListeners();
    // Same roles / tabs on the user's other devices (servers with feature `prefs_mobile`).
    if (_serverInfo?.has('prefs_mobile') ?? false) {
      apiClient.saveMobileShell(config.toJson()).catchError((Object e) {
        debugPrint('mobile_shell sync: $e');
      });
    }
  }

  /// Picks (and verifies) the NEXTX server. Switching servers signs out first.
  Future<void> selectServer(String url) async {
    final normalized = normalizeServerUrl(url);
    if (normalized.isEmpty) return;
    final changed = normalized != _apiBaseUrl;
    if (changed && _session.isLoggedIn) await logout();
    final prefs = await SharedPreferences.getInstance();
    _recentServers = pushRecentServer(_recentServers, normalized);
    await prefs.setStringList(_keyRecentServers, _recentServers);
    await prefs.setBool(_keyServerConfirmed, true);
    _serverConfirmed = true;
    await setApiBaseUrl(normalized);
    _loadServerInfo(prefs);
    refreshServerInfo(force: true).catchError((Object e) {
      debugPrint('server info: $e');
    });
  }

  /// Back to the server step (from the login screen).
  Future<void> resetServerChoice() async {
    _serverConfirmed = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyServerConfirmed, false);
    notifyListeners();
  }

  Future<void> forgetRecentServer(String url) async {
    _recentServers = _recentServers.where((e) => e != url).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyRecentServers, _recentServers);
    notifyListeners();
  }

  void _connectRealtime() {
    final token = _session.accessToken;
    if (token == null || token.isEmpty) return;
    RealtimeService.instance.connect(
      baseUrl: _apiBaseUrl,
      token: token,
      businessId: _session.businessId,
    );
    UnreadNotifications.instance.refresh(apiClient);
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
      packageCode: _session.packageCode,
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
    await _completeLogin(data, fallbackEmail: email);
  }

  /// Sends a one-time sign-in code to [email] (`/api/auth/otp/email/request`).
  Future<void> requestEmailOtp(String email) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    await _api.requestEmailOtp(email);
  }

  /// Signs in with the emailed code. Accounts that need linking confirm on the web.
  Future<void> loginWithEmailOtp({required String email, required String code}) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.verifyEmailOtp(email: email, code: code);
    _throwIfLinkNeeded(data);
    await _completeLogin(data, fallbackEmail: email);
  }

  /// Sends a sign-in code by SMS (`/api/auth/otp/sms/request`).
  Future<void> requestSmsOtp(String phone) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    await _api.requestSmsOtp(phone);
  }

  Future<void> loginWithSmsOtp({required String phone, required String code}) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.verifySmsOtp(phone: phone, code: code);
    _throwIfLinkNeeded(data);
    await _completeLogin(data, fallbackEmail: '');
  }

  void _throwIfLinkNeeded(Map<String, dynamic> data) {
    if (data['needLinkConfirm'] == true) {
      throw LinkConfirmRequired(data['intentToken']?.toString() ?? '', method: data['method']?.toString());
    }
  }

  /// Confirms linking a new sign-in method to an existing account.
  Future<void> confirmLink(String intentToken) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.linkConfirm(intentToken);
    await _completeLogin(data, fallbackEmail: '');
  }

  /// Google ID token (from native Google Sign-In) → NEXTX session.
  Future<void> loginWithGoogleIdToken(String idToken) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.googleOneTap(idToken);
    if (data['need_merge'] == true) {
      throw GoogleMergeRequired(data['merge_intent']?.toString() ?? '');
    }
    await _completeLogin(data, fallbackEmail: '');
  }

  Future<void> confirmGoogleMerge(String intentToken) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final data = await _api.googleMergeConfirm(intentToken);
    await _completeLogin(data, fallbackEmail: '');
  }

  /// JWT captured from the LINE login redirect (`/login?token=`).
  Future<void> loginWithToken(String token) async {
    _api.attachSession(baseUrl: _apiBaseUrl, accessToken: token);
    final me = await _api.getMe();
    await _completeLogin({
      'token': token,
      'user': me['user'],
      'business': me['business'],
    }, fallbackEmail: '');
  }

  /// Register; returns true when the account still needs admin approval.
  Future<bool> registerAccount({
    required String fullName,
    required String email,
    required String password,
    String? serialKey,
    String? businessName,
    String? inviteToken,
  }) async {
    _api.attachSession(baseUrl: _apiBaseUrl);
    final withKey = (serialKey != null && serialKey.trim().isNotEmpty) || (inviteToken ?? '').isNotEmpty;
    final data = await _api.register(
      fullName: fullName,
      email: email,
      password: password,
      signupType: withKey ? 'with_key' : 'without_key',
      serialKey: serialKey?.trim(),
      businessName: businessName,
      inviteToken: inviteToken,
    );
    if ((inviteToken ?? '').isNotEmpty) _pendingInvite = null;
    if (data['pending'] == true || data['token'] == null) return true;
    await _completeLogin(data, fallbackEmail: email);
    return false;
  }

  /// Stores the session returned by any NEXTX login endpoint (`{token, user, business}`).
  Future<void> _completeLogin(Map<String, dynamic> data, {required String fallbackEmail}) async {
    final email = fallbackEmail;
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
    final loginId = email.trim().isNotEmpty ? email.trim() : emailOut;
    if (loginId.isNotEmpty) {
      _recentAccounts = pushRecentAccount(
          _recentAccounts, RecentAccount(server: _apiBaseUrl, loginId: loginId, name: _displayFromUser(user, emailOut)));
      await prefs.setString(_keyRecentAccounts, encodeRecentAccounts(_recentAccounts));
    }
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
    // Package is chosen next (picker auto-selects the default / only one).
    await prefs.remove(_keyPackageCode);
    await prefs.remove(_keyPackageId);
    await prefs.remove(_keyMenuKeys);
    _packageId = null;
    _sessionExpiredNotice = false;
    await prefs.remove(_keySessionExpired);
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
    await _loadUserScoped(prefs);
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
      packageCode: _session.packageCode,
    );
    final me = await _api.getMe();
    final user = asStringKeyedMap(me['user']);
    final business = asStringKeyedMap(me['business']);
    final uid = user?['id']?.toString() ?? me['userId']?.toString() ?? _session.userId;
    final email = user?['email1']?.toString() ?? _session.email;
    final bid = business?['id']?.toString() ?? me['businessId']?.toString() ?? _session.businessId;
    final bname = business?['business_name']?.toString() ?? _session.businessName;
    List<String>? menus;
    final superadmin = me['is_superadmin'] == true ||
        user?['is_superadmin'] == true ||
        user?['is_superadmin'] == 1;
    // Package is picked explicitly (PackagePickerScreen); null = not chosen yet.
    final pkg = _session.packageCode;
    // Same as the web: menus = package ∩ role permissions (GET /api/me/menus?package=).
    if (pkg != null && pkg.isNotEmpty && bid != null) {
      try {
        menus = await _api.getMenuKeys(packageCode: pkg);
      } catch (_) {}
    }
    final allowed = me['allowed_menu_keys'];
    if (menus == null && allowed is List) {
      menus = allowed.map((e) => e.toString()).toList();
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
      businessRole: me['role']?.toString(),
    );
    // New device: take the roles / tabs saved on the account (feature `prefs_mobile`).
    final remote = ShellTabsConfig.fromServer(user?['mobile_shell']);
    if (_shell == null && remote != null) {
      _shell = remote;
      await prefs.setString(_shellKey, remote.encode());
    }
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
    // A different business means a different package list → pick again.
    _manualBusinessPick = false;
    await prefs.remove(_keyPackageId);
    if (packageCode != null) {
      await prefs.setString(_keyPackageCode, packageCode);
    } else {
      await prefs.remove(_keyPackageCode);
    }
    _packageId = null;
    _session = SessionState(
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: businessId,
      businessName: businessName,
      email: _session.email,
      displayName: _session.displayName,
      packageCode: packageCode,
      isSuperadmin: _session.isSuperadmin,
    );
    _api.attachSession(
      baseUrl: _apiBaseUrl,
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: businessId,
      packageCode: packageCode,
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

  /// Last package this user used in [businessId] on this server.
  Future<String?> lastPackageFor(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastPackageKey(businessId));
  }

  /// Enters [code] (empty = business without packages). Reloads menus for it.
  Future<void> selectPackage({required String code, String? packageId, bool setDefault = false}) async {
    final bid = _session.businessId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPackageCode, code);
    if (packageId != null) {
      await prefs.setString(_keyPackageId, packageId);
    } else {
      await prefs.remove(_keyPackageId);
    }
    if (bid != null && code.isNotEmpty) await prefs.setString(_lastPackageKey(bid), code);
    _packageId = packageId;
    _manualPackagePick = false;
    _session = _session.copyWith(packageCode: code, menusLoaded: false, clearMenus: true);
    notifyListeners();
    try {
      await refreshSession();
    } catch (_) {}
    if (setDefault && packageId != null && bid != null) {
      try {
        await apiClient.setDefaultPackage(packageId: packageId, businessId: bid);
      } catch (_) {}
    }
  }

  /// Back to the package picker for the current business (switch package).
  Future<void> clearPackage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPackageCode);
    await prefs.remove(_keyPackageId);
    _packageId = null;
    _manualPackagePick = true;
    _session = SessionState(
      accessToken: _session.accessToken,
      userId: _session.userId,
      businessId: _session.businessId,
      businessName: _session.businessName,
      email: _session.email,
      displayName: _session.displayName,
      isSuperadmin: _session.isSuperadmin,
      businessRole: _session.businessRole,
    );
    notifyListeners();
  }

  /// Back to the business list (switch business).
  Future<void> clearBusiness() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_keyBusinessId, _keyBusinessName, _keyPackageCode, _keyPackageId, _keyMenuKeys]) {
      await prefs.remove(k);
    }
    _packageId = null;
    _manualBusinessPick = true;
    _session = SessionState(
      accessToken: _session.accessToken,
      userId: _session.userId,
      email: _session.email,
      displayName: _session.displayName,
      isSuperadmin: _session.isSuperadmin,
    );
    notifyListeners();
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
    await prefs.remove(_keyPackageId);
    await prefs.remove(_keyMenuKeys);
    _packageId = null;
    _shell = null;
    _session = const SessionState();
    _api.attachSession(baseUrl: _apiBaseUrl);
    AppLock.instance.reset();
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

  /// Offline punches the server refused (too old, already punched…). Kept on the
  /// device and shown on the attendance screen so nothing disappears silently.
  List<Map<String, dynamic>> _failedPunches = const [];
  List<Map<String, dynamic>> get failedPunches => _failedPunches;

  Future<void> _loadFailedPunches() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_keyPunchFailed);
      final list = raw == null ? const [] : jsonDecode(raw);
      _failedPunches = list is List ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    } catch (_) {
      _failedPunches = const [];
    }
  }

  Future<void> _saveFailedPunches(List<Map<String, dynamic>> list) async {
    _failedPunches = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPunchFailed, jsonEncode(list));
    notifyListeners();
  }

  /// User read the problem (and told HR) — remove it from the list.
  Future<void> dismissFailedPunch(Map<String, dynamic> item) =>
      _saveFailedPunches(_failedPunches.where((e) => e['queued_at'] != item['queued_at']).toList());

  /// Punches waiting to be sent (oldest first).
  Future<List<Map<String, dynamic>>> pendingPunches() async =>
      (await _offlineQueue.load()).where((e) => e['type'] == 'punch').toList();

  /// Clock in/out. Without network, on a server with feature `offline_attendance`,
  /// the device time is saved and sent later — returns `true` when queued.
  Future<bool> punch({required bool clockIn, required double lat, required double lng, String? address}) async {
    try {
      if (clockIn) {
        await apiClient.clockIn(latitude: lat, longitude: lng, address: address);
      } else {
        await apiClient.clockOut(latitude: lat, longitude: lng, address: address);
      }
      return false;
    } on ApiException catch (e) {
      if (e.statusCode != 0 || !(_serverInfo?.has('offline_attendance') ?? false)) rethrow;
      await _offlineQueue.enqueue({
        'type': 'punch',
        'dir': clockIn ? 'in' : 'out',
        'at': DateTime.now().toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        'address': ?address,
        'user_id': _session.userId,
        'business_id': _session.businessId,
      });
      notifyListeners();
      return true;
    }
  }

  Future<void> flushOfflineQueue() async {
    if (_failedPunches.isEmpty) await _loadFailedPunches();
    final pending = await _offlineQueue.load();
    if (pending.isEmpty) return;
    final remain = <Map<String, dynamic>>[];
    final failed = [..._failedPunches];
    var offline = false;
    for (final item in pending) {
      // Keep order (clock-in before clock-out): once the network is down, keep the rest as is.
      if (offline) {
        remain.add(item);
        continue;
      }
      if (item['type'] == 'punch') {
        // Another account / business on this phone: keep it for its owner, never send it as someone else.
        if (item['user_id'] != _session.userId || item['business_id'] != _session.businessId) {
          remain.add(item);
          continue;
        }
        final at = DateTime.tryParse(item['at']?.toString() ?? '');
        final lat = (item['lat'] as num?)?.toDouble() ?? 0;
        final lng = (item['lng'] as num?)?.toDouble() ?? 0;
        try {
          if (at == null) throw ApiException(400, 'เวลาที่บันทึกไว้ไม่ถูกต้อง');
          if (item['dir'] == 'out') {
            await apiClient.clockOut(latitude: lat, longitude: lng, address: item['address']?.toString(), offlineAt: at);
          } else {
            await apiClient.clockIn(latitude: lat, longitude: lng, address: item['address']?.toString(), offlineAt: at);
          }
        } catch (e) {
          final status = e is ApiException ? e.statusCode : (e is ApiEnvelopeException ? e.statusCode : 0);
          if (status == 0 || status == 401) {
            // No network / signed out: keep it (and everything after it) for later.
            offline = true;
            remain.add(item);
          } else {
            // The server refused it (too old, already punched…): keep it visible, never drop it.
            failed.add({...item, 'error': formatApiError(e), 'failed_at': DateTime.now().toUtc().toIso8601String()});
          }
        }
        continue;
      }
      try {
        final type = item['type']?.toString();
        final id = item['id']?.toString() ?? '';
        final lat = (item['lat'] as num?)?.toDouble();
        final lng = (item['lng'] as num?)?.toDouble();
        if (type != 'checkin' || id.isEmpty) continue;
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;
        await apiClient.activityCheckin(id, lat: lat, lng: lng);
      } on ApiException catch (e) {
        // Network still down → retry later; a real server rejection is dropped.
        if (e.statusCode == 0) {
          remain.add(item);
        } else {
          debugPrint('[offline] check-in ${item['id']} rejected: ${e.userMessage}');
        }
      } catch (_) {
        remain.add(item);
      }
    }
    await _offlineQueue.save(remain);
    if (failed.length != _failedPunches.length) await _saveFailedPunches(failed);
    notifyListeners();
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

/// True when the last session refresh is older than [minGap] (or never ran).
bool shouldRefreshSession(DateTime? last, DateTime now, Duration minGap) =>
    last == null || now.difference(last) >= minGap;
