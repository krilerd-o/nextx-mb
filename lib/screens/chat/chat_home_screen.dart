import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
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
              final id = TextEditingController();
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('แชทส่วนตัว'),
                  content: TextField(
                    controller: id,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'รหัสผู้ใช้'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('เปิด')),
                  ],
                ),
              );
              final userId = id.text.trim();
              id.dispose();
              if (ok == true && userId.isNotEmpty) {
                try {
                  final room = await context.read<AppConfig>().apiClient.createChatDm(userId);
                  if (!mounted) return;
                  final map = room.isEmpty ? {'id': userId, 'name': 'DM'} : room;
                  nxPush<void>(context, ChatRoomScreen(room: map));
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                  }
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
