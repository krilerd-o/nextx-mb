import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/doc_form/job_form_rules.dart';
import '../../core/i18n.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_icons.dart';

/// Building blocks of the job step form: pick tiles / rows that open the
/// search pages, folded sections, the case / contract and customer / site
/// cards and the priority segments.

/// Big "open the picker" tile (empty state of a pick).
class JobPickTile extends StatelessWidget {
  const JobPickTile({super.key, required this.icon, required this.title, required this.subtitle, this.onTap, this.error = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = error ? cs.error : cs.primary;
    return Material(
      color: c.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.withValues(alpha: 0.45), width: 1.2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle), child: Icon(icon, color: c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c)),
                Text(tr(subtitle), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(NxI.caretRight, color: c),
          ]),
        ),
      ),
    );
  }
}

/// One tappable "label / value ›" row that opens a picker.
class JobFieldRow extends StatelessWidget {
  const JobFieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.muted = false,
    this.hint,
    this.valueKey,
    this.required = false,
    this.error,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool muted;
  final String? hint;
  final Key? valueKey;
  final bool required;
  final String? error;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // The standard field box (same as the Lead / entity form pickers):
    // label on the border, icon inside, caret when it opens a picker.
    final caret = onTap == null ? null : Icon(NxI.caretDown, size: 20, color: cs.onSurfaceVariant);
    return NxOutlinedTapField(
      label: label,
      required: required,
      isEmpty: false,
      multiLine: true,
      errorText: error,
      onTap: onTap,
      prefixIcon: Icon(icon),
      suffixIcon: trailing == null ? caret : Row(mainAxisSize: MainAxisSize.min, children: [trailing!, ?caret]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(value, key: valueKey, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(color: muted ? cs.onSurfaceVariant : null)),
        if (hint != null && hint!.isNotEmpty) Text(hint!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Section card whose body folds away behind a one-line summary.
class JobCollapsible extends StatelessWidget {
  const JobCollapsible({super.key, required this.title, required this.icon, required this.color, required this.summary, required this.open, required this.onToggle, required this.child, this.toggleKey});
  final String title;
  final IconData icon;
  final Color color;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: dark ? cs.surfaceContainerHigh : cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: toggleKey,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(tr(summary), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(NxI.caretDown, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: child),
        ]),
      ),
    );
  }
}

/// Compact card of the linked case / contract: number · title, customer,
/// status, due / end; เปลี่ยน and ✕ (unless it is the parent).
class JobLinkCard extends StatelessWidget {
  const JobLinkCard({super.key, required this.module, required this.view, this.onChange, this.onClear, this.parent = false});
  final String module;
  final JobLinkView view;
  final VoidCallback? onChange;
  final VoidCallback? onClear;
  final bool parent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = module == 'case' ? const Color(0xFFF97316) : const Color(0xFF0EA5E9);
    final statusColor = view.closed ? const Color(0xFF64748B) : const Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: tint.withValues(alpha: 0.35))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Icon(module == 'case' ? NxI.lifeBuoy : NxI.fileText, size: 19, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(module == 'case' ? (parent ? 'สร้างจากเคส' : 'เคส') : (parent ? 'สร้างจากสัญญาบริการ' : 'สัญญาบริการ')),
                style: theme.textTheme.labelSmall?.copyWith(color: tint, fontWeight: FontWeight.w800)),
            Text(view.heading.isEmpty ? '—' : view.heading, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
            if (view.customer.isNotEmpty) Text(view.customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (view.status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(tr(view.status), style: theme.textTheme.labelSmall?.copyWith(color: theme.brightness == Brightness.dark ? Color.lerp(statusColor, Colors.white, 0.35) : statusColor, fontWeight: FontWeight.w700)),
                ),
              if (view.extra.isNotEmpty) Text(tr(view.extra), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
        if (onChange != null) IconButton(key: ValueKey('job-${module == 'case' ? 'case' : 'contract'}-change'), tooltip: tr('เปลี่ยน'), visualDensity: VisualDensity.compact, onPressed: onChange, icon: Icon(NxI.arrowsLeftRight, size: 18, color: cs.onSurfaceVariant)),
        if (onClear != null) IconButton(key: ValueKey('job-${module == 'case' ? 'case' : 'contract'}-clear'), tooltip: tr('เลิกเชื่อม'), visualDensity: VisualDensity.compact, onPressed: onClear, icon: Icon(NxI.x, size: 18, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Selected customer: name + kind, phone / e-mail / address, เปลี่ยน and ✕.
class JobCustomerCard extends StatelessWidget {
  const JobCustomerCard({super.key, required this.name, required this.kind, this.lines = const [], this.onChange, this.onClear});
  final String name;
  final String kind;
  final List<(IconData, String)> lines;
  final VoidCallback? onChange;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('job-customer-card'),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.primary.withValues(alpha: 0.28))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
            child: Icon(NxI.buildings, color: cs.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? '—' : name, key: const ValueKey('job-customer-name'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                child: Text(tr(kind), key: const ValueKey('job-customer-kind'), style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (onClear != null)
            IconButton(key: const ValueKey('job-customer-clear'), tooltip: tr('ล้างลูกค้า'), visualDensity: VisualDensity.compact, onPressed: onClear, icon: Icon(NxI.x, size: 18, color: cs.onSurfaceVariant)),
        ]),
        if (lines.isNotEmpty) const SizedBox(height: 8),
        for (final (icon, text) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, right: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: cs.onSurfaceVariant)),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ),
        if (onChange != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(key: const ValueKey('job-customer-change'), onPressed: onChange, icon: const Icon(NxI.arrowsLeftRight, size: 16), label: Text(tr('เปลี่ยน'))),
          )
        else
          const SizedBox(height: 8),
      ]),
    );
  }
}

