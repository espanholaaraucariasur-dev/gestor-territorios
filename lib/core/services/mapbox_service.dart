import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Servicio Mapbox para geocodificación de direcciones.
/// Plan Free: 100,000 requests/mes — con 200 direcciones usamos 0.2%.
class MapboxService {
  static const String _token = AppSecrets.mapboxToken;
  static const String _baseUrl =
      'https://api.mapbox.com/search/geocode/v6/forward';
  static const String _bbox =
      '-49.45,-25.70,-49.30,-25.55';

  /// Convierte una dirección de texto en coordenadas lat/lng.
  /// Retorna [lat, lng] o null si no encontró.
  static Future<List<double>?> geocodificar(String direccion) async {
    try {
      // Agregar ciudad para mejorar precisión
      final query = Uri.encodeComponent('$direccion, Araucária, PR, Brasil');

      final url = Uri.parse(
        '$_baseUrl?q=$query&access_token=$_token&limit=1&bbox=$_bbox&country=BR&language=pt',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
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
