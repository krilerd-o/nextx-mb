import 'package:flutter/material.dart';

import '../../core/html_display.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_icons.dart';

/// คีย์คอลัมน์จากสถานะบอร์ดจริง (keys ของ [grouped])
List<String> kanbanColumnKeys(Map<String, List<Map<String, dynamic>>> grouped) {
  if (grouped.isNotEmpty) return grouped.keys.toList();
  return const ['อื่นๆ'];
}

String _statusOf(Map<String, dynamic> row) {
  final st = row['status'] ?? row['state'] ?? 'อื่นๆ';
  return st.toString();
}

String _taskTitle(Map<String, dynamic> row) {
  final t = row['title'] ?? row['name'] ?? row['subject'];
  if (t != null) {
    final s = stripHtmlPreview(t.toString(), maxLen: 120);
    if (s.isNotEmpty) return s;
  }
  return 'Task ${row['id'] ?? '?'}';
}

/// Board แนวนอน (ได้แรงบันดาลใจจาก UX แบบ Kanban ทั่วไป — ไม่ใช่โค้ดจาก AppFlowy)
class WorkspaceKanbanBoard extends StatelessWidget {
  const WorkspaceKanbanBoard({
    super.key,
    required this.grouped,
    required this.onTaskTap,
    required this.onChangeStatus,
  });

  final Map<String, List<Map<String, dynamic>>> grouped;
  final void Function(Map<String, dynamic> row) onTaskTap;
  final Future<void> Function(BuildContext context, Map<String, dynamic> row, String newStatus) onChangeStatus;

  static const double _columnWidth = 300;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = kanbanColumnKeys(grouped);

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: keys.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final status = keys[index];
            final rows = grouped[status] ?? [];
            return SizedBox(
              width: _columnWidth,
              child: DragTarget<Map<String, dynamic>>(
                onAcceptWithDetails: (DragTargetDetails<Map<String, dynamic>> details) {
                  final row = details.data;
                  if (_statusOf(row) != status) {
                    onChangeStatus(context, row, status);
                  }
                },
                builder: (context, candidate, rejected) {
                  final highlight = candidate.isNotEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: highlight ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.3),
                        width: highlight ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  status,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${rows.length}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: rows.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      'ลากการ์ดมาวาง',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                                  itemCount: rows.length,
                                  itemBuilder: (context, i) {
                                    final row = rows[i];
                                    final current = _statusOf(row);
                                    final card = _TaskKanbanCard(
                                      title: _taskTitle(row),
                                      subtitle: _shortSubtitle(row['description']?.toString()),
                                      onTap: () => onTaskTap(row),
                                      menu: PopupMenuButton<String>(
                                        tooltip: 'เปลี่ยนสถานะ',
                                        icon: const Icon(NxI.dotsThreeVertical, size: 20),
                                        onSelected: (v) => onChangeStatus(context, row, v),
                                        itemBuilder: (ctx) => [
                                          for (final opt in grouped.keys)
                                            PopupMenuItem<String>(
                                              value: opt,
                                              child: Row(
                                                children: [
                                                  if (opt == current)
                                                    Icon(NxI.check, size: 18, color: Theme.of(ctx).colorScheme.primary)
                                                  else
                                                    const SizedBox(width: 18),
                                                  const SizedBox(width: 8),
                                                  Text(opt),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                    return LongPressDraggable<Map<String, dynamic>>(
                                      data: row,
                                      feedback: Material(
                                        elevation: 8,
                                        borderRadius: BorderRadius.circular(12),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 276),
                                          child: ListTile(
                                            title: Text(
                                              _taskTitle(row),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            tileColor: theme.colorScheme.surfaceContainerHighest,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.35,
                                        child: card,
                                      ),
                                      child: card,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

String? _shortSubtitle(String? d) {
  final s = stripHtmlPreview(d, maxLen: 80);
  return s.isEmpty ? null : s;
}

class _TaskKanbanCard extends StatelessWidget {
  const _TaskKanbanCard({
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.menu,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DenseCardTile(
        title: title,
        subtitle: subtitle,
        trailing: menu,
        onTap: onTap,
      ),
    );
  }
}
