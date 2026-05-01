import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio de restauración mensual automática.
/// Se ejecuta el primer día de cada mes.
/// NO restaura: estadísticas, tarjetas temporales.
class RestauracionMensual {

  /// Verifica si hoy es el primer día del mes y si ya se ejecutó este mes.
  static Future<bool> debeEjecutarse() async {
    final hoy = DateTime.now();
    if (hoy.day != 1) return false;

    final mesActual = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sistema')
          .doc('restauracion_mensual')
          .get();
      if (doc.exists) {
        final ultimaEjecucion = doc.data()?['ultimo_mes'] as String?;
        if (ultimaEjecucion == mesActual) return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ejecuta la restauración mensual completa.
  /// Reglas:
  /// - SÍ restaura: datos dinámicos de direcciones, tarjetas (bloqueo, asignaciones)
  /// - NO restaura: estadísticas, tarjetas temporales (tipo == 'temporal')
  static Future<void> ejecutar(BuildContext context) async {
    try {
      debugPrint('Iniciando restauración mensual...');

      // 1. Restaurar direcciones dinámicas
      final direccionesSnap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      int batchCount = 0;
      WriteBatch currentBatch = FirebaseFirestore.instance.batch();

      for (final doc in direccionesSnap.docs) {
        currentBatch.update(doc.reference, {
          'visitado': false,
          'predicado': false,
          'estado_predicacion': 'pendiente',
          'asignado_a': null,
          'asignado_en': null,
          'entregado_a': null,
          'entregado_en': null,
          'devuelto': false,
          'devuelto_por': null,
          'devuelto_en': null,
        });
        batchCount++;
        if (batchCount >= 400) {
          await currentBatch.commit();
          currentBatch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) await currentBatch.commit();

      // 2. Restaurar tarjetas (excepto temporales)
      final territoriosSnap = await FirebaseFirestore.instance
          .collection('territorios')
          .get();

      batchCount = 0;
      currentBatch = FirebaseFirestore.instance.batch();

      for (final territorio in territoriosSnap.docs) {
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();

        for (final tarjeta in tarjetasSnap.docs) {
          final data = tarjeta.data();
          // NO restaurar tarjetas temporales
          if (data['tipo'] == 'temporal' || data['es_temporal'] == true) continue;

          currentBatch.update(tarjeta.reference, {
            'disponible_para_publicadores': false,
            'bloqueado': true,
            'asignado_a': null,
            'asignado_en': null,
            'enviado_a': null,
            'enviado_nombre': null,
            'enviado_en': null,
            'estatus_envio': null,
            'hora_programada': null,
            'devuelto': false,
            'devuelto_por': null,
            'devuelto_en': null,
          });
          batchCount++;
          if (batchCount >= 400) {
            await currentBatch.commit();
            currentBatch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
        }

        currentBatch.update(territorio.reference, {
          'disponible_para_publicadores': false,
          'asignado_a': null,
          'asignado_en': null,
          'enviado_a': null,
          'enviado_en': null,
        });
        batchCount++;
      }
      if (batchCount > 0) await currentBatch.commit();

      // 3. Registrar ejecución
      final mesActual = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      await FirebaseFirestore.instance
          .collection('sistema')
          .doc('restauracion_mensual')
          .set({
        'ultimo_mes': mesActual,
        'ejecutado_en': FieldValue.serverTimestamp(),
      });

      debugPrint('Restauración mensual completada');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restauración mensual completada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en restauración mensual: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en restauración mensual: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
