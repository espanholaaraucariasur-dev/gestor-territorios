import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum UpdateCheckResult { continuar, bloqueado }

class UpdateService {
  static StreamSubscription<InstallStatus>? _descargaFlexible;

  /// Verifica si hay actualización disponible y la fuerza.
  /// Solo funciona en Android con Play Store. En web/iOS no hace nada.
  ///
  /// Devuelve [UpdateCheckResult.bloqueado] cuando hay una actualización
  /// confirmada que el usuario no completó (canceló o falló). Si la
  /// comprobación no se puede hacer (sin red, APK fuera de Play, emulador),
  /// devuelve [UpdateCheckResult.continuar] para no dejar la app inutilizable.
  static Future<UpdateCheckResult> verificarActualizacion() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return UpdateCheckResult.continuar;
    }

    final AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('ℹ️ No se pudo comprobar actualización: $e');
      return UpdateCheckResult.continuar;
    }

    try {
      switch (info.updateAvailability) {
        case UpdateAvailability.unknown:
        case UpdateAvailability.updateNotAvailable:
          debugPrint('✅ App al día — no hay actualizaciones');
          return UpdateCheckResult.continuar;

        case UpdateAvailability.developerTriggeredUpdateInProgress:
          return _continuarDescargaFlexible(info);

        case UpdateAvailability.updateAvailable:
          debugPrint('🔄 Actualización disponible — forzando actualización');

          if (info.immediateUpdateAllowed) {
            final resultado = await InAppUpdate.performImmediateUpdate();
            if (resultado == AppUpdateResult.success) {
              return UpdateCheckResult.continuar;
            }
            debugPrint('⛔ Actualización inmediata no completada: $resultado');
            return UpdateCheckResult.bloqueado;
          }

          if (info.flexibleUpdateAllowed) {
            if (info.installStatus == InstallStatus.downloaded) {
              await InAppUpdate.completeFlexibleUpdate();
              return UpdateCheckResult.continuar;
            }

            final resultado = await InAppUpdate.startFlexibleUpdate();
            if (resultado == AppUpdateResult.success) {
              _escucharDescargaFlexible();
              return UpdateCheckResult.bloqueado;
            }
            debugPrint('⛔ Actualización flexible no iniciada: $resultado');
          }

          return UpdateCheckResult.bloqueado;
      }
    } catch (e) {
      debugPrint('⛔ Error al aplicar actualización: $e');
      return UpdateCheckResult.bloqueado;
    }
  }

  static Future<UpdateCheckResult> _continuarDescargaFlexible(
    AppUpdateInfo info,
  ) async {
    if (info.installStatus == InstallStatus.downloaded) {
      try {
        await InAppUpdate.completeFlexibleUpdate();
      } catch (e) {
        debugPrint('⛔ No se pudo instalar la actualización descargada: $e');
        return UpdateCheckResult.bloqueado;
      }
      return UpdateCheckResult.continuar;
    }

    if (info.installStatus == InstallStatus.installed) {
      return UpdateCheckResult.continuar;
    }

    if (info.installStatus == InstallStatus.failed ||
        info.installStatus == InstallStatus.canceled) {
      if (info.flexibleUpdateAllowed) {
        final resultado = await InAppUpdate.startFlexibleUpdate();
        if (resultado == AppUpdateResult.success) {
          _escucharDescargaFlexible();
          return UpdateCheckResult.bloqueado;
        }
      }
      return UpdateCheckResult.bloqueado;
    }

    _escucharDescargaFlexible();
    return UpdateCheckResult.bloqueado;
  }

  static void _escucharDescargaFlexible() {
    _descargaFlexible?.cancel();
    _descargaFlexible =
        InAppUpdate.installUpdateListener.listen((status) async {
      if (status == InstallStatus.downloaded) {
        await _descargaFlexible?.cancel();
        _descargaFlexible = null;
        try {
          await InAppUpdate.completeFlexibleUpdate();
        } catch (e) {
          debugPrint('⛔ No se pudo completar la actualización flexible: $e');
        }
      }
    });
  }
}
