import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/effects.dart';

// ─────────────────────────── time of day ───────────────────────────

/// Part of the day the hero scene shows (เช้า · สาย · เที่ยง · บ่าย · เย็น · ดึก).
enum HeroPhase { dawn, lateMorning, noon, afternoon, evening, night }

/// 05–08 dawn · 08–11 late morning · 11–13 noon · 13–16 afternoon ·
/// 16–19 evening · otherwise night.
HeroPhase heroPhaseFor(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 8) return HeroPhase.dawn;
  if (h >= 8 && h < 11) return HeroPhase.lateMorning;
  if (h >= 11 && h < 13) return HeroPhase.noon;
  if (h >= 13 && h < 16) return HeroPhase.afternoon;
  if (h >= 16 && h < 19) return HeroPhase.evening;
  return HeroPhase.night;
}

/// Minutes since midnight (with seconds as a fraction).
double heroMinuteOfDay(DateTime t) => t.hour * 60 + t.minute + t.second / 60;

/// Sun above the hills from 05:50 to 18:25 (Thailand, roughly all year).
const double kHeroSunrise = 5 * 60 + 50;
const double kHeroSunset = 18 * 60 + 25;

/// Moon shown from 18:40 to 05:40.
const double kHeroMoonrise = 18 * 60 + 40;
const double kHeroMoonset = 5 * 60 + 40;

/// 0 (rising, left) → 1 (setting, right) while the sun is up, else null.
double? heroSunProgress(DateTime t) {
  final m = heroMinuteOfDay(t);
  if (m < kHeroSunrise || m > kHeroSunset) return null;
  return (m - kHeroSunrise) / (kHeroSunset - kHeroSunrise);
}

/// 0 → 1 across the night sky, else null.
double? heroMoonProgress(DateTime t) {
  final m = heroMinuteOfDay(t);
  const span = 24 * 60 - kHeroMoonrise + kHeroMoonset;
  if (m >= kHeroMoonrise) return (m - kHeroMoonrise) / span;
  if (m <= kHeroMoonset) return (m + 24 * 60 - kHeroMoonrise) / span;
  return null;
}

// ─────────────────────────── palette ───────────────────────────

/// Every colour of the scene at one moment. Key moments are blended by the
/// minute ([heroPaletteAt]), so the scene never jumps between phases.
@immutable
class HeroPalette {
  const HeroPalette({
    required this.skyTop,
    required this.skyMid,
    required this.skyHorizon,
    required this.horizonGlow,
    required this.sun,
    required this.sunGlow,
    required this.cloudLit,
    required this.cloudShade,
    required this.cloudAlpha,
    required this.hillFar,
    required this.hillMid,
    required this.hillNear,
    required this.hillFront,
    required this.hillShade,
    required this.mist,
    required this.starAlpha,
    required this.moonAlpha,
    required this.birdAlpha,
  });

  final Color skyTop, skyMid, skyHorizon;

  /// Warm band low on the horizon on the sun's side (dawn / sunset).
  final Color horizonGlow;
  final Color sun, sunGlow;
  final Color cloudLit, cloudShade;
  final double cloudAlpha;

  /// Hills from the back to the front; [hillShade] darkens their feet.
  final Color hillFar, hillMid, hillNear, hillFront, hillShade;
  final Color mist;
  final double starAlpha, moonAlpha, birdAlpha;

  List<Color> get colors => [
    skyTop, skyMid, skyHorizon, horizonGlow, sun, sunGlow, cloudLit, cloudShade, //
    hillFar, hillMid, hillNear, hillFront, hillShade, mist,
  ];

  static HeroPalette lerp(HeroPalette a, HeroPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    double d(double x, double y) => x + (y - x) * t;
    return HeroPalette(
      skyTop: c(a.skyTop, b.skyTop),
      skyMid: c(a.skyMid, b.skyMid),
      skyHorizon: c(a.skyHorizon, b.skyHorizon),
      horizonGlow: c(a.horizonGlow, b.horizonGlow),
      sun: c(a.sun, b.sun),
      sunGlow: c(a.sunGlow, b.sunGlow),
      cloudLit: c(a.cloudLit, b.cloudLit),
      cloudShade: c(a.cloudShade, b.cloudShade),
      cloudAlpha: d(a.cloudAlpha, b.cloudAlpha),
      hillFar: c(a.hillFar, b.hillFar),
      hillMid: c(a.hillMid, b.hillMid),
      hillNear: c(a.hillNear, b.hillNear),
      hillFront: c(a.hillFront, b.hillFront),
      hillShade: c(a.hillShade, b.hillShade),
      mist: c(a.mist, b.mist),
      starAlpha: d(a.starAlpha, b.starAlpha),
      moonAlpha: d(a.moonAlpha, b.moonAlpha),
      birdAlpha: d(a.birdAlpha, b.birdAlpha),
    );
  }
}

