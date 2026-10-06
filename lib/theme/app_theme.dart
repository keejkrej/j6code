import 'package:flutter/material.dart';

class AppTheme {
  // T3 Code dark design system colors
  static const Color background = Color(0xFF0F0F10);
  static const Color surface = Color(0xFF161618);
  static const Color surfaceSubtle = Color(0xFF1E1E22);
  static const Color surfaceHover = Color(0xFF26262B);
  static const Color border = Color(0xFF2B2B30);
  static const Color borderSubtle = Color(0xFF222226);
  
  static const Color textPrimary = Color(0xFFEEEEF0);
  static const Color textSecondary = Color(0xFF9E9EA8);
  static const Color textMuted = Color(0xFF6B6B76);
  
  static const Color accent = Color(0xFF6366F1); // Indigo / Violet
  static const Color accentHover = Color(0xFF7D80F5);
  static const Color accentSubtle = Color(0x1F6366F1);
  
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFEAB308);
  static const Color error = Color(0xFFEF4444);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      fontFamily: 'Segoe UI',
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        surfaceContainerHighest: surfaceSubtle,
        onSurface: textPrimary,
      ),
      dividerColor: border,
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(border),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
