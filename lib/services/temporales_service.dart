import 'package:cloud_firestore/cloud_firestore.dart';

class TemporalesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Lógica Maestra: Generar la Tarjeta y la Carpeta
  Future<void> generarNuevaTarjeta({
    required String territorio,
    required List<String> idsSeleccionados,
    required int limiteSlider,
  }) async {
    final batch = _db.batch();

    // Aplicamos el recorte del Slider
    final idsParaTarjeta = idsSeleccionados.take(limiteSlider).toList();
    final idsRestantes = idsSeleccionados.skip(limiteSlider).toList();

    // Referencia a la Carpeta Madre (Contenedor)
    DocumentReference carpetaRef =
        _db.collection('territorios/temporales/tarjetas').doc(territorio);
    DocumentSnapshot carpetaSnap = await carpetaRef.get();

    int contador = 0;
    if (carpetaSnap.exists) {
      contador =
          (carpetaSnap.data() as Map<String, dynamic>)['contador_tarjetas'] ??
              0;
    } else {
      // Si la carpeta no existe, la primera dirección la crea
      batch.set(carpetaRef, {
        'nombre_grupo': territorio,
        'tipo': 'agrupacion_temporal',
        'contador_tarjetas': 0,
        'ultimo_cambio': FieldValue.serverTimestamp(),
      });
    }

    // Nomenclatura Automática: T-TEMP [Territorio] [Número]
    int nuevoNumero = contador + 1;
    String nombreTarjeta = 'T-TEMP $territorio $nuevoNumero';

    DocumentReference tarjetaRef =
        carpetaRef.collection('sub_tarjetas').doc(nombreTarjeta);

    batch.set(tarjetaRef, {
      'nombre_tarjeta': nombreTarjeta,
      'cantidad_direcciones': idsParaTarjeta.length,
      'ids_direcciones': idsParaTarjeta,
      'estado': 'preparada',
      'fecha_creacion': FieldValue.serverTimestamp(),
      'icono_visual': 'Icons.layers_outlined', // Según el protocolo
    });

    // Actualizamos contador de la carpeta
    batch.update(carpetaRef, {'contador_tarjetas': nuevoNumero});

    // Vinculación en direcciones_globales
    for (var id in idsParaTarjeta) {
      batch.update(_db.collection('direcciones_globales').doc(id), {
        'tarjeta_id': nombreTarjeta,
      });
    }

    // Limpieza: Las que sobraron por el slider vuelven a null
    for (var id in idsRestantes) {
      batch.update(_db.collection('direcciones_globales').doc(id), {
        'tarjeta_id': null,
      });
    }

    await batch.commit();
  }

  // 2. Lógica de Envío (Asignación a Publicador)
  Future<void> enviarTarjeta(
      String territorio, String nombreTarjeta, String publicador) async {
    DocumentReference ref = _db
        .collection('territorios/temporales/tarjetas')
        .doc(territorio)
        .collection('sub_tarjetas')
        .doc(nombreTarjeta);

    await ref.update({
      'entregado_a': publicador,
      'fecha_salida': FieldValue.serverTimestamp(),
      'estado': 'enviada',
      'icono_visual': 'Icons.outgoing_mail', // Icono de tránsito
    });
  }

  // 3. Lógica de Devolución
  Future<void> devolverTarjeta(String territorio, String nombreTarjeta) async {
    DocumentReference ref = _db
        .collection('territorios/temporales/tarjetas')
        .doc(territorio)
        .collection('sub_tarjetas')
        .doc(nombreTarjeta);

    await ref.update({
      'entregado_a': '',
      'fecha_salida': null,
      'estado': 'preparada',
      'icono_visual': 'Icons.layers_outlined', // Icono original
    });
  }
}
