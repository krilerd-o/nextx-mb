import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nx_motion.dart';
import 'nx_press_scale.dart';
import 'nx_glass.dart';
import '../core/i18n.dart';

class NxTabDestination {
  const NxTabDestination({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class NxTabNav extends StatelessWidget {
  const NxTabNav({super.key, required this.destinations, required this.selectedIndex, required this.onSelect, this.rail = false, this.docked = false, this.badges = const {}});

  /// Floating card height (icon circle + label) — matches the tab-setup preview.
  static const double barHeight = 76;
  static const double railWidth = 76;
  static const double inset = 8;
  static const double dot = 42;

  final List<NxTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;
  final bool rail;

  /// Tablet: only the glass card (rail column or compact bar) — the shell
  /// places it at the chosen dock position.
  final bool docked;

  /// Unread counts per destination index (0 / missing = no badge).
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    if (docked) {
      if (rail) return _RailCard(nav: this);
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: destinations.length * 84.0 + 12),
        child: NxTabBarCard(destinations: destinations, selectedIndex: selectedIndex, onSelect: onSelect, badges: badges),
      );
    }
    return rail ? _Rail(nav: this) : _Bar(nav: this);
  }
}

/// The bar body without the safe-area / floating padding — used live and in
/// the onboarding preview so both always look the same.
class NxTabBarCard extends StatelessWidget {
  const NxTabBarCard({super.key, required this.destinations, required this.selectedIndex, this.onSelect, this.badges = const {}});

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
        child: Stack(
          children: [
            // One highlight that slides (and stretches a little) to the tapped menu.
            if (selectedIndex >= 0 && selectedIndex < destinations.length)
              Positioned.fill(
                child: _SlidingDot(count: destinations.length, index: selectedIndex),
              ),
            Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _Item(
                      dest: destinations[i],
                      selected: i == selectedIndex,
                      ownDot: false,
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
          ],
        ),
      ),
    );
  }
}

/// The selected menu's highlight: slides from the old menu to the new one and
/// stretches into a short pill while moving. Same column layout as `_Item`
/// (dot, gap, one invisible label line) so it sits exactly under the icon.
class _SlidingDot extends StatelessWidget {
  const _SlidingDot({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11, height: 1.2, fontWeight: FontWeight.w700);
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: const ValueKey('nx-tab-sliding-dot'),
        tween: Tween(end: index.toDouble()),
        duration: NxMotion.duration(context, 420),
        curve: Curves.easeOutCubic,
        builder: (context, pos, _) {
          final x = count <= 1 ? 0.0 : -1 + 2 * pos / (count - 1);
          // Still moving → stretch sideways a little (liquid feel), settle to a circle.
          final stretch = 1 + ((pos - index).abs() * 0.6).clamp(0.0, 0.45);
          return Align(
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: NxTabNav.dot * stretch,
                    height: NxTabNav.dot,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(NxTabNav.dot),
                      boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Opacity(opacity: 0, child: Text('ก', maxLines: 1, style: labelStyle)),
                ],
              ),
            ),
          );
        },
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
      child: NxTabBarCard(destinations: nav.destinations, selectedIndex: nav.selectedIndex, onSelect: nav.onSelect, badges: nav.badges),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.nav});
  final NxTabNav nav;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _RailCard(nav: nav),
        ),
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.nav});
  final NxTabNav nav;

  @override
  Widget build(BuildContext context) {
    final n = nav.destinations.length;
    return SizedBox(
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
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.dest, required this.selected, required this.onTap, this.badge = 0, this.ownDot = true});

  final NxTabDestination dest;
  final bool selected;

  /// false = the bar draws one sliding highlight behind all items.
  final bool ownDot;
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
        color: selected && ownDot ? cs.primary : cs.primary.withValues(alpha: 0),
        shape: BoxShape.circle,
        boxShadow: selected && ownDot ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: d,
        child: Icon(selected ? dest.selectedIcon : dest.icon, key: ValueKey(selected), size: 20, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
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
                    tr(badge > 99 ? '99+' : '$badge'),
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
      label: tr(dest.label),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          withBadge,
          const SizedBox(height: 4),
          Text(
            tr(dest.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 11, height: 1.2, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? cs.onSurface : cs.onSurfaceVariant),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return NxPressScale(onTap: onTap!, child: body);
  }
}
