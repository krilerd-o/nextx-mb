import 'thai_time.dart';

/// Chat display rules shared by the room list and the room (same as the NEXTX web:
/// `components/chat/ChatMessageExtras.jsx`).

Map<String, dynamic>? _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// DM rooms are stored as "แชทกับ X" from the creator's side — show the other person instead.
String chatRoomTitle(Map<String, dynamic> room) {
  final display = room['display_name']?.toString().trim() ?? '';
  final peer = _map(room['peer']);
  final peerName = peer?['name']?.toString().trim() ?? '';
  if (room['room_type']?.toString() == 'dm') {
    if (display.isNotEmpty) return display;
    if (peerName.isNotEmpty) return peerName;
  }
  final name = room['name']?.toString().trim() ?? '';
  return name.isEmpty ? 'ห้องแชท' : name;
}

bool chatRoomIsDm(Map<String, dynamic> room) => room['room_type']?.toString() == 'dm';

/// 'image' | 'video' | 'audio' | 'file'
String chatAttachmentKind(String? mime, [String? name]) {
  final m = (mime ?? '').toLowerCase();
  final ext = (name ?? '').split('.').last.toLowerCase();
  if (m.startsWith('image/') || const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) return 'image';
  if (m.startsWith('video/') || const ['mp4', 'mov', 'm4v', '3gp'].contains(ext)) return 'video';
  if (m.startsWith('audio/') || const ['m4a', 'aac', 'mp3', 'wav', 'ogg', 'opus'].contains(ext)) return 'audio';
  return 'file';
}

const _kindLabel = {
  'image': '📷 รูปภาพ',
  'video': '🎬 วิดีโอ',
  'audio': '🎤 ข้อความเสียง',
  'file': '📎 ไฟล์',
};

String chatKindLabel(String kind) => _kindLabel[kind] ?? _kindLabel['file']!;

/// Text without HTML tags and with `@[12:Name]` mentions shown as `@Name`.
String chatPlainText(String? body) {
  var s = body ?? '';
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAllMapped(RegExp(r'@\[(\d+):((?:[^\[\]]|\[[^\[\]]*\])+)\]'), (m) => '@${m[2]}');
  s = s.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"');
  return s.trim();
}

String chatDuration(num? seconds) {
  final s = (seconds ?? 0).round().clamp(0, 1 << 30);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// How a call log looks for this viewer (caller vs. someone who missed it).
({String title, String detail, bool missed}) chatCallLabel(Map<String, dynamic>? call, String? me) {
  final video = call?['media']?.toString() == 'video';
  final what = video ? 'วิดีโอคอล' : 'โทรด้วยเสียง';
  final iAmCaller = call?['caller_id']?.toString() == me;
  final missedIds = (call?['missed_ids'] is List ? call!['missed_ids'] as List : const []).map((e) => '$e');
  final iMissed = me != null && missedIds.contains(me);
  switch (call?['status']?.toString()) {
    case 'completed':
      return (title: what, detail: chatDuration(call?['duration_s'] as num?), missed: false);
    case 'cancelled':
      return iAmCaller ? (title: what, detail: 'ยกเลิก', missed: false) : (title: 'สายที่ไม่ได้รับ', detail: what, missed: true);
    case 'declined':
      return (title: what, detail: iAmCaller ? 'ปลายสายปฏิเสธ' : 'ปฏิเสธสาย', missed: false);
    case 'busy':
      return (title: what, detail: 'สายไม่ว่าง', missed: false);
    default:
      return iMissed || !iAmCaller
          ? (title: 'สายที่ไม่ได้รับ', detail: what, missed: true)
          : (title: what, detail: 'ไม่มีผู้รับสาย', missed: false);
  }
}

/// One line under the room name: "คุณ: …", "Somchai: 📷 รูปภาพ", "📞 สายที่ไม่ได้รับ" …
String chatRoomPreview(Map<String, dynamic> room, String? me) {
  final m = _map(room['last_message']);
  if (m == null) {
    final legacy = room['last_message'];
    return legacy is String ? chatPlainText(legacy) : '';
  }
  final mine = m['user_id']?.toString() == me;
  final who = mine ? 'คุณ' : (chatRoomIsDm(room) ? '' : (m['sender_name']?.toString() ?? ''));
  String text;
  if (m['deleted'] == true) {
    text = 'ข้อความถูกลบแล้ว';
  } else if (m['kind']?.toString() == 'call' && m['call'] is Map) {
    final call = _map(m['call']);
    text = '${call?['media'] == 'video' ? '📹' : '📞'} ${chatCallLabel(call, me).title}';
  } else {
    text = chatPlainText(m['body']?.toString()).replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty && m['attachment_kind'] != null) text = chatKindLabel(m['attachment_kind'].toString());
    if (m['forwarded'] == true) text = '↪ $text';
  }
  return who.isEmpty ? text : '$who: $text';
}

