import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../core/config/app_secrets.dart';
import '../../../../../core/l10n/translation_service.dart';
import '../../../../../core/services/navegacion_rutas_service.dart';
import '../../../../../core/services/ruta_orden_service.dart';

/// Pantalla de navegación continua dentro de la app.
///
/// A diferencia de abrir Google Maps (que pausa en cada parada), aquí el mapa
/// avanza solo: cuando el publicador llega a 25 m del destino actual, la ruta
/// salta a la siguiente dirección y anuncia por voz, sin que tenga que tocar
/// nada.
/// Modo de transporte para calcular la ruta en el mapa.
enum ModoViaje { caminando, auto }

class NavegacionScreen extends StatefulWidget {
  final String titulo;
  final List<DireccionRuta> destinos;

  const NavegacionScreen({
    super.key,
    required this.titulo,
    required this.destinos,
  });

  @override
  State<NavegacionScreen> createState() => _NavegacionScreenState();
}

class _NavegacionScreenState extends State<NavegacionScreen> {
  /// Distancia a la que se considera "llegué" y se avanza sola.
  static const double _umbralLlegadaMetros = 25;

  final MapController _mapController = MapController();

  /// Controlador del mini-mapa. Es un mapa APARTE (en una [OverlayEntry] de la
  /// Overlay raíz) para que quede por encima de TODA la app, incluidos los
  /// diálogos de otros flujos (enviar tarjeta, etc.) sin desmontar el mapa
  /// principal ni pelearse con el árbol de rutas.
  final MapController _miniMapController = MapController();
  final FlutterTts _tts = FlutterTts();

  /// Ventana flotante: cuando está minimizada, el mapa se muestra como una
  /// tarjeta pequeña y arrastrable y el resto de la app queda usable debajo.
  bool _minimizado = false;
  Offset _miniOffset = const Offset(12, 80);

  /// Entrada de overlay del mini-mapa (solo existe mientras está minimizado).
  OverlayEntry? _miniOverlay;
  bool _miniMapaListo = false;

  /// Para no reinsertar la ventana al frente en cada lectura de GPS.
  DateTime? _ultimoReinsertFlotante;

  StreamSubscription<Position>? _subPosicion;
  Position? _posicion;
  double _heading = 0;

  int _actual = 0;
  List<LatLng> _rutaPuntos = const [];

  /// Todas las rutas alternativas devueltas por Mapbox y cuál se muestra.
  List<RutaNav> _rutasAlternativas = const [];
  int _rutaSeleccionada = 0;

  /// Geometría de la ruta mostrada (con distancias acumuladas) para proyectar
  /// la posición GPS sobre ella.
  GeometriaRuta? _geometriaActual;

  /// Índice del tramo donde quedó el usuario la última vez. Sirve para buscar
  /// solo alrededor de ahí y no saltar a otro tramo que pase cerca.
  int _ultimoIndiceProyectado = 0;

  /// Distancia a la polilínea por encima de la cual se considera desvío.
  static const double _umbralDesvioMetros = 45;

  /// Tramos a mirar hacia adelante al proyectar la posición sobre la ruta.
  static const int _ventanaProyeccion = 40;

  /// Puntos de ruta (sobre la polilínea) que faltan por recorrer para avisar
  /// del desvío solo cuando venimos siguiendo la ruta.
  int _lecturasFueraDeRuta = 0;

  /// Cuándo se calculó la última ruta realmente.
  DateTime? _ultimoRecalculo;

  /// Cuándo se pidió el último cálculo desde la posición actual.
  DateTime? _ultimaSolicitud;

  /// Si se pidió un recálculo mientras había otro en vuelo.
  bool _recalcularPendiente = false;

  /// Si el último intento chocó con el límite de peticiones de Mapbox.
  bool _limiteTasa = false;

  /// Mensaje de error legible para mostrar al usuario (null = todo bien).
  String? _mensajeRuta;

  /// Si el usuario ya salió de la ruta, se recalcula aunque el cooldown no
  /// haya pasado, pero no más seguido que esto.
  static const Duration _cooldownDesvioMinimo = Duration(seconds: 4);

  bool _ttsListo = false;
  bool _vozActiva = true;
  bool _siguiendo = true;
  bool _mapaListo = false;
  bool _cargandoRuta = false;
  bool _finalizado = false;

