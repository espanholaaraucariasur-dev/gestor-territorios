import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Servicio de descubrimiento de puntos de interés (POI) usando Mapbox.
/// Busca lugares por categoría dentro de un bounding box regional y devuelve
/// los resultados con coordenadas para cruzar contra las direcciones
/// existentes en Firestore.
class MapboxPoiService {
  static const String _token = AppSecrets.mapboxToken;
  static const String _baseUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// Bounding box por defecto para Araucária Sur (min_lng, min_lat, max_lng, max_lat).
  /// Ajustable si el proyecto define regiones concretas.
  static const Map<String, List<double>> _regiones = {
    'araucaria': [-49.476, -25.640, -49.150, -25.460], // Araucária, PR
    'araucaria_sur': [-49.476, -25.640, -49.150, -25.460],
  };

  static const List<double> _bboxDefault = [-49.476, -25.640, -49.150, -25.460];

  /// Busca lugares por categoría (ej. 'farmacia', 'mercado', 'oficina mecanica')
  /// dentro de la región indicada.
  ///
  /// [region] acepta nombres conocidos ('araucaria', 'araucaria_sur') o un
  /// bounding box 'min_lng,min_lat,max_lng,max_lat'.
  ///
  /// Retorna una lista de mapas: { nombre, direccion, lat, lng, categoria }.
  static Future<List<Map<String, dynamic>>> buscarLugaresPorCategoria({
    required String categoria,
    required String region,
  }) async {
    final List<double> bbox = _resolverBBox(region);
    final List<Map<String, dynamic>> resultado = [];

    // Construir la búsqueda agregando la región al término
    final termino = '$categoria, Araucária, PR, Brasil';
    final query = Uri.encodeComponent(termino);

    final bboxParam =
        bbox.map((v) => v.toStringAsFixed(6)).join(',');
    final url = Uri.parse(
      '$_baseUrl/$query.json'
      '?access_token=$_token'
      '&country=BR'
      '&language=pt'
      '&limit=20'
      '&bbox=$bboxParam',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        for (final f in features.cast<Map<String, dynamic>>()) {
          final geometry = (f['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
          if (geometry == null || geometry.length < 2) continue;

          final nombre = (f['text'] as String?) ?? (f['place_name'] as String?) ?? '';
          if (nombre.isEmpty) continue;

          final lng = (geometry[0] as num).toDouble();
          final lat = (geometry[1] as num).toDouble();

          resultado.add({
            'nombre': nombre,
            'direccion': (f['place_name'] as String?) ?? '',
            'lat': lat,
            'lng': lng,
            'categoria': categoria,
          });
        }
      } else {
        print('⚠️ Mapbox POI status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en Mapbox POI: $e');
    }

    return resultado;
  }

  static List<double> _resolverBBox(String region) {
    final key = region.toLowerCase().trim();
    if (_regiones.containsKey(key)) return _regiones[key]!;
    // Si es un bbox literal 'min_lng,min_lat,max_lng,max_lat'
    final partes = region.split(',');
    if (partes.length == 4) {
      final vals = partes.map(double.tryParse).toList();
      if (vals.every((v) => v != null)) return vals.cast<double>();
    }
    return _bboxDefault;
  }
}