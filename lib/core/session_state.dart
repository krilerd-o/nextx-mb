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

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;
  bool get hasBusinessContext =>
      userId != null &&
      userId!.isNotEmpty &&
      businessId != null &&
      businessId!.isNotEmpty;

  bool canAccess(String menuKey) {
    if (isSuperadmin) return true;
    if (!menusLoaded) return false;
    final keys = menuKeys;
    if (keys == null || keys.isEmpty) return false;
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
    );
  }
}
