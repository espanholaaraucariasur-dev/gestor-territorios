import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_secrets.dart';

/// Una ruta candidata entre dos puntos.
class RutaNav {
  const RutaNav({
    required this.puntos,
    required this.distanciaM,
    required this.duracionS,
    this.aproximada = false,
  });

  /// Línea recta origen→destino. Solo se usa como último recurso cuando
  /// Mapbox no responde: no sigue calles, así que no sirve para detectar
  /// salida de ruta ni para calcular tiempos reales.
  factory RutaNav.directa(
    LatLng origen,
    LatLng destino, {
    required double velocidadMs,
  }) {
    final d = NavegacionRutasService.metros(origen, destino);
    return RutaNav(
      puntos: [origen, destino],
      distanciaM: d,
      duracionS: d / velocidadMs,
      aproximada: true,
    );
  }

  final List<LatLng> puntos;
  final double distanciaM;
  final double duracionS;
  final bool aproximada;
}

/// Resultado de pedir rutas: o hay al menos una, o hay un error explicado.
class ResultadoRutas {
  const ResultadoRutas.ok(this.rutas)
      : error = null,
        limiteTasa = false;

  const ResultadoRutas.error(this.error, {this.limiteTasa = false})
      : rutas = const [];

  final List<RutaNav> rutas;
  final String? error;

  /// true si Mapbox respondió 429 (demasiadas peticiones): conviene esperar
  /// bastante antes de volver a pedir.
  final bool limiteTasa;

  bool get ok => rutas.isNotEmpty;
}

class _Intento {
  const _Intento(this.perfil, this.rumbo);
  final String perfil;
  final double? rumbo;
}

class _ErrorApi implements Exception {
  const _ErrorApi(this.mensaje);
  final String mensaje;
}

class _ErrorAuth implements Exception {
  const _ErrorAuth();
}

class _LimiteTasa implements Exception {
  const _LimiteTasa();
}

/// Pide a Mapbox la ruta del punto A al punto B, con alternativas.
///
/// Se piden SIEMPRE solo dos coordenadas (donde estoy → próxima parada):
/// - El perfil `driving-traffic` admite como máximo 3 coordenadas, así que
///   pasar toda la lista de paradas fallaba en cuanto había más de dos.
/// - Las alternativas (hasta 2 extra) están disponibles en los perfiles de
///   coche y a pie.
class NavegacionRutasService {
  const NavegacionRutasService._();

  static const String _base = 'https://api.mapbox.com/directions/v5/mapbox';
  static const Duration _tiempoMax = Duration(seconds: 8);

  /// [rumbo] (grados, opcional): si el usuario ya va en movimiento, se envía
  /// para que la ruta no arranque con un giro en U por la calle contraria.
  static Future<ResultadoRutas> obtener({
    required LatLng origen,
    required LatLng destino,
    required String perfil,
    double? rumbo,
  }) async {
    // Variantes en orden: la ideal primero y, si falla por motivos de la
    // petición (no de la red), una más simple.
    final intentos = <_Intento>[
      if (rumbo != null) _Intento(perfil, rumbo),
      _Intento(perfil, null),
      if (perfil == 'driving-traffic') const _Intento('driving', null),
    ];

    var ultimoError = 'Mapbox no encontró ruta';
    for (final intento in intentos) {
      try {
        final rutas = await _pedir(origen, destino, intento);
        if (rutas.isNotEmpty) return ResultadoRutas.ok(rutas);
        ultimoError = 'Mapbox no encontró ruta';
      } on _ErrorAuth {
        return const ResultadoRutas.error(
            'Token de Mapbox inválido o sin permisos');
      } on _LimiteTasa {
        return const ResultadoRutas.error(
          'Límite de peticiones de Mapbox alcanzado',
          limiteTasa: true,
        );
      } on _ErrorApi catch (e) {
        ultimoError = e.mensaje; // se prueba la siguiente variante
      } on TimeoutException {
        return const ResultadoRutas.error('Mapbox tardó demasiado en responder');
      } catch (_) {
        // Sin red: probar más variantes seguidas no sirve de nada.
        return const ResultadoRutas.error('Sin conexión con Mapbox');
      }
    }
    return ResultadoRutas.error(ultimoError);
  }

