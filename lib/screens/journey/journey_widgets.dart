import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_status_stepper.dart';
import '../../widgets/nx_surface_card.dart';

/// Tone colours like the web (`NextActionCard`): primary sky, warning amber,
/// success emerald, danger rose, neutral slate.
Color journeyTone(BuildContext context, String tone) {
  final cs = Theme.of(context).colorScheme;
  return switch (tone) {
    'warning' => const Color(0xFFD97706),
    'success' => const Color(0xFF059669),
    'danger' => const Color(0xFFE11D48),
    'neutral' => cs.onSurfaceVariant,
    _ => cs.primary,
  };
}

IconData journeyActionIcon(String action) => switch (action) {
      'accept' => NxI.check,
      'forward' || 'assign' => NxI.arrowRight,
      'wait' => NxI.clock,
      'resume' => NxI.play,
      'cancel' || 'reject' => NxI.x,
      'close' || 'close_sale' => NxI.flag,
      'reopen' || 'reopen_quotation' => NxI.arrowsClockwise,
      'gen_activity' || 'follow_up' || 'schedule' => NxI.calendarPlus,
      'open_activities' => NxI.calendarCheck,
      'open_signatures' => NxI.penLine,
      'approve' => NxI.shieldCheck,
      'submit_approval' || 'view_approval' => NxI.shieldCheck,
      'send_email' => NxI.envelope,
      'public_link' => NxI.link,
      'duplicate' => NxI.copySimple,
      'revise' => NxI.pencilSimple,
      'edit' || 'edit_quotation' => NxI.pencilSimple,
      'create_job' || 'open_job' => NxI.wrench,
      'open_latest' || 'compare_versions' => NxI.arrowsLeftRight,
      _ => NxI.arrowRight,
    };

/// Journey steps + side chips (cancelled / lost / rejected / revised).
class JourneyStageStrip extends StatelessWidget {
  const JourneyStageStrip({
    super.key,
    required this.steps,
    required this.current,
    this.skipped = const {},
    this.side,
    this.sideLabel,
    this.sideDanger = true,
    this.onPick,
    this.sideChips = const [],
  });

  final List<NxStep> steps;
  final int current;

  /// Step ids drawn as skipped (approval not needed).
  final Set<String> skipped;
  final String? side;
  final String? sideLabel;
  final bool sideDanger;
  final ValueChanged<int>? onPick;

  /// Extra tappable chips on the right (e.g. "ยกเลิก") — `(id, label, onTap)`.
  final List<(String, String, VoidCallback?)> sideChips;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final danger = const Color(0xFFE11D48);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxStatusStepper(
          key: const ValueKey('journey-stages'),
          steps: [
            for (final s in steps)
              NxStep(
                id: s.id,
                label: skipped.contains(s.id) ? '${s.label} · ${tr('ข้าม')}' : s.label,
                color: side != null && sideDanger && steps.indexOf(s) == current ? danger : s.color,
                isDone: s.isDone,
              ),
          ],
          current: current,
          onPick: onPick,
          stepKeyPrefix: 'jstep-',
          doneKeyPrefix: 'jstep-done-',
          padding: EdgeInsets.zero,
        ),
        if (sideLabel != null || sideChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (sideLabel != null)
                  Chip(
                    key: ValueKey('journey-side-$side'),
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(sideDanger ? NxI.warning : NxI.info, size: 16, color: sideDanger ? danger : cs.onSurfaceVariant),
                    label: Text(sideLabel!),
                    side: BorderSide(color: (sideDanger ? danger : cs.outline).withValues(alpha: 0.4)),
                  ),
                for (final c in sideChips)
                  ActionChip(
                    key: ValueKey('journey-chip-${c.$1}'),
                    visualDensity: VisualDensity.compact,
                    label: Text(c.$2),
                    onPressed: c.$3,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "ขั้นถัดไป" card: title + hint + primary button + secondary chips.
class NextActionCard extends StatelessWidget {
  const NextActionCard({super.key, required this.module, required this.next, required this.onAction, this.busy = false});

  final String module;
  final NextAction next;
  final ValueChanged<String> onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = journeyTone(context, next.tone);
    final hint = nextHint(module, next);
    return Container(
      key: ValueKey('next-${next.key}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.withValues(alpha: 0.16), tone.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: tone.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(NxI.lightning, size: 16, color: tone),
              ),
              const SizedBox(width: 8),
              Text(
                tr('ขั้นถัดไป'),
                style: theme.textTheme.labelMedium?.copyWith(color: tone, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(nextTitle(module, next), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(hint, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (next.action != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: ValueKey('next-action-${next.action}'),
                style: FilledButton.styleFrom(
                  backgroundColor: tone,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: busy
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        onAction(next.action!);
                      },
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(journeyActionIcon(next.action!), size: 20),
                label: Text(actionLabel(module, next.action!), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          if (next.secondary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in next.secondary)
                  OutlinedButton.icon(
                    key: ValueKey('next-secondary-$a'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: busy ? null : () => onAction(a),
                    icon: Icon(journeyActionIcon(a), size: 16),
                    label: Text(actionLabel(module, a)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class KpiTile {
  const KpiTile({required this.icon, required this.label, required this.value, this.hint, this.tone = 'neutral', this.onTap, this.id});
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final String tone;
  final VoidCallback? onTap;
  final String? id;
}

/// 2×2 (phone) / 4 (wide) KPI tiles.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});
  final List<KpiTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 640 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in tiles)
            SizedBox(
              width: w,
              child: NxSurfaceCard(
                key: t.id == null ? null : ValueKey('kpi-${t.id}'),
                onTap: t.onTap,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(t.icon, size: 16, color: t.tone == 'neutral' ? cs.onSurfaceVariant : journeyTone(context, t.tone)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: t.tone == 'neutral' || t.tone == 'primary' ? null : journeyTone(context, t.tone),
                      ),
                    ),
                    if (t.hint != null && t.hint!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(t.hint!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Section card with a title row and optional trailing action.
class JourneySection extends StatelessWidget {
  const JourneySection({super.key, required this.title, required this.child, this.icon, this.trailing});
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// One row of a checklist (✓ / ! / i).
class ChecklistRow extends StatelessWidget {
  const ChecklistRow({super.key, required this.label, required this.ok, this.value, this.info = false});
  final String label;
  final bool ok;
  final String? value;
  final bool info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = info ? cs.onSurfaceVariant : (ok ? const Color(0xFF059669) : const Color(0xFFD97706));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(info ? NxI.info : (ok ? NxI.checkCircle : NxI.warningCircle), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (value != null) Text(value!, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Customer → Quotation → Job → Activities trail from `GET /api/links/:m/:id`.
class JourneyTrail extends StatelessWidget {
  const JourneyTrail({super.key, required this.nodes});

  /// `(icon, label, subtitle, current, onTap)`
  final List<(IconData, String, String?, bool, VoidCallback?)> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        for (var i = 0; i < nodes.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: nodes[i].$5,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Column(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: nodes[i].$4 ? cs.primary : cs.surfaceContainerHighest,
                            ),
                            child: Icon(nodes[i].$1, size: 16, color: nodes[i].$4 ? cs.onPrimary : cs.onSurfaceVariant),
                          ),
                          if (i < nodes.length - 1)
                            Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: cs.outlineVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nodes[i].$2, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: nodes[i].$4 ? FontWeight.w800 : FontWeight.w600)),
                            if (nodes[i].$3 != null && nodes[i].$3!.isNotEmpty)
                              Text(nodes[i].$3!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                    if (nodes[i].$5 != null) Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
