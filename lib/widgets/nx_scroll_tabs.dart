import 'package:flutter/material.dart';
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
    this.keyPrefix = 'nx-tab-',
    this.padding = EdgeInsets.zero,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Optional leading icon per tab.
  final List<IconData?>? icons;
  final String keyPrefix;
  final EdgeInsets padding;

  static const height = 44.0;

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
    return Padding(
      padding: widget.padding,
      child: Container(
        height: NxScrollTabs.height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: TabBar(
          controller: _ctrl,
          isScrollable: true,
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
