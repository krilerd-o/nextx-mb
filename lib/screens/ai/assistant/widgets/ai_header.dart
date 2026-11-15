import 'package:flutter/material.dart';

import '../../../../core/i18n.dart';
import '../../../../widgets/nx_icons.dart';
import 'ai_style.dart';

/// Top bar with three controls: ☰ history · title ▾ (chat menu) · ✎ new chat.
/// Back shows only when the screen was pushed (not as a tab).
class AiHeader extends StatelessWidget {
  const AiHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.folderColor,
    required this.showHistoryButton,
    required this.onHistory,
    required this.onNewChat,
    this.onTitle,
  });

  final String title;

  /// Folder name of the open chat, if any.
  final String? subtitle;
  final Color? folderColor;
  final bool showHistoryButton;
  final VoidCallback onHistory;
  final VoidCallback onNewChat;

  /// Opens the chat menu (null for a new, unsaved chat).
  final VoidCallback? onTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            if (canPop) IconButton(tooltip: tr('กลับ'), icon: const Icon(NxI.arrowLeft, size: 22), onPressed: () => Navigator.of(context).maybePop()),
            if (showHistoryButton)
              IconButton(key: const ValueKey('ai-open-chats'), tooltip: tr('ประวัติแชท'), icon: const Icon(NxI.listBullets, size: 22), onPressed: onHistory),
            if (!canPop && !showHistoryButton) const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                button: onTitle != null,
                label: onTitle != null ? tr('ตัวเลือกแชท') : null,
                child: InkWell(
                  key: const ValueKey('ai-title'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTitle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
                              ),
                            ),
                            if (onTitle != null) ...[const SizedBox(width: 2), Icon(NxI.caretDown, size: 16, color: cs.onSurfaceVariant)],
                          ],
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Row(
                            children: [
                              Icon(NxI.folder, size: 12, color: folderColor ?? cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('ai-new-chat'),
              tooltip: tr('แชทใหม่'),
              icon: Icon(AiIcons.newChat, size: 22, color: cs.onSurface),
              onPressed: onNewChat,
            ),
          ],
        ),
      ),
    );
  }
}
