import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/nx_breakpoint.dart';

class NxSkeleton extends StatefulWidget {
  const NxSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<NxSkeleton> createState() => _NxSkeletonState();
}

class _NxSkeletonState extends State<NxSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (rect) {
            final t = _c.value;
            return LinearGradient(
              begin: Alignment(-1.2 + t * 2.4, 0),
              end: Alignment(-0.2 + t * 2.4, 0),
              colors: [
                Colors.white.withOpacity(0.35),
                Colors.white,
                Colors.white.withOpacity(0.35),
              ],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: IgnorePointer(child: widget.child),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.85),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class NxSkeletonList extends StatelessWidget {
  const NxSkeletonList({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return NxSkeleton(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: const Row(
                  children: [
                    NxBone(width: 44, height: 44, radius: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NxBone(width: 160, height: 14),
                          SizedBox(height: 8),
                          NxBone(width: 220, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
              width: cols == 1
                  ? double.infinity
                  : (MediaQuery.sizeOf(context).width - 40 - 12 * (cols - 1)) / cols,
              child: Container(
                height: 120,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NxBone(width: 36, height: 36, radius: 18),
                    Spacer(),
                    NxBone(width: 80, height: 28),
                    SizedBox(height: 8),
                    NxBone(width: 64, height: 12),
                  ],
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
