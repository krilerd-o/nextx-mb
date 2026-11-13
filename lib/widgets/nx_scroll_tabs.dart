import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';

/// Pill tabs that slide left / right (built on [TabBar], scrollable).
/// Every tab keeps its natural width and a comfortable 44 px touch target;
/// the selected tab scrolls into view. When all tabs fit they sit centred.
///
/// Used for every in-page tab row in the app (record detail, activity, HR,
/// shop, chat info, workspace…).
class NxScrollTabs extends StatefulWidget {
  const NxScrollTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.icons,
    this.badges,
    this.keyPrefix = 'nx-tab-',
    this.padding = EdgeInsets.zero,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Optional leading icon per tab.
  final List<IconData?>? icons;

  /// Optional count per tab (shown as a small pill; null / 0 = hidden).
  final List<int?>? badges;
  final String keyPrefix;
  final EdgeInsets padding;

  static const height = 44.0;

  /// Extra paint room above / below the track for the selected pill's shadow
  /// (the TabBar's horizontal scroll view clips to its own box).
  static const shadowRoom = 10.0;

  @override
  State<NxScrollTabs> createState() => _NxScrollTabsState();
}

class _NxScrollTabsState extends State<NxScrollTabs> with TickerProviderStateMixin {
  late TabController _ctrl = _make();

  TabController _make() => TabController(
        length: widget.labels.length,
        initialIndex: widget.index.clamp(0, widget.labels.length - 1),
        vsync: this,
        animationDuration: const Duration(milliseconds: 220),
      );

  @override
  void didUpdateWidget(NxScrollTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _ctrl.dispose();
      _ctrl = _make();
    } else if (_ctrl.index != widget.index && widget.index >= 0 && widget.index < widget.labels.length) {
      _ctrl.animateTo(widget.index);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const room = NxScrollTabs.shadowRoom;
    // The track keeps its 44 px; the TabBar (its scroll view clips) reaches
    // [room] past it above and below so the selected pill's shadow is not cut.
    return Padding(
      padding: widget.padding,
      child: SizedBox(
        height: NxScrollTabs.height,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              key: const ValueKey('nx-tabs-track'),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: -room,
              bottom: -room,
              child: _tabBar(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBar(ColorScheme cs) => TabBar(
          controller: _ctrl,
          isScrollable: true,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4 + NxScrollTabs.shadowRoom),
          tabAlignment: TabAlignment.center,
          dividerColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 18),
          labelColor: cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          onTap: (i) {
            if (i == widget.index) return;
            HapticFeedback.selectionClick();
            widget.onChanged(i);
          },
          tabs: [
            for (var i = 0; i < widget.labels.length; i++)
              Tab(
                key: ValueKey('${widget.keyPrefix}$i'),
                height: NxScrollTabs.height - 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icons != null && i < widget.icons!.length && widget.icons![i] != null) ...[
                      Icon(widget.icons![i], size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(tr(widget.labels[i]), maxLines: 1, softWrap: false),
                    if (widget.badges != null && i < widget.badges!.length && (widget.badges![i] ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: i == widget.index ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.badges![i]! > 99 ? '99+' : '${widget.badges![i]}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i == widget.index ? cs.onPrimary : cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
}

/// Shows a pinned copy of a page's tab row under the header once the real
/// row (marked with [anchorKey]) scrolls above [top]. Put it in a [Stack]
/// over the page's scroll view.
class NxStickyTabs extends StatefulWidget {
  const NxStickyTabs({
    super.key,
    required this.controller,
    required this.anchorKey,
    required this.top,
    required this.child,
    this.horizontal = 16,
  });

  final ScrollController controller;
  final GlobalKey anchorKey;
  final double top;
  final double horizontal;
  final Widget child;

  @override
  State<NxStickyTabs> createState() => _NxStickyTabsState();
}

class _NxStickyTabsState extends State<NxStickyTabs> {
  bool _show = false;

  /// While the pinned copy is shown, re-check a few times a second: content above the real row
  /// can grow or shrink (late loads, another tab) without any scroll event. A timer (not a
  /// ticker) so no frames are forced while nothing changes.
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void didUpdateWidget(NxStickyTabs old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_check);
      widget.controller.addListener(_check);
    }
    // The page rebuilt (e.g. another tab was picked): the content above / below the real row
    // can change size and the scroll offset can be clamped without a scroll event, so the
    // pinned copy could stay visible while the real row is on screen. Re-check after layout.
    _recheckAfterLayout();
  }

  bool _recheckQueued = false;
  void _recheckAfterLayout() {
    if (_recheckQueued) return;
    _recheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckQueued = false;
      if (!mounted) return;
      _check(); // re-measures whenever the real row is laid out; otherwise keeps the last pin point
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    _watch?.cancel();
    super.dispose();
  }

  /// Scroll offset at which the real tab row reaches [NxStickyTabs.top]
  /// (remembered: lazy lists drop the row once it is far off screen).
  double? _pinAt;

  void _check() {
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    final anchor = widget.anchorKey.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (anchor is RenderBox && me is RenderBox && anchor.attached && me.attached) {
      // Scroll offset that brings the row to the viewport top (layout-based,
      // so it is right even while the frame is mid-scroll).
      final viewport = RenderAbstractViewport.maybeOf(anchor);
      if (viewport != null && viewport is RenderBox) {
        final reveal = viewport.getOffsetToReveal(anchor, 0).offset;
        final vpTop = (viewport as RenderBox).localToGlobal(Offset.zero).dy - me.localToGlobal(Offset.zero).dy;
        _pinAt = reveal + vpTop - widget.top;
      }
    }
    final at = _pinAt;
    if (at == null) return;
    final show = offset > at;
    if (show != _show) setState(() => _show = show);
    if (_show && _watch == null) {
      _watch = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (mounted) _check();
      });
    } else if (!_show && _watch != null) {
      _watch!.cancel();
      _watch = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: widget.top,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_show,
            child: AnimatedOpacity(
              opacity: _show ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: AnimatedSlide(
                offset: _show ? Offset.zero : const Offset(0, -0.3),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Container(
                  key: const ValueKey('sticky-tabs'),
                  padding: EdgeInsets.fromLTRB(widget.horizontal, 6, widget.horizontal, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.98),
                    border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  child: _show ? widget.child : const SizedBox(height: NxScrollTabs.height),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Swipe the page content left / right to move to the next / previous tab.
/// Horizontal scrollers inside (photo strips, steppers) still win their drags.
class NxSwipeTabs extends StatelessWidget {
  const NxSwipeTabs({super.key, required this.index, required this.count, required this.onChanged, required this.child});

  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 350) return;
        final next = v < 0 ? index + 1 : index - 1;
        if (next < 0 || next >= count) return;
        HapticFeedback.selectionClick();
        onChanged(next);
      },
      child: child,
    );
  }
}
