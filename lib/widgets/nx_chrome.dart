import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Icon a collapsed toolbar leaves in the header (search, filter, view…).
@immutable
class NxChromeAction {
  const NxChromeAction({required this.id, required this.icon, required this.tooltip, required this.onTap, this.badge = 0, this.pinned = false});

  /// Shown in the header all the time, not only while the toolbar is folded
  /// (search / filter live as header icons by default).
  final bool pinned;

  final String id;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  bool same(NxChromeAction o) => o.id == id && o.icon == icon && o.badge == badge && o.tooltip == tooltip && o.pinned == pinned;
}

/// App-wide signals for chrome outside a page (the shell's tab bar).
class NxChromeBus {
  NxChromeBus._();

  /// The visible page scrolled into its content: tab bar slides away.
  static final hidden = ValueNotifier<bool>(false);

  /// A card is being dragged (Kanban): tab bar and FAB make room for the dock.
  static final dragging = ValueNotifier<bool>(false);

  static void reset() {
    hidden.value = false;
    dragging.value = false;
  }
}

/// Page chrome state: collapsed while the user reads further into the content
/// (scrolling down), expanded again on a small scroll back or near the top.
/// [NxScrollScaffold] owns one; toolbars collapse into header icons with it.
class NxChrome extends ChangeNotifier {
  bool _collapsed = false;
  double _acc = 0;
  final Map<Object, List<NxChromeAction>> _actions = {};
  bool _notifyQueued = false;
  bool _disposed = false;

  bool get collapsed => _collapsed;

  /// Header icons registered by collapsed toolbars, in registration order.
  List<NxChromeAction> get actions => [for (final l in _actions.values) ...l];

  static const collapseAfter = 24.0;
  static const expandAfter = 12.0;

  void setCollapsed(bool v) {
    if (v == _collapsed) return;
    _collapsed = v;
    NxChromeBus.hidden.value = v;
    _notify();
  }

  void expand() {
    _acc = 0;
    setCollapsed(false);
  }

  void setActions(Object owner, List<NxChromeAction> list) {
    final old = _actions[owner];
    if (old != null && old.length == list.length && [for (var i = 0; i < list.length; i++) old[i].same(list[i])].every((e) => e)) {
      _actions[owner] = list; // same look, fresh callbacks
      return;
    }
    _actions[owner] = list;
    _notify();
  }

  void removeActions(Object owner) {
    if (_actions.remove(owner) != null) _notify();
  }

  /// Feed vertical scroll updates; returns false so others still see them.
  bool handleScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;
    final m = n.metrics;
    // Short lists never collapse (nothing to make room for).
    if (m.maxScrollExtent - m.minScrollExtent < 48) return false;
    if (m.pixels <= m.minScrollExtent + 8) {
      expand();
      return false;
    }
    final d = n.scrollDelta ?? 0;
    if (d > 0) {
      _acc = (_acc < 0 ? 0 : _acc) + d;
      if (_acc > collapseAfter) setCollapsed(true);
    } else if (d < 0) {
      _acc = (_acc > 0 ? 0 : _acc) + d;
      if (_acc < -expandAfter) setCollapsed(false);
    }
    return false;
  }

  // Registration happens during build: notify after the frame.
  void _notify() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyQueued) return;
    _notifyQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Listening lookup (rebuilds on change); null outside an [NxScrollScaffold].
  static NxChrome? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NxChromeScope>()?.notifier;

  /// Non-listening lookup.
  static NxChrome? maybeRead(BuildContext context) => context.getInheritedWidgetOfExactType<NxChromeScope>()?.notifier;
}

class NxChromeScope extends InheritedNotifier<NxChrome> {
  const NxChromeScope({super.key, required NxChrome chrome, required super.child}) : super(notifier: chrome);
}

/// Folds [child] away (height + fade) while the page chrome is collapsed.
class NxChromeCollapse extends StatelessWidget {
  const NxChromeCollapse({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chrome = NxChrome.of(context);
    if (!enabled || chrome == null) return child;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: chrome.collapsed ? 0 : 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v,
          child: Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: IgnorePointer(ignoring: v < 0.5, child: child),
          ),
        ),
      ),
    );
  }
}

/// Listens to scroll notifications from [child] into the nearest/own chrome.
class NxChromeScrollListener extends StatelessWidget {
  const NxChromeScrollListener({super.key, required this.chrome, required this.child});
  final NxChrome chrome;
  final Widget child;

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(onNotification: chrome.handleScroll, child: child);
}
