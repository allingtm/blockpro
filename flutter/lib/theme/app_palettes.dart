import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

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
