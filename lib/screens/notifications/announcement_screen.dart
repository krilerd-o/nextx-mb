import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/push_tap.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_notification_view.dart' show boldSpans;
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import '../profile/profile_ui.dart';

/// Look of an announcement kind (`announcement` | `maintenance` | `general` | `app_update`).
({String label, IconData icon, Color color}) announcementKindStyle(String? kind) => switch ((kind ?? '').trim()) {
      'maintenance' => (label: 'ปิดปรับปรุงระบบ', icon: NxI.wrench, color: const Color(0xFFF59E0B)),
      'app_update' => (label: 'อัปเดตแอป', icon: NxI.downloadSimple, color: const Color(0xFF10B981)),
      'general' => (label: 'ประกาศทั่วไป', icon: NxI.info, color: const Color(0xFF0EA5E9)),
      _ => (label: 'ประกาศ', icon: NxI.megaphone, color: const Color(0xFF6366F1)),
    };

/// Body text with its line breaks kept (`boldSpans` folds whitespace) and
/// `**bold**` parts bold.
List<InlineSpan> announcementBodySpans(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  return [
    for (final (i, line) in lines.indexed) ...[
      if (i > 0) const TextSpan(text: '\n'),
      ...boldSpans(line),
    ],
  ];
}

/// One announcement in full (`GET /api/announcements/:id`): a company
/// announcement, a maintenance notice, a general notice or an app update
/// (with a button to the store of this phone). Opened from its push / bell
/// row ([notificationId] = that bell row, marked read here).
class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key, required this.id, this.notificationId, this.ios});

  final String id;
  final String? notificationId;

  /// Platform for the store link (tests); null = this phone.
  final bool? ios;

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  Map<String, dynamic>? _a;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _markRead();
    });
  }

  ApiClient get _api => context.read<AppConfig>().apiClient;

  Future<void> _markRead() async {
    final n = widget.notificationId;
    if (n == null || n.isEmpty) return;
    try {
      await _api.markNotificationRead(n);
      await UnreadNotifications.instance.refresh(_api);
    } catch (e) {
      debugPrint('[announcement] read: $e');
    }
  }

  Future<void> _load() async {
    try {
      final a = await _api.getAnnouncement(widget.id);
      if (!mounted) return;
      setState(() {
        _a = a;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openStore(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await pushStoreLauncher(Uri.parse(url));
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('เปิดร้านค้าแอปไม่ได้'))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = _a;
    final children = <Widget>[];
    if (_loading) {
      children.add(const NxSkeletonList(rows: 3));
    } else if (a == null) {
      final missing = _error != null && isMissingEndpoint(_error!);
      children.add(NxSoftNote(
        key: const ValueKey('ann-error'),
        icon: missing ? NxI.megaphone : NxI.warningCircle,
        color: missing ? null : cs.error,
        title: missing ? 'ไม่พบประกาศนี้' : null,
        text: missing ? 'ประกาศอาจถูกลบแล้ว หรือระบบของพื้นที่ทำงานนี้ยังไม่รองรับการเปิดอ่านประกาศ' : formatApiError(_error ?? ''),
        action: missing
            ? null
            : TextButton.icon(onPressed: _load, icon: const Icon(NxI.arrowClockwise, size: 16), label: Text(tr('ลองใหม่'))),
      ));
    } else {
      final kind = '${a['kind'] ?? ''}';
      final style = announcementKindStyle(kind);
      final title = '${a['title'] ?? ''}'.trim();
      final body = '${a['body'] ?? ''}'.trim();
      final sender = '${a['sender_name'] ?? ''}'.trim();
      final when = formatThaiField(a['created_at'], null, year: uiYear);
      final store = kind == 'app_update' ? appStoreLinkOf(a, ios: widget.ios) : null;
      Widget meta(IconData icon, String text, Key key) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(icon, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text, key: key, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          );
      children.add(Container(
        key: const ValueKey('ann-card'),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: style.color.withValues(alpha: 0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: style.color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(style.icon, color: style.color, size: 22),
            ),
            const SizedBox(width: 12),
            Container(
              key: const ValueKey('ann-kind'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: style.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
              child: Text(tr(style.label), style: theme.textTheme.labelMedium?.copyWith(color: style.color, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 14),
          if (title.isNotEmpty)
            Text.rich(
              TextSpan(children: boldSpans(title)),
              key: const ValueKey('ann-title'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.3),
            ),
          const SizedBox(height: 6),
          if (sender.isNotEmpty) meta(NxI.userCircle, tr('จาก $sender'), const ValueKey('ann-sender')),
          if (when.isNotEmpty) meta(NxI.clock, when, const ValueKey('ann-date')),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            SelectableText.rich(
              TextSpan(children: announcementBodySpans(body)),
              key: const ValueKey('ann-body'),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: cs.onSurface),
            ),
          ],
        ]),
      ));
      if (store != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FilledButton.icon(
            key: const ValueKey('ann-update'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => _openStore(store),
            icon: const Icon(NxI.downloadSimple, size: 18),
            label: Text(tr('อัปเดตแอป')),
          ),
        ));
      }
    }
    return ProfileSubPage(title: 'ประกาศ', onRefresh: _load, children: children);
  }
}
