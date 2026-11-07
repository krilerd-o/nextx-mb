import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/effects.dart';
import 'nx_surface_card.dart';

/// Frosted surface (expo-backdrop idea): live blur behind on capable devices,
/// translucent fill on [EffectsLevel.lite], solid card on [EffectsLevel.off].
class NxGlass extends StatelessWidget {
  const NxGlass({
    super.key,
    required this.child,
    this.radius = 26,
    this.sigma = 18,
    this.padding,
    this.tint,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final double sigma;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final level = Effects.of(context);
    final base = tint ?? cs.surface;
    final fill = switch (level) {
      EffectsLevel.full => base.withValues(alpha: dark ? 0.62 : 0.72),
      EffectsLevel.lite => base.withValues(alpha: 0.94),
      EffectsLevel.off => base,
    };
    final br = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: br,
        border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.08 : 0.04)),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (level == EffectsLevel.full) {
      body = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: body);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: shadow
            ? (dark
                ? NxSurfaceCard.shadows(true)
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))])
            : null,
      ),
      child: ClipRRect(borderRadius: br, child: RepaintBoundary(child: body)),
    );
  }
}

/// Progressive blur band (blur fades out toward [end]) — for headers and the
/// area under the floating tab bar. Draws nothing below [EffectsLevel.full]
/// except a soft gradient so content still reads.
class NxProgressiveBlur extends StatelessWidget {
  const NxProgressiveBlur({
    super.key,
    required this.height,
    this.begin = Alignment.bottomCenter,
    this.end = Alignment.topCenter,
    this.sigma = 14,
  });

  final double height;
  final Alignment begin;
  final Alignment end;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final level = Effects.of(context);
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [bg.withValues(alpha: level == EffectsLevel.full ? 0.55 : 0.92), bg.withValues(alpha: 0)],
        ),
      ),
    );
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: level != EffectsLevel.full
            ? gradient
            : ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  begin: begin,
                  end: end,
                  colors: const [Colors.black, Colors.transparent],
                ).createShader(r),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: gradient,
                  ),
                ),
              ),
      ),
    );
  }
}
