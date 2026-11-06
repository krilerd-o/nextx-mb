import 'dart:convert';

/// An account signed in on this device before (no password is ever kept).
class RecentAccount {
  const RecentAccount({required this.server, required this.loginId, this.name = ''});

  final String server;
  final String loginId;
  final String name;

  Map<String, dynamic> toJson() => {'server': server, 'id': loginId, 'name': name};

  static RecentAccount? fromJson(Object? j) {
    if (j is! Map) return null;
    final server = j['server']?.toString() ?? '';
    final id = j['id']?.toString() ?? '';
    if (server.isEmpty || id.isEmpty) return null;
    return RecentAccount(server: server, loginId: id, name: j['name']?.toString() ?? '');
  }
}

List<RecentAccount> decodeRecentAccounts(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [for (final e in j) ?RecentAccount.fromJson(e)];
  } catch (_) {
    return const [];
  }
}

String encodeRecentAccounts(List<RecentAccount> list) => jsonEncode([for (final a in list) a.toJson()]);

bool _same(RecentAccount a, String server, String id) =>
    a.server == server && a.loginId.toLowerCase() == id.toLowerCase();

/// Most-recent-first, one entry per server + login id, capped.
List<RecentAccount> pushRecentAccount(List<RecentAccount> list, RecentAccount a, {int max = 5}) {
  if (a.server.isEmpty || a.loginId.trim().isEmpty) return list;
  return [a, ...list.where((e) => !_same(e, a.server, a.loginId))].take(max).toList();
}

List<RecentAccount> removeRecentAccount(List<RecentAccount> list, RecentAccount a) =>
    list.where((e) => !_same(e, a.server, a.loginId)).toList();

List<RecentAccount> recentAccountsFor(List<RecentAccount> list, String server) =>
    list.where((e) => e.server == server).toList();
