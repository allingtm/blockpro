import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Fixed dark navy used by the brand AppBar and end-drawer in both themes.
const Color kAppBarNavy = Color(0xFF0E1A2E);

/// Primary action blue used on Start / Complete / Continue buttons.
const Color kActionBlue = Color(0xFF3F7BE0);

/// Stripe accent colours for status indicators on cards.
const Color kStatusRed = Color(0xFFD64545);
const Color kStatusAmber = Color(0xFFE0A340);
const Color kStatusGreen = Color(0xFF3FB76A);

/// Scaffold background used in light mode (just off-white).
const Color kScaffoldGrey = Color(0xFFF4F5F7);

/// BlockPro brand colour palette.
///
/// FlexColorScheme generates full M3 tonal palettes from these seeds.
class AppPalettes {
  AppPalettes._();

  static const blockpro = FlexSchemeData(
    name: 'BlockPro',
    description: 'Brand blues with green and red accents',
    light: FlexSchemeColor(
      primary: Color(0xFF345799),
      primaryContainer: Color(0xFFD4DFEF),
      secondary: Color(0xFF3A63B5),
      secondaryContainer: Color(0xFFD6E0F2),
      tertiary: Color(0xFF43B86A),
      tertiaryContainer: Color(0xFFC8F0D4),
      error: Color(0xFFC13F39),
      errorContainer: Color(0xFFFCDAD8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFA8C4E8),
      primaryContainer: Color(0xFF1E3A66),
      secondary: Color(0xFF9BB8E8),
      secondaryContainer: Color(0xFF1E3566),
      tertiary: Color(0xFF8EDDA6),
      tertiaryContainer: Color(0xFF1E7A3E),
      error: Color(0xFFF0918C),
      errorContainer: Color(0xFF7A1F1B),
    ),
  );
}
