import 'package:flutter/material.dart';

/// "Back closes this first" for in-page state: an open search, a selected
/// row in a two-pane list, a sub-folder…
///
/// - Inside a shell tab the shell owns system back (it decides tab → home →
///   exit), so the handler registers with [NxShellBack] under that tab and
///   only runs while that tab is showing.
/// - On a pushed page it is a plain [PopScope].
class NxBackHandler extends StatefulWidget {
  const NxBackHandler({super.key, required this.active, required this.onBack, required this.child});

  /// true while there is something for back to close.
  final bool active;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<NxBackHandler> createState() => _NxBackHandlerState();
}

class _NxBackHandlerState extends State<NxBackHandler> {
  String? _tab;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = NxShellTabScope.maybeOf(context);
    if (tab != _tab) {
      NxShellBack.instance._remove(this);
      _tab = tab;
      if (tab != null) NxShellBack.instance._add(this);
    }
  }

  @override
  void dispose() {
    NxShellBack.instance._remove(this);
    super.dispose();
  }

  bool _tryHandle() {
    if (!mounted || !widget.active) return false;
    widget.onBack();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_tab != null) return widget.child;
    return PopScope(
      canPop: !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active) widget.onBack();
      },
      child: widget.child,
    );
  }
}

/// Marks the subtree of one shell tab (set by the app shell).
class NxShellTabScope extends InheritedWidget {
  const NxShellTabScope({super.key, required this.tabId, required super.child});
  final String tabId;

  static String? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NxShellTabScope>()?.tabId;

  @override
  bool updateShouldNotify(NxShellTabScope old) => old.tabId != tabId;
}

/// Back handlers registered by shell tabs; newest (deepest) first.
class NxShellBack {
  NxShellBack._();
  static final instance = NxShellBack._();
  final List<_NxBackHandlerState> _handlers = [];

  void _add(_NxBackHandlerState s) => _handlers.add(s);
  void _remove(_NxBackHandlerState s) => _handlers.remove(s);

  /// Runs the newest active handler of [tabId]; false when none.
  bool handle(String tabId) {
    for (final h in _handlers.reversed.toList()) {
      if (h._tab == tabId && h._tryHandle()) return true;
    }
    return false;
  }
}
