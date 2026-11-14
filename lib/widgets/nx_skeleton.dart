import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/effects.dart';
import '../core/nx_breakpoint.dart';

/// Loading placeholder in the theme's own colours.
///
/// - Shown only when loading is slow: invisible for [delay] (250ms), then
///   fades in, so fast loads never flash a skeleton.
/// - One shimmer controller per skeleton; bones read it (no ShaderMask over
///   the whole tree), repaint inside a [RepaintBoundary], and the shimmer runs
///   only on full effects (lite / off / reduced motion: still bones) and pauses
///   while the page is off screen.
class NxSkeleton extends StatefulWidget {
  const NxSkeleton({super.key, required this.child, this.delay = const Duration(milliseconds: 250)});

  final Widget child;
  final Duration delay;

  @override
  State<NxSkeleton> createState() => _NxSkeletonState();
}

class _NxSkeletonState extends State<NxSkeleton> with TickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 150);
  late final AnimationController _appear = AnimationController(vsync: this, duration: widget.delay + _fade)..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _appear,
    curve: Interval(widget.delay.inMicroseconds / (widget.delay + _fade).inMicroseconds, 1, curve: Curves.easeOut),
  );
  AnimationController? _shimmer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lite ("เบา") too: a moving gradient on every bone repaints the whole skeleton each frame,
    // which low-end phones feel while the page behind it is still loading.
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true || Effects.of(context) != EffectsLevel.full;
    if (still) {
      _shimmer?.dispose();
      _shimmer = null;
    } else {
      _shimmer ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _shimmer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: RepaintBoundary(
        child: _ShimmerScope(
          animation: _shimmer ?? const AlwaysStoppedAnimation<double>(-1),
          child: IgnorePointer(child: ExcludeSemantics(child: widget.child)),
        ),
      ),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});
  final Animation<double> animation;

  static Animation<double>? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// Theme colours for skeletons: the real card colour, and bones/highlight as
/// faint tints of the text colour (never pure white), so any accent fits.
class NxSkeletonColors {
  const NxSkeletonColors({required this.card, required this.bone, required this.highlight});
  final Color card;
  final Color bone;
  final Color highlight;

  static NxSkeletonColors of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return NxSkeletonColors(
      card: theme.cardTheme.color ?? cs.surface,
      bone: cs.onSurface.withValues(alpha: dark ? 0.08 : 0.06),
      highlight: cs.onSurface.withValues(alpha: dark ? 0.14 : 0.10),
    );
  }
}

class NxBone extends StatelessWidget {
  const NxBone({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = NxSkeletonColors.of(context);
    final shimmer = _ShimmerScope.of(context);
    BoxDecoration deco(double t) => BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: t < 0 ? c.bone : null,
          gradient: t < 0
              ? null
              : LinearGradient(
                  begin: Alignment(-2.2 + t * 4.4, 0),
                  end: Alignment(-1.2 + t * 4.4, 0),
                  colors: [c.bone, c.highlight, c.bone],
                ),
        );
    if (shimmer == null || shimmer.value < 0) {
      return Container(width: width, height: height, decoration: deco(-1));
    }
    return AnimatedBuilder(
      animation: shimmer,
      builder: (_, _) => Container(width: width, height: height, decoration: deco(shimmer.value)),
    );
  }
}

/// A card in the theme's card colour.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16), this.margin = const EdgeInsets.only(bottom: 12)});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(color: NxSkeletonColors.of(context).card, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      child: child,
    );
  }
}