/// "14:05" today, "เมื่อวาน", weekday this week, else "9 พ.ย."
String chatRoomTime(dynamic raw, {DateTime? now}) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '';
  final n = now ?? thaiNow();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 1) return 'เมื่อวาน';
  const wd = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
  if (diff > 1 && diff < 7) return wd[d.weekday - 1];
  const mo = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  return '${d.day} ${mo[d.month - 1]}';
}

int chatUnread(Map<String, dynamic> r) => int.tryParse('${r['unread_count'] ?? ''}') ?? 0;

/// Starred rooms first, then newest message first (rooms without messages by creation time).
List<Map<String, dynamic>> chatSortRooms(List<Map<String, dynamic>> rooms) {
  String at(Map r) => '${r['last_message_at'] ?? r['created_at'] ?? ''}';
  final out = [...rooms];
  out.sort((a, b) {
    final sa = a['starred'] == true ? 1 : 0, sb = b['starred'] == true ? 1 : 0;
    if (sa != sb) return sb - sa;
    final ta = parseThai(at(a)), tb = parseThai(at(b));
    if (ta != null && tb != null) return tb.compareTo(ta);
    return at(b).compareTo(at(a));
  });
  return out;
}

/// `@Name` in the composer → `@[id:Name]` the server understands, plus the mentioned ids.
({String body, List<int> ids}) chatEncodeMentions(String text, Map<String, String> mentionByName) {
  var body = text;
  final ids = <int>{};
  final names = mentionByName.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final token = '@$name';
    if (!body.contains(token)) continue;
    final id = mentionByName[name]!;
    body = body.replaceAll(token, '@[$id:$name]');
    final n = int.tryParse(id);
    if (n != null) ids.add(n);
  }
  return (body: body, ids: ids.toList());
}

/// URLs in a message (for link previews), at most [max].
List<String> chatLinks(String? body, {int max = 1}) {
  final text = chatPlainText(body);
  return RegExp(r'https?://[^\s<>"]+').allMatches(text).map((m) => m[0]!.replaceAll(RegExp(r'[).,]+$'), '')).take(max).toList();
}

/// Plain chat text with Slack-style tokens (**bold**, _italic_, ~~strike~~, `code`, links) → simple HTML
/// for [NxHtmlView]. Text that already contains HTML is returned unchanged.
String chatMarkdownToHtml(String body) {
  if (RegExp(r'<(p|br|b|i|strong|em|a|div|span|ul|ol|li)\b', caseSensitive: false).hasMatch(body)) return body;
  var s = body.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '<b>${m[1]}</b>');
  s = s.replaceAllMapped(RegExp(r'(^|[\s(])_(\S(?:.*?\S)?)_(?=$|[\s).,!?])', multiLine: true), (m) => '${m[1]}<i>${m[2]}</i>');
  s = s.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<b>${m[1]}</b>');
  s = s.replaceAllMapped(RegExp(r'(https?://[^\s<]+[^\s<.,)])'), (m) => '<a href="${m[1]}">${m[1]}</a>');
  s = s.replaceAllMapped(RegExp(r'^&gt; ?(.*)$', multiLine: true), (m) => '│ <i>${m[1]}</i>');
  s = s.replaceAllMapped(RegExp(r'^[-*] (.*)$', multiLine: true), (m) => '• ${m[1]}');
  return s.replaceAll('\n', '<br>');
}