const _night = HeroPalette(
  skyTop: Color(0xFF060B1E),
  skyMid: Color(0xFF111D44),
  skyHorizon: Color(0xFF26386A),
  horizonGlow: Color(0x0026386A),
  sun: Color(0xFFFFF4D6),
  sunGlow: Color(0x00FFF4D6),
  cloudLit: Color(0xFF3A4872),
  cloudShade: Color(0xFF19223F),
  cloudAlpha: 0.42,
  hillFar: Color(0xFF223258),
  hillMid: Color(0xFF1A2C42),
  hillNear: Color(0xFF142633),
  hillFront: Color(0xFF10212A),
  hillShade: Color(0xFF050A12),
  mist: Color(0x247C8CC0),
  starAlpha: 1,
  moonAlpha: 1,
  birdAlpha: 0,
);

const _predawn = HeroPalette(
  skyTop: Color(0xFF0F1940),
  skyMid: Color(0xFF323E78),
  skyHorizon: Color(0xFF9A7A9E),
  horizonGlow: Color(0x66F0A08A),
  sun: Color(0xFFFFE0B0),
  sunGlow: Color(0x00FFC98F),
  cloudLit: Color(0xFF6D6A94),
  cloudShade: Color(0xFF2C2F5A),
  cloudAlpha: 0.55,
  hillFar: Color(0xFF4A4F78),
  hillMid: Color(0xFF33455A),
  hillNear: Color(0xFF263B40),
  hillFront: Color(0xFF1E3430),
  hillShade: Color(0xFF0A141A),
  mist: Color(0x40B8A8D0),
  starAlpha: 0.45,
  moonAlpha: 0.6,
  birdAlpha: 0,
);

const _dawn = HeroPalette(
  skyTop: Color(0xFF4C6FB4),
  skyMid: Color(0xFFA8B4DC),
  skyHorizon: Color(0xFFFFCDA8),
  horizonGlow: Color(0x99FFB98A),
  sun: Color(0xFFFFE0B0),
  sunGlow: Color(0x80FFC98F),
  cloudLit: Color(0xFFFFE3D6),
  cloudShade: Color(0xFFB3A2C4),
  cloudAlpha: 1,
  hillFar: Color(0xFF95A6C2),
  hillMid: Color(0xFF6F9A84),
  hillNear: Color(0xFF4F8459),
  hillFront: Color(0xFF3F7247),
  hillShade: Color(0xFF1C3A26),
  mist: Color(0x8CFFF1EA),
  starAlpha: 0,
  moonAlpha: 0.15,
  birdAlpha: 0.5,
);

const _morning = HeroPalette(
  skyTop: Color(0xFF4A8CDA),
  skyMid: Color(0xFF9BC9F0),
  skyHorizon: Color(0xFFE4F1F8),
  horizonGlow: Color(0x33FFF2D0),
  sun: Color(0xFFFFF8E2),
  sunGlow: Color(0x66FFF1C4),
  cloudLit: Color(0xFFFFFFFF),
  cloudShade: Color(0xFFC6D6EA),
  cloudAlpha: 1,
  hillFar: Color(0xFF9CBAC9),
  hillMid: Color(0xFF7DB37C),
  hillNear: Color(0xFF5BA25B),
  hillFront: Color(0xFF4A9149),
  hillShade: Color(0xFF234D27),
  mist: Color(0x59FFFFFF),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.55,
);

const _lateMorning = HeroPalette(
  skyTop: Color(0xFF3D83DB),
  skyMid: Color(0xFF8DC2F1),
  skyHorizon: Color(0xFFDCEEFA),
  horizonGlow: Color(0x1AFFFFFF),
  sun: Color(0xFFFFFDF0),
  sunGlow: Color(0x55FFF8DC),
  cloudLit: Color(0xFFFFFFFF),
  cloudShade: Color(0xFFCCDBEE),
  cloudAlpha: 1,
  hillFar: Color(0xFFA0C0D0),
  hillMid: Color(0xFF82BC7C),
  hillNear: Color(0xFF5FAA5A),
  hillFront: Color(0xFF4D9A48),
  hillShade: Color(0xFF22502A),
  mist: Color(0x40FFFFFF),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.5,
);

const _noon = HeroPalette(
  skyTop: Color(0xFF2E7AE0),
  skyMid: Color(0xFF7FBDF3),
  skyHorizon: Color(0xFFD5EBFB),
  horizonGlow: Color(0x00FFFFFF),
  sun: Color(0xFFFFFFF6),
  sunGlow: Color(0x66FFFBE6),
  cloudLit: Color(0xFFFFFFFF),
  cloudShade: Color(0xFFD0DEEF),
  cloudAlpha: 1,
  hillFar: Color(0xFFA4C4D2),
  hillMid: Color(0xFF86C07B),
  hillNear: Color(0xFF62AE59),
  hillFront: Color(0xFF4F9C47),
  hillShade: Color(0xFF22522A),
  mist: Color(0x33FFFFFF),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.45,
);

const _afternoon = HeroPalette(
  skyTop: Color(0xFF3278D5),
  skyMid: Color(0xFF88BEEC),
  skyHorizon: Color(0xFFE3EEF2),
  horizonGlow: Color(0x14FFE9C0),
  sun: Color(0xFFFFF8E4),
  sunGlow: Color(0x55FFF0C8),
  cloudLit: Color(0xFFFFFFFF),
  cloudShade: Color(0xFFD3DAE6),
  cloudAlpha: 1,
  hillFar: Color(0xFFA6BFC8),
  hillMid: Color(0xFF8BBC72),
  hillNear: Color(0xFF66A853),
  hillFront: Color(0xFF539644),
  hillShade: Color(0xFF27502A),
  mist: Color(0x2EFFFFFF),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.5,
);

