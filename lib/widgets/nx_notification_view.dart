import 'package:flutter/material.dart';

import '../core/html_display.dart';
import '../core/i18n.dart';
import '../core/thai_time.dart';
import 'nx_icons.dart';

/// Shared look of a NEXTX notification (bell tray + notification center),
/// matching the web: category icon/colour, **bold** markers rendered bold,
/// digest lists (daily 09:00 "งานค้าง" / "งานวันนี้") with one link per task.

/// Category of a notification — same rules as the web / backend
/// (`notificationCategory.js`): `meta.module` first, then path / type.
String notifCategory(Map<String, dynamic> n) {
  final meta = n['meta'];
  if (meta is Map) {
    final m = '${meta['module'] ?? ''}'.toLowerCase();
    const known = {'work', 'case', 'calendar', 'chat', 'sales', 'quotation', 'contract', 'job', 'mail', 'store', 'ai', 'hr', 'social'};
    if (m == 'workspace') return 'work';
    if (known.contains(m)) return m;
    if (m == 'system') return 'other';
  }
  final path = '${n['link_path'] ?? ''}'.toLowerCase();
  final type = '${n['type'] ?? ''}'.toLowerCase();
  if (path.startsWith('/workspace')) return 'work';
  if (type.contains('chat') || type.contains('mention') || path.startsWith('/community-chat') || path.startsWith('/camp')) return 'chat';
  if (type.contains('quotation') || path.contains('/quotation')) return 'quotation';
  if (type == 'contract' || path.startsWith('/modules/service_contract')) return 'contract';
  if (type == 'ai_job' || path == '/ai' || path.startsWith('/ai/')) return 'ai';
  if (type.contains('job') || path.contains('/job')) return 'job';
  if (path.startsWith('/commercial-store') || path.startsWith('/mini-store')) return 'store';
  if (type.contains('mail') || path.startsWith('/mail')) return 'mail';
  if (type.contains('case') || path.contains('/modules/case')) return 'case';
  if (type == 'sales' || RegExp(r'/(lead|deal|contact|account)').hasMatch(path)) return 'sales';
  if (type.contains('calendar') || path.startsWith('/calendar') || path.startsWith('/boards')) return 'calendar';
  if (path == '/hr' || path.startsWith('/hr/') || type.contains('leave')) return 'hr';
  if (path.startsWith('/social')) return 'social';
  return 'other';
}

/// Tabs shown in the bell tray (like the web bell).
const kNotifTrayTabs = ['all', 'work', 'chat', 'case', 'calendar', 'sales', 'other'];

({String label, IconData icon, Color color}) notifCategoryStyle(String c) => switch (c) {
      'all' => (label: 'ทั้งหมด', icon: NxI.bell, color: const Color(0xFF6366F1)),
      'work' => (label: 'งาน', icon: NxI.kanban, color: const Color(0xFF3B82F6)),
      'chat' => (label: 'แชท', icon: NxI.chatCircle, color: const Color(0xFF10B981)),
      'case' => (label: 'เคส', icon: NxI.headset, color: const Color(0xFFEF4444)),
      'calendar' => (label: 'ปฏิทิน', icon: NxI.calendarBlank, color: const Color(0xFFF97316)),
      'sales' => (label: 'การขาย', icon: NxI.handshake, color: const Color(0xFF14B8A6)),
      'quotation' => (label: 'ใบเสนอราคา', icon: NxI.receipt, color: const Color(0xFFF59E0B)),
      'contract' => (label: 'สัญญา', icon: NxI.note, color: const Color(0xFF8B5CF6)),
      'job' => (label: 'งานบริการ', icon: NxI.wrench, color: const Color(0xFF0EA5E9)),
      'mail' => (label: 'เมล', icon: NxI.envelope, color: const Color(0xFF6366F1)),
      'store' => (label: 'ร้านค้า', icon: NxI.package, color: const Color(0xFFEC4899)),
      'ai' => (label: 'AI', icon: NxI.sparkle, color: const Color(0xFF7C3AED)),
      'hr' => (label: 'บุคคล', icon: NxI.idCard, color: const Color(0xFF0D9488)),
      'social' => (label: 'โซเชียล', icon: NxI.shareNetwork, color: const Color(0xFF2563EB)),
      _ => (label: 'อื่นๆ', icon: NxI.bell, color: const Color(0xFF64748B)),
    };

