import 'dart:ui';
import 'package:flutter/material.dart';

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
  });

  final double spacingXs, spacingSm, spacingMd, spacingLg;
  final double spacingXl, spacing2xl, spacing3xl, spacing4xl;
  final double radiusSm, radiusMd, radiusLg, radiusXl;
  final double iconSm, iconMd, iconLg, iconXl, icon2xl;

  static const standard = AppThemeTokens();

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
    );
  }
}

extension AppThemeTokensExtension on BuildContext {
  AppThemeTokens get tokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? const AppThemeTokens();
}