const _lateAfternoon = HeroPalette(
  skyTop: Color(0xFF3B6FC2),
  skyMid: Color(0xFF9BBDE2),
  skyHorizon: Color(0xFFF5E2C0),
  horizonGlow: Color(0x55FFD59A),
  sun: Color(0xFFFFE6A6),
  sunGlow: Color(0x80FFD07A),
  cloudLit: Color(0xFFFFF2DE),
  cloudShade: Color(0xFFCFC0C2),
  cloudAlpha: 1,
  hillFar: Color(0xFFAFB4BC),
  hillMid: Color(0xFF96B466),
  hillNear: Color(0xFF6F9D49),
  hillFront: Color(0xFF5A8A3E),
  hillShade: Color(0xFF2B4622),
  mist: Color(0x33FFE9C8),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.55,
);

const _golden = HeroPalette(
  skyTop: Color(0xFF34569C),
  skyMid: Color(0xFFC48CA4),
  skyHorizon: Color(0xFFFFAE6C),
  horizonGlow: Color(0xB3FF9A52),
  sun: Color(0xFFFFD58C),
  sunGlow: Color(0x99FF9F55),
  cloudLit: Color(0xFFFFC59C),
  cloudShade: Color(0xFF9E7898),
  cloudAlpha: 1,
  hillFar: Color(0xFF9C7F98),
  hillMid: Color(0xFF8A8458),
  hillNear: Color(0xFF66763F),
  hillFront: Color(0xFF4E6334),
  hillShade: Color(0xFF22301A),
  mist: Color(0x4DFFC9A3),
  starAlpha: 0,
  moonAlpha: 0,
  birdAlpha: 0.6,
);

const _dusk = HeroPalette(
  skyTop: Color(0xFF1A2556),
  skyMid: Color(0xFF4E4A84),
  skyHorizon: Color(0xFFCF7F6E),
  horizonGlow: Color(0x80E8806A),
  sun: Color(0xFFFFC27A),
  sunGlow: Color(0x00FF9F55),
  cloudLit: Color(0xFFB98390),
  cloudShade: Color(0xFF443F6C),
  cloudAlpha: 0.7,
  hillFar: Color(0xFF4B4A6E),
  hillMid: Color(0xFF34455A),
  hillNear: Color(0xFF283A42),
  hillFront: Color(0xFF1F3234),
  hillShade: Color(0xFF0B121A),
  mist: Color(0x33A898C0),
  starAlpha: 0.35,
  moonAlpha: 0.7,
  birdAlpha: 0,
);

/// (minute of day, palette) — blended in between.
const List<(double, HeroPalette)> kHeroKeyframes = [
  (0, _night),
  (4 * 60 + 45, _night),
  (5 * 60 + 30, _predawn),
  (6 * 60 + 30, _dawn),
  (8 * 60 + 15, _morning),
  (10 * 60, _lateMorning),
  (12 * 60, _noon),
  (14 * 60 + 30, _afternoon),
  (16 * 60 + 30, _lateAfternoon),
  (17 * 60 + 45, _golden),
  (18 * 60 + 45, _dusk),
  (19 * 60 + 45, _night),
  (24 * 60, _night),
];

/// Scene colours for [t]: the two nearest key moments blended (smoothstep).
HeroPalette heroPaletteAt(DateTime t) => heroPaletteAtMinute(heroMinuteOfDay(t));

HeroPalette heroPaletteAtMinute(double minute) {
  final m = minute.clamp(0.0, 24 * 60.0);
  for (var i = 0; i < kHeroKeyframes.length - 1; i++) {
    final (m0, a) = kHeroKeyframes[i];
    final (m1, b) = kHeroKeyframes[i + 1];
    if (m >= m0 && m <= m1) {
      final f = m1 == m0 ? 0.0 : (m - m0) / (m1 - m0);
      return HeroPalette.lerp(a, b, f * f * (3 - 2 * f));
    }
  }
  return _night;
}

// ─────────────────────────── geometry ───────────────────────────

/// Layout of the scene in a box of [size]: horizon, sun arc, hill ridges.
class _Geo {
  _Geo(this.size) : k = (size.height / 420).clamp(0.6, 1.25);
  final Size size;
  final double k;

  double get w => size.width;
  double get h => size.height;

  /// Where the far hills sit; the sun / moon rise from just below it.
  double get horizon => h * 0.50;

  /// Highest point of the sun / moon path (between the greeting and the card).
  double get zenith => h * 0.34;

  /// Point on the sky arc for progress [p] (0 = left, 1 = right).
  Offset arc(double p) {
    final x = w * (0.07 + 0.86 * p);
    final lift = math.sin(math.pi * p.clamp(0.0, 1.0));
    final base = horizon + 14 * k;
    return Offset(x, base - lift * (base - zenith));
  }

  /// Ridge height of [hill] at x (absolute px, so wide screens get more hills).
  double ridge(_Hill hill, double x) {
    var y = h * hill.base;
    for (final (a, len, phase) in hill.waves) {
      y += a * k * math.sin(x / len * 2 * math.pi + phase);
    }
    return y;
  }
}

