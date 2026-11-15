/// "ไอแซคช่วยกรอก": what `POST /api/ai/extract-fields` suggested for a
/// create form, already shaped for the app's forms (people and linked
/// records as `{id, label}`).
class AiFillResult {
  const AiFillResult({this.values = const {}, this.filled = const [], this.hints = const {}, this.missing = const [], this.duplicates = const []});

  /// Field name → form value.
  final Map<String, dynamic> values;

  /// Fields Isaac filled (for ✨ and the banner).
  final List<String> filled;

  /// Field name → what Isaac read but could not match (a person, a customer)
  /// with up to 5 candidates `{id, label}` to pick from.
  final Map<String, ({String text, List<Map<String, dynamic>> candidates})> hints;

  /// Required fields still empty `{field, label}`.
  final List<Map<String, dynamic>> missing;

  /// Same customer may already exist `{module, id, name, reason}`.
  final List<Map<String, dynamic>> duplicates;

  bool get isEmpty => values.isEmpty && hints.isEmpty;

  factory AiFillResult.fromJson(Map<String, dynamic> j) {
    final values = <String, dynamic>{};
    final filled = <String>[];
    final hints = <String, ({String text, List<Map<String, dynamic>> candidates})>{};
    final fields = j['fields'] is Map ? Map<String, dynamic>.from(j['fields'] as Map) : const <String, dynamic>{};
    fields.forEach((name, raw) {
      if (raw is! Map) return;
      final v = raw['value'];
      final label = raw['label'];
      if (v == null || '$v'.isEmpty) {
        final hint = '${raw['hint'] ?? ''}';
        if (hint.isNotEmpty) {
          hints[name] = (
            text: hint,
            candidates: [
              for (final c in (raw['candidates'] is List ? raw['candidates'] as List : const []))
                if (c is Map) Map<String, dynamic>.from(c),
            ],
          );
        }
        return;
      }
      values[name] = label != null && '$label'.isNotEmpty ? {'id': '$v', 'label': '$label'} : v;
      filled.add(name);
    });
    List<Map<String, dynamic>> maps(dynamic x) => [
      for (final e in (x is List ? x : const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    return AiFillResult(values: values, filled: filled, hints: hints, missing: maps(j['missing_required']), duplicates: maps(j['duplicates']));
  }
}

/// Asks Isaac to fill a form from [text].
typedef AiFillFn = Future<AiFillResult> Function(String text);

/// A form value as plain text for summaries (`{id, label}` → label).
String aiFillDisplay(dynamic v) {
  if (v is Map) return '${v['label'] ?? v['name'] ?? v['id'] ?? ''}';
  return v == null ? '' : '$v';
}
