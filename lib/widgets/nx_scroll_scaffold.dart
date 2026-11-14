import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../core/effects.dart';
import 'nx_chrome.dart';

export 'nx_chrome.dart' show NxChrome, NxChromeAction, NxChromeBus, NxChromeCollapse;

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
class NxScrollScaffold extends StatefulWidget {
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
    this.headerBlur,
  });

  /// When given, the blur behind the header only shows while this is true
  /// (Home: hidden while the full-bleed hero photo sits under the status bar).
  final ValueListenable<bool>? headerBlur;

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
  State<NxScrollScaffold> createState() => _NxScrollScaffoldState();
}

class _NxScrollScaffoldState extends State<NxScrollScaffold> {
  /// Toolbars fold into header icons and the tab bar slides away while the
  /// user reads down the page (see [NxChrome]).
  final _chrome = NxChrome();

  @override
  void dispose() {
    // Leaving a collapsed page must not strand the tab bar off-screen.
    if (_chrome.collapsed) NxChromeBus.hidden.value = false;
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final body = w.body;
    final motionBlur = w.motionBlur;
    final insetBody = w.insetBody;
    final bottomBlur = w.bottomBlur;
    final floatingActionButton = w.floatingActionButton;
    Widget content = NxChromeScrollListener(chrome: _chrome, child: motionBlur ? NxMotionBlur(child: body) : body);
    final topInset = NxScrollScaffold.topInset;
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
            // Ends at about the middle of the floating tab bar (bar ≈ 76 + 10 margin).
            // viewPadding = system inset only; padding.bottom here also holds the bar.
            height: 48 + MediaQuery.viewPaddingOf(context).bottom,
            child: const NxEdgeBlur(fromTop: false, solidFraction: 0.5),
          ),
        ],
      );
    }
    // Lift the FAB above the floating tab bar (its height is in padding.bottom);
    // when the bar slides away the FAB drops and shrinks a little, and while a
    // card is dragged it steps aside for the drop dock.
    final barLift = underFloatingBar
        ? (MediaQuery.paddingOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom).clamp(0.0, 200.0)
        : 0.0;
    // While typing, the + button would sit right over the focused field.
    // (MediaQuery for the rebuild; View for tab pages whose outer Scaffold already took the inset.)
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0 || View.of(context).viewInsets.bottom > 0;
    final fab = floatingActionButton == null || typing
        ? null
        : ListenableBuilder(
            listenable: Listenable.merge([NxChromeBus.hidden, NxChromeBus.dragging]),
            child: floatingActionButton,
            builder: (context, child) {
              final hidden = underFloatingBar && NxChromeBus.hidden.value;
              final dragging = NxChromeBus.dragging.value;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: hidden ? 0 : barLift),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: dragging ? 0 : (_chrome.collapsed ? 0.86 : 1),
                  child: child,
                ),
              );
            },
          );
    return NxChromeScope(
      chrome: _chrome,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: w.resizeToAvoidBottomInset,
        appBar: _FloatingHeader(header: w.header, extend: !insetBody, bottom: w.headerBottom, bottomHeight: w.headerBottomHeight, blurVisible: w.headerBlur),
        floatingActionButton: fab,
        bottomNavigationBar: w.bottomNavigationBar,
        body: content,
      ),
    );
  }
}

