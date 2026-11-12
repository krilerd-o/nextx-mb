import 'package:flutter/foundation.dart';

/// In-memory snapshot of auth/session for quick reads (persisted via AppConfig).
@immutable
class SessionState {
  const SessionState({
    this.accessToken,
    this.userId,
    this.businessId,
    this.businessName,
    this.email,
    this.displayName,
    this.packageCode,
    this.menuKeys,
    this.isSuperadmin = false,
    this.menusLoaded = false,
    this.businessRole,
  });

  final String? accessToken;
  final String? userId;
  final String? businessId;
  final String? businessName;
  final String? email;
  final String? displayName;
  final String? packageCode;
  final List<String>? menuKeys;
  final bool isSuperadmin;
  final bool menusLoaded;

  /// Role in the current business from `/api/me` (`owner` | `admin` | `member`).
  final String? businessRole;

  /// Owner/admin of the current business (or superadmin) — gates admin-only APIs
  /// such as store stock and mark-paid.
  bool get isBusinessAdmin =>
      isSuperadmin || businessRole == 'owner' || businessRole == 'admin';

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;
  bool get hasBusinessContext =>
      userId != null &&
      userId!.isNotEmpty &&
      businessId != null &&
      businessId!.isNotEmpty;

  /// Same rule as the NEXTX web: menus = Package ∩ role permissions. `null` (no Package picked /
  /// the business has no Package, and the role does not restrict menus) means unrestricted — the
  /// web shows every menu then. An empty list means nothing is allowed.
  bool canAccess(String menuKey) {
    if (isSuperadmin) return true;
    if (!menusLoaded) return false;
    final keys = menuKeys;
    if (keys == null) return true;
    if (keys.isEmpty) return false;
    return keys.contains(menuKey);
  }

  SessionState copyWith({
    String? accessToken,
    String? userId,
    String? businessId,
    String? businessName,
    String? email,
    String? displayName,
    String? packageCode,
    List<String>? menuKeys,
    bool? isSuperadmin,
    bool? menusLoaded,
    String? businessRole,
    bool clearToken = false,
    bool clearBusiness = false,
    bool clearMenus = false,
  }) {
    return SessionState(
      accessToken: clearToken ? null : (accessToken ?? this.accessToken),
      userId: userId ?? this.userId,
      businessId: clearBusiness ? null : (businessId ?? this.businessId),
      businessName: clearBusiness ? null : (businessName ?? this.businessName),
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      packageCode: packageCode ?? this.packageCode,
      menuKeys: clearMenus ? null : (menuKeys ?? this.menuKeys),
      isSuperadmin: isSuperadmin ?? this.isSuperadmin,
      menusLoaded: menusLoaded ?? this.menusLoaded,
      businessRole: clearBusiness ? null : (businessRole ?? this.businessRole),
    );
  }
}
