import 'package:flutter/material.dart';

import '../core/entity_display.dart';
import 'nx_avatar.dart';
import 'nx_surface_card.dart';
import 'nx_icons.dart';

class NxEntityRow extends StatelessWidget {
  const NxEntityRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          NxAvatar(label: title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (meta != null && meta!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              meta!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else
            Icon(NxI.caretRight, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  factory NxEntityRow.fromRow(
    Map<String, dynamic> row, {
    String? module,
    VoidCallback? onTap,
  }) {
    return NxEntityRow(
      title: entityTitle(row, module: module),
      subtitle: entitySubtitle(row, module: module),
      meta: entityWhen(row) ?? entityStatus(row),
      onTap: onTap,
    );
  }
}
