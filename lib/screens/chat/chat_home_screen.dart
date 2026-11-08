import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../services/realtime_service.dart';
import 'chat_room_screen.dart';
import 'chat_search_screen.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/app_bottom_sheet.dart' show nxSheetHeight;

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
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // New messages anywhere → refresh unread counts (debounced for bursts).
    _sub = RealtimeService.instance.on('new_message').listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _revision++);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final api = context.read<AppConfig>().apiClient;
    List<Map<String, dynamic>> users;
    try {
      users = await api.getUsers(limit: 200);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return;
    }
    if (!mounted) return;
    final me = context.read<AppConfig>().session.userId;
    final result = await showModalBottomSheet<({String name, List<String> ids})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _GroupCreateSheet(users: users.where((u) => u['id']?.toString() != me).toList()),
    );
    if (result == null || !mounted) return;
    try {
      final room = await api.createChatRoom(name: result.name, memberIds: result.ids);
      if (!mounted) return;
      setState(() => _revision++);
      if (room['id'] != null) await _openRoom(room);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    await nxPush<void>(context, ChatRoomScreen(room: room));
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'แชททีม',
        actions: [
          IconButton(
            tooltip: tr('ค้นหาข้อความ'),
            icon: const Icon(NxI.magnifyingGlass),
            onPressed: () => nxPush<void>(context, ChatSearchScreen(rooms: _rooms)),
          ),
          IconButton(tooltip: tr('สร้างห้องกลุ่ม'), icon: const Icon(NxI.users), onPressed: _createGroup),
          IconButton(
            tooltip: tr('แชทส่วนตัว'),
            icon: const Icon(NxI.userPlus),
            onPressed: () async {
              final api = context.read<AppConfig>().apiClient;
              List<Map<String, dynamic>> users = const [];
              try {
                users = await api.getUsers(limit: 80);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                }
                return;
              }
              if (!mounted) return;
              final selected = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                useRootNavigator: true,
                builder: (ctx) {
                  final q = TextEditingController();
                  var filtered = users;
                  return StatefulBuilder(
                    builder: (ctx, setSheet) {
                      return Padding(
                        // Above the keyboard: the search field and results stay visible.
                        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                        child: SafeArea(
                          child: SizedBox(
                            height: nxSheetHeight(ctx, 0.7),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: TextField(
                                    controller: q,
                                    decoration: InputDecoration(labelText: tr('ค้นหาผู้ใช้'), prefixIcon: Icon(NxI.magnifyingGlass)),
                                    onChanged: (v) {
                                      final needle = v.trim().toLowerCase();
                                      setSheet(() {
                                        filtered = users.where((u) {
                                          final name = userDisplayName(u).toLowerCase();
                                          final email = (userEmail(u) ?? '').toLowerCase();
                                          final id = (u['id'] ?? '').toString();
                                          return needle.isEmpty || name.contains(needle) || email.contains(needle) || id.contains(needle);
                                        }).toList();
                                      });
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (_, i) {
                                      final u = filtered[i];
                                      final name = userDisplayName(u);
                                      return ListTile(
                                        leading: const Icon(NxI.user),
                                        title: Text(tr(name)),
                                        subtitle: Text(tr(userEmail(u) ?? u['id']?.toString() ?? '')),
                                        onTap: () => Navigator.pop(ctx, u),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
              if (selected == null) return;
              final userId = selected['id']?.toString() ?? '';
              if (userId.isEmpty) return;
              try {
                final room = await api.createChatDm(userId);
                if (!mounted) return;
                final map = room.isEmpty ? {'id': userId, 'name': userDisplayName(selected)} : room;
                await _openRoom(map);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                }
              }
            },
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getChatRooms(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: Center(child: Text(tr('ยังไม่มีห้องแชท'))),
        builder: (context, all) {
          _rooms = all;
          final theme = Theme.of(context);
          int unreadOf(Map r) => int.tryParse('${r['unread_count'] ?? ''}') ?? 0;
          String lastAt(Map r) => '${r['last_message_at'] ?? r['updated_at'] ?? r['created_at'] ?? ''}';
          final rooms = nxApplyLocalQuery<Map<String, dynamic>>(
            all,
            _lq.copyWith(q: _query),
            text: (r) => '${r['name'] ?? ''} ${r['last_message'] ?? ''}',
            filters: {
              'kind': (r, v) => v.contains(r['room_type']?.toString() == 'dm' ? 'dm' : 'group'),
              'state': (r, v) => !v.contains('unread') || unreadOf(r) > 0,
            },
            sorts: {
              'recent': (a, b) => lastAt(b).compareTo(lastAt(a)),
              'unread': (a, b) => unreadOf(b).compareTo(unreadOf(a)),
              'name': (a, b) => '${a['name'] ?? ''}'.toLowerCase().compareTo('${b['name'] ?? ''}'.toLowerCase()),
            },
          );
          final items = NxRefresh(
            onRefresh: () async => setState(() => _revision++),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                NxListToolbar(
                  query: _lq.copyWith(q: _query),
                  liveSearch: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  searchHint: 'ค้นหาห้อง',
                  quickGroup: 'kind',
                  groups: const [
                    NxFilterGroup(key: 'kind', label: 'ประเภทห้อง', multi: false, options: [NxFilterOption('group', 'กลุ่ม'), NxFilterOption('dm', 'ส่วนตัว')]),
                    NxFilterGroup(key: 'state', label: 'สถานะ', multi: false, options: [NxFilterOption('unread', 'ยังไม่อ่าน')]),
                  ],
                  sorts: const [NxSortOption('recent', 'ข้อความล่าสุด'), NxSortOption('unread', 'ยังไม่อ่านมากสุด'), NxSortOption('name', 'ชื่อ ก–ฮ')],
                  onChanged: (q) => setState(() {
                    _query = q.q;
                    _lq = q.copyWith(q: '');
                  }),
                ),
                if (rooms.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text(tr('ไม่พบห้อง'))),
                  ),
                for (final ch in rooms)
                  Builder(
                    builder: (context) {
                      final name = ch['name']?.toString() ?? 'ห้อง';
                      final unread = int.tryParse(ch['unread_count']?.toString() ?? '') ?? 0;
                      final emoji = ch['icon_emoji']?.toString();
                      final isDm = ch['room_type']?.toString() == 'dm';
                      final preview = stripHtmlPreview(ch['last_message']?.toString() ?? ch['description']?.toString() ?? ch['topic']?.toString() ?? '');
                      return DenseCardTile(
                        title: name,
                        subtitle: [if (preview.isNotEmpty) preview, if (!isDm && ch['member_count'] != null) '${ch['member_count']} สมาชิก'].join(' · '),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: emoji != null && emoji.isNotEmpty
                              ? Text(tr(emoji))
                              : Icon(isDm ? NxI.user : NxI.chatCircle, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        trailing: unread > 0 ? Badge(label: Text(tr(unread > 99 ? '99+' : '$unread')), backgroundColor: theme.colorScheme.primary) : null,
                        onTap: () {
                          if (twoPane) {
                            setState(() => _selected = ch);
                            return;
                          }
                          _openRoom(ch);
                        },
                      );
                    },
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

class _GroupCreateSheet extends StatefulWidget {
  const _GroupCreateSheet({required this.users});
  final List<Map<String, dynamic>> users;

  @override
  State<_GroupCreateSheet> createState() => _GroupCreateSheetState();
}

class _GroupCreateSheetState extends State<_GroupCreateSheet> {
  final _name = TextEditingController();
  final Set<String> _picked = {};
  var _needle = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users.where((u) {
      if (_needle.isEmpty) return true;
      return userDisplayName(u).toLowerCase().contains(_needle) || (userEmail(u) ?? '').toLowerCase().contains(_needle);
    }).toList();
    final canCreate = _name.text.trim().isNotEmpty && _picked.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr('ชื่อห้อง'), border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(hintText: tr('ค้นหาสมาชิก'), prefixIcon: Icon(NxI.magnifyingGlass), isDense: true),
                  onChanged: (v) => setState(() => _needle = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final u = filtered[i];
                    final id = u['id']?.toString() ?? '';
                    return CheckboxListTile(
                      value: _picked.contains(id),
                      title: Text(tr(userDisplayName(u))),
                      subtitle: userEmail(u) == null ? null : Text(tr(userEmail(u)!)),
                      onChanged: id.isEmpty ? null : (v) => setState(() => v == true ? _picked.add(id) : _picked.remove(id)),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: canCreate ? () => Navigator.pop(context, (name: _name.text.trim(), ids: _picked.toList())) : null,
                  child: Text(tr('สร้างห้อง (${_picked.length} คน)')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
