import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme.dart';

const String _brightnessModeKey = 'brightness_mode';

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

final brightnessModeProvider =
    StateNotifierProvider<BrightnessModeNotifier, ThemeMode>(
  (ref) => BrightnessModeNotifier(),
);

/// Light ThemeData.
final lightThemeProvider = Provider<ThemeData>((ref) {
  return AppTheme.light(AppPalettes.blockpro);
});

/// Dark ThemeData.
final darkThemeProvider = Provider<ThemeData>((ref) {
  return AppTheme.dark(AppPalettes.blockpro);
});
