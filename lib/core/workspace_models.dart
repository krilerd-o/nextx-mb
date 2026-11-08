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

  /// Closed without finishing (ยกเลิก / cancelled / closed lost).
  bool get isCancelled {
    final n = name.toLowerCase();
    final l = '${raw['label_th'] ?? ''} ${raw['label_en'] ?? ''}'.toLowerCase();
    return !isDone &&
        (n.startsWith('cancel') || n.contains('closed_lost') || n.contains('closed lost') || n == 'lost' || l.contains('ยกเลิก') || l.contains('cancel'));
  }

  /// End states get the big buttons at the bottom of the "ย้ายไปที่" panel.
  bool get isTerminal => isDone || isCancelled;

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
      'checklist' => (label: 'รายการเช็ค', icon: NxI.listChecks, color: const Color(0xFF14B8A6)),
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

/// Quick add, same defaults as the web (`workspaceQuickAddBody` + quick create):
/// assignee / reporter = me, start / end / due = today (Thai), medium priority.
Map<String, dynamic> wsQuickAddBody({required String title, required String statusId, String? me, String type = 'task', DateTime? now}) {
  final t = now ?? DateTime.now().toUtc().add(const Duration(hours: 7));
  final today = '${t.year}-${'${t.month}'.padLeft(2, '0')}-${'${t.day}'.padLeft(2, '0')}';
  final uid = me == null ? null : int.tryParse(me);
  return {
    'title': title.trim(),
    'type': type,
    'status_id': int.tryParse(statusId) ?? statusId,
    'priority': 'medium',
    'start_date': today,
    'end_date': today,
    'due_date': today,
    if (uid != null) 'assignee_id': uid,
    if (uid != null) 'reporter_id': uid,
  };
}

/// Board names seen so far by code (boards list / board page), so item keys
/// can use the short name of a deal board instead of its deal number.
final Map<String, String> wsBoardNames = {};

void wsRememberBoard(Map<String, dynamic> board) {
  final code = '${board['code'] ?? ''}'.trim();
  final name = '${board['name'] ?? ''}'.trim();
  if (code.isNotEmpty && name.isNotEmpty) wsBoardNames[code] = name;
}

/// Short code shown to people: deal boards get an automatic code from the
/// deal number (`D26110500003`); when the board is named like a code
/// (`KFDN`) that name is shown instead. Links keep the real code ([wsLinkKey]).
String wsDisplayCode(String code, {String? name}) {
  if (!RegExp(r'^D\d{8,}$').hasMatch(code)) return code;
  final n = (name ?? wsBoardNames[code] ?? '').trim().toUpperCase();
  return RegExp(r'^[A-Z][A-Z0-9]{1,11}$').hasMatch(n) ? n : code;
}

/// `KFDN-12` — short board code + item number (what people read).
String wsKey(Map<String, dynamic> item, {String? boardCode}) {
  final code = '${item['board_code'] ?? boardCode ?? ''}';
  final no = '${item['item_no'] ?? ''}';
  if (code.isEmpty || no.isEmpty) return no.isEmpty ? '#${item['id']}' : '#$no';
  return '${wsDisplayCode(code, name: item['board_name']?.toString())}-$no';
}

/// `CODE-12` with the board's real code — for web links and copying.
String wsLinkKey(Map<String, dynamic> item, {String? boardCode}) {
  final code = '${item['board_code'] ?? boardCode ?? ''}';
  final no = '${item['item_no'] ?? ''}';
  if (code.isEmpty || no.isEmpty) return no.isEmpty ? '#${item['id']}' : '#$no';
  return '$code-$no';
}

/// Share text like the web: key, full title, link.
String wsShareText(Map<String, dynamic> item, String webUrl, {String? boardCode}) =>
    '${wsLinkKey(item, boardCode: boardCode)}\n${'${item['title'] ?? ''}'.trim()}\n$webUrl';

/// Title without the board automation prefix (`[CODE]: `).
String wsTitle(Map<String, dynamic> item) {
  final t = '${item['title'] ?? ''}';
  return t.replaceFirst(RegExp(r'^\[[A-Z0-9_-]+\]:\s*'), '');
}

int? wsInt(dynamic v) => v == null ? null : int.tryParse('$v'.split('.').first);

/// Parses "1h 30m", "90m", "1.5h", "2d", "1w", "1ชม 30น", "45" (minutes).
/// Same units as NEXTX `parseTimeToMinutes`: 1d = 24h, 1w = 7d. Null if invalid.
int? parseDuration(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(',', '.');
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  final re = RegExp(r'(\d+(?:\.\d+)?)\s*(weeks|week|w|สัปดาห์|days|day|d|วัน|hours|hour|hrs|hr|h|ชั่วโมง|ชม\.?|minutes|minute|mins|min|m|นาที|น\.?)');
  var total = 0.0;
  var matched = false;
  for (final m in re.allMatches(s)) {
    matched = true;
    final n = double.parse(m.group(1)!);
    final u = m.group(2)!;
    if (u.startsWith('w') || u == 'สัปดาห์') {
      total += n * 7 * 24 * 60;
    } else if (u.startsWith('d') || u == 'วัน') {
      total += n * 24 * 60;
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

/// 90 → "1h 30m", 1500 → "1d 1h" (w/d/h/m like the NEXTX web), 0/null → "0m".
String formatMinutes(int? minutes) {
  var rest = minutes ?? 0;
  if (rest <= 0) return '0m';
  const units = [('w', 7 * 24 * 60), ('d', 24 * 60), ('h', 60), ('m', 1)];
  final parts = <String>[];
  for (final (u, mul) in units) {
    final v = rest ~/ mul;
    if (v > 0) {
      parts.add('$v$u');
      rest -= v * mul;
    }
  }
  return parts.join(' ');
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
