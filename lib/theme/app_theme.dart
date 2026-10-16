import 'package:flutter/material.dart';

const paper = Color(0xFFF4F0EA);
const ink = Color(0xFF1C1917);
const accent = Color(0xFF0F6E6B);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    surface: paper,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Color(0xFFD6D0C8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6D0C8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6D0C8)),
      ),
    ),
  );
}
