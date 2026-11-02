import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Servicio Mapbox para geocodificación de direcciones.
/// Plan Free: 100,000 requests/mes — con 200 direcciones usamos 0.2%.
class MapboxService {
  static const String _token = AppSecrets.mapboxToken;
  static const String _baseUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// Valida que una dirección sea REAL antes de guardarla.
  ///
  /// Mapbox devuelve coordenadas incluso para texto inventado (p. ej.
  /// "Rua Teste 20") cayendo al nivel de ciudad/región. Este método exige:
  /// - al menos una feature a nivel de dirección/POI (no solo ciudad/región)
  /// - relevancia alta (relevance >= 0.5)
  /// - que el componente de calle del texto aparezca en el nombre devuelto
  /// - coordenadas dentro de la caja de la región de Araucária
  ///
  /// Retorna un mapa con `ok` (bool), `lat`, `lng`, `lugar` (nombre devuelto)
  /// y `motivo` (si ok es false, explica por qué se rechazó).
  static Future<Map<String, dynamic>> validarDireccion(String direccion) async {
    try {
      final consulta = direccion.trim();
      if (consulta.isEmpty) {
        return {
          'ok': false,
          'motivo': 'Dirección vacía.',
          'lat': null,
          'lng': null,
          'lugar': '',
        };
      }
      // Solo la inspección de Mapbox sin forzar la ciudad; así validamos la
      // calle real en cualquier parte, pero luego exigimos estar dentro de
      // la región esperada.
      final query = Uri.encodeComponent(consulta);
      final url = Uri.parse(
        '$_baseUrl/$query.json?access_token=$_token&country=BR&language=pt'
        '&limit=1',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return {
          'ok': false,
          'motivo': 'Mapbox no respondió (${response.statusCode}).',
          'lat': null,
          'lng': null,
          'lugar': '',
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = (data['features'] as List? ?? []);
      if (features.isEmpty) {
        return {
          'ok': false,
          'motivo': 'Mapbox no encontró esa dirección.',
          'lat': null,
          'lng': null,
          'lugar': '',
        };
      }

      final first = features.first as Map<String, dynamic>;
      final placeTypes = (first['place_type'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      final relevance = (first['relevance'] as num?)?.toDouble() ?? 0;
      final placeName = (first['place_name'] as String? ?? '')
          .toString()
          .toLowerCase();

      // Coordenadas: [lng, lat]
      double? lat;
      double? lng;
      final geometry = first['geometry'] as Map<String, dynamic>?;
      if (geometry != null && geometry['coordinates'] is List) {
        final coords = geometry['coordinates'] as List;
        if (coords.length >= 2) {
          lng = (coords[0] as num).toDouble();
          lat = (coords[1] as num).toDouble();
        }
      }

      // 1) Nivel de precisión: dirección/POI real.
      final esNivelDireccion = placeTypes.contains('address') ||
          placeTypes.contains('poi');
      if (!esNivelDireccion) {
        return {
          'ok': false,
          'motivo':
              'Mapbox no ubicó una dirección real (nivel: ${placeTypes.join(',')} y la ingresada puede ser inventada).',
          'lat': lat,
          'lng': lng,
          'lugar': placeName,
        };
      }

      // 2) Relevancia mínima.
      if (relevance < 0.5) {
        return {
          'ok': false,
          'motivo': 'Coincidencia de Mapbox muy baja (relevance $relevance).',
          'lat': lat,
          'lng': lng,
          'lugar': placeName,
        };
      }

      // 3) El componente de calle del texto debe coincidir con el resultado.
      final calleNormalizada = _extraerCalle(consulta)
          .replaceAll(RegExp(r'[^a-zà-ú0-9\s]'), ' ')
          .toLowerCase();
      if (calleNormalizada.isNotEmpty) {
        final toks = calleNormalizada
            .split(RegExp(r'\s+'))
            .where((t) => t.length > 2)
            .toSet();
        final coincidencias = toks.where(placeName.contains).length;
        if (toks.isNotEmpty && coincidencias == 0) {
          return {
            'ok': false,
            'motivo': 'El nombre devuelto ($placeName) no coincide con la calle ingresada.',
            'lat': lat,
            'lng': lng,
            'lugar': placeName,
          };
        }
      }

      // 4) Dentro de la región esperada (Araucária y alrededores).
      if (lat != null && lng != null) {
        if (lng < -49.6 || lng > -49.2 || lat < -25.8 || lat > -25.4) {
          return {
            'ok': false,
            'motivo': 'Dirección fuera de la zona de la congregación.',
            'lat': lat,
            'lng': lng,
            'lugar': placeName,
          };
        }
      }

      return {
        'ok': true,
        'lat': lat,
        'lng': lng,
        'lugar': placeName,
        'relevance': relevance,
      };
    } catch (e) {
      return {
        'ok': false,
        'motivo': 'Error validando con Mapbox: $e',
        'lat': null,
        'lng': null,
        'lugar': '',
      };
    }
  }

  /// Extrae la parte de "calle" (descarta número y complementos) para
  /// compararla con el lugar devuelto por Mapbox.
  static String _extraerCalle(String direccion) {
    // Quitar el número inicial tras la calle (p. ej. "Rua X 123")
    final sinNumero =
        direccion.replaceFirst(RegExp(r'\b\d+\b'), '').trim();
    if (sinNumero.isEmpty) return direccion;
    return sinNumero;
  }

  /// Convierte una dirección de texto en coordenadas lat/lng.
  /// Retorna [lat, lng] o null si no encontró.
  static Future<List<double>?> geocodificar(String direccion) async {
    try {
      // Agregar ciudad para mejorar precisión
      final query = Uri.encodeComponent('$direccion, Araucária, PR, Brasil');

      final url = Uri.parse(
        '$_baseUrl/$query.json?access_token=$_token&country=BR&language=pt',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List?;

        if (features is List && features.isNotEmpty) {
          final coords = features.first['geometry']['coordinates'] as List;
          // Mapbox retorna [lng, lat] — invertimos a [lat, lng]
          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          return [lat, lng];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Geocodifica múltiples direcciones en paralelo.
  /// Retorna mapa de direccionId → [lat, lng]
  static Future<Map<String, List<double>>> geocodificarMultiples(
      Map<String, String> direcciones) async {
    final resultados = <String, List<double>>{};

    // Procesar en lotes de 5 para no saturar la API
    final entries = direcciones.entries.toList();
    for (int i = 0; i < entries.length; i += 5) {
      final lote = entries.sublist(
          i, i + 5 > entries.length ? entries.length : i + 5);

      final futures = lote.map((entry) async {
        final coords = await geocodificar(entry.value);
        if (coords != null) {
          resultados[entry.key] = coords;
        }
      });

      await Future.wait(futures);

      // Pequeña pausa entre lotes para respetar rate limits
      if (i + 5 < entries.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    return resultados;
  }
}