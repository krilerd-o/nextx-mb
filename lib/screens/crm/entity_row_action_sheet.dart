import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'entity_record_actions.dart';

/// Commands offered when a list row is long-pressed.
enum EntityRowAction { convert, status, comment, edit, duplicate, delete, select }

/// Long-press menu for a record: a big-icon grid (status, comment, edit,
/// duplicate, delete, multi-select) like the web row menu. Returns the pick.
Future<EntityRowAction?> showEntityRowActionSheet(
  BuildContext context, {
  required String module,
  required String moduleLabel,
  required Map<String, dynamic> row,
  String? statusKey,
  String? statusLabel,
  String? statusColor,
  int? commentCount,
}) {
  HapticFeedback.mediumImpact();
  final perms = EntityRowPerms.of(module, row);
  return showAppBottomSheet<EntityRowAction>(
    context: context,
    title: moduleLabel,
    child: EntityRowActionGrid(
      module: module,
      row: row,
      perms: perms,
      hasStatus: statusKey != null,
      statusLabel: statusLabel,
      statusColor: statusColor,
      commentCount: commentCount,
    ),
  );
}

class EntityRowActionGrid extends StatelessWidget {
  const EntityRowActionGrid({
    super.key,
    required this.module,
    required this.row,
    required this.perms,
    required this.hasStatus,
    this.statusLabel,
    this.statusColor,
    this.commentCount,
  });

  final String module;
  final Map<String, dynamic> row;
  final EntityRowPerms perms;
  final bool hasStatus;
  final String? statusLabel;
  final String? statusColor;
  final int? commentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = entityTitle(row, module: module);
    final no = '${row['${module}_no'] ?? row['no'] ?? ''}'.trim();
    final status = statusLabel;
    final sc = EntityRecordActions.statusColor(cs, status ?? '', statusColor);
    final caseLocked = module == 'case' && hasStatus;
    final tiles = <Widget>[
      if (module == 'lead' && perms.canEdit && !EntityRowPerms.leadLocked(row))
        _ActionTile(
          key: const ValueKey('row-act-convert'),
          icon: NxI.userCheck,
          label: 'แปลงเป็นลูกค้า',
          color: const Color(0xFF16A34A),
          onTap: () => Navigator.pop(context, EntityRowAction.convert),
        ),
      if (hasStatus && (perms.canStatus || caseLocked))
        _ActionTile(
          key: const ValueKey('row-act-status'),
          icon: NxI.flag,
          label: 'ปรับสถานะ',
          color: status == null ? cs.primary : sc,
          disabledHint: caseLocked ? 'เปลี่ยนสถานะเคสได้ในหน้าเคส' : null,
          onTap: perms.canStatus ? () => Navigator.pop(context, EntityRowAction.status) : null,
        ),
      _ActionTile(
        key: const ValueKey('row-act-comment'),
        icon: NxI.chatCircle,
        label: 'อัปเดตคอมเมนต์',
        badge: (commentCount ?? 0) > 0 ? '$commentCount' : null,
        color: const Color(0xFF0EA5E9),
        onTap: () => Navigator.pop(context, EntityRowAction.comment),
      ),
      if (perms.canEdit) ...[
        _ActionTile(
          key: const ValueKey('row-act-edit'),
          icon: NxI.pencilSimple,
          label: 'แก้ไข',
          color: const Color(0xFF6366F1),
          onTap: () => Navigator.pop(context, EntityRowAction.edit),
        ),
        _ActionTile(
          key: const ValueKey('row-act-duplicate'),
          icon: NxI.copySimple,
          label: 'ทำซ้ำ',
          color: const Color(0xFF14B8A6),
          onTap: () => Navigator.pop(context, EntityRowAction.duplicate),
        ),
      ],
      if (perms.canDelete)
        _ActionTile(
          key: const ValueKey('row-act-delete'),
          icon: NxI.trash,
          label: 'ลบ',
          color: cs.error,
          onTap: () => Navigator.pop(context, EntityRowAction.delete),
        ),
      _ActionTile(
        key: const ValueKey('row-act-select'),
        icon: NxI.checks,
        label: 'เลือกหลายรายการ',
        color: cs.onSurfaceVariant,
        onTap: () => Navigator.pop(context, EntityRowAction.select),
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final cols = wide ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Which record: title + number + current status.
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const ValueKey('row-act-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (no.isNotEmpty || status != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (no.isNotEmpty)
                      Text(no, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    if (status != null && status.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: sc.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tr(status),
                          style: theme.textTheme.labelMedium?.copyWith(color: sc, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 10.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
    this.disabledHint,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onTap != null;
    final c = enabled ? color : cs.onSurfaceVariant.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tr(label),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: theme.brightness == Brightness.dark ? 0.55 : 0.6),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!();
                }
              : () {
                  if (disabledHint == null) return;
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(disabledHint!))));
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Icon(icon, size: 26, color: c),
                    ),
                    if (badge != null)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tr(label),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                if (!enabled && disabledHint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr(disabledHint!),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