class _FloatingHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Fade below the header (content dissolves into it). Long enough that the
  /// blur eases out instead of stopping at a visible line.
  static const double _tail = 26;

  const _FloatingHeader({required this.header, required this.extend, this.bottom, this.bottomHeight = 0, this.blurVisible});
  final PreferredSizeWidget header;
  final ValueListenable<bool>? blurVisible;
  final Widget? bottom;
  final double bottomHeight;

  /// Let the blur run below the header (only when content scrolls under it).
  final bool extend;

  @override
  Size get preferredSize => Size.fromHeight(header.preferredSize.height + (bottom == null ? 0 : bottomHeight));

  Widget _blurGate(Widget blur) {
    final v = blurVisible;
    if (v == null) return blur;
    return ValueListenableBuilder<bool>(
      valueListenable: v,
      child: blur,
      builder: (context, on, child) => AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : const Duration(milliseconds: 180),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final chrome = NxChrome.of(context);
    // The toolbar row folds away while reading; the blur follows its height.
    final folded = bottom != null && (chrome?.collapsed ?? false);
    // Never shorter than the status bar: the Scaffold hands the body this height as its
    // top inset, so an empty header (Home draws its own) would otherwise put the page's
    // content under the status bar.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: top),
      child: Stack(
      clipBehavior: Clip.none,
      children: [
        // The blur reaches below the header so content dissolves into it.
        TweenAnimationBuilder<double>(
          tween: Tween(end: folded ? header.preferredSize.height : preferredSize.height),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (context, h, _) => Positioned(
            left: 0,
            right: 0,
            top: 0,
            // A short tail below the header so the blur ends softly but takes little room.
            height: top + h + (extend ? _tail : 0),
            child: IgnorePointer(
              child: _blurGate(
                NxEdgeBlur(
                  fromTop: true,
                  // Full blur over the status bar + most of the header (so nothing ghosts
                  // through its text), then a long soft fade below.
                  solidFraction: extend ? (top + h * 0.75) / (top + h + _tail) : 0.6,
                  washSolid: extend ? (top + h - 4) / (top + h + _tail) : 0.9,
                ),
              ),
            ),
          ),
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
    ),
    );
  }
}

/// Progressive blur toward one edge.
///
/// Full: many fine steps, each a hair stronger than the one below it and
/// blurred evenly in both directions, so the eye sees one smooth ramp instead
/// of stacked bands. Lite and off: the wash gradient only (no live blur —
/// cheap on low-end phones); lite's wash is a little lighter than off's.
class NxEdgeBlur extends StatelessWidget {
  const NxEdgeBlur({super.key, required this.fromTop, this.maxSigma = 14, this.steps = 12, this.solidFraction = 0.45, this.washSolid});

  /// Fraction of the band covered by step [i] (0 = tallest, lightest).
  double bandHeight(int i) {
    if (steps <= 1) return 1;
    final t = i / (steps - 1);
    return 1 - (1 - solidFraction) * t;
  }

  /// Blur of step [i]: even increments from ~0.6 to [maxSigma], so no step
  /// edge is a visible jump.
  double sigma(int i) {
    if (steps <= 1) return maxSigma;
    final t = i / (steps - 1);
    return 0.6 + (maxSigma - 0.6) * t;
  }

  final bool fromTop;

  /// Part of the band (from the edge) that stays fully blurred — e.g. the
  /// header itself; the rest fades out.
  final double solidFraction;
  final double maxSigma;
  final int steps;

  /// Lite / off: part of the band (from the edge) where the wash stays almost
  /// solid — the header itself — so tall headers (title + search + chips) read
  /// as clearly as Home's; only the tail below fades.
  final double? washSolid;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final level = Effects.of(context);
    final edge = fromTop ? Alignment.topCenter : Alignment.bottomCenter;
    final away = fromTop ? Alignment.bottomCenter : Alignment.topCenter;
    final full = level == EffectsLevel.full;
    final lite = level == EffectsLevel.lite;
    // Eased wash: many stops so the fade has no visible end line.
    final alphas = full
        ? const [0.42, 0.34, 0.24, 0.15, 0.08, 0.03, 0.0]
        : lite
            ? const [0.9, 0.82, 0.68, 0.5, 0.3, 0.12, 0.0]
            : const [0.94, 0.86, 0.72, 0.52, 0.3, 0.12, 0.0];
    final ws = full ? null : washSolid?.clamp(0.0, 0.95);
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: ws == null
            ? LinearGradient(
                begin: edge,
                end: away,
                colors: [for (final a in alphas) bg.withValues(alpha: a)],
                stops: const [0, 0.3, 0.48, 0.64, 0.78, 0.9, 1],
              )
            : LinearGradient(
                begin: edge,
                end: away,
                colors: [
                  for (final a in lite ? const [1.0, 0.99, 0.97, 0.68, 0.34, 0.1, 0.0] : const [0.97, 0.95, 0.92, 0.66, 0.34, 0.1, 0.0])
                    bg.withValues(alpha: a),
                ],
                stops: [0, ws * 0.5, ws, ws + (1 - ws) * 0.3, ws + (1 - ws) * 0.6, ws + (1 - ws) * 0.85, 1],
              ),
      ),
      child: const SizedBox.expand(),
    );
    // Lite / off: the wash only — no BackdropFilter. Each live blur re-reads and
    // filters the screen under it every frame, which is what made scrolling stutter
    // on low-end phones; the lite wash alphas are strong enough to keep text behind
    // the header from ghosting through.
    if (!full) return IgnorePointer(child: tint);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < steps; i++)
            Align(
              alignment: edge,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: bandHeight(i),
                child: ClipRect(
                  child: BackdropFilter.grouped(
                    filter: ui.ImageFilter.blur(sigmaX: sigma(i), sigmaY: sigma(i)),
                    child: const SizedBox.expand(),
                  ),
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
