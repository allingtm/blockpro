import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  // Display
  static const TextStyle displayLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
  );

  // Headlines
  static const TextStyle headlineLarge =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
  static const TextStyle headlineMedium =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const TextStyle headlineSmall =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  // Titles
  static const TextStyle titleLarge =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
  static const TextStyle titleMedium =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static const TextStyle titleSmall =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  // Body
  static const TextStyle bodyLarge =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const TextStyle bodyLargeBold =
      TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
  static const TextStyle bodyMedium =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const TextStyle bodySmall =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  // Labels
  static const TextStyle labelLarge =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle labelMedium =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
  static const TextStyle labelSmall =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  // Caption
  static const TextStyle caption =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
}
