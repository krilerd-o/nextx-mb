import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_theme.dart';
import '../../core/effects.dart';

/// The one shimmer clock of the app: a single [Ticker] that runs only while at
/// least one animated skeleton listens, and stops when the last one goes.
///
/// Every skeleton on screen reads the same phase, and the highlight is placed
/// in screen coordinates, so all of them show one sweep across the page.
class NxShimmerClock extends ChangeNotifier implements ValueListenable<double> {
  NxShimmerClock._();

  static final NxShimmerClock instance = NxShimmerClock._();

  static const period = Duration(milliseconds: 1500);

  Ticker? _ticker;
  int _listeners = 0;
  double _phase = 0;

  /// Tickers ever created (tests: the whole app shares one).
  @visibleForTesting
  int debugTickersCreated = 0;

  /// Skeletons listening right now.
  int get listenerCount => _listeners;

  bool get isTicking => _ticker?.isActive ?? false;

  /// 0‥1 through the current sweep.
  @override
  double get value => _phase;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listeners++;
    if (_listeners == 1) {
      _ticker ??= () {
        debugTickersCreated++;
        return Ticker(_tick, debugLabel: 'NxShimmerClock');
      }();
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners = (_listeners - 1).clamp(0, 1 << 30);
    if (_listeners == 0 && (_ticker?.isActive ?? false)) _ticker!.stop();
  }

  void _tick(Duration elapsed) {
    final p = period.inMicroseconds;
    _phase = (elapsed.inMicroseconds % p) / p;
    notifyListeners();
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // App-wide singleton: never disposed.
  }
}

/// Theme colours for skeletons: the real card colour, and bones/highlight as
/// faint tints of the text colour (never pure white), so any accent fits.
class NxSkeletonColors {
  const NxSkeletonColors({required this.card, required this.bone, required this.highlight});
  final Color card;
  final Color bone;
  final Color highlight;

  static NxSkeletonColors of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return NxSkeletonColors(
      card: theme.extension<NxAtmosphereTokens>()?.cardElevated ?? theme.cardTheme.color ?? cs.surface,
      bone: cs.onSurface.withValues(alpha: dark ? 0.08 : 0.06),
      highlight: cs.onSurface.withValues(alpha: dark ? 0.14 : 0.10),
    );
  }
}

/// Shared paint state of one skeleton: its bones, colours and the sweep's
/// shader for the current frame (built once, used by every bone).
class _ShimmerPaint {
  final Set<_RenderBone> bones = {};
  double phase = -1;
  double viewWidth = 400;
  Color bone = const Color(0x0F000000);
  Color highlight = const Color(0x1A000000);

  Shader? _shader;
  double _shaderPhase = -2;

  /// Gradient in screen coordinates (one band sweeping across the view).
  Shader? shader() {
    if (phase < 0) return null;
    if (_shader != null && _shaderPhase == phase) return _shader;
    final band = (viewWidth * 0.35).clamp(120.0, 360.0);
    final cx = -band + phase * (viewWidth + band * 2);
    _shader = ui.Gradient.linear(Offset(cx - band, 0), Offset(cx + band, 0), [bone, highlight, bone], const [0, 0.5, 1]);
    _shaderPhase = phase;
    return _shader;
  }

  void tick(double p) {
    phase = p;
    for (final b in bones) {
      b.markNeedsPaint();
    }
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.paint, required super.child});
  final _ShimmerPaint paint;

  static _ShimmerPaint? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.paint;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.paint != paint;
}

/// Loading placeholder in the theme's own colours.
///
/// - Shown only when loading is slow: invisible for [delay] (250ms), then
///   fades in, so fast loads never flash a skeleton (it still takes its space).
/// - One listener per skeleton on the app-wide [NxShimmerClock]; bones are
///   plain render boxes that only repaint (no rebuilds, no per-bone animation),
///   and share one gradient laid out in screen coordinates.
/// - The shimmer runs only on full effects; lite / off / reduced motion show
///   still bones. Follows [Effects.preference] live and pauses off screen.
///
/// Inside another skeleton it adds nothing (blocks compose freely).
class NxSkeleton extends StatelessWidget {
  const NxSkeleton({super.key, required this.child, this.delay = const Duration(milliseconds: 250)});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_ShimmerScope>() != null) return child;
    return _NxSkeletonRoot(delay: delay, child: child);
  }
}

