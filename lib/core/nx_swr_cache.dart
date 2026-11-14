import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide stale-while-revalidate cache for screen data.
///
/// A screen that loads a list or a record keeps its last answer here under a
/// request key ([key]: method + path + sorted query); opening it again shows
/// that answer at once (no skeleton) while it refreshes in the background.
///
/// - In memory, least-recently-used, at most [capacity] answers.
/// - A few hot keys can also live on disk ([put] with `persist: true`, JSON
///   values only) so a cold start shows them too; they are read back by
///   [warm] when the Space opens.
/// - Every key is scoped to the server + user + Space ([scope]); changing the
///   scope (Space switch, sign-out) drops the memory cache, and sign-out also
///   removes the persisted answers of that account.
/// - A successful write (POST / PUT / PATCH / DELETE) drops the answers of the
///   same API area ([invalidateForWrite], called by the API client), so the
///   next open refetches what the write changed.
class NxSwrCache {
  NxSwrCache._();

  static final NxSwrCache instance = NxSwrCache._();

  static const capacity = 160;
  static const _diskPrefix = 'nx_swr|';
  static const _diskIndex = 'nx_swr_index';

  final LinkedHashMap<String, _Entry> _mem = LinkedHashMap();
  String _scope = '';

  /// Server + user + Space the cached answers belong to ('' = signed out).
  String get scope => _scope;
  set scope(String v) {
    if (v == _scope) return;
    final old = _scope;
    _scope = v;
    _mem.clear();
    _revision.value++;
    if (v.isEmpty && old.isNotEmpty) {
      _dropDisk(old);
    } else if (v.isNotEmpty) {
      warm();
    }
  }

  final ValueNotifier<int> _revision = ValueNotifier(0);

  /// Bumped whenever answers are dropped (scope change, writes, clear).
  ValueListenable<int> get revision => _revision;

  /// Request key: `GET /api/leave/requests?all=1&status=pending`.
  static String key(String path, {String method = 'GET', Map<String, Object?>? query}) {
    final q = query == null
        ? ''
        : (query.entries.where((e) => e.value != null && '${e.value}'.isNotEmpty).toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}=${e.value}')
            .join('&');
    return '${method.toUpperCase()} $path${q.isEmpty ? '' : '?$q'}';
  }

  String _full(String key) => '$_scope|$key';

  /// The last answer for [key], or null. Counts as a use (LRU).
  T? peek<T>(String key) {
    final k = _full(key);
    final e = _mem.remove(k);
    if (e == null) return null;
    _mem[k] = e;
    final v = e.value;
    return v is T ? v : null;
  }

  bool has(String key) => _mem.containsKey(_full(key));

  /// When [key] was stored (null when absent).
  DateTime? storedAt(String key) => _mem[_full(key)]?.at;

  /// Keep [value] as the latest answer for [key]. [persist]: also on disk
  /// (JSON-encodable values only; for a few hot lists).
  void put<T>(String key, T value, {bool persist = false}) {
    if (_scope.isEmpty) return;
    final k = _full(key);
    _mem.remove(k);
    _mem[k] = _Entry(value, DateTime.now(), persist);
    while (_mem.length > capacity) {
      _mem.remove(_mem.keys.first);
    }
    if (persist) _writeDisk(k, value);
  }

  /// Run [load] and keep its answer under [key].
  Future<T> fetch<T>(String key, Future<T> Function() load, {bool persist = false}) async {
    final v = await load();
    put<T>(key, v, persist: persist);
    return v;
  }

  void invalidate(String key) {
    final k = _full(key);
    final e = _mem.remove(k);
    if (e != null) {
      if (e.persist) _removeDisk([k]);
      _revision.value++;
    }
  }

  /// Drop every key whose request path starts with [pathPrefix] (any method / query).
  void invalidatePath(String pathPrefix) {
    final head = '$_scope|';
    final gone = <String>[];
    for (final k in _mem.keys) {
      if (!k.startsWith(head)) continue;
      final rest = k.substring(head.length);
      final sp = rest.indexOf(' ');
      final path = sp < 0 ? rest : rest.substring(sp + 1);
      if (path.startsWith(pathPrefix)) gone.add(k);
    }
    if (gone.isEmpty) return;
    final disk = [for (final k in gone) if (_mem[k]!.persist) k];
    for (final k in gone) {
      _mem.remove(k);
    }
    if (disk.isNotEmpty) _removeDisk(disk);
    _revision.value++;
  }

  /// A write to [path] succeeded: drop the answers of its API area
  /// (`/api/leave/...` → everything under `/api/leave`).
  void invalidateForWrite(String path) {
    final area = writeArea(path);
    if (area != null) invalidatePath(area);
  }

  /// `/api/leave/requests/9/cancel` → `/api/leave`; null for paths outside `/api/`.
  @visibleForTesting
  static String? writeArea(String path) {
    final p = path.split('?').first;
    final parts = p.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2 || parts.first != 'api') return null;
    // Auth / device / presence pings change no screen data.
    if (const {'auth', 'devices', 'presence', 'telemetry', 'client-errors'}.contains(parts[1])) return null;
    return '/api/${parts[1]}';
  }

  void clear() {
    _mem.clear();
    _revision.value++;
  }

  int get length => _mem.length;

  // ── disk ──

  Future<void> warm() async {
    final scope = _scope;
    if (scope.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final index = p.getStringList(_diskIndex) ?? const [];
      for (final k in index) {
        if (!k.startsWith('$scope|') || _mem.containsKey(k)) continue;
        final raw = p.getString('$_diskPrefix$k');
        if (raw == null) continue;
        if (_scope != scope) return;
        _mem[k] = _Entry(jsonDecode(raw), DateTime.fromMillisecondsSinceEpoch(0), true);
      }
    } catch (_) {}
  }

  Future<void> _writeDisk(String k, Object? value) async {
    final String raw;
    try {
      raw = jsonEncode(value);
    } catch (_) {
      return;
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_diskPrefix$k', raw);
      final index = p.getStringList(_diskIndex) ?? <String>[];
      if (!index.contains(k)) await p.setStringList(_diskIndex, [...index, k]);
    } catch (_) {}
  }

  Future<void> _removeDisk(List<String> keys) async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in keys) {
        await p.remove('$_diskPrefix$k');
      }
      final index = p.getStringList(_diskIndex) ?? <String>[];
      await p.setStringList(_diskIndex, [for (final k in index) if (!keys.contains(k)) k]);
    } catch (_) {}
  }

  Future<void> _dropDisk(String scope) async {
    try {
      final p = await SharedPreferences.getInstance();
      final index = p.getStringList(_diskIndex) ?? const <String>[];
      await _removeDisk([for (final k in index) if (k.startsWith('$scope|')) k]);
    } catch (_) {}
  }

  /// Forget the memory cache and the scope (a new app state starts empty).
  void reset() {
    _mem.clear();
    _scope = '';
  }
}

class _Entry {
  _Entry(this.value, this.at, this.persist);
  final Object? value;
  final DateTime at;
  final bool persist;
}