/// The work site: place name, address, pin; เปลี่ยน / ปักหมุด / แก้ไข.
class JobSiteCard extends StatelessWidget {
  const JobSiteCard({super.key, required this.name, required this.address, this.pinned = false, this.onChange, this.onPin, this.onEdit, this.editing = false});
  final String name;
  final String address;
  final bool pinned;
  final VoidCallback? onChange;
  final VoidCallback? onPin;
  final VoidCallback? onEdit;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const tint = Color(0xFF8B5CF6);
    return Container(
      key: const ValueKey('job-site-card'),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: tint.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13)),
            child: Icon(pinned ? NxI.mapPinned : NxI.mapPin, color: tint, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? tr('สถานที่ทำงาน') : name, key: const ValueKey('job-site-name'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (address.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(address, key: const ValueKey('job-site-address'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              if (pinned)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(NxI.navigationArrow, size: 13, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(tr('มีพิกัด — ช่างนำทางได้'), key: const ValueKey('job-site-pinned'), style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
        Wrap(children: [
          if (onChange != null) TextButton.icon(key: const ValueKey('job-site-change'), onPressed: onChange, icon: const Icon(NxI.arrowsLeftRight, size: 16), label: Text(tr('เปลี่ยน'))),
          if (onPin != null) TextButton.icon(key: const ValueKey('job-site-pin'), onPressed: onPin, icon: const Icon(NxI.mapPinned, size: 16), label: Text(tr('ปักหมุด'))),
          if (onEdit != null)
            TextButton.icon(key: const ValueKey('job-site-edit'), onPressed: onEdit, icon: Icon(editing ? NxI.caretUp : NxI.pencilSimple, size: 16), label: Text(tr(editing ? 'ซ่อน' : 'แก้ไข'))),
        ]),
      ]),
    );
  }
}

/// Colour of a priority value.
Color jobPriorityColor(String v) => switch (v.toLowerCase()) {
      'urgent' => const Color(0xFFDC2626),
      'high' => const Color(0xFFF97316),
      'normal' => const Color(0xFF2563EB),
      'low' => const Color(0xFF64748B),
      _ => const Color(0xFF6366F1),
    };

/// Priority as one segmented control (every choice visible, one tap).
class JobPrioritySegment extends StatelessWidget {
  const JobPrioritySegment({super.key, required this.choices, required this.value, this.onChanged});
  final List<JobChoice> choices;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? cs.surfaceContainerHighest.withValues(alpha: 0.45) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        for (final c in choices)
          Expanded(
            child: Builder(builder: (context) {
              final on = c.value == value;
              final color = jobPriorityColor(c.value);
              return Semantics(
                button: true,
                selected: on,
                label: c.label,
                child: GestureDetector(
                  key: ValueKey('job-priority-${c.value}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onChanged!(c.value);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 40),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!on) ...[
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          tr(c.label),
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? Colors.white : cs.onSurface),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          ),
      ]),
    );
  }
}

/// Small label above a group of controls inside a card.
class JobLabel extends StatelessWidget {
  const JobLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant))),
        ?trailing,
      ]),
    );
  }
}
