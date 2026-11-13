import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/effects.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_number.dart';
import '../../core/session_state.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_app_header.dart' show NxHubAvatar;
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_notif_morph.dart';
import '../../core/app_theme.dart' show NxAtmosphereTokens;
import 'home_boxes.dart' show HomeCardShadow, homeCardFill;
import 'home_chart_data.dart' show WonData;
import 'home_charts.dart' show chartCompact;
import 'home_hero_scene.dart';

export 'home_hero_scene.dart';

// ─────────────────────────── headline choice ───────────────────────────

/// What the big number on the hero is about.
enum HomeHeadlineKind { sales, service, attendance, none }

/// Sales menus → closed-won this month; field service / cases → today's jobs
/// and cases; else today's clock-in when the user has attendance; else none.
HomeHeadlineKind homeHeadlineKind(SessionState s) {
  if (MenuAccess.any(s, const [MenuAccess.deal, MenuAccess.quotation])) return HomeHeadlineKind.sales;
  if (MenuAccess.any(s, const [MenuAccess.job, MenuAccess.caseKey])) return HomeHeadlineKind.service;
  if (MenuAccess.allow(s, MenuAccess.attendance)) return HomeHeadlineKind.attendance;
  return HomeHeadlineKind.none;
}

/// "+23.4%" / "−5%" (one decimal under 100%, ".0" dropped).
String heroDeltaLabel(double pct) {
  final a = pct.abs();
  final s = a < 100 ? a.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '') : a.round().toString();
  return '${pct >= 0 ? '+' : '−'}$s%';
}

// ─────────────────────────── styles ───────────────────────────

const _textShadow = [Shadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 1))];

TextStyle? _onPhoto(TextStyle? s, {double alpha = 1, FontWeight? weight}) => s?.copyWith(
  color: Colors.white.withValues(alpha: alpha),
  shadows: _textShadow,
  fontWeight: weight,
);

Duration _motion(BuildContext context, int ms) => MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : Duration(milliseconds: ms);

// ─────────────────────────── hero ───────────────────────────

