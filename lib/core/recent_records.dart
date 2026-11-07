import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the user opened lately (per server + user), newest first —
/// shown on Home as "เปิดล่าสุด".
class RecentRecords {
  RecentRecords._();
  static final RecentRecords instance = RecentRecords._();

  static const _max = 12;
  final ValueNotifier<List<Map<String, String>>> items = ValueNotifier(const []);
  String? _scope;

  String _key(String scope) => 'nx_recent_records_$scope';

  Future<void> load(String scope) async {
    if (_scope == scope && items.value.isNotEmpty) return;
    _scope = scope;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(scope));
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      items.value = [
        for (final e in list)
          if (e is Map) {for (final x in e.entries) '${x.key}': '${x.value}'},
      ];
    } catch (_) {
      items.value = const [];
    }
  }

  Future<void> add(String scope, {required String module, required String id, required String title}) async {
    if (id.isEmpty) return;
    if (_scope != scope) await load(scope);
    final next = [
      {'module': module, 'id': id, 'title': title, 'at': DateTime.now().toIso8601String()},
      ...items.value.where((e) => !(e['module'] == module && e['id'] == id)),
    ].take(_max).toList();
    items.value = next;
    try {
      await (await SharedPreferences.getInstance()).setString(_key(scope), jsonEncode(next));
    } catch (_) {}
  }

  Future<void> remove(String scope, String module, String id) async {
    items.value = items.value.where((e) => !(e['module'] == module && e['id'] == id)).toList();
    try {
      await (await SharedPreferences.getInstance()).setString(_key(scope), jsonEncode(items.value));
    } catch (_) {}
  }
}
