import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';

/// Calendar views, coarse → fine (the order drives the zoom direction).
enum CalView { year, month, week, threeDay, day, list }

extension CalViewX on CalView {
  String get label => switch (this) {
        CalView.year => 'ปี',
        CalView.month => 'เดือน',
        CalView.week => 'สัปดาห์',
        CalView.threeDay => '3 วัน',
        CalView.day => 'วัน',
        CalView.list => 'รายการ',
      };

  /// Days shown side by side in a time grid.
  int get gridDays => switch (this) {
        CalView.week => 7,
        CalView.threeDay => 3,
        _ => 1,
      };

  bool get isTimeGrid => this == CalView.week || this == CalView.threeDay || this == CalView.day;
}

const thMonths = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
const thMonthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const enMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Sunday-first, as Thai calendars (and the reference design) show weeks.
const thWeekShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
const enWeekShort = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const thWeekLong = ['วันอาทิตย์', 'วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์'];
const enWeekLong = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

String monthName(int m) => (L10n.isEn ? enMonths : thMonths)[m - 1];
String monthShort(int m) => (L10n.isEn ? enMonthsShort : thMonthsShort)[m - 1];

/// Weekday label for a date (Sunday-first tables).
String weekdayShort(DateTime d) => (L10n.isEn ? enWeekShort : thWeekShort)[d.weekday % 7];
String weekdayLong(DateTime d) => (L10n.isEn ? enWeekLong : thWeekLong)[d.weekday % 7];
List<String> get weekHeaders => L10n.isEn ? enWeekShort : thWeekShort;

DateTime calDay(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// First day (Sunday) of [d]'s week.
DateTime weekStart(DateTime d) => calDay(d).subtract(Duration(days: d.weekday % 7));


String calKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `2026-11-11 09:30:00` — Thailand wall time, the way the NEXTX web saves it.
String ymdhm(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:00';

/// Header label of the period on screen, in Thai (BE year) or English.
String periodLabel(CalView v, DateTime d) {
  final y = uiYear(d.year);
  switch (v) {
    case CalView.year:
      return '$y';
    case CalView.week:
    case CalView.threeDay:
      final s = v == CalView.week ? weekStart(d) : calDay(d);
      final e = s.add(Duration(days: v.gridDays - 1));
      if (s.month == e.month) return '${s.day}–${e.day} ${monthShort(s.month)} ${uiYear(s.year)}';
      return '${s.day} ${monthShort(s.month)} – ${e.day} ${monthShort(e.month)} ${uiYear(e.year)}';
    case CalView.day:
      return '${d.day} ${monthShort(d.month)} $y';
    case CalView.month:
    case CalView.list:
      return '${monthShort(d.month)} $y';
  }
}

/// "วันพุธที่ 11 พฤศจิกายน" / "Wednesday 11 November" (+ year when not this year).
String dayHeading(DateTime d) {
  final now = thaiNow();
  final year = d.year == now.year ? '' : ' ${uiYear(d.year)}';
  if (L10n.isEn) return '${weekdayLong(d)} ${d.day} ${monthName(d.month)}$year';
  return '${weekdayLong(d)}ที่ ${d.day} ${monthName(d.month)}$year';
}

/// One appointment on the calendar, times in Thailand wall clock.
class CalEvent {
  CalEvent._(this.raw, this.id, this.title, this.start, this.end, this.allDay);

  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  String get status => '${raw['status'] ?? ''}';
  String get type => '${raw['activitytype'] ?? ''}';
  String get location => '${raw['location'] ?? ''}';
  bool get checkedIn => '${raw['checkindate'] ?? ''}'.isNotEmpty;
  Color get color => calStatusColor(status);

  /// Spans more than one calendar day.
  bool get multiDay => !sameDay(start, end.subtract(const Duration(microseconds: 1)));

  /// Covers [day] (multi-day and all-day events show on every day they span).
  bool on(DateTime day) {
    final d0 = calDay(day);
    final d1 = d0.add(const Duration(days: 1));
    final e = end.isAfter(start) ? end : start.add(const Duration(minutes: 1));
    return start.isBefore(d1) && e.isAfter(d0);
  }

  /// Minutes long (at least 15 for drawing).
  int get minutes => end.difference(start).inMinutes.clamp(15, 24 * 60 * 31);

  CalEvent copyWith({DateTime? start, DateTime? end}) => CalEvent._(raw, id, title, start ?? this.start, end ?? this.end, allDay);

  static CalEvent? from(Map<String, dynamic> row) {
    // date_start/date_end: Bangkok wall clock with a fake Z (see isWallClockField).
    final s = parseWall(row['date_start']);
    if (s == null) return null;
    final allDay = row['all_day'] == true || '${row['all_day']}' == '1' || '${row['date_start']}'.trim().length <= 10;
    var e = row['date_end'] != null ? parseWall(row['date_end']) : parseThai(row['due_date']);
    if (e == null || !e.isAfter(s)) e = allDay ? calDay(s).add(const Duration(days: 1)) : s.add(const Duration(hours: 1));
    final title = '${row['subject'] ?? row['name'] ?? ''}'.trim();
    return CalEvent._(row, '${row['id'] ?? ''}', title.isEmpty ? tr('(ไม่มีชื่อ)') : title, s, e, allDay);
  }
}

Color calStatusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'held':
    case 'completed':
      return const Color(0xFF10B981);
    case 'planned':
    case 'not started':
      return const Color(0xFF0EA5E9);
    case 'in progress':
      return const Color(0xFF6366F1);
    case 'cancelled':
    case 'not held':
      return const Color(0xFFF97316);
    default:
      return const Color(0xFFEC4899);
  }
}

