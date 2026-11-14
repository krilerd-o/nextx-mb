import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/nx_breakpoint.dart';
import '../fields/nx_field_chrome.dart';
import '../nx_scroll_tabs.dart';
import '../nx_status_stepper.dart';
import 'nx_shimmer.dart';

/// Shared skeleton building blocks. Each one wraps itself in an [NxSkeleton]
/// unless it already sits inside one (then it only adds bones), so blocks can
/// be used alone or composed into a page skeleton.

/// Non-scrolling list of skeleton children that never overflows: it takes the
/// height it needs, or clips to what the parent allows.
class NxSkeletonListView extends StatelessWidget {
  const NxSkeletonListView({super.key, required this.children, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      addSemanticIndexes: false,
      children: children,
    );
  }
}

/// Page gutter for list skeletons: [padded] adds the usual 16 px sides; pass
/// false when the skeleton sits inside an already padded list.
EdgeInsets _gutter(bool padded, {double top = 8, double bottom = 24}) =>
    EdgeInsets.fromLTRB(padded ? 16 : 0, top, padded ? 16 : 0, bottom);

/// A bone [widthFactor] of the available width, left-aligned.
class NxBoneLine extends StatelessWidget {
  const NxBoneLine(this.widthFactor, {super.key, this.height = 13, this.radius = 7});
  final double widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor.clamp(0.05, 1.0),
        child: NxBone(height: height, radius: radius),
      );
}

// ─────────────────────────────── rows ───────────────────────────────

enum NxSkelLeading { none, avatar, icon }

enum NxSkelTrailing { none, chevron, text, badge, pill, switcher, timeBadge }

enum NxSkelRowStyle {
  /// Its own card (like [NxEntityRow]).
  card,

  /// Plain row on the page.
  flat,

  /// Plain row with a hairline under it.
  divided,
}

/// One list row: leading avatar / icon tile, one to three lines, trailing
/// bit; card, flat or divided. The default is [NxEntityRow]'s 68 px card.
class NxSkeletonRow extends StatelessWidget {
  const NxSkeletonRow({
    super.key,
    this.leading = NxSkelLeading.avatar,
    this.leadingSize = 44,
    this.lines = 2,
    this.trailing = NxSkelTrailing.chevron,
    this.style = NxSkelRowStyle.card,
    this.wide = true,
    this.padding,
    this.minHeight,
    this.indent,
  });

  final NxSkelLeading leading;
  final double leadingSize;
  final int lines;
  final NxSkelTrailing trailing;
  final NxSkelRowStyle style;

  /// Long or short title (rows alternate so the list does not look ruled).
  final bool wide;
  final EdgeInsetsGeometry? padding;

  /// Row height floor (the real row's height, e.g. 72 for notifications).
  final double? minHeight;

  /// Divider indent for [NxSkelRowStyle.divided] (default: past the leading).
  final double? indent;

  @override
  Widget build(BuildContext context) {
    final lead = switch (leading) {
      NxSkelLeading.avatar => NxBone.circle(leadingSize),
      NxSkelLeading.icon => NxBone(width: leadingSize, height: leadingSize, radius: leadingSize * 0.3),
      NxSkelLeading.none => null,
    };
    final trail = switch (trailing) {
      NxSkelTrailing.chevron => const NxBone(width: 8, height: 14, radius: 3),
      NxSkelTrailing.text => const NxBone(width: 44, height: 11),
      NxSkelTrailing.badge => const NxBone(width: 64, height: 24, radius: 12),
      NxSkelTrailing.pill => const NxBone(width: 56, height: 20, radius: 10),
      NxSkelTrailing.switcher => const NxBone(width: 44, height: 26, radius: 13),
      NxSkelTrailing.timeBadge => const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [NxBone(width: 36, height: 10), SizedBox(height: 8), NxBone.circle(18)],
        ),
      NxSkelTrailing.none => null,
    };
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxBoneLine(wide ? 0.72 : 0.5, height: 15),
        for (var i = 1; i < lines; i++) ...[
          const SizedBox(height: 8),
          NxBoneLine(i == 1 ? (wide ? 0.5 : 0.82) : 0.36, height: 11),
        ],
      ],
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: math.max(0, (minHeight ?? 0) - _vPad * 2)),
      child: Row(children: [
        if (lead != null) ...[lead, const SizedBox(width: 12)],
        Expanded(child: text),
        if (trail != null) ...[const SizedBox(width: 12), trail],
      ]),
    );
    final body = switch (style) {
      NxSkelRowStyle.card => NxSkeletonCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: _vPad),
          child: row,
        ),
      _ => Padding(padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: _vPad), child: row),
    };
    final out = style != NxSkelRowStyle.divided
        ? body
        : Column(mainAxisSize: MainAxisSize.min, children: [
            body,
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: indent ?? (lead == null ? 16 : 16 + leadingSize + 12),
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ]);
    return NxSkeleton(child: out);
  }

  static const _vPad = 12.0;
}

