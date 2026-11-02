import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'mapbox_service.dart';

/// Una parada de la ruta, ya con coordenadas resueltas.
class DireccionRuta {
  final String id;
  final String nombre;
  final double lat;
  final double lng;
  final bool prioridadMesAnterior;

  const DireccionRuta({
    required this.id,
    required this.nombre,
    required this.lat,
    required this.lng,
    this.prioridadMesAnterior = false,
  });
}

/// Prepara y ordena las direcciones de una tarjeta para armar una ruta.
///
/// Ordena por proximidad geográfica (vecino más cercano) partiendo de la
/// ubicación del publicador, dejando primero las prioridades del mes anterior
/// para no perderlas de vista. Si una dirección no tiene coordenadas, se
/// geocodifica con Mapbox y se guarda en `direcciones_globales` para no
/// repetir la consulta la próxima vez.
class RutaOrdenService {
  RutaOrdenService._();

  static const String _coleccion = 'direcciones_globales';

  /// Resuelve coordenadas y devuelve las direcciones ordenadas.
  ///
  /// Si no se pasa origen, se respeta el orden original (solo se agrupan las
  /// prioridades primero), que es lo que pide el flujo de "el orden en que
  /// aparecen en la tarjeta".
  static Future<List<DireccionRuta>> preparar(
    List<QueryDocumentSnapshot> docs, {
    double? origenLat,
    double? origenLng,
  }) async {
    final resueltas = <DireccionRuta>[];

    for (final doc in docs) {
      final data = _data(doc);
      final nombre = _nombre(data);

      var lat = _double(data['lat']);
      var lng = _double(data['lng']);
      if (!_valida(lat, lng)) {
        final geo = await MapboxService.geocodificar(nombre);
        if (geo != null) {
          lat = geo[0];
          lng = geo[1];
          _cachear(doc.id, lat, lng);
        }
      }
      if (!_valida(lat, lng)) continue;

      resueltas.add(DireccionRuta(
        id: doc.id,
        nombre: nombre,
        lat: lat!,
        lng: lng!,
        prioridadMesAnterior: data['prioridad_mes_anterior'] == true,
      ));
    }

    if (origenLat == null || origenLng == null) {
      // Sin ubicación: prioridades primero, luego el orden en que aparecen.
      final copia = [...resueltas];
      copia.sort((a, b) {
        final ap = a.prioridadMesAnterior ? 0 : 1;
        final bp = b.prioridadMesAnterior ? 0 : 1;
        return ap.compareTo(bp);
      });
      return copia;
    }

    final prioridades = resueltas.where((d) => d.prioridadMesAnterior).toList();
    final resto = resueltas.where((d) => !d.prioridadMesAnterior).toList();

    final orden = <DireccionRuta>[];
    var cLat = origenLat;
    var cLng = origenLng;

    final priorOrden = _vecinoMasCercano(prioridades, cLat, cLng);
    orden.addAll(priorOrden);
    if (priorOrden.isNotEmpty) {
      cLat = priorOrden.last.lat;
      cLng = priorOrden.last.lng;
    }
    orden.addAll(_vecinoMasCercano(resto, cLat, cLng));
    return orden;
  }

  /// Ordena por vecino más cercano partiendo de (lat,lng).
  static List<DireccionRuta> _vecinoMasCercano(
      List<DireccionRuta> entrada, double lat, double lng) {
    final pendientes = [...entrada];
    final salida = <DireccionRuta>[];
    var cLat = lat;
    var cLng = lng;

    while (pendientes.isNotEmpty) {
      var mejor = 0;
      var mejorDist = double.infinity;
      for (var i = 0; i < pendientes.length; i++) {
        final d = _haversine(cLat, cLng, pendientes[i].lat, pendientes[i].lng);
        if (d < mejorDist) {
          mejorDist = d;
          mejor = i;
        }
      }
      final elegido = pendientes.removeAt(mejor);
      salida.add(elegido);
      cLat = elegido.lat;
      cLng = elegido.lng;
    }
    return salida;
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double grados) => grados * math.pi / 180.0;

  static Map<String, dynamic> _data(QueryDocumentSnapshot doc) {
    try {
      return (doc.data() as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  static String _nombre(Map<String, dynamic> data) {
    final calle = (data['calle'] as String?)?.trim() ?? '';
    final comp = (data['complemento'] as String?)?.trim() ?? '';
    if (calle.isEmpty && comp.isEmpty) {
      return (data['texto_direccion'] as String?)?.trim() ?? '';
    }
    return comp.isEmpty ? calle : '$calle, $comp';
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool _valida(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  static void _cachear(String id, double lat, double lng) {
    FirebaseFirestore.instance
        .collection(_coleccion)
        .doc(id)
        .update({'lat': lat, 'lng': lng}).catchError((_) {});
  }
}
