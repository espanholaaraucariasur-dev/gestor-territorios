import 'package:flutter/material.dart';
import 'package:araucaria_sur/core/constants/app_colors.dart';

class AppTheme {
  // ── Colores modo oscuro (estilo Wise) ────────────────────
  static const _darkBg       = Color(0xFF161B22);  // Fondo principal
  static const _darkSurface  = Color(0xFF1C2128);  // Cards / sheets
  static const _darkCard     = Color(0xFF22272E);  // Cards secundarias
  static const _darkInput    = Color(0xFF2D333B);  // Inputs
  static const _darkBorder   = Color(0xFF373E47);  // Bordes
  static const _darkText     = Color(0xFFCDD9E5);  // Texto primario
  static const _darkTextSub  = Color(0xFF768390);  // Texto secundario
  static const _verde        = Color(0xFF2EA043);  // Verde acento oscuro
  static const _verdeLight   = Color(0xFF3FB950);  // Verde claro

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.secondary),
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

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: _verdeLight,
          secondary: _verdeLight,
          surface: _darkSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: _darkText,
          outline: _darkBorder,
        ),
        scaffoldBackgroundColor: _darkBg,
        cardColor: _darkCard,
        dialogBackgroundColor: _darkSurface,
        canvasColor: _darkSurface,
        // AppBar — mantenemos el gradiente verde
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B5E20),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        // Drawer
        drawerTheme: const DrawerThemeData(
          backgroundColor: _darkSurface,
        ),
        // Bottom sheet
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _darkSurface,
          modalBackgroundColor: _darkSurface,
        ),
        // Cards
        cardTheme: CardTheme(
          color: _darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _darkBorder, width: 0.5),
          ),
        ),
        // Botones
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _verde,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _darkText,
            side: const BorderSide(color: _darkBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _verdeLight),
        ),
        // Inputs
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _verdeLight, width: 2),
          ),
          labelStyle: const TextStyle(color: _darkTextSub),
          hintStyle: const TextStyle(color: _darkTextSub),
        ),
        // Texto
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: _darkText),
          displayMedium: TextStyle(color: _darkText),
          bodyLarge: TextStyle(color: _darkText),
          bodyMedium: TextStyle(color: _darkText),
          bodySmall: TextStyle(color: _darkTextSub),
          titleLarge: TextStyle(color: _darkText),
          titleMedium: TextStyle(color: _darkText),
          titleSmall: TextStyle(color: _darkTextSub),
          labelLarge: TextStyle(color: _darkText),
          labelMedium: TextStyle(color: _darkTextSub),
        ),
        // Iconos
        iconTheme: const IconThemeData(color: _darkTextSub),
        primaryIconTheme: const IconThemeData(color: Colors.white),
        // ListTile
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: _darkText,
          iconColor: _darkTextSub,
        ),
        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? _verdeLight : _darkBorder),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? _verde.withOpacity(0.5)
                  : _darkInput),
        ),
        // Divisores
        dividerColor: _darkBorder,
        dividerTheme: const DividerThemeData(color: _darkBorder, thickness: 0.5),
        // ExpansionTile
        expansionTileTheme: const ExpansionTileThemeData(
          textColor: _darkText,
          iconColor: _darkTextSub,
          collapsedTextColor: _darkText,
          collapsedIconColor: _darkTextSub,
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
        ),
        // Snackbar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _darkCard,
          contentTextStyle: const TextStyle(color: _darkText),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _darkBorder),
          ),
        ),
        // Chips
        chipTheme: ChipThemeData(
          backgroundColor: _darkInput,
          labelStyle: const TextStyle(color: _darkText),
          side: const BorderSide(color: _darkBorder),
        ),
        // PopupMenu
        popupMenuTheme: const PopupMenuThemeData(
          color: _darkSurface,
          textStyle: TextStyle(color: _darkText),
        ),
        // TabBar
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: _darkTextSub,
          indicatorColor: _verdeLight,
        ),
      );
}


  static ThemeData get dark => ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF1E1E1E),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        dialogBackgroundColor: const Color(0xFF1E1E1E),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E1E1E),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF1A1A1A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          elevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF81C784),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white60),
          hintStyle: const TextStyle(color: Colors.white38),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
          titleSmall: TextStyle(color: Colors.white70),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.white,
          iconColor: Colors.white70,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.primary.withOpacity(0.5)
                  : Colors.grey.withOpacity(0.3)),
        ),
        dividerColor: Colors.white12,
        dividerTheme: const DividerThemeData(color: Colors.white12),
        expansionTileTheme: const ExpansionTileThemeData(
          textColor: Colors.white,
          iconColor: Colors.white70,
          collapsedTextColor: Colors.white,
          collapsedIconColor: Colors.white54,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2A2A2A),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2A2A2A),
          labelStyle: const TextStyle(color: Colors.white),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
      );
}
