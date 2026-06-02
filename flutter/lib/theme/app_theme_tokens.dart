import 'dart:ui';
import 'package:flutter/material.dart';

import 'app_palettes.dart';

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    this.spacingXs = 4,
    this.spacingSm = 8,
    this.spacingMd = 12,
    this.spacingLg = 16,
    this.spacingXl = 24,
    this.spacing2xl = 32,
    this.spacing3xl = 40,
    this.spacing4xl = 60,
    this.radiusSm = 4,
    this.radiusMd = 8,
    this.radiusLg = 12,
    this.radiusXl = 16,
    this.iconSm = 20,
    this.iconMd = 35,
    this.iconLg = 48,
    this.iconXl = 80,
    this.icon2xl = 100,
    this.cardSurface = const Color(0xFFFFFFFF),
    this.textStrong = const Color(0xFF1B2A4A),
    this.textMuted = const Color(0xFF4A5670),
    this.textFaint = const Color(0x8A000000),
    this.brandIcon = kAppBarNavy,
    this.hairline = const Color(0xFFE3E6EC),
    this.fieldFill = const Color(0xFFEFEFEF),
    this.fieldBorder = const Color(0xFFD7DBE3),
  });

  final double spacingXs, spacingSm, spacingMd, spacingLg;
  final double spacingXl, spacing2xl, spacing3xl, spacing4xl;
  final double radiusSm, radiusMd, radiusLg, radiusXl;
  final double iconSm, iconMd, iconLg, iconXl, icon2xl;

  /// Semantic surface/text colours. These differ per brightness so cards,
  /// titles and hairlines render correctly in both light and dark themes.
  final Color cardSurface;
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;
  final Color brandIcon;
  final Color hairline;
  final Color fieldFill;
  final Color fieldBorder;

  static const standard = AppThemeTokens();

  /// Dark-mode colour overrides. Spacing/radius/icon sizes are inherited.
  static const dark = AppThemeTokens(
    cardSurface: Color(0xFF1A2434),
    textStrong: Color(0xFFE8ECF4),
    textMuted: Color(0xFFAEB7C9),
    textFaint: Color(0xB3FFFFFF),
    brandIcon: Color(0xFFA8C4E8),
    hairline: Color(0xFF2E3A50),
    fieldFill: Color(0xFF222E42),
    fieldBorder: Color(0xFF3A4760),
  );

  @override
  AppThemeTokens copyWith({
    double? spacingXs,
    double? spacingSm,
    double? spacingMd,
    double? spacingLg,
    double? spacingXl,
    double? spacing2xl,
    double? spacing3xl,
    double? spacing4xl,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? iconSm,
    double? iconMd,
    double? iconLg,
    double? iconXl,
    double? icon2xl,
    Color? cardSurface,
    Color? textStrong,
    Color? textMuted,
    Color? textFaint,
    Color? brandIcon,
    Color? hairline,
    Color? fieldFill,
    Color? fieldBorder,
  }) {
    return AppThemeTokens(
      spacingXs: spacingXs ?? this.spacingXs,
      spacingSm: spacingSm ?? this.spacingSm,
      spacingMd: spacingMd ?? this.spacingMd,
      spacingLg: spacingLg ?? this.spacingLg,
      spacingXl: spacingXl ?? this.spacingXl,
      spacing2xl: spacing2xl ?? this.spacing2xl,
      spacing3xl: spacing3xl ?? this.spacing3xl,
      spacing4xl: spacing4xl ?? this.spacing4xl,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      iconSm: iconSm ?? this.iconSm,
      iconMd: iconMd ?? this.iconMd,
      iconLg: iconLg ?? this.iconLg,
      iconXl: iconXl ?? this.iconXl,
      icon2xl: icon2xl ?? this.icon2xl,
      cardSurface: cardSurface ?? this.cardSurface,
      textStrong: textStrong ?? this.textStrong,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      brandIcon: brandIcon ?? this.brandIcon,
      hairline: hairline ?? this.hairline,
      fieldFill: fieldFill ?? this.fieldFill,
      fieldBorder: fieldBorder ?? this.fieldBorder,
    );
  }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      spacingXs: lerpDouble(spacingXs, other.spacingXs, t)!,
      spacingSm: lerpDouble(spacingSm, other.spacingSm, t)!,
      spacingMd: lerpDouble(spacingMd, other.spacingMd, t)!,
      spacingLg: lerpDouble(spacingLg, other.spacingLg, t)!,
      spacingXl: lerpDouble(spacingXl, other.spacingXl, t)!,
      spacing2xl: lerpDouble(spacing2xl, other.spacing2xl, t)!,
      spacing3xl: lerpDouble(spacing3xl, other.spacing3xl, t)!,
      spacing4xl: lerpDouble(spacing4xl, other.spacing4xl, t)!,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t)!,
      iconSm: lerpDouble(iconSm, other.iconSm, t)!,
      iconMd: lerpDouble(iconMd, other.iconMd, t)!,
      iconLg: lerpDouble(iconLg, other.iconLg, t)!,
      iconXl: lerpDouble(iconXl, other.iconXl, t)!,
      icon2xl: lerpDouble(icon2xl, other.icon2xl, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      brandIcon: Color.lerp(brandIcon, other.brandIcon, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
    );
  }
}

extension AppThemeTokensExtension on BuildContext {
  AppThemeTokens get tokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? const AppThemeTokens();
}