/// Lays overlapping timed events side by side: event → (column, columns).
Map<CalEvent, (int, int)> layoutOverlaps(List<CalEvent> events) {
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start) != 0 ? a.start.compareTo(b.start) : b.end.compareTo(a.end));
  final out = <CalEvent, (int, int)>{};
  var cluster = <CalEvent>[];
  var clusterEnd = DateTime(0);
  final colEnds = <DateTime>[];
  void flush() {
    final n = colEnds.length;
    for (final e in cluster) {
      out[e] = (out[e]!.$1, n);
    }
    cluster = [];
    colEnds.clear();
  }

  for (final e in sorted) {
    final end = e.start.add(Duration(minutes: e.minutes));
    if (cluster.isNotEmpty && !e.start.isBefore(clusterEnd)) flush();
    var col = colEnds.indexWhere((c) => !e.start.isBefore(c));
    if (col < 0) {
      col = colEnds.length;
      colEnds.add(end);
    } else {
      colEnds[col] = end;
    }
    out[e] = (col, 0);
    cluster.add(e);
    if (end.isAfter(clusterEnd)) clusterEnd = end;
  }
  if (cluster.isNotEmpty) flush();
  return out;
}

// ── kept for callers of the old screen ───────────────────────────────────

/// Local `yyyy-MM-dd` → activities starting that day (server sends UTC ISO).
Map<String, List<Map<String, dynamic>>> groupActivitiesByDay(List<Map<String, dynamic>> rows) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final raw = r['date_start']?.toString() ?? '';
    final d = DateTime.tryParse(raw);
    final key = d == null ? (raw.length >= 10 ? raw.substring(0, 10) : raw) : calKey(parseWall(raw) ?? d);
    if (key.isEmpty) continue;
    (out[key] ??= []).add(r);
  }
  return out;
}

/// "09:30–10:30" (Thai time) or the raw value when it cannot be parsed.
String activityTimeLabel(Map<String, dynamic> row) {
  String fmt(dynamic v, String field) {
    final raw = v?.toString() ?? '';
    if (raw.length <= 10) return '';
    final d = parseThaiField(raw, field);
    return d == null ? '' : hm(d);
  }

  final a = fmt(row['date_start'], 'date_start');
  final b = row['date_end'] != null ? fmt(row['date_end'], 'date_end') : fmt(row['due_date'], 'due_date');
  if (a.isEmpty) return row['date_start']?.toString() ?? '';
  return b.isEmpty ? a : '$a–$b';
}
