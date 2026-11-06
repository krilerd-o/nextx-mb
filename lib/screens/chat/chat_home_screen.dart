import 'dart:async';

import 'package:flutter/material.dart';
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
import '../../widgets/nx_icons.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  var _revision = 0;
  var _query = '';
  Map<String, dynamic>? _selected;
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

  Future<void> _openRoom(Map<String, dynamic> room) async {
    await nxPush<void>(context, ChatRoomScreen(room: room));
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return Scaffold(
      appBar: NxAppHeader(
        title: 'แชททีม',
        actions: [
          IconButton(
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => setState(() => _revision++),
          ),
          IconButton(
            icon: const Icon(NxI.userPlus),
            onPressed: () async {
              final api = context.read<AppConfig>().apiClient;
              List<Map<String, dynamic>> users = const [];
              try {
                users = await api.getUsers(limit: 80);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                }
                return;
              }
              if (!mounted) return;
              final selected = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                builder: (ctx) {
                  final q = TextEditingController();
                  var filtered = users;
                  return StatefulBuilder(
                    builder: (ctx, setSheet) {
                      return SafeArea(
                        child: SizedBox(
                          height: MediaQuery.of(ctx).size.height * 0.7,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: TextField(
                                  controller: q,
                                  decoration: const InputDecoration(
                                    labelText: 'ค้นหาผู้ใช้',
                                    prefixIcon: Icon(NxI.magnifyingGlass),
                                  ),
                                  onChanged: (v) {
                                    final needle = v.trim().toLowerCase();
                                    setSheet(() {
                                      filtered = users.where((u) {
                                        final name = userDisplayName(u).toLowerCase();
                                        final email = (userEmail(u) ?? '').toLowerCase();
                                        final id = (u['id'] ?? '').toString();
                                        return needle.isEmpty ||
                                            name.contains(needle) ||
                                            email.contains(needle) ||
                                            id.contains(needle);
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
                                      title: Text(name),
                                      subtitle: Text(userEmail(u) ?? u['id']?.toString() ?? ''),
                                      onTap: () => Navigator.pop(ctx, u),
                                    );
                                  },
                                ),
                              ),
                            ],
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
                final map = room.isEmpty
                    ? {'id': userId, 'name': userDisplayName(selected)}
                    : room;
                await _openRoom(map);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
        empty: const Center(child: Text('ยังไม่มีห้องแชท')),
        builder: (context, all) {
          final theme = Theme.of(context);
          final needle = _query.trim().toLowerCase();
          final rooms = needle.isEmpty
              ? all
              : all.where((r) => (r['name']?.toString() ?? '').toLowerCase().contains(needle)).toList();
          final items = RefreshIndicator(
            onRefresh: () async => setState(() => _revision++),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'ค้นหาห้อง',
                    prefixIcon: const Icon(NxI.magnifyingGlass),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                if (rooms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('ไม่พบห้อง')),
                  ),
                for (final ch in rooms)
                  Builder(builder: (context) {
                    final name = ch['name']?.toString() ?? 'ห้อง';
                    final unread = int.tryParse(ch['unread_count']?.toString() ?? '') ?? 0;
                    final emoji = ch['icon_emoji']?.toString();
                    final isDm = ch['room_type']?.toString() == 'dm';
                    final preview = stripHtmlPreview(
                      ch['last_message']?.toString() ?? ch['description']?.toString() ?? ch['topic']?.toString() ?? '',
                    );
                    return DenseCardTile(
                      title: name,
                      subtitle: [
                        if (preview.isNotEmpty) preview,
                        if (!isDm && ch['member_count'] != null) '${ch['member_count']} สมาชิก',
                      ].join(' · '),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: emoji != null && emoji.isNotEmpty
                            ? Text(emoji)
                            : Icon(isDm ? NxI.user : NxI.chatCircle, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      trailing: unread > 0
                          ? Badge(
                              label: Text(unread > 99 ? '99+' : '$unread'),
                              backgroundColor: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        if (twoPane) {
                          setState(() => _selected = ch);
                          return;
                        }
                        _openRoom(ch);
                      },
                    );
                  }),
              ],
            ),
          );
          return NxSplitView(
            list: items,
            detail: _selected == null
                ? null
                : ChatRoomScreen(
                    key: ValueKey(_selected!['id']),
                    room: _selected!,
                    embedded: true,
                  ),
          );
        },
      ),
    );
  }
}
