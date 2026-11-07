import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/effects.dart';

/// Marks a header as floating: [NxAppHeader] then paints no background so the
/// page shows through the progressive blur behind it.
class NxFloatingHeaderScope extends InheritedWidget {
  const NxFloatingHeaderScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NxFloatingHeaderScope>() != null;

  @override
  bool updateShouldNotify(NxFloatingHeaderScope oldWidget) => false;
}

/// Page with a floating header (expo-backdrop style): content scrolls *under*
/// the header, which sits on a blur that is strongest at the top edge and
/// fades out below it. Fast flings add a vertical motion blur.
///
/// Scrollables in [body] must add [topInset] to their top padding so their
/// first item starts below the header (and can then scroll up beneath it).
class NxScrollScaffold extends StatelessWidget {
  const NxScrollScaffold({
    super.key,
    required this.header,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.motionBlur = true,
    this.bottomBlur = false,
    this.insetBody = true,
    this.resizeToAvoidBottomInset,
    this.headerBottom,
    this.headerBottomHeight = 0,
  });

  /// Extra floating row(s) under the header (search, filter chips) that sit on
  /// the same glass; content scrolls beneath both.
  final Widget? headerBottom;
  final double headerBottomHeight;

  final PreferredSizeWidget header;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  /// Blur the content in the scroll direction while flinging fast.
  final bool motionBlur;

  /// Also fade/blur content toward the bottom edge (pages with a floating CTA).
  final bool bottomBlur;

  /// true: body starts below the header (works with any body as-is).
  /// false: body runs under the header — its scrollable adds [topInset] to
  /// its top padding so items scroll up beneath the blurred header.
  final bool insetBody;
  final bool? resizeToAvoidBottomInset;

  /// Status bar + header height: the top padding a body scrollable needs.
  static double topInset(BuildContext context) => MediaQuery.paddingOf(context).top;

  @override
  Widget build(BuildContext context) {
    Widget content = motionBlur ? NxMotionBlur(child: body) : body;
    if (insetBody) {
      final inner = content; // capture before reassigning (else the Builder nests itself)
      content = Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(top: topInset(context)),
          child: MediaQuery.removePadding(context: context, removeTop: true, child: inner),
        ),
      );
    }
    // Inside the tab shell (floating bar adds bottom padding) blur toward the
    // bottom here, so it sits *under* this page's FAB instead of over it.
    final underFloatingBar = MediaQuery.paddingOf(context).bottom > 48;
    if (bottomBlur || underFloatingBar) {
      content = Stack(
        children: [
          Positioned.fill(child: content),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96 + MediaQuery.paddingOf(context).bottom,
            child: const NxEdgeBlur(fromTop: false),
          ),
        ],
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: _FloatingHeader(header: header, extend: !insetBody, bottom: headerBottom, bottomHeight: headerBottomHeight),
      // Lift the FAB above the floating tab bar (its height is in padding.bottom).
      floatingActionButton: floatingActionButton == null || !underFloatingBar
          ? floatingActionButton
          : Padding(
              padding: EdgeInsets.only(
                bottom: (MediaQuery.paddingOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom).clamp(0, 200),
              ),
              child: floatingActionButton,
            ),
      bottomNavigationBar: bottomNavigationBar,
      body: content,
    );
  }
}

class _FloatingHeader extends StatelessWidget implements PreferredSizeWidget {
  const _FloatingHeader({required this.header, required this.extend, this.bottom, this.bottomHeight = 0});
  final PreferredSizeWidget header;
  final Widget? bottom;
  final double bottomHeight;

  /// Let the blur run below the header (only when content scrolls under it).
  final bool extend;

  @override
  Size get preferredSize => Size.fromHeight(header.preferredSize.height + (bottom == null ? 0 : bottomHeight));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The blur reaches below the header so content dissolves into it.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top + preferredSize.height + (extend ? 36 : 0),
          child: const NxEdgeBlur(fromTop: true),
        ),
        NxFloatingHeaderScope(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              if (bottom != null) SizedBox(height: bottomHeight, child: bottom),
            ],
          ),
        ),
      ],
    );
  }
}

/// Multi-step progressive blur toward one edge: several blur layers, each
/// masked to a shorter band, so blur grows smoothly toward the edge instead
/// of ending in a hard line. Lite/off devices get a background fade only.
class NxEdgeBlur extends StatelessWidget {
  const NxEdgeBlur({super.key, required this.fromTop, this.maxSigma = 16, this.steps = 3});

  final bool fromTop;
  final double maxSigma;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final level = Effects.of(context);
    final edge = fromTop ? Alignment.topCenter : Alignment.bottomCenter;
    final away = fromTop ? Alignment.bottomCenter : Alignment.topCenter;
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: edge,
          end: away,
          colors: [
            // Mostly blur, a light wash only — reads as frosted glass, not a white bar.
            bg.withValues(alpha: level == EffectsLevel.full ? 0.38 : 0.94),
            bg.withValues(alpha: level == EffectsLevel.full ? 0.12 : 0.6),
            bg.withValues(alpha: 0),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
    if (level != EffectsLevel.full) return IgnorePointer(child: tint);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < steps; i++)
            // Layer i covers the band nearest the edge: stronger blur, shorter band.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: edge,
                end: away,
                colors: const [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.15 + 0.25 * (steps - 1 - i) / steps, 1 - 0.3 * i / steps],
              ).createShader(r),
              child: ClipRect(
                child: BackdropFilter.grouped(
                  filter: ui.ImageFilter.blur(
                    sigmaX: maxSigma * (i + 1) / (steps * 2),
                    sigmaY: maxSigma * (i + 1) / steps,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          tint,
        ],
      ),
    );
  }
}

/// Vertical motion blur while a child scrollable flings fast (expo-motion-blur).
/// Only on the "full" effects level; clears as soon as the scroll slows.
class NxMotionBlur extends StatefulWidget {
  const NxMotionBlur({super.key, required this.child, this.threshold = 2200, this.maxSigma = 6});

  final Widget child;

  /// Speed (logical px/s) where blur starts.
  final double threshold;
  final double maxSigma;

  @override
  State<NxMotionBlur> createState() => _NxMotionBlurState();
}

class _NxMotionBlurState extends State<NxMotionBlur> {
  double _sigma = 0;
  DateTime? _last;
  Timer? _decay;

  @override
  void dispose() {
    _decay?.cancel();
    super.dispose();
  }

  void _set(double v) {
    if ((v - _sigma).abs() < 0.25) return;
    setState(() => _sigma = v);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollUpdateNotification) {
      // Finger on screen = the user is reading/dragging: keep it sharp.
      if (n.dragDetails != null) {
        _set(0);
        return false;
      }
      final now = DateTime.now();
      final dt = _last == null ? 16 : now.difference(_last!).inMicroseconds / 1000;
      _last = now;
      final speed = (n.scrollDelta ?? 0).abs() / (dt.clamp(4, 50) / 1000);
      final over = (speed - widget.threshold) / widget.threshold;
      _set(over <= 0 ? 0 : (over * widget.maxSigma).clamp(0, widget.maxSigma));
      _decay?.cancel();
      _decay = Timer(const Duration(milliseconds: 120), () {
        if (mounted) _set(0);
      });
    } else if (n is ScrollEndNotification) {
      _set(0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (Effects.of(context) != EffectsLevel.full) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ImageFiltered(
        enabled: _sigma > 0,
        imageFilter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: _sigma),
        child: widget.child,
      ),
    );
  }
}
