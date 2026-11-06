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
import 'chat_room_screen.dart';
import '../../widgets/nx_icons.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  var _revision = 0;
  Map<String, dynamic>? _selected;

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
                    ? {'id': userId, 'name': selected['name'] ?? 'DM'}
                    : room;
                nxPush<void>(context, ChatRoomScreen(room: map));
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
        builder: (context, rooms) {
          final items = ListView(
            padding: const EdgeInsets.all(16),
            children: rooms.map((ch) {
              final name = ch['name']?.toString() ?? 'ห้อง';
              final preview = stripHtmlPreview(
                ch['last_message']?.toString() ?? ch['topic']?.toString() ?? '',
              );
              return DenseCardTile(
                title: name,
                subtitle: preview,
                leading: const CircleAvatar(child: Icon(NxI.tag)),
                onTap: () {
                  if (twoPane) {
                    setState(() => _selected = ch);
                    return;
                  }
                  nxPush<void>(context, ChatRoomScreen(room: ch));
                },
              );
            }).toList(),
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
