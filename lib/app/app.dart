import 'package:flutter/material.dart';
import '../core/themes/app_theme.dart';
import '../core/themes/theme_provider.dart';
import '../core/l10n/translation_service.dart';
import '../features/auth/presentation/pages/splash_page.dart';

class AraucariaApp extends StatelessWidget {
  const AraucariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeProviderScope(
      child: TranslationProvider(
        initialLanguage: 'ES',
        child: Builder(
          builder: (context) {
            final themeProvider = ThemeProviderScope.of(context);
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Congregación Araucaria Sur',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeProvider.themeMode,
              home: const SplashPage(),
            );
          },
        ),
      ),
    );
  }
}
