import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Servicio de geocodificación con Mapbox Geocoding API.
/// Valida direcciones reales, autocompleta y obtiene coordenadas.
class MapboxService {
  static const String _token = AppSecrets.mapboxToken;
  static const String _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';

  // ─── CONFIGURACIÓN ───
  static const String _country = 'br'; // Brasil
  static const String _language = 'pt'; // Portugués
  static const int _limit = 5;
  static const String _types = 'address,place,poi'; // address=calle+número, place=ciudad/barrio, poi=puntos de interés

  /// Busca una dirección en Mapbox (forward geocoding).
  /// Retorna lista de candidatos con: place_name, center [lng, lat], place_type, context (barrio, ciudad, estado).
  static Future<List<Map<String, dynamic>>> buscar(String consulta) async {
    if (consulta.trim().isEmpty) return [];

    try {
      final query = Uri.encodeComponent(consulta.trim());
      final url = Uri.parse('$_baseUrl/$query.json')
          .replace(queryParameters: {
        'access_token': _token,
        'country': _country,
        'language': _language,
        'limit': _limit.toString(),
        'types': _types,
        'autocomplete': 'true', // permite búsqueda por prefijo
      });

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List?;
        if (features == null || features.isEmpty) return [];

        return features.map((f) {
          final center = f['center'] as List?; // [lng, lat]
          final context = f['context'] as List?;
          String barrio = '';
          String ciudad = '';
          String estado = '';
          if (context != null) {
            for (final c in context) {
              final id = c['id'] as String?;
              if (id?.startsWith('neighborhood') == true) barrio = c['text'] as String? ?? '';
              if (id?.startsWith('place') == true) ciudad = c['text'] as String? ?? '';
              if (id?.startsWith('region') == true) estado = c['text'] as String? ?? '';
            }
          }
          return {
            'place_name': f['place_name'] as String? ?? '',
            'center': center, // [lng, lat]
            'place_type': (f['place_type'] as List?)?.first ?? '',
            'relevance': f['relevance'] as double? ?? 0,
            'barrio': barrio,
            'ciudad': ciudad,
            'estado': estado,
          };
        }).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Busca y valida si una dirección existe (coincidencia fuerte).
  /// Usa relevancia >= 0.8 y tipo 'address' para confirmar que es una dirección real con número.
  static Future<Map<String, dynamic>?> validarDireccion(String consulta) async {
    final resultados = await buscar(consulta);
    if (resultados.isEmpty) return null;

    // Priorizar tipo 'address' (calle + número) con alta relevancia
    for (final r in resultados) {
      final tipo = r['place_type'] as String? ?? '';
      final relevancia = r['relevance'] as double? ?? 0;
      if (tipo == 'address' && relevancia >= 0.75) {
        return r;
      }
    }

    // Fallback: primer resultado con buena relevancia
    final mejor = resultados.firstWhere(
      (r) => (r['relevance'] as double? ?? 0) >= 0.6,
      orElse: () => resultados.first,
    );
    return mejor;
  }

  /// Obtiene coordenadas [lat, lng] de una dirección.
  static Future<Map<String, double>?> obtenerCoordenadas(String consulta) async {
    final r = await validarDireccion(consulta);
    if (r == null) return null;
    final center = r['center'] as List?;
    if (center == null || center.length != 2) return null;
    return {'lat': center[1] as double, 'lng': center[0] as double};
  }

  /// Verifica conectividad con Mapbox API.
  static Future<Map<String, dynamic>> verificarConexion() async {
    try {
      final url = Uri.parse('$_baseUrl/test.json')
          .replace(queryParameters: {'access_token': _token, 'limit': '1'});
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'ok': true, 'mensaje': 'Conexión a Mapbox exitosa'};
      } else if (response.statusCode == 401) {
        return {'ok': false, 'mensaje': 'Token Mapbox inválido (401)'};
      } else {
        return {'ok': false, 'mensaje': 'Mapbox HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'ok': false, 'mensaje': 'Error: $e'};
    }
  }
}