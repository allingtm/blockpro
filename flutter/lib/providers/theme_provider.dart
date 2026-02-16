import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme.dart';

const String _themeVariantKey = 'theme_variant';
const String _brightnessModeKey = 'brightness_mode';

/// Manages the selected ThemeVariant (colour palette).
class ThemeVariantNotifier extends StateNotifier<ThemeVariant> {
  ThemeVariantNotifier() : super(ThemeVariant.forest) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeVariantKey);
    if (saved != null) {
      state = ThemeVariant.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => ThemeVariant.forest,
      );
    }
  }

  Future<void> set(ThemeVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeVariantKey, variant.name);
  }
}

/// Manages the brightness mode (light, dark, or system).
class BrightnessModeNotifier extends StateNotifier<ThemeMode> {
  BrightnessModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_brightnessModeKey);
    if (saved != null) {
      state = ThemeMode.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brightnessModeKey, mode.name);
  }
}

// ── Providers ──────────────────────────────────────────────

final themeVariantProvider =
    StateNotifierProvider<ThemeVariantNotifier, ThemeVariant>(
  (ref) => ThemeVariantNotifier(),
);

final brightnessModeProvider =
    StateNotifierProvider<BrightnessModeNotifier, ThemeMode>(
  (ref) => BrightnessModeNotifier(),
);

/// Light ThemeData for the current variant.
final lightThemeProvider = Provider<ThemeData>((ref) {
  final variant = ref.watch(themeVariantProvider);
  final schemeData = AppPalettes.getSchemeData(variant);
  return AppTheme.light(schemeData);
});

/// Dark ThemeData for the current variant.
final darkThemeProvider = Provider<ThemeData>((ref) {
  final variant = ref.watch(themeVariantProvider);
  final schemeData = AppPalettes.getSchemeData(variant);
  return AppTheme.dark(schemeData);
});
