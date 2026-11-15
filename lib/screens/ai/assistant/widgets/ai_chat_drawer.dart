import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../core/i18n.dart';
import '../../../../widgets/isaac_sticker.dart';
import '../../../../widgets/nx_icons.dart';
import '../../../../widgets/nx_skeleton.dart';
import '../ai_assistant_controller.dart';
import 'ai_style.dart';

/// History: search, shortcuts, 📁 folders, 📌 pinned, recent chats by day,
/// archived at the bottom. Swipe a chat → pin / more; long-press → menu;
/// "เลือก" → move many into a folder.
class AiChatDrawer extends StatefulWidget {
  const AiChatDrawer({
    super.key,
    required this.controller,
    required this.docked,
    required this.onNewChat,
    required this.onOpenChat,
    required this.onChatMenu,
    required this.onOpenFolder,
    required this.onFolderMenu,
    required this.onCreateFolder,
    required this.onMoveMany,
    required this.onAgent,
    required this.onNotebook,
    required this.onPrompts,
  });

  final AiAssistantController controller;
  final bool docked;
  final VoidCallback onNewChat;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<AiConversation> onChatMenu;
  final ValueChanged<AiFolder> onOpenFolder;
  final ValueChanged<AiFolder> onFolderMenu;
  final VoidCallback onCreateFolder;
  final ValueChanged<Set<String>> onMoveMany;
  final VoidCallback onAgent;
  final VoidCallback onNotebook;
  final VoidCallback onPrompts;

  @override
  State<AiChatDrawer> createState() => _AiChatDrawerState();
}

class _AiChatDrawerState extends State<AiChatDrawer> {
  late final _search = TextEditingController(text: widget.controller.query);
  Timer? _debounce;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _showArchived = false;

