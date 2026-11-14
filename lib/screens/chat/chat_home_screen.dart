import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/chat_format.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_bottom_sheet.dart' show nxSheetHeight;
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../core/nx_swr_cache.dart';
import '../../widgets/nx_split_view.dart';
import 'chat_room_screen.dart';
import 'chat_search_screen.dart';

/// Chat list like LINE / Slack: avatar, name (the other person for DMs), last message with sender,
/// time, unread badge, starred first, muted. Long press = mute / star / mark read.
class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  var _revision = 0;
  var _query = '';
  NxListQuery _lq = const NxListQuery();
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _rooms = const [];
  final Map<String, Map<String, dynamic>> _overrides = {}; // local muted / starred / read until the next load
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    // New messages anywhere → refresh the list (debounced for bursts).
    _sub = RealtimeService.instance.on('new_message').listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 1200), _reload);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _overrides.clear();
      _revision++;
    });
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(t))));

  Future<List<Map<String, dynamic>>> _pickUsers({required bool multi}) async {
    final me = context.read<AppConfig>().session.userId;
    List<Map<String, dynamic>> users;
    try {
      users = (await _api.getUsers(limit: 200)).where((u) => u['id']?.toString() != me).toList();
    } catch (e) {
      _snack(formatApiError(e));
      return const [];
    }
    if (!mounted) return const [];
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => _UserPickerSheet(users: users, multi: multi),
    );
    return picked ?? const [];
  }

  Future<void> _newDm() async {
    final users = await _pickUsers(multi: false);
    if (users.isEmpty || !mounted) return;
    try {
      final room = await _api.createChatDm('${users.first['id']}');
      if (!mounted) return;
      await _openRoom(room.isEmpty ? {'id': users.first['id'], 'name': userDisplayName(users.first)} : {...room, 'room_type': 'dm', 'display_name': userDisplayName(users.first)});
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _newGroup() async {
    final users = await _pickUsers(multi: true);
    if (users.isEmpty || !mounted) return;
    final name = TextEditingController(text: users.take(3).map(userDisplayName).join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ตั้งชื่อกลุ่ม')),
        content: TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('ชื่อกลุ่ม'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('สร้างกลุ่ม (${users.length} คน)'))),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    try {
      final room = await _api.createChatRoom(name: name.text.trim(), memberIds: [for (final u in users) '${u['id']}']);
      if (!mounted) return;
      _reload();
      if (room['id'] != null) await _openRoom(room);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _newMenu() async {
    final pick = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const ValueKey('chat-new-dm'), leading: const Icon(NxI.user), title: Text(tr('แชทส่วนตัว')), onTap: () => Navigator.pop(ctx, 'dm')),
          ListTile(key: const ValueKey('chat-new-group'), leading: const Icon(NxI.users), title: Text(tr('สร้างกลุ่ม')), onTap: () => Navigator.pop(ctx, 'group')),
          ListTile(key: const ValueKey('chat-search-messages'), leading: const Icon(NxI.magnifyingGlass), title: Text(tr('ค้นหาในข้อความ')), onTap: () => Navigator.pop(ctx, 'search')),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'dm':
        await _newDm();
      case 'group':
        await _newGroup();
      case 'search':
        await nxPush<void>(context, ChatSearchScreen(rooms: _rooms));
    }
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    final id = '${room['id']}';
    setState(() => _overrides[id] = {...?_overrides[id], 'unread_count': 0});
    if (NxBreakpoint.of(context).twoPane) {
      setState(() => _selected = room);
      return;
    }
    await nxPush<void>(context, ChatRoomScreen(room: room));
    _reload();
  }

  Future<void> _roomMenu(Map<String, dynamic> r) async {
    final id = '${r['id']}';
    final muted = r['muted'] == true, starred = r['starred'] == true;
    final pick = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(chatRoomTitle(r), style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(leading: Icon(starred ? NxI.starFill : NxI.star), title: Text(tr(starred ? 'เลิกติดดาว' : 'ติดดาว (อยู่บนสุด)')), onTap: () => Navigator.pop(ctx, 'star')),
          ListTile(leading: Icon(muted ? NxI.bell : NxI.bellSlash), title: Text(tr(muted ? 'เปิดเสียงแจ้งเตือน' : 'ปิดเสียงแจ้งเตือน')), onTap: () => Navigator.pop(ctx, 'mute')),
          if (chatUnread(r) > 0) ListTile(leading: const Icon(NxI.checks), title: Text(tr('ทำเครื่องหมายว่าอ่านแล้ว')), onTap: () => Navigator.pop(ctx, 'read')),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    try {
      switch (pick) {
        case 'star':
          await _api.setChatRoomStarred(id, !starred);
          setState(() => _overrides[id] = {...?_overrides[id], 'starred': !starred});
        case 'mute':
          await _api.setChatRoomMuted(id, !muted);
          setState(() => _overrides[id] = {...?_overrides[id], 'muted': !muted});
        case 'read':
          final last = r['last_message'] is Map ? '${(r['last_message'] as Map)['id']}' : null;
          if (last != null) await _api.markChatRead(id, last);
          setState(() => _overrides[id] = {...?_overrides[id], 'unread_count': 0});
      }
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Widget _toolbar(int totalUnread) => NxListToolbar(
        query: _lq.copyWith(q: _query),
        liveSearch: true,
        padding: const EdgeInsets.only(bottom: 6),
        searchHint: 'ค้นหาแชท',
        quickGroup: 'kind',
        groups: [
          const NxFilterGroup(key: 'kind', label: 'ประเภท', multi: false, options: [NxFilterOption('dm', 'ส่วนตัว'), NxFilterOption('group', 'กลุ่ม')]),
          NxFilterGroup(key: 'state', label: 'สถานะ', multi: false, options: [NxFilterOption('unread', totalUnread > 0 ? 'ยังไม่อ่าน ($totalUnread)' : 'ยังไม่อ่าน')]),
        ],
        onChanged: (q) => setState(() {
          _query = q.q;
          _lq = q.copyWith(q: '');
        }),
      );

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppConfig>().session.userId;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'แชททีม',
        actions: [
          IconButton(key: const ValueKey('chat-new'), tooltip: tr('แชทใหม่'), icon: const Icon(NxI.squarePen), onPressed: _newMenu),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => _api.getChatRooms(),
        // Last list (also kept on disk): the chat tab opens on it and refreshes.
        cacheKey: NxSwrCache.key('/api/chat/rooms'),
        persist: true,
        // The real toolbar stays; only the rooms are bones (50 px avatar, name /
        // preview, time and unread badge), in the list's own padding.
        skeleton: NxSkeleton(
          key: const ValueKey('chat-home-skeleton'),
          child: NxSkeletonListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: IgnorePointer(child: _toolbar(0))),
              for (var i = 0; i < 9; i++)
                NxSkeletonRow(
                  style: NxSkelRowStyle.flat,
                  leadingSize: 50,
                  trailing: NxSkelTrailing.timeBadge,
                  wide: i.isEven,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
            ],
          ),
        ),
        isEmpty: (list) => list.isEmpty,
        empty: Center(child: Text(tr('ยังไม่มีห้องแชท'))),
        builder: (context, loaded) {
          final all = [for (final r in loaded) {...r, ...?_overrides['${r['id']}']}];
          _rooms = all;
          final rooms = chatSortRooms(nxApplyLocalQuery<Map<String, dynamic>>(
            all,
            _lq.copyWith(q: _query),
            text: (r) => '${chatRoomTitle(r)} ${chatRoomPreview(r, me)}',
            filters: {
              'kind': (r, v) => v.contains(chatRoomIsDm(r) ? 'dm' : 'group'),
              'state': (r, v) => !v.contains('unread') || chatUnread(r) > 0,
            },
          ));
          final totalUnread = all.fold<int>(0, (n, r) => n + (r['muted'] == true ? 0 : chatUnread(r)));
          final items = NxRefresh(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _toolbar(totalUnread),
                ),
                if (rooms.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('ไม่พบห้อง')))),
                for (final r in rooms)
                  ChatRoomTile(
                    key: ValueKey('chat-room-${r['id']}'),
                    room: r,
                    me: me,
                    selected: _selected != null && '${_selected!['id']}' == '${r['id']}',
                    onTap: () => _openRoom(r),
                    onLongPress: () => _roomMenu(r),
                  ),
              ],
            ),
          );
          return NxSplitView(
            onClose: () => setState(() => _selected = null),
            list: items,
            detail: _selected == null ? null : ChatRoomScreen(key: ValueKey(_selected!['id']), room: _selected!, embedded: true),
          );
        },
      ),
    );
  }
}

