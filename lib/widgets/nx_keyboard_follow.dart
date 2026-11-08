import 'dart:async';

import 'package:flutter/widgets.dart';

/// App-wide: when the keyboard opens (or grows) while a text field has focus,
/// scroll that field into view once the keyboard has settled. Flutter tries
/// this itself, but on some phones it runs mid-animation and the comment box
/// stays under the keyboard; this runs again after the insets stop changing.
class NxKeyboardFollow extends StatefulWidget {
  const NxKeyboardFollow({super.key, required this.child});
  final Widget child;

  @override
  State<NxKeyboardFollow> createState() => _NxKeyboardFollowState();
}

class _NxKeyboardFollowState extends State<NxKeyboardFollow> with WidgetsBindingObserver {
  Timer? _settle;
  double _lastInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settle?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final v = views.first;
    final inset = v.viewInsets.bottom / v.devicePixelRatio;
    final grew = inset > _lastInset + 1;
    _lastInset = inset;
    if (!grew) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 280), _reveal);
  }

  void _reveal() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    // Only text inputs: a TextField's focus node lives inside its EditableText.
    if (ctx.findAncestorWidgetOfExactType<EditableText>() == null) return;
    if (Scrollable.maybeOf(ctx) == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
