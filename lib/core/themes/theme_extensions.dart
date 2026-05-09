import 'package:flutter/material.dart';

extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get cardBg => isDark ? const Color(0xFF22272E) : Colors.white;
  Color get pageBg => isDark ? const Color(0xFF161B22) : const Color(0xFFF5F5F5);
  Color get surfaceMid => isDark ? const Color(0xFF2D333B) : const Color(0xFFF0F0F0);
  Color get inputFill => isDark ? const Color(0xFF2D333B) : const Color(0xFFF5F5F5);
  Color get dividerColor => isDark ? const Color(0xFF373E47) : Colors.grey.shade200;
  Color get borderColor => isDark ? const Color(0xFF373E47) : Colors.grey.shade200;
  Color get textPrimary => isDark ? const Color(0xFFCDD9E5) : const Color(0xFF1A1A1A);
  Color get textSecondary => isDark ? const Color(0xFF768390) : Colors.grey.shade600;
  Color get textHint => isDark ? const Color(0xFF545D68) : Colors.grey.shade400;
  Color get verde => isDark ? const Color(0xFF2EA043) : const Color(0xFF1B5E20);
  Color get verdeLight => isDark ? const Color(0xFF3FB950) : const Color(0xFF2E7D32);
  Color get statBlueBg => isDark ? const Color(0xFF0D2137) : const Color(0xFFE3F2FD);
  Color get statBlueText => isDark ? const Color(0xFF58A6FF) : const Color(0xFF1565C0);
  Color get statOrangeBg => isDark ? const Color(0xFF2D1B00) : const Color(0xFFFFF3E0);
  Color get statOrangeText => isDark ? const Color(0xFFD29922) : const Color(0xFFE65100);
  Color get statGreenBg => isDark ? const Color(0xFF0D2017) : const Color(0xFFE8F5E9);
  Color get statGreenText => isDark ? const Color(0xFF3FB950) : const Color(0xFF1B5E20);
}