class _Hill {
  const _Hill(this.base, this.waves);
  final double base;

  /// (amplitude px, wavelength px, phase).
  final List<(double, double, double)> waves;
}

const _range = _Hill(0.47, [(11, 260, 1.7), (9, 610, 0.2), (6, 97, 0.4), (2.5, 43, 2.2)]);
const _far = _Hill(0.51, [(8, 300, 0.6), (6, 830, 1.9), (4, 120, 2.1), (1.5, 47, 0.9)]);
const _mid = _Hill(0.565, [(12, 400, 2.4), (7, 1130, 0.7), (4, 160, 0.3)]);
const _near = _Hill(0.635, [(15, 520, 4.1), (8, 1370, 2.6), (5, 200, 1.2)]);
const _front = _Hill(0.72, [(14, 650, 1.0), (6, 1700, 0.4), (5, 240, 3.3)]);

// ─────────────────────────── scene widget ───────────────────────────

/// Drawn landscape behind the top of Home: sky, sun or moon and stars, drifting
/// clouds and rolling hills, all following the time of day.
///
/// Cheap by design: three layers in their own [RepaintBoundary]s (sky, moving
/// clouds / stars, hills). Full: only the middle one repaints on a throttled
/// 24 fps timer, and only while Home is on screen and the app is in the
/// foreground. Lite, effects off or "reduce motion": one still frame (no motion
/// timer, no parallax — the cached layers just scroll with the page) that is
/// redrawn once per minute so it still follows the time of day.
class HomeHeroScene extends StatefulWidget {
  const HomeHeroScene({super.key, this.time, this.parallax = true});

  /// Wall clock time at build (default: device clock); the scene keeps
  /// following the clock from there.
  final DateTime? time;

  /// Sky / clouds / hills move at different speeds while Home scrolls.
  final bool parallax;

  @override
  State<HomeHeroScene> createState() => HomeHeroSceneState();
}

class HomeHeroSceneState extends State<HomeHeroScene> {
  /// [widget.time] minus the device clock: keeps the scene on the caller's clock
  /// (e.g. Thai time) even after the phone has slept.
  Duration _offset = Duration.zero;

  final ValueNotifier<double> _motion = ValueNotifier(0);
  final ValueNotifier<double> _scroll = ValueNotifier(0);
  final Stopwatch _frameWatch = Stopwatch();
  Timer? _frames;
  Timer? _clock;
  AppLifecycleListener? _life;
  ScrollPosition? _position;

  EffectsLevel _level = EffectsLevel.lite;
  bool _tickerOn = true;
  bool _shown = true;
  bool _resumed = true;
  bool _onScreen = true;

  late _SceneSpec _spec;

  /// The motion timer is running (clouds / stars moving).
  @visibleForTesting
  bool get animating => _frames != null;

  /// The once-a-minute time-of-day refresh is armed (still scene on screen).
  @visibleForTesting
  bool get followingClock => _clock != null;

  /// Clouds drift and the layers move at different speeds while scrolling: full effects only.
  /// Lite phones get a still frame — continuous repaints were what made them stutter.
  bool get _moving => _level == EffectsLevel.full;

  /// Jumps the cloud / star / bird motion to [seconds] (previews, tests).
  @visibleForTesting
  set debugMotion(double seconds) => _motion.value = seconds;

  /// Scene time now.
  DateTime get now => DateTime.now().add(_offset);

  @override
  void initState() {
    super.initState();
    _anchor();
    _spec = _SceneSpec.at(now, _level);
    Effects.preference.addListener(_refreshLevel);
    _life = AppLifecycleListener(onStateChange: (s) {
      _resumed = s == AppLifecycleState.resumed;
      if (_resumed) _updateSpec();
      _sync();
    });
  }

  void _anchor() {
    final t = widget.time;
    _offset = t == null ? Duration.zero : t.difference(DateTime.now());
  }

