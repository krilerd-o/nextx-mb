import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shakes its child sideways (e.g. a required field left empty on save).
/// Call `key.currentState?.shake()`.
class NxShake extends StatefulWidget {
  const NxShake({super.key, required this.child});
  final Widget child;

  @override
  State<NxShake> createState() => NxShakeState();
}

class NxShakeState extends State<NxShake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  /// Shake + a short vibration.
  Future<void> shake({bool haptic = true}) async {
    if (haptic) HapticFeedback.heavyImpact();
    await _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Damped sine: 4 swings, fading out.
        final t = _c.value;
        final dx = math.sin(t * math.pi * 8) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// After `Form.validate()` fails: scroll to the first field showing an error
/// and shake it (wrap fields in [NxShake]), with a short vibration.
void nxRevealFormError(BuildContext context) {
  HapticFeedback.heavyImpact();
  FormFieldState? first;
  void visit(Element e) {
    if (first != null) return;
    if (e is StatefulElement && e.state is FormFieldState && (e.state as FormFieldState).hasError) {
      first = e.state as FormFieldState;
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  final f = first;
  if (f == null) return;
  Scrollable.ensureVisible(f.context, alignment: 0.2, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    if (f.mounted) f.context.findAncestorStateOfType<NxShakeState>()?.shake(haptic: false);
  });
}

/// Shakes [key]'s field and vibrates — for custom checks (no Form).
void nxShakeField(GlobalKey<NxShakeState> key) {
  final ctx = key.currentContext;
  if (ctx != null) {
    Scrollable.ensureVisible(ctx, alignment: 0.2, duration: const Duration(milliseconds: 280));
  }
  key.currentState?.shake();
}

/// `label` for a required TextField: bold text with a red " *".
Widget nxRequiredLabel(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Text.rich(
    TextSpan(
      text: text,
      style: const TextStyle(fontWeight: FontWeight.w700),
      children: [TextSpan(text: ' *', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))],
    ),
  );
}
