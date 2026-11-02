import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:araucaria_sur/core/constants/app_colors.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        // CanvasKit (WEB) solo trae Roboto. Para los caracteres que Roboto no
        // cubre (emoji y símbolos como ⏱ ⚠ ↩ ◀ ✅ ❌) la app depende del
        // fallback automático, que intenta bajar Noto de Google Fonts y falla
        // sin red o sin cobertura completa: "Could not find a set of Noto fonts
        // to display all missing characters".
        //
        // Estas dos fuentes van empaquetadas en el bundle (ver pubspec.yaml) y
        // son complementarias: NotoEmoji aporta los símbolos de BMP y
        // NotoSansSymbols2 los emoji astrales. Van DE TRAS de Roboto, así que
        // el texto normal sigue igual y solo caemos en ellas cuando hace falta.
        //
        // ⚠️ CRÍTICO: SOLO se aplican en WEB. Además de emoji, estas fuentes
        // de símbolos contienen glifos ASCII de DÍGITOS y PUNTUACIÓN con
        // métricas de emoji (p.ej. "1"=0.098 em, "0"=1.043 em, "8"=1.27 em).
        // En Android/iOS "Roboto" NO existe como familia empaquetada, así que
        // el motor resolvía los números con estas fuentes -> el desastre
        // visual "1 0 / 1 0 / 2 0 2 6". En web CanvasKit trae Roboto
        // registrado, por eso el bug no se veía ahí. En móvil el SO ya aporta
        // su propia tipografía y sus propios emoji, así que usamos la default.
        fontFamily: kIsWeb ? 'Roboto' : null,
        fontFamilyFallback:
            kIsWeb ? const ['NotoEmoji', 'NotoSansSymbols2'] : null,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onBackground,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.onBackground,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.onBackground),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      );
}
