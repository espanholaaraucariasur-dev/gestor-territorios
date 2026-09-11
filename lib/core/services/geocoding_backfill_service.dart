import 'package:cloud_firestore/cloud_firestore.dart';
import 'groq_territory_service.dart';
import 'mapbox_geocoding_service.dart';

/// Resultado agregado de una corrida de backfill de coordenadas.
class BackfillResultado {
  final int total;
  final int actualizadas;
  final int fallidas;
  final List<Map<String, dynamic>> errores;

  BackfillResultado({
    required this.total,
    required this.actualizadas,
    required this.fallidas,
    required this.errores,
  });

  bool get sinPendientes => total == 0;
}

/// Orquesta el backfill de coordenadas para `direcciones_globales` que aún
/// no tienen lat/lng.
///
/// Flujo (Groq dirige, Mapbox ejecuta):
///  1. Firestore: trae las direcciones sin coordenadas.
///  2. Groq: normaliza el texto (completa ciudad/estado, corrige
///     abreviaturas) y decide el orden de envío agrupando por barrio.
///  3. Mapbox: geocodifica cada dirección ya normalizada -> lat/lng/CEP.
///  4. Firestore: guarda lat/lng (uso interno del sistema) y CEP (visible,
///     útil para que Google Maps sea más exacto al momento de armar la ruta).
class GeocodingBackfillService {
  static const String _coleccion = 'direcciones_globales';

  /// Geocodificaciones a Mapbox en paralelo por micro-lote. Mapbox free
  /// tier soporta ~600 req/min; 5 en paralelo con backoff en 429 es un
  /// margen seguro.
  static const int _concurrenciaMapbox = 5;

  /// Ejecuta el backfill completo.
  ///
  /// [onProgreso] se invoca después de cada dirección procesada con
  /// (procesadas, total, actualizadas, fallidas), para que la UI pueda
  /// mostrar una barra de progreso en vivo.
  static Future<BackfillResultado> ejecutarBackfillCoordenadas({
    void Function(int procesadas, int total, int actualizadas, int fallidas)?
        onProgreso,
  }) async {
    final firestore = FirebaseFirestore.instance;

    // 1. Traer todas las direcciones y filtrar localmente las que no tienen
    // lat/lng (evita depender de que el campo exista para poder filtrarlo
    // por query, ya que documentos viejos pueden no tenerlo en absoluto).
    final snapshot = await firestore.collection(_coleccion).get();
    final docsSinCoordenadas = snapshot.docs.where((doc) {
      final data = doc.data();
      return data['lat'] == null || data['lng'] == null;
    }).toList();

    final total = docsSinCoordenadas.length;
    if (total == 0) {
      return BackfillResultado(
          total: 0, actualizadas: 0, fallidas: 0, errores: []);
    }

    int procesadas = 0;
    int actualizadas = 0;
    int fallidas = 0;
    final List<Map<String, dynamic>> errores = [];

    void reportar() =>
        onProgreso?.call(procesadas, total, actualizadas, fallidas);

    // 2. Procesar en lotes según el límite de Groq para normalización.
    final tamLote = GroqTerritoryService.maxDireccionesPorLoteGeocoding;

    for (int i = 0; i < docsSinCoordenadas.length; i += tamLote) {
      final finLote = (i + tamLote > docsSinCoordenadas.length)
          ? docsSinCoordenadas.length
          : i + tamLote;
      final lote = docsSinCoordenadas.sublist(i, finLote);

      final crudas = lote
          .map((doc) => {
                'id': doc.id,
                'calle': doc.data()['calle'] ?? doc.data()['direccion'] ?? '',
                'numero': doc.data()['numero'] ?? '',
                'complemento': doc.data()['complemento'] ?? '',
                'barrio': doc.data()['barrio'] ?? '',
              })
          .toList();

      List<Map<String, dynamic>> normalizadas;
      try {
        normalizadas = await GroqTerritoryService
            .normalizarDireccionesParaGeocoding(crudas);
      } catch (e) {
        // Si Groq falla para todo el lote, lo marcamos y seguimos con el
        // siguiente lote en vez de abortar todo el proceso.
        fallidas += lote.length;
        procesadas += lote.length;
        errores.add({'lote_desde': i, 'error': 'Groq: $e'});
        reportar();
        continue;
      }

      // Respetar el orden sugerido por Groq (agrupado por barrio/cercanía).
      normalizadas.sort((a, b) =>
          ((a['orden'] as num?) ?? 0).compareTo((b['orden'] as num?) ?? 0));

      // 3. Geocodificar con concurrencia limitada.
      for (int j = 0; j < normalizadas.length; j += _concurrenciaMapbox) {
        final finGrupo = (j + _concurrenciaMapbox > normalizadas.length)
            ? normalizadas.length
            : j + _concurrenciaMapbox;
        final grupo = normalizadas.sublist(j, finGrupo);

        await Future.wait(grupo.map((item) async {
          final id = item['id']?.toString() ?? '';
          final direccionNormalizada =
              item['direccion_normalizada']?.toString() ?? '';

          if (id.isEmpty || direccionNormalizada.isEmpty) {
            fallidas++;
            procesadas++;
            errores.add({'id': id, 'error': 'Dirección normalizada vacía'});
            reportar();
            return;
          }

          try {
            final geo = await _geocodificarConReintento(direccionNormalizada);
            procesadas++;

            if (geo == null) {
              fallidas++;
              errores.add({
                'id': id,
                'direccion': direccionNormalizada,
                'error': 'Mapbox no encontró coincidencias',
              });
              reportar();
              return;
            }

            // 4. Guardar: lat/lng para uso interno del sistema (rutas,
            // distancias), CEP visible/útil para Google Maps.
            await firestore.collection(_coleccion).doc(id).update({
              'lat': geo['lat'],
              'lng': geo['lng'],
              'cep': geo['cep'],
              'direccionNormalizada': direccionNormalizada,
              'geocodingConfianza': item['confianza'] ?? '',
              'geocodedAt': FieldValue.serverTimestamp(),
              'geocodingSource': 'groq+mapbox',
            });

            actualizadas++;
            reportar();
          } catch (e) {
            fallidas++;
            procesadas++;
            errores.add({'id': id, 'error': e.toString()});
            reportar();
          }
        }));
      }
    }

    return BackfillResultado(
      total: total,
      actualizadas: actualizadas,
      fallidas: fallidas,
      errores: errores,
    );
  }

  /// Reintenta una vez con backoff si Mapbox responde 429 (rate limit).
  /// Si el segundo intento también choca con el límite, se deja para una
  /// próxima corrida del backfill (no bloquea el resto del lote).
  static Future<Map<String, dynamic>?> _geocodificarConReintento(
    String direccion,
  ) async {
    try {
      return await MapboxGeocodingService.geocodificarDireccion(direccion);
    } on MapboxRateLimitException {
      await Future.delayed(const Duration(seconds: 2));
      try {
        return await MapboxGeocodingService.geocodificarDireccion(direccion);
      } on MapboxRateLimitException {
        return null;
      }
    }
  }
}