class _NxSkeletonRoot extends StatefulWidget {
  const _NxSkeletonRoot({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  State<_NxSkeletonRoot> createState() => _NxSkeletonState();
}

class _NxSkeletonState extends State<_NxSkeletonRoot> with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 150);
  late final AnimationController _appear = AnimationController(vsync: this, duration: widget.delay + _fade)..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _appear,
    curve: Interval(widget.delay.inMicroseconds / (widget.delay + _fade).inMicroseconds, 1, curve: Curves.easeOut),
  );
  final _paint = _ShimmerPaint();
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    Effects.preference.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final animate = MediaQuery.maybeDisableAnimationsOf(context) != true &&
        Effects.of(context) == EffectsLevel.full &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_listening) {
      NxShimmerClock.instance.addListener(_tick);
      _listening = true;
    } else if (!animate && _listening) {
      NxShimmerClock.instance.removeListener(_tick);
      _listening = false;
      _paint.tick(-1);
    }
  }

  void _tick() => _paint.tick(NxShimmerClock.instance.value);

  @override
  void dispose() {
    Effects.preference.removeListener(_sync);
    if (_listening) NxShimmerClock.instance.removeListener(_tick);
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NxSkeletonColors.of(context);
    _paint
      ..bone = c.bone
      ..highlight = c.highlight
      ..viewWidth = MediaQuery.sizeOf(context).width;
    return FadeTransition(
      opacity: _opacity,
      child: RepaintBoundary(
        child: _ShimmerScope(
          paint: _paint,
          child: IgnorePointer(child: ExcludeSemantics(child: widget.child)),
        ),
      ),
    );
  }
}

/// One placeholder shape. Outside an [NxSkeleton] it is a still bone.
class NxBone extends LeafRenderObjectWidget {
  const NxBone({super.key, this.width, this.height = 14, this.radius = 8, this.circle = false});

  /// Null: as wide as the parent allows.
  final double? width;
  final double height;
  final double radius;

  /// Round (avatars); [radius] is ignored.
  final bool circle;

  const NxBone.circle(double size, {super.key})
      : width = size,
        height = size,
        radius = size / 2,
        circle = true;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBone(
        width: width,
        height: height,
        radius: circle ? (width ?? height) / 2 : radius,
        paintState: _ShimmerScope.of(context),
        color: NxSkeletonColors.of(context).bone,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBone)
      ..width = width
      ..height = height
      ..radius = circle ? (width ?? height) / 2 : radius
      ..paintState = _ShimmerScope.of(context)
      ..color = NxSkeletonColors.of(context).bone;
  }
}

class _RenderBone extends RenderBox {
  _RenderBone({double? width, required double height, required double radius, _ShimmerPaint? paintState, required Color color})
      : _width = width,
        _height = height,
        _radius = radius,
        _paintState = paintState,
        _color = color;

  double? _width;
  set width(double? v) {
    if (v == _width) return;
    _width = v;
    markNeedsLayout();
  }

  double _height;
  set height(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  double _radius;
  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  _ShimmerPaint? _paintState;
  set paintState(_ShimmerPaint? v) {
    if (identical(v, _paintState)) return;
    if (attached) _paintState?.bones.remove(this);
    _paintState = v;
    if (attached) _paintState?.bones.add(this);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _paintState?.bones.add(this);
  }

  @override
  void detach() {
    _paintState?.bones.remove(this);
    super.detach();
  }

  @override
  bool get sizedByParent => false;

  Size _sizeFor(BoxConstraints c) {
    final w = _width ?? (c.hasBoundedWidth ? c.maxWidth : 0.0);
    return c.constrain(Size(w, _height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _sizeFor(constraints);

  @override
  double computeMinIntrinsicWidth(double height) => _width ?? 0;
  @override
  double computeMaxIntrinsicWidth(double height) => _width ?? 0;
  @override
  double computeMinIntrinsicHeight(double width) => _height;
  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  void performLayout() {
    size = _sizeFor(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => false;

  static final Paint _fill = Paint();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final r = RRect.fromRectAndRadius(offset & size, Radius.circular(_radius.clamp(0, size.shortestSide / 2)));
    final shader = _paintState?.shader();
    if (shader == null) {
      _fill
        ..shader = null
        ..color = _color;
      context.canvas.drawRRect(r, _fill);
      return;
    }
    // The shader lives in screen coordinates: draw with the canvas moved so that
    // its origin is the screen's, so every bone shows its slice of one sweep.
    final g = localToGlobal(Offset.zero);
    final dx = offset.dx - g.dx;
    final dy = offset.dy - g.dy;
    final canvas = context.canvas
      ..save()
      ..translate(dx, dy);
    _fill
      ..color = const Color(0xFF000000)
      ..shader = shader;
    canvas.drawRRect(r.shift(Offset(-dx, -dy)), _fill);
    canvas.restore();
    _fill.shader = null;
  }
}

/// A card in the theme's card colour (same radius as [NxSurfaceCard]).
class NxSkeletonCard extends StatelessWidget {
  const NxSkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.radius,
    this.height,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? radius;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      height: height,
      decoration: BoxDecoration(color: NxSkeletonColors.of(context).card, borderRadius: BorderRadius.circular(radius ?? AppTheme.cardRadius)),
      child: child,
    );
  }
}
