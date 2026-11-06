import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Atmosphere tokens — Inbox lavender fill, floating cards, comfortable ink.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF6366F1);

  static const Color ink = Color(0xFF1C1C1E);
  static const Color inkSecondary = Color(0xFF636366);
  static const Color inkTertiary = Color(0xFF8E8E93);
  static const Color lightBg = Color(0xFFF6F7FB);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightLine = Color(0x147C7C80);

  static const Color _darkSurface = Color(0xFF16161D);
  static const Color _darkVariant = Color(0xFF1E1F28);
  static const Color _darkOn = Color(0xFFF5F5F7);
  static const Color _darkMuted = Color(0xFFA1A1AA);
  static const Color _darkOutline = Color(0xFF4E4E57);

  static const double radius = 16;
  static const double cardRadius = 20;

  static ThemeData get dark => themed(brightness: Brightness.dark);
  static ThemeData get light => themed(brightness: Brightness.light);

  static ThemeData themed({required Brightness brightness, Color? accent}) {
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
          )
        : ColorScheme.light(
            primary: primaryColor,
            onPrimary: Colors.white,
            primaryContainer: container,
            secondary: primaryColor,
            onSecondary: Colors.white,
            surface: lightCard,
            onSurface: ink,
            surfaceContainerHighest: lightBg,
            onSurfaceVariant: inkSecondary,
            outline: const Color(0xFFD1D1D6),
          );
    final scaffold = isDark ? _darkSurface : lightBg;
    final cardColor = isDark ? _darkVariant : lightCard;
    return _base(
      brightness: brightness,
      scheme: scheme,
      scaffold: scaffold,
      card: cardColor,
      cta: primaryColor,
      onCta: Colors.white,
      atmosphere: NxAtmosphereTokens(
        top: scaffold,
        mid: scaffold,
        bottom: scaffold,
        cardElevated: cardColor,
      ),
    );
  }

  static ThemeData _base({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color cta,
    required Color onCta,
    required NxAtmosphereTokens atmosphere,
  }) {
    final isDark = brightness == Brightness.dark;
    final text = _uiText(scheme);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      canvasColor: scaffold,
      scaffoldBackgroundColor: scaffold,
      fontFamily: text.bodyMedium?.fontFamily,
      fontFamilyFallback: const ['Noto Sans Thai', 'Leelawadee UI', 'Tahoma', 'sans-serif'],
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
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
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: const StadiumBorder(),
        backgroundColor: isDark ? _darkVariant : const Color(0xFFF2F2F7),
        selectedColor: cta,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? _darkOn : ink,
        ),
        secondaryLabelStyle: const TextStyle(
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
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 1 : 0.7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 1 : 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      textTheme: text,
      extensions: [atmosphere],
    );
  }

  static bool get _useSystemSf =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static TextTheme _uiText(ColorScheme scheme) {
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
    final colored = base.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final binding = WidgetsBinding.instance.runtimeType.toString();
    if (_useSystemSf || binding.contains('Test')) {
      return colored;
    }
    try {
      final inter = GoogleFonts.interTextTheme(colored);
      final display = GoogleFonts.plusJakartaSansTextTheme(colored);
      final thai = GoogleFonts.notoSansThaiTextTheme(colored);
      return inter.copyWith(
        displayLarge: display.displayLarge,
        displayMedium: display.displayMedium,
        headlineLarge: display.headlineLarge,
        headlineMedium: display.headlineMedium,
        titleLarge: thai.titleLarge ?? display.titleLarge,
        titleMedium: thai.titleMedium ?? inter.titleMedium,
        titleSmall: thai.titleSmall ?? inter.titleSmall,
        bodyLarge: thai.bodyLarge ?? inter.bodyLarge,
        bodyMedium: thai.bodyMedium ?? inter.bodyMedium,
        bodySmall: thai.bodySmall ?? inter.bodySmall,
        labelLarge: thai.labelLarge ?? inter.labelLarge,
        labelMedium: thai.labelMedium ?? inter.labelMedium,
        labelSmall: thai.labelSmall ?? inter.labelSmall,
      );
    } catch (_) {
      return colored;
    }
  }
}

@immutable
class NxAtmosphereTokens extends ThemeExtension<NxAtmosphereTokens> {
  const NxAtmosphereTokens({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.cardElevated,
  });

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
  NxAtmosphereTokens copyWith({
    Color? top,
    Color? mid,
    Color? bottom,
    Color? cardElevated,
  }) {
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
