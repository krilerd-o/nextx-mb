import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Unsaved step-form work kept on the device, one per
/// business + module + record (`new`, `<id>`, `dup:<id>`, `rev:<id>`), so
/// leaving mid-way and coming back offers "ทำต่อจากร่าง" / "เริ่มใหม่".
/// Cleared after a successful save.
class DocFormDraftStore {
  DocFormDraftStore._();

  static const _prefix = 'nx.docform.draft.';

  static String key({required String? businessId, required String module, required String record}) =>
      '$_prefix${businessId ?? '-'}.$module.$record';

  static Future<DocFormDraft?> read(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return DocFormDraft.fromJson(Map<String, dynamic>.from(m));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, DocFormDraft draft) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(draft.toJson()));
    } catch (_) {
      // A draft that cannot be stored (odd value) is not worth an error.
    }
  }

  static Future<void> clear(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {}
  }
}

class DocFormDraft {
  DocFormDraft({required this.values, this.lines = const [], this.step = 0, this.extra = const {}, DateTime? savedAt})
      : savedAt = savedAt ?? DateTime.now();

  final Map<String, dynamic> values;
  final List<Map<String, dynamic>> lines;
  final int step;

  /// Screen-specific bits (revise reason, checklist, appointment …).
  final Map<String, dynamic> extra;
  final DateTime savedAt;

  static Object? _plain(Object? v) {
    if (v == null || v is num || v is String || v is bool) return v;
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) return {for (final e in v.entries) '${e.key}': _plain(e.value)};
    if (v is Iterable) return [for (final x in v) _plain(x)];
    return '$v';
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'values': _plain(values),
        'lines': _plain(lines),
        'step': step,
        'extra': _plain(extra),
        'saved_at': savedAt.toIso8601String(),
      };

  factory DocFormDraft.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    return DocFormDraft(
      values: map(j['values']),
      lines: [for (final l in (j['lines'] is List ? j['lines'] as List : const [])) if (l is Map) Map<String, dynamic>.from(l)],
      step: j['step'] is num ? (j['step'] as num).toInt() : 0,
      extra: map(j['extra']),
      savedAt: DateTime.tryParse('${j['saved_at'] ?? ''}'),
    );
  }
}