bool notifUnread(Map<String, dynamic> n) => n['read_at'] == null && n['is_read'] != true;

/// `"งาน **NEXTT-16** เลยกำหนด **3 วัน**"` → spans with the marked parts bold.
List<InlineSpan> boldSpans(String raw, {TextStyle? bold}) {
  final text = stripHtmlPreview(raw, maxLen: 100000);
  final out = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*');
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
    out.add(TextSpan(text: m.group(1), style: bold ?? const TextStyle(fontWeight: FontWeight.w800)));
    at = m.end;
  }
  if (at < text.length) out.add(TextSpan(text: text.substring(at)));
  return out;
}

/// Plain text without ** markers (for one-line previews).
String plainNotif(String raw) => stripHtmlPreview(raw, maxLen: 100000).replaceAll('**', '');

/// Items of a daily digest (`meta.items`), or empty.
List<Map<String, dynamic>> notifDigestItems(Map<String, dynamic> n) {
  final meta = n['meta'];
  final items = meta is Map ? meta['items'] : null;
  if (items is! List) return const [];
  return [for (final e in items) if (e is Map) Map<String, dynamic>.from(e)];
}

/// "วันนี้" / "เมื่อวาน" / "ก่อนหน้า" heading for the list.
String notifDayBucket(dynamic createdAt, {DateTime? now}) {
  final d = parseThai(createdAt?.toString() ?? '');
  if (d == null) return 'ก่อนหน้า';
  final n = now ?? thaiNow();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'วันนี้';
  if (diff == 1) return 'เมื่อวาน';
  return 'ก่อนหน้า';
}

/// One notification row.
class NxNotifTile extends StatelessWidget {
  const NxNotifTile({
    super.key,
    required this.item,
    required this.onOpen,
    this.onOpenLink,
    this.timeLabel,
    this.compact = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onOpen;

  /// Opens one task of a digest (its `link_path`).
  final ValueChanged<String>? onOpenLink;
  final String? timeLabel;

  /// Tray: shorter body, 3 digest rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unread = notifUnread(item);
    final cat = notifCategory(item);
    final style = notifCategoryStyle(cat);
    final digest = notifDigestItems(item);
    final body = '${item['body'] ?? ''}';
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 9 : 12, 16, compact ? 9 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 34 : 40,
              height: compact ? 34 : 40,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: unread ? 0.18 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, size: compact ? 17 : 19, color: unread ? style.color : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: boldSpans(tr('${item['title'] ?? ''}'))),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
                  ),
                  if (digest.isNotEmpty)
                    _DigestList(items: digest, max: compact ? 3 : 8, onOpenLink: onOpenLink)
                  else if (body.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: boldSpans(tr(body))),
                      maxLines: compact ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(tr(style.label), style: theme.textTheme.labelSmall?.copyWith(color: style.color, fontWeight: FontWeight.w700)),
                    ),
                    if (timeLabel != null && timeLabel!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(tr(timeLabel!), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ]),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 8),
                child: Container(width: 9, height: 9, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DigestList extends StatefulWidget {
  const _DigestList({required this.items, required this.max, this.onOpenLink});
  final List<Map<String, dynamic>> items;
  final int max;
  final ValueChanged<String>? onOpenLink;

  @override
  State<_DigestList> createState() => _DigestListState();
}

class _DigestListState extends State<_DigestList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = _all ? widget.items : widget.items.take(widget.max).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in shown)
            InkWell(
              key: ValueKey('digest-${it['code'] ?? it['title']}'),
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onOpenLink == null ? null : () => widget.onOpenLink!('${it['link_path'] ?? '/workspace'}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    if ('${it['board'] ?? ''}'.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          '${it['board']} · ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        [it['code'], it['title']].where((e) => e != null && '$e'.isNotEmpty).join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if ((num.tryParse('${it['days'] ?? ''}') ?? 0) > 0)
                      Text(
                        tr('เลย ${it['days']} วัน'),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
                      ),
                  ],
                ),
              ),
            ),
          if (widget.items.length > widget.max)
            GestureDetector(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _all ? tr('ย่อ') : tr('ดูทั้งหมด ${widget.items.length} งาน'),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
