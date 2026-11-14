import 'package:flutter/material.dart';

import '../../core/home_layout.dart';
import '../../widgets/nx_skeleton.dart';
import 'home_boxes.dart';
import 'home_charts.dart';
import 'home_edit_mode.dart';

/// Home while its first answers load: the user's own saved widgets, in their
/// order and sizes, each drawn as its frame (header + a body shaped like the
/// widget: figure tiles, work rows, chart bars / donut …) at the real height.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key, required this.entries});

  /// The saved widgets this user may see, in order.
  final List<HomeEntry> entries;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: LayoutBuilder(builder: (context, c) {
        final cols = homeGridColumns(c.maxWidth);
        const gap = 12.0;
        final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
        final rows = <Widget>[];
        var row = <Widget>[];
        var used = 0;
        void flush() {
          if (row.isEmpty) return;
          rows.add(Padding(
            padding: const EdgeInsets.only(top: kHomeWidgetGap),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < row.length; i++) ...[if (i > 0) const SizedBox(width: gap), row[i]],
            ]),
          ));
          row = [];
          used = 0;
        }

        for (final e in entries) {
          final chart = HomeLayout.isChart(e.id);
          if (!chart) {
            final w = homeSectionSkeleton(e.id);
            if (w == null) continue;
            flush();
            rows.add(Padding(padding: const EdgeInsets.only(top: kHomeWidgetGap), child: w));
            continue;
          }
          final half = e.size == HomeSize.half;
          final span = half ? 1 : cols;
          if (used + span > cols) flush();
          row.add(SizedBox(width: half ? cellW : c.maxWidth, child: HomeChartSkeleton(id: e.id, half: half)));
          used += span;
          if (used >= cols) flush();
        }
        flush();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      }),
    );
  }

  /// Skeleton of a classic Home section, or null for sections that only
  /// appear when they have data (birthdays, upcoming, pending, recent).
  static Widget? homeSectionSkeleton(String id) => switch (id) {
        'today' => const _Frame(key: ValueKey('home-skel-today'), child: _TodayBody()),
        'ai' => const _Frame(key: ValueKey('home-skel-ai'), child: _AiBody()),
        'work' => const _Frame(key: ValueKey('home-skel-work'), header: true, child: NxSkeletonBox(rows: 3, pill: true)),
        'quick' => const _QuickBody(key: ValueKey('home-skel-quick')),
        'sales' => const _Frame(key: ValueKey('home-skel-sales'), header: true, chips: true, child: NxSkeletonFigures(count: 3)),
        'cases' => const _Frame(key: ValueKey('home-skel-cases'), header: true, chips: true, child: NxSkeletonFigures(count: 6)),
        'stats' => const _StatsBody(key: ValueKey('home-skel-stats')),
        _ => null,
      };
}

/// The chart card's frame (same fixed height) with a chart-shaped body.
class HomeChartSkeleton extends StatelessWidget {
  const HomeChartSkeleton({super.key, required this.id, required this.half});
  final String id;
  final bool half;

  static NxChartKind kindOf(String id) => switch (id) {
        'chart_winrate' || 'chart_case_sla' || 'chart_lead_conv' => NxChartKind.ring,
        'chart_quote' || 'chart_lead_source' || 'chart_case_status' => NxChartKind.donut,
        'chart_pipeline' || 'chart_closing' || 'chart_leave' => NxChartKind.bars,
        'chart_work' => NxChartKind.line,
        _ => NxChartKind.columns,
      };

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: NxSkeletonCard(
        key: ValueKey('home-skel-$id'),
        margin: EdgeInsets.zero,
        radius: kHomeCardRadius,
        height: half ? kHalfChartHeight : kFullChartHeight,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [NxBone.circle(28), SizedBox(width: 8), Expanded(child: NxBoneLine(0.6, height: 14))]),
          const SizedBox(height: 8),
          const Align(alignment: AlignmentDirectional.centerStart, child: NxBone(width: 96, height: 22, radius: 11)),
          const SizedBox(height: 10),
          Expanded(child: NxSkeletonChart(kind: kindOf(id))),
        ]),
      ),
    );
  }
}

/// A Home card: optional header (icon dot, title, link) and period chips.
class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.child, this.header = false, this.chips = false});
  final Widget child;
  final bool header;
  final bool chips;

  @override
  Widget build(BuildContext context) {
    return NxSkeletonCard(
      margin: EdgeInsets.zero,
      radius: kHomeCardRadius,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header) ...[
          const Row(children: [NxBone.circle(28), SizedBox(width: 10), NxBone(width: 96, height: 15), Spacer(), NxBone(width: 48, height: 12)]),
          const SizedBox(height: 12),
        ],
        if (chips) ...[
          const Row(children: [
            NxBone(width: 64, height: 30, radius: 15),
            SizedBox(width: 8),
            NxBone(width: 64, height: 30, radius: 15),
            SizedBox(width: 8),
            NxBone(width: 64, height: 30, radius: 15),
          ]),
          const SizedBox(height: 12),
        ],
        child,
      ]),
    );
  }
}

/// ลงเวลา: status line with the round clock button, then the work counters.
class _TodayBody extends StatelessWidget {
  const _TodayBody();

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        NxBone(width: 44, height: 44, radius: 14),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NxBoneLine(0.5, height: 15),
            SizedBox(height: 8),
            NxBoneLine(0.7, height: 11),
          ]),
        ),
        SizedBox(width: 12),
        NxBone(width: 92, height: 44, radius: 22),
      ]),
      SizedBox(height: 18),
      Row(children: [
        Expanded(child: NxBone(height: 52, radius: 14)),
        SizedBox(width: 8),
        Expanded(child: NxBone(height: 52, radius: 14)),
        SizedBox(width: 8),
        Expanded(child: NxBone(height: 52, radius: 14)),
      ]),
    ]);
  }
}

/// ไอแซคแนะนำ: sticker, two lines of suggestion.
class _AiBody extends StatelessWidget {
  const _AiBody();

  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      NxBone.circle(44),
      SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NxBoneLine(0.4, height: 14),
          SizedBox(height: 8),
          NxBoneLine(0.9, height: 11),
          SizedBox(height: 6),
          NxBoneLine(0.7, height: 11),
        ]),
      ),
    ]);
  }
}

/// ทางลัด: a row of round shortcut tiles with labels.
class _QuickBody extends StatelessWidget {
  const _QuickBody({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = c.maxWidth >= 560 ? 8 : 4;
      return Row(children: [
        for (var i = 0; i < n; i++)
          const Expanded(
            child: Column(children: [
              NxBone(width: 52, height: 52, radius: 18),
              SizedBox(height: 8),
              NxBone(width: 44, height: 10),
            ]),
          ),
      ]);
    });
  }
}

/// ภาพรวม: title, then stat cards in a strip.
class _StatsBody extends StatelessWidget {
  const _StatsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const NxBone(width: 72, height: 15),
      const SizedBox(height: 10),
      SizedBox(
        height: 112,
        child: ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            maxWidth: double.infinity,
            child: Row(children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                const SizedBox(
                  width: 140,
                  child: NxSkeletonCard(
                    margin: EdgeInsets.zero,
                    height: 112,
                    padding: EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NxBone.circle(28),
                      Spacer(),
                      NxBone(width: 48, height: 20),
                      SizedBox(height: 6),
                      NxBone(width: 72, height: 10),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}