  static Future<List<RutaNav>> _pedir(
    LatLng origen,
    LatLng destino,
    _Intento intento,
  ) async {
    final coords = '${origen.longitude},${origen.latitude};'
        '${destino.longitude},${destino.latitude}';

    final params = StringBuffer()
      ..write('alternatives=true')
      ..write('&geometries=geojson')
      ..write('&overview=full')
      ..write('&steps=false');
    if (intento.rumbo != null) {
      final r = ((intento.rumbo! % 360) + 360) % 360;
      // "grados,tolerancia" para el origen; el destino queda libre (vacío).
      params.write('&bearings=${r.round()},45;');
    }
    params.write('&access_token=${AppSecrets.mapboxToken}');

    final url = Uri.parse('$_base/${intento.perfil}/$coords?$params');
    final resp = await http.get(url).timeout(_tiempoMax);

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const _ErrorAuth();
    }
    if (resp.statusCode == 429) throw const _LimiteTasa();

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }

    if (resp.statusCode != 200) {
      throw _ErrorApi(
          data?['message']?.toString() ?? 'Error HTTP ${resp.statusCode}');
    }
    if (data == null || data['code'] != 'Ok') {
      throw _ErrorApi(data?['message']?.toString() ?? 'Respuesta inválida');
    }

    final rutasJson = (data['routes'] as List?) ?? const [];
    final resultado = <RutaNav>[];
    for (final r in rutasJson.take(3)) {
      final coordsJson = (r['geometry'] as Map)['coordinates'] as List;
      final puntos = <LatLng>[
        for (final c in coordsJson)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (puntos.length < 2) continue;
      resultado.add(RutaNav(
        puntos: puntos,
        distanciaM: (r['distance'] as num).toDouble(),
        duracionS: (r['duration'] as num).toDouble(),
      ));
    }
    return resultado;
  }

  /// Distancia en metros entre dos puntos (haversine).
  static double metros(LatLng a, LatLng b) {
    const radioTierra = 6371000.0;
    double rad(double g) => g * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLng = rad(b.longitude - a.longitude);
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 +
        math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * s2 * s2;
    return 2 * radioTierra * math.asin(math.min(1.0, math.sqrt(h)));
  }
}

/// Dónde está el usuario sobre una ruta.
class ProyeccionRuta {
  const ProyeccionRuta({
    required this.indice,
    required this.punto,
    required this.distanciaM,
    required this.recorridoM,
  });

  /// El usuario está sobre el tramo puntos[indice] → puntos[indice + 1].
  final int indice;

  /// Punto de la ruta más cercano al usuario.
  final LatLng punto;

  /// Distancia (perpendicular) entre el usuario y la ruta. Si es grande, se
  /// salió de la ruta.
  final double distanciaM;

  /// Metros de ruta ya recorridos desde su inicio hasta [punto].
  final double recorridoM;
}

/// Geometría de una ruta con distancias acumuladas, para proyectar la
/// posición GPS sobre ella.
class GeometriaRuta {
  GeometriaRuta(this.puntos) : acumulada = _acumular(puntos);

  final List<LatLng> puntos;

  /// acumulada[i] = metros desde puntos[0] hasta puntos[i].
  final List<double> acumulada;

  double get largoM => acumulada.isEmpty ? 0 : acumulada.last;

  static List<double> _acumular(List<LatLng> p) {
    final r = List<double>.filled(p.length, 0);
    for (var i = 1; i < p.length; i++) {
      r[i] = r[i - 1] + NavegacionRutasService.metros(p[i - 1], p[i]);
    }
    return r;
  }

  /// Parte de la ruta que falta: desde el punto proyectado hasta el final.
  List<LatLng> restante(ProyeccionRuta p) {
    if (p.indice + 1 >= puntos.length) return [p.punto];
    return [p.punto, ...puntos.sublist(p.indice + 1)];
  }

  /// Proyecta [pos] sobre la ruta.
  ///
  /// Con [ventana] solo se miran esos tramos a partir de [desdeIndice]: es
  /// más rápido y evita saltar a otra parte de la ruta que pase cerca (por
  /// ejemplo, una ruta que cruza sobre sí misma). Sin [ventana] se busca en
  /// toda la ruta.
  ProyeccionRuta? proyectar(LatLng pos, {int desdeIndice = 0, int? ventana}) {
    if (puntos.length < 2) return null;

    final ultimo = puntos.length - 2;
    final ini = math.max(0, math.min(desdeIndice, ultimo));
    final fin = ventana == null ? ultimo : math.min(ultimo, ini + ventana);

    // Plano local en metros centrado en la posición del usuario.
    final kx = 111320.0 * math.cos(pos.latitude * math.pi / 180);
    const ky = 110574.0;

    var mejorD = double.infinity;
    var mejorI = ini;
    var mejorT = 0.0;

    for (var i = ini; i <= fin; i++) {
      final ax = (puntos[i].longitude - pos.longitude) * kx;
      final ay = (puntos[i].latitude - pos.latitude) * ky;
      final bx = (puntos[i + 1].longitude - pos.longitude) * kx;
      final by = (puntos[i + 1].latitude - pos.latitude) * ky;
      final dx = bx - ax;
      final dy = by - ay;
      final largo2 = dx * dx + dy * dy;

      var t = 0.0;
      if (largo2 > 0) {
        t = (-ax * dx - ay * dy) / largo2;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
      }
      final px = ax + t * dx;
      final py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < mejorD) {
        mejorD = d;
        mejorI = i;
        mejorT = t;
      }
    }

    final a = puntos[mejorI];
    final b = puntos[mejorI + 1];
    final punto = LatLng(
      a.latitude + (b.latitude - a.latitude) * mejorT,
      a.longitude + (b.longitude - a.longitude) * mejorT,
    );
    final largoTramo = acumulada[mejorI + 1] - acumulada[mejorI];
    return ProyeccionRuta(
      indice: mejorI,
      punto: punto,
      distanciaM: mejorD,
      recorridoM: acumulada[mejorI] + largoTramo * mejorT,
    );
  }
}
