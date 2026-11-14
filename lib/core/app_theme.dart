import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/fields/nx_field_chrome.dart';
import '../widgets/nx_icons.dart';
import 'ui_font.dart';

/// Atmosphere tokens — Inbox lavender fill, floating cards, comfortable ink.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF6366F1);

  static const Color ink = Color(0xFF1C1C1E);
  static const Color inkSecondary = Color(0xFF6B7280);
  static const Color inkTertiary = Color(0xFF8E8E93);
  static const Color lightBg = Color(0xFFF6F7FB);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightLine = Color(0x147C7C80);

  static const Color _darkSurface = Color(0xFF111114);
  static const Color _darkVariant = Color(0xFF1E1F28);
  static const Color _darkOn = Color(0xFFE7E7EA);
  static const Color _darkMuted = Color(0xFFA1A1AA);
  static const Color _darkOutline = Color(0xFF4E4E57);

  /// Default app font family (pubspec `fonts:`); the user can pick another
  /// one (see ui_font.dart) — read it from `Theme.of(context)`.
  static const String fontFamily = 'GoogleSans';

  static const double radius = 16;
  static const double cardRadius = 20;

  static ThemeData get dark => themed(brightness: Brightness.dark);
  static ThemeData get light => themed(brightness: Brightness.light);

  /// Built themes by (brightness, accent). Building a ThemeData is not free
  /// text themes, so rebuilding on every app notify caused visible hitches.
  static final Map<(Brightness, int, String), ThemeData> _cache = {};

  static ThemeData themed({required Brightness brightness, Color? accent, String family = fontFamily}) {
    final key = (brightness, (accent ?? primary).toARGB32(), family);
    return _cache[key] ??= _build(brightness: brightness, accent: accent, family: family);
  }

  static ThemeData _build({required Brightness brightness, Color? accent, required String family}) {
    final primaryColor = accent ?? primary;
    final isDark = brightness == Brightness.dark;
    final container = isDark
        ? Color.lerp(primaryColor, _darkVariant, 0.55)!
        : Color.lerp(primaryColor, Colors.white, 0.86)!;
    final scheme = isDark
        ? ColorScheme.dark(
            primary: primaryColor,
            onPrimary: Colors.white,
            primaryContainer: container,
            secondary: primaryColor,
            surface: _darkSurface,
            onSurface: _darkOn,
            surfaceContainerHighest: _darkVariant,
            onSurfaceVariant: _darkMuted,
            outline: _darkOutline,
            outlineVariant: const Color(0xFF2A2A31),
          )
        : ColorScheme.light(
            primary: primaryColor,
            onPrimary: Colors.white,
            primaryContainer: container,
            // ColorScheme.light defaults this to onPrimary (white) — unreadable
            // on the pale container (tip banners, avatar chips). Use a deep
            // shade of the accent instead.
            onPrimaryContainer: Color.lerp(primaryColor, Colors.black, 0.6)!,
            secondary: primaryColor,
            onSecondary: Colors.white,
            surface: lightCard,
            onSurface: ink,
            surfaceContainerHighest: lightBg,
            onSurfaceVariant: inkSecondary,
            outline: const Color(0xFFD1D1D6),
            outlineVariant: const Color(0xFFE5E7EB),
          );
    final scaffold = isDark ? _darkSurface : lightBg;
    final cardColor = isDark ? _darkVariant : lightCard;
    return _base(
      family: family,
      brightness: brightness,
      scheme: scheme,
      scaffold: scaffold,
      card: cardColor,
      cta: primaryColor,
      onCta: Colors.white,
      atmosphere: NxAtmosphereTokens(top: scaffold, mid: scaffold, bottom: scaffold, cardElevated: cardColor),
    );
  }

  static ThemeData _base({
    required String family,
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color cta,
    required Color onCta,
    required NxAtmosphereTokens atmosphere,
  }) {
    final isDark = brightness == Brightness.dark;
    final text = _uiText(scheme, family);
    // Component styles (chips, snack bars, field labels) name the chosen font
    // too — otherwise they fall back to the system font.
    final fallback = uiFontFallback(family);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      canvasColor: scaffold,
      scaffoldBackgroundColor: scaffold,
      fontFamily: family,
      fontFamilyFallback: uiFontFallback(family),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: card,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: cta,
          foregroundColor: onCta,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        backgroundColor: cta,
        foregroundColor: onCta,
        shape: const CircleBorder(),
      ),
      // Chips must read as "pills" on any surface (cards and sheets are
      // _darkVariant in dark mode): a lighter fill plus a hairline outline;
      // selected = solid accent with white text.
      // Explicit: ColorScheme.dark() without inversePrimary made the "เลิกทำ"
      // action white on a light bar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2C2C34) : const Color(0xFF1F2937),
        contentTextStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          color: Colors.white,
          fontSize: 14,
        ),
        actionTextColor: Color.lerp(scheme.primary, Colors.white, isDark ? 0.45 : 0.55),
        closeIconColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide(color: scheme.primary)
              : BorderSide(color: isDark ? const Color(0xFF3A3B46) : const Color(0xFFE2E2E8)),
        ),
        shape: const StadiumBorder(),
        backgroundColor: isDark ? const Color(0xFF2A2B36) : const Color(0xFFF2F2F7),
        selectedColor: scheme.primary,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontWeight: FontWeight.w500,
          color: isDark ? _darkOn : ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: family,
            fontFamilyFallback: fallback,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      // One input look app-wide — the Lead / entity form box (see NxFieldStyle).
      inputDecorationTheme: NxFieldStyle.theme(scheme, fontFamily: family, fontFamilyFallback: fallback),
      textTheme: text,
      // Thin, soft lines + light-stroke icons in a muted colour (not pure black).
      dividerTheme: DividerThemeData(thickness: 0.6, space: 1, color: scheme.outlineVariant),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      // Built-in back / close / menu buttons use Lucide too (same as every other icon).
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(NxI.arrowLeft),
        closeButtonIconBuilder: (_) => const Icon(NxI.x),
        drawerButtonIconBuilder: (_) => const Icon(NxI.listBullets),
        endDrawerButtonIconBuilder: (_) => const Icon(NxI.listBullets),
      ),
      extensions: [atmosphere],
    );
  }

  static TextTheme _uiText(ColorScheme scheme, String family) {
    const base = TextTheme(
      displayLarge: TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      displayMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.35),
      bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.35),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    );
    // The chosen font everywhere (bundled in assets/fonts — no network, no flicker).
    return base.apply(
      fontFamily: family,
      fontFamilyFallback: uiFontFallback(family),
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
  }
}

