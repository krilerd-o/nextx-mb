import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nx_icons.dart';
import '../core/i18n.dart';

/// One floating "app card" in the hero art.
class NxHeroChip {
  const NxHeroChip(this.icon, this.title, this.subtitle, this.alignment, {this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final Alignment alignment;
  final Color? color;
}

const kDefaultHeroChips = [
  NxHeroChip(NxI.clock, 'ลงเวลาแล้ว 08:58', 'เข้างานตรงเวลา', Alignment(-0.92, -0.35), color: Color(0xFF10B981)),
  NxHeroChip(NxI.handshake, 'ดีลใหม่ ฿120k', 'บริษัท เอ จำกัด', Alignment(0.95, -0.05), color: Color(0xFFF59E0B)),
  NxHeroChip(NxI.chatCircle, 'แชททีม · 3 ข้อความ', 'ประชุมบ่ายนี้ 14:00', Alignment(-0.55, 0.72), color: Color(0xFF0EA5E9)),
];

/// Code-drawn hero art for the welcome / login screens: soft gradient,
/// concentric arcs and floating UI cards that bob gently. No image assets.
class NxHeroIllustration extends StatefulWidget {
  const NxHeroIllustration({
    super.key,
    this.height = 320,
    this.chips = kDefaultHeroChips,
    this.centerIcon = NxI.squaresFourFill,
    this.animate = true,
  });

  final double height;
  final List<NxHeroChip> chips;
  final IconData centerIcon;
  final bool animate;

  @override
  State<NxHeroIllustration> createState() => _NxHeroIllustrationState();
}

class _NxHeroIllustrationState extends State<NxHeroIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = Color.lerp(cs.primary, Colors.white, dark ? 0.55 : 0.82)!;
    final bottom = dark ? cs.surface : Colors.white;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [dark ? Color.lerp(cs.primary, Colors.black, 0.55)! : top, bottom],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _ArcsPainter(color: cs.primary, dark: dark))),
            Align(
              alignment: const Alignment(0, 0.05),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14)),
                  ],
                ),
                child: Icon(widget.centerIcon, color: Colors.white, size: 44),
              ),
            ),
            for (var i = 0; i < widget.chips.length; i++)
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final phase = _c.value * 2 * math.pi + i * 2.1;
                  return Align(
                    alignment: widget.chips[i].alignment,
                    child: Transform.translate(offset: Offset(0, math.sin(phase) * 6), child: child),
                  );
                },
                child: _HeroChipCard(chip: widget.chips[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroChipCard extends StatelessWidget {
  const _HeroChipCard({required this.chip});
  final NxHeroChip chip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = chip.color ?? theme.colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(chip.icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(chip.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(tr(chip.subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcsPainter extends CustomPainter {
  _ArcsPainter({required this.color, required this.dark});
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.52);
    for (var i = 0; i < 4; i++) {
      final r = size.width * (0.22 + i * 0.16);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: (dark ? 0.10 : 0.07) - i * 0.012);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcsPainter old) => old.color != color || old.dark != dark;
}
