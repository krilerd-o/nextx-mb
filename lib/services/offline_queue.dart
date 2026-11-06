import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _key = 'offline_checkin_queue_v1';

class OfflineQueue {
  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  Future<void> enqueue(Map<String, dynamic> item) async {
    final list = await load();
    list.add(item);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }
}
