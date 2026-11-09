import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/chat_format.dart';
import '../../../core/i18n.dart';
import '../../../services/api_client.dart';
import '../../../widgets/nx_avatar.dart';
import '../../../widgets/nx_emoji_picker.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_overlay_panel.dart';

const chatQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// What the user picked in the long-press sheet.
sealed class ChatAction {
  const ChatAction();
}

class ChatReact extends ChatAction {
  const ChatReact(this.emoji);
  final String emoji;
}

enum ChatActionKind { reply, thread, copy, forward, pin, unpin, save, edit, delete }

class ChatSimpleAction extends ChatAction {
  const ChatSimpleAction(this.kind);
  final ChatActionKind kind;
}

/// Long-press sheet: quick reactions (+ all emoji), reply, thread, copy, forward, pin, save, edit, delete.
Future<ChatAction?> showChatMessageActions(
  BuildContext context, {
  required bool mine,
  required bool pinned,
  required bool hasText,
  bool canThread = true,
}) {
  return showNxBlurPanel<ChatAction>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget item(ChatActionKind k, IconData icon, String label, {Color? color}) => ListTile(
            key: ValueKey('chat-act-${k.name}'),
            dense: true,
            leading: Icon(icon, color: color),
            title: Text(tr(label), style: TextStyle(color: color)),
            onTap: () => Navigator.pop(ctx, ChatSimpleAction(k)),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in chatQuickReactions)
                InkResponse(
                  key: ValueKey('chat-react-$e'),
                  radius: 24,
                  onTap: () => Navigator.pop(ctx, ChatReact(e)),
                  child: Padding(padding: const EdgeInsets.all(5), child: Text(e, style: const TextStyle(fontSize: 26))),
                ),
              InkResponse(
                key: const ValueKey('chat-react-more'),
                radius: 24,
                onTap: () async {
                  final e = await showNxEmojiPicker(ctx);
                  if (e != null && ctx.mounted) Navigator.pop(ctx, ChatReact(e));
                },
                child: CircleAvatar(radius: 17, backgroundColor: cs.surfaceContainerHighest, child: Icon(NxI.plus, size: 18, color: cs.onSurface)),
              ),
            ]),
          ),
          const Divider(height: 12),
          item(ChatActionKind.reply, NxI.reply, 'ตอบกลับ'),
          if (canThread) item(ChatActionKind.thread, NxI.thread, 'ตอบในเธรด'),
          item(ChatActionKind.forward, NxI.forward, 'ส่งต่อ'),
          if (hasText) item(ChatActionKind.copy, NxI.copySimple, 'คัดลอกข้อความ'),
          item(pinned ? ChatActionKind.unpin : ChatActionKind.pin, NxI.pushPin, pinned ? 'เลิกปักหมุด' : 'ปักหมุด'),
          item(ChatActionKind.save, NxI.bookmark, 'บันทึกไว้ดูภายหลัง'),
          if (mine && hasText) item(ChatActionKind.edit, NxI.pencilSimple, 'แก้ไข'),
          if (mine) item(ChatActionKind.delete, NxI.trash, 'ลบข้อความ', color: cs.error),
        ]),
      );
    },
  );
}

/// Pick rooms (search) and add an optional note, then forward. Returns how many rooms got it.
Future<int?> showChatForwardSheet(
  BuildContext context, {
  required String fromRoomId,
  required Map<String, dynamic> message,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (ctx) => _ForwardSheet(fromRoomId: fromRoomId, message: message),
  );
}

class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet({required this.fromRoomId, required this.message});
  final String fromRoomId;
  final Map<String, dynamic> message;

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  late final Future<List<Map<String, dynamic>>> _rooms = context.read<AppConfig>().apiClient.getChatRooms();
  final _picked = <String>{};
  final _note = TextEditingController();
  var _q = '';
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final out = await context.read<AppConfig>().apiClient.forwardChatMessage(
            widget.fromRoomId,
            '${widget.message['id']}',
            _picked.toList(),
            comment: _note.text,
          );
      if (!mounted) return;
      Navigator.pop(context, (out['sent'] is List ? (out['sent'] as List).length : _picked.length));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = chatPlainText(widget.message['body']?.toString());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text(tr('ส่งต่อข้อความ'), style: Theme.of(context).textTheme.titleMedium)),
                if (_picked.isNotEmpty) Text(tr('เลือก ${_picked.length} ห้อง'), style: TextStyle(color: cs.primary)),
              ]),
            ),
            if (preview.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                decoration: InputDecoration(isDense: true, hintText: tr('ค้นหาห้องหรือคน'), prefixIcon: const Icon(NxI.magnifyingGlass)),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _rooms,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final rooms = chatSortRooms(snap.data!).where((r) => _q.isEmpty || chatRoomTitle(r).toLowerCase().contains(_q)).toList();
                  return ListView.builder(
                    itemCount: rooms.length,
                    itemBuilder: (_, i) {
                      final r = rooms[i];
                      final id = '${r['id']}';
                      final on = _picked.contains(id);
                      return CheckboxListTile(
                        key: ValueKey('chat-forward-room-$id'),
                        value: on,
                        onChanged: (_) => setState(() => on ? _picked.remove(id) : _picked.add(id)),
                        secondary: NxAvatar(label: chatRoomTitle(r), size: 36),
                        title: Text(chatRoomTitle(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(tr(chatRoomIsDm(r) ? 'แชทส่วนตัว' : '${r['member_count'] ?? 0} สมาชิก')),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    decoration: InputDecoration(isDense: true, hintText: tr('เพิ่มข้อความ (ไม่บังคับ)')),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('chat-forward-send'),
                  onPressed: _picked.isEmpty || _busy ? null : _send,
                  child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('ส่งต่อ')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Delete confirmation.
Future<bool> confirmChatDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ลบข้อความนี้?')),
      content: Text(tr('ทุกคนในห้องจะเห็นว่า "ข้อความนี้ถูกลบแล้ว"')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
        FilledButton(
          key: const ValueKey('chat-delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('ลบข้อความ')),
        ),
      ],
    ),
  );
  return ok == true;
}