  /// Modo de transporte (a pie / en coche). Por defecto en coche.
  ModoViaje _modo = ModoViaje.auto;

  /// Hasta que el usuario elija el orden y confirme, no se navega.
  bool _iniciado = false;

  /// Copia mutable para poder reordenar antes de iniciar la ruta.
  late List<DireccionRuta> _destinos;

  String _idiomaTts = 'es-ES';
  String? _idiomaAplicado;

  @override
  void initState() {
    super.initState();
    _destinos = [...widget.destinos];
    _initTts();
    _iniciarUbicacion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = TranslationService.of(context)?.currentLanguage;
    if (lang != null && lang.isNotEmpty) {
      _idiomaTts = lang.toUpperCase().startsWith('PT') ? 'pt-BR' : 'es-ES';
    }
  }

  @override
  void dispose() {
    _subPosicion?.cancel();
    _tts.stop();
    _miniOverlay?.remove();
    _miniOverlay = null;
    _mapController.dispose();
    _miniMapController.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      // Velocidad natural (0.85 ≈ ritmo humano; 0.5 suena lento/robótico) y
      // tono neutro para que no suene grave ni de robot.
      await _tts.setSpeechRate(0.85);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      await _aplicarMejorVoz(_idiomaTts);
      _ttsListo = true;
    } catch (_) {
      _ttsListo = false;
    }
  }

  /// Elige la voz más natural disponible para el idioma, evitando las voces
  /// sintéticas que suenan robóticas cuando hay una mejor.
  Future<void> _aplicarMejorVoz(String idioma) async {
    try {
      final voces = await _tts.getVoices;
      if (voces == null || voces.isEmpty) return;
      final lista = voces.whereType<Map>().toList();
      final prefijo = idioma.split('-').first.toLowerCase();

      // Preferir, en orden: voces no "compact"/"robot", que incluyan
      // "network"/"natural"/"enhanced", y del idioma pedido.
      int puntaje(Map v) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final loc = (v['locale'] ?? '').toString().toLowerCase();
        int s = 0;
        if (loc.startsWith(prefijo)) s += 100;
        if (loc.startsWith(idioma.toLowerCase())) s += 20;
        if (name.contains('natural')) s += 40;
        if (name.contains('neural')) s += 40;
        if (name.contains('enhanced')) s += 30;
        if (name.contains('network')) s += 25;
        if (name.contains('google')) s += 15;
        if (name.contains('compact')) s -= 30;
        if (name.contains('robot')) s -= 50;
        return s;
      }

      lista.sort((a, b) => puntaje(b).compareTo(puntaje(a)));
      final mejor = lista.first;
      final loc = (mejor['locale'] ?? '').toString();
      if (loc.isNotEmpty) {
        await _tts.setVoice(Map<String, String>.from(mejor));
      }
    } catch (_) {}
  }

  Future<void> _hablar(String texto) async {
    if (!_vozActiva || !_ttsListo) return;
    try {
      if (_idiomaAplicado != _idiomaTts) {
        await _tts.setLanguage(_idiomaTts);
        await _aplicarMejorVoz(_idiomaTts);
        _idiomaAplicado = _idiomaTts;
      }
      await _tts.stop();
      await _tts.speak(texto);
    } catch (_) {}
  }

  Future<void> _iniciarUbicacion() async {
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        _recalcularRuta();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _alRecibirPosicion(pos);

      _subPosicion = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
        ),
      ).listen(_alRecibirPosicion, onError: (_) {});
    } catch (_) {
      _recalcularRuta();
    }
  }

  void _alRecibirPosicion(Position pos) {
    _posicion = pos;
    final h = pos.heading;
    if (!h.isNaN && h >= 0) _heading = h;

    // Avance automático al llegar al destino actual (solo si ya se inició).
    if (_iniciado && !_finalizado && _actual < _destinos.length) {
      final d = _distancia(
        pos.latitude,
        pos.longitude,
        _destinos[_actual].lat,
        _destinos[_actual].lng,
      );
      if (d <= _umbralLlegadaMetros) {
        _avanzar(automatico: true);
      }
    }

    // Recentra el mapa a pantalla completa.
    if (_siguiendo && _mapaListo) {
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    }

    // Y el mini-mapa de la ventana flotante (es un mapa aparte).
    if (_minimizado && _miniMapaListo) {
      _miniMapController.move(
        LatLng(pos.latitude, pos.longitude),
        _miniMapController.camera.zoom,
      );
    }

    _reinsertarFlotanteAlFrente();

    _talVezRecalcular();
    if (mounted) setState(() {});
  }

  /// Reinserta la ventana flotante al frente de la Overlay para que siga
  /// visible por encima de diálogos que se abran desde la app de abajo
  /// (enviar tarjeta, etc.). Con límite de frecuencia para no parpadear.
  void _reinsertarFlotanteAlFrente() {
    if (!_minimizado || _miniOverlay == null) return;
    final ahora = DateTime.now();
    final ultimo = _ultimoReinsertFlotante;
    if (ultimo != null && ahora.difference(ultimo).inMilliseconds < 1200) {
      return;
    }
    _ultimoReinsertFlotante = ahora;
    final entry = _miniOverlay!;
    entry.remove();
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// Decide si hay que recalcular, de forma robusta:
  ///  * proyecta la posición sobre la polilínea: si queda lejos de la ruta y
  ///    el usuario venía siguiéndola, está desviado;
  ///  * mientras siga sobre la ruta, no recalcula por avanzar (la línea ya
  ///    llega al destino).
  /// Aplica anti-rebote (varias lecturas seguidas) y tiempos mínimos entre
  /// recálculos para no saturar la API.
  Future<void> _talVezRecalcular() async {
    if (_finalizado || _posicion == null) return;
    final aqui = LatLng(_posicion!.latitude, _posicion!.longitude);

    // Umbral de desvío adaptativo: a pie (más lento) toleramos más margen.
    final umbralDesvio =
        _modo == ModoViaje.auto ? _umbralDesvioMetros : 30.0;

    double? distanciaLinea;
    final geo = _geometriaActual;
    if (geo != null && geo.puntos.length >= 2) {
      final proyeccion = geo.proyectar(
        aqui,
        desdeIndice: _ultimoIndiceProyectado,
        ventana: _ventanaProyeccion,
      );
      if (proyeccion != null) {
        distanciaLinea = proyeccion.distanciaM;
        _ultimoIndiceProyectado = proyeccion.indice;
      }
    } else if (_rutaPuntos.length >= 2) {
      distanciaLinea = _distanciaALinea(aqui, _rutaPuntos);
    }

    final fueraDeRuta =
        distanciaLinea != null && distanciaLinea > umbralDesvio;

    // Desvío confirmado: varias lecturas seguidas fuera de ruta.
    if (fueraDeRuta) {
      _lecturasFueraDeRuta++;
    } else {
      _lecturasFueraDeRuta = 0;
    }
    final desviado = _lecturasFueraDeRuta >= 2;

    if (!desviado) return;

    // Anti-spam: un desvío recalcula antes, pero respetando un mínimo.
    final ahora = DateTime.now();
    final ultima = _ultimaSolicitud ?? _ultimoRecalculo;
    if (ultima != null &&
        ahora.difference(ultima) < _cooldownDesvioMinimo) {
      return;
    }

    // Si ya hay un cálculo en vuelo, reencolar en vez de descartar.
    if (_cargandoRuta) {
      _recalcularPendiente = true;
      return;
    }

    _lecturasFueraDeRuta = 0;
    _ultimaSolicitud = ahora;
    await _recalcularRuta();
  }

  /// Distancia mínima (m) de [p] a la polilínea [linea]. Se usa solo mientras
  /// no hay geometría con distancias acumuladas.
  double _distanciaALinea(LatLng p, List<LatLng> linea) {
    var mejor = double.infinity;
    for (var i = 0; i < linea.length - 1; i++) {
      final d = _distanciaASegmento(p, linea[i], linea[i + 1]);
      if (d < mejor) mejor = d;
    }
    return mejor;
  }

  /// Distancia (m) de [p] al segmento [a]-[b], en proyección equirectangular.
  double _distanciaASegmento(LatLng p, LatLng a, LatLng b) {
    const metrosPorGrado = 111320.0;
    final latRad = p.latitude * math.pi / 180;
    final cosLat = math.cos(latRad);

    double ax = (a.longitude - p.longitude) * metrosPorGrado * cosLat;
    double ay = (a.latitude - p.latitude) * metrosPorGrado;
    double bx = (b.longitude - p.longitude) * metrosPorGrado * cosLat;
    double by = (b.latitude - p.latitude) * metrosPorGrado;

    final dx = bx - ax;
    final dy = by - ay;
    final largo2 = dx * dx + dy * dy;
    if (largo2 == 0) return math.sqrt(ax * ax + ay * ay);

    var t = -(ax * dx + ay * dy) / largo2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  /// Refresca [_geometriaActual] y [_rutaPuntos] a partir de la ruta mostrada.
  void _aplicarRutaSeleccionada() {
    if (_rutasAlternativas.isEmpty ||
        _rutaSeleccionada >= _rutasAlternativas.length) {
      _geometriaActual = null;
      return;
    }
    final puntos = _rutasAlternativas[_rutaSeleccionada].puntos;
    _rutaPuntos = puntos;
    _geometriaActual = GeometriaRuta(puntos);
    _ultimoIndiceProyectado = 0;
  }

  /// Calcula la ruta hasta la parada actual.
  ///
  /// [motivoDesvio] = true cuando se llama porque el usuario se salió de la
  /// ruta: en ese caso, si Mapbox falla, conservamos la ruta anterior en vez
  /// de dejar una línea recta que no sigue calles. Solo se pide una vez (sin
  /// reintento inmediato que empeore el problema si hay límite de tasa).
  Future<void> _recalcularRuta({
    bool conservarSeleccion = false,
    bool motivoDesvio = false,
  }) async {
    if (!_iniciado || _finalizado) return;
    if (_cargandoRuta) {
      _recalcularPendiente = true;
      return;
    }
    _cargandoRuta = true;
    _ultimoRecalculo = DateTime.now();

    final origen = _posicion != null
        ? LatLng(_posicion!.latitude, _posicion!.longitude)
        : null;
    if (origen == null || _actual >= _destinos.length) {
      _cargandoRuta = false;
      if (mounted) setState(() {});
      return;
    }
    final destino =
        LatLng(_destinos[_actual].lat, _destinos[_actual].lng);

    final resultado = await NavegacionRutasService.obtener(
      origen: origen,
      destino: destino,
      perfil: _perfilMapbox,
      rumbo: _heading.isFinite && _heading > 0 ? _heading : null,
    );

    _cargandoRuta = false;
    if (!mounted) return;

    setState(() {
      _limiteTasa = resultado.limiteTasa;
      _mensajeRuta = null;
      if (resultado.ok) {
        _rutasAlternativas = resultado.rutas;
        // Al recalcular por desvío se elige la mejor; al cambiar de alternativa
        // manualmente se conserva la selección si sigue existiendo.
        if (!conservarSeleccion ||
            _rutaSeleccionada >= resultado.rutas.length) {
          _rutaSeleccionada = 0;
        }
        _aplicarRutaSeleccionada();
      } else {
        _mensajeRuta = resultado.error;
        if (!motivoDesvio && _rutaPuntos.isEmpty) {
          // Solo si nunca hubo ruta: línea directa como último recurso.
          _rutasAlternativas = const [];
          _aplicarRutaSeleccionada();
          _rutaPuntos = [origen, destino];
        }
        // Si ya había una ruta válida, se conserva (mejor que la línea recta).
      }
    });
    _procesarRecalculoPendiente();
  }

  /// Si durante el cálculo llegó otra posición que pedía recalcular, lo hace.
  void _procesarRecalculoPendiente() {
    if (!_recalcularPendiente) return;
    _recalcularPendiente = false;
    _talVezRecalcular();
  }

  /// Rota a la siguiente ruta alternativa disponible.
  void _cambiarAlternativa() {
    if (_rutasAlternativas.length < 2) return;
    setState(() {
      _rutaSeleccionada =
          (_rutaSeleccionada + 1) % _rutasAlternativas.length;
      _aplicarRutaSeleccionada();
    });
    _hablar('Ruta alternativa ${_rutaSeleccionada + 1}');
  }

  void _avanzar({bool automatico = false}) {
    if (_finalizado) return;

    if (_actual >= _destinos.length - 1) {
      _finalizado = true;
      _hablar(automatico
          ? 'Llegaste al último destino. Ruta completada.'
          : 'Ruta finalizada.');
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _actual++;
      _rutaSeleccionada = 0;
      _ultimoIndiceProyectado = 0;
      _lecturasFueraDeRuta = 0;
    });
    _hablar('Llegaste. Próxima parada: ${_destinos[_actual].nombre}');
    _recalcularRuta();
  }

  void _finalizar() {
    _finalizado = true;
    _hablar('Ruta finalizada.');
    if (mounted) setState(() {});
  }

  void _recentrar() {
    setState(() => _siguiendo = true);
    if (_posicion != null && _mapaListo) {
      _mapController.move(
        LatLng(_posicion!.latitude, _posicion!.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  LatLng _centroInicial() {
    if (_posicion != null) {
      return LatLng(_posicion!.latitude, _posicion!.longitude);
    }
    if (_destinos.isNotEmpty) {
      final d = _destinos[_actual < _destinos.length ? _actual : 0];
      return LatLng(d.lat, d.lng);
    }
    return const LatLng(-25.6, -49.4); // Araucária - PR
  }

  double _distancia(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  double? _distanciaDesdeMi(DireccionRuta d) {
    if (_posicion == null) return null;
    return _distancia(_posicion!.latitude, _posicion!.longitude, d.lat, d.lng);
  }

  double _distanciaActual() {
    if (_posicion == null || _actual >= _destinos.length) return 0;
    final d = _destinos[_actual];
    return _distancia(
        _posicion!.latitude, _posicion!.longitude, d.lat, d.lng);
  }

  String _formatoDistancia(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  /// Perfil de Mapbox según el modo elegido.
  String get _perfilMapbox =>
      _modo == ModoViaje.auto ? 'driving-traffic' : 'walking';

  /// Velocidad promedio para estimar el tiempo restante (m/s).
  double get _velocidad => _modo == ModoViaje.auto ? 8.3 : 1.4;

  String _formatoEta(double m) {
    final seg = m / _velocidad;
    if (seg < 60) return 'menos de 1 min';
    return '${(seg / 60).round()} min';
  }

  /// ETA del destino actual: usa la duración real de la ruta elegida escalada
  /// por la distancia restante; si no hay dato, estima por velocidad media.
  String _etaRestante(double distanciaLinea) {
    if (_rutasAlternativas.length > _rutaSeleccionada) {
      final ruta = _rutasAlternativas[_rutaSeleccionada];
      if (ruta.distanciaM > 0 && ruta.duracionS > 0) {
        final fraccion = (distanciaLinea / ruta.distanciaM).clamp(0.0, 1.5);
        final seg = ruta.duracionS * fraccion;
        if (seg < 60) return 'menos de 1 min';
        final min = (seg / 60).round();
        if (min < 60) return '$min min';
        return '${(min / 60).floor()} h ${min % 60} min';
      }
    }
    return _formatoEta(distanciaLinea);
  }

  List<Marker> _marcadores() {
    final markers = <Marker>[];

    for (var i = 0; i < _destinos.length; i++) {
      final d = _destinos[i];
      final esActual = i == _actual && !_finalizado;
      final visitado = i < _actual || _finalizado;

      markers.add(Marker(
        point: LatLng(d.lat, d.lng),
        width: 36,
        height: 36,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: visitado
                ? Colors.green.shade600
                : (esActual ? Colors.orange.shade800 : const Color(0xFF1565C0)),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3),
            ],
          ),
          child: esActual
              ? const Icon(Icons.flag, color: Colors.white, size: 18)
              : Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ));
    }

    if (_posicion != null) {
      markers.add(Marker(
        point: LatLng(_posicion!.latitude, _posicion!.longitude),
        width: 44,
        height: 44,
        child: Transform.rotate(
          angle: _heading * math.pi / 180,
          child: const Icon(Icons.navigation, color: Color(0xFF1A73E8), size: 34),
        ),
      ));
    }

    return markers;
  }

  /// Capas comunes del mapa (tiles, ruta y marcadores).
  List<Widget> _capasMapa() {
    const token = AppSecrets.mapboxToken;
    return [
      TileLayer(
        urlTemplate:
            'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token=$token',
        userAgentPackageName: 'com.congregacion.araucaria_sur',
        maxZoom: 19,
      ),
      if (_rutaPuntos.isNotEmpty)
        PolylineLayer(polylines: [
          Polyline(
            points: _rutaPuntos,
            color: Colors.blue.shade700,
            strokeWidth: 5,
          ),
        ]),
      MarkerLayer(markers: _marcadores()),
    ];
  }

  /// Mapa a pantalla completa (vive dentro de la ruta de navegación).
  Widget _widgetMapa() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _centroInicial(),
        initialZoom: 16,
        onMapReady: () {
          _mapaListo = true;
          if (_posicion != null) {
            _mapController.move(
              LatLng(_posicion!.latitude, _posicion!.longitude),
              16.5,
            );
          }
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _siguiendo) {
            setState(() => _siguiendo = false);
          }
        },
      ),
      children: _capasMapa(),
    );
  }

  /// Mini-mapa de la ventana flotante. Es un mapa APARTE (solo lectura) que
  /// vive en una [OverlayEntry] de la Overlay raíz para quedar por encima de
  /// toda la app, sin desmontar el mapa principal.
  Widget _widgetMiniMapa() {
    return FlutterMap(
      mapController: _miniMapController,
      options: MapOptions(
        initialCenter: _centroInicial(),
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
        onMapReady: () => _miniMapaListo = true,
      ),
      children: _capasMapa(),
    );
  }

  /// Contenido de la ventana flotante: la tarjeta arrastrable con el mini-mapa.
  ///
  /// Se monta dentro de una [OverlayEntry] de la Overlay raíz, así queda por
  /// encima de toda la app (incluidos los diálogos de otros flujos) y todo lo
  /// que cae fuera de la tarjeta llega a la pantalla de abajo sin estorbar.
  Widget _contenidoFlotante() {
    const ancho = 300.0;
    const alto = 224.0;
    const margen = 8.0;

    final destino = _actual < _destinos.length ? _destinos[_actual] : null;
    final distancia = destino == null ? null : _distanciaDesdeMi(destino);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft =
            (constraints.maxWidth - ancho - margen).clamp(margen, 100000.0);
        final maxTop =
            (constraints.maxHeight - alto - margen).clamp(margen, 100000.0);
        final left = _miniOffset.dx.clamp(margen, maxLeft);
        final top = _miniOffset.dy.clamp(margen, maxTop);

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                onPanUpdate: (d) {
                  _miniOffset = Offset(
                    _miniOffset.dx + d.delta.dx,
                    _miniOffset.dy + d.delta.dy,
                  );
                  _miniOverlay?.markNeedsBuild();
                },
                child: Material(
                  elevation: 14,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: ancho,
                    height: alto,
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          color: const Color(0xFF1B5E20),
                          padding: const EdgeInsets.only(left: 12, right: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.navigation,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      destino?.nombre ?? 'Ruta finalizada',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (distancia != null)
                                      Text(
                                        _formatoDistancia(distancia),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ampliar',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.open_in_full,
                                    color: Colors.white, size: 18),
                                onPressed: _ampliar,
                              ),
                              IconButton(
                                tooltip: 'Cerrar navegación',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 18),
                                onPressed: _cerrarNavegacion,
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _widgetMiniMapa()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Minimiza el mapa: la ruta se oculta y aparece la ventana flotante en la
  /// Overlay raíz, por encima de toda la app (diálogos incluidos).
  void _minimizar() {
    if (_minimizado) return;
    setState(() => _minimizado = true);
    _mostrarFlotante();
  }

  void _mostrarFlotante() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _miniOverlay?.remove();
    _miniOverlay = OverlayEntry(builder: (_) => _contenidoFlotante());
    overlay.insert(_miniOverlay!);
  }

  /// Vuelve a la navegación a pantalla completa desde la ventana flotante.
  void _ampliar() {
    _miniOverlay?.remove();
    _miniOverlay = null;
    _miniMapaListo = false;
    setState(() {
      _minimizado = false;
      _siguiendo = true;
    });
    // El mapa full se vuelve a montar; recentramos al quedar listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapaListo) return;
      if (_posicion != null) {
        _mapController.move(
          LatLng(_posicion!.latitude, _posicion!.longitude),
          _mapController.camera.zoom,
        );
      }
    });
  }

  /// Cierra la navegación: remueve la ventana flotante y sale de la ruta.
  void _cerrarNavegacion() {
    _miniOverlay?.remove();
    _miniOverlay = null;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hayDestino = _actual < _destinos.length;
    final destino = hayDestino ? _destinos[_actual] : null;
    final distancia = _distanciaActual();

    final appBarFull = AppBar(
      title: Text(widget.titulo.isEmpty ? 'Navegación' : widget.titulo),
      backgroundColor: const Color(0xFF1B5E20),
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18,
        letterSpacing: 0.3,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      actions: [
        IconButton(
          tooltip: 'Minimizar mapa',
          icon: const Icon(Icons.picture_in_picture_alt),
          onPressed: _minimizar,
        ),
        if (_rutasAlternativas.length > 1)
          IconButton(
            tooltip: 'Ruta alternativa',
            icon: const Icon(Icons.alt_route),
            onPressed: _cambiarAlternativa,
          ),
        PopupMenuButton<ModoViaje>(
          tooltip: 'Cómo ir',
          onSelected: _cambiarModo,
          icon: Icon(_modo == ModoViaje.auto
              ? Icons.directions_car
              : Icons.directions_walk),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: ModoViaje.caminando,
              child: ListTile(
                leading: Icon(Icons.directions_walk),
                title: Text('A pie'),
              ),
            ),
            PopupMenuItem(
              value: ModoViaje.auto,
              child: ListTile(
                leading: Icon(Icons.directions_car),
                title: Text('En coche'),
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: _vozActiva ? 'Silenciar voz' : 'Activar voz',
          icon: Icon(_vozActiva ? Icons.volume_up : Icons.volume_off),
          onPressed: () => setState(() => _vozActiva = !_vozActiva),
        ),
      ],
    );

    // Minimizado: la ventana flotante vive en la Overlay raíz (por encima de
    // todo). La ruta se vuelve transparente y NO absorbe toques, así la app de
    // abajo queda usable sin cerrar la navegación.
    if (_minimizado) return const SizedBox.shrink();

    return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBarFull,
        body: Stack(
          children: [
            _widgetMapa(),

            // Atribución obligatoria de Mapbox / OpenStreetMap.
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                color: Colors.white70,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: const Text(
                  '© Mapbox © OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
            ),

            // Banner superior: instrucciones al planificar o destino.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _iniciado
                  ? _bannerDestino(destino, distancia)
                  : _bannerPlanificar(),
            ),

            // Controles inferiores: planificador o navegación en curso.
            if (_iniciado)
              Positioned(
                bottom: 16,
                left: 12,
                right: 12,
                child: _controles(),
              )
            else
              _planificador(),
          ],
        ),
    );
  }

  void _cambiarModo(ModoViaje m) {
    if (m == _modo) return;
    setState(() {
      _modo = m;
      _rutaSeleccionada = 0;
      _ultimoIndiceProyectado = 0;
      _lecturasFueraDeRuta = 0;
    });
    _recalcularRuta();
    _hablar(m == ModoViaje.auto ? 'Ruta en coche' : 'Ruta a pie');
  }

  /// Comienza la navegación con el orden actual de paradas.
  void _iniciarRuta() {
    if (_destinos.isEmpty) return;
    setState(() {
      _iniciado = true;
      _finalizado = false;
      _actual = 0;
      _rutaSeleccionada = 0;
      _ultimoIndiceProyectado = 0;
      _lecturasFueraDeRuta = 0;
      _siguiendo = true;
    });
    _hablar('Ruta iniciada. Primera parada: ${_destinos.first.nombre}');
    _recalcularRuta();
    if (_posicion != null && _mapaListo) {
      _mapController.move(
        LatLng(_posicion!.latitude, _posicion!.longitude),
        16.5,
      );
    }
  }

  /// Pone la parada [i] como primera y arranca la navegación.
  void _empezarPor(int i) {
    if (i < 0 || i >= _destinos.length) return;
    setState(() {
      final elegida = _destinos.removeAt(i);
      _destinos.insert(0, elegida);
    });
    _iniciarRuta();
  }

  void _reordenar(int viejo, int nuevo) {
    setState(() {
      final item = _destinos.removeAt(viejo);
      _destinos.insert(nuevo, item);
    });
  }

  Widget _bannerPlanificar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(Icons.route, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Elegí por dónde empezar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B1B1B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ordená las paradas o tocá el ▶ para arrancar por una. '
                  'Modo actual: ${_modo == ModoViaje.auto ? 'en coche' : 'a pie'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planificador() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 10),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.list_alt, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${_destinos.length} parada${_destinos.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  const Icon(Icons.drag_indicator,
                      size: 18, color: Colors.grey),
                ],
              ),
            ),
            Flexible(
              child: _destinos.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No hay direcciones para ubicar.'),
                    )
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      itemCount: _destinos.length,
                      onReorderItem: _reordenar,
                      itemBuilder: (ctx, i) {
                        final d = _destinos[i];
                        final dist = _distanciaDesdeMi(d);
                        return ListTile(
                          key: ValueKey(d.id),
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFF1565C0),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                          title: Text(
                            d.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: dist != null
                              ? Text(_formatoDistancia(dist),
                                  style: const TextStyle(fontSize: 11))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Empezar por esta',
                                icon: Icon(Icons.play_arrow,
                                    color: Colors.green.shade700),
                                onPressed: () => _empezarPor(i),
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_handle),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _destinos.isEmpty ? null : _iniciarRuta,
                    icon: const Icon(Icons.navigation, size: 20),
                    label: const Text('Iniciar ruta',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerDestino(DireccionRuta? destino, double distancia) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _finalizado ? Icons.check_circle : Icons.flag,
                color: _finalizado
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _finalizado
                    ? 'Ruta completada'
                    : 'Destino ${_actual + 1} de ${_destinos.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              if (_rutasAlternativas.length > 1 && !_finalizado)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: _cambiarAlternativa,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alt_route,
                              size: 13, color: Colors.blue.shade700),
                          const SizedBox(width: 3),
                          Text(
                            'Ruta ${_rutaSeleccionada + 1}/'
                            '${_rutasAlternativas.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_posicion == null)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_cargandoRuta)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _finalizado
                ? 'Todas las direcciones visitadas'
                : (destino?.nombre ?? 'Sin destinos'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B1B1B),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!_finalizado) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.straighten, size: 15, color: Colors.blue.shade700),
                const SizedBox(width: 4),
                Text(
                  _formatoDistancia(distancia),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _modo == ModoViaje.auto
                      ? Icons.directions_car
                      : Icons.directions_walk,
                  size: 15,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  _etaRestante(distancia),
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
          if (_mensajeRuta != null && !_finalizado) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _limiteTasa ? Icons.hourglass_top : Icons.wifi_off,
                  size: 15,
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _limiteTasa
                        ? 'Mapbox limitó las peticiones. Reintentando en un momento…'
                        : _mensajeRuta!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _controles() {
    return Row(
      children: [
        _botonIcono(
          _siguiendo ? Icons.my_location : Icons.location_searching,
          'Recentrar',
          _recentrar,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _finalizado ? null : () => _avanzar(),
            icon: Icon(
              _finalizado ? Icons.check : Icons.skip_next,
              size: 20,
            ),
            label: Text(
              _finalizado ? 'Completado' : 'Siguiente parada',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.green.shade700,
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _botonIcono(Icons.close, 'Finalizar', _finalizar),
      ],
    );
  }

  Widget _botonIcono(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: const Color(0xFF1B5E20)),
        onPressed: onTap,
      ),
    );
  }
}

/// Ruta transparente para la navegación.
///
/// `PageRouteBuilder` (y toda [ModalRoute]) crea SIEMPRE una `ModalBarrier`
/// con `HitTestBehavior.opaque`, que absorbe todos los toques de la pantalla:
/// por eso, aun con `opaque: false` y `barrierColor: transparent`, la app de
/// abajo quedaba inservible al minimizar el mapa.
///
/// Aquí sobreescribimos [buildModalBarrier] para devolver un widget nulo: la
/// barrera sigue existiendo como entry pero no ocupa ni consume nada, de modo
/// que los toques atraviesan la ruta y llegan a la pantalla de abajo.
class RutaNavegacionTransparente<T> extends PageRouteBuilder<T> {
  RutaNavegacionTransparente({required super.pageBuilder})
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        );

  @override
  Widget buildModalBarrier() {
    return const SizedBox.shrink();
  }
}