@immutable
class NxAtmosphereTokens extends ThemeExtension<NxAtmosphereTokens> {
  const NxAtmosphereTokens({required this.top, required this.mid, required this.bottom, required this.cardElevated});

  final Color top;
  final Color mid;
  final Color bottom;
  final Color cardElevated;

  Color get atmosphereTop => top;

  static NxAtmosphereTokens of(BuildContext context) {
    return Theme.of(context).extension<NxAtmosphereTokens>() ??
        const NxAtmosphereTokens(
          top: AppTheme.lightBg,
          mid: AppTheme.lightBg,
          bottom: AppTheme.lightBg,
          cardElevated: Colors.white,
        );
  }

  @override
  NxAtmosphereTokens copyWith({Color? top, Color? mid, Color? bottom, Color? cardElevated}) {
    return NxAtmosphereTokens(
      top: top ?? this.top,
      mid: mid ?? this.mid,
      bottom: bottom ?? this.bottom,
      cardElevated: cardElevated ?? this.cardElevated,
    );
  }

  @override
  NxAtmosphereTokens lerp(ThemeExtension<NxAtmosphereTokens>? other, double t) {
    if (other is! NxAtmosphereTokens) return this;
    return NxAtmosphereTokens(
      top: Color.lerp(top, other.top, t)!,
      mid: Color.lerp(mid, other.mid, t)!,
      bottom: Color.lerp(bottom, other.bottom, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
    );
  }
}
