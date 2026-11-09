/// Display time is always Thailand (Asia/Bangkok, UTC+7, no daylight saving),
/// whatever timezone the phone is set to. Only display changes: values sent to
/// and stored by the server are untouched.
library;

const Duration thaiOffset = Duration(hours: 7);

/// [d] as Thailand wall-clock time (a plain DateTime holding Thai fields).
DateTime toThai(DateTime d) {
  final t = (d.isUtc ? d : d.toUtc()).add(thaiOffset);
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond, t.microsecond);
}

/// "Now" in Thailand — use for greetings, "today", clocks shown to the user.
DateTime thaiNow() => toThai(DateTime.now());

final RegExp _zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// Parses a server time for display. ISO strings with a zone (`…Z`, `+00:00`)
/// are converted to Thai time; zone-less strings (`2026-11-07 14:05:00`) are
/// already Thai wall time from NEXTX and are kept as they are.
DateTime? parseThai(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return toThai(raw);
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return _zoned.hasMatch(s) ? toThai(d) : d;
}

extension ThaiTimeX on DateTime {
  DateTime toThaiTime() => toThai(this);
}

/// Fields NEXTX saves as Bangkok **wall clock** in `timestamp without time
/// zone`. The API still adds a `Z` (node-pg OID 1114), but those digits are
/// already Thai time — adding +7 would be wrong. Same rule as the NEXTX web
/// (`activityDateTime.js`, `formatEntityTableCell.js`, `caseWallDateTime.js`).
bool isWallClockField(String? field, {String? module}) {
  final f = (field ?? '').toLowerCase();
  if (f.isEmpty) return false;
  if (f == 'date_start' || f == 'date_end' || f.endsWith('_datetime')) return true;
  // Activity visit stamps are written as Bangkok wall clock (same as the web visit panel).
  if (f == 'checkindate' || f == 'checkoutdate') return true;
  if (module == 'case' && const {'createdtime', 'modifiedtime', 'created_at', 'updated_at'}.contains(f)) return true;
  return false;
}

/// Wall-clock value: the digits as written, ignoring a fake `Z`/offset.
DateTime? parseWall(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day, raw.hour, raw.minute, raw.second);
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?').firstMatch(s);
  if (m == null) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
}

/// Display parse of a field value: wall-clock fields keep their digits,
/// everything else is a real instant shown in Thai time.
DateTime? parseThaiField(dynamic raw, String? field, {String? module}) =>
    isWallClockField(field, module: module) ? parseWall(raw) : parseThai(raw);

/// `11/11/2569 14:05` (BE in Thai) — or date only when the value has no time
/// / [dateOnly]. Returns the raw text when it is not a date.
String formatThaiField(dynamic raw, String? field, {String? module, bool dateOnly = false, int Function(int)? year}) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return '';
  final d = parseThaiField(s, field, module: module);
  if (d == null) return s;
  String two(int n) => n.toString().padLeft(2, '0');
  final y = year == null ? d.year : year(d.year);
  final date = '${two(d.day)}/${two(d.month)}/$y';
  final hasTime = s.length > 10 && !dateOnly;
  return hasTime ? '$date ${two(d.hour)}:${two(d.minute)}' : date;
}

/// Calendar date for display (`10/11/2569`). DATE columns come back either as
/// `2026-11-10` or — through node-pg in a Bangkok-TZ server — as the instant
/// `2026-11-09T17:00:00.000Z`; cutting at "T" would show the day before.
String thaiDate(dynamic raw, {int Function(int)? year}) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return '';
  final d = parseThaiDate(s);
  if (d == null) return s;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${year == null ? d.year : year(d.year)}';
}

/// A DATE column value as a Thai calendar day (see [thaiDate]).
DateTime? parseThaiDate(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final d = s.length <= 10 ? DateTime.tryParse(s) : parseThai(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}
