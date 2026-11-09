import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/chat_format.dart';
import '../../../core/entity_display.dart';
import '../../../core/i18n.dart';
import '../../../services/api_client.dart';
import '../../../widgets/nx_app_header.dart';
import '../../../widgets/nx_attachments.dart' show openNxImageViewer;
import '../../../widgets/nx_avatar.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_media.dart';
import 'chat_attachments.dart';
import 'chat_message_bubble.dart';

/// Room details: members (add), photos & videos, files, mute / star.
class ChatRoomInfoScreen extends StatefulWidget {
  const ChatRoomInfoScreen({super.key, required this.room, this.onChanged});
  final Map<String, dynamic> room;
  final void Function(Map<String, dynamic> room)? onChanged;

  @override
  State<ChatRoomInfoScreen> createState() => _ChatRoomInfoScreenState();
}

class _ChatRoomInfoScreenState extends State<ChatRoomInfoScreen> {
  late Map<String, dynamic> _room = {...widget.room};
  late Future<List<Map<String, dynamic>>> _members = _api.getChatRoomMembers(_id);
  late final Future<List<Map<String, dynamic>>> _files = _api.getChatRoomFiles(_id).catchError((Object _) => <Map<String, dynamic>>[]);

  ApiClient get _api => context.read<AppConfig>().apiClient;
  String get _id => '${widget.room['id']}';

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(t))));

  Future<void> _toggle(String key) async {
    final next = !(_room[key] == true);
    try {
      if (key == 'muted') {
        await _api.setChatRoomMuted(_id, next);
      } else {
        await _api.setChatRoomStarred(_id, next);
      }
      setState(() => _room = {..._room, key: next});
      widget.onChanged?.call(_room);
      _snack(key == 'muted' ? (next ? 'ปิดเสียงแจ้งเตือนแล้ว (ยกเว้นเมื่อมีคน @ถึงคุณ)' : 'เปิดเสียงแจ้งเตือนแล้ว') : (next ? 'ติดดาวแล้ว' : 'เลิกติดดาวแล้ว'));
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _addMember(List<Map<String, dynamic>> current) async {
    List<Map<String, dynamic>> users;
    try {
      users = await _api.getUsers(limit: 200);
    } catch (e) {
      _snack(formatApiError(e));
      return;
    }
    if (!mounted) return;
    final inRoom = current.map((m) => '${m['user_id']}').toSet();
    final pick = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: ListView(children: [
            for (final u in users.where((u) => !inRoom.contains('${u['id']}')))
              ListTile(
                leading: NxAvatar(label: userDisplayName(u), size: 34),
                title: Text(userDisplayName(u)),
                subtitle: Text(userEmail(u) ?? ''),
                onTap: () => Navigator.pop(ctx, u),
              ),
          ]),
        ),
      ),
    );
    if (pick == null) return;
    try {
      await _api.addChatRoomMember(_id, '${pick['id']}');
      setState(() => _members = _api.getChatRoomMembers(_id));
      _snack('เพิ่มสมาชิกแล้ว');
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dm = chatRoomIsDm(_room);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: NxAppHeader(title: tr(dm ? 'ข้อมูลแชท' : 'ข้อมูลห้อง')),
        body: NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverToBoxAdapter(
              child: Column(children: [
                const SizedBox(height: 16),
                NxAvatar(label: chatRoomTitle(_room), size: 76),
                const SizedBox(height: 10),
                Text(chatRoomTitle(_room), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                if ((_room['description']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(_room['description'].toString(), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _RoundAction(
                    key: const ValueKey('room-info-mute'),
                    icon: _room['muted'] == true ? NxI.bellSlash : NxI.bell,
                    label: _room['muted'] == true ? 'เปิดเสียง' : 'ปิดเสียง',
                    onTap: () => _toggle('muted'),
                  ),
                  const SizedBox(width: 18),
                  _RoundAction(
                    key: const ValueKey('room-info-star'),
                    icon: _room['starred'] == true ? NxI.starFill : NxI.star,
                    label: _room['starred'] == true ? 'เลิกติดดาว' : 'ติดดาว',
                    onTap: () => _toggle('starred'),
                  ),
                ]),
                const SizedBox(height: 8),
                TabBar(tabs: [Tab(text: tr('สมาชิก')), Tab(text: tr('รูปและวิดีโอ')), Tab(text: tr('ไฟล์'))]),
              ]),
            ),
          ],
          body: TabBarView(children: [
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _members,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                return ListView(children: [
                  if (!dm && _room['is_general'] != true)
                    ListTile(
                      leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(NxI.userPlus, color: cs.onPrimaryContainer)),
                      title: Text(tr('เพิ่มสมาชิก')),
                      onTap: () => _addMember(list),
                    ),
                  for (final m in list)
                    ListTile(
                      leading: NxAvatar(label: chatSenderName(m), size: 36),
                      title: Text(chatSenderName(m)),
                      subtitle: (m['role']?.toString() ?? '') == 'admin' || (m['role']?.toString() ?? '') == 'owner' ? Text(tr('ผู้ดูแลห้อง')) : null,
                    ),
                ]);
              },
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _files,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final media = snap.data!.where((f) {
                  final k = chatAttachmentKind(f['mime_type']?.toString(), f['file_name']?.toString());
                  return k == 'image' || k == 'video';
                }).toList();
                if (media.isEmpty) return Center(child: Text(tr('ยังไม่มีรูปหรือวิดีโอ')));
                final images = media.where((f) => chatAttachmentKind(f['mime_type']?.toString(), f['file_name']?.toString()) == 'image').toList();
                final urls = [for (final f in images) _api.chatFileUrl(f['file_path']?.toString())];
                return GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                  itemCount: media.length,
                  itemBuilder: (_, i) {
                    final f = media[i];
                    final video = chatAttachmentKind(f['mime_type']?.toString(), f['file_name']?.toString()) == 'video';
                    final url = _api.chatFileUrl(f['file_path']?.toString());
                    return GestureDetector(
                      onTap: () => video ? openNxVideoPlayer(context, url, name: f['file_name']?.toString()) : openNxImageViewer(context, urls, images.indexOf(f)),
                      child: video
                          ? Container(color: Colors.black87, child: const Center(child: Icon(NxI.play, color: Colors.white)))
                          : ChatNetworkImage(urls: _api.chatFileUrls(f['file_path']?.toString())),
                    );
                  },
                );
              },
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _files,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.where((f) {
                  final k = chatAttachmentKind(f['mime_type']?.toString(), f['file_name']?.toString());
                  return k == 'file' || k == 'audio';
                }).toList();
                if (docs.isEmpty) return Center(child: Text(tr('ยังไม่มีไฟล์')));
                return ListView(padding: const EdgeInsets.all(12), children: [
                  for (final f in docs)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Align(alignment: Alignment.centerLeft, child: ChatFileCard(attachment: f, mine: false))),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          CircleAvatar(radius: 22, backgroundColor: cs.surfaceContainerHighest, child: Icon(icon, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(tr(label), style: Theme.of(context).textTheme.labelMedium),
        ]),
      ),
    );
  }
}