/// List rows like the app's list cards: code · title · chip · avatar.
class NxSkeletonList extends StatelessWidget {
  const NxSkeletonList({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    // shrinkWrap so it also works nested inside another ListView while loading.
    return NxSkeleton(
      child: ListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [NxBone(width: 16, height: 16, radius: 5), SizedBox(width: 8), NxBone(width: 72, height: 11)]),
        const SizedBox(height: 10),
        FractionallySizedBox(widthFactor: wide ? 0.78 : 0.56, child: const NxBone(height: 16)),
        const SizedBox(height: 12),
        const Row(children: [NxBone(width: 96, height: 22, radius: 11), Spacer(), NxBone(width: 28, height: 28, radius: 14)]),
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
              decoration: BoxDecoration(
                color: NxSkeletonColors.of(context).bone.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius + 4),
              ),
              child: Column(children: [
                const NxBone(width: 64, height: 14),
                const SizedBox(height: 6),
                const NxBone(width: 40, height: 11),
                const SizedBox(height: 14),
                for (var i = 0; i < 3 - c; i++) _ListCard(wide: i.isEven),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Record / task detail: path, title, stepper, two field groups.
class NxSkeletonDetail extends StatelessWidget {
  const NxSkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) {
    Widget group(int n) => _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NxBone(width: 90, height: 12),
            const SizedBox(height: 14),
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  const NxBone(width: 18, height: 18, radius: 6),
                  const SizedBox(width: 12),
                  const NxBone(width: 70, height: 12),
                  const SizedBox(width: 16),
                  Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: i.isEven ? 0.9 : 0.6, child: const NxBone(height: 12))),
                ]),
              ),
          ]),
        );
    return NxSkeleton(
      child: ListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const NxBone(width: 140, height: 11),
          const SizedBox(height: 10),
          const FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.8, child: NxBone(height: 22, radius: 10)),
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < 4; i++) ...[
              const Expanded(child: NxBone(height: 8, radius: 4)),
              if (i < 3) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 18),
          group(4),
          group(3),
        ],
      ),
    );
  }
}

/// Calendar: week strip + event rows.
class NxSkeletonCalendar extends StatelessWidget {
  const NxSkeletonCalendar({super.key});

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: ListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            for (var i = 0; i < 7; i++)
              const Expanded(
                child: Column(children: [NxBone(width: 18, height: 10), SizedBox(height: 8), NxBone(width: 30, height: 30, radius: 15)]),
              ),
          ]),
          const SizedBox(height: 18),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(width: 44, child: NxBone(width: 36, height: 11)),
                Expanded(
                  child: _Card(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.5, child: const NxBone(height: 14)),
                      const SizedBox(height: 8),
                      const NxBone(width: 110, height: 11),
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

/// Chat: bubbles left and right.
class NxSkeletonChat extends StatelessWidget {
  const NxSkeletonChat({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return NxSkeleton(
      child: ListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: i.isOdd ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (i.isEven) ...[const NxBone(width: 30, height: 30, radius: 15), const SizedBox(width: 8)],
                  NxBone(width: w * (i % 3 == 0 ? 0.62 : 0.44), height: i % 3 == 0 ? 56 : 38, radius: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small placeholder inside a home box.
class NxSkeletonBox extends StatelessWidget {
  const NxSkeletonBox({super.key, this.rows = 3});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const NxBone(width: 22, height: 22, radius: 7),
                const SizedBox(width: 10),
                Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: i.isEven ? 0.85 : 0.6, child: const NxBone(height: 13))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class NxSkeletonKpiGrid extends StatelessWidget {
  const NxSkeletonKpiGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final cols = NxBreakpoint.of(context).gridColumns.clamp(1, 4);
    return NxSkeleton(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < cols.clamp(2, 4); i++)
            SizedBox(
              width: cols == 1 ? double.infinity : (MediaQuery.sizeOf(context).width - 40 - 12 * (cols - 1)) / cols,
              child: const _Card(
                margin: EdgeInsets.zero,
                child: SizedBox(
                  height: 88,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NxBone(width: 36, height: 36, radius: 18),
                      Spacer(),
                      NxBone(width: 80, height: 24),
                      SizedBox(height: 8),
                      NxBone(width: 64, height: 12),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NxSkeletonForm extends StatelessWidget {
  const NxSkeletonForm({super.key, this.fields = 8});

  final int fields;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (var i = 0; i < fields; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: NxBone(height: 52, radius: 14),
            ),
        ],
      ),
    );
  }
}
