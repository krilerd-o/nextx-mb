import 'package:flutter/material.dart';

import '../widgets/nx_icons.dart';
import 'i18n.dart';
import 'thai_time.dart';

/// Board status column (`/api/boards/:id/statuses`).
class WsStatus {
  WsStatus(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get name => '${raw['name'] ?? ''}';
  String get label => '${(L10n.isEn ? raw['label_en'] : raw['label_th']) ?? raw['label_th'] ?? raw['name'] ?? ''}';
  int get sequence => int.tryParse('${raw['sequence'] ?? 0}') ?? 0;
  bool get isInitial => '${raw['is_initial']}' == '1' || raw['is_initial'] == true;
  bool get isDone => '${raw['is_done']}' == '1' || raw['is_done'] == true;

  Color get color {
    final hex = '${raw['color'] ?? ''}'.replaceAll('#', '');
    final v = int.tryParse(hex, radix: 16);
    if (hex.length == 6 && v != null) return Color(0xFF000000 | v);
    if (isDone) return const Color(0xFF10B981);
    if (isInitial) return const Color(0xFF64748B);
    return const Color(0xFF6366F1);
  }

  static List<WsStatus> list(List<Map<String, dynamic>> rows) =>
      [for (final r in rows) WsStatus(r)]..sort((a, b) => a.sequence.compareTo(b.sequence));
}

/// Item types on NEXTX boards.
const kWsTypes = ['epic', 'task', 'bug', 'story', 'subtask', 'checklist'];

/// Label (Thai; translated by tr()), icon and colour of an item type.
({String label, IconData icon, Color color}) wsTypeStyle(String type) => switch (type) {
      'epic' => (label: 'Epic', icon: NxI.lightning, color: const Color(0xFF8B5CF6)),
      'bug' => (label: 'บั๊ก', icon: NxI.bug, color: const Color(0xFFEF4444)),
      'story' => (label: 'Story', icon: NxI.bookmark, color: const Color(0xFF10B981)),
      'subtask' => (label: 'งานย่อย', icon: NxI.subtask, color: const Color(0xFF0EA5E9)),
      'checklist' => (label: 'เช็คลิสต์', icon: NxI.listChecks, color: const Color(0xFF14B8A6)),
      _ => (label: 'งาน', icon: NxI.checkSquare, color: const Color(0xFF3B82F6)),
    };

const kWsPriorities = ['highest', 'high', 'medium', 'low', 'lowest'];

({String label, IconData icon, Color color}) wsPriorityStyle(String? p) => switch (p) {
      'highest' => (label: 'สูงสุด', icon: NxI.chevronsUp, color: const Color(0xFFDC2626)),
      'high' => (label: 'สูง', icon: NxI.caretUp, color: const Color(0xFFF97316)),
      'low' => (label: 'ต่ำ', icon: NxI.caretDown, color: const Color(0xFF0EA5E9)),
      'lowest' => (label: 'ต่ำสุด', icon: NxI.chevronsDown, color: const Color(0xFF64748B)),
      _ => (label: 'ปานกลาง', icon: NxI.equals, color: const Color(0xFFF59E0B)),
    };

/// Kind used by the API paths: `epic` or `task` (everything else).
String wsKind(Map<String, dynamic> item) => item['_kind'] == 'epic' || item['type'] == 'epic' ? 'epic' : 'task';

/// Type of an item row (epics have no `type` column).
String wsType(Map<String, dynamic> item) => item['_kind'] == 'epic' ? 'epic' : '${item['type'] ?? 'task'}';

/// `CODE-12` — board code + item number.
String wsKey(Map<String, dynamic> item, {String? boardCode}) {
  final code = '${item['board_code'] ?? boardCode ?? ''}';
  final no = '${item['item_no'] ?? ''}';
  if (code.isEmpty || no.isEmpty) return no.isEmpty ? '#${item['id']}' : '#$no';
  return '$code-$no';
}

/// Title without the board automation prefix (`[CODE]: `).
String wsTitle(Map<String, dynamic> item) {
  final t = '${item['title'] ?? ''}';
  return t.replaceFirst(RegExp(r'^\[[A-Z0-9_-]+\]:\s*'), '');
}

int? wsInt(dynamic v) => v == null ? null : int.tryParse('$v'.split('.').first);

/// Parses "1h 30m", "90m", "1.5h", "2d", "1ชม 30น", "45" (minutes).
/// A working day is 8 hours, like the NEXTX web. Returns null if invalid.
int? parseDuration(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(',', '.');
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  final re = RegExp(r'(\d+(?:\.\d+)?)\s*(days|day|d|วัน|hours|hour|hrs|hr|h|ชั่วโมง|ชม\.?|minutes|minute|mins|min|m|นาที|น\.?)');
  var total = 0.0;
  var matched = false;
  for (final m in re.allMatches(s)) {
    matched = true;
    final n = double.parse(m.group(1)!);
    final u = m.group(2)!;
    if (u.startsWith('d') || u == 'วัน') {
      total += n * 8 * 60;
    } else if (u.startsWith('h') || u.startsWith('ชม') || u == 'ชั่วโมง') {
      total += n * 60;
    } else {
      total += n;
    }
  }
  if (!matched) return null;
  final leftover = s.replaceAll(re, '').trim();
  if (leftover.isNotEmpty) return null;
  final v = total.round();
  return v > 0 ? v : null;
}

/// 90 → "1h 30m" (English units like the web), 0/null → "0m".
String formatMinutes(int? minutes) {
  final m = minutes ?? 0;
  if (m <= 0) return '0m';
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '${r}m';
  if (r == 0) return '${h}h';
  return '${h}h ${r}m';
}

/// Short date in Thai time (BE in Thai), e.g. `9 พ.ย.` / `9 Nov`.
String wsShortDate(dynamic raw) {
  final d = parseThai(raw);
  if (d == null) return '';
  const th = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  return '${d.day} ${tr(th[d.month - 1])}';
}

/// Full date-time in Thai time: `9/11/2569 14:05`.
String wsDateTime(dynamic raw) {
  final d = parseThai(raw);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${uiYear(d.year)} ${two(d.hour)}:${two(d.minute)}';
}

/// Days until due (negative = overdue), null when no due date.
int? wsDueIn(dynamic due) {
  final d = parseThai(due);
  if (d == null) return null;
  final now = thaiNow();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// Field names in the change history, same labels as the web.
const Map<String, (String, String)> kWsFieldLabels = {
  'title': ('หัวข้อ', 'Title'),
  'description': ('คำอธิบาย', 'Description'),
  'status_id': ('สถานะ', 'Status'),
  'assignee_id': ('ผู้รับผิดชอบ', 'Assignee'),
  'reporter_id': ('ผู้รายงาน', 'Reporter'),
  'release_id': ('Release', 'Release'),
  'start_date': ('วันเริ่ม', 'Start date'),
  'end_date': ('วันสิ้นสุด', 'End date'),
  'due_date': ('ครบกำหนด', 'Due date'),
  'priority': ('ความสำคัญ', 'Priority'),
  'story_points': ('Story points', 'Story points'),
  'type': ('ประเภท', 'Type'),
  'epic_id': ('Epic', 'Epic'),
  'parent_id': ('งานแม่', 'Parent'),
  'labels': ('ป้ายกำกับ', 'Labels'),
  'original_estimate_minutes': ('เวลาประมาณ', 'Original estimate'),
  'original_estimate': ('เวลาประมาณ', 'Original estimate'),
  'time_remaining_minutes': ('เวลาคงเหลือ', 'Remaining'),
  'time_spent_minutes': ('เวลาที่ใช้', 'Time spent'),
  'blocked_by_id': ('ถูกบล็อกโดย', 'Blocked by'),
  'recurrence_type': ('การทำซ้ำ', 'Recurrence'),
  'sprint_id': ('Sprint', 'Sprint'),
  'milestone_id': ('Milestone', 'Milestone'),
  'attachments': ('ไฟล์แนบ', 'Attachments'),
};

String wsFieldLabel(String field) {
  final l = kWsFieldLabels[field];
  if (l == null) return field;
  return L10n.isEn ? l.$2 : l.$1;
}
