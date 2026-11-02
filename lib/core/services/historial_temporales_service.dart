import 'dart:async';
import 'dart:developer' as developer;

import 'package:araucaria_sur/core/services/estadisticas_temporales_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Registra entradas y salidas de direcciones hacia/desde la bandeja de
/// temporales. Cada documento: {tipo: 'entrada'|'salida', direccion_id,
/// territorio_origen_id, territorio_origen_nombre, calle, fecha, motivo}.
/// Este histórico alimenta el gráfico de movimiento de temporales en
/// estadísticas.
///
/// Devuelve `true` solo si el movimiento quedó registrado de verdad.
///
/// Antes esto tenía un `catch (e) {}` vacío: si fallaba la escritura, la
/// dirección se quedaba en la bandeja de temporales (el batch que la mueve sí
/// se había confirmado) pero sin movimiento y sin contador. La estadística se
/// separaba de la realidad de forma permanente y silenciosa — así aparecieron
/// 9 direcciones sin movimiento el 26/09. Ahora el error se registra y el
/// llamador puede avisar en vez de perderlo.
Future<bool> registrarMovimientoTemporal({
  required String tipo, // 'entrada' | 'salida'
  required String direccionId,
  String? territorioOrigenId,
  String? territorioOrigenNombre,
  String? calle,
  String? motivo,
  String? por,
}) async {
  final movimiento =
      FirebaseFirestore.instance.collection('historial_temporales').add({
    'tipo': tipo,
    'direccion_id': direccionId,
    'territorio_origen_id': territorioOrigenId ?? '',
    'territorio_origen_nombre': territorioOrigenNombre ?? '',
    'calle': calle ?? '',
    'motivo': motivo ?? '',
    'por': por ?? '',
    'fecha': Timestamp.now(),
  });

  // Ambas escrituras se encolan en Firestore y se reflejan en caché. No esperar
  // el ACK de red: el historial y su contador se sincronizan al reconectar.
  unawaited(
      movimiento.then<void>((_) {}, onError: (Object error, StackTrace st) {
    developer.log(
      'No se pudo sincronizar el movimiento $tipo de $direccionId.',
      name: 'historial_temporales',
      error: error,
      stackTrace: st,
    );
  }));
  unawaited(EstadisticasTemporalesService.sumarMovimiento(tipo));
  return true;
}
