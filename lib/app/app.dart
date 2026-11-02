import 'package:flutter/material.dart';
import '../core/themes/app_theme.dart';
import '../core/l10n/translation_service.dart';
import '../core/services/offline_sync_service.dart';
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
        builder: (context, child) => AnimatedBuilder(
          animation: OfflineSyncService.instance,
          builder: (context, _) => Column(
            children: [
              OfflineStatusBanner(
                offline: OfflineSyncService.instance.isOffline,
                syncing: OfflineSyncService.instance.isSyncing,
              ),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
        home: const SplashPage(),
      ),
    );
  }
}
