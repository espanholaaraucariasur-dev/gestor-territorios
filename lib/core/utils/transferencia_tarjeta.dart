import 'package:araucaria_sur/core/services/notificacion_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Lógica compartida para transferir una tarjeta entre publicadores.
///
/// CONtexto: la propiedad de una tarjeta se define por UN SOLO campo,
/// `asignado_a` (el NOMBRE del publicador). El publicador ve sus tarjetas con
/// `collectionGroup('tarjetas').where('asignado_a', isEqualTo: nombre)`.
/// Por eso, cambiar `asignado_a` hace que la tarjeta desaparezca de la lista
/// del publicador anterior en el siguiente snapshot, sin aviso.
///
/// Estas utilidades evitan esa sorpresa: leen el dueño actual ANTES de
/// escribir, exigen confirmación explícita nombrando al publicador afectado, y
/// le notifican para que no se entere por la vía de la tarjeta perdida.
class TransferenciaTarjeta {
  TransferenciaTarjeta._();

  /// Dominios de correo de prueba / reserva que NUNCA son publicadores reales.
  static const Set<String> _destinatariosDePrueba = {
    'correo.com',
    'email.com',
    'tucorreo.com',
    'tucorreo.com.com',
    'example.com',
    'test.com',
  };

  static bool _esEmailValido(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    if (e.isEmpty) return false;
    for (final dominio in _destinatariosDePrueba) {
      if (e.endsWith('@$dominio')) return false;
    }
    return e.contains('@') && e.contains('.');
  }

  /// Marca de tiempo en que la tarjeta quedó con su dueño, si existe.
  static DateTime? _fechaAsignacion(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final k in ['asignado_en', 'enviado_en', 'tomado_en']) {
      final v = data[k];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }

  /// Normaliza el nombre del dueño actual. Devuelve `null` si la tarjeta está
  /// libre (o el campo está vacío), para poder compararlo con seguridad.
  ///
  /// Si se pasa [vencidoTras], un dueño cuya asignación sea más antigua que ese
  /// lapso se considera vencido y se devuelve `null`: la tarjeta "dura" con el
  /// publicador un tiempo limitado y la devolución automática puede no haberla
  /// limpiado todavía.
  static String? leerDuenoActual(
    Map<String, dynamic>? data, {
    Duration? vencidoTras,
  }) {
    final crudo = (data?['asignado_a'] as String?)?.trim();
    if (crudo == null || crudo.isEmpty) return null;
    if (vencidoTras != null) {
      final t = _fechaAsignacion(data);
      if (t != null && DateTime.now().difference(t) > vencidoTras) return null;
    }
    return crudo;
  }

  /// ¿El envío es un simple reenvío al mismo dueño, o realmente lo mueve?
  static bool esTransferenciaReal(String? duenoActual, String nuevoDueno) {
    if (duenoActual == null) return false;
    return duenoActual.toLowerCase() != nuevoDueno.trim().toLowerCase();
  }

  /// Pide confirmación explícita cuando la tarjeta ya tiene dueño y se va a
  /// quitarle. Devuelve `true` solo si el usuario confirma.
  static Future<bool> confirmarTransferencia({
    required BuildContext context,
    required String tarjetaNombre,
    required String? duenoActual,
    required String nuevoDueno,
    String? nuevoEmail,
  }) async {
    if (!esTransferenciaReal(duenoActual, nuevoDueno)) return true;

    final actual = duenoActual!;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.swap_horiz, color: Colors.orange, size: 32),
        title: const Text('La tarjeta ya tiene dueño'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, height: 1.4),
                children: [
                  const TextSpan(text: 'La tarjeta '),
                  TextSpan(
                    text: '"$tarjetaNombre"',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' está siendo trabajada por '),
                  TextSpan(
                    text: actual,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Si continuas, la tarjeta se le QUITA a $actual y '
                      'pasará a $nuevoDueno. Le enviaremos una notificación '
                      'para avisarle.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
            if (nuevoEmail != null && !_esEmailValido(nuevoEmail)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Atención: el correo "$nuevoEmail" parece inválido o de '
                      'prueba. Verifica antes de transferir.',
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar y transferir'),
          ),
        ],
      ),
    );
    return confirmado == true;
  }

  /// Avisa al publicador que perderá la tarjeta, y a los admins de territorio.
  /// Nunca lanza: una notificación fallida no debe tumbar la transferencia.
  static Future<void> notificarTransferencia({
    required String? duenoAnterior,
    required String nuevoDueno,
    required String tarjetaNombre,
    String? territorioId,
    String? territorioNombre,
  }) async {
    if (duenoAnterior == null) return;
    final anterior = duenoAnterior.trim();
    if (anterior.isEmpty) return;

    try {
      await NotificacionService.enviarAUser(
        destinatarioNombre: anterior,
        titulo: '📤 Te quitaron una tarjeta',
        cuerpo: '"$tarjetaNombre" fue reasignada a $nuevoDueno'
            '${territorioNombre != null && territorioNombre.isNotEmpty ? " ($territorioNombre)" : ""}.',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {
          'screen': 'mis_tarjetas',
          'tarjeta_nombre': tarjetaNombre,
          'nuevo_dueno': nuevoDueno,
          if (territorioId != null) 'territorio_id': territorioId,
          if (territorioNombre != null) 'territorio_nombre': territorioNombre,
        },
      );
    } catch (_) {
      // La notificación es best-effort.
    }
  }

  /// Avisa al nuevo dueño de que ya tiene la tarjeta.
  static Future<void> notificarnuevoDueno({
    required String nuevoDueno,
    required String tarjetaNombre,
    String? territorioNombre,
  }) async {
    try {
      await NotificacionService.enviarAUser(
        destinatarioNombre: nuevoDueno,
        titulo: '📋 Tarjeta asignada',
        cuerpo: 'Se te asignó la tarjeta "$tarjetaNombre"'
            '${territorioNombre != null && territorioNombre.isNotEmpty ? " ($territorioNombre)" : ""}.',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {
          'screen': 'mis_tarjetas',
          'tarjeta_nombre': tarjetaNombre,
        },
      );
    } catch (_) {}
  }
}
