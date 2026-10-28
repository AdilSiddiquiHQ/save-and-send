import 'package:flutter/material.dart';

import 'i18n.dart';

// ---------------------------------------------------------------------------
// Palette: Quiet, premium, high-contrast consumer palette
// Inspired by top-tier modern craft apps (Linear, Raycast, Things, Wise)
// ---------------------------------------------------------------------------

// Primary Accents
const kGreen = Color(0xFF0F6E47); // Rich British Racing Green / Emerald
const kBrightGreen = Color(0xFF25D366); // WhatsApp Official Green
const kDeepGreen = Color(0xFF0A442B); // Deepest forest green

// Canvas & Neutrals
const kCanvasTop = Color(0xFFFAF9F6); // Warm quiet alabaster
const kCanvasBottom = Color(0xFFF1F3F0); // Subtle soft studio sage
const kSurface = Color(0xFFFFFFFF); // Pure crisp white
const kSurfaceMuted = Color(0xFFF8FAF9); // Whisper-soft tint
const kSurfaceSofter = Color(0xFFF2F5F3); // Soft pill/chip background

// Lines & Borders
const kLine = Color(0xFFE5E9E6); // Clean hairline border
const kLineStrong = Color(0xFFD3DCD5); // Structured border

// Text & Ink
const kInk = Color(0xFF111915); // Deepest obsidian ink
const kMuted = Color(0xFF5F6E66); // Slate neutral with WCAG AAA readability

// Functional Accents
const kBrandTint = Color(0xFFEAF5EE); // Light emerald wash
const kAmber = Color(0xFFC07018); // Refined warm amber
const kAmberTint = Color(0xFFFDF4E7); // Warm amber wash
const kRed = Color(0xFFC53B30); // Crisp ruby danger
const kDangerTint = Color(0xFFFDECEB); // Soft danger wash

// ---------------------------------------------------------------------------
// Typography: World-class pairing
// Headings: Plus Jakarta Sans (tight, confident tracking)
// Body: Manrope (geometric, legible, modern)
// Urdu: Noto Sans Arabic (crafted RTL line-heights without clipping)
// ---------------------------------------------------------------------------
const kFontBody = 'Manrope';
const kFontDisplay = 'PlusJakartaSans';
const kFontUrdu = 'NotoSansArabic';

/// Families the engine may use when a glyph is missing from the main font.
///
/// Only [kFontUrdu] is bundled. The other two are registered by the visual
/// tests so the golden screenshots can show Devanagari and Bengali; on a real
/// device they are absent and Android's own font fallback takes over.
const kFontFallback = <String>[
  kFontUrdu,
  'NotoSansDevanagari',
  'NotoSansBengali',
];

TextStyle _body(
  double size, {
  FontWeight weight = FontWeight.w400,
  double height = 1.5,
  double spacing = 0,
  Color color = kInk,
}) {
  return TextStyle(
    fontFamily: kFontBody,
    fontFamilyFallback: kFontFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
  );
}

TextStyle _display(
  double size, {
  FontWeight weight = FontWeight.w700,
  double height = 1.15,
  double spacing = -0.8,
  Color color = kInk,
}) {
  return TextStyle(
    fontFamily: kFontDisplay,
    fontFamilyFallback: kFontFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
  );
}

ThemeData buildTheme({String language = 'en'}) {
  // Urdu and Arabic both use the bundled Arabic-script face. Languages with
  // other scripts fall through to the platform font, so no extra font is
  // shipped per script.
  final isArabicScript = AppLanguage.usesArabicScript(language);

  TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    double height = 1.18,
    double spacing = -0.6,
    Color color = kInk,
  }) {
    if (isArabicScript) {
      return TextStyle(
        fontFamily: kFontUrdu,
        fontSize: size * 0.92,
        height: 1.55,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: color,
      );
    }
    return _display(
      size,
      weight: weight,
      height: height,
      spacing: spacing,
      color: color,
    );
  }

  const scheme = ColorScheme.light(
    primary: kGreen,
    onPrimary: Colors.white,
    primaryContainer: kBrandTint,
    onPrimaryContainer: kDeepGreen,
    secondary: kAmber,
    onSecondary: Colors.white,
    secondaryContainer: kAmberTint,
    onSecondaryContainer: Color(0xFF533108),
    tertiary: kDeepGreen,
    onTertiary: Colors.white,
    surface: kSurface,
    onSurface: kInk,
    surfaceContainerHighest: kSurfaceMuted,
    onSurfaceVariant: kMuted,
    outline: kLineStrong,
    outlineVariant: kLine,
    error: kRed,
    onError: Colors.white,
    errorContainer: kDangerTint,
    onErrorContainer: Color(0xFF6B1812),
  );

  TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
    double spacing = 0,
    Color color = kInk,
  }) {
    // Letter spacing pulls Arabic-script letters apart, so it stays at zero
    // for those locales.
    return _body(
      size,
      weight: weight,
      height: height,
      spacing: isArabicScript ? 0 : spacing,
      color: color,
    );
  }

  final textTheme = TextTheme(
    displayLarge: display(40, weight: FontWeight.w800, height: 1.08, spacing: -1.4),
    displayMedium: display(32, weight: FontWeight.w800, height: 1.12, spacing: -1.0),
    displaySmall: display(26, weight: FontWeight.w800, height: 1.16, spacing: -0.7),
    headlineLarge: display(24, weight: FontWeight.w700, height: 1.2, spacing: -0.5),
    headlineMedium: display(21, weight: FontWeight.w700, height: 1.22, spacing: -0.35),
    headlineSmall: display(19, weight: FontWeight.w700, height: 1.25, spacing: -0.2),
    titleLarge: display(17, weight: FontWeight.w700, height: 1.3, spacing: -0.1),
    titleMedium: body(15.5, weight: FontWeight.w700, height: 1.4, spacing: -0.05),
    titleSmall: body(14, weight: FontWeight.w600, height: 1.35),
    bodyLarge: body(15.5, height: 1.55, spacing: 0),
    bodyMedium: body(14, height: 1.52),
    bodySmall: body(12.5, height: 1.45, color: kMuted),
    labelLarge: body(15, weight: FontWeight.w700, height: 1.2, spacing: 0.1),
    labelMedium: body(13, weight: FontWeight.w700, height: 1.2, spacing: 0.2),
    labelSmall: body(11, weight: FontWeight.w700, height: 1.2, spacing: 0.9, color: kMuted),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kFontBody,
    fontFamilyFallback: kFontFallback,
    textTheme: textTheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: kCanvasTop,
    dividerTheme: const DividerThemeData(
      color: kLine,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: textTheme.bodyMedium?.copyWith(color: kMuted.withValues(alpha: 0.7)),
      prefixIconColor: kMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kLine, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kLine, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kGreen, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kRed, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kRed, width: 1.8),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kGreen,
      linearTrackColor: kBrandTint,
    ),
  );
}