/// A list of [NxSkeletonRow]s (optionally with day headings every few rows).
class NxSkeletonRows extends StatelessWidget {
  const NxSkeletonRows({
    super.key,
    this.count = 6,
    this.leading = NxSkelLeading.avatar,
    this.leadingSize = 44,
    this.lines = 2,
    this.trailing = NxSkelTrailing.chevron,
    this.style = NxSkelRowStyle.card,
    this.padded = true,
    this.dayHeaders = 0,
    this.minHeight,
    this.top = 8,
    this.loadMore = false,
  });

  final int count;
  final NxSkelLeading leading;
  final double leadingSize;
  final int lines;
  final NxSkelTrailing trailing;
  final NxSkelRowStyle style;

  /// 16 px page sides; false inside an already padded list.
  final bool padded;

  /// A day heading before every [dayHeaders] rows (0 = none).
  final int dayHeaders;
  final double? minHeight;
  final double top;

  /// A "loading more" bone at the end (paging lists).
  final bool loadMore;

  @override
  Widget build(BuildContext context) {
    final flat = style != NxSkelRowStyle.card;
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: flat ? EdgeInsets.only(top: top, bottom: 24) : _gutter(padded, top: top),
        children: [
          for (var i = 0; i < count; i++) ...[
            if (dayHeaders > 0 && i % dayHeaders == 0)
              Padding(
                padding: EdgeInsets.fromLTRB(flat || !padded ? 16 : 4, i == 0 ? 4 : 14, 16, 10),
                child: const Align(alignment: AlignmentDirectional.centerStart, child: NxBone(width: 96, height: 12)),
              ),
            NxSkeletonRow(
              leading: leading,
              leadingSize: leadingSize,
              lines: lines,
              trailing: trailing,
              style: style,
              wide: i.isEven,
              minHeight: minHeight,
              padding: flat && !padded ? const EdgeInsets.symmetric(vertical: 12) : null,
            ),
          ],
          if (loadMore) const NxSkeletonLoadMore(),
        ],
      ),
    );
  }
}

/// The "loading more" bone at the end of a paging list.
class NxSkeletonLoadMore extends StatelessWidget {
  const NxSkeletonLoadMore({super.key});

  @override
  Widget build(BuildContext context) => const NxSkeleton(
        delay: Duration.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(child: NxBone(width: 120, height: 12)),
        ),
      );
}

/// [NxEntityCard]: code line, two-line title, badge top-right, divider, footer.
class NxSkeletonEntityCard extends StatelessWidget {
  const NxSkeletonEntityCard({super.key, this.wide = true, this.footer = true});
  final bool wide;
  final bool footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: NxSkeletonCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const NxBone(width: 72, height: 11),
                const SizedBox(height: 8),
                NxBoneLine(wide ? 0.86 : 0.64, height: 16),
                const SizedBox(height: 8),
                NxBoneLine(wide ? 0.5 : 0.62, height: 11),
              ]),
            ),
            const SizedBox(width: 8),
            const NxBone(width: 64, height: 24, radius: 12),
          ]),
          if (footer) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 0.5, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            const Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [NxBone(width: 15, height: 15, radius: 4), SizedBox(width: 8), NxBone(width: 92, height: 12)]),
                  SizedBox(height: 8),
                  Row(children: [NxBone.circle(20), SizedBox(width: 8), NxBone(width: 76, height: 12)]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                NxBone(width: 40, height: 10),
                SizedBox(height: 6),
                NxBone(width: 84, height: 20),
              ]),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// A list of [NxSkeletonEntityCard]s (grid on wide screens).
class NxSkeletonEntityCards extends StatelessWidget {
  const NxSkeletonEntityCards({super.key, this.count = 5, this.padded = true, this.loadMore = false});
  final int count;
  final bool padded;
  final bool loadMore;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded),
        children: [
          for (var i = 0; i < count; i++) NxSkeletonEntityCard(wide: i.isEven),
          if (loadMore) const NxSkeletonLoadMore(),
        ],
      ),
    );
  }
}

// ───────────────────────────── chrome ─────────────────────────────