  AiAssistantController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => c.search(v));
  }

  void _toggleSelect(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: c, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = groupAiChats(c.visibleConversations);
    final searching = c.query.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              const IsaacSticker(state: 'idle', size: 32, animate: false),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('ประวัติแชท'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                key: const ValueKey('ai-select-mode'),
                onPressed: () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
                child: Text(tr(_selecting ? 'เสร็จ' : 'เลือก')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ai-chat-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    c.search(v);
                  },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('ล้าง'),
                            icon: const Icon(NxI.x, size: 16),
                            onPressed: () {
                              _search.clear();
                              _debounce?.cancel();
                              c.search('');
                            },
                          ),
                    hintText: tr('ค้นหาแชท'),
                    isDense: true,
                    filled: true,
                    fillColor: AiStyle.tint(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('ai-drawer-new-chat'),
                tooltip: tr('แชทใหม่'),
                onPressed: widget.onNewChat,
                icon: const Icon(AiIcons.newChat, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) c.loadMore();
              return false;
            },
            child: ListView(
              key: const ValueKey('ai-chat-list'),
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (!searching && !_selecting) ...[
                  _Shortcut(icon: NxI.robot, label: 'Agent', hint: 'งาน Agent และงานพื้นหลัง', onTap: widget.onAgent),
                  _Shortcut(
                    key: const ValueKey('ai-open-notebook'),
                    icon: NxI.bookOpen,
                    label: 'Notebook',
                    hint: 'ถามจากแหล่งข้อมูลในสมุดของคุณ',
                    onTap: widget.onNotebook,
                  ),
                  _Shortcut(
                    key: const ValueKey('ai-open-prompts'),
                    icon: AiIcons.slash,
                    label: 'คลังคำสั่ง',
                    hint: 'คำสั่งลัดของคุณและของธุรกิจ',
                    onTap: widget.onPrompts,
                  ),
                  _Header(
                    label: 'โฟลเดอร์',
                    action: IconButton(
                      key: const ValueKey('ai-folder-create'),
                      tooltip: tr('สร้างโฟลเดอร์'),
                      icon: Icon(AiIcons.folderPlus, size: 18, color: cs.primary),
                      onPressed: widget.onCreateFolder,
                    ),
                  ),
                  if (c.folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Text(tr('จัดแชทเป็นกลุ่ม เช่น ลูกค้า ทีม หรือโครงการ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    )
                  else
                    for (final f in c.folders)
                      ListTile(
                        key: ValueKey('ai-folder-${f.id}'),
                        dense: true,
                        minTileHeight: 44,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        leading: Icon(NxI.folder, size: 20, color: AiStyle.folderColor(context, f.color)),
                        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                        trailing: Text('${c.chatCountIn(f.id)}', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        onTap: () => widget.onOpenFolder(f),
                        onLongPress: () => widget.onFolderMenu(f),
                      ),
                ],
                if (c.listLoading && c.conversations.isEmpty)
                  const NxSkeletonList(rows: 5)
                else if (c.visibleConversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        const IsaacSticker(state: 'confused', size: 56, animate: false),
                        const SizedBox(height: 8),
                        Text(tr(searching ? 'ไม่พบแชทที่ค้นหา' : 'ยังไม่มีแชท'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                else
                  for (final g in groups) ...[
                    _Header(label: g.label, icon: g.label == 'ปักหมุด' ? AiIcons.pin : null),
                    for (final chat in g.items) _chatRow(context, chat),
                  ],
                if (c.loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (!searching && !_selecting) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    key: const ValueKey('ai-archived-toggle'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Icon(NxI.archive, size: 18, color: cs.onSurfaceVariant),
                    title: Text(tr('แชทที่เก็บถาวร'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    trailing: Icon(_showArchived ? NxI.caretUp : NxI.caretDown, size: 16),
                    onTap: () {
                      setState(() => _showArchived = !_showArchived);
                      if (_showArchived) c.loadArchived();
                    },
                  ),
                  if (_showArchived)
                    if (c.archivedLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (c.archivedChats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(tr('ไม่มีแชทที่เก็บถาวร'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      )
                    else
                      for (final a in c.archivedChats)
                        ListTile(
                          key: ValueKey('ai-archived-${a.id}'),
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 20, right: 8),
                          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: tr('นำกลับมา'),
                            icon: const Icon(AiIcons.restore, size: 18),
                            onPressed: () => c.setArchived(a.id, false),
                          ),
                          onTap: () => widget.onOpenChat(a.id),
                        ),
                ],
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: AiStyle.of(context),
          child: _selecting && _selected.isNotEmpty
              ? SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: FilledButton.icon(
                      key: const ValueKey('ai-move-many'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                      onPressed: () {
                        final ids = {..._selected};
                        setState(() {
                          _selecting = false;
                          _selected.clear();
                        });
                        widget.onMoveMany(ids);
                      },
                      icon: const Icon(NxI.folder, size: 18),
                      label: Text(tr('ย้ายไปโฟลเดอร์ (${_selected.length})')),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _chatRow(BuildContext context, AiConversation chat) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final folder = c.folderById(chat.projectId);
    final selected = chat.id == c.activeId;
    final tile = ListTile(
      key: ValueKey('ai-chat-${chat.id}'),
      dense: true,
      minTileHeight: 46,
      contentPadding: const EdgeInsets.only(left: 20, right: 4),
      selected: selected && !_selecting,
      selectedTileColor: cs.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: _selecting
          ? Checkbox(value: _selected.contains(chat.id), onChanged: (_) => _toggleSelect(chat.id))
          : folder != null
          ? Icon(NxI.folder, size: 16, color: AiStyle.folderColor(context, folder.color))
          : Icon(chat.starred ? AiIcons.pin : NxI.chatCircle, size: 16, color: chat.starred ? cs.primary : cs.onSurfaceVariant),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: selected ? FontWeight.w600 : null),
      ),
      trailing: _selecting ? null : IconButton(tooltip: tr('ตัวเลือก'), icon: const Icon(NxI.dotsThree, size: 18), onPressed: () => widget.onChatMenu(chat)),
      onTap: _selecting ? () => _toggleSelect(chat.id) : () => widget.onOpenChat(chat.id),
      onLongPress: _selecting ? null : () => widget.onChatMenu(chat),
    );
    if (_selecting) return tile;
    return Dismissible(
      key: ValueKey('ai-swipe-${chat.id}'),
      background: _SwipeBg(icon: chat.starred ? AiIcons.pinOff : AiIcons.pin, label: chat.starred ? 'เลิกปักหมุด' : 'ปักหมุด', color: cs.primary, left: true),
      secondaryBackground: _SwipeBg(icon: NxI.dotsThree, label: 'ตัวเลือก', color: cs.onSurfaceVariant, left: false),
      confirmDismiss: (dir) async {
        HapticFeedback.selectionClick();
        if (dir == DismissDirection.startToEnd) {
          unawaited(c.toggleStar(chat.id, !chat.starred));
        } else {
          widget.onChatMenu(chat);
        }
        return false;
      },
      child: tile,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, this.icon, this.action});
  final String label;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, action == null ? 20 : 8, action == null ? 4 : 0),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: cs.onSurfaceVariant), const SizedBox(width: 6)],
          Expanded(
            child: Text(
              tr(label),
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({super.key, required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 16, color: cs.primary),
      ),
      title: Text(tr(label)),
      subtitle: Text(tr(hint), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.icon, required this.label, required this.color, required this.left});
  final IconData icon;
  final String label;
  final Color color;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.10),
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            tr(label),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
