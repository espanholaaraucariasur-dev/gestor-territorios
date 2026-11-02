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

  /// Versión del formato de `calle` que produce [ensamblarDireccionFinal].
  /// Se guarda en el doc ('calleFormato') para poder reprocesar UNA sola vez
  /// las direcciones viejas cuando el formato cambia, sin quedar en loop.
  static const int _versionFormatoCalle = 2;

  /// Ejecuta el backfill completo.
  ///
  /// [coleccion] permite reutilizar la misma lógica tanto para direcciones
  /// ya confirmadas ('direcciones_globales', default) como para la bandeja
  /// de sugerencias pendientes ('sugerencias') — mismo motor, mismo
  /// batching, mismo reintento con partición.
  ///
  /// [onProgreso] se invoca después de cada dirección procesada con
  /// (procesadas, total, actualizadas, fallidas), para que la UI pueda
  /// mostrar una barra de progreso en vivo.
  static Future<BackfillResultado> ejecutarBackfillCoordenadas({
    String coleccion = _coleccion,
    void Function(int procesadas, int total, int actualizadas, int fallidas)?
        onProgreso,
    // Cuando es true (bandeja "Nuevas Direcciones"), una sugerencia que ya
    // tiene coords, texto normalizado y CEP igual se reprocesa si el CEP no
    // quedó pegado en la dirección visible ('calle'), para que se muestre.
    bool reprocesarSinCepVisible = false,
  }) async {
    final firestore = FirebaseFirestore.instance;

    // 1. Traer todos los documentos y filtrar localmente los que necesitan
    // procesarse. IMPORTANTE: se chequean TRES señales independientes, no
    // solo lat/lng. Una dirección puede tener coordenadas de otro camino
    // (ej. la validación de Mapbox del auto-asignador) sin haber pasado
    // nunca por Groq para limpiar el texto — si solo miráramos lat/lng,
    // quedaría marcada como "ya lista" para siempre con el texto crudo.
    // Y puede tener coords+texto pero sin CEP (o con el CEP sin pegar en la
    // dirección), que es justo lo que el auditor espera completar al
    // "Normalizar bandeja".
    final snapshot = await firestore.collection(coleccion).get();
    final docsSinCoordenadas = snapshot.docs.where((doc) {
      final data = doc.data();
      final sinCoords = data['lat'] == null || data['lng'] == null;
      final sinNormalizar = (data['direccionNormalizada'] ?? '').toString().isEmpty;
      final cep = (data['cep'] ?? '').toString().trim();
      final cepPendiente = reprocesarSinCepVisible &&
          (cep.isEmpty ||
              !(data['calle'] ?? '').toString().contains(cep));
      final formatoViejo = reprocesarSinCepVisible &&
          (((data['calleFormato'] as num?)?.toInt()) ?? 0) <
              _versionFormatoCalle;
      return sinCoords || sinNormalizar || cepPendiente || formatoViejo;
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
                'calle': doc.data()['calle'] ??
                    doc.data()['direccion'] ??
                    doc.data()['texto_direccion'] ??
                    '',
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

            // 4. Guardar: 'calle' con el texto normalizado + barrio y CEP
            // reales de Mapbox ensamblados (para que el CEP se vea en la
            // dirección en todas partes, no solo en el diálogo que lo generó),
            // lat/lng para uso interno del sistema, CEP y barrio en campos
            // propios para poder filtrarlos/buscarlos.
            final calleFinal = MapboxGeocodingService.ensamblarDireccionFinal(
              direccionNormalizada,
              geo,
            );
            final barrioGeo = (geo['barrio'] as String?)?.trim() ?? '';
            await firestore.collection(coleccion).doc(id).update({
              'calle': calleFinal,
              'lat': geo['lat'],
              'lng': geo['lng'],
              'cep': geo['cep'],
              'direccionNormalizada': direccionNormalizada,
              if (barrioGeo.isNotEmpty) 'barrio': barrioGeo,
              'geocodingConfianza': item['confianza'] ?? '',
              'geocodedAt': FieldValue.serverTimestamp(),
              'geocodingSource': 'groq+mapbox',
              'calleFormato': _versionFormatoCalle,
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

  /// Punto de entrada ÚNICO para normalizar y geocodificar UNA dirección
  /// recién llegada, sin importar de dónde venga (admin, WhatsApp,
  /// auto-asignación, asignación manual del auditor). Groq limpia/completa
  /// el texto (agrega ciudad/estado, corrige abreviaturas) y Mapbox la
  /// geocodifica. Todos los caminos de ingreso deben llamar a este método
  /// ANTES de guardar la dirección por primera vez, en vez de mostrarla
  /// cruda y normalizarla recién cuando alguien la abre.
  ///
  /// Retorna null si Groq o Mapbox fallan (sin conexión, error de API,
  /// etc.) — en ese caso el llamador debe guardar el texto original tal
  /// cual, sin bloquear el flujo por un problema de red puntual.
  ///
  /// [direccionCruda] debe tener al menos "calle" (o "direccion"); "numero",
  /// "complemento" y "barrio" son opcionales.
  static Future<Map<String, dynamic>?> normalizarYGeocodificarUna(
    Map<String, dynamic> direccionCruda,
  ) async {
    try {
      final normalizadas =
          await GroqTerritoryService.normalizarDireccionesParaGeocoding([
        {
          'id': 'temp',
          'calle': direccionCruda['calle'] ?? direccionCruda['direccion'] ?? '',
          'numero': direccionCruda['numero'] ?? '',
          'complemento': direccionCruda['complemento'] ?? '',
          'barrio': direccionCruda['barrio'] ?? '',
        }
      ]);
      final direccionNormalizada = normalizadas.isNotEmpty
          ? (normalizadas.first['direccion_normalizada']?.toString() ?? '')
          : '';
      if (direccionNormalizada.isEmpty) return null;

      final geo = await _geocodificarConReintento(direccionNormalizada);
      if (geo == null) {
        // Mapbox no encontró coincidencias, pero el texto sí se normalizó:
        // vale la pena devolver al menos la calle limpia sin coordenadas.
        return {
          'calle': direccionNormalizada,
          'direccionNormalizada': direccionNormalizada,
          'cep': '',
          'lat': null,
          'lng': null,
        };
      }

      return {
        'calle': direccionNormalizada,
        'direccionNormalizada': direccionNormalizada,
        'cep': geo['cep'] ?? '',
        'lat': geo['lat'],
        'lng': geo['lng'],
      };
    } catch (_) {
      return null;
    }
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
