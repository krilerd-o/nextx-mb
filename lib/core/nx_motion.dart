import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// iOS-style springs (Marcel / Consi) — fast launch, long settle tail.
class NxMotion {
  NxMotion._();

  /// Critically damped — nav capsule, fades, progress. No bounce.
  static const SpringDescription settle = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 26.8,
  );

  /// Slightly underdamped — sheets released with momentum.
  static const SpringDescription sheet = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 22,
  );

  static const SpringDescription press = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 28,
  );

  /// Approximates spring long-tail when a Curve is required.
  static const Curve settleCurve = Cubic(0.16, 1, 0.3, 1);

  static bool reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, [int milliseconds = 400]) {
    if (reduced(context)) return Duration.zero;
    return Duration(milliseconds: milliseconds);
  }

  static Simulation spring(SpringDescription desc, {double from = 0, double to = 1, double velocity = 0}) {
    return SpringSimulation(desc, from, to, velocity);
  }
}

Duration nxMotion(BuildContext context, [int milliseconds = 220]) {
  return NxMotion.duration(context, milliseconds);
}
