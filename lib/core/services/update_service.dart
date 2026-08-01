import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  /// Verifica si hay actualización disponible y la fuerza si existe.
  /// Solo funciona en Android con Play Store. En web/iOS no hace nada.
  static Future<void> verificarActualizacion(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        debugPrint('🔄 Actualización disponible — forzando actualización inmediata');

        // Actualización INMEDIATA — el usuario no puede continuar sin actualizar
        await InAppUpdate.performImmediateUpdate();
      } else {
        debugPrint('✅ App al día — no hay actualizaciones');
      }
    } catch (e) {
      // Si falla (emulador, debug, sin Play Store) continúa normalmente
      debugPrint('ℹ️ in_app_update no disponible: $e');
    }
  }
}
