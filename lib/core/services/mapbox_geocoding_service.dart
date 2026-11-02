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
    // El barrio viene igual, con { id: "neighborhood.xxxx", text: "..." }.
    // Estos dos son la única fuente de verdad real para barrio+CEP: Groq no
    // puede saber el barrio real de una dirección (solo repite lo que se le
    // haya dado como dato) y nunca tiene el CEP.
    String? cep;
    String? barrio;
    final context = (f['context'] as List?) ?? [];
    for (final c in context.cast<Map<String, dynamic>>()) {
      final id = (c['id'] as String?) ?? '';
      if (id.startsWith('postcode')) {
        cep = c['text'] as String?;
      } else if (id.startsWith('neighborhood')) {
        barrio = c['text'] as String?;
      }
    }

    return {
      'lat': lat,
      'lng': lng,
      'cep': cep ?? '',
      'barrio': barrio ?? '',
      'placeName': (f['place_name'] as String?) ?? '',
      'relevancia': (f['relevance'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Ensambla el texto final de una dirección combinando el texto base
  /// (ya corregido/normalizado por Groq o tipeado por el usuario) con el
  /// barrio y CEP reales devueltos por Mapbox al geocodificar. Solo agrega
  /// lo que falte — no duplica si el texto ya lo incluye.
  ///
  /// Pensado como punto único de ensamblado para que todos los caminos de
  /// entrada de direcciones (publicador, admin manual, auto-asignador IA,
  /// asignación manual del auditor) arme el texto final de la misma forma.
  static String ensamblarDireccionFinal(
    String texto,
    Map<String, dynamic>? geo,
  ) {
    if (geo == null) return texto.replaceAll(RegExp(r'\s+'), ' ').trim();

    final barrio = (geo['barrio'] as String?)?.trim() ?? '';
    final cep = (geo['cep'] as String?)?.trim() ?? '';

    // 1. Quedarnos solo con "calle + número", descartando ciudad/estado, país,
    // CEP y barrio si el texto ya los traía, para no duplicar al reensamblar.
    var base = texto.trim();
    final idxCiudad = base.toLowerCase().indexOf('arauc');
    if (idxCiudad != -1) {
      base = base.substring(0, idxCiudad);
    }
    base = base
        .replaceAll(RegExp(r'[,;]?\s*brasil\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[,\-]+\s*$'), '')
        .trim();
    if (cep.isNotEmpty) {
      base = base
          .replaceAll(RegExp(r'[,\s]*' + RegExp.escape(cep) + r'\s*$'), '')
          .trim();
    }
    if (barrio.isNotEmpty) {
      base = base
          .replaceAll(
              RegExp(r'[,\-]?\s*' + RegExp.escape(barrio) + r'\s*$',
                  caseSensitive: false),
              '')
          .replaceAll(RegExp(r'[,\-]+\s*$'), '')
          .trim();
    }

    // 2. Separar calle y número (el número puede venir con o sin coma:
    // "Rua X, 101" o "Rua X 101") y descartar un barrio suelto si el texto
    // crudo ya lo traía (ej. "Rua X 854, Iguaçu" -> queda "Rua X, 854").
    final segs =
        base.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    while (segs.length > 1 && !RegExp(r'\d').hasMatch(segs.last)) {
      segs.removeLast();
    }
    var numero = '';
    if (segs.isNotEmpty) {
      final ultimo = segs.last;
      final mNum =
          RegExp(r'^(.*?\S)\s+(\d{1,6}\s*[A-Za-z]?)$').firstMatch(ultimo);
      if (mNum != null) {
        numero = mNum.group(2)!.trim();
        segs[segs.length - 1] = mNum.group(1)!.trim();
      } else if (RegExp(r'^\d{1,6}\s*[A-Za-z]?$').hasMatch(ultimo)) {
        numero = ultimo;
        segs.removeLast();
      }
    }

    // 3. Formato canónico: Calle, número - Barrio, Araucária - PR, CEP, Brasil.
    final buffer = StringBuffer(_titulo(segs.join(', ')));
    if (numero.isNotEmpty) buffer.write(', $numero');
    if (barrio.isNotEmpty) buffer.write(' - ${_titulo(barrio)}');
    buffer.write(', Araucária - PR');
    if (cep.isNotEmpty) buffer.write(', $cep');
    buffer.write(', Brasil');

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Pone en Mayúscula La Primera Letra De Cada Palabra.
  static String _titulo(String s) => s
      .split(' ')
      .where((p) => p.trim().isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}