/// Search pill + filter button, and a row of filter chips (list toolbars).
class NxSkeletonToolbar extends StatelessWidget {
  const NxSkeletonToolbar({super.key, this.chips = 3, this.padded = true});
  final int chips;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padded ? 16 : 0, 8, padded ? 16 : 0, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Row(children: [
            Expanded(child: NxBone(height: 44, radius: 22)),
            SizedBox(width: 8),
            NxBone(width: 44, height: 44, radius: 14),
          ]),
          if (chips > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  maxWidth: double.infinity,
                  child: Row(children: [
                    for (var i = 0; i < chips; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      NxBone(width: i == 0 ? 64 : 84, height: 32, radius: 16),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Pill tab row ([NxScrollTabs]): same 44 px track.
class NxSkeletonTabs extends StatelessWidget {
  const NxSkeletonTabs({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: Container(
        height: NxScrollTabs.height,
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.all(4),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: double.infinity,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const NxBone(width: 16, height: 16, radius: 5),
                    const SizedBox(width: 6),
                    NxBone(width: i.isEven ? 52 : 40, height: 12),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// [NxStatusStepper]'s chevron bar: same frame, height and arrow clip. Also a
/// space reserver while the statuses load, so nothing below it jumps.
class NxSkeletonChevronBar extends StatelessWidget {
  const NxSkeletonChevronBar({super.key, this.steps = 4, this.padding = EdgeInsets.zero});
  final int steps;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF0F172A) : Colors.white;
    final frame = dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    return NxSkeleton(
      child: Padding(
        padding: padding,
        child: Container(
          key: const ValueKey('nx-skeleton-status-bar'),
          height: NxStatusStepper.barHeight,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: frame.withValues(alpha: 0.9))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LayoutBuilder(builder: (context, c) {
              final n = math.max(1, steps);
              const o = NxStatusStepper.overlap;
              final w = (c.maxWidth + o * (n - 1)) / n;
              return Stack(children: [
                for (var k = 0; k < n; k++)
                  Positioned(
                    left: k * (w - o),
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: ClipPath(
                      clipper: NxChevronClipper(first: k == 0, last: k == n - 1),
                      child: const NxBone(height: NxStatusStepper.pillHeight, radius: 0),
                    ),
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── detail ─────────────────────────────

/// A record's head card: centred avatar, title, people line, quick actions
/// (and the lead's convert button when [cta]).
class NxSkeletonHero extends StatelessWidget {
  const NxSkeletonHero({super.key, this.avatar = 76, this.actions = 4, this.cta = false});
  final double avatar;
  final int actions;
  final bool cta;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonCard(
        radius: 28,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Column(children: [
          NxBone.circle(avatar),
          const SizedBox(height: 14),
          const NxBone(width: 180, height: 22, radius: 10),
          const SizedBox(height: 8),
          const NxBone(width: 120, height: 13),
          const SizedBox(height: 14),
          if (actions > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (var i = 0; i < actions; i++)
                  const Column(mainAxisSize: MainAxisSize.min, children: [
                    NxBone(width: 44, height: 44, radius: 14),
                    SizedBox(height: 6),
                    NxBone(width: 34, height: 10),
                  ]),
              ]),
            ),
          if (cta) ...[const SizedBox(height: 12), const NxBone(height: 48, radius: 16), const SizedBox(height: 4)],
        ]),
      ),
    );
  }
}

/// Body of a record while its fields load: the field card (label · value
/// rows), a related-records card and the tag chips — tab content only.
class NxSkeletonDetailBody extends StatelessWidget {
  const NxSkeletonDetailBody({super.key, this.fields = 6, this.related = true});
  final int fields;
  final bool related;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        NxSkeletonCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [NxBone(width: 110, height: 13), Spacer(), NxBone(width: 60, height: 13)]),
            const SizedBox(height: 10),
            for (var i = 0; i < fields; i++) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.4)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(children: [
                  const SizedBox(width: 104, child: NxBoneLine(0.78, height: 11)),
                  const SizedBox(width: 12),
                  Expanded(child: NxBoneLine(const [0.8, 0.55, 0.7, 0.4][i % 4], height: 13)),
                ]),
              ),
            ],
          ]),
        ),
        if (related) ...[
          const SizedBox(height: 16),
          const NxBone(width: 120, height: 15),
          const SizedBox(height: 10),
          const NxSkeletonRow(leading: NxSkelLeading.icon, leadingSize: 36, trailing: NxSkelTrailing.chevron),
          const NxSkeletonRow(leading: NxSkelLeading.icon, leadingSize: 36, trailing: NxSkelTrailing.chevron, wide: false),
        ],
      ]),
    );
  }
}

/// Whole record page (deep links): head card, chevron status bar, tabs, body.
class NxSkeletonEntityDetail extends StatelessWidget {
  const NxSkeletonEntityDetail({super.key, this.statusBar = true, this.tabs = 4, this.cta = false, this.padded = true});
  final bool statusBar;
  final int tabs;
  final bool cta;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded, top: 8, bottom: 28),
        children: [
          NxSkeletonHero(cta: cta),
          if (statusBar) ...[const SizedBox(height: 12), const NxSkeletonChevronBar()],
          const SizedBox(height: 14),
          NxSkeletonTabs(count: tabs),
          const SizedBox(height: 14),
          const NxSkeletonDetailBody(),
        ],
      ),
    );
  }
}