  @override
  void didUpdateWidget(HomeHeroScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.time != widget.time) {
      _anchor();
      _updateSpec(rebuild: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _level = Effects.of(context);
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _shown = Visibility.of(context);
    final pos = widget.parallax ? Scrollable.maybeOf(context, axis: Axis.vertical)?.position : null;
    if (!identical(pos, _position)) {
      _position?.removeListener(_onScrolled);
      _position = pos;
      _position?.addListener(_onScrolled);
    }
    _updateSpec(rebuild: false);
    _sync();
  }

  void _refreshLevel() {
    if (!mounted) return;
    _level = Effects.of(context);
    _updateSpec();
    _sync();
  }

  void _onScrolled() {
    final pos = _position;
    if (pos == null || !pos.hasPixels) return;
    final px = pos.pixels;
    final height = context.size?.height ?? 420;
    final onScreen = px < height;
    if (_moving) _scroll.value = px.clamp(0.0, height);
    if (onScreen != _onScreen) {
      _onScreen = onScreen;
      if (onScreen) _updateSpec();
      _sync();
    }
  }

  /// New palette when the minute (or the effects level) changed.
  void _updateSpec({bool rebuild = true}) {
    final next = _SceneSpec.at(now, _level);
    if (next.same(_spec)) return;
    if (rebuild && mounted) {
      setState(() => _spec = next);
    } else {
      _spec = next;
    }
  }

  /// Starts / stops the timers for what the scene may do right now.
  void _sync() {
    final active = _tickerOn && _shown && _resumed && _onScreen;
    final move = active && _moving;
    if (!_moving && _scroll.value != 0) _scroll.value = 0;
    if (move && _frames == null) {
      _clock?.cancel();
      _clock = null;
      _frameWatch
        ..reset()
        ..start();
      _frames = Timer.periodic(const Duration(microseconds: 1000000 ~/ 24), (_) => _tick());
    } else if (!move && _frames != null) {
      _frames!.cancel();
      _frames = null;
      _frameWatch.stop();
    }
    if (!move && active) {
      if (_clock == null) _armClock();
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  /// Still scene: one redraw at the next minute boundary (then re-armed), so the
  /// sky follows the time of day without a running timer between minutes.
  void _armClock() {
    final t = now;
    final wait = Duration(seconds: 60 - t.second, milliseconds: -t.millisecond).inMilliseconds.clamp(200, 60000);
    _clock = Timer(Duration(milliseconds: wait), () {
      _clock = null;
      if (!mounted) return;
      _updateSpec();
      _sync();
    });
  }

  void _tick() {
    // Only the time spent on screen moves the clouds (no jump after a pause).
    final dt = math.min(_frameWatch.elapsedMicroseconds / 1e6, 0.25);
    _frameWatch
      ..reset()
      ..start();
    _motion.value += dt;
    if (now.minute != _spec.minuteKey % 60) _updateSpec();
  }

  @override
  void dispose() {
    _frames?.cancel();
    _clock?.cancel();
    _life?.dispose();
    _position?.removeListener(_onScrolled);
    Effects.preference.removeListener(_refreshLevel);
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    Widget layer(CustomPainter painter, double depth) {
      final paint = RepaintBoundary(child: CustomPaint(painter: painter, size: Size.infinite));
      if (!widget.parallax || depth == 0 || !_moving) return paint;
      return ValueListenableBuilder<double>(
        valueListenable: _scroll,
        child: paint,
        builder: (context, px, child) => Transform.translate(offset: Offset(0, px * depth), child: child),
      );
    }

    final scene = Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      textDirection: TextDirection.ltr,
      children: [
        // The sky drifts down as the page scrolls up (seems further away).
        layer(_SkyPainter(spec), 0.35),
        layer(_DriftPainter(spec, _motion), 0.25),
        layer(_LandPainter(spec), 0.10),
      ],
    );
    // Still scene: one cached layer that only moves with the page (no repaint while scrolling).
    return ExcludeSemantics(child: _moving ? scene : RepaintBoundary(child: scene));
  }
}

/// What the three layers draw for one minute.
@immutable
class _SceneSpec {
  const _SceneSpec(this.minuteKey, this.palette, this.sun, this.moon, this.level);

  factory _SceneSpec.at(DateTime t, EffectsLevel level) =>
      _SceneSpec(t.hour * 60 + t.minute, heroPaletteAt(DateTime(2000, 1, 1, t.hour, t.minute)), heroSunProgress(t), heroMoonProgress(t), level);

  final int minuteKey;
  final HeroPalette palette;
  final double? sun;
  final double? moon;
  final EffectsLevel level;

  bool get lite => level != EffectsLevel.full;

  bool same(_SceneSpec o) => o.minuteKey == minuteKey && o.level == level;
}

// ─────────────────────────── sky: gradient, glow, sun, moon ───────────────────────────

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.spec);
  final _SceneSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    final p = spec.palette;
    final skyBottom = g.horizon + 40 * g.k;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.skyTop, p.skyMid, p.skyHorizon],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, size.width, skyBottom)),
    );

    final sunAt = spec.sun == null ? null : g.arc(spec.sun!);
    // Warm band on the horizon, on the side where the sun is (or just was).
    if (p.horizonGlow.a > 0.01) {
      final m = spec.minuteKey;
      final gx = sunAt?.dx ?? (m < 12 * 60 ? g.w * 0.12 : g.w * 0.88);
      final r = math.max(g.w * 0.8, 320.0);
      canvas.save();
      canvas.translate(gx, g.horizon + 6 * g.k);
      canvas.scale(1, 0.42);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [p.horizonGlow, p.horizonGlow.withValues(alpha: p.horizonGlow.a * 0.45), p.horizonGlow.withValues(alpha: 0)],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
      canvas.restore();
    }

    if (sunAt != null) _sun(canvas, g, sunAt, p);
    if (spec.moon != null && p.moonAlpha > 0.01) _moon(canvas, g, g.arc(spec.moon!), p.moonAlpha);
  }

  void _sun(Canvas canvas, _Geo g, Offset c, HeroPalette p) {
    // Low sun: bigger, softer glow.
    final low = 1 - math.sin(math.pi * spec.sun!.clamp(0.0, 1.0));
    final r = 15 * g.k * (1 + 0.22 * low);
    if (p.sunGlow.a > 0.01) {
      final rg = math.min(g.w, 520.0) * (0.42 + 0.18 * low);
      canvas.drawCircle(
        c,
        rg,
        Paint()
          ..shader = RadialGradient(
            colors: [p.sunGlow, p.sunGlow.withValues(alpha: p.sunGlow.a * 0.35), p.sunGlow.withValues(alpha: 0)],
            stops: const [0, 0.3, 1],
          ).createShader(Rect.fromCircle(center: c, radius: rg)),
      );
    }
    canvas.drawCircle(
      c,
      r * 1.9,
      Paint()
        ..color = p.sun.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, p.sun], stops: const [0.35, 1]).createShader(Rect.fromCircle(center: c, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );
  }

  void _moon(Canvas canvas, _Geo g, Offset c, double a) {
    final r = 10.5 * g.k;
    final rg = r * 8;
    canvas.drawCircle(
      c,
      rg,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFB8C8F0).withValues(alpha: 0.22 * a), const Color(0xFFB8C8F0).withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: rg)),
    );
    // Earthshine on the dark part, then the lit crescent.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFDDE4F5).withValues(alpha: 0.10 * a));
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.48, -r * 0.22), radius: r * 0.9)),
    );
    canvas.drawPath(
      crescent,
      Paint()
        ..color = const Color(0xFFF7F2E1).withValues(alpha: a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => !old.spec.same(spec);
}

// ─────────────────────────── moving: stars, clouds, birds ───────────────────────────

class _Star {
  const _Star(this.x, this.y, this.r, this.speed, this.phase);
  final double x, y, r, speed, phase;
}

final List<_Star> _stars = () {
  final rnd = math.Random(7);
  return List.generate(90, (_) {
    final y = math.pow(rnd.nextDouble(), 1.3).toDouble() * 0.48;
    final big = rnd.nextDouble() < 0.1;
    return _Star(rnd.nextDouble(), y, big ? 1.3 + rnd.nextDouble() * 0.5 : 0.5 + rnd.nextDouble() * 0.6, 0.6 + rnd.nextDouble() * 1.6,
        rnd.nextDouble() * math.pi * 2);
  });
}();

class _Cloud {
  const _Cloud(this.x, this.y, this.width, this.speed, this.seed, {this.wisp = false});

  /// Start along the track (0–1), height (fraction of the scene), size and drift px/s.
  final double x, y, width, speed;
  final int seed;
  final bool wisp;
}

/// One 412px-wide tile of sky; wider screens repeat it.
const _cloudTile = [
  _Cloud(0.08, 0.10, 120, 1.4, 1, wisp: true),
  _Cloud(0.55, 0.17, 80, 1.8, 2, wisp: true),
  _Cloud(0.80, 0.29, 128, 3.0, 3),
  _Cloud(0.30, 0.37, 96, 3.4, 4),
  _Cloud(0.02, 0.43, 76, 4.0, 5),
  _Cloud(0.60, 0.45, 60, 4.4, 6),
];

final Map<int, Path> _cloudPaths = {};

/// Cumulus: flat base, a row of round puffs (largest in the middle) and one or
/// two towering on top. Unit width 100.
Path _cumulus(int seed) => _cloudPaths.putIfAbsent(seed, () {
  final rnd = math.Random(seed * 31 + 3);
  final p = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-50, -8, 100, 10), const Radius.circular(5)));
  final n = 6 + seed % 3;
  for (var i = 0; i < n; i++) {
    final fx = -0.42 + 0.84 * i / (n - 1) + (rnd.nextDouble() - 0.5) * 0.05;
    final bulge = 1 - (fx.abs() / 0.46).clamp(0.0, 1.0);
    final rad = 100 * (0.06 + 0.06 * bulge + rnd.nextDouble() * 0.03);
    p.addOval(Rect.fromCenter(center: Offset(fx * 100, -4 - rad * 0.45), width: rad * 2.3, height: rad * 2));
  }
  final tops = 1 + seed % 2;
  for (var i = 0; i < tops; i++) {
    final fx = (rnd.nextDouble() - 0.6) * 0.3 + i * 0.22;
    final rad = 100 * (0.11 + rnd.nextDouble() * 0.04);
    p.addOval(Rect.fromCenter(center: Offset(fx * 100, -9 - rad * 0.55), width: rad * 2.2, height: rad * 2));
  }
  return p;
});

