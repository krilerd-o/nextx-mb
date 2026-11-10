import 'package:flutter/material.dart' show DateTimeRange;

import 'thai_time.dart';

/// Kind of leave, guessed from the leave type's name / code (each business names its own types).
enum LeaveKind { sick, personal, vacation, maternity, ordination, military, other }

LeaveKind leaveKindOf(Map<String, dynamic>? type) {
  final s = '${type?['name'] ?? type?['leave_type_name'] ?? ''} ${type?['code'] ?? type?['leave_type_code'] ?? ''}'.toLowerCase();
  if (s.contains('ป่วย') || s.contains('sick')) return LeaveKind.sick;
  if (s.contains('คลอด') || s.contains('matern')) return LeaveKind.maternity;
  if (s.contains('บวช') || s.contains('ordin')) return LeaveKind.ordination;
  if (s.contains('ทหาร') || s.contains('militar')) return LeaveKind.military;
  if (s.contains('พักร้อน') || s.contains('พักผ่อน') || s.contains('vacation') || s.contains('annual')) return LeaveKind.vacation;
  if (s.contains('กิจ') || s.contains('personal') || s.contains('business')) return LeaveKind.personal;
  return LeaveKind.other;
}

/// Ready-made reasons per kind (tap to fill).
List<String> leaveReasonSuggestions(LeaveKind kind) {
  switch (kind) {
    case LeaveKind.sick:
      return const ['ไม่สบาย มีไข้', 'ไปพบแพทย์', 'พักฟื้นตามคำแนะนำแพทย์'];
    case LeaveKind.personal:
      return const ['ติดธุระส่วนตัว', 'ติดต่อราชการ', 'ธุระครอบครัว'];
    case LeaveKind.vacation:
      return const ['พักผ่อนประจำปี', 'ท่องเที่ยวกับครอบครัว', 'กลับบ้านต่างจังหวัด'];
    case LeaveKind.maternity:
      return const ['ลาคลอดบุตร'];
    case LeaveKind.ordination:
      return const ['ลาอุปสมบท'];
    case LeaveKind.military:
      return const ['เข้ารับการตรวจเลือกทหาร', 'ฝึกวิชาทหาร'];
    case LeaveKind.other:
      return const ['ติดธุระส่วนตัว'];
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
bool _weekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

/// Next Mon–Fri on or after [d].
DateTime nextWorkday(DateTime d) {
  var x = _day(d);
  while (_weekend(x)) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

/// Days the request counts (same as the server: every calendar day, both ends included).
int leaveDays(DateTimeRange r) => _day(r.end).difference(_day(r.start)).inDays + 1;

/// Suggested first range: sick leave = today, other kinds = the next working day.
DateTimeRange defaultLeaveRange(LeaveKind kind, {DateTime? now}) {
  final today = _day(now ?? thaiNow());
  if (kind == LeaveKind.sick) return DateTimeRange(start: today, end: today);
  final d = nextWorkday(today.add(const Duration(days: 1)));
  return DateTimeRange(start: d, end: d);
}

class LeaveDatePreset {
  const LeaveDatePreset(this.id, this.label, this.range);
  final String id;
  final String label;
  final DateTimeRange range;
}

/// Quick picks for the date row.
List<LeaveDatePreset> leaveDatePresets({DateTime? now}) {
  final today = _day(now ?? thaiNow());
  final tomorrow = today.add(const Duration(days: 1));
  final out = <LeaveDatePreset>[
    LeaveDatePreset('today', 'วันนี้', DateTimeRange(start: today, end: today)),
    LeaveDatePreset('tomorrow', 'พรุ่งนี้', DateTimeRange(start: tomorrow, end: tomorrow)),
  ];
  if (today.weekday < DateTime.friday) {
    final fri = today.add(Duration(days: DateTime.friday - today.weekday));
    out.add(LeaveDatePreset('to_friday', 'ถึงศุกร์นี้', DateTimeRange(start: today, end: fri)));
  }
  final nextMon = today.add(Duration(days: 8 - today.weekday));
  out.add(LeaveDatePreset('next_week', 'สัปดาห์หน้า (จ–ศ)', DateTimeRange(start: nextMon, end: nextMon.add(const Duration(days: 4)))));
  return out;
}

num _num(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

/// Days left per leave type id, from GET /hr/leave-balance.
Map<int, num> leaveRemainingByType(List<Map<String, dynamic>> balance) {
  final out = <int, num>{};
  for (final b in balance) {
    final id = int.tryParse(b['leave_type_id']?.toString() ?? '');
    if (id == null) continue;
    out[id] = _num(b['total_days']) - _num(b['used_days']);
  }
  return out;
}

/// Recommended type: the one used last (if days remain), else the first type with days left,
/// else the first type.
int? suggestLeaveTypeId(
  List<Map<String, dynamic>> types,
  Map<int, num> remaining,
  List<Map<String, dynamic>> myRequests,
) {
  final ids = [for (final t in types) ?int.tryParse(t['id']?.toString() ?? '')];
  if (ids.isEmpty) return null;
  bool hasDays(int id) => !remaining.containsKey(id) || remaining[id]! > 0;
  final recent = [...myRequests]
    ..removeWhere((r) => r['status']?.toString() == 'Cancelled')
    ..sort((a, b) => '${b['created_at'] ?? b['start_date'] ?? ''}'.compareTo('${a['created_at'] ?? a['start_date'] ?? ''}'));
  for (final r in recent) {
    final id = int.tryParse(r['leave_type_id']?.toString() ?? '');
    if (id != null && ids.contains(id) && hasDays(id)) return id;
  }
  for (final id in ids) {
    if (hasDays(id)) return id;
  }
  return ids.first;
}

/// My Pending / Approved request that overlaps [r] (to warn before sending a duplicate).
Map<String, dynamic>? overlappingLeave(DateTimeRange r, List<Map<String, dynamic>> myRequests) {
  final s = _day(r.start), e = _day(r.end);
  for (final q in myRequests) {
    final st = q['status']?.toString();
    if (st != 'Pending' && st != 'Approved') continue;
    final qs = parseThaiDate(q['start_date']);
    final qe = parseThaiDate(q['end_date']) ?? qs;
    if (qs == null || qe == null) continue;
    if (!_day(qe).isBefore(s) && !_day(qs).isAfter(e)) return q;
  }
  return null;
}

/// Sick leave of 3 days or more usually needs a medical certificate (Thai labour law).
bool leaveNeedsCertificateHint(LeaveKind kind, int days) => kind == LeaveKind.sick && days >= 3;
