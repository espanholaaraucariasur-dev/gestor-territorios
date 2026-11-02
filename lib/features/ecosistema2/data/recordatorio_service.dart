import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'arreglo_service.dart';
import 'notificacion_service.dart';

class RecordatorioService {
  static Timer? _timer;
  static bool _procesando = false;

  static void iniciar() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 12), (_) {
      verificarArreglosPorVencer();
    });
    verificarArreglosPorVencer();
  }

  static void detener() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> verificarArreglosPorVencer() async {
    if (_procesando) return;
    _procesando = true;

    try {
      final porVencer = await ArregloService.obtenerPorVencer(7);

      for (final arreglo in porVencer) {
        final existingNotifs = await FirebaseFirestore.instance
            .collection('eco2_notificaciones')
            .where('arreglo_id', isEqualTo: arreglo.id)
            .where('tipo', isEqualTo: 'recordatorio')
            .get();

        final yaNotificado = existingNotifs.docs.any((doc) {
          final data = doc.data();
          final createdAt = data['created_at'] as dynamic;
          if (createdAt == null) return false;
          final fecha = createdAt.toDate();
          return fecha.isAfter(DateTime.now().subtract(const Duration(days: 1)));
        });

        if (!yaNotificado) {
          final diasRestantes =
              arreglo.fechaFin.difference(DateTime.now()).inDays;
          await NotificacionService.crearRecordatorio(
            paraUid: arreglo.gestionadoPor,
            funcionId: arreglo.funcionId,
            arregloId: arreglo.id,
            titulo: 'Tu arreglo "${arreglo.titulo}" termina en $diasRestantes días',
            mensaje:
                'Crea un nuevo arreglo para el próximo período antes de que termine el actual.',
          );
        }
      }
    } catch (_) {
    } finally {
      _procesando = false;
    }
  }
}
