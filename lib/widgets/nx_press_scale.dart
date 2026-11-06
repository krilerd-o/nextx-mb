import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/nx_motion.dart';

class NxPressScale extends StatefulWidget {
  const NxPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.minScale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double minScale;

  @override
  State<NxPressScale> createState() => _NxPressScaleState();
}

class _NxPressScaleState extends State<NxPressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _to(double target) {
    if (NxMotion.reduced(context)) {
      _c.value = target;
      return;
    }
    _c.animateWith(
      SpringSimulation(NxMotion.press, _c.value, target, _c.velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.onTap == null && widget.onLongPress == null ? null : (_) => _to(widget.minScale),
      onPointerUp: widget.onTap == null && widget.onLongPress == null ? null : (_) => _to(1),
      onPointerCancel: widget.onTap == null && widget.onLongPress == null ? null : (_) => _to(1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.scale(scale: _c.value, child: child),
          child: widget.child,
        ),
      ),
    );
  }
}