/// Task page: title, status stepper, field rows, sub-items section.
class NxSkeletonTaskDetail extends StatelessWidget {
  const NxSkeletonTaskDetail({super.key, this.padded = true});
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded, top: 12, bottom: 28),
        children: [
          const Row(children: [NxBone(width: 22, height: 22, radius: 6), SizedBox(width: 8), NxBone(width: 80, height: 12)]),
          const SizedBox(height: 12),
          const NxBoneLine(0.86, height: 22, radius: 10),
          const SizedBox(height: 8),
          const NxBoneLine(0.5, height: 22, radius: 10),
          const SizedBox(height: 16),
          const NxSkeletonChevronBar(),
          const SizedBox(height: 16),
          const NxSkeletonDetailBody(fields: 5, related: false),
          const SizedBox(height: 18),
          const NxBone(width: 110, height: 15),
          const SizedBox(height: 10),
          for (var i = 0; i < 2; i++)
            NxSkeletonRow(leading: NxSkelLeading.icon, leadingSize: 22, lines: 1, trailing: NxSkelTrailing.pill, wide: i.isEven),
        ],
      ),
    );
  }
}

// ───────────────────────────── settings ─────────────────────────────

/// [SettingsGroup]: caption, then a rounded group of tiles (tinted icon
/// square, two lines, switch or chevron), hairlines between.
class NxSkeletonSettingsGroup extends StatelessWidget {
  const NxSkeletonSettingsGroup({super.key, this.tiles = 3, this.trailing = NxSkelTrailing.switcher, this.title = true});
  final int tiles;
  final NxSkelTrailing trailing;
  final bool title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (title)
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 22, 6, 10),
            child: Align(alignment: AlignmentDirectional.centerStart, child: NxBone(width: 96, height: 11)),
          ),
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            for (var i = 0; i < tiles; i++) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 60, color: cs.outlineVariant.withValues(alpha: 0.6)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  const NxBone(width: 34, height: 34, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        NxBoneLine(i.isEven ? 0.56 : 0.42, height: 14),
                        const SizedBox(height: 7),
                        NxBoneLine(i.isEven ? 0.78 : 0.64, height: 11),
                      ]),
                    ),
                  ),
                  if (trailing != NxSkelTrailing.none) ...[
                    const SizedBox(width: 12),
                    if (trailing == NxSkelTrailing.switcher)
                      const NxBone(width: 44, height: 26, radius: 13)
                    else
                      const NxBone(width: 8, height: 14, radius: 3),
                  ],
                ],
              ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// A settings page: several [NxSkeletonSettingsGroup]s.
class NxSkeletonSettings extends StatelessWidget {
  const NxSkeletonSettings({super.key, this.groups = const [3, 2], this.trailing = NxSkelTrailing.switcher, this.padded = true, this.header});
  final List<int> groups;
  final NxSkelTrailing trailing;
  final bool padded;

  /// Optional block above the groups (e.g. a profile card).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded, top: 0),
        children: [
          ?header,
          for (final n in groups) NxSkeletonSettingsGroup(tiles: n, trailing: trailing),
        ],
      ),
    );
  }
}

/// Form page: section labels, then field boxes as tall as the standard input.
class NxSkeletonFields extends StatelessWidget {
  const NxSkeletonFields({super.key, this.sections = const [3, 2], this.padded = true, this.header});
  final List<int> sections;
  final bool padded;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: padded ? const EdgeInsets.fromLTRB(16, 12, 16, 24) : const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          ?header,
          for (var s = 0; s < sections.length; s++) ...[
            Padding(
              padding: EdgeInsets.only(top: s == 0 ? 4 : 18, bottom: 12),
              child: const Align(alignment: AlignmentDirectional.centerStart, child: NxBone(width: 110, height: 14)),
            ),
            for (var i = 0; i < sections[s]; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: NxSkeletonFieldBox(),
              ),
          ],
        ],
      ),
    );
  }
}

/// One outlined input ([NxFieldStyle.controlHeight], radius 14) with a resting label bone.
class NxSkeletonFieldBox extends StatelessWidget {
  const NxSkeletonFieldBox({super.key, this.height = NxFieldStyle.controlHeight});
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NxFieldStyle.radius),
          border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        ),
        child: const NxBone(width: 110, height: 12),
      ),
    );
  }
}

// ───────────────────────────── grids / charts ─────────────────────────────

