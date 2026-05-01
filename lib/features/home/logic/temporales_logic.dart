import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> generarTarjetaTemporal({
  required String nombreTerritorio,
  required List<DocumentSnapshot> direccionesSeleccionadas,
  required int cantidadSlider,
}) async {
  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();

  // 1. Recorte de lista basado en el Slider
  final direccionesParaTarjeta = direccionesSeleccionadas.take(cantidadSlider).toList();
  final direccionesRestantes = direccionesSeleccionadas.skip(cantidadSlider).toList();

  // 2. Referencia a la Carpeta (Contenedor)
  DocumentReference carpetaRef = firestore.collection('territorios/temporales/tarjetas').doc(nombreTerritorio);
  DocumentSnapshot carpetaSnap = await carpetaRef.get();

  int siguienteNumero = 1;
  if (carpetaSnap.exists) {
    // Si existe, leemos el contador para la nomenclatura
    Map<String, dynamic> data = carpetaSnap.data() as Map<String, dynamic>;
    siguienteNumero = (data['contador_tarjetas'] ?? 0) + 1;
  } else {
    // Si no existe, creamos la carpeta madre
    batch.set(carpetaRef, {
      'nombre_grupo': nombreTerritorio,
      'tipo': 'agrupacion_temporal',
      'contador_tarjetas': 0,
      'ultimo_cambio': FieldValue.serverTimestamp(),
    });
  }

  // 3. Crear la Tarjeta con Nomenclatura Automática
  String nombreTarjeta = 'T-TEMP $nombreTerritorio $siguienteNumero';
  DocumentReference tarjetaRef = carpetaRef.collection('sub_tarjetas').doc(nombreTarjeta);

  // 4. Extraer IDs de las direcciones para la tarjeta
  final idsDirecciones = direccionesParaTarjeta.map((doc) => doc.id).toList();

  batch.set(tarjetaRef, {
    'nombre_tarjeta': nombreTarjeta,
    'cantidad_direcciones': idsDirecciones.length,
    'ids_direcciones': idsDirecciones,
    'estado': 'preparada',
    'fecha_creacion': FieldValue.serverTimestamp(),
    'territorio_nombre': nombreTerritorio,
  });

  // 5. Actualizar contador en la Carpeta
  batch.update(carpetaRef, {'contador_tarjetas': siguienteNumero});

  // 6. Vincular IDs en direcciones_globales
  for (final doc in direccionesParaTarjeta) {
    batch.update(doc.reference, {
      'tarjeta_id': nombreTarjeta,
      'territorio_temporal': nombreTerritorio,
    });
  }

  // 7. Desmarcar las que no entraron por el límite del slider
  for (final doc in direccionesRestantes) {
    batch.update(doc.reference, {
      'tarjeta_id': null,
      'territorio_temporal': null,
    });
  }

  await batch.commit();
}

Future<void> enviarTarjetaTemporal({
  required String pathTarjeta,
  required String nombrePublicador,
  required String nombreUsuario,
  required String emailUsuario,
}) async {
  final ref = FirebaseFirestore.instance.doc(pathTarjeta);

  await ref.update({
    'estado': 'enviada',
    'entregado_a': nombrePublicador,
    'fecha_salida': FieldValue.serverTimestamp(),
    'enviado_por': nombreUsuario,
    'enviado_email': emailUsuario,
    'icono_estado': 'Icons.outgoing_mail', // Para que la UI cambie el icono
  });
}

Future<void> devolverTarjetaTemporal({
  required String pathTarjeta,
}) async {
  final ref = FirebaseFirestore.instance.doc(pathTarjeta);

  await ref.update({
    'estado': 'preparada',
    'entregado_a': '',
    'fecha_salida': null,
    'enviado_por': '',
    'enviado_email': '',
    'icono_estado': null,
  });
}
