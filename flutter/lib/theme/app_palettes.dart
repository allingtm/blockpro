import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Available theme variants the user can select.
enum ThemeVariant {
  forest('Forest'),
  ocean('Ocean'),
  rose('Rose'),
  ember('Ember'),
  midnight('Midnight'),
  lavender('Lavender'),
  highContrast('High Contrast');

  final String displayName;
  const ThemeVariant(this.displayName);
}

/// Defines seed color schemes for each ThemeVariant.
///
/// FlexColorScheme generates full M3 tonal palettes from these seeds.
/// Only 6 colours are needed per mode — the rest is computed.
class AppPalettes {
  AppPalettes._();

  // ── Forest ──────────────────────────────────────────────
  static const forest = FlexSchemeData(
    name: 'Forest',
    description: 'Natural greens with warm earth tones',
    light: FlexSchemeColor(
      primary: Color(0xFF4A7C59),
      primaryContainer: Color(0xFFB8E0C4),
      secondary: Color(0xFF8B6914),
      secondaryContainer: Color(0xFFFFF0C2),
      tertiary: Color(0xFF5C6B5E),
      tertiaryContainer: Color(0xFFD8E8DA),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFF81C784),
      primaryContainer: Color(0xFF2E5235),
      secondary: Color(0xFFFFD270),
      secondaryContainer: Color(0xFF5C4400),
      tertiary: Color(0xFFA8C4AA),
      tertiaryContainer: Color(0xFF3A4A3C),
    ),
  );

  // ── Ocean ───────────────────────────────────────────────
  static const ocean = FlexSchemeData(
    name: 'Ocean',
    description: 'Deep blues with coral accents',
    light: FlexSchemeColor(
      primary: Color(0xFF1565C0),
      primaryContainer: Color(0xFFD1E4FF),
      secondary: Color(0xFFE65100),
      secondaryContainer: Color(0xFFFFDBC8),
      tertiary: Color(0xFF006B5E),
      tertiaryContainer: Color(0xFFC2F0E9),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFF90CAF9),
      primaryContainer: Color(0xFF0D47A1),
      secondary: Color(0xFFFFAB6B),
      secondaryContainer: Color(0xFF7A3300),
      tertiary: Color(0xFF6FD5C5),
      tertiaryContainer: Color(0xFF004D42),
    ),
  );

  // ── Rose ────────────────────────────────────────────────
  static const rose = FlexSchemeData(
    name: 'Rose',
    description: 'Warm pinks with soft purples',
    light: FlexSchemeColor(
      primary: Color(0xFFC2185B),
      primaryContainer: Color(0xFFFFD9E2),
      secondary: Color(0xFF7B1FA2),
      secondaryContainer: Color(0xFFF3E5F5),
      tertiary: Color(0xFF8D6E63),
      tertiaryContainer: Color(0xFFEFDED8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFF48FB1),
      primaryContainer: Color(0xFF880E4F),
      secondary: Color(0xFFCE93D8),
      secondaryContainer: Color(0xFF4A148C),
      tertiary: Color(0xFFBCAAA4),
      tertiaryContainer: Color(0xFF4E342E),
    ),
  );

  // ── Ember ───────────────────────────────────────────────
  static const ember = FlexSchemeData(
    name: 'Ember',
    description: 'Bold orange with dark contrast',
    light: FlexSchemeColor(
      primary: Color(0xFFE65100),
      primaryContainer: Color(0xFFFFCCBC),
      secondary: Color(0xFF212121),
      secondaryContainer: Color(0xFFE0E0E0),
      tertiary: Color(0xFF795548),
      tertiaryContainer: Color(0xFFEFDED8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFFFAB6B),
      primaryContainer: Color(0xFF8B3200),
      secondary: Color(0xFFBDBDBD),
      secondaryContainer: Color(0xFF424242),
      tertiary: Color(0xFFBCAAA4),
      tertiaryContainer: Color(0xFF3E2723),
    ),
  );

  // ── Midnight ────────────────────────────────────────────
  static const midnight = FlexSchemeData(
    name: 'Midnight',
    description: 'Deep navy with gold accents',
    light: FlexSchemeColor(
      primary: Color(0xFF00296B),
      primaryContainer: Color(0xFFA0C2ED),
      secondary: Color(0xFFD26900),
      secondaryContainer: Color(0xFFFFD270),
      tertiary: Color(0xFF5C5C95),
      tertiaryContainer: Color(0xFFC8DBF8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFB1CFF5),
      primaryContainer: Color(0xFF3873BA),
      secondary: Color(0xFFFFD270),
      secondaryContainer: Color(0xFFD26900),
      tertiary: Color(0xFFC9CBFC),
      tertiaryContainer: Color(0xFF535393),
    ),
  );

  // ── Lavender ────────────────────────────────────────────
  static const lavender = FlexSchemeData(
    name: 'Lavender',
    description: 'Soft purple with sage green',
    light: FlexSchemeColor(
      primary: Color(0xFF6750A4),
      primaryContainer: Color(0xFFE8DEF8),
      secondary: Color(0xFF558B2F),
      secondaryContainer: Color(0xFFDCEDC8),
      tertiary: Color(0xFF7D5260),
      tertiaryContainer: Color(0xFFFFD9E3),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFCFBCFF),
      primaryContainer: Color(0xFF4F378B),
      secondary: Color(0xFFC5E1A5),
      secondaryContainer: Color(0xFF33691E),
      tertiary: Color(0xFFEFB8C8),
      tertiaryContainer: Color(0xFF633B48),
    ),
  );

  // ── High Contrast ───────────────────────────────────────
  static const highContrast = FlexSchemeData(
    name: 'High Contrast',
    description: 'Maximum readability (WCAG AAA)',
    light: FlexSchemeColor(
      primary: Color(0xFF000000),
      primaryContainer: Color(0xFFE0E0E0),
      secondary: Color(0xFF00296B),
      secondaryContainer: Color(0xFFD1E4FF),
      tertiary: Color(0xFF4A148C),
      tertiaryContainer: Color(0xFFF3E5F5),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF424242),
      secondary: Color(0xFF90CAF9),
      secondaryContainer: Color(0xFF0D47A1),
      tertiary: Color(0xFFCE93D8),
      tertiaryContainer: Color(0xFF4A148C),
    ),
  );

  /// Returns the FlexSchemeData for a given variant.
  static FlexSchemeData getSchemeData(ThemeVariant variant) {
    return switch (variant) {
      ThemeVariant.forest => forest,
      ThemeVariant.ocean => ocean,
      ThemeVariant.rose => rose,
      ThemeVariant.ember => ember,
      ThemeVariant.midnight => midnight,
      ThemeVariant.lavender => lavender,
      ThemeVariant.highContrast => highContrast,
    };
  }

  /// Returns [backgroundColor, primaryColor] for theme selector preview circles.
  static List<Color> getPreviewColors(
      ThemeVariant variant, Brightness brightness) {
    final data = getSchemeData(variant);
    final colors = brightness == Brightness.dark ? data.dark : data.light;
    return [
      brightness == Brightness.dark ? const Color(0xFF1C1B1F) : Colors.white,
      colors.primary,
    ];
  }
}