/// One row of the chat list.
class ChatRoomTile extends StatelessWidget {
  const ChatRoomTile({super.key, required this.room, required this.me, required this.onTap, this.onLongPress, this.selected = false});
  final Map<String, dynamic> room;
  final String? me;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = chatRoomTitle(room);
    final unread = chatUnread(room);
    final muted = room['muted'] == true;
    final starred = room['starred'] == true;
    final preview = chatRoomPreview(room, me);
    final time = chatRoomTime(room['last_message_at'] ?? room['created_at']);
    final emoji = room['icon_emoji']?.toString() ?? '';
    final dm = chatRoomIsDm(room);
    final last = room['last_message'] is Map ? room['last_message'] as Map : null;
    final missedCall = last?['kind'] == 'call' && preview.contains('ไม่ได้รับ');
    final bold = unread > 0;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              dm || emoji.isEmpty
                  ? NxAvatar(label: title, size: 50, imageUrl: (room['peer'] is Map) ? (room['peer'] as Map)['avatar']?.toString() : null)
                  : CircleAvatar(radius: 25, backgroundColor: cs.primaryContainer, child: Text(emoji, style: const TextStyle(fontSize: 22))),
              if (!dm && emoji.isEmpty)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                    child: Icon(NxI.users, size: 12, color: cs.onSurfaceVariant),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (starred) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(NxI.starFill, size: 14, color: Colors.amber.shade600)),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  if (muted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(NxI.bellSlash, size: 14, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Text(tr(time), style: theme.textTheme.labelSmall?.copyWith(color: bold ? cs.primary : cs.onSurfaceVariant, fontWeight: bold ? FontWeight.w700 : null)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(
                      tr(preview.isEmpty ? (dm ? 'เริ่มแชทได้เลย' : '${room['member_count'] ?? ''} สมาชิก') : preview),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: missedCall ? cs.error : (bold ? cs.onSurface : cs.onSurfaceVariant),
                        fontWeight: bold ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      key: ValueKey('chat-unread-${room['id']}'),
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: muted ? cs.outline : cs.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text(unread > 99 ? '99+' : '$unread', textAlign: TextAlign.center, style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet({required this.users, required this.multi});
  final List<Map<String, dynamic>> users;
  final bool multi;

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final Set<String> _picked = {};
  var _needle = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users.where((u) {
      if (_needle.isEmpty) return true;
      return userDisplayName(u).toLowerCase().contains(_needle) || (userEmail(u) ?? '').toLowerCase().contains(_needle);
    }).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: nxSheetHeight(context, 0.8),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: !widget.multi,
                decoration: InputDecoration(hintText: tr(widget.multi ? 'ค้นหาสมาชิก' : 'ค้นหาคนที่จะแชท'), prefixIcon: const Icon(NxI.magnifyingGlass), isDense: true),
                onChanged: (v) => setState(() => _needle = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final u = filtered[i];
                  final id = '${u['id']}';
                  final leading = NxAvatar(label: userDisplayName(u), size: 38);
                  if (!widget.multi) {
                    return ListTile(
                      key: ValueKey('chat-user-$id'),
                      leading: leading,
                      title: Text(userDisplayName(u)),
                      subtitle: Text(userEmail(u) ?? ''),
                      onTap: () => Navigator.pop(context, [u]),
                    );
                  }
                  return CheckboxListTile(
                    key: ValueKey('chat-user-$id'),
                    value: _picked.contains(id),
                    secondary: leading,
                    title: Text(userDisplayName(u)),
                    subtitle: Text(userEmail(u) ?? ''),
                    onChanged: (v) => setState(() => v == true ? _picked.add(id) : _picked.remove(id)),
                  );
                },
              ),
            ),
            if (widget.multi)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, [for (final u in widget.users) if (_picked.contains('${u['id']}')) u]),
                    child: Text(tr('ถัดไป (${_picked.length} คน)')),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
