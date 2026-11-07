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
