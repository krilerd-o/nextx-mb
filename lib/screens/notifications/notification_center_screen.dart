import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/navigation/notification_deep_link.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_notification_view.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_split_view.dart';
import '../../core/nx_breakpoint.dart';
import '../deep_link_loaders.dart' show nxPaneForRoute;

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
  if (type.startsWith('mention ')) return NxI.at;
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
  /// Two-pane: record opened beside the list.
  String? _paneRoute;
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
    if (notifUnread(item) && id.isNotEmpty) {
      _api.markNotificationRead(id).catchError((Object e) {
        debugPrint('[notif] read: $e');
      });
      _markLocalRead(item);
    }
    final path = item['link_path']?.toString() ?? '';
    final meta = item['meta'];
    final extra = item['link_extra']?.toString() ?? (meta is Map ? meta['kind']?.toString() : null);
    final route = notificationDeepLink(path, linkId: item['link_id']?.toString(), extra: extra);
    // Tablet / unfolded: open the record beside the list.
    if (NxBreakpoint.of(context).twoPane && nxPaneForRoute(route) != null) {
      setState(() => _paneRoute = route);
      return;
    }
    context.push(route);
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final index = _items.indexOf(item);
    setState(() => _items = [..._items]..remove(item));
    if (notifUnread(item)) UnreadNotifications.instance.markedRead();
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
    final cs = Theme.of(context).colorScheme;
    final unread = notifUnread(it);
    return Dismissible(
      key: ValueKey('n-${it['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: cs.errorContainer,
        child: Icon(NxI.trash, color: cs.onErrorContainer),
      ),
      // Ask first (accidental swipe); cancel snaps the row back.
      confirmDismiss: (_) => showDeleteConfirm(
        context,
        name: '${it['title'] ?? ''}'.trim().isEmpty ? tr('การแจ้งเตือนนี้') : '${it['title']}'.trim(),
        loses: const ['การแจ้งเตือนนี้จะหายจากรายการ'],
        note: null,
      ),
      onDismissed: (_) => _delete(it),
      child: Material(
        color: unread ? cs.primaryContainer.withValues(alpha: 0.25) : Colors.transparent,
        child: NxNotifTile(
          item: it,
          timeLabel: relativeTime(it['created_at']),
          onOpen: () => _open(it),
          onOpenLink: (path) => context.push(notificationDeepLink(path)),
        ),
      ),
    );
  }

  /// Category + unread go to the server; search and sort apply locally.
  NxListQuery _query = const NxListQuery();

  List<Map<String, dynamic>> get _shown => nxApplyLocalQuery<Map<String, dynamic>>(
        _items,
        _query.copyWith(filters: const {}),
        text: (n) => '${n['title'] ?? ''} ${n['body'] ?? ''}',
        sorts: {
          'old': (a, b) => '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}'),
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    Widget body;
    if (_loading) {
      body = const NxSkeletonList();
    } else if (_error != null && _items.isEmpty) {
      body = ListView(children: [
        const SizedBox(height: 80),
        Center(child: Text(tr(formatApiError(_error!)))),
        Center(child: TextButton(onPressed: _reload, child: Text(tr('ลองใหม่')))),
      ]);
    } else if (shown.isEmpty) {
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
        itemCount: shown.length + (_cursor != null ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= shown.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final day = notifDayBucket(shown[i]['created_at']);
          final first = i == 0 || notifDayBucket(shown[i - 1]['created_at']) != day;
          if (!first) return _tile(shown[i]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(tr(day), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              _tile(shown[i]),
            ],
          );
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
      body: NxSplitView(
        onClose: () => setState(() => _paneRoute = null),
        detail: _paneRoute == null
            ? null
            : NxPaneHost(
                key: ValueKey('notif-pane-$_paneRoute'),
                onPopRoot: () => setState(() => _paneRoute = null),
                child: nxPaneForRoute(_paneRoute!)!,
              ),
        list: Column(
        children: [
          NxListToolbar(
            query: _query,
            liveSearch: true,
            searchHint: 'ค้นหาการแจ้งเตือน',
            quickGroup: 'cat',
            groups: [
              NxFilterGroup(
                key: 'cat',
                label: 'หมวด',
                multi: false,
                options: [
                  for (final e in notificationCategories.entries)
                    if (e.key != 'all') NxFilterOption(e.key, e.value),
                ],
              ),
              const NxFilterGroup(
                key: 'state',
                label: 'สถานะ',
                multi: false,
                options: [NxFilterOption('unread', 'ยังไม่อ่าน')],
              ),
            ],
            sorts: const [NxSortOption('new', 'ใหม่ → เก่า'), NxSortOption('old', 'เก่า → ใหม่')],
            onChanged: (q) {
              final reload = q.single('cat') != _query.single('cat') || q.has('state', 'unread') != _query.has('state', 'unread');
              setState(() {
                _query = q;
                _category = q.single('cat') ?? 'all';
                _unreadOnly = q.has('state', 'unread');
              });
              if (reload) _reload();
            },
          ),
          Expanded(child: NxRefresh(onRefresh: _reload, child: body)),
        ],
      ),
      ),
    );
  }
}
