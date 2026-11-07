import 'package:flutter/material.dart';

import '../core/card_layout.dart';
import '../core/entity_display.dart';
import '../core/i18n.dart';
import 'nx_icons.dart';
import 'nx_surface_card.dart';

/// List card laid out by the user's [CardLayout]: number/label on top, status
/// badge, title, subtitle, then a footer with date, person and amount.
class NxEntityCard extends StatelessWidget {
  const NxEntityCard({
    super.key,
    required this.row,
    required this.layout,
    required this.fields,
    this.module,
    this.onTap,
    this.onLongPress,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Map<String, dynamic> row;
  final CardLayout layout;
  final CardFieldContext fields;
  final String? module;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets margin;

  static const _palette = [
    Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B),
    Color(0xFFF43F5E), Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF97316),
  ];

  Color? _hex(dynamic raw) {
    final s = raw?.toString().replaceAll('#', '') ?? '';
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// Status colour: the picklist's own colour, else a few well-known words.
  Color _badgeColor(ColorScheme cs, String field, String raw) {
    final c = _hex(fields.option(field, raw)?['color']);
    if (c != null) return c;
    final v = raw.toLowerCase();
    if (RegExp(r'won|approved|accept|done|complete|closed won|qualified|paid|อนุมัติ|สำเร็จ|เสร็จ').hasMatch(v)) {
      return const Color(0xFF10B981);
    }
    if (RegExp(r'lost|reject|cancel|expired|unqualified|ยกเลิก|ไม่อนุมัติ').hasMatch(v)) return cs.error;
    if (RegExp(r'draft|new|ร่าง|ใหม่').hasMatch(v)) return cs.onSurfaceVariant;
    return const Color(0xFFF59E0B);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final top = fields.text(row, layout.top);
    var title = fields.text(row, layout.title);
    if (title.isEmpty) title = entityTitle(row, module: module);
    final sub = fields.text(row, layout.subtitle);
    final showSub = sub.isNotEmpty &&
        switch (layout.subtitleMode) {
          'never' => false,
          'always' => true,
          _ => sub != title,
        };
    final date = fields.text(row, layout.date);
    final person = fields.text(row, layout.person);
    final amount = fields.text(row, layout.amount, money: true);
    final badgeRaw = layout.badge == null ? '' : '${row[layout.badge] ?? ''}';
    final badge = fields.text(row, layout.badge);
    final hasFooter = date.isNotEmpty || person.isNotEmpty || amount.isNotEmpty;

    return NxSurfaceCard(
      margin: margin,
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (top.isNotEmpty)
                      Text(
                        top,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (showSub)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${fields.label(layout.subtitle!)} · ',
                              style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                            ),
                            TextSpan(text: sub),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (badge.isNotEmpty) ...[
                const SizedBox(width: 8),
                () {
                  final c = _badgeColor(cs, layout.badge!, badgeRaw);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700),
                    ),
                  );
                }(),
              ],
            ],
          ),
          if (hasFooter) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 0.5, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (date.isNotEmpty)
                        Row(children: [
                          Icon(NxI.calendarBlank, size: 15, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                          ),
                        ]),
                      if (person.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: date.isNotEmpty ? 6 : 0),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: _palette[person.hashCode.abs() % _palette.length].withValues(alpha: 0.18),
                              child: Text(
                                person.characters.first,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _palette[person.hashCode.abs() % _palette.length],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(person, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
                if (amount.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fields.label(layout.amount!),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        amount,
                        style: theme.textTheme.titleLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder used in previews when there is no row yet.
Map<String, dynamic> cardSampleRow(CardLayout l, CardFieldContext f) => {
      for (final s in CardLayout.slots)
        if (l.slot(s) != null) l.slot(s)!: s == 'amount' ? 3600 : tr(f.label(l.slot(s)!)),
    };
