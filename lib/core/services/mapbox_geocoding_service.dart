import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Excepción específica para 429 (rate limit) de Mapbox, para que la capa
/// orquestadora pueda reintentar con backoff sin confundirlo con un error
/// real de geocodificación.
class MapboxRateLimitException implements Exception {
  @override
  String toString() => 'Mapbox: límite de tasa (429) alcanzado';
}

/// Servicio de geocodificación de UNA dirección de texto -> coordenadas.
///
/// A diferencia de [MapboxPoiService] (que busca lugares por categoría),
/// este servicio resuelve una dirección puntual (calle + número + barrio)
/// a lat/lng, y cuando Mapbox lo provee, al código postal (CEP).
///
/// El bounding box de Araucária, PR limita los resultados a la región de
/// operación de la congregación, evitando que Mapbox resuelva una calle
/// con nombre homónimo en otra ciudad lejana (causa raíz de las rutas de
/// cientos de km ya vistas).
class MapboxGeocodingService {
  static const String _token = AppSecrets.mapboxToken;
  static const String _baseUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// min_lng, min_lat, max_lng, max_lat — Araucária, PR.
  static const List<double> _bboxAraucaria = [
    -49.476,
    -25.640,
    -49.150,
    -25.460,
  ];

  /// Geocodifica una única dirección de texto ya normalizada (idealmente
  /// pasada por [GroqTerritoryService.normalizarDireccionesParaGeocoding]
  /// antes de llegar acá, para incluir ciudad/estado y corregir abreviaturas).
  ///
  /// Retorna null si Mapbox no encuentra coincidencias.
  /// Lanza [MapboxRateLimitException] en 429 para que el llamador reintente.
  static Future<Map<String, dynamic>?> geocodificarDireccion(
    String direccionTexto,
  ) async {
    final texto = direccionTexto.trim();
    if (texto.isEmpty) return null;

    final query = Uri.encodeComponent(texto);
    final bboxParam =
        _bboxAraucaria.map((v) => v.toStringAsFixed(6)).join(',');

    final url = Uri.parse(
      '$_baseUrl/$query.json'
      '?access_token=$_token'
      '&country=BR'
      '&language=pt'
      '&limit=1'
      '&types=address,poi'
      '&bbox=$bboxParam',
    );

    final response =
        await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode == 429) {
      throw MapboxRateLimitException();
    }

    if (response.statusCode != 200) {
      print(
          '⚠️ Mapbox geocoding status ${response.statusCode}: ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List?) ?? [];
    if (features.isEmpty) return null;

    final f = features.first as Map<String, dynamic>;
    final geometry =
        (f['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
    if (geometry == null || geometry.length < 2) return null;

    final lng = (geometry[0] as num).toDouble();
    final lat = (geometry[1] as num).toDouble();

    // El CEP viene en "context" como { id: "postcode.xxxx", text: "83700-000" }.
    String? cep;
    final context = (f['context'] as List?) ?? [];
    for (final c in context.cast<Map<String, dynamic>>()) {
      final id = (c['id'] as String?) ?? '';
      if (id.startsWith('postcode')) {
        cep = c['text'] as String?;
        break;
      }
    }

    return {
      'lat': lat,
      'lng': lng,
      'cep': cep ?? '',
      'placeName': (f['place_name'] as String?) ?? '',
      'relevancia': (f['relevance'] as num?)?.toDouble() ?? 0.0,
    };
  }
}