/// Tiles in [cols] columns of [tileHeight] (KPI tiles, leave balances, media).
class NxSkeletonGrid extends StatelessWidget {
  const NxSkeletonGrid({
    super.key,
    this.cols = 2,
    this.count,
    this.tileHeight = 110,
    this.gap = 12,
    this.ring,
    this.square = false,
    this.radius,
    this.padded = false,
  });

  final int cols;

  /// Tiles (default: two rows).
  final int? count;
  final double tileHeight;
  final double gap;

  /// A ring of this size in each tile (leave balance cards).
  final double? ring;

  /// Plain square bones (media grid): no card, no lines.
  final bool square;
  final double? radius;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final n = count ?? cols * 2;
    return NxSkeleton(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padded ? 16 : 0),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.hasBoundedWidth ? c.maxWidth : MediaQuery.sizeOf(context).width - 32;
          final cw = ((w - gap * (cols - 1)) / cols).floorToDouble();
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (var i = 0; i < n; i++)
              SizedBox(
                width: cw,
                height: square ? cw : tileHeight,
                child: square
                    ? NxBone(radius: radius ?? 8, height: cw)
                    : NxSkeletonCard(
                        margin: EdgeInsets.zero,
                        radius: radius,
                        padding: const EdgeInsets.all(14),
                        child: ring != null
                            ? Column(children: [
                                Expanded(child: Center(child: _Ring(size: ring!))),
                                const SizedBox(height: 10),
                                const NxBone(width: 70, height: 12),
                                const SizedBox(height: 6),
                                const NxBone(width: 48, height: 10),
                              ])
                            : const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                NxBone.circle(32),
                                Spacer(),
                                NxBone(width: 72, height: 20),
                                SizedBox(height: 8),
                                NxBone(width: 56, height: 11),
                              ]),
                      ),
              ),
          ]);
        }),
      ),
    );
  }
}

/// A ring bone (donut / progress ring) drawn as an outlined circle.
class _Ring extends StatelessWidget {
  const _Ring({required this.size, this.stroke});
  final double size;
  final double? stroke;

  @override
  Widget build(BuildContext context) {
    final s = stroke ?? math.max(8.0, size * 0.13);
    return SizedBox.square(
      dimension: size,
      child: ClipPath(
        clipper: _RingClipper(s),
        child: NxBone(width: size, height: size, radius: size / 2),
      ),
    );
  }
}

class _RingClipper extends CustomClipper<Path> {
  const _RingClipper(this.stroke);
  final double stroke;

  @override
  Path getClip(Size size) {
    final outer = Offset.zero & size;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(outer)
      ..addOval(outer.deflate(stroke));
  }

  @override
  bool shouldReclip(_RingClipper old) => old.stroke != stroke;
}

enum NxChartKind { columns, bars, donut, ring, line }

/// Chart-shaped bones that fill the given height (Home charts, insights).
class NxSkeletonChart extends StatelessWidget {
  const NxSkeletonChart({super.key, this.kind = NxChartKind.columns, this.height});
  final NxChartKind kind;

  /// Fixed height; null = fill the parent (must be bounded).
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget body = LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight.isFinite ? c.maxHeight : 120.0;
      switch (kind) {
        case NxChartKind.columns:
        case NxChartKind.line:
          const vals = [0.45, 0.7, 0.55, 0.9, 0.62, 0.8, 0.5];
          final thin = kind == NxChartKind.line;
          return Column(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < vals.length; i++) ...[
                  if (i > 0) SizedBox(width: thin ? 10 : 8),
                  Expanded(child: NxBone(height: math.max(6, (h - 20) * vals[i]), radius: thin ? 3 : 6)),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            const NxBone(height: 9, radius: 4),
          ]);
        case NxChartKind.bars:
          const vals = [0.85, 0.62, 0.48, 0.3, 0.2];
          final rows = math.max(2, math.min(vals.length, (h / 30).floor()));
          return Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < rows; i++)
              Row(children: [
                const SizedBox(width: 64, child: NxBoneLine(0.85, height: 10)),
                const SizedBox(width: 8),
                Expanded(child: NxBoneLine(vals[i], height: 14, radius: 5)),
              ]),
          ]);
        case NxChartKind.donut:
        case NxChartKind.ring:
          final side = math.max(40.0, math.min(h, c.maxWidth * 0.45));
          return Row(children: [
            _Ring(size: side, stroke: kind == NxChartKind.ring ? side * 0.1 : side * 0.2),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < (kind == NxChartKind.ring ? 2 : 3); i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(children: [const NxBone.circle(8), const SizedBox(width: 6), Expanded(child: NxBoneLine(i.isEven ? 0.8 : 0.6, height: 10))]),
                ],
              ]),
            ),
          ]);
      }
    });
    if (height != null) body = SizedBox(height: height, child: body);
    return NxSkeleton(child: body);
  }
}

/// A card with a header (icon dot + title + pill) and a chart body (insights).
class NxSkeletonChartCard extends StatelessWidget {
  const NxSkeletonChartCard({super.key, this.kind = NxChartKind.columns, this.height = 220});
  final NxChartKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonCard(
        height: height,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [NxBone.circle(28), SizedBox(width: 8), NxBone(width: 120, height: 14)]),
          const SizedBox(height: 10),
          const NxBone(width: 88, height: 22, radius: 11),
          const SizedBox(height: 12),
          Expanded(child: NxSkeletonChart(kind: kind)),
        ]),
      ),
    );
  }
}

// ───────────────────────────── forms ─────────────────────────────

/// Quotation / job step form: step chips, section cards of fields, bottom
/// action bar; a summary pane at the side on wide screens.
class NxSkeletonStepForm extends StatelessWidget {
  const NxSkeletonStepForm({super.key, this.steps = 4, this.sections = const [3, 2], this.sidePane});
  final int steps;
  final List<int> sections;

  /// Null: from the width (≥ 900 px).
  final bool? sidePane;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: LayoutBuilder(builder: (context, c) {
        final wide = sidePane ?? (c.maxWidth >= 900);
        final chips = SizedBox(
          height: 40,
          child: ClipRect(
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              maxWidth: double.infinity,
              child: Row(children: [
                for (var i = 0; i < steps; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const NxBone.circle(24),
                    const SizedBox(width: 6),
                    NxBone(width: i.isEven ? 64 : 48, height: 12),
                  ]),
                  if (i < steps - 1) ...[const SizedBox(width: 8), const NxBone(width: 18, height: 2, radius: 1)],
                ],
              ]),
            ),
          ),
        );
        Widget section(int fields, int s) => NxSkeletonCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [const NxBone(width: 20, height: 20, radius: 6), const SizedBox(width: 8), NxBone(width: s.isEven ? 120 : 96, height: 14)]),
                const SizedBox(height: 14),
                for (var i = 0; i < fields; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: NxSkeletonFieldBox()),
              ]),
            );
        final main = NxSkeletonListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            chips,
            const SizedBox(height: 14),
            for (var s = 0; s < sections.length; s++) section(sections[s], s),
          ],
        );
        final bar = Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.5))),
          child: const Row(children: [
            NxBone(width: 96, height: 46, radius: 14),
            SizedBox(width: 12),
            Expanded(child: NxBone(height: 46, radius: 14)),
          ]),
        );
        final side = SizedBox(
          width: 320,
          child: NxSkeletonListView(
            padding: const EdgeInsets.fromLTRB(0, 10, 16, 16),
            children: [
              NxSkeletonCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NxBone(width: 100, height: 14),
                  const SizedBox(height: 14),
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [NxBone(width: i.isEven ? 80 : 64, height: 11), const Spacer(), const NxBone(width: 56, height: 12)]),
                    ),
                  const SizedBox(height: 6),
                  const NxBone(height: 22),
                ]),
              ),
            ],
          ),
        );
        final content = wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: main), side]) : main;
        if (!c.hasBoundedHeight) return Column(mainAxisSize: MainAxisSize.min, children: [content, bar]);
        return Column(children: [Expanded(child: content), bar]);
      }),
    );
  }
}

/// Key–value card (order summary): heading, label · value rows, total line.
class NxSkeletonKeyValueCard extends StatelessWidget {
  const NxSkeletonKeyValueCard({super.key, this.rows = 5, this.total = true});
  final int rows;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: NxSkeletonCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NxBone(width: 120, height: 15),
          const SizedBox(height: 14),
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [NxBone(width: i.isEven ? 92 : 70, height: 12), const Spacer(), NxBone(width: i.isEven ? 76 : 100, height: 13)]),
            ),
          if (total) ...[
            Divider(height: 12, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 6),
            const Row(children: [NxBone(width: 64, height: 15), Spacer(), NxBone(width: 120, height: 22)]),
          ],
        ]),
      ),
    );
  }
}

// ───────────────────────────── feeds ─────────────────────────────

