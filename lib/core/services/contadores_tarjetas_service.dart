import 'package:cloud_firestore/cloud_firestore.dart';

/// Mantiene alineados los dos contadores de una tarjeta:
///
/// - `cantidad_direcciones`: lo que muestran la UI y el publicador.
/// - `totalDirecciones`: el cupo que usa el auto-asignador (máximo 8).
///
/// Ambos deben reflejar la cantidad real de documentos en
/// `direcciones_globales` con ese `tarjeta_id`. Recalcularlos desde la fuente
/// de verdad evita que un flujo que crea, mueve o elimina direcciones deje
/// uno de los dos (o ambos) desactualizado.
class ContadorTarjetasService {
  ContadorTarjetasService._();

  static Future<int> sincronizar({
    required String territorioId,
    required String tarjetaId,
  }) async {
    final db = FirebaseFirestore.instance;
    final agregado = await db
        .collection('direcciones_globales')
        .where('tarjeta_id', isEqualTo: tarjetaId)
        .count()
        .get();
    final real = agregado.count ?? 0;
    await db
        .collection('territorios')
        .doc(territorioId)
        .collection('tarjetas')
        .doc(tarjetaId)
        .update({
      'cantidad_direcciones': real,
      'totalDirecciones': real,
    });
    return real;
  }
}
