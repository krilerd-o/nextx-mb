import 'package:flutter/material.dart';

import '../../../core/ai_assistant.dart';
import '../../../core/i18n.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_skeleton.dart';
import 'ai_assistant_controller.dart';
import 'widgets/ai_style.dart';

/// What the folder page asks the chat screen to do.
class AiFolderResult {
  const AiFolderResult.open(String this.chatId) : newChat = false;
  const AiFolderResult.newChat() : chatId = null, newChat = true;
  final String? chatId;
  final bool newChat;
}

/// One folder: its colour and standing instructions, every chat in it, and
/// "แชทใหม่ในโฟลเดอร์นี้".
class AiProjectScreen extends StatefulWidget {
  const AiProjectScreen({super.key, required this.controller, required this.folderId, this.onEdit});
  final AiAssistantController controller;
  final String folderId;

  /// Folder menu (rename / colour / instructions / delete).
  final Future<void> Function()? onEdit;

  @override
  State<AiProjectScreen> createState() => _AiProjectScreenState();
}

class _AiProjectScreenState extends State<AiProjectScreen> {
  List<AiConversation>? _chats;

  AiAssistantController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await c.api.getAiConversations(projectId: widget.folderId, archived: false, limit: 200);
      // Older servers ignore project_id: filter here too.
      final list = [for (final r in rows) AiConversation.fromJson(r)].where((x) => x.projectId == widget.folderId && !x.archived).toList();
      if (mounted) setState(() => _chats = list);
    } catch (_) {
      if (mounted) setState(() => _chats = c.conversations.where((x) => x.projectId == widget.folderId).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final f = c.folderById(widget.folderId);
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        if (f == null) {
          // Deleted from the menu: leave.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        final color = AiStyle.folderColor(context, f.color);
        return Scaffold(
          key: const ValueKey('ai-folder-screen'),
          backgroundColor: AiStyle.canvas(context),
          appBar: AppBar(
            backgroundColor: AiStyle.canvas(context),
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            title: Row(
              children: [
                Icon(NxI.folder, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.onEdit != null)
                IconButton(
                  key: const ValueKey('ai-folder-edit'),
                  tooltip: tr('ตัวเลือกโฟลเดอร์'),
                  icon: const Icon(NxI.dotsThree),
                  onPressed: () async {
                    await widget.onEdit!();
                    await _load();
                  },
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('ai-folder-new-chat'),
            onPressed: () => Navigator.pop(context, const AiFolderResult.newChat()),
            icon: const Icon(AiIcons.newChat),
            label: Text(tr('แชทใหม่ในโฟลเดอร์นี้')),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AiStyle.gutter, 8, AiStyle.gutter, 96),
              children: [
                Container(
                  key: const ValueKey('ai-folder-instructions-card'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AiStyle.surface(context),
                    borderRadius: BorderRadius.circular(AiStyle.cardRadius),
                    boxShadow: AiStyle.softShadow(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AiIcons.wand, size: 18, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(tr('คำสั่งประจำโฟลเดอร์'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (f.instructions ?? '').trim().isEmpty
                            ? tr('ยังไม่มี — ตั้งคำสั่งให้ไอแซคใช้ในทุกแชทของโฟลเดอร์นี้ เช่น โทนภาษา หรือข้อมูลลูกค้าที่ต้องอ้างอิง')
                            : f.instructions!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: (f.instructions ?? '').trim().isEmpty ? cs.onSurfaceVariant : null, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    tr('แชทในโฟลเดอร์ (${_chats?.length ?? '…'})'),
                    style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_chats == null)
                  const NxSkeletonList(rows: 4)
                else if (_chats!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      tr('ยังไม่มีแชทในโฟลเดอร์นี้'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  Material(
                    color: AiStyle.surface(context),
                    borderRadius: BorderRadius.circular(AiStyle.cardRadius),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, chat) in _chats!.indexed) ...[
                          if (i > 0) Divider(height: 1, indent: 52, color: cs.outlineVariant.withValues(alpha: 0.4)),
                          ListTile(
                            key: ValueKey('ai-folder-chat-${chat.id}'),
                            minTileHeight: 52,
                            leading: Icon(chat.starred ? AiIcons.pin : NxI.chatCircle, size: 18, color: chat.starred ? cs.primary : cs.onSurfaceVariant),
                            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                            onTap: () => Navigator.pop(context, AiFolderResult.open(chat.id)),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