/// High thin cloud: a few long soft streaks. Unit width 100.
Path _wisp(int seed) => _cloudPaths.putIfAbsent(-seed, () {
  final rnd = math.Random(seed * 17 + 5);
  final p = Path();
  for (var i = 0; i < 3; i++) {
    final w = 100 * (0.55 + rnd.nextDouble() * 0.4);
    p.addOval(Rect.fromCenter(center: Offset((rnd.nextDouble() - 0.5) * 40, i * 4.5 - 4), width: w, height: 5 + rnd.nextDouble() * 3));
  }
  return p;
});

class _DriftPainter extends CustomPainter {
  _DriftPainter(this.spec, this.motion) : super(repaint: motion);
  final _SceneSpec spec;
  final ValueListenable<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    final p = spec.palette;
    final t = motion.value;

    if (p.starAlpha > 0.01) {
      final moonAt = spec.moon == null ? null : g.arc(spec.moon!);
      final paint = Paint();
      final count = spec.lite ? 55 : _stars.length;
      final tiles = math.max(1, (g.w / 412).ceil());
      for (var tile = 0; tile < tiles; tile++) {
        for (var i = 0; i < count; i++) {
          final s = _stars[i];
          final at = Offset((tile + s.x) * 412 * (g.w / (412 * tiles)), s.y * g.h);
          if (moonAt != null && (at - moonAt).distanceSquared < 900 * g.k * g.k) continue;
          final twinkle = 0.62 + 0.38 * math.sin(t * s.speed + s.phase);
          final fade = 1 - (s.y / 0.5) * 0.55;
          paint.color = Colors.white.withValues(alpha: (p.starAlpha * twinkle * fade).clamp(0.0, 1.0));
          canvas.drawCircle(at, s.r, paint);
          if (s.r > 1.2) {
            paint.color = const Color(0xFFCFDCFF).withValues(alpha: p.starAlpha * twinkle * 0.12);
            canvas.drawCircle(at, s.r * 2.2, paint);
          }
        }
      }
    }