/// Full-bleed drawn landscape at the top of Home (follows the time of day), under the pinned
/// [HomeGreetingBar], then the role's headline. Home passes no [overlap] any more
/// ("ไอแซคแนะนำ" is an ordinary Home widget); the scene's bottom fades into the page.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    this.headline,
    this.overlap,
    this.now,
    this.maxContentWidth = 1100,
    this.gutter = 16,
  });

  final Widget? headline;
  final Widget? overlap;

  /// Time of day the scene shows; it keeps following the clock from here
  /// (default: device clock).
  final DateTime? now;
  final double maxContentWidth;
  final double gutter;

  /// How far [overlap] hangs below the scene.
  static const double overlapDepth = 40;

  /// Without an [overlap] card, the scene keeps painting this far below the hero's own box, so
  /// the first Home widget sits over the hills (the scene fades out under it).
  static const double sceneUnderlap = 70;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Status bar + the pinned greeting header (the page's top inset).
    final top = MediaQuery.paddingOf(context).top;
    final under = overlap == null && headline == null ? sceneUnderlap : 0.0;

    Widget limit(Widget child) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Align(alignment: AlignmentDirectional.centerStart, child: child),
        ),
      ),
    );

    // No rounded edge: the scene melts into the page (behind [overlap] when there is one).
    // The bottom fades out with an alpha mask (the scene itself turns transparent), so it melts
    // into whatever the page colour is, with no seam.
    final scene = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Color(0x73FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)],
        stops: [0, 0.64, 0.80, 0.90, 0.97],
      ).createShader(r),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Runs 12px past the bottom (cut by the outer clip): the layer's own last pixel
          // row can escape the fade mask on some renderers and show as a hairline.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: -12,
            child: HomeHeroScene(key: const ValueKey('home-hero-scene'), time: now),
          ),
          // Dark mode: the whole scene a little dimmer.
          if (dark) const ColoredBox(key: ValueKey('home-hero-dim'), color: Color(0x38000000)),
          // Scrim so white text reads on a bright sky, then fade into the page.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.26), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0)],
                stops: const [0, 0.30, 0.55],
              ),
            ),
          ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons while the scene is under them.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Stack(
        key: const ValueKey('home-hero'),
        // The scene runs on under the widgets below (they paint after the hero, on top of it).
        clipBehavior: Clip.none,
        children: [
          // Ends 1px early and clipped: some renderers leave the mask's last pixel row unmasked.
          Positioned(left: 0, right: 0, top: 0, bottom: 1 - under, child: ClipRect(child: scene)),
          // The scene layer's last, partly covered pixel row can show as a hairline at a
          // fractional height; the page colour covers it (the fade is already transparent there).
          Positioned(left: 0, right: 0, bottom: -under, height: 3, child: ColoredBox(color: NxAtmosphereTokens.of(context).top)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The greeting row is Home's pinned header ([HomeGreetingBar]); the page's top
              // inset already holds it, so the scene simply runs on under it.
              SizedBox(height: top),
              if (headline != null) ...[const SizedBox(height: 18), limit(headline!)],
              // Open sky under the greeting; without a card this is where the scene fades out.
              SizedBox(height: headline != null ? 28 : (overlap == null ? 144 - under : 164)),
              if (overlap != null) limit(overlap!),
              SizedBox(height: overlap == null ? 0 : 18),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home's header: avatar, greeting + date, name, search and bell. Pinned while
/// the page scrolls, like every list page's header. [solid] 0 = over the scene
/// (white text, frosted buttons, light status bar), 1 = over the page (the
/// normal header colours); in between it blends as the scene scrolls away.
class HomeGreetingBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeGreetingBar({
    super.key,
    required this.greeting,
    required this.date,
    required this.solid,
    required this.height,
    this.name,
    this.maxContentWidth = 1100,
    this.gutter = 16,
  });

  final String greeting;
  final String? name;
  final String date;
  final ValueListenable<double> solid;

  /// Without the status bar; see [heightFor].
  final double height;
  final double maxContentWidth;
  final double gutter;

  static const double _padTop = 10;
  static const double _padBottom = 6;

  /// Room for the row (avatar / two text lines at the user's text size).
  static double heightFor(TextScaler s) => _padTop + math.max(50.0, s.scale(20) + s.scale(28) + 2) + _padBottom;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;
    final hasName = name != null && name!.trim().isNotEmpty;
    return ValueListenableBuilder<double>(
      valueListenable: solid,
      builder: (context, p, _) {
        final ink = Color.lerp(Colors.white, theme.colorScheme.onSurface, p)!;
        final soft = Color.lerp(Colors.white.withValues(alpha: 0.92), theme.colorScheme.onSurfaceVariant, p)!;
        final shadows = p >= 1
            ? const <Shadow>[]
            : [for (final s in _textShadow) Shadow(color: s.color.withValues(alpha: s.color.a * (1 - p)), blurRadius: s.blurRadius, offset: s.offset)];
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Light icons on the scene; the theme's own once the page is under them.
          value: (p < 0.5 || dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
          child: Padding(
            padding: EdgeInsets.only(top: top + _padTop, bottom: _padBottom),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: SizedBox(
                    key: const ValueKey('home-greeting-bar'),
                    height: height - _padTop - _padBottom,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const NxHubAvatar(size: 46, ring: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                date.isEmpty ? tr(greeting) : '${tr(greeting)} · ${tr(date)}',
                                key: const ValueKey('home-greeting'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(color: soft, shadows: shadows, fontWeight: FontWeight.w500),
                              ),
                              if (hasName)
                                Text(
                                  name!,
                                  key: const ValueKey('home-name'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(color: ink, shadows: shadows, fontWeight: FontWeight.w800),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        HeroGlassButton(
                          key: const ValueKey('home-search'),
                          icon: NxI.magnifyingGlass,
                          tooltip: tr('ค้นหาทุกอย่าง'),
                          solid: p,
                          onTap: (_) => context.push(AppRoutes.globalSearch),
                        ),
                        const SizedBox(width: 10),
                        _HeroBell(solid: p),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Frosted round button on the photo (blur where effects allow).
class HeroGlassButton extends StatelessWidget {
  const HeroGlassButton({super.key, required this.icon, required this.onTap, this.tooltip, this.badge = 0, this.solid = 0});
  final IconData icon;

  /// 0 = frosted on the scene, 1 = the header's solid round button (page under it).
  final double solid;

  /// Gets the button's own context (bell: the panel grows out of it).
  final void Function(BuildContext context) onTap;
  final String? tooltip;
  final int badge;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final level = Effects.of(context);
    final blur = level != EffectsLevel.off;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final p = solid.clamp(0.0, 1.0);
    // Same fill as the list pages' header buttons once the page is under it.
    final fill = dark ? const Color(0xFF2A2B36) : Colors.white;
    Widget face = Material(
      color: Color.lerp(Colors.white.withValues(alpha: blur ? 0.22 : 0.30), fill, p),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.45 * (1 - p)))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onTap(context),
        child: Center(
          child: Icon(
            icon,
            size: 21,
            color: Color.lerp(Colors.white, theme.colorScheme.onSurface, p),
            shadows: p >= 1 ? null : [for (final s in _textShadow) Shadow(color: s.color.withValues(alpha: s.color.a * (1 - p)), blurRadius: s.blurRadius, offset: s.offset)],
          ),
        ),
      ),
    );
    if (blur && p < 1) {
      face = ClipOval(
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: face),
      );
    }
    if (p > 0) {
      face = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: (dark ? 0.5 : 0.18) * p), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: face,
      );
    }
    final button = Semantics(
      button: true,
      label: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: face),
            if (badge > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  key: const ValueKey('home-bell-badge'),
                  constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF375F),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, excludeFromSemantics: true, child: button);
  }
}

class _HeroBell extends StatelessWidget {
  const _HeroBell({this.solid = 0});
  final double solid;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UnreadNotifications.instance,
      builder: (context, _) => HeroGlassButton(
        key: const ValueKey('home-bell'),
        icon: NxI.bell,
        tooltip: tr('การแจ้งเตือน'),
        badge: UnreadNotifications.instance.count,
        solid: solid,
        onTap: (btn) async {
          final box = btn.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) {
            await GoRouter.maybeOf(btn)?.push(AppRoutes.notifications);
            await UnreadNotifications.instance.refreshIfBound();
            return;
          }
          await showNotifMorph(btn, box.localToGlobal(Offset.zero) & box.size);
        },
      ),
    );
  }
}

