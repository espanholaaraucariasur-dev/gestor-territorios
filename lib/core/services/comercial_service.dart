import 'dart:math';

/// Grupo resultante con metadatos de geometría para mostrar en la vista.
class Zona {
  final List<Map<String, dynamic>> direcciones;
  final double latCentro;
  final double lngCentro;
  final double radioKm;
  final double distanciaMediaMetros;

  Zona({
    required this.direcciones,
    required this.latCentro,
    required this.lngCentro,
    required this.radioKm,
    required this.distanciaMediaMetros,
  });
}

/// Motor de agrupación de direcciones comerciales en ZONAS por cercanía real.
///
/// Cada zona se arma con la dirección semilla más aislada y sus vecinas más
/// cercanas por distancia Haversine, mezclando categorías (farmacias, mercados,
/// mecánicas, escuelas…) para que una sola tarjeta cubra un recorrido compacto.
class ComercialService {

  /// Distancia en metros (Haversine) entre dos coordenadas.
  double distanciaMetros(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _rad(double grados) => grados * pi / 180;

  /// Agrupa [direcciones] en zonas de entre [minPorZona] y [maxPorZona]
  /// direcciones, buscando las agrupaciones más compactas por proximidad real.
  /// Devuelve un mapa: id de dirección -> id de zona (ZONA-N).
  ///
  /// Las direcciones sin `lat`/`lng` no pueden agruparse por distancia, así que
  /// se organizan por barrio (en bloques de hasta [maxPorZona]) para no dejarlas
  /// fuera. [variante] permite alternar la elección de semillas para ofrecer
  /// agrupaciones ligeramente distintas (botón "Re-agrupar").
  Map<String, String> agruparEnZonas(
    List<Map<String, dynamic>> direcciones, {
    int minPorZona = 4,
    int maxPorZona = 6,
    List<Map<String, dynamic>>? direccionesSinGeo,
    int variante = 0,
  }) {
    direccionesSinGeo?.clear();
    final mapa = <String, String>{};
    if (direcciones.isEmpty) return mapa;

    final conGeo = <Map<String, dynamic>>[];
    final sinGeo = <Map<String, dynamic>>[];
    for (final d in direcciones) {
      final id = d['id'] as String?;
      final lat = d['lat'];
      final lng = d['lng'];
      if (id == null || lat is! num || lng is! num) {
        sinGeo.add(d);
      } else {
        conGeo.add(d);
      }
    }

    int zonaIndex = 0;

    // 1. Agrupar por cercanía las direcciones con coordenadas.
    final usadas = <String>{};
    while (usadas.length < conGeo.length) {
      final semilla = _elegirSemilla(conGeo, usadas, variante: variante);
      if (semilla == null) break;
      usadas.add(semilla['id'] as String);
      final grupo = <Map<String, dynamic>>[semilla];

      while (grupo.length < maxPorZona) {
        final cercana = _vecinaMasCercana(semilla, conGeo, usadas);
        if (cercana == null) break;
        grupo.add(cercana);
        usadas.add(cercana['id'] as String);
      }

      zonaIndex++;
      final zonaId = 'ZONA-$zonaIndex';
      for (final d in grupo) {
        mapa[d['id'] as String] = zonaId;
      }
    }

    // 2. Sin coordenadas: agrupar por barrio para no dejarlas fuera.
    final porBarrio = <String, List<Map<String, dynamic>>>{};
    for (final d in sinGeo) {
      final barrio = (d['barrio'] ?? 'Sin barrio').toString().trim();
      porBarrio
          .putIfAbsent(barrio.isEmpty ? 'Sin barrio' : barrio, () => [])
          .add(d);
    }
    for (final lista in porBarrio.values) {
      for (var i = 0; i < lista.length; i += maxPorZona) {
        final chunk = lista.sublist(
            i, i + maxPorZona > lista.length ? lista.length : i + maxPorZona);
        zonaIndex++;
        final zonaId = 'ZONA-$zonaIndex';
        for (final d in chunk) {
          mapa[d['id'] as String] = zonaId;
        }
      }
    }

    return mapa;
  }

  Map<String, dynamic>? _elegirSemilla(
      List<Map<String, dynamic>> direcciones, Set<String> usadas,
      {int variante = 0}) {
    final candidatas = direcciones
        .where((d) =>
            !usadas.contains(d['id']) &&
            d['id'] != null &&
            d['lat'] is num &&
            d['lng'] is num)
        .toList();
    candidatas.sort((a, b) =>
        _aislamiento(b, candidatas).compareTo(_aislamiento(a, candidatas)));
    if (candidatas.isEmpty) return null;

    // Con variante se elige entre las N más aisladas (alternando), de modo
    // que "Re-agrupar" produzca distribuciones distintas.
    if (variante > 0) {
      final n = candidatas.length > 3 ? 3 : candidatas.length;
      final idx = variante % n;
      return candidatas[idx];
    }
    return candidatas.first;
  }

  /// Distancia de aislamiento: metros a su vecina más cercana no usada.
  double _aislamiento(
      Map<String, dynamic> d, List<Map<String, dynamic>> candidatas) {
    final v = _vecinaMasCercana(d, candidatas, {d['id'] as String});
    if (v == null) return double.infinity;
    return distanciaMetros(
      (d['lat'] as num).toDouble(),
      (d['lng'] as num).toDouble(),
      (v['lat'] as num).toDouble(),
      (v['lng'] as num).toDouble(),
    );
  }

  Map<String, dynamic>? _vecinaMasCercana(
    Map<String, dynamic> centro,
    List<Map<String, dynamic>> direcciones,
    Set<String> usadas,
  ) {
    final latC = (centro['lat'] as num).toDouble();
    final lngC = (centro['lng'] as num).toDouble();
    Map<String, dynamic>? mejor;
    double mejorDist = double.infinity;
    for (final d in direcciones) {
      final id = d['id'] as String?;
      if (id == null || usadas.contains(id)) continue;
      final lat = d['lat'];
      final lng = d['lng'];
      if (lat is! num || lng is! num) continue;
      final dist = distanciaMetros(latC, lngC, lat.toDouble(), lng.toDouble());
      if (dist < mejorDist) {
        mejorDist = dist;
        mejor = d;
      }
    }
    return mejor;
  }

  /// Calcula el centroide y radio de una zona.
  Zona calcularGeometriaZona(List<Map<String, dynamic>> direcciones) {
    var sumLat = 0.0;
    var sumLng = 0.0;
    var conGeo = 0;
    for (final d in direcciones) {
      final lat = d['lat'];
      final lng = d['lng'];
      if (lat is num && lng is num) {
        sumLat += lat.toDouble();
        sumLng += lng.toDouble();
        conGeo++;
      }
    }
    if (conGeo == 0) {
      return Zona(
        direcciones: direcciones,
        latCentro: 0,
        lngCentro: 0,
        radioKm: 0,
        distanciaMediaMetros: 0,
      );
    }
    final latCentro = sumLat / conGeo;
    final lngCentro = sumLng / conGeo;

    double maxDistMetros = 0;
    double sumaDist = 0;
    for (final d in direcciones) {
      final lat = d['lat'];
      final lng = d['lng'];
      if (lat is! num || lng is! num) continue;
      final dist = distanciaMetros(
          latCentro, lngCentro, lat.toDouble(), lng.toDouble());
      if (dist > maxDistMetros) maxDistMetros = dist;
      sumaDist += dist;
    }
    final media = conGeo > 0 ? sumaDist / conGeo : 0.0;
    return Zona(
      direcciones: direcciones,
      latCentro: latCentro,
      lngCentro: lngCentro,
      radioKm: maxDistMetros / 1000,
      distanciaMediaMetros: media,
    );
  }
}