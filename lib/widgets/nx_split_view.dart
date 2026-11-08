import 'package:flutter/material.dart';

import '../core/nx_breakpoint.dart';
import '../core/i18n.dart';

class NxSplitView extends StatelessWidget {
  const NxSplitView({
    super.key,
    required this.list,
    this.detail,
    this.empty,
  });

  final Widget list;
  final Widget? detail;
  final Widget? empty;

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
    if (hinge != null) return _HingeSplit(hinge: hinge, list: list, detail: _detail(context));
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
class _HingeSplit extends StatefulWidget {
  const _HingeSplit({required this.hinge, required this.list, required this.detail});
  final Rect hinge;
  final Widget list;
  final Widget detail;

  @override
  State<_HingeSplit> createState() => _HingeSplitState();
}

class _HingeSplitState extends State<_HingeSplit> {
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
