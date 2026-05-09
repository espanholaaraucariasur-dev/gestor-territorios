import 'package:flutter/material.dart';
import '../core/themes/app_theme.dart';
import '../core/l10n/translation_service.dart';
import '../features/auth/presentation/pages/splash_page.dart';

class AraucariaApp extends StatelessWidget {
  const AraucariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(
      initialLanguage: 'ES',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Araucaria Sur',
        theme: AppTheme.light,
        home: const SplashPage(),
      ),
    );
  }
}
