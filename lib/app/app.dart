import 'package:flutter/material.dart';
import '../core/themes/app_theme.dart';
import '../features/auth/presentation/pages/splash_page.dart';

class AraucariaApp extends StatelessWidget {
  const AraucariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Congregación Araucaria Sur',
      theme: AppTheme.light,
      home: const SplashPage(),
    );
  }
}
