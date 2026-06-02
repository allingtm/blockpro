import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'app_palettes.dart';
import 'app_theme_tokens.dart';

/// Builds ThemeData using FlexColorScheme.
///
/// Uses the seed colours from [AppPalettes] to generate a complete
/// Material 3 ColorScheme with tonal palettes, surface blends,
/// and component themes.
class AppTheme {
  AppTheme._();

  /// Build a light theme from a [FlexSchemeData].
  static ThemeData light(FlexSchemeData schemeData) {
    final base = FlexThemeData.light(
      // ── Colours ─────────────────────────────────────
      colors: schemeData.light,
      useMaterial3: true,

      // ── Seed-generated ColorScheme ──────────────────
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),

      // ── Surface blending ────────────────────────────
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 4,

      // ── Component themes ────────────────────────────
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 10,
        blendOnColors: false,

        // Input decoration
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 12.0,
        inputDecoratorIsFilled: true,

        // Consistent radius
        defaultRadius: 12.0,

        // AppBar
        appBarCenterTitle: true,
        appBarScrolledUnderElevation: 0,
      ),

      // ── Typography ──────────────────────────────────
      typography: Typography.material2021(
        platform: TargetPlatform.android,
      ),

      // ── Theme extensions ────────────────────────────
      extensions: <ThemeExtension<dynamic>>{
        AppThemeTokens.standard,
      },
    );

    return base.copyWith(
      scaffoldBackgroundColor: kScaffoldGrey,
      appBarTheme: _navyAppBarTheme(),
      cardTheme: _brandCardTheme(AppThemeTokens.standard.cardSurface),
    );
  }

  /// Build a dark theme from a [FlexSchemeData].
  static ThemeData dark(FlexSchemeData schemeData) {
    final base = FlexThemeData.dark(
      colors: schemeData.dark,
      useMaterial3: true,

      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),

      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 8,

      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 20,
        blendOnColors: true,

        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 12.0,
        inputDecoratorIsFilled: true,

        defaultRadius: 12.0,

        appBarCenterTitle: true,
        appBarScrolledUnderElevation: 0,
      ),

      typography: Typography.material2021(
        platform: TargetPlatform.android,
      ),

      extensions: <ThemeExtension<dynamic>>{
        AppThemeTokens.dark,
      },
    );

    return base.copyWith(
      appBarTheme: _navyAppBarTheme(),
      cardTheme: _brandCardTheme(AppThemeTokens.dark.cardSurface),
    );
  }

  static AppBarTheme _navyAppBarTheme() {
    return const AppBarTheme(
      backgroundColor: kAppBarNavy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: Colors.white),
      actionsIconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static CardThemeData _brandCardTheme(Color surface) {
    return CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      margin: EdgeInsets.zero,
    );
  }
}

/// Convenience extension for accessing ColorScheme from BuildContext.
extension AppColorsExtension on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}