// ─────────────────────────── headlines ───────────────────────────

/// Label · big value · extra line(s), all on the photo.
class _Headline extends StatelessWidget {
  const _Headline({super.key, required this.label, required this.value, this.trailing, this.below, this.onTap});
  final String label;
  final String value;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr(label), style: _onPhoto(theme.textTheme.titleSmall, alpha: 0.9, weight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: _motion(context, 280),
                  child: Text(
                    value,
                    key: ValueKey('home-headline-value-$value'),
                    maxLines: 1,
                    style: _onPhoto(theme.textTheme.displaySmall, weight: FontWeight.w800)?.copyWith(letterSpacing: -0.8, height: 1.1),
                  ),
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
        if (below != null) ...[const SizedBox(height: 10), below!],
      ],
    );
    return Semantics(
      container: true,
      button: onTap != null,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
    );
  }
}

/// Small pill on the photo: green up / red down.
class HeroDeltaPill extends StatelessWidget {
  const HeroDeltaPill({super.key, required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final c = up ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Container(
      key: const ValueKey('home-headline-delta'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scaleY: up ? 1 : -1,
            child: const Icon(NxI.trendUp, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            heroDeltaLabel(pct),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Thin progress bar on the photo.
class _PhotoProgress extends StatelessWidget {
  const _PhotoProgress({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.28))),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFD9F99D)]),
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sales: closed-won this month, % vs last month, progress to the target
/// (when the data has one; else the deal count). Quotation-only users see
/// this month's quotations instead.
class HeroSalesHeadline extends StatelessWidget {
  const HeroSalesHeadline({super.key, this.won, this.quotes, required this.deals, this.onTap});

  /// Closed-won data (null while loading or on error).
  final WonData? won;

  /// Quotations this month (quotation-only users).
  final double? quotes;

  /// User can see deals (else quotations only).
  final bool deals;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = _onPhoto(theme.textTheme.bodySmall, alpha: 0.88, weight: FontWeight.w500);
    if (!deals) {
      final q = quotes;
      return _Headline(
        key: const ValueKey('home-headline-quotes'),
        label: 'ใบเสนอราคาเดือนนี้',
        value: q == null ? '—' : nxInt(q),
        below: Text(tr('ใบเสนอราคาที่สร้างในเดือนนี้'), style: small),
        onTap: onTap,
      );
    }
    final w = won;
    final delta = w?.deltaPct;
    final progress = w?.progress;
    Widget? below;
    if (w != null && progress != null) {
      below = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('เป้าเดือนนี้ ${chartCompact(w.target!, baht: true)}'), style: small)),
              Text('${(progress * 100).round()}%', style: small?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          _PhotoProgress(key: const ValueKey('home-headline-progress'), value: progress),
        ],
      );
    } else if (w != null) {
      below = Text([tr('${nxInt(w.count)} ดีล'), if (delta != null) tr('เทียบเดือนก่อน')].join(' · '), style: small);
    }
    return _Headline(
      key: const ValueKey('home-headline-sales'),
      label: 'ยอดปิดการขายเดือนนี้',
      value: w == null ? '—' : nxBaht(w.amount),
      trailing: delta == null ? null : HeroDeltaPill(pct: delta),
      below: below,
      onTap: onTap,
    );
  }
}

/// Field service / cases: new jobs and cases of mine today.
class HeroServiceHeadline extends StatelessWidget {
  const HeroServiceHeadline({super.key, this.jobs, this.cases, required this.showJobs, required this.showCases, this.open, this.onTap});
  final int? jobs;
  final int? cases;
  final bool showJobs;
  final bool showCases;

