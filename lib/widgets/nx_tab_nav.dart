import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nx_motion.dart';
import 'nx_press_scale.dart';
import 'nx_glass.dart';

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
    this.badges = const {},
  });

  /// Floating card height (icon circle + label) — matches the tab-setup preview.
  static const double barHeight = 76;
  static const double railWidth = 76;
  static const double inset = 8;
  static const double dot = 42;

  final List<NxTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;
  final bool rail;

  /// Unread counts per destination index (0 / missing = no badge).
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    return rail ? _Rail(nav: this) : _Bar(nav: this);
  }
}

/// The bar body without the safe-area / floating padding — used live and in
/// the onboarding preview so both always look the same.
class NxTabBarCard extends StatelessWidget {
  const NxTabBarCard({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    this.onSelect,
    this.badges = const {},
  });

  final List<NxTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    return NxGlass(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: NxTabNav.inset),
      child: SizedBox(
        height: NxTabNav.barHeight - NxTabNav.inset * 2,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _Item(
                  dest: destinations[i],
                  selected: i == selectedIndex,
                  badge: badges[i] ?? 0,
                  onTap: onSelect == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onSelect!(i);
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.nav});
  final NxTabNav nav;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final wide = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide > 560 ? (wide - 528) / 2 : 16, 0, wide > 560 ? (wide - 528) / 2 : 16, 10 + pad.bottom),
      child: NxTabBarCard(
        destinations: nav.destinations,
        selectedIndex: nav.selectedIndex,
        onSelect: nav.onSelect,
        badges: nav.badges,
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
          child: SizedBox(
            width: NxTabNav.railWidth,
            child: NxGlass(
              radius: 26,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < n; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _Item(
                        dest: nav.destinations[i],
                        selected: i == nav.selectedIndex,
                        badge: nav.badges[i] ?? 0,
                        onTap: nav.onSelect == null
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                nav.onSelect!(i);
                              },
                      ),
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
    this.badge = 0,
  });

  final NxTabDestination dest;
  final bool selected;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = NxMotion.duration(context, 360);
    final circle = AnimatedContainer(
      duration: d,
      curve: NxMotion.settleCurve,
      width: NxTabNav.dot,
      height: NxTabNav.dot,
      decoration: BoxDecoration(
        color: selected ? cs.primary : cs.primary.withValues(alpha: 0),
        shape: BoxShape.circle,
        boxShadow: selected ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: d,
        child: Icon(
          selected ? dest.selectedIcon : dest.icon,
          key: ValueKey(selected),
          size: 20,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
    final withBadge = badge <= 0
        ? circle
        : Stack(
            clipBehavior: Clip.none,
            children: [
              circle,
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onError, fontSize: 10, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                ),
              ),
            ],
          );
    final body = Semantics(
      button: true,
      selected: selected,
      label: dest.label,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          withBadge,
          const SizedBox(height: 4),
          Text(
            dest.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return NxPressScale(onTap: onTap!, child: body);
  }
}
