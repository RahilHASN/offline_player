import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B0B12);
  static const card = Color(0xFF1B1B28);
  static const music = <Color>[Color(0xFF8B5CF6), Color(0xFFEC4899)];
  static const video = <Color>[Color(0xFF06B6D4), Color(0xFF3B82F6)];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8B5CF6),
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.bg,
    primary: const Color(0xFFA78BFA),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
  );
}