/// History / activity timeline: dot and rail on the left, lines on the right.
class NxSkeletonTimeline extends StatelessWidget {
  const NxSkeletonTimeline({super.key, this.rows = 5, this.padded = false});
  final int rows;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final rail = NxSkeletonColors.of(context).bone;
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: EdgeInsets.fromLTRB(padded ? 16 : 0, 8, padded ? 16 : 0, 16),
        children: [
          for (var i = 0; i < rows; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 28,
                  child: Column(children: [
                    const SizedBox(height: 4),
                    const NxBone.circle(12),
                    if (i < rows - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: rail)),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [const NxBone.circle(20), const SizedBox(width: 8), NxBone(width: i.isEven ? 120 : 90, height: 12), const Spacer(), const NxBone(width: 48, height: 10)]),
                      const SizedBox(height: 10),
                      NxBoneLine(i.isEven ? 0.86 : 0.6, height: 12),
                      if (i % 3 == 0) ...[const SizedBox(height: 8), const NxBone(width: 140, height: 22, radius: 11)],
                    ]),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Comments: avatar and a bubble (name, two lines) per row.
class NxSkeletonComments extends StatelessWidget {
  const NxSkeletonComments({super.key, this.rows = 4, this.padded = false});
  final int rows;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final bubble = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: EdgeInsets.fromLTRB(padded ? 16 : 0, 8, padded ? 16 : 0, 16),
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const NxBone.circle(34),
                const SizedBox(width: 10),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: i.isEven ? 0.92 : 0.7,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [NxBone(width: 84, height: 12), Spacer(), NxBone(width: 40, height: 10)]),
                        const SizedBox(height: 10),
                        const NxBoneLine(0.95, height: 12),
                        if (i.isEven) ...[const SizedBox(height: 6), const NxBoneLine(0.6, height: 12)],
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Message cards (mail thread): sender line, a few body lines.
class NxSkeletonMessageCards extends StatelessWidget {
  const NxSkeletonMessageCards({super.key, this.count = 3, this.padded = true});
  final int count;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded, top: 12),
        children: [
          for (var i = 0; i < count; i++)
            NxSkeletonCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const NxBone.circle(36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NxBoneLine(i.isEven ? 0.5 : 0.4, height: 13),
                      const SizedBox(height: 7),
                      const NxBoneLine(0.3, height: 10),
                    ]),
                  ),
                  const NxBone(width: 48, height: 10),
                ]),
                if (i == count - 1) ...[
                  const SizedBox(height: 16),
                  for (final f in const [0.95, 0.9, 0.98, 0.7, 0.85, 0.5]) ...[NxBoneLine(f, height: 12), const SizedBox(height: 9)],
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

/// Article (announcement, mail body): title, meta line, optional cover, paragraphs.
class NxSkeletonArticle extends StatelessWidget {
  const NxSkeletonArticle({super.key, this.cover = false, this.title = true, this.padded = true, this.paragraphs = 3});
  final bool cover;
  final bool title;
  final bool padded;
  final int paragraphs;

  @override
  Widget build(BuildContext context) {
    const widths = [0.96, 0.9, 0.98, 0.84, 0.92, 0.6];
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: padded ? const EdgeInsets.fromLTRB(20, 16, 20, 24) : const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          if (title) ...[
            const NxBoneLine(0.9, height: 22, radius: 10),
            const SizedBox(height: 10),
            const NxBoneLine(0.55, height: 22, radius: 10),
            const SizedBox(height: 14),
            const Row(children: [NxBone.circle(28), SizedBox(width: 10), NxBone(width: 120, height: 12), Spacer(), NxBone(width: 64, height: 11)]),
            const SizedBox(height: 20),
          ],
          if (cover) ...[
            const AspectRatio(aspectRatio: 16 / 9, child: NxBone(radius: 16, height: double.infinity)),
            const SizedBox(height: 18),
          ],
          for (var p = 0; p < paragraphs; p++) ...[
            for (var i = 0; i < (p.isEven ? 5 : 4); i++) ...[NxBoneLine(widths[(i + p) % widths.length], height: 13), const SizedBox(height: 10)],
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Calendar agenda: day headings, each with a card of event tiles (time
/// column, colour bar, title, place) like [CalCard].
class NxSkeletonAgenda extends StatelessWidget {
  const NxSkeletonAgenda({super.key, this.days = 3});
  final int days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          for (var d = 0; d < days; d++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [NxBone(width: d == 0 ? 72 : 120, height: 15), const SizedBox(width: 8), const NxBone(width: 56, height: 11)]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                for (var i = 0; i < (d.isEven ? 3 : 2); i++) ...[
                  if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 72, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(children: [
                      const SizedBox(
                        width: 46,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [NxBone(width: 38, height: 12), SizedBox(height: 6), NxBone(width: 30, height: 10)]),
                      ),
                      const NxBone(width: 4, height: 38, radius: 2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          NxBoneLine(i.isEven ? 0.7 : 0.52, height: 14),
                          const SizedBox(height: 8),
                          NxBoneLine(i.isEven ? 0.4 : 0.55, height: 11),
                        ]),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small event chips over a calendar grid (month / week / day views) while
/// their events load: the grid itself is real, only the chips are bones.
class NxSkeletonEventChips extends StatelessWidget {
  const NxSkeletonEventChips({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < count; i++) Padding(padding: const EdgeInsets.only(bottom: 3), child: NxBoneLine(i.isEven ? 1 : 0.7, height: 10, radius: 4)),
      ]),
    );
  }
}

// ─────────────────────────── legacy blocks ───────────────────────────

/// List rows like the app's list cards: code · title · chip · avatar.
class NxSkeletonList extends StatelessWidget {
  const NxSkeletonList({super.key, this.rows = 6, this.padded = true});

  final int rows;

  /// 16 px sides; false inside an already padded list (no double padding).
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded),
        children: [for (var i = 0; i < rows; i++) _ListCard(wide: i.isEven)],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({this.wide = true});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return NxSkeletonCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [NxBone(width: 16, height: 16, radius: 5), SizedBox(width: 8), NxBone(width: 72, height: 11)]),
        const SizedBox(height: 10),
        NxBoneLine(wide ? 0.78 : 0.56, height: 16),
        const SizedBox(height: 12),
        const Row(children: [NxBone(width: 96, height: 22, radius: 11), Spacer(), NxBone.circle(28)]),
      ]),
    );
  }
}

