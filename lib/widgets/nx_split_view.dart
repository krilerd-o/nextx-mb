import 'package:flutter/material.dart';

import 'nx_back_handler.dart';

import '../core/nx_breakpoint.dart';
import '../core/i18n.dart';

class NxSplitView extends StatelessWidget {
  const NxSplitView({
    super.key,
    required this.list,
    this.detail,
    this.empty,
    this.onClose,
  });

  final Widget list;
  final Widget? detail;
  final Widget? empty;

  /// Two-pane: system back closes the open detail first (clear the selection).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    if (!bp.twoPane) {
      return _ListScope(
        list: list,
        child: Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (ctx, _, _) => const _ListProxy(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
      );
    }
    final hinge = bp.hinge;
    final Widget split = hinge != null ? NxHingeSplit(hinge: hinge, list: list, detail: _detail(context)) : _row(context, bp);
    if (onClose == null) return split;
    return NxBackHandler(active: detail != null, onBack: onClose!, child: split);
  }

  Widget _row(BuildContext context, NxBreakpoint bp) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: bp.listPaneWidth,
          child: list,
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
        ),
        Expanded(child: _detail(context)),
      ],
    );
  }

  Widget _detail(BuildContext context) =>
      detail ??
      empty ??
      Center(
        child: Text(
          tr('เลือกจากรายการ'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

/// List on one side of a foldable's fold, detail on the other — nothing sits
/// under the hinge. The hinge rect is global, so the split is measured from
/// where this view actually starts on screen (e.g. after a side rail).
class NxHingeSplit extends StatefulWidget {
  const NxHingeSplit({super.key, required this.hinge, required this.list, required this.detail});
  final Rect hinge;
  final Widget list;
  final Widget detail;

  @override
  State<NxHingeSplit> createState() => _NxHingeSplitState();
}

class _NxHingeSplitState extends State<NxHingeSplit> {
  double _originX = 0;

  void _measure() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final x = box.localToGlobal(Offset.zero).dx;
    if ((x - _originX).abs() > 0.5 && mounted) setState(() => _originX = x);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final left = (widget.hinge.left - _originX).clamp(0.0, box.maxWidth);
      final gap = widget.hinge.width.clamp(0.0, box.maxWidth - left);
      return Row(
        key: const ValueKey('nx-hinge-split'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: left, child: widget.list),
          // A physical hinge has width (leave it empty); a flexible fold is a line.
          gap > 0 ? SizedBox(width: gap) : VerticalDivider(width: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.35)),
          Expanded(child: widget.detail),
        ],
      );
    });
  }
}

class _ListScope extends InheritedWidget {
  const _ListScope({required this.list, required super.child});

  final Widget list;

  static Widget of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ListScope>()!.list;
  }

  @override
  bool updateShouldNotify(_ListScope oldWidget) => list != oldWidget.list;
}

class _ListProxy extends StatelessWidget {
  const _ListProxy();

  @override
  Widget build(BuildContext context) => _ListScope.of(context);
}

/// Hosts a full detail screen inside the right pane of a split view.
/// It gets its own navigator, so the screen shows no back arrow, a pop from
/// inside (e.g. after delete) stays in the pane, and pages it opens stack
/// inside the pane with their own back button.
class NxPaneHost extends StatelessWidget {
  const NxPaneHost({super.key, required this.child, this.onPopRoot});
  final Widget child;

  /// The hosted screen tried to close itself (e.g. after delete).
  final VoidCallback? onPopRoot;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: HeroControllerScope.none(
        child: NavigatorPopHandler(
          onPopWithResult: (_) => onPopRoot?.call(),
          child: Navigator(
            onGenerateRoute: (s) => MaterialPageRoute<void>(settings: s, builder: (_) => child),
          ),
        ),
      ),
    );
  }
}
