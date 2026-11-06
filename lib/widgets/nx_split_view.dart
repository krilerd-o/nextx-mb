import 'package:flutter/material.dart';

import '../core/nx_breakpoint.dart';

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
            pageBuilder: (ctx, _, __) => const _ListProxy(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
      );
    }
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
          color: Theme.of(context).colorScheme.outline.withOpacity(0.35),
        ),
        Expanded(
          child: detail ??
              empty ??
              Center(
                child: Text(
                  'เลือกจากรายการ',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
        ),
      ],
    );
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