/// Kanban board: columns with a header and task cards.
class NxSkeletonBoard extends StatelessWidget {
  const NxSkeletonBoard({super.key, this.columns = 2});
  final int columns;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final colW = (w * 0.8).clamp(240.0, 320.0);
    final tint = NxSkeletonColors.of(context).bone.withValues(alpha: 0.04);
    return NxSkeleton(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var c = 0; c < columns; c++)
            Container(
              width: colW,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppTheme.cardRadius + 4)),
              child: Column(children: [
                const NxBone(width: 64, height: 14),
                const SizedBox(height: 6),
                const NxBone(width: 40, height: 11),
                const SizedBox(height: 14),
                for (var i = 0; i < 3 - c % 3; i++) _ListCard(wide: i.isEven),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Record / task detail body (kept for callers that only need the body).
class NxSkeletonDetail extends StatelessWidget {
  const NxSkeletonDetail({super.key, this.padded = true});
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonListView(
        padding: _gutter(padded, top: 12),
        children: const [NxSkeletonDetailBody()],
      ),
    );
  }
}

/// Calendar agenda (kept name).
class NxSkeletonCalendar extends StatelessWidget {
  const NxSkeletonCalendar({super.key});

  @override
  Widget build(BuildContext context) => const NxSkeletonAgenda();
}

/// Chat: bubbles left and right.
class NxSkeletonChat extends StatelessWidget {
  const NxSkeletonChat({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: LayoutBuilder(builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : MediaQuery.sizeOf(context).width;
        return NxSkeletonListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: i.isOdd ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (i.isEven) ...[const NxBone.circle(30), const SizedBox(width: 8)],
                    NxBone(width: math.min(520, w * (i % 3 == 0 ? 0.62 : 0.44)), height: i % 3 == 0 ? 56 : 38, radius: 18),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Small placeholder inside a home box: icon · title · pill rows.
class NxSkeletonBox extends StatelessWidget {
  const NxSkeletonBox({super.key, this.rows = 3, this.pill = false});
  final int rows;

  /// A status pill at the end of each row (MyWork lines).
  final bool pill;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const NxBone(width: 17, height: 17, radius: 5),
                const SizedBox(width: 10),
                Expanded(child: NxBoneLine(i.isEven ? 0.8 : 0.58, height: 13)),
                if (pill) ...[const SizedBox(width: 8), NxBone(width: i.isEven ? 56 : 44, height: 20, radius: 10)],
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Home period box figures: 3-column figure tiles.
class NxSkeletonFigures extends StatelessWidget {
  const NxSkeletonFigures({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: LayoutBuilder(builder: (context, c) {
        final w = ((c.hasBoundedWidth ? c.maxWidth : 300) - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < count; i++)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(color: NxSkeletonColors.of(context).bone.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NxBoneLine(i.isEven ? 0.7 : 0.5, height: 18),
                const SizedBox(height: 6),
                const NxBoneLine(0.8, height: 10),
              ]),
            ),
        ]);
      }),
    );
  }
}

class NxSkeletonKpiGrid extends StatelessWidget {
  const NxSkeletonKpiGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final cols = NxBreakpoint.of(context).gridColumns.clamp(2, 4);
    return NxSkeletonGrid(cols: cols, count: cols, tileHeight: 120);
  }
}

/// Form: field boxes at the standard input height.
class NxSkeletonForm extends StatelessWidget {
  const NxSkeletonForm({super.key, this.fields = 8});

  final int fields;

  @override
  Widget build(BuildContext context) => NxSkeletonFields(sections: [fields]);
}