  /// All my jobs + cases (open total), when loaded.
  final int? open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = _onPhoto(theme.textTheme.bodySmall, alpha: 0.88, weight: FontWeight.w500);
    final loading = (showJobs && jobs == null) || (showCases && cases == null);
    final total = (showJobs ? jobs ?? 0 : 0) + (showCases ? cases ?? 0 : 0);
    final label = showJobs && showCases
        ? 'งานบริการและเคสใหม่วันนี้'
        : showJobs
        ? 'งานบริการใหม่วันนี้'
        : 'เคสใหม่วันนี้';
    final parts = [
      if (showJobs && showCases && jobs != null) '${tr('งานบริการ')} ${nxInt(jobs)}',
      if (showJobs && showCases && cases != null) '${tr('เคส')} ${nxInt(cases)}',
      if (open != null) tr('ทั้งหมดของฉัน ${nxInt(open)}'),
    ];
    return _Headline(
      key: const ValueKey('home-headline-service'),
      label: label,
      value: loading ? '—' : nxInt(total),
      below: parts.isEmpty ? null : Text(parts.join(' · '), style: small),
      onTap: onTap,
    );
  }
}

/// Everyone else: today's clock in / out with the punch button.
class HeroAttendanceHeadline extends StatelessWidget {
  const HeroAttendanceHeadline({
    super.key,
    required this.inAt,
    required this.outAt,
    required this.clockedIn,
    required this.clockedOut,
    required this.onPunch,
    this.loaded = true,
  });

  /// false while today's record is loading (no status guessed yet).
  final bool loaded;

  /// "10:09" (empty when unknown).
  final String inAt;
  final String outAt;
  final bool clockedIn;
  final bool clockedOut;
  final VoidCallback onPunch;

  @override
  Widget build(BuildContext context) {
    final String status;
    final String cta;
    if (!clockedIn) {
      status = 'ยังไม่ได้ลงเวลา';
      cta = 'ลงเวลาเข้า';
    } else if (!clockedOut) {
      status = 'เข้า $inAt';
      cta = 'ลงเวลาออก';
    } else {
      status = 'เข้า $inAt · ออก $outAt';
      cta = 'ประวัติ';
    }
    return _Headline(
      key: const ValueKey('home-headline-attendance'),
      label: 'ลงเวลาวันนี้',
      value: loaded ? tr(status) : '—',
      below: FilledButton.icon(
        key: const ValueKey('home-punch'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 42),
          elevation: 2,
          shadowColor: Colors.black26,
        ),
        onPressed: loaded ? onPunch : null,
        icon: Icon(clockedOut ? NxI.clockCounterClockwise : NxI.clock, size: 18),
        label: Text(tr(cta)),
      ),
    );
  }
}

// ─────────────────────────── ISAAC card ───────────────────────────

/// First sentence of the day summary: the closed "ไอแซคแนะนำ" widget's one-liner
/// (the widget itself is `IsaacBriefCard` in home_isaac.dart).
String isaacSuggestion(String brief) {
  final t = brief.trim();
  if (t.isEmpty) return t;
  final first = t.split(' · ').first.trim();
  return first;
}

// ─────────────────────────── stat cards ───────────────────────────

/// One white stat card: icon, big number, label, "+N · 7 วัน" when there is growth.
class HomeStatCard extends StatelessWidget {
  const HomeStatCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.added, this.onTap});
  final String label;

  /// null while loading.
  final int? value;
  final IconData icon;
  final Color color;

  /// New records in the last 7 days (pill only when > 0).
  final int? added;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final good = dark ? const Color(0xFF34C77B) : const Color(0xFF0F9D58);
    final a = added ?? 0;
    return HomeCardShadow(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: homeCardFill(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: dark ? 0.22 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: color),
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value == null ? '…' : nxInt(value),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (a > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: good.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      '+${nxInt(a)} · ${tr('7 วัน')}',
                      maxLines: 1,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: good),
                    ),
                  )
                else
                  Text(tr('ของฉัน'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stat cards in one row: side by side when they fit (tablet), else a
/// horizontal scroll (phone).
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({super.key, required this.children, this.cardWidth = 156});
  final List<Widget> children;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, c) {
        final fits = children.length * cardWidth + gap * (children.length - 1) <= c.maxWidth;
        final row = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                fits ? Expanded(child: children[i]) : SizedBox(width: cardWidth, child: children[i]),
              ],
            ],
          ),
        );
        if (fits) return Padding(padding: const EdgeInsets.only(bottom: 8), child: row);
        return SingleChildScrollView(
          key: const ValueKey('home-stat-strip'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(bottom: 8),
          child: row,
        );
      },
    );
  }
}
