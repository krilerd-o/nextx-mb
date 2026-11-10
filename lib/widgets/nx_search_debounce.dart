import 'dart:async';

import 'package:flutter/material.dart';

/// How long after the last keystroke a search runs by itself. The keyboard's
/// Search key (or Enter) runs it straight away.
const Duration kSearchDelay = Duration(milliseconds: 2500);

/// Typing → wait [delay] → run. Restarts on every keystroke; [flush] runs now.
class NxSearchDebounce extends ChangeNotifier {
  NxSearchDebounce({this.delay = kSearchDelay});

  final Duration delay;
  Timer? _timer;
  VoidCallback? _run;

  /// Changes on every restart, so the countdown ring starts over.
  int tick = 0;

  bool get pending => _timer?.isActive ?? false;

  void schedule(VoidCallback run) {
    _timer?.cancel();
    _run = run;
    tick++;
    _timer = Timer(delay, () {
      final r = _run;
      _run = null;
      notifyListeners();
      r?.call();
    });
    notifyListeners();
  }

  /// Run the waiting search now (keyboard Search / Enter).
  void flush() {
    final r = _run;
    cancel();
    r?.call();
  }

  void cancel() {
    final was = pending;
    _timer?.cancel();
    _timer = null;
    _run = null;
    if (was) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Small ring that fills while a search is counting down (shown in the box).
class NxSearchCountdown extends StatelessWidget {
  const NxSearchCountdown({super.key, required this.debounce, this.size = 18});

  final NxSearchDebounce debounce;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: debounce,
      builder: (context, _) {
        if (!debounce.pending) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            key: const ValueKey('nx-search-countdown'),
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(debounce.tick),
              tween: Tween(begin: 0, end: 1),
              duration: debounce.delay,
              builder: (context, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 2.2,
                backgroundColor: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      },
    );
  }
}