    // Clouds: the far (high) ones drift slower. See-through clouds (night,
    // dusk) share one layer so overlaps don't add up.
    final faint = p.cloudAlpha < 0.99;
    if (faint) canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, p.cloudAlpha));
    final tiles = math.max(1, (g.w / 412).round());
    for (var tile = 0; tile < tiles; tile++) {
      for (var i = 0; i < _cloudTile.length; i++) {
        final c = _cloudTile[i];
        if (spec.lite && i == 5) continue;
        final w = c.width * g.k;
        final track = g.w + w * 2;
        final x = ((c.x + tile) / tiles * track + c.speed * t) % track - w;
        // Each extra tile: other shapes, a little higher or lower.
        final y = c.y + (tile == 0 ? 0 : ((tile * 37) % 5 - 2) * 0.012);
        _cloud(canvas, Offset(x, y * g.h), w, c, p, seed: c.seed + tile * 10);
      }
    }
    if (faint) canvas.restore();

    if (!spec.lite && p.birdAlpha > 0.01 && spec.sun != null) _birds(canvas, g, t, p);
  }

  void _cloud(Canvas canvas, Offset at, double w, _Cloud c, HeroPalette p, {required int seed}) {
    final s = w / 100;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(s);
    if (c.wisp) {
      canvas.drawPath(
        _wisp(seed),
        Paint()
          ..color = Color.lerp(p.cloudLit, p.cloudShade, 0.2)!.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    } else {
      // Shaded body, then the same shape nudged up and clipped to it: lit tops,
      // a soft shadowed underside.
      final body = _cumulus(seed);
      canvas.drawPath(
        body,
        Paint()
          ..color = p.cloudShade
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      canvas.save();
      canvas.clipPath(body);
      canvas.translate(-1.5, -4);
      canvas.drawPath(
        body,
        Paint()
          ..color = p.cloudLit
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.4),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// A few small birds crossing now and then (about every 50 s, for ~16 s).
  void _birds(Canvas canvas, _Geo g, double t, HeroPalette p) {
    const period = 50.0, cross = 16.0;
    final cycle = (t / period).floor();
    final f = (t - cycle * period) / cross;
    if (f < 0 || f > 1) return;
    final rnd = math.Random(cycle);
    final rtl = rnd.nextBool();
    final y0 = g.h * (0.30 + rnd.nextDouble() * 0.1);
    final x0 = rtl ? g.w * (1 - f) * 1.2 : g.w * (f * 1.2 - 0.1);
    final paint = Paint()
      ..color = const Color(0xFF26313C).withValues(alpha: p.birdAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final dx = (rtl ? 1 : -1) * (i * 11.0 + (i.isOdd ? 4 : 0));
      final dy = (i.isOdd ? -6.0 : 5.0) * (i == 0 ? 0 : 1) + math.sin(t * 1.3 + i) * 2;
      final c = Offset(x0 + dx, y0 + dy);
      final flap = math.sin(t * 9 + i * 1.7);
      final span = 4.2 * g.k;
      final tip = -1.5 - flap * 1.6;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - span, c.dy + tip)
          ..quadraticBezierTo(c.dx - span * 0.45, c.dy - 1.4, c.dx, c.dy)
          ..quadraticBezierTo(c.dx + span * 0.45, c.dy - 1.4, c.dx + span, c.dy + tip),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DriftPainter old) => !old.spec.same(spec) || old.motion != motion;
}

// ─────────────────────────── land: hills, mist, trees ───────────────────────────

class _LandPainter extends CustomPainter {
  _LandPainter(this.spec);
  final _SceneSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    final p = spec.palette;
    // Light catching the ridges: sky-coloured by day, warm at dawn / sunset.
    final rim = Color.lerp(p.skyHorizon, p.sun, spec.sun == null ? 0 : 0.4)!;

    canvas.saveLayer(Offset.zero & size, Paint());
    // Faint far range, almost the colour of the sky (air in between).
    _hill(canvas, g, _range, Color.lerp(p.skyHorizon, p.hillFar, 0.45)!, Color.lerp(p.skyHorizon, p.hillFar, 0.7)!, shade: 0);
    _hill(canvas, g, _far, p.hillFar, p.hillShade, shade: 0.18, rim: rim, rimAlpha: 0.35);
    _mist(canvas, g, g.h * 0.545, 26 * g.k, p.mist);
    _trees(canvas, g, _mid, p.hillMid, p.hillShade, 0.62, small: true);
    _hill(canvas, g, _mid, p.hillMid, p.hillShade, shade: 0.28, rim: rim, rimAlpha: 0.30);
    _mist(canvas, g, g.h * 0.61, 20 * g.k, p.mist.withValues(alpha: p.mist.a * 0.6));
    _trees(canvas, g, _near, p.hillNear, p.hillShade, 0.55);
    _hill(canvas, g, _near, p.hillNear, p.hillShade, shade: 0.32, rim: rim, rimAlpha: 0.3);
    _hill(canvas, g, _front, p.hillFront, p.hillShade, shade: 0.35, rim: rim, rimAlpha: 0.22);

    // The land is lighter toward the sun (or the glow it left on the horizon).
    final glow = spec.sun != null ? p.sunGlow : p.horizonGlow;
    if (glow.a > 0.01) {
      final cx = spec.sun != null ? g.arc(spec.sun!).dx : (spec.minuteKey < 12 * 60 ? g.w * 0.12 : g.w * 0.88);
      final r = math.max(g.w * 0.7, 300.0);
      final c = Offset(cx, g.horizon);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = RadialGradient(
            colors: [glow.withValues(alpha: glow.a * 0.55), glow.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    canvas.restore();
  }

  void _hill(Canvas canvas, _Geo g, _Hill hill, Color top, Color shadeColor, {required double shade, Color? rim, double rimAlpha = 0}) {
    final path = Path()..moveTo(0, g.h + 20);
    final ridge = Path();
    var minY = g.h;
    for (var x = 0.0; x <= g.w + 4; x += 4) {
      final y = g.ridge(hill, x);
      minY = math.min(minY, y);
      path.lineTo(x, y);
      x == 0 ? ridge.moveTo(x, y) : ridge.lineTo(x, y);
    }
    path
      ..lineTo(g.w + 4, g.h + 20)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, Color.lerp(top, shadeColor, shade)!],
        ).createShader(Rect.fromLTRB(0, minY, g.w, math.min(g.h, minY + 120 * g.k))),
    );
    if (rim != null && rimAlpha > 0) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * g.k
          ..color = rim.withValues(alpha: rimAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * g.k),
      );
      canvas.restore();
    }
  }

  /// Soft horizontal band of haze lying in the valleys.
  void _mist(Canvas canvas, _Geo g, double y, double half, Color c) {
    if (c.a < 0.01) return;
    canvas.drawRect(
      Rect.fromLTRB(0, y - half, g.w, y + half),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: 0), c, c.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(0, y - half, g.w, y + half)),
    );
  }

  /// Small trees standing on the ridge of [hill] (drawn just before the hill so
  /// their trunks sink into it).
  void _trees(Canvas canvas, _Geo g, _Hill hill, Color hillColor, Color shadeColor, double darken, {bool small = false}) {
    final color = Color.lerp(hillColor, shadeColor, darken)!;
    final paint = Paint()..color = color;
    final rnd = math.Random(small ? 41 : 97);
    var x = rnd.nextDouble() * 60;
    while (x < g.w) {
      // Groves of 1–3 trees with open stretches between.
      final grove = 1 + rnd.nextInt(3);
      for (var i = 0; i < grove; i++) {
        final tx = x + i * (small ? 6 : 10) * g.k + rnd.nextDouble() * 4;
        final ty = g.ridge(hill, tx) + 2 * g.k;
        final hgt = (small ? 7 + rnd.nextDouble() * 4 : 12 + rnd.nextDouble() * 7) * g.k;
        if (rnd.nextDouble() < 0.4) {
          // Slim cypress / palm-less evergreen.
          canvas.drawPath(
            Path()
              ..moveTo(tx, ty - hgt)
              ..quadraticBezierTo(tx + hgt * 0.24, ty - hgt * 0.45, tx + hgt * 0.13, ty)
              ..lineTo(tx - hgt * 0.13, ty)
              ..quadraticBezierTo(tx - hgt * 0.24, ty - hgt * 0.45, tx, ty - hgt)
              ..close(),
            paint,
          );
        } else {
          // Round broadleaf crown on a short trunk.
          final cr = hgt * 0.34;
          canvas.drawRect(Rect.fromLTWH(tx - hgt * 0.04, ty - hgt * 0.45, hgt * 0.08, hgt * 0.45), paint);
          canvas.drawCircle(Offset(tx, ty - hgt + cr), cr, paint);
          canvas.drawCircle(Offset(tx - cr * 0.6, ty - hgt + cr * 1.6), cr * 0.75, paint);
          canvas.drawCircle(Offset(tx + cr * 0.62, ty - hgt + cr * 1.5), cr * 0.8, paint);
        }
      }
      x += (small ? 70 : 110) + rnd.nextDouble() * (small ? 120 : 170);
    }
  }

  @override
  bool shouldRepaint(_LandPainter old) => !old.spec.same(spec);
}
