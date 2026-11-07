import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/html_display.dart';
import '../../core/navigation/notification_deep_link.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';

/// NEXTX notification categories (backend/src/services/notificationCategory.js).
const notificationCategories = <String, String>{
  'all': 'ทั้งหมด',
  'work': 'งาน',
  'chat': 'แชท',
  'case': 'เคส',
  'calendar': 'ปฏิทิน',
  'sales': 'การขาย',
  'quotation': 'ใบเสนอราคา',
  'job': 'งานบริการ',
  'mail': 'เมล',
};

IconData notificationIcon(Map<String, dynamic> n) {
  final type = '${n['type'] ?? ''} ${n['link_path'] ?? ''}'.toLowerCase();
  if (type.contains('chat') || type.contains('camp')) return NxI.chatCircle;
  if (type.contains('calendar') || type.contains('activity')) return NxI.calendarBlank;
  if (type.contains('workspace') || type.contains('task')) return NxI.kanban;
  if (type.contains('quotation')) return NxI.receipt;
  if (type.contains('mail')) return NxI.envelope;
  if (type.contains('case')) return NxI.headset;
  if (type.contains('job') || type.contains('field')) return NxI.wrench;
  if (type.contains('leave') || type.contains('hr')) return NxI.briefcase;
  return NxI.bell;
}

/// "5 นาทีที่แล้ว" style label.
String relativeTime(dynamic raw, {DateTime? now}) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '';
  final diff = (now ?? thaiNow()).difference(d);
  if (diff.inMinutes < 1) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
  return '${d.day}/${d.month}/${uiYear(d.year)}';
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _unreadOnly = false;
  String _category = 'all';
  Object? _error;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _sub = RealtimeService.instance.on('notification').listen((e) {
      if (!mounted) return;
      final id = e.data['id']?.toString();
      if (id == null || _items.any((n) => n['id']?.toString() == id)) return;
      setState(() => _items = [e.data, ..._items]);
    });
    _reload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<AppConfig>().apiClient;

  Future<void> _reload() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await _api.getNotificationsPage(category: _category, unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _loading = false;
      });
      UnreadNotifications.instance.refresh(_api);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.getNotificationsPage(cursor: _cursor, category: _category, unreadOnly: _unreadOnly);
      if (!mounted) return;
      final seen = _items.map((n) => n['id']?.toString()).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((n) => !seen.contains(n['id']?.toString()))];
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _markLocalRead(Map<String, dynamic> n) {
    if (n['read_at'] != null) return;
    setState(() {
      _items = [
        for (final it in _items)
          if (it['id'] == n['id']) {...it, 'read_at': thaiNow().toIso8601String()} else it,
      ];
    });
    UnreadNotifications.instance.markedRead();
  }

  void _open(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if (item['read_at'] == null && id.isNotEmpty) {
      _api.markNotificationRead(id).catchError((Object e) {
        debugPrint('[notif] read: $e');
      });
      _markLocalRead(item);
    }
    final path = item['link_path']?.toString() ?? '';
    context.push(notificationDeepLink(path, linkId: item['link_id']?.toString()));
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final index = _items.indexOf(item);
    setState(() => _items = [..._items]..remove(item));
    if (item['read_at'] == null) UnreadNotifications.instance.markedRead();
    try {
      await _api.deleteNotification(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = [..._items]..insert(index.clamp(0, _items.length), item));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _readAll() async {
    try {
      await _api.markAllNotificationsRead();
      if (!mounted) return;
      final now = thaiNow().toIso8601String();
      setState(() => _items = [for (final it in _items) {...it, 'read_at': it['read_at'] ?? now}]);
      UnreadNotifications.instance.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  Widget _tile(Map<String, dynamic> it) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unread = it['read_at'] == null;
    final body = stripHtmlPreview(it['body']?.toString() ?? '', maxLen: 140);
    return Dismissible(
      key: ValueKey('n-${it['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: cs.errorContainer,
        child: Icon(NxI.trash, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => _delete(it),
      child: Material(
        color: unread ? cs.primaryContainer.withValues(alpha: 0.25) : Colors.transparent,
        child: InkWell(
          onTap: () => _open(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: unread ? cs.primary : cs.surfaceContainerHighest,
                  child: Icon(notificationIcon(it), size: 20, color: unread ? cs.onPrimary : cs.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(stripHtmlPreview(it['title']?.toString() ?? '', maxLen: 80)),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(tr(body), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        tr(relativeTime(it['created_at'])),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 8),
                    child: Icon(Icons.circle, size: 10, color: cs.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_loading) {
      body = const NxSkeletonList();
    } else if (_error != null && _items.isEmpty) {
      body = ListView(children: [
        const SizedBox(height: 80),
        Center(child: Text(tr(formatApiError(_error!)))),
        Center(child: TextButton(onPressed: _reload, child: Text(tr('ลองใหม่')))),
      ]);
    } else if (_items.isEmpty) {
      body = ListView(children: [
        const SizedBox(height: 100),
        Icon(NxI.bellSimple, size: 56, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text(tr(_unreadOnly ? 'อ่านครบทุกรายการแล้ว' : 'ไม่มีการแจ้งเตือน'), style: theme.textTheme.titleMedium)),
      ]);
    } else {
      body = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_cursor != null ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return _tile(_items[i]);
        },
      );
    }

    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'การแจ้งเตือน',
        menu: [
          NxHeaderMenuItem(label: 'อ่านทั้งหมด', icon: NxI.checkCircle, onTap: _readAll),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(tr('ยังไม่อ่าน')),
                    selected: _unreadOnly,
                    onSelected: (v) {
                      setState(() => _unreadOnly = v);
                      _reload();
                    },
                  ),
                ),
                for (final e in notificationCategories.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tr(e.value)),
                      selected: _category == e.key,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _category = e.key);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: RefreshIndicator(onRefresh: _reload, child: body)),
        ],
      ),
    );
  }
}
