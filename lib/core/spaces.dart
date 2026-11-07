import 'dart:convert';

import 'package:flutter/material.dart';

/// One signed-in MOAI NEXT account on one server ("Space", like a Slack
/// workspace). Several Spaces can live side by side — different domains, or
/// the same domain with another account — and the user switches between them.
///
/// Inside a Space the user still picks business / package as before.
@immutable
class Space {
  const Space({
    required this.id,
    required this.baseUrl,
    this.label,
    this.colorValue,
    this.userId,
    this.email,
    this.displayName,
    this.businessName,
    this.packageCode,
    this.bundle = const {},
    this.lastUsedAt,
  });

  final String id;
  final String baseUrl;

  /// User-chosen name; falls back to business name, then domain.
  final String? label;
  final int? colorValue;
  final String? userId;
  final String? email;
  final String? displayName;
  final String? businessName;
  final String? packageCode;

  /// Saved session preferences of this Space (restored when switching back).
  final Map<String, Object?> bundle;
  final DateTime? lastUsedAt;

  String get host {
    final u = Uri.tryParse(baseUrl);
    return (u == null || u.host.isEmpty) ? baseUrl : (u.hasPort ? '${u.host}:${u.port}' : u.host);
  }

  String get title {
    final l = label?.trim() ?? '';
    if (l.isNotEmpty) return l;
    final b = businessName?.trim() ?? '';
    return b.isNotEmpty ? b : host;
  }

  /// Initials for the avatar tile (first letters of the title).
  String get initials {
    final words = title.split(RegExp(r'[\s·\-_.]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final a = words.first.characters.first;
    final b = words.length > 1 ? words[1].characters.first : '';
    return (a + b).toUpperCase();
  }

  Color get color => Color(colorValue ?? spaceColorFor(baseUrl + (userId ?? '')));

  Space copyWith({
    String? baseUrl,
    String? label,
    bool clearLabel = false,
    int? colorValue,
    String? userId,
    String? email,
    String? displayName,
    String? businessName,
    String? packageCode,
    Map<String, Object?>? bundle,
    DateTime? lastUsedAt,
  }) =>
      Space(
        id: id,
        baseUrl: baseUrl ?? this.baseUrl,
        label: clearLabel ? null : (label ?? this.label),
        colorValue: colorValue ?? this.colorValue,
        userId: userId ?? this.userId,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        businessName: businessName ?? this.businessName,
        packageCode: packageCode ?? this.packageCode,
        bundle: bundle ?? this.bundle,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'baseUrl': baseUrl,
        if (label != null) 'label': label,
        if (colorValue != null) 'color': colorValue,
        if (userId != null) 'userId': userId,
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
        if (businessName != null) 'businessName': businessName,
        if (packageCode != null) 'packageCode': packageCode,
        'bundle': bundle,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  static Space? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final base = raw['baseUrl']?.toString() ?? '';
    if (id.isEmpty || base.isEmpty) return null;
    final b = raw['bundle'];
    return Space(
      id: id,
      baseUrl: base,
      label: raw['label']?.toString(),
      colorValue: (raw['color'] as num?)?.toInt(),
      userId: raw['userId']?.toString(),
      email: raw['email']?.toString(),
      displayName: raw['displayName']?.toString(),
      businessName: raw['businessName']?.toString(),
      packageCode: raw['packageCode']?.toString(),
      bundle: b is Map ? Map<String, Object?>.from(b) : const {},
      lastUsedAt: DateTime.tryParse(raw['lastUsedAt']?.toString() ?? ''),
    );
  }
}

/// Palette for Space tiles (stable per server + user).
const spacePalette = <int>[
  0xFF6366F1, 0xFF0EA5E9, 0xFF10B981, 0xFFF59E0B, 0xFFEC4899, 0xFF8B5CF6, 0xFF14B8A6, 0xFFEF4444,
];

int spaceColorFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return spacePalette[h % spacePalette.length];
}

String encodeSpaces(List<Space> list) => jsonEncode([for (final s in list) s.toJson()]);

List<Space> decodeSpaces(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [for (final e in j) ?Space.fromJson(e)];
  } catch (_) {
    return const [];
  }
}

/// New id for a Space (time-based, unique enough on one device).
String newSpaceId() => 'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Replaces (or appends) [s] in [list] by id.
List<Space> upsertSpace(List<Space> list, Space s) {
  final i = list.indexWhere((e) => e.id == s.id);
  if (i < 0) return [...list, s];
  return [...list]..[i] = s;
}

/// The same server + user already saved as a Space (re-login into it).
Space? findSpaceFor(List<Space> list, String baseUrl, String? userId) {
  String norm(String u) => u.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
  for (final s in list) {
    if (norm(s.baseUrl) == norm(baseUrl) && s.userId != null && s.userId == userId) return s;
  }
  return null;
}
