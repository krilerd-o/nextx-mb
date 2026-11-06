import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'offline_checkin_queue_v1';

/// Field actions (activity check-in) saved while offline and replayed later.
class OfflineQueue {
  /// Number of items waiting, for the "pending sync" banner.
  static final ValueNotifier<int> pending = ValueNotifier<int>(0);

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      pending.value = 0;
      return [];
    }
    final decoded = jsonDecode(raw);
    final list = decoded is List
        ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    pending.value = list.length;
    return list;
  }

  Future<void> enqueue(Map<String, dynamic> item) async {
    final list = await load();
    list.add({...item, 'queued_at': DateTime.now().toIso8601String()});
    await save(list);
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
    pending.value = items.length;
  }
}
