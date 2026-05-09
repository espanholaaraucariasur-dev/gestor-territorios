import 'package:flutter/material.dart';

/// Extensión para obtener colores que se adaptan al modo oscuro.
/// Uso: context.cardBg, context.textPrimary, context.surface, etc.
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // Superficies
  Color get cardBg => isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get pageBg => isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
  Color get surfaceMid => isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
  Color get inputFill => isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
  Color get dividerColor => isDark ? Colors.white12 : Colors.grey.shade200;
  Color get borderColor => isDark ? Colors.white12 : Colors.grey.shade200;

  // Texto
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textSecondary => isDark ? Colors.white70 : Colors.grey.shade600;
  Color get textHint => isDark ? Colors.white38 : Colors.grey.shade400;

  // Colores de marca (no cambian)
  Color get verde => const Color(0xFF1B5E20);
  Color get verdeLight => const Color(0xFF2E7D32);
  Color get verdeAccent => const Color(0xFF4CAF50);

  // Contenedor header verde (siempre verde)
  Color get headerBg => const Color(0xFF1B5E20);

  // Stats cards
  Color get statBlueBg => isDark ? const Color(0xFF0D2A4A) : const Color(0xFFE3F2FD);
  Color get statBlueText => isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
  Color get statOrangeBg => isDark ? const Color(0xFF3E2000) : const Color(0xFFFFF3E0);
  Color get statOrangeText => isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
  Color get statGreenBg => isDark ? const Color(0xFF0A2A0A) : const Color(0xFFE8F5E9);
  Color get statGreenText => isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20);
}
