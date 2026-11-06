import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_theme.dart';
import '../core/nx_breakpoint.dart';
import 'nx_press_scale.dart';
import 'nx_surface_card.dart';

class NxTabDestination {
  const NxTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class NxTabNav extends StatelessWidget {
  const NxTabNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    this.rail = false,
  });

  static const double barHeight = 52;
  static const double railWidth = 72;
  static const double inset = 4;

  final List<NxTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    return rail ? _Rail(nav: this) : _Bar(nav: this);
  }
}

Color _barFill(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? Colors.white : AppTheme.ink;
}

Color _onBar(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? AppTheme.ink : Colors.white;
}

Color _selectedPill(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFFE8E8ED) : const Color(0xFF3A3A3C);
}

Widget _capsule({
  required BuildContext context,
  required Widget child,
  double? width,
  double? height,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: _barFill(context),
      borderRadius: BorderRadius.circular(999),
      boxShadow: NxSurfaceCard.shadows(dark),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.nav});
  final NxTabNav nav;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final n = nav.destinations.length;
    final tight = NxBreakpoint.of(context).isMini;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + pad.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _capsule(
          context: context,
          height: NxTabNav.barHeight,
          child: Padding(
            padding: const EdgeInsets.all(NxTabNav.inset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < n; i++)
                  _Item(
                    dest: nav.destinations[i],
                    selected: i == nav.selectedIndex,
                    compact: tight,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      nav.onSelect(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.nav});
  final NxTabNav nav;

  @override
  Widget build(BuildContext context) {
    final n = nav.destinations.length;
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _capsule(
            context: context,
            width: NxTabNav.railWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: NxTabNav.inset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < n; i++)
                    _Item(
                      dest: nav.destinations[i],
                      selected: i == nav.selectedIndex,
                      vertical: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        nav.onSelect(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.dest,
    required this.selected,
    required this.onTap,
    this.vertical = false,
    this.compact = false,
  });

  final NxTabDestination dest;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onBar = _onBar(context);
    final color = selected ? onBar : onBar.withValues(alpha: 0.55);
    final icon = Icon(selected ? dest.selectedIcon : dest.icon, color: color, size: 22);
    // Lay text out at intrinsic width — AnimatedSize + ellipsis squashes Thai on web refresh.
    final label = Text(
      dest.label,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.visible,
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: GoogleFonts.notoSansThai(
        fontSize: vertical ? 11 : 13,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: onBar,
      ),
    );
    final inner = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (selected) ...[const SizedBox(height: 4), label],
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (selected) ...[const SizedBox(width: 8), label],
            ],
          );

    final hPad = compact ? 8.0 : 12.0;
    return NxPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: NxMotion.duration(context, 400),
        curve: NxMotion.settleCurve,
        width: vertical ? double.infinity : null,
        height: vertical ? null : NxTabNav.barHeight - NxTabNav.inset * 2,
        margin: vertical ? const EdgeInsets.symmetric(vertical: 2) : EdgeInsets.zero,
        padding: selected
            ? (vertical ? const EdgeInsets.fromLTRB(8, 10, 8, 10) : EdgeInsets.fromLTRB(hPad, 0, hPad + 2, 0))
            : (vertical ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10) : EdgeInsets.symmetric(horizontal: hPad)),
        decoration: BoxDecoration(
          color: selected ? _selectedPill(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: inner,
      ),
    );
  }
}
