import 'dart:async';
import 'dart:math' show cos, sqrt, asin, pi;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:araucaria_sur/core/services/groq_territory_service.dart';
import 'package:araucaria_sur/core/services/mapbox_poi_service.dart';
import 'package:araucaria_sur/core/services/auto_asignador_service.dart';
import 'package:araucaria_sur/core/services/notificacion_service.dart';
import 'package:araucaria_sur/core/services/geocoding_backfill_service.dart';
import 'whatsapp_ingestion_dialog.dart';

class AuditorPanelPage extends StatefulWidget {
  final Map<String, dynamic>? usuarioData;

  const AuditorPanelPage({Key? key, this.usuarioData}) : super(key: key);

  @override
  State<AuditorPanelPage> createState() => _AuditorPanelPageState();
}

/// Caché compartida y de corta duración del universo canónico de
/// territorios/tarjetas (Requerimiento 1).
///
/// Sustituye el patrón "N+1" que estaba repetido en ~6 métodos del panel
/// (leer TODOS los territorios y luego, por cada uno, hacer un `.get()`
/// aparte a su subcolección `tarjetas`) por UNA sola lectura de territorios
/// + UNA sola lectura de tarjetas vía `collectionGroup('tarjetas')`.
///
/// Importante: `collectionGroup('tarjetas')` empareja cualquier subcolección
/// llamada `tarjetas` en toda la base, incluida una eventual colección RAÍZ
/// `tarjetas` (legacy) si todavía existiera físicamente. Por eso cada
/// documento se valida contra `reference.parent.parent`: solo se acepta si
/// cuelga de `territorios/{id}/tarjetas`, que es la única ubicación canónica
/// permitida por el Requerimiento 1. Cualquier tarjeta legacy de raíz queda
/// automáticamente excluida sin necesitar una migración previa.
class _TerritorioTarjetaCache {
  _TerritorioTarjetaCache(this._firestore);
  final FirebaseFirestore _firestore;

  static const Duration _ttl = Duration(seconds: 20);
  DateTime? _cargadoEn;
  Future<void>? _cargaEnCurso;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _territorios = [];
  Map<String, Map<String, dynamic>> _tarjetaMeta = {};
  Map<String, String> _nombreATerritorioId = {};
  Map<String, String> _territorioNombre = {};

  bool get _vigente =>
      _cargadoEn != null && DateTime.now().difference(_cargadoEn!) < _ttl;

  /// Marca la caché como obsoleta. Debe llamarse justo después de cualquier
  /// escritura que cree/edite/elimine territorios o tarjetas, para que la
  /// siguiente lectura no sirva datos desactualizados.
  void invalidar() => _cargadoEn = null;

  Future<void> _asegurarCargado({bool forzar = false}) async {
    if (!forzar && _vigente) return;
    if (_cargaEnCurso != null && !forzar) {
      final enCurso = _cargaEnCurso;
      if (enCurso != null) return enCurso;
    }

    final future = () async {
      final territoriosSnap = await _firestore.collection('territorios').get();
      final nuevoNombreATerritorioId = <String, String>{};
      final nuevoTerritorioNombre = <String, String>{};
      for (final t in territoriosSnap.docs) {
        final nombre = ((t.data()['nombre'] as String?) ?? '').trim();
        nuevoTerritorioNombre[t.id] = nombre.isEmpty ? t.id : nombre;
        if (nombre.isNotEmpty) {
          nuevoNombreATerritorioId[nombre.toLowerCase()] = t.id;
        }
        nuevoNombreATerritorioId[t.id.toLowerCase()] = t.id;
      }

      final tarjetasSnap = await _firestore.collectionGroup('tarjetas').get();
      final nuevoTarjetaMeta = <String, Map<String, dynamic>>{};
      for (final d in tarjetasSnap.docs) {
        final territorioId = d.reference.parent.parent?.id;
        if (territorioId == null ||
            !nuevoTerritorioNombre.containsKey(territorioId)) {
          continue; // No cuelga de territorios/{id}/tarjetas: se descarta.
        }
        final data = d.data();
        nuevoTarjetaMeta[d.id] = {
          'id': d.id,
          'nombre': data['nombre'] ?? 'Sin nombre',
          'territorio_id': territorioId,
          'territorio_nombre': nuevoTerritorioNombre[territorioId],
          'totalDirecciones': (data['totalDirecciones'] as num?)?.toInt() ?? 0,
        };
      }

      _territorios = territoriosSnap.docs;
      _tarjetaMeta = nuevoTarjetaMeta;
      _nombreATerritorioId = nuevoNombreATerritorioId;
      _territorioNombre = nuevoTerritorioNombre;
      _cargadoEn = DateTime.now();
    }();

    _cargaEnCurso = future;
    try {
      await future;
    } finally {
      _cargaEnCurso = null;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> territorios(
      {bool forzar = false}) async {
    await _asegurarCargado(forzar: forzar);
    return _territorios;
  }

  /// tarjeta_id -> {id, nombre, territorio_id, territorio_nombre, totalDirecciones}
  Future<Map<String, Map<String, dynamic>>> tarjetaMeta(
      {bool forzar = false}) async {
    await _asegurarCargado(forzar: forzar);
    return _tarjetaMeta;
  }

  /// nombre-o-id de territorio en minúsculas -> territorio_id real.
  Future<Map<String, String>> nombreATerritorioId({bool forzar = false}) async {
    await _asegurarCargado(forzar: forzar);
    return _nombreATerritorioId;
  }

  /// territorio_id -> nombre para mostrar.
  Future<Map<String, String>> territorioNombre({bool forzar = false}) async {
    await _asegurarCargado(forzar: forzar);
    return _territorioNombre;
  }

  /// Equivalente al antiguo `_cargarTodasTarjetas`: lista plana para pasarle
  /// a la IA (GroqTerritoryService.decidirTarjetaParaDireccion).
  Future<List<Map<String, dynamic>>> tarjetasComoLista(
      {bool forzar = false}) async {
    final meta = await tarjetaMeta(forzar: forzar);
    return meta.values.toList();
  }

  /// Set de ids de tarjetas activas, para chequeos rápidos de pertenencia
  /// (usado por la limpieza de huérfanos y por los conteos por tarjeta).
  Future<Set<String>> idsActivos({bool forzar = false}) async {
    final meta = await tarjetaMeta(forzar: forzar);
    return meta.keys.toSet();
  }
}

class _AuditorPanelPageState extends State<AuditorPanelPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;
  late final _TerritorioTarjetaCache _catalogo = _TerritorioTarjetaCache(_firestore);

  bool _cargando = true;
  bool _autoDivision = true;
  bool _autoAsignacionActiva = false;
  bool _iaConectada = false;
  bool _cargandoEstado = true;

  // --- Backfill de coordenadas (Groq normaliza y ordena, Mapbox geocodifica) ---
  bool _backfillEnCurso = false;
  int _backfillProcesadas = 0;
  int _backfillTotal = 0;
  int _backfillActualizadas = 0;
  int _backfillFallidas = 0;

  // Filtros
  List<String> _reglasProtegidas = ['FARMACIAS', 'COMERCIOS', 'ESCUELAS', 'PUESTO DE GASOLINA'];
  final TextEditingController _nuevoFiltroController = TextEditingController();

  // Selección dinámica
  Set<String> _sugerenciasSeleccionadas = {};

  // Métricas
  int _totalSugerencias = 0;
  int _saturadasCount = 0;
  int _totalNuevasDirecciones = 0; // Reemplaza Terrenos/Aptos

  // --- Métricas de progreso mensual (Requerimiento 3) ---
  // "Existentes": universo total de direcciones válidamente vinculadas a una
  // tarjeta activa dentro de territorios/{id}/tarjetas.
  // "Completadas": subconjunto de las existentes cuyo estado_predicacion ya
  // no es 'pendiente' (NOTA: se asume que cualquier estado distinto de
  // 'pendiente' representa una dirección trabajada; si la app maneja un
  // enum más granular -p.ej. 'completada'/'no_en_casa'/'visitada'- ajustar
  // el filtro de _esCompletada() más abajo).
  // "Pendientes": existentes - completadas.
  int _direccionesExistentes = 0;
  int _direccionesCompletadas = 0;
  int _direccionesPendientesProgreso = 0;
  double get _porcentajeProgresoMensual => _direccionesExistentes == 0
      ? 0.0
      : (_direccionesCompletadas / _direccionesExistentes).clamp(0.0, 1.0);

  // Registros de la raíz `direcciones_globales` que NO tienen una
  // vinculación explícita y válida a territorio/tarjeta (Requerimiento 2.2).
  // Se muestran solo como alerta de calidad de datos; nunca se computan
  // dentro de las métricas ni se listan en las vistas de trabajo del Auditor.
  int _direccionesSinVinculo = 0;

  // --- Soporte para el flujo de "Nueva dirección" ---
  // Firmas de texto (calle+barrio) y coordenadas de direcciones YA
  // existentes en direcciones_globales, para detectar sugerencias
  // duplicadas apenas llegan a la bandeja.
  Set<String> _firmasTextoExistentes = {};
  Set<String> _coordsExistentes = {};
  // Puntos con coordenadas + tarjeta activa, usados como candidatos para
  // la asignación manual por cercanía geográfica.
  List<Map<String, dynamic>> _puntosReferencia = [];
  // Índice "calle_base|número" -> direcciones existentes con esa misma
  // calle+número (sin importar el complemento casa/apto/etc). Señal más
  // fuerte que la distancia geográfica para direcciones multi-casa.
  Map<String, List<Map<String, dynamic>>> _direccionesPorVia = {};

  List<Map<String, dynamic>> _tarjetasMatriz = [];
  List<Map<String, dynamic>> _sugerenciasLista = [];
  List<Map<String, dynamic>> _nuevasDireccionesLista = []; // Bandeja de entrada de nuevas direcciones

  // Escaneo de zona con Mapbox (POI Discovery)
  bool _escanenandoZona = false;

  // Reorganización local de zonas protegidas (farmacias, comercios, etc.)
  bool _reorganizandoZona = false;

  // Entrada de nuevas direcciones: texto pegado + modo automático en vivo
  final TextEditingController _textoPegadoController = TextEditingController();
  StreamSubscription<QuerySnapshot>? _sugerenciasSub;
  StreamSubscription<QuerySnapshot>? _sugerenciasPendientesSub;
  bool _procesandoAutomatico = false;
  final Set<String> _autoProcesadas = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarConsolaDinamica();
    _cargarEstadoAutoAsignacion();
    _comprobarConexionIA();
    _iniciarEscuchaSugerencias();
  }

  /// Escucha en tiempo real la bandeja de 'sugerencias'.
  ///
  /// Antes, CUALQUIER cambio en 'sugerencias' disparaba `_cargarConsolaDinamica()`
  /// completa (territorios + tarjetas + TODAS las direcciones_globales), lo
  /// cual es costoso y innecesario: la bandeja de nuevas direcciones no
  /// depende de esos datos. Ahora se usan dos listeners independientes:
  ///  1) Uno SIN filtro que actualiza `_nuevasDireccionesLista` /
  ///     `_totalNuevasDirecciones` directamente desde el snapshot (barato).
  ///  2) Uno filtrado por `estado == 'PENDIENTE_AUDITORIA'` que solo evalúa
  ///     si corresponde disparar el modo automático.
  void _iniciarEscuchaSugerencias() {
    _sugerenciasSub?.cancel();
    _sugerenciasSub = _firestore
        .collection('sugerencias')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final nuevasProcesadas = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      setState(() {
        _nuevasDireccionesLista = nuevasProcesadas;
        _totalNuevasDirecciones = nuevasProcesadas.length;
      });
    });

    _sugerenciasPendientesSub?.cancel();
    _sugerenciasPendientesSub = _firestore
        .collection('sugerencias')
        .where('estado', isEqualTo: 'PENDIENTE_AUDITORIA')
        .snapshots()
        .listen((snap) {
      if (!mounted || !_autoAsignacionActiva) return;
      final pendientes = snap.docs
          .where((d) => !_autoProcesadas.contains(d.id))
          .toList();
      if (pendientes.isNotEmpty && !_procesandoAutomatico) {
        _autoProcesarSugerencias(pendientes);
      }
    });
  }

  /// Coloca en lote todas las sugerencias pendientes de la bandeja cuando el
  /// modo automático está activo.
  Future<void> _autoProcesarSugerencias(List<QueryDocumentSnapshot> docs) async {
    if (_procesandoAutomatico) return;
    _procesandoAutomatico = true;

    final direcciones = <Map<String, dynamic>>[];
    for (final d in docs) {
      final data = (d.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final texto = (data['texto_direccion'] ?? '').toString().trim();
      final calle = (data['calle'] ?? texto).toString().trim();
      direcciones.add({
        ...data,
        'id_sugerencia': d.id,
        'calle': calle,
        'complemento': data['complemento'] ?? '',
        'barrio': data['barrio'] ?? '',
        'texto_direccion': texto,
      });
    }

    final email = (widget.usuarioData?['email'] as String?) ?? 'sistema';
    try {
      final resumen = await AutoAsignadorService.procesarLoteDirecciones(
        direcciones: direcciones,
        usuarioEmail: email,
      );

      // Eliminar de la bandeja SOLO las direcciones efectivamente colocadas.
      // Las rechazadas (no reales según Mapbox) se quedan en la bandeja para
      // que el auditor las revise; NO se borran.
      final idsProcesados =
          ((resumen['ids_procesados'] ?? <String>[]) as List).cast<String>();
      final docPorId = {for (final d in docs) d.id: d};
      final batch = _firestore.batch();
      int ops = 0;
      for (final id in idsProcesados) {
        final doc = docPorId[id];
        if (doc == null) continue;
        if (ops >= 380) break;
        batch.delete(doc.reference);
        _autoProcesadas.add(id);
        ops++;
      }
      await batch.commit();

      _cargarConsolaDinamica();
      if (mounted) {
        final errores = (resumen['errores'] as List).cast<String>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Modo automático: ${resumen['procesadas']} dirección(es) colocada(s). '
                '${errores.length} rechazada(s) o con error (quedan en bandeja).'),
            backgroundColor: const Color(0xFF1B4D2E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error en modo automático: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      _procesandoAutomatico = false;
    }
  }

  Future<void> _comprobarConexionIA() async {
    final bool estado = await GroqTerritoryService.verificarConexion();
    if (!mounted) return;
    setState(() {
      _iaConectada = estado;
      _cargandoEstado = false;
    });
  }

  void _abrirCargaMasivaWhatsApp() {
    showDialog<bool>(
      context: context,
      builder: (context) => WhatsAppIngestionDialog(
        usuarioData: widget.usuarioData,
      ),
    ).then((cambio) {
      if (cambio == true && mounted) {
        _cargarConsolaDinamica();
      }
    });
  }

  /// Escanea la zona con Mapbox para cada regla protegida (categoría).
  /// Los lugares nuevos se deduplican contra [direcciones_globales] y, si no
  /// existen, se registran en [sugerencias_pendientes] y en [historial_auditoria].
  /// Escanea la zona con Mapbox para cada regla protegida (categoría).
  /// Los lugares nuevos se deduplican contra [direcciones_globales] y se
  /// muestran en un modal de PREVISUALIZACI"N antes de guardarse. Solo tras la
  /// confirmación del usuario se registran en [sugerencias_pendientes].
  /// Escanea la zona con Mapbox. Flujo interactivo:
  /// 1) El auditor elige el filtro (categoría) a escanear.
  /// 2) Mapbox detecta lugares nuevos (farmacias, comercios, etc.).
  /// 3) La IA sugiere a qué tarjeta/territorio asignar cada uno y por qué.
  /// 4) El auditor aprueba y se cargan directo en direcciones_globales.
  Future<void> _escanearZonaConMapbox() async {
    if (_escanenandoZona || _reglasProtegidas.isEmpty) return;

    // 1. El usuario elige el filtro/categoría a escanear.
    final categoria = await _mostrarSelectorFiltro();
    if (categoria == null || !mounted) return;

    setState(() => _escanenandoZona = true);
    final email = widget.usuarioData?['email']?.toString() ?? 'sistema';
    final region = 'araucaria_sur';

    // 2. Escanear la categoría elegida.
    final List<Map<String, dynamic>> nuevos = [];
    int duplicados = 0;
    final List<String> errores = [];

    final Set<String> coordsExistentes = {};
    final Set<String> dirsExistentes = {};
    try {
      final direccionesSnap =
          await _firestore.collection('direcciones_globales').get();
      for (final doc in direccionesSnap.docs) {
        final d = doc.data();
        final lat = d['lat'];
        final lng = d['lng'];
        if (lat != null && lng != null) {
          coordsExistentes.add('${lat.toStringAsFixed(1)},${lng.toStringAsFixed(1)}');
        }
        final calle = (d['calle'] as String?)?.trim().toLowerCase() ?? '';
        if (calle.isNotEmpty) dirsExistentes.add(calle);
      }
    } catch (e) {
      errores.add('No se pudo leer direcciones existentes: $e');
    }

    final List<String> categoriasAEscanear = (categoria == 'TODAS')
        ? _reglasProtegidas
        : [categoria];

    for (final cat in categoriasAEscanear) {
      List<Map<String, dynamic>> lugares;
      try {
        lugares = await MapboxPoiService.buscarLugaresPorCategoria(
          categoria: cat.toLowerCase(),
          region: region,
        );
      } catch (e) {
        errores.add('$cat: $e');
        continue;
      }
      for (final lugar in lugares) {
        final lat = (lugar['lat'] as num).toDouble();
        final lng = (lugar['lng'] as num).toDouble();
        final claveCoord = '${lat.toStringAsFixed(1)},${lng.toStringAsFixed(1)}';
        final nombre = (lugar['nombre'] as String? ?? '').trim().toLowerCase();
        final dir = (lugar['direccion'] as String? ?? '').trim().toLowerCase();

        if (coordsExistentes.contains(claveCoord) ||
            dirsExistentes.contains(nombre) ||
            (dir.isNotEmpty && dirsExistentes.contains(dir))) {
          duplicados++;
          continue;
        }
        nuevos.add({...lugar, 'categoria_regla': cat});
        coordsExistentes.add(claveCoord);
      }
    }

    if (!mounted) return;
    setState(() => _escanenandoZona = false);

    if (nuevos.isEmpty) {
      _cargarConsolaDinamica();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontraron lugares nuevos de "$categoria". '
              '$duplicados duplicado(s) ignorados.'
              '${errores.isNotEmpty ? '\n\nErrores: ${errores.join('\n')}' : ''}'),
          backgroundColor: const Color(0xFF1B4D2E),
        ),
      );
      return;
    }

    // 3. La IA sugiere la asignación y el auditor aprueba.
    final guardar = await _mostrarAsignacionPois(nuevos, duplicados, errores, email);
    if (guardar == true && mounted) {
      await _guardarPoisEncontrados(nuevos, email, region);
    }
  }

  /// Modal para elegir el filtro/categoría a escanear.
  Future<String?> _mostrarSelectorFiltro() {
    String? seleccion = _reglasProtegidas.isNotEmpty ? _reglasProtegidas.first : null;
    TextEditingController nuevoCtrl = TextEditingController();
    final List<String> opciones = ['TODAS', ..._reglasProtegidas];

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void update() => setDialogState(() {});
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.travel_explore, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text("Filtrar zona a escanear",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¿Qué tipo de lugares quiere buscar?',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    ...opciones.map((op) => RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(op,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          value: op,
                          groupValue: seleccion,
                          activeColor: Colors.teal,
                          onChanged: (v) {
                            seleccion = v;
                            update();
                          },
                        )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nuevoCtrl,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: '+ Nueva categoría (filtro)...',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) {
                              final t = v.trim().toUpperCase();
                              if (t.isNotEmpty && !_reglasProtegidas.contains(t)) {
                                _reglasProtegidas.add(t);
                                seleccion = t;
                                nuevoCtrl.clear();
                                update();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.teal),
                          onPressed: () {
                            final t = nuevoCtrl.text.trim().toUpperCase();
                            if (t.isNotEmpty && !_reglasProtegidas.contains(t)) {
                              _reglasProtegidas.add(t);
                              seleccion = t;
                              nuevoCtrl.clear();
                              update();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    if (seleccion != null) {
                      Navigator.pop(context, seleccion);
                    }
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text("Escanear"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Muestra los lugares nuevos y pide a la IA la tarjeta destino de cada uno.
  /// El auditor aprueba o cancela.
  Future<bool?> _mostrarAsignacionPois(List<Map<String, dynamic>> nuevos,
      int duplicados, List<String> errores, String email) async {
    // Pedir a la IA la asignación de cada lugar a una tarjeta.
    final asignaciones = await _sugerirAsignacionesPois(nuevos, email);

    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.add_location_alt, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Sugerencia de distribución (${nuevos.length})",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$duplicados ya registrado(s) ignorado(s).',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const Divider(),
                  // Lista de lugares con su asignación sugerida.
                  ...nuevos.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    final asg = (asignaciones != null && i < asignaciones.length)
                        ? asignaciones[i]
                        : null;
                    final tarjeta = asg?['tarjeta_nombre'] ?? 'Sin asignación';
                    final razon = asg?['explicacion'] ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${p['nombre']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('${p['direccion']}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('IA sugiere: $tarjeta',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal.shade900)),
                            if (razon.isNotEmpty)
                              Text('Por qué: $razon',
                                  style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (errores.isNotEmpty) ...[
                    const Divider(),
                    Text('Advertencias:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.orange.shade900)),
                    ...errores.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('" $e',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.orange)),
                        )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Descartar"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text("Aprobar y cargar (${nuevos.length})"),
            ),
          ],
        );
      },
    );
  }

  /// Carga TODAS las tarjetas desde su ubicación canónica (subcolección
  /// `territorios/{id}/tarjetas`), con su territorio resuelto en cada doc.
  /// Delega en la caché compartida `_catalogo` (una sola lectura vía
  /// `collectionGroup`, en vez del patrón N+1 anterior).
  Future<List<Map<String, dynamic>>> _cargarTodasTarjetas(
      FirebaseFirestore firestore) async {
    try {
      return await _catalogo.tarjetasComoLista();
    } catch (_) {
      return const [];
    }
  }

  /// Pide a la IA la tarjeta destino de cada dirección detectada.
  Future<List<Map<String, dynamic>>?> _sugerirAsignacionesPois(
      List<Map<String, dynamic>> lugares, String email) async {
    try {
      final tarjetas = await _cargarTodasTarjetas(_firestore);

      final asignaciones = <Map<String, dynamic>>[];
      const int concurrentes = 6;
      for (int i = 0; i < lugares.length; i += concurrentes) {
        final fin = (i + concurrentes) > lugares.length
            ? lugares.length
            : i + concurrentes;
        final chunk = lugares.sublist(i, fin);
        final resultados = await Future.wait(chunk.map((lugar) async {
          final dir = {
            'calle': lugar['nombre'],
            'complemento': '',
            'barrio': lugar['categoria_regla'] ?? '',
            'direccion': lugar['direccion'] ?? '',
          };
          try {
            return await GroqTerritoryService.decidirTarjetaParaDireccion(
              direccion: dir,
              tarjetasExistentes: tarjetas,
            );
          } catch (_) {
            return <String, dynamic>{
              'tarjeta_id_destino': '',
              'tarjeta_nombre': '',
              'explicacion': '',
            };
          }
        }));
        asignaciones.addAll(resultados);
      }
      return asignaciones;
    } catch (_) {
      return null;
    }
  }

  /// Persiste los POIs confirmados en [direcciones_globales] con su tarjeta
  /// destino, actualiza el contador de la tarjeta y registra en el historial.
  Future<void> _guardarPoisEncontrados(
      List<Map<String, dynamic>> nuevos, String email, String region) async {
    int ops = 0;
    var batch = _firestore.batch();

    // Tarjetas existentes para resolver el destino sugerido por la IA, más un
    // mapa tarjeta_id -> territorio (id/nombre) para escribir el `barrio` real.
    final tarjetasPorNombre = <String, String>{};
    final tarjetaTerritorioId = <String, String>{};
    final territorioNombre = <String, String>{};
    try {
      final canonicas = await _cargarTodasTarjetas(_firestore);
      for (final t in canonicas) {
        final id = t['id'].toString();
        final nombre = t['nombre']?.toString() ?? '';
        if (nombre.isNotEmpty) tarjetasPorNombre[nombre] = id;
        final tid = t['territorio_id']?.toString() ?? '';
        if (tid.isNotEmpty) tarjetaTerritorioId[id] = tid;
      }
      territorioNombre.addAll(await _catalogo.territorioNombre());
    } catch (_) {}

    final asignaciones = await _sugerirAsignacionesPois(nuevos, email);

    Future<void> commitSiNecesario() async {
      if (ops >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        ops = 0;
      }
    }

    for (int i = 0; i < nuevos.length; i++) {
      final lugar = nuevos[i];
      final asg = (asignaciones != null && i < asignaciones.length)
          ? asignaciones[i]
          : null;
      final tarjetaNombre = asg?['tarjeta_nombre']?.toString() ?? '';
      final tarjetaId = asg?['tarjeta_id_destino']?.toString() ?? '';

      // Resolver el id real de la tarjeta destino (por id o por nombre).
      String? tarjetaRealId;
      if (tarjetaId.isNotEmpty && (tarjetaId.startsWith('t') || tarjetasPorNombre.containsValue(tarjetaId))) {
        tarjetaRealId = tarjetaId;
      } else if (tarjetaNombre.isNotEmpty && tarjetasPorNombre.containsKey(tarjetaNombre)) {
        tarjetaRealId = tarjetasPorNombre[tarjetaNombre];
      }

      final lat = (lugar['lat'] as num).toDouble();
      final lng = (lugar['lng'] as num).toDouble();
      // `barrio` = territorio real de la tarjeta destino (para que el grid lo
      // pueda vincular); si no se pudo resolver, se conserva la categoría como
      // último recurso (fallback a dato previo).
      final barrioReal = (tarjetaRealId != null && tarjetaRealId.isNotEmpty)
          ? (territorioNombre[tarjetaTerritorioId[tarjetaRealId]] ??
              tarjetaTerritorioId[tarjetaRealId] ??
              (lugar['categoria_regla'] ?? ''))
          : (lugar['categoria_regla'] ?? '');
      final ref = _firestore.collection('direcciones_globales').doc();
      batch.set(ref, {
        'calle': lugar['nombre'],
        'complemento': '',
        'barrio': barrioReal.toString(),
        'tarjeta_id': tarjetaRealId ?? '',
        'territorio_id': tarjetaTerritorioId[tarjetaRealId] ?? '',
        'estado_predicacion': 'pendiente',
        'lat': lat,
        'lng': lng,
        'origen': 'Mapbox Crawler',
        'categoria_regla': lugar['categoria_regla'],
        'creado_el': FieldValue.serverTimestamp(),
      });
      ops++;

      // Incrementar contador de la tarjeta destino (subcolección canónica) SOLO
      // si la tarjeta existe y se resolvió su territorio; evita romper el
      // batch con un id inventado por la IA.
      final tTerId = (tarjetaRealId != null && tarjetaRealId.isNotEmpty)
          ? tarjetaTerritorioId[tarjetaRealId]
          : null;
      if (tarjetaRealId != null &&
          tarjetaRealId.isNotEmpty &&
          tTerId != null &&
          tTerId.isNotEmpty) {
        batch.update(
          _firestore
              .collection('territorios')
              .doc(tTerId)
              .collection('tarjetas')
              .doc(tarjetaRealId),
          {'totalDirecciones': FieldValue.increment(1)},
        );
        ops++;
      }

      await commitSiNecesario();
    }

    try {
      if (ops > 0) await batch.commit();
      // Este batch pudo incrementar `totalDirecciones` de una tarjeta:
      // invalidar la caché compartida para que la próxima lectura no sirva
      // el conteo desactualizado.
      _catalogo.invalidar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
      );
    }

    try {
      await _firestore.collection('historial_auditoria').doc().set({
        'tipo': 'POI_DISCOVERY',
        'region': region,
        'categorias': nuevos.map((n) => n['categoria_regla']).toSet().toList(),
        'resultados': nuevos.length,
        'usuario': email,
        'detalle': 'Escaneo de zona con Mapbox, aprobado y cargado en direcciones_globales',
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (!mounted) return;
    _cargarConsolaDinamica();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${nuevos.length} lugar(es) cargado(s) en el banco de datos (direcciones_globales).'),
        backgroundColor: const Color(0xFF1B4D2E),
      ),
    );
  }

  /// Umbral de "pantalla angosta" (celular). Por encima de esto se muestra
  /// todo el AppBar como antes; por debajo, se colapsa en un menú "⋮" para
  /// no desbordar (RenderFlex overflow), que era la causa del caos visual
  /// y de que las funciones "desaparecieran" en celulares.
  static const double _anchoAngostoBreakpoint = 700;

  /// Dispara el backfill de coordenadas: Groq normaliza/ordena las
  /// direcciones sin lat/lng de `direcciones_globales`, Mapbox las
  /// geocodifica, y se guardan lat/lng (uso interno) + CEP (visible).
  Future<void> _ejecutarBackfillCoordenadas() async {
    if (_backfillEnCurso) return;

    setState(() {
      _backfillEnCurso = true;
      _backfillProcesadas = 0;
      _backfillTotal = 0;
      _backfillActualizadas = 0;
      _backfillFallidas = 0;
    });

    try {
      final resultado = await GeocodingBackfillService.ejecutarBackfillCoordenadas(
        onProgreso: (procesadas, total, actualizadas, fallidas) {
          if (!mounted) return;
          setState(() {
            _backfillProcesadas = procesadas;
            _backfillTotal = total;
            _backfillActualizadas = actualizadas;
            _backfillFallidas = fallidas;
          });
        },
      );

      if (!mounted) return;

      if (resultado.sinPendientes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todas las direcciones ya tienen coordenadas. ✅'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Backfill de coordenadas completado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total revisadas: ${resultado.total}'),
                Text('Actualizadas con coordenadas: ${resultado.actualizadas}',
                    style: const TextStyle(color: Colors.green)),
                if (resultado.fallidas > 0)
                  Text('No se pudieron geocodificar: ${resultado.fallidas}',
                      style: const TextStyle(color: Colors.orange)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error en el backfill de coordenadas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _backfillEnCurso = false);
    }
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final anchoAngosto =
        MediaQuery.of(context).size.width < _anchoAngostoBreakpoint;

    if (!anchoAngosto) {
      // Pantallas anchas (tablet/desktop/web escritorio): todo visible.
      return [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
          child: _buildStatusBadge(),
        ),
        IconButton(
          tooltip: 'Carga Masiva desde WhatsApp',
          icon: const Icon(Icons.input, color: Colors.white),
          onPressed: _abrirCargaMasivaWhatsApp,
        ),
        IconButton(
          tooltip: _direccionesSinVinculo > 0
              ? 'Mantenimiento: $_direccionesSinVinculo dirección(es) sin vínculo detectada(s)'
              : 'Mantenimiento: limpiar direcciones huérfanas',
          icon: Badge(
            isLabelVisible: _direccionesSinVinculo > 0,
            label: Text('$_direccionesSinVinculo'),
            backgroundColor: Colors.red,
            child: const Icon(Icons.cleaning_services, color: Colors.white),
          ),
          onPressed: _limpiarDireccionesHuerfanas,
        ),
        IconButton(
          tooltip: _backfillEnCurso
              ? 'Revisando direcciones... ($_backfillProcesadas/$_backfillTotal)'
              : 'Revisar direcciones globales (coordenadas Groq + Mapbox)',
          icon: _backfillEnCurso
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.travel_explore, color: Colors.white),
          onPressed: _backfillEnCurso ? null : _ejecutarBackfillCoordenadas,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Auto-División', style: TextStyle(color: Colors.white, fontSize: 12)),
            Switch(
              value: _autoDivision,
              activeColor: Colors.amber,
              onChanged: (val) => setState(() => _autoDivision = val),
            ),
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _cargarConsolaDinamica),
          ],
        ),
      ];
    }

    // Pantallas angostas (celular): solo el estado de la IA (ícono) queda
    // inline; todo lo demás se colapsa en un menú de "más opciones".
    return [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _buildStatusBadgeCompacto(),
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        tooltip: 'Más opciones',
        onSelected: (valor) {
          switch (valor) {
            case 'whatsapp':
              _abrirCargaMasivaWhatsApp();
              break;
            case 'mantenimiento':
              _limpiarDireccionesHuerfanas();
              break;
            case 'coordenadas':
              _ejecutarBackfillCoordenadas();
              break;
            case 'refresh':
              _cargarConsolaDinamica();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'whatsapp',
            child: ListTile(
              leading: Icon(Icons.input),
              title: Text('Carga masiva desde WhatsApp'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'mantenimiento',
            child: ListTile(
              leading: Badge(
                isLabelVisible: _direccionesSinVinculo > 0,
                label: Text('$_direccionesSinVinculo'),
                backgroundColor: Colors.red,
                child: const Icon(Icons.cleaning_services),
              ),
              title: const Text('Limpiar direcciones huérfanas'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'coordenadas',
            enabled: !_backfillEnCurso,
            child: ListTile(
              leading: _backfillEnCurso
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore),
              title: Text(_backfillEnCurso
                  ? 'Revisando... ($_backfillProcesadas/$_backfillTotal)'
                  : 'Revisar coordenadas (Groq + Mapbox)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          // enabled: false deja el Switch interactivo sin que el ítem se
          // auto-seleccione/cierre el menú al tocarlo (patrón estándar de
          // Flutter para widgets interactivos dentro de PopupMenuItem).
          PopupMenuItem(
            enabled: false,
            child: StatefulBuilder(
              builder: (context, setLocalState) => Row(
                children: [
                  const Expanded(child: Text('Auto-División')),
                  Switch(
                    value: _autoDivision,
                    onChanged: (val) {
                      setState(() => _autoDivision = val);
                      setLocalState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Actualizar consola'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ];
  }

  /// Versión compacta (solo ícono + tooltip) del estado de la IA, para no
  /// ocupar ancho innecesario en el AppBar de celulares.
  Widget _buildStatusBadgeCompacto() {
    if (_cargandoEstado) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Tooltip(
      message: _iaConectada ? 'Motor IA: Conectado' : 'Motor IA: Inoperativo',
      child: Icon(
        _iaConectada ? Icons.check_circle : Icons.error,
        color: _iaConectada ? Colors.greenAccent.shade400 : Colors.redAccent,
        size: 22,
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_cargandoEstado) {
      return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _iaConectada ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _iaConectada ? Colors.green : Colors.red),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iaConectada ? Icons.check_circle : Icons.error,
            size: 14,
            color: _iaConectada ? Colors.green.shade800 : Colors.red.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            _iaConectada ? "Motor IA: Conectado" : "Motor IA: Inoperativo",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _iaConectada ? Colors.green.shade900 : Colors.red.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sugerenciasSub?.cancel();
    _sugerenciasPendientesSub?.cancel();
    _tabController.dispose();
    _nuevoFiltroController.dispose();
    _textoPegadoController.dispose();
    super.dispose();
  }

  Future<void> _cargarConsolaDinamica() async {
    setState(() => _cargando = true);

    try {
      // 1. Obtener Territorios y Tarjetas desde la caché compartida
      // (una sola lectura vía collectionGroup en vez de N+1 llamadas).
      // Se fuerza refresco aquí porque este es el punto de entrada principal
      // de la consola y el auditor espera ver datos al día tras un refresh.
      final territoriosSnap = await _catalogo.territorios(forzar: true);
      final Map<String, Map<String, dynamic>> matrizMap = {};
      final Map<String, String> nombreAId = {};

      for (var doc in territoriosSnap) {
        final nombre =
            ((doc.data()['nombre'] as String?) ?? doc.id).trim();
        matrizMap[doc.id] = {
          'id': doc.id,
          'nombre': nombre.isEmpty ? doc.id : nombre,
          'direcciones': <Map<String, dynamic>>[],
          'esProtegida': _reglasProtegidas.contains(nombre.toUpperCase()) ||
              _reglasProtegidas.contains(doc.id.toUpperCase()),
        };
        if (nombre.isNotEmpty) nombreAId[nombre.toLowerCase()] = doc.id;
        nombreAId[doc.id.toLowerCase()] = doc.id;
      }

      // Metadatos de tarjeta (para vincular direcciones a territorio por tarjeta).
      // Fuente ÚNICA: subcolección territorios/{id}/tarjetas, servida por la
      // caché compartida (ya excluye cualquier `tarjetas` legacy de raíz).
      final Map<String, Map<String, dynamic>> tarjetaMeta =
          await _catalogo.tarjetaMeta();

      // 2. Obtener Direcciones Globales
      final direccionesSnap = await _firestore.collection('direcciones_globales').get();
      final List<Map<String, dynamic>> sugerenciasProcesadas = [];
      final Map<String, int> dirsPorTarjeta = {};

      // Vincula una dirección a un territorio de forma canónica.
      // PRIORIDAD (Requerimientos 1 y 2):
      //   1) tarjeta_id -> tarjetaMeta -> territorio_id. Esta es la ÚNICA
      //      fuente de verdad, ya que se resuelve contra la subcolección real
      //      `territorios/{id}/tarjetas`. Evita que dos territorios con
      //      barrios de nombre parecido/duplicado se mezclen entre sí.
      //   2) Solo si la tarjeta no existe o no tiene territorio válido, se
      //      intenta un match por texto (barrio/territorio_destino) como
      //      alternativa de compatibilidad hacia atrás para datos legacy.
      // Si ninguna de las dos resuelve, la dirección se considera "sin
      // vínculo" y se aísla completamente (no entra a la matriz ni a las
      // métricas), solo se cuenta para la alerta de calidad de datos.
      String? _resolverTerritorioId(Map<String, dynamic> data) {
        final tid = (data['tarjeta_id'] ?? '').toString().trim();
        if (tid.isNotEmpty) {
          final meta = tarjetaMeta[tid];
          if (meta != null) {
            final tidT = (meta['territorio_id'] as String?)?.toString() ?? '';
            if (tidT.isNotEmpty && matrizMap.containsKey(tidT)) return tidT;
          }
          // Tiene tarjeta_id pero esa tarjeta ya no existe en
          // territorios/{id}/tarjetas (huérfana): NO se debe reconstruir el
          // territorio por texto, porque enmascararía un registro que la
          // herramienta de mantenimiento (Requerimiento 4) debe poder
          // detectar y limpiar.
          return null;
        }

        final candidatos = <String>[
          (data['barrio'] ?? '').toString().trim(),
          (data['territorio_destino'] ?? '').toString().trim(),
        ];
        for (final c in candidatos) {
          if (c.isEmpty) continue;
          if (matrizMap.containsKey(c)) return c;
          final porNombre = nombreAId[c.toLowerCase()];
          if (porNombre != null) return porNombre;
        }
        return null;
      }

      int existentes = 0;
      int pendientesProgreso = 0;
      int sinVinculo = 0;

      // --- Soporte para el flujo de "Nueva dirección" (detección de
      // duplicados + asignación manual por cercanía) ---
      // Firma de texto normalizada (calle+barrio) de cada dirección ya
      // existente, para detectar sugerencias que en realidad ya están
      // cargadas en direcciones_globales.
      final Set<String> firmasTextoExistentes = {};
      // Coordenada redondeada (~11m de precisión) -> también para duplicados.
      final Set<String> coordsExistentes = {};
      // Puntos de referencia con coordenadas + tarjeta válida, para calcular
      // la dirección más cercana al asignar manualmente (Requerimiento:
      // "la base debe ser por cercanía").
      final List<Map<String, dynamic>> puntosReferencia = [];
      // Índice calle_base|número -> direcciones existentes con esa misma vía
      // (no requiere coordenadas: detecta direcciones multi-casa como
      // "Rua Capivari 461, casa 1/2/3" aunque el geocodificador no las haya
      // ubicado con exactitud idéntica).
      final Map<String, List<Map<String, dynamic>>> direccionesPorVia = {};

      for (var dirDoc in direccionesSnap.docs) {
        final data = dirDoc.data();
        final tid = data['tarjeta_id'];
        final tidStr = tid?.toString() ?? '';

        // Requerimiento 2: el conteo por tarjeta solo contempla registros
        // cuyo tarjeta_id apunta a una tarjeta ACTIVA (existente en
        // territorios/{id}/tarjetas). Un tarjeta_id huérfano no suma aquí.
        if (tidStr.isNotEmpty && tarjetaMeta.containsKey(tidStr)) {
          dirsPorTarjeta[tidStr] = (dirsPorTarjeta[tidStr] ?? 0) + 1;
        }

        // Firma de texto/coordenada para el detector de duplicados: se
        // captura para CUALQUIER dirección existente (pendiente o
        // completada), esté o no vinculada a un territorio.
        final calleNorm = _normalizarTexto((data['calle'] ?? '').toString());
        final barrioNorm = _normalizarTexto((data['barrio'] ?? '').toString());
        if (calleNorm.isNotEmpty) firmasTextoExistentes.add('$calleNorm|$barrioNorm');
        final latRaw = data['lat'];
        final lngRaw = data['lng'];
        if (latRaw is num && lngRaw is num) {
          coordsExistentes.add(
              '${latRaw.toStringAsFixed(4)},${lngRaw.toStringAsFixed(4)}');
        }

        final territorioResuelto = _resolverTerritorioId(data);
        if (territorioResuelto == null) {
          // Requerimiento 2.2: aislamiento total. No se agrega a la matriz,
          // no se cuenta en sugerencias, no entra al progreso mensual. Solo
          // se contabiliza para que Mantenimiento pueda limpiarla.
          sinVinculo++;
          continue;
        }

        // Índice por vía (calle+número): la señal MÁS fuerte para sugerir
        // tarjeta destino, sin depender de coordenadas.
        if (tidStr.isNotEmpty && tarjetaMeta.containsKey(tidStr)) {
          final claveVia = _extraerClaveVia(
              (data['calle'] ?? data['texto_direccion'] ?? '').toString());
          if (claveVia != null) {
            (direccionesPorVia[claveVia] ??= []).add({
              'tarjeta_id': tidStr,
              'territorio_id': territorioResuelto,
              'calle': data['calle'] ?? '',
              'barrio': data['barrio'] ?? '',
              'complemento': _extraerComplementoCorto(
                  (data['calle'] ?? '').toString(),
                  (data['complemento'] ?? '').toString()),
            });
          }
        }

        // Punto de referencia para búsqueda por cercanía (solo con
        // coordenadas reales y tarjeta activa; una tarjeta huérfana no debe
        // usarse como sugerencia de destino).
        if (latRaw is num &&
            lngRaw is num &&
            tidStr.isNotEmpty &&
            tarjetaMeta.containsKey(tidStr)) {
          puntosReferencia.add({
            'lat': latRaw.toDouble(),
            'lng': lngRaw.toDouble(),
            'tarjeta_id': tidStr,
            'territorio_id': territorioResuelto,
            'calle': data['calle'] ?? '',
            'barrio': data['barrio'] ?? '',
          });
        }

        // Requerimiento 3: universo de direcciones válidamente asignadas.
        existentes++;
        final esPendiente = data['estado_predicacion'] == 'pendiente';
        if (esPendiente) pendientesProgreso++;

        (matrizMap[territorioResuelto]!['direcciones'] as List)
            .add({'id': dirDoc.id, ...data});

        // Las direcciones de zonas/reglas protegidas (farmacias, comercios, etc.)
        // NO entran a la reorganización general: se manejan de forma local.
        final esProtegida =
            (matrizMap[territorioResuelto]!['esProtegida'] as bool? ?? false);
        if (data['estado_predicacion'] == 'pendiente' && !esProtegida) {
          sugerenciasProcesadas.add({
            'id': dirDoc.id,
            'territorio': territorioResuelto,
            'barrio':
                (data['barrio'] as String?)?.toString() ?? '',
            'calle': data['calle'] ?? 'Sin dirección',
          });
        }
      }

      // 3. Cargar Entrada de Nuevas Direcciones (Colección 'sugerencias' / bandeja)
      final nuevasSnap = await _firestore.collection('sugerencias').get();
      final List<Map<String, dynamic>> nuevasProcesadas = nuevasSnap.docs.map((d) {
        return {
          'id': d.id,
          ...d.data(),
        };
      }).toList();

      // 4. Procesar Matriz Grid (a nivel de Territorio)
      // Un Territorio NO tiene límite de 8 direcciones: puede tener las tarjetas
      // que sean necesarias. Se muestra "Total: X Direcciones (Y Tarjetas)".
      // La saturación (>8) se calcula a nivel de TARJETA individual.
      final int saturadas =
          dirsPorTarjeta.values.where((n) => n > 8).length;

      final List<Map<String, dynamic>> listaMatriz = [];
      matrizMap.forEach((key, item) {
        final dirs = (item['direcciones'] as List).cast<Map<String, dynamic>>();
        final totalDirs = dirs.length;
        final tarjetaIds = dirs
            .map((d) => (d['tarjeta_id'] as String?))
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet();
        final totalTarjetas = tarjetaIds.length;

        // Tarjetas asociadas a este territorio (por territorio_id).
        final tarjetasDeTerritorio = tarjetaMeta.values
            .where((t) => t['territorio_id'] == key)
            .map((t) => {
                  'id': t['id'],
                  'nombre': t['nombre'],
                  'total': dirsPorTarjeta[t['id']] ?? 0,
                  'saturada': (dirsPorTarjeta[t['id']] ?? 0) > 8,
                })
            .toList();

        // Nivel de saturación del territorio: el máximo entre sus tarjetas.
        final maxTarjeta = tarjetasDeTerritorio.isEmpty
            ? 0
            : tarjetasDeTerritorio
                .map((t) => t['total'] as int)
                .reduce((a, b) => a > b ? a : b);

        listaMatriz.add({
          'nombre': item['nombre'],
          'id': key,
          'total': totalDirs,
          'totalTarjetas': totalTarjetas,
          'esProtegida': item['esProtegida'],
          'maxTarjeta': maxTarjeta,
          'tarjetas': tarjetasDeTerritorio,
          'dirsPorTarjeta': Map<String, int>.from(dirsPorTarjeta),
        });
      });

      setState(() {
        _tarjetasMatriz = listaMatriz;
        _totalSugerencias = sugerenciasProcesadas.length;
        _nuevasDireccionesLista = nuevasProcesadas;
        _totalNuevasDirecciones = nuevasProcesadas.length;
        _saturadasCount = saturadas;
        _sugerenciasLista = sugerenciasProcesadas;
        _sugerenciasSeleccionadas = sugerenciasProcesadas.map((e) => e['id'] as String).toSet();
        // Requerimiento 3: contador estricto sobre el universo de tarjetas
        // activas (sin desfasaje por registros sueltos de la raíz).
        _direccionesExistentes = existentes;
        _direccionesPendientesProgreso = pendientesProgreso;
        _direccionesCompletadas = existentes - pendientesProgreso;
        // Requerimiento 2.2 / 4: visibilidad de calidad de datos.
        _direccionesSinVinculo = sinVinculo;
        // Soporte para detección de duplicados y asignación manual por
        // cercanía en la bandeja de "Nuevas Direcciones".
        _firmasTextoExistentes = firmasTextoExistentes;
        _coordsExistentes = coordsExistentes;
        _puntosReferencia = puntosReferencia;
        _direccionesPorVia = direccionesPorVia;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error en Consola: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Requerimiento 4: Herramienta de mantenimiento y calidad de datos.
  ///
  /// Escanea la colección raíz `direcciones_globales`, compara cada
  /// `tarjeta_id` contra el universo de tarjetas ACTIVAS leídas de
  /// `territorios/{id}/tarjetas` (fuente única de verdad) y elimina en lote
  /// (`WriteBatch`) los registros huérfanos: aquellos que no tienen
  /// `tarjeta_id` válido NI un `barrio`/`territorio_destino` que resuelva a
  /// un territorio existente.
  ///
  /// Es una operación destructiva: primero se muestra al auditor un conteo
  /// de candidatos y se pide confirmación explícita antes de borrar nada.
  Future<void> _limpiarDireccionesHuerfanas() async {
    setState(() => _cargando = true);
    try {
      // 1. Universo de tarjetas y territorios activos (misma fuente que
      // _cargarConsolaDinamica, vía la caché compartida). Se fuerza refresco
      // porque esta es una operación destructiva: no puede basarse en datos
      // potencialmente obsoletos de hace hasta 20s.
      //
      // NOTA: se usa únicamente `nombreATerritorioId` (que indexa tanto el
      // nombre como el id del territorio, ambos en minúsculas) en vez de un
      // segundo set de ids en su formato original: comparar ids sin
      // normalizar contra texto ya pasado a minúsculas nunca podía dar match
      // (bug latente del código anterior).
      final nombreATerritorioId = await _catalogo.nombreATerritorioId(forzar: true);
      final tarjetasActivas = await _catalogo.idsActivos();

      // 2. Escanear la raíz y clasificar huérfanos.
      final direccionesSnap = await _firestore.collection('direcciones_globales').get();
      final huerfanos = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final doc in direccionesSnap.docs) {
        final data = doc.data();
        final tid = (data['tarjeta_id'] ?? '').toString().trim();
        if (tid.isNotEmpty && tarjetasActivas.contains(tid)) {
          continue; // Vinculación válida por tarjeta.
        }
        final barrio = (data['barrio'] ?? '').toString().trim().toLowerCase();
        final destino = (data['territorio_destino'] ?? '').toString().trim().toLowerCase();
        final resuelvePorTexto = nombreATerritorioId.containsKey(barrio) ||
            nombreATerritorioId.containsKey(destino);
        if (resuelvePorTexto) continue;

        huerfanos.add(doc);
      }

      if (!mounted) return;
      setState(() => _cargando = false);

      if (huerfanos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin registros huérfanos: todas las direcciones tienen vínculo válido.'),
            backgroundColor: Color(0xFF1B4D2E),
          ),
        );
        return;
      }

      // 3. Confirmación explícita antes de borrar (operación destructiva).
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Limpiar direcciones huérfanas'),
          content: Text(
            'Se encontraron ${huerfanos.length} dirección(es) en "direcciones_globales" '
            'sin vínculo válido a un territorio o tarjeta activa.\n\n'
            'Esta acción las eliminará permanentemente. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmar != true) return;

      // 4. Borrado en lote, respetando el límite de operaciones por batch de
      // Firestore (mismo patrón usado en el resto del panel: commitea y
      // reinicia cada ~400 operaciones).
      setState(() => _cargando = true);
      var batch = _firestore.batch();
      int ops = 0;
      for (final doc in huerfanos) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();

      await _firestore.collection('historial_auditoria').doc().set({
        'accion_tomada': 'limpieza_huerfanos',
        'detalle': '${huerfanos.length} dirección(es) huérfana(s) eliminada(s) de direcciones_globales.',
        'usuario': (widget.usuarioData?['email'] as String?) ?? 'sistema',
        'fecha': FieldValue.serverTimestamp(),
        'icono': Icons.cleaning_services,
      });

      await _cargarConsolaDinamica();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${huerfanos.length} dirección(es) huérfana(s) eliminada(s).'),
            backgroundColor: const Color(0xFF1B4D2E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al limpiar huérfanos: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ======================================================================
  // Flujo de "Nueva dirección": detección de duplicados + asignación manual
  // por cercanía geográfica (con ayuda de Groq para la explicación).
  // ======================================================================

  /// Normaliza texto para comparaciones tolerantes a acentos/mayúsculas/
  /// puntuación (p. ej. "Rúa Capivarí!" -> "rua capivari").
  String _normalizarTexto(String s) {
    var out = s.trim().toLowerCase();
    const acentos = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a',
      'é': 'e', 'ê': 'e',
      'í': 'i',
      'ó': 'o', 'õ': 'o', 'ô': 'o',
      'ú': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    acentos.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  /// Extrae la clave "calle_base|número" de un texto de dirección,
  /// IGNORANDO el complemento (casa/apto/bloco/torre/lote + su número).
  ///
  /// Esta es la señal más fuerte de todo el flujo: dos direcciones con la
  /// misma calle+número son, casi siempre, el MISMO predio/edificio con
  /// varias unidades ("Rua Capivari 461, casa 1" / "... casa 2" / "... casa
  /// 3"). Si ya existe una tarjeta con ese predio, la nueva casa/unidad debe
  /// ir ahí sin importar la distancia geográfica (que además suele ser ~0,
  /// pero puede no coincidir exactamente por el margen de error del
  /// geocodificador de Mapbox).
  String? _extraerClaveVia(String textoCrudo) {
    var t = _normalizarTexto(textoCrudo);
    if (t.isEmpty) return null;
    // Si el complemento aparece ANTES del nombre de la calle (p. ej. "casa 3
    // rua capivari 461"), se descarta su número para no confundirlo con el
    // número de la vía.
    t = t.replaceFirst(
        RegExp(r'^(casa|apto|apartamento|bloco|torre|lote|kitnet|km)\s*\d+\s*'),
        '');
    final match = RegExp(r'^([a-z\s]+?)\s*(\d+)').firstMatch(t);
    if (match == null) return null;
    final calleBase = match.group(1)!.trim();
    final numero = match.group(2)!;
    if (calleBase.length < 3) return null; // evita falsos positivos con texto casi vacío
    return '$calleBase|$numero';
  }

  /// Etiqueta corta del complemento (para mostrar "casa 1, casa 2" en la
  /// explicación), extraída del mismo texto crudo.
  String _extraerComplementoCorto(String textoCrudo, String complementoCampo) {
    if (complementoCampo.trim().isNotEmpty) return complementoCampo.trim();
    final t = _normalizarTexto(textoCrudo);
    final match = RegExp(r'(casa|apto|apartamento|bloco|torre|lote|kitnet)\s*\d+').firstMatch(t);
    return match?.group(0) ?? '';
  }

  /// Distancia en km entre dos coordenadas (fórmula de Haversine).
  double _distanciaKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 12742.0; // 2 * radio de la Tierra en km
    final p = pi / 180;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return r * asin(sqrt(a));
  }

  /// ¿Esta sugerencia ya existe en `direcciones_globales`? Compara por
  /// coordenada redondeada (si la sugerencia trae lat/lng) y por texto
  /// normalizado calle+barrio, contra las firmas cargadas en
  /// `_cargarConsolaDinamica` (sin lecturas adicionales a Firestore).
  bool _esPosibleDuplicado(Map<String, dynamic> item) {
    final calle = _normalizarTexto(
        (item['calle'] ?? item['texto_direccion'] ?? '').toString());
    final barrio = _normalizarTexto((item['barrio'] ?? '').toString());
    if (calle.isNotEmpty &&
        _firmasTextoExistentes.contains('$calle|$barrio')) {
      return true;
    }
    final lat = item['lat'];
    final lng = item['lng'];
    if (lat is num && lng is num) {
      final clave =
          '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
      if (_coordsExistentes.contains(clave)) return true;
    }
    return false;
  }

  /// Elimina una entrada de la bandeja `sugerencias`, previa confirmación.
  /// El mensaje de confirmación se adapta si además se detectó como
  /// probable duplicado de una dirección ya existente.
  Future<void> _eliminarSugerencia(Map<String, dynamic> item) async {
    final calle = (item['calle'] ?? item['texto_direccion'] ?? 'esta dirección').toString();
    final esDuplicado = _esPosibleDuplicado(item);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de la bandeja'),
        content: Text(esDuplicado
            ? '"$calle" ya parece existir en direcciones_globales. '
                '¿Eliminar esta entrada duplicada de la bandeja?'
            : '¿Eliminar "$calle" de la bandeja de nuevas direcciones?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _firestore.collection('sugerencias').doc(item['id']).delete();
      // No hace falta refrescar manualmente: el listener liviano de
      // 'sugerencias' actualiza `_nuevasDireccionesLista` al vuelo.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eliminado de la bandeja.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Busca, entre los puntos de referencia con coordenadas + tarjeta activa
  /// (`_puntosReferencia`, recolectados en `_cargarConsolaDinamica`), el más
  /// cercano a [lat]/[lng]. Esta es la base por CERCANÍA que exige el flujo
  /// de asignación manual.
  Map<String, dynamic>? _buscarPuntoMasCercano(double lat, double lng) {
    Map<String, dynamic>? mejor;
    double mejorDist = double.infinity;
    for (final p in _puntosReferencia) {
      final d = _distanciaKm(lat, lng, p['lat'] as double, p['lng'] as double);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = {...p, 'distancia_km': d};
      }
    }
    return mejor;
  }

  /// Igual que `_buscarPuntoMasCercano`, pero devuelve hasta 2 candidatos de
  /// TARJETAS DISTINTAS (no solo el punto más cercano en general), ordenados
  /// por distancia. Sirve para ofrecer una alternativa real —de otra
  /// tarjeta— cuando el auditor no está de acuerdo con la principal. El
  /// primer elemento siempre coincide con `_buscarPuntoMasCercano`.
  List<Map<String, dynamic>> _buscarDosTarjetasMasCercanas(double lat, double lng) {
    final mejorPorTarjeta = <String, Map<String, dynamic>>{};
    for (final p in _puntosReferencia) {
      final d = _distanciaKm(lat, lng, p['lat'] as double, p['lng'] as double);
      final tid = p['tarjeta_id'] as String;
      final actual = mejorPorTarjeta[tid];
      if (actual == null || d < (actual['distancia_km'] as double)) {
        mejorPorTarjeta[tid] = {...p, 'distancia_km': d};
      }
    }
    final ordenados = mejorPorTarjeta.values.toList()
      ..sort((a, b) =>
          (a['distancia_km'] as double).compareTo(b['distancia_km'] as double));
    return ordenados.take(2).toList();
  }

  /// Direcciones ya existentes (con coordenadas) de una tarjeta, para
  /// mostrarlas en el diagrama de sugerencia junto con su distancia a la
  /// dirección nueva. Se toman de `_puntosReferencia` (ya filtrado a
  /// tarjetas activas con lat/lng reales).
  List<Map<String, dynamic>> _direccionesDeTarjeta(String tarjetaId) {
    return _puntosReferencia.where((p) => p['tarjeta_id'] == tarjetaId).toList();
  }

  /// Formatea una distancia en km como metros (< 1 km) o km con un decimal.
  String _formatDistancia(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  /// Construye el nodo visual "carpeta (territorio) → tarjeta" en estilo
  /// diagrama/flowchart: la tarjeta muestra sus direcciones existentes (con
  /// la distancia aproximada a la dirección nueva) y la dirección nueva
  /// resaltada. [destacado] controla si se pinta como la opción activa
  /// (verde, con glow) o como alternativa atenuada (gris).
  Widget _nodoSugerencia({
    required String territorioNombre,
    required String tarjetaNombre,
    required List<Map<String, dynamic>> direccionesExistentes,
    required String nuevaDireccionTexto,
    required String nuevaComplemento,
    required double? nuevaLat,
    required double? nuevaLng,
    required int cupoActual,
    required bool destacado,
  }) {
    final colorBase = destacado ? const Color(0xFF1B4D2E) : Colors.grey.shade500;
    final colorFondo =
        destacado ? const Color(0xFF1B4D2E).withOpacity(0.06) : Colors.grey.shade50;
    final lleno = cupoActual >= 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Nodo "carpeta" = territorio ---
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: destacado
                    ? [const Color(0xFF1B4D2E), const Color(0xFF2E7D52)]
                    : [Colors.grey.shade400, Colors.grey.shade500],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: destacado
                  ? [
                      BoxShadow(
                          color: const Color(0xFF1B4D2E).withOpacity(0.35),
                          blurRadius: 10,
                          spreadRadius: 1),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open, color: Colors.white, size: 15),
                const SizedBox(width: 6),
                Text(
                  territorioNombre,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ),
        // --- Conector ---
        Center(
          child: Column(
            children: [
              Container(width: 2, height: 9, color: colorBase.withOpacity(0.5)),
              Icon(Icons.arrow_drop_down, color: colorBase.withOpacity(0.7), size: 18),
            ],
          ),
        ),
        // --- Nodo "tarjeta" ---
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorFondo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorBase, width: destacado ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.badge, size: 14, color: colorBase),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      tarjetaNombre,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: destacado ? const Color(0xFF1B4D2E) : Colors.grey.shade700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: lleno ? Colors.red.shade100 : colorBase.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$cupoActual/8',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: lleno ? Colors.red.shade800 : colorBase),
                    ),
                  ),
                ],
              ),
              if (direccionesExistentes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('YA EN ESTA TARJETA',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: direccionesExistentes.take(4).map((d) {
                    String? dist;
                    final dLat = d['lat'];
                    final dLng = d['lng'];
                    if (nuevaLat != null &&
                        nuevaLng != null &&
                        dLat is double &&
                        dLng is double) {
                      dist = _formatDistancia(
                          _distanciaKm(nuevaLat, nuevaLng, dLat, dLng));
                    }
                    final etiqueta =
                        (d['calle'] as String? ?? '?').split(',').first.trim();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        dist != null ? '$etiqueta · $dist' : etiqueta,
                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                      ),
                    );
                  }).toList(),
                ),
                if (direccionesExistentes.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('+${direccionesExistentes.length - 4} más',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  ),
                const SizedBox(height: 8),
              ],
              // --- Dirección nueva, resaltada ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: destacado ? Colors.amber.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: destacado ? Colors.amber.shade700 : Colors.grey.shade400,
                      width: 1.3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.push_pin,
                        size: 14, color: destacado ? Colors.amber.shade800 : Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nuevaDireccionTexto,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 11.5)),
                          if (nuevaComplemento.isNotEmpty)
                            Text(nuevaComplemento,
                                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('NUEVA',
                        style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Abre el flujo de asignación MANUAL para una sugerencia de la bandeja.
  /// Usa 3 niveles de evidencia, de más a menos fuerte:
  ///
  ///  NIVEL 1 — Misma vía (calle+número), ignorando el complemento. Esta es
  ///  la señal más fuerte: si ya existen "Rua Capivari 461, casa 1" y
  ///  "casa 2" en una tarjeta, una nueva "casa 3" del MISMO número debe ir
  ///  en esa misma tarjeta casi con certeza (es el mismo predio/edificio),
  ///  sin importar la distancia geográfica exacta que reporte el
  ///  geocodificador.
  ///  NIVEL 2 — Cercanía geográfica real (Haversine) contra direcciones ya
  ///  colocadas con coordenadas de Mapbox, si el Nivel 1 no encontró nada.
  ///  NIVEL 3 — Si no hay coordenadas ni coincidencia de vía, se le pide a
  ///  Groq una sugerencia basada en el texto (barrio/calle), o se deja
  ///  elegir manualmente.
  ///
  /// En todos los casos se le pide a Groq una explicación en lenguaje
  /// natural adicional (best-effort) para reforzar el motivo mostrado.
  Future<void> _abrirAsignacionManual(Map<String, dynamic> item) async {
    final calle = (item['calle'] ?? item['texto_direccion'] ?? 'Sin calle').toString();
    final barrio = (item['barrio'] ?? '').toString();
    final lat = item['lat'];
    final lng = item['lng'];
    final tieneCoords = lat is num && lng is num;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Buscando la mejor tarjeta...')),
          ],
        ),
      ),
    );

    // --- NIVEL 1: misma vía (calle+número) ya registrada -----------------
    List<Map<String, dynamic>> hermanas = const [];
    Map<String, dynamic>? porVia;
    final claveVia = _extraerClaveVia(calle);
    if (claveVia != null && _direccionesPorVia.containsKey(claveVia)) {
      hermanas = _direccionesPorVia[claveVia]!;
      // Si por algún motivo hay hermanas en más de una tarjeta (dato
      // legado inconsistente), se toma la tarjeta con más coincidencias.
      final conteoPorTarjeta = <String, int>{};
      for (final h in hermanas) {
        final tid = h['tarjeta_id'] as String;
        conteoPorTarjeta[tid] = (conteoPorTarjeta[tid] ?? 0) + 1;
      }
      final tidGanadora =
          conteoPorTarjeta.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      porVia = hermanas.firstWhere((h) => h['tarjeta_id'] == tidGanadora);
    }

    // --- NIVEL 2: cercanía geográfica. Se calcula SIEMPRE que haya
    // coordenadas (no solo cuando el Nivel 1 no encontró nada), porque
    // también sirve como candidata a ALTERNATIVA cuando el Nivel 1 sí
    // encontró algo pero el auditor prefiere ver otra opción cercana.
    final List<Map<String, dynamic>> dosMasCercanas =
        tieneCoords ? _buscarDosTarjetasMasCercanas((lat as num).toDouble(), (lng as num).toDouble()) : const [];
    final Map<String, dynamic>? cercano = dosMasCercanas.isNotEmpty ? dosMasCercanas.first : null;

    // Candidato ganador para esta sugerencia (Nivel 1 tiene prioridad).
    final Map<String, dynamic>? ganador = porVia ?? cercano;
    final bool porMultiCasa = porVia != null;

    // Candidato ALTERNATIVO: la tarjeta cercana más próxima que NO sea la
    // misma que el ganador (así siempre es una opción realmente distinta).
    Map<String, dynamic>? alternativa;
    if (ganador != null) {
      for (final c in dosMasCercanas) {
        if (c['tarjeta_id'] != ganador['tarjeta_id']) {
          alternativa = c;
          break;
        }
      }
    }

    // Nombres legibles del territorio/tarjeta ganadores y de la alternativa.
    String? territorioNombre;
    String? tarjetaNombre;
    String? territorioNombreAlt;
    String? tarjetaNombreAlt;
    int cupoGanador = 0;
    int cupoAlternativa = 0;
    final tMeta = await _catalogo.tarjetaMeta();
    if (ganador != null) {
      final tNombres = await _catalogo.territorioNombre();
      tarjetaNombre = tMeta[ganador['tarjeta_id']]?['nombre']?.toString();
      territorioNombre = tNombres[ganador['territorio_id']];
      cupoGanador = (tMeta[ganador['tarjeta_id']]?['totalDirecciones'] as int?) ?? 0;
    }
    if (alternativa != null) {
      final tNombres = await _catalogo.territorioNombre();
      tarjetaNombreAlt = tMeta[alternativa['tarjeta_id']]?['nombre']?.toString();
      territorioNombreAlt = tNombres[alternativa['territorio_id']];
      cupoAlternativa = (tMeta[alternativa['tarjeta_id']]?['totalDirecciones'] as int?) ?? 0;
    }

    // Direcciones ya existentes de cada tarjeta candidata, para el diagrama.
    final direccionesGanador =
        ganador != null ? _direccionesDeTarjeta(ganador['tarjeta_id'] as String) : const <Map<String, dynamic>>[];
    final direccionesAlternativa = alternativa != null
        ? _direccionesDeTarjeta(alternativa['tarjeta_id'] as String)
        : const <Map<String, dynamic>>[];

    // --- NIVEL 3 / refuerzo: explicación enriquecida con IA (Groq). ------
    // Best-effort: si falla o no hay conexión, se usa solo la explicación
    // local (que ya es sólida en los Niveles 1 y 2).
    String explicacionIA = '';
    if (ganador == null) {
      try {
        final tarjetas = await _catalogo.tarjetasComoLista();
        final decision = await GroqTerritoryService.decidirTarjetaParaDireccion(
          direccion: {
            'calle': calle,
            'complemento': item['complemento'] ?? '',
            'barrio': barrio,
            'lat': lat,
            'lng': lng,
          },
          tarjetasExistentes: tarjetas,
        );
        explicacionIA = (decision['explicacion'] ?? '').toString();
      } catch (_) {
        // Sin IA disponible: se deja solo la explicación local.
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // cierra el loader

    final String explicacionLocal;
    if (porMultiCasa) {
      final ejemplos = hermanas
          .map((h) => (h['complemento'] as String).isNotEmpty
              ? h['complemento'] as String
              : (h['calle'] as String))
          .where((s) => s.isNotEmpty)
          .toSet()
          .take(4)
          .join(', ');
      explicacionLocal = 'Es la mejor opción, y con alta confianza: ya hay '
          '${hermanas.length} dirección(es) registrada(s) en la MISMA calle y '
          'número${ejemplos.isNotEmpty ? ' ($ejemplos)' : ''}, dentro de la '
          'tarjeta "$tarjetaNombre" del territorio "$territorioNombre". '
          'Es casi seguro el mismo predio/edificio con varias unidades, así '
          'que debe ir en esa misma tarjeta sin importar la distancia exacta '
          'que reporte el mapa.';
    } else if (cercano != null) {
      explicacionLocal = 'Es la mejor opción local: la dirección registrada más cercana '
          '("${cercano['calle']}"${(cercano['barrio'] as String).isNotEmpty ? ', ${cercano['barrio']}' : ''}) '
          'está a ${(cercano['distancia_km'] as double).toStringAsFixed(2)} km, '
          'dentro de la tarjeta "$tarjetaNombre" del territorio "$territorioNombre". '
          'Agrupar direcciones cercanas en la misma tarjeta reduce el recorrido del publicador.';
    } else if (tieneCoords) {
      explicacionLocal =
          'No hay direcciones cercanas ni en la misma vía con tarjeta asignada '
          'todavía; no se pudo sugerir una tarjeta local con confianza.';
    } else {
      explicacionLocal =
          'Esta sugerencia no trae coordenadas propias ni coincide con ninguna '
          'vía ya registrada, así que no se pudo calcular una recomendación con '
          'confianza. Elige el territorio/tarjeta manualmente abajo.';
    }

    // Estado local del diálogo: si el auditor tocó "Usar esta alternativa",
    // se destaca ella en vez del ganador original, y "Asignar aquí" apunta
    // a la que esté activa en ese momento.
    bool usarAlternativa = false;
    bool verAlternativa = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final Map<String, dynamic>? activo = usarAlternativa ? alternativa : ganador;
        final String? territorioActivo = usarAlternativa ? territorioNombreAlt : territorioNombre;
        final String? tarjetaActiva = usarAlternativa ? tarjetaNombreAlt : tarjetaNombre;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(porMultiCasa ? 'Misma dirección detectada' : 'Asignación manual'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(calle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (barrio.isNotEmpty)
                    Text(barrio, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                  const SizedBox(height: 14),

                  // --- Diagrama de la opción activa (principal o alternativa) ---
                  if (ganador != null)
                    _nodoSugerencia(
                      territorioNombre: territorioActivo ?? activo!['territorio_id'] as String,
                      tarjetaNombre: tarjetaActiva ?? activo!['tarjeta_id'] as String,
                      direccionesExistentes: usarAlternativa ? direccionesAlternativa : direccionesGanador,
                      nuevaDireccionTexto: calle,
                      nuevaComplemento: (item['complemento'] ?? '').toString(),
                      nuevaLat: tieneCoords ? (lat as num).toDouble() : null,
                      nuevaLng: tieneCoords ? (lng as num).toDouble() : null,
                      cupoActual: usarAlternativa ? cupoAlternativa : cupoGanador,
                      destacado: true,
                    ),

                  if (porMultiCasa && !usarAlternativa) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.home_work, size: 14, color: Color(0xFF1B4D2E)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${hermanas.length} dirección(es) más en el mismo predio',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 12),
                  const Text('¿Por qué es mejor local?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(explicacionLocal, style: const TextStyle(fontSize: 12)),
                  if (explicacionIA.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('IA (Groq): $explicacionIA',
                        style: TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[700])),
                  ],

                  // --- Alternativa colapsable ---
                  if (alternativa != null) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setLocal(() => verAlternativa = !verAlternativa),
                      child: Row(
                        children: [
                          Icon(verAlternativa ? Icons.expand_less : Icons.expand_more,
                              size: 18, color: Colors.grey[700]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              verAlternativa
                                  ? 'Ocultar alternativa'
                                  : 'Ver alternativa: ${tarjetaNombreAlt ?? alternativa['tarjeta_id']} (${_formatDistancia(alternativa['distancia_km'] as double)})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (verAlternativa) ...[
                      const SizedBox(height: 8),
                      _nodoSugerencia(
                        territorioNombre: territorioNombreAlt ?? alternativa['territorio_id'] as String,
                        tarjetaNombre: tarjetaNombreAlt ?? alternativa['tarjeta_id'] as String,
                        direccionesExistentes: direccionesAlternativa,
                        nuevaDireccionTexto: calle,
                        nuevaComplemento: (item['complemento'] ?? '').toString(),
                        nuevaLat: tieneCoords ? (lat as num).toDouble() : null,
                        nuevaLng: tieneCoords ? (lng as num).toDouble() : null,
                        cupoActual: cupoAlternativa,
                        destacado: false,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => setLocal(() => usarAlternativa = !usarAlternativa),
                          icon: Icon(usarAlternativa ? Icons.check_circle : Icons.swap_horiz, size: 16),
                          label: Text(usarAlternativa
                              ? 'Usando la alternativa'
                              : 'Usar esta alternativa'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _abrirSelectorManualTerritorioTarjeta(item);
              },
              child: const Text('Elegir otro territorio/tarjeta'),
            ),
            if (activo != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B4D2E)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _confirmarAsignacionManual(
                    item: item,
                    tarjetaId: activo['tarjeta_id'] as String,
                    territorioId: activo['territorio_id'] as String,
                  );
                },
                child: const Text('Asignar aquí', style: TextStyle(color: Colors.white)),
              ),
          ],
        );
      }),
    );
  }

  /// Selector simple de territorio -> tarjeta cuando el auditor prefiere no
  /// seguir la sugerencia por cercanía (o cuando no había coordenadas para
  /// calcularla).
  Future<void> _abrirSelectorManualTerritorioTarjeta(Map<String, dynamic> item) async {
    final territorios = await _catalogo.territorios();
    final tarjetaMeta = await _catalogo.tarjetaMeta();
    String? territorioSel;
    String? tarjetaSel;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final tarjetasDelTerritorio = territorioSel == null
              ? const <MapEntry<String, Map<String, dynamic>>>[]
              : tarjetaMeta.entries
                  .where((e) => e.value['territorio_id'] == territorioSel)
                  .toList();
          return AlertDialog(
            title: const Text('Elegir territorio y tarjeta'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: territorioSel,
                  decoration: const InputDecoration(labelText: 'Territorio'),
                  items: territorios
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text((t.data()['nombre'] as String?) ?? t.id),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    territorioSel = v;
                    tarjetaSel = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tarjetaSel,
                  decoration: const InputDecoration(labelText: 'Tarjeta'),
                  items: tarjetasDelTerritorio
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value['nombre']?.toString() ?? e.key),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => tarjetaSel = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: (territorioSel != null && tarjetaSel != null)
                    ? () async {
                        Navigator.pop(ctx);
                        await _confirmarAsignacionManual(
                          item: item,
                          tarjetaId: tarjetaSel!,
                          territorioId: territorioSel!,
                        );
                      }
                    : null,
                child: const Text('Asignar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Persiste la sugerencia como una nueva dirección en `direcciones_globales`
  /// con la tarjeta/territorio elegidos manualmente, incrementa el contador
  /// de la tarjeta y elimina la sugerencia de la bandeja.
  Future<void> _confirmarAsignacionManual({
    required Map<String, dynamic> item,
    required String tarjetaId,
    required String territorioId,
  }) async {
    try {
      final batch = _firestore.batch();
      final ref = _firestore.collection('direcciones_globales').doc();
      batch.set(ref, {
        'calle': item['calle'] ?? item['texto_direccion'] ?? '',
        'complemento': item['complemento'] ?? '',
        'barrio': item['barrio'] ?? '',
        'tarjeta_id': tarjetaId,
        'territorio_id': territorioId,
        'estado_predicacion': 'pendiente',
        if (item['lat'] != null) 'lat': item['lat'],
        if (item['lng'] != null) 'lng': item['lng'],
        'origen': 'Asignación manual (Auditor)',
        'creado_el': FieldValue.serverTimestamp(),
      });
      batch.update(
        _firestore
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(tarjetaId),
        {'totalDirecciones': FieldValue.increment(1)},
      );
      if (item['id'] != null) {
        batch.delete(_firestore.collection('sugerencias').doc(item['id']));
      }
      await batch.commit();
      _catalogo.invalidar();

      await _firestore.collection('historial_auditoria').doc().set({
        'accion_tomada': 'asignacion_manual',
        'direccion_ingresada': item['calle'] ?? item['texto_direccion'] ?? '',
        'territorio': territorioId,
        'tarjeta_nombre': tarjetaId,
        'usuario': (widget.usuarioData?['email'] as String?) ?? 'sistema',
        'fecha': FieldValue.serverTimestamp(),
        'icono': Icons.touch_app,
      });

      await _cargarConsolaDinamica();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección asignada manualmente.'),
            backgroundColor: Color(0xFF1B4D2E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al asignar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Auto-Asignar una nueva dirección a la tarjeta global
  Future<void> _aprobarYProcesarAutomatica(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final String textoDireccion =
        (data['texto_direccion'] as String?)?.trim() ?? '';
    final String calleRaw =
        (data['calle'] as String?)?.trim() ?? textoDireccion;
    final String barrio = (data['barrio'] as String?)?.trim() ?? '';
    final String complemento = (data['complemento'] as String?) ?? '';

    final email = (widget.usuarioData?['email'] as String?) ?? 'sistema';

    // Procesar la dirección con el AutoAsignadorService: IA decide la tarjeta
    // óptima, crea tarjeta/territorio si hace falta, guarda en
    // direcciones_globales, actualiza contador, historial y notificación.
    try {
      final resultado = await AutoAsignadorService.procesarDireccionNueva(
        nuevaDireccion: {
          'calle': calleRaw,
          'complemento': complemento,
          'barrio': barrio,
          'texto_direccion': textoDireccion,
        },
        usuarioEmail: email,
      );
      // Si la dirección no pudo colocarse (no es real según Mapbox, o no hay
      // ningún territorio existente donde ubicarla), NO se borra de la bandeja:
      // se queda para revisión del auditor.
      final decision = (resultado['decision'] as String?) ?? '';
      if (decision.isNotEmpty) {
        final motivo = (resultado['explicacion'] as String?) ?? 'Sin motivo.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dirección no colocada ($decision): $motivo'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      _autoProcesadas.add(doc.id);
      await doc.reference.delete();
      _cargarConsolaDinamica();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección colocada automáticamente en su mejor ubicación.'),
            backgroundColor: Color(0xFF1B4D2E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al auto-colocar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleAutoAsignacion(bool valor) async {
    setState(() => _autoAsignacionActiva = valor);
    await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('auditoria')
        .set({'auto_asignacion': valor}, SetOptions(merge: true));

    // Al activar el modo automático, procesar de inmediato las sugerencias
    // pendientes de la bandeja.
    if (valor) {
      try {
        final snap = await _firestore
            .collection('sugerencias')
            .where('estado', isEqualTo: 'PENDIENTE_AUDITORIA')
            .get();
        final pendientes = snap.docs
            .where((d) => !_autoProcesadas.contains(d.id))
            .toList();
        if (pendientes.isNotEmpty) {
          _autoProcesarSugerencias(pendientes);
        }
      } catch (_) {}
    }
  }

  Future<void> _cargarEstadoAutoAsignacion() async {
    try {
      final doc = await _firestore
          .collection('configuracion')
          .doc('auditoria')
          .get();
      if (doc.exists && mounted) {
        final valor = doc.data()?['auto_asignacion'] as bool?;
        if (valor != null) setState(() => _autoAsignacionActiva = valor);
      }
    } catch (_) {}
  }

  /// Organiza texto desordenado pegado (p. ej. chat de WhatsApp) con la IA y
  /// lo procesa: en modo automático coloca directo; en manual muestra un
  /// preview para aprobar antes de guardar.
  Future<void> _organizarTextoPegado() async {
    final texto = _textoPegadoController.text.trim();
    if (texto.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Pega el texto con las direcciones primero.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final email = (widget.usuarioData?['email'] as String?) ?? 'sistema';

    // Loader mientras la IA organiza el texto.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
                child:
                    Text('La IA está organizando las direcciones del texto...')),
          ],
        ),
      ),
    );

    List<Map<String, dynamic>> direcciones;
    try {
      // 1. La IA extrae y organiza las direcciones del texto pegado.
      final extraidas = await GroqTerritoryService.extraerDireccionesWhatsApp(
          textoWhatsApp: texto);
      direcciones = extraidas.map((e) {
        final calle = (e['direccion'] ?? '').toString().trim();
        return {
          'calle': calle,
          'numero': (e['numero'] ?? '').toString().trim(),
          'complemento': (e['observaciones'] ?? '').toString().trim(),
          'barrio': (e['barrio'] ?? '').toString().trim(),
          'casas_detectadas': e['casas_detectadas'] ?? 1,
          'texto_direccion': calle,
        };
      }).toList();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al organizar: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context); // Cierra loader.

    if (direcciones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('La IA no encontró direcciones claras en el texto.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // 2. Decidir según el modo.
    if (_autoAsignacionActiva) {
      await _procesarDireccionesConIA(direcciones, email, texto);
    } else {
      await _mostrarPreviewYProcesar(direcciones, email, texto);
    }
  }

  /// Procesa de inmediato (modo automático).
  Future<void> _procesarDireccionesConIA(
      List<Map<String, dynamic>> direcciones, String email, String texto) async {
    try {
      final resumen = await AutoAsignadorService.procesarLoteDirecciones(
        direcciones: direcciones,
        usuarioEmail: email,
      );
      _textoPegadoController.clear();
      _cargarConsolaDinamica();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Modo automático: ${resumen['procesadas']} dirección(es) colocada(s). '
                '${(resumen['errores'] as List).length} error(es).'),
            backgroundColor: const Color(0xFF1B4D2E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Muestra un preview de las direcciones organizadas para aprobación
  /// (modo manual). Al aprobar, las procesa.
  Future<void> _mostrarPreviewYProcesar(
      List<Map<String, dynamic>> direcciones, String email, String texto) async {
    final aprobar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Direcciones organizadas (${direcciones.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('La IA interpretó el texto así. Aprueba para colocar:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const Divider(),
                  ...direcciones.map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${d['calle']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              if ((d['complemento'] ?? '').toString().isNotEmpty)
                                Text('Complemento: ${d['complemento']}',
                                    style: const TextStyle(fontSize: 11)),
                              if ((d['barrio'] ?? '').toString().isNotEmpty)
                                Text('Barrio: ${d['barrio']}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueGrey.shade600)),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Descartar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text('Aprobar y colocar (${direcciones.length})'),
            ),
          ],
        );
      },
    );

    if (aprobar != true || !mounted) return;
    await _procesarDireccionesConIA(direcciones, email, texto);
  }

  void _solicitarPlanInteligente(List<Map<String, dynamic>> sugerencias) async {
    // 1. Ventana de progreso con tiempo transcurrido y restante estimado.
    //    La reorganización no es rápida: puede tardar entre 1 y 5+ minutos
    //    (el plan free de Groq limita tokens por minuto, por eso se trocea
    //    en lotes). No se usa timeout corto.
    final progreso = _ProgresoReorg(total: 1, lote: 1, segLote: 0.0);
    final stopwatch = Stopwatch()..start();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          progreso.onUpdate = () {
            if (mounted) setStateDialog(() {});
          };
          return _construirVentanaProgreso(progreso, stopwatch);
        },
      ),
    );

    // Refresca el contador de tiempo transcurrido cada segundo para que la
    // ventana de progreso muestre el avance en vivo mientras la IA procesa.
    final refrescaTiempo = Timer.periodic(const Duration(seconds: 1), (_) {
      progreso.onUpdate?.call();
    });

    try {
      // Obtener snapshot de tarjetas actuales (subcolección canónica)
      final tarjetas =
          await _cargarTodasTarjetas(FirebaseFirestore.instance);

      progreso.total =
          (sugerencias.length / 40).ceil().clamp(1, 999999);
      progreso.onUpdate?.call();

      // 2. Consulta a la API de Groq (payload compacto y en lotes para no
      //    exceder el ToKens Per Minute del plan free " el "413" de Groq es
      //    realmente un límite de TPM).
      final plan = await _pedirPlanCompleto(
        sugerencias,
        tarjetas,
        onProgresoLote: (loteActual, totalLotes, segPorLote) {
          progreso.lote = loteActual;
          progreso.total = totalLotes;
          progreso.segLote = segPorLote;
          progreso.onUpdate?.call();
        },
      );

      stopwatch.stop();
      refrescaTiempo.cancel();
      if (mounted) Navigator.pop(context); // Cierra ventana de progreso

      // 3. Enriquecer el plan con análisis LOCAL determinista (duplicados
      //    considerando complemento, más robusto que solo la IA)
      final planEnriquecido = _enriquecerPlan(plan, tarjetas);

      if (mounted) {
        // 4. Modal de previsualización completa del plan, con confirmación y
        //    espacio para una sugerencia del usuario antes de aplicar.
        final sugerencia =
            await _mostrarPreviewPlan(planEnriquecido, sugerencias);
        if (sugerencia != null && mounted) {
          await _aplicarPlanEnFirestore(planEnriquecido, sugerencias,
              sugerenciaUsuario: sugerencia);
        }
      }
    } catch (e) {
      refrescaTiempo.cancel();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Construye la ventana de progreso de la reorganización con el tiempo
  /// transcurrido y el tiempo restante estimado (que puede superar 5 min).
  Widget _construirVentanaProgreso(_ProgresoReorg p, Stopwatch sw) {
    final transcurrido = sw.elapsedMilliseconds / 1000.0;
    final lote = p.lote;
    final total = p.total;
    final restantes = total - lote;

    String restanteStr = 'calculando...';
    if (p.segLote > 0 && restantes > 0) {
      final segRest = p.segLote * restantes;
      restanteStr = '~${_formatearSegundos(segRest)}';
    }

    final avance = total <= 0 ? 0.0 : (lote / total).clamp(0.0, 1.0);

    // Ancho responsive: hasta 360px en pantallas anchas, pero nunca más del
    // 90% del ancho disponible (evita overflow en celulares angostos).
    final anchoDialogo =
        (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 360.0);

    return AlertDialog(
      content: SizedBox(
        width: anchoDialogo,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'El motor de IA está analizando y reorganizando las direcciones...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: avance,
              backgroundColor: Colors.grey.shade300,
              color: const Color(0xFF1B4D2E),
            ),
            const SizedBox(height: 12),
            Text(
              'Lote $lote de $total',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Tiempo transcurrido: ${_formatearSegundos(transcurrido)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            Text(
              'Tiempo restante estimado: $restanteStr',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Text(
              'Esto puede tardar entre 1 y 5 minutos o más, sin prisa. '
              'No cierres esta ventana mientras procesa.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orange.shade800),
            ),
          ],
        ),
      ),
    );
  }

  String _formatearSegundos(double seg) {
    final s = seg.round().clamp(0, 359999);
    final m = (s ~/ 60);
    final ss = (s % 60).toString().padLeft(2, '0');
    return '${m}m ${ss}s';
  }

  /// Pide el plan de la IA en lotes de a pocas sugerencias y combina los
  /// resultados. Evita el error de límite de tokens por minuto de Groq.
  ///
  /// `onProgresoLote` se invoca con (loteActual, totalLotes, segundosPorLote)
  /// para que la UI muestre el avance y el tiempo restante estimado.
  Future<Map<String, dynamic>> _pedirPlanCompleto(
    List<Map<String, dynamic>> sugerencias,
    List<Map<String, dynamic>> tarjetas, {
    void Function(int loteActual, int totalLotes, double segPorLote)? onProgresoLote,
  }) async {
    const int lote = 100;

    // Merge de listas de planes en uno consolidado.
    Map<String, dynamic> combinar(List<Map<String, dynamic>> planes) {
      final resultado = <String, dynamic>{};
      final listas = <String>[
        'tarjetas_a_eliminar',
        'tarjetas_a_crear_o_actualizar',
        'desglose_por_barrio',
        'direcciones_duplicadas',
        'movimientos',
        'estado_final',
      ];
      final narrativas = <String>[];
      for (var p in planes) {
        final nar = p['explicacion_narrativa']?.toString();
        if (nar != null && nar.isNotEmpty) narrativas.add(nar);
        for (final k in listas) {
          final lista = p[k];
          if (lista is List) {
            final acc = resultado[k];
            if (acc is List) {
              acc.addAll(lista);
            } else {
              resultado[k] = List<dynamic>.from(lista);
            }
          }
        }
        if (p['territorio_nuevo_sugerido'] is Map && resultado['territorio_nuevo_sugerido'] == null) {
          resultado['territorio_nuevo_sugerido'] = p['territorio_nuevo_sugerido'];
        }
      }
      resultado['explicacion_narrativa'] = narrativas.join('\n\n');
      return resultado;
    }

    // Si cabe en un lote, un solo request.
    if (sugerencias.length <= lote) {
      onProgresoLote?.call(1, 1, 0);
      final stopwatch = Stopwatch()..start();
      final plan = await GroqTerritoryService.analizarYPlanificarReorganizacion(
        sugerencias: sugerencias,
        tarjetasActuales: tarjetas,
      );
      stopwatch.stop();
      onProgresoLote?.call(1, 1,
          stopwatch.elapsedMilliseconds / 1000.0);
      return plan;
    }

    // Procesar por lotes.
    final totalLotes =
        (sugerencias.length / lote).ceil();
    final planes = <Map<String, dynamic>>[];
    final demoras = <double>[];
    for (int i = 0; i < sugerencias.length; i += lote) {
      final loteActual = (i ~/ lote) + 1;
      final chunk = sugerencias.sublist(i, (i + lote) > sugerencias.length ? sugerencias.length : i + lote);
      onProgresoLote?.call(loteActual, totalLotes,
          demoras.isEmpty ? 0 : (demoras.reduce((a, b) => a + b) / demoras.length));
      final stopwatch = Stopwatch()..start();
      planes.add(await GroqTerritoryService.analizarYPlanificarReorganizacion(
        sugerencias: chunk,
        tarjetasActuales: tarjetas,
      ));
      stopwatch.stop();
      demoras.add(stopwatch.elapsedMilliseconds / 1000.0);
      onProgresoLote?.call(loteActual, totalLotes,
          demoras.reduce((a, b) => a + b) / demoras.length);
    }
    return combinar(planes);
  }

  /// Análisis LOCAL y determinista para reforzar el plan de la IA:
  /// detecta duplicados considerando el complemento (misma calle+número+barrio
  /// con complemento distinto NO es duplicado) y calcula el estado final.
  Map<String, dynamic> _enriquecerPlan(
      Map<String, dynamic> plan, List<Map<String, dynamic>> tarjetas) {
    // Normalizador de "clave de dirección" que ignora el complemento.
    String claveSinComplemento(Map<String, dynamic> d) {
      final calle =
          ((d['calle'] ?? d['direccion'] ?? d['texto_direccion'] ?? '') as String)
              .trim()
              .toLowerCase();
      final numero = ((d['numero'] ?? '') as String).trim().toLowerCase();
      final barrio = ((d['barrio'] ?? '') as String).trim().toLowerCase();
      return '$calle|$numero|$barrio';
    }

    final duplicadosLocales = <Map<String, dynamic>>[];
    final vistos = <String, String>{};

    // Analizar sobre direcciones globales + nuevas sugerencias de la bandeja.
    final todas = <Map<String, dynamic>>[
      ..._nuevasDireccionesLista,
      ..._sugerenciasLista.map((s) => s).toList(),
    ];

    for (final d in todas) {
      final clave = claveSinComplemento(d);
      final id = (d['id'] ?? '').toString();
      final complemento = ((d['complemento'] ?? '') as String).trim();

      if (vistos.containsKey(clave)) {
        // Solo marcar duplicado si el complemento también coincide o falta.
        final primerComplemento = vistos[clave] ?? '';
        if (complemento.isEmpty || complemento == primerComplemento) {
          duplicadosLocales.add({
            'id': id,
            'calle': d['calle'] ?? d['direccion'] ?? d['texto_direccion'] ?? '',
            'barrio': d['barrio'] ?? '',
            'complemento': complemento,
            'motivo': 'Duplicado (mismo domicilio y complemento)',
          });
        }
      } else {
        vistos[clave] = complemento;
      }
    }

    return {
      ...plan,
      'direcciones_duplicadas': duplicadosLocales,
    };
  }

  /// Modal de previsualización del plan completo. Espera confirmación del
  /// usuario y permite ingresar una sugerencia/override antes de aplicar.
  Future<String?> _mostrarPreviewPlan(
      Map<String, dynamic> plan, List<Map<String, dynamic>> sugerencias) {
    final sugerenciaCtrl = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.map_outlined, color: Colors.teal),
              SizedBox(width: 8),
              Expanded(
                child: Text("Plan de Reorganización",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _sec('Resumen del motor IA'),
                Text(
                  plan['explicacion_narrativa']?.toString() ??
                      'Sin explicación.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const Divider(height: 24),

                // Duplicados a eliminar
                _sec('Direcciones duplicadas a eliminar (${_len(plan, 'direcciones_duplicadas')})'),
                if (_length(plan, 'direcciones_duplicadas') == 0)
                  const Text('" Ninguna detectada (se consideró el complemento).',
                      style: TextStyle(fontSize: 12, color: Colors.green))
                else
                  ...(_items(plan, 'direcciones_duplicadas')).map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '" ${d['calle']} · ${d['barrio']}'
                          '${(d['complemento'] as String? ?? '').isNotEmpty ? ' · ${d['complemento']}' : ''}'
                          ' " ${d['motivo']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                const Divider(height: 24),

                // Movimientos
                _sec('Movimientos de direcciones (${_len(plan, 'movimientos')})'),
                if (_length(plan, 'movimientos') == 0)
                  const Text('" Sin movimientos especificados.',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...(_items(plan, 'movimientos')).map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          "${m['calle']} · ${m['barrio']} > ${m['hacia_tarjeta'] ?? '?'}",
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                const Divider(height: 24),

                // Tarjetas a crear/actualizar
                _sec('Tarjetas a crear / actualizar (${_len(plan, 'tarjetas_a_crear_o_actualizar')})'),
                ...(_items(plan, 'tarjetas_a_crear_o_actualizar')).map((t) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '" ${t['nombre'] ?? '?'} (${t['direccionesCount'] ?? 0} dirs)'
                        '${(t['nueva'] == true) ? ' " NUEVA' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                const Divider(height: 24),

                // Tarjetas a eliminar
                _sec('Tarjetas a eliminar (${_len(plan, 'tarjetas_a_eliminar')})'),
                ...(_items(plan, 'tarjetas_a_eliminar')).map((t) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        "${t['nombre'] ?? t['id']}",
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    )),
                const Divider(height: 24),

                // Territorio nuevo sugerido
                _sec('Territorio nuevo sugerido'),
                Text(
                  (plan['territorio_nuevo_sugerido'] is Map &&
                          plan['territorio_nuevo_sugerido']?['nombre'] != null)
                      ? '" ${plan['territorio_nuevo_sugerido']['nombre']} " ${plan['territorio_nuevo_sugerido']['motivo']}'
                      : '" No se sugiere territorio nuevo.',
                  style: const TextStyle(fontSize: 12),
                ),
                const Divider(height: 24),

                // Estado final
                _sec('Cómo quedará (estado final)'),
                if (_length(plan, 'estado_final') == 0)
                  const Text('" El estado final se actualizará en Firestore.',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...(_items(plan, 'estado_final')).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '" ${e['tarjeta_nombre']}: ${e['direcciones']} dirs'
                          '${e['creada_o_eliminada'] != 'ninguna' ? ' (${e['creada_o_eliminada']})' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                const Divider(height: 24),

                // Campo de sugerencia del usuario
                _sec('Sugerencia del auditor (opcional)'),
                TextField(
                  controller: sugerenciaCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText:
                        'Ej: no eliminar la Rua Teste Casa 2, crear 2 tarjetas en el barrio X, etc.',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cancelar
              },
              child: const Text("Cancelar"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () {
                Navigator.pop(context, sugerenciaCtrl.text.trim());
              },
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text("Confirmar y Aplicar"),
            ),
          ],
        );
      },
    );
  }

  Widget _sec(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );

  int _length(Map<String, dynamic> plan, String clave) =>
      (plan[clave] as List?)?.length ?? 0;

  int _len(Map<String, dynamic> plan, String clave) =>
      (plan[clave] as List?)?.length ?? 0;

  List<Map<String, dynamic>> _items(Map<String, dynamic> plan, String clave) {
    final lista = plan[clave];
    if (lista is List) {
      return lista
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : {'valor': e})
          .toList();
    }
    return const [];
  }

  Future<void> _aplicarPlanEnFirestore(
    Map<String, dynamic> plan,
    List<Map<String, dynamic>> sugerenciasProcesadas, {
    String? sugerenciaUsuario,
  }) async {
    final firestore = FirebaseFirestore.instance;
    var batch = firestore.batch();
    int ops = 0;

    /// Nombre -> (id, territorio) de las tarjetas ya existentes en la
    /// subcolección canónica, para actualizar en vez de crear duplicados
    /// (la IA puede inventar IDs ficticios).
    final tarjetasExistentesPorNombre = <String, Map<String, String>>{};
    {
      final canonicas = await _cargarTodasTarjetas(firestore);
      for (final t in canonicas) {
        final nombre = t['nombre']?.toString() ?? '';
        if (nombre.isNotEmpty) {
          tarjetasExistentesPorNombre[nombre] = {
            'id': t['id'].toString(),
            'territorio_id': t['territorio_id']?.toString() ?? '',
          };
        }
      }
    }

    /// Reintenta commitear el batch cuando alcanza ~400 operaciones: commitea,
    /// reasigna una instancia nueva de WriteBatch y reinicia el contador.
    Future<void> commitSiNecesario() async {
      if (ops >= 400) {
        await batch.commit();
        batch = firestore.batch();
        ops = 0;
      }
    }

    // 1. Eliminar tarjetas indicadas por la IA (en la subcolección del
    //    territorio; allí el doc id de una tarjeta ES su nombre).
    final tarjetasAEliminar = (plan['tarjetas_a_eliminar'] as List?) ?? [];
    for (var t in tarjetasAEliminar) {
      if (t is! Map) continue;
      final nombre = (t['id'] ?? t['nombre'])?.toString() ?? '';
      if (nombre.isEmpty) continue;
      final terPlan = (t['territorioId'] ?? t['territorio_id'])?.toString() ?? '';
      final terr = terPlan.isNotEmpty
          ? terPlan
          : (tarjetasExistentesPorNombre[nombre]?['territorio_id'] ?? '');
      if (terr.isEmpty) continue;
      batch.delete(
        firestore
            .collection('territorios')
            .doc(terr)
            .collection('tarjetas')
            .doc(nombre),
      );
      ops++;
      await commitSiNecesario();
    }

    // 2. Eliminar las direcciones duplicadas detectadas (manteniendo una).
    final duplicados = (plan['direcciones_duplicadas'] as List?) ?? [];
    for (var d in duplicados) {
      if (d is Map && d['id'] != null) {
        final ref =
            firestore.collection('direcciones_globales').doc(d['id'].toString());
        batch.delete(ref);
        ops++;
        await commitSiNecesario();
      }
    }

    // 3. Crear/actualizar tarjetas según el plan (sin duplicar existentes).
    final tarjetasNuevas =
        (plan['tarjetas_a_crear_o_actualizar'] as List?) ?? [];
    for (var t in tarjetasNuevas) {
      if (t is! Map || t['nombre'] == null) continue;
      final nombre = t['nombre'].toString();
      final dirs = (t['direccionesCount'] is num) ? t['direccionesCount'] : 0;
      final terPlan = (t['territorioId'] ?? t['territorio_id'])?.toString() ?? '';
      final territorio = terPlan.isNotEmpty
          ? terPlan
          : (tarjetasExistentesPorNombre[nombre]?['territorio_id'] ?? '');
      if (territorio.isEmpty) continue;

      final ref = firestore
          .collection('territorios')
          .doc(territorio)
          .collection('tarjetas')
          .doc(nombre);

      // Si ya existe una tarjeta con ese nombre, actualízala en vez de crear.
      final existia = tarjetasExistentesPorNombre.containsKey(nombre);
      if (existia) {
        batch.update(ref, {
          'totalDirecciones': FieldValue.increment(dirs is int ? dirs : 0),
          'sugerencia_auditor': sugerenciaUsuario ?? '',
          'actualizado_por_ia': true,
          'updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        batch.set(ref, {
          'nombre': nombre,
          'territorio_id': territorio,
          'totalDirecciones': dirs,
          'creado_por_ia': true,
          'sugerencia_auditor': sugerenciaUsuario ?? '',
          'created_at': FieldValue.serverTimestamp(),
        });
        // Registrar el nuevo doc para no duplicar en el mismo plan.
        tarjetasExistentesPorNombre[nombre] = {
          'id': nombre,
          'territorio_id': territorio,
        };
      }
      ops++;
      await commitSiNecesario();
    }

    // 4. Eliminar las sugerencias ya procesadas de la bandeja.
    for (var sug in sugerenciasProcesadas) {
      if (sug['id'] != null) {
        batch.delete(firestore.collection('sugerencias').doc(sug['id']));
        ops++;
        await commitSiNecesario();
      }
    }

    try {
      await batch.commit();
      // El plan pudo crear, editar o eliminar tarjetas: invalidar la caché
      // compartida de territorios/tarjetas.
      _catalogo.invalidar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar el plan: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 5. Registrar auditoría completa en el Historial.
    await firestore.collection('historial_reorganizaciones').add({
      'fecha': FieldValue.serverTimestamp(),
      'usuario': (widget.usuarioData?['email'] as String?) ?? 'Auditor',
      'totalDireccionesProcesadas': sugerenciasProcesadas.length,
      'resumenIA': plan['explicacion_narrativa'],
      'desglose': plan['desglose_por_barrio'],
      'tarjetasEliminadasCount': tarjetasAEliminar.length,
      'sugerencia_auditor': sugerenciaUsuario ?? '',
      'duplicadosEliminados':
          ((plan['direcciones_duplicadas'] as List?) ?? []).length,
      'movimientos': plan['movimientos'],
    });

    setState(() {
      _sugerenciasSeleccionadas.clear();
    });
    _cargarConsolaDinamica();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Proceso completado! Se actualizó la estructura y se guardó en el historial.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151821),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4D2E),
        title: const Text(
          'Consola de Control y Auditoría',
          style: TextStyle(color: Colors.white, fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        actions: _buildAppBarActions(context),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: MediaQuery.of(context).size.width < _anchoAngostoBreakpoint,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Sugerencias (${_sugerenciasSeleccionadas.length})'),
            Tab(text: 'Nuevas Direcciones ($_totalNuevasDirecciones)'), // Reemplazado aquí
            Tab(text: 'Matriz Grid (${_tarjetasMatriz.length})'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Column(
              children: [
                // KPI Header Dinámico
                Container(
                  color: const Color(0xFF1B4D2E),
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildInteractiveKpiCard('$_totalSugerencias', 'Sugerencias', Colors.teal.shade100, Colors.teal, () {
                        _tabController.animateTo(0);
                      }),
                      const SizedBox(width: 8),
                      // KPI de Nuevas Direcciones (Reemplazado)
                      _buildInteractiveKpiCard('$_totalNuevasDirecciones', 'Nuevas Direcciones', Colors.blue.shade100, Colors.blue.shade900, () {
                        _tabController.animateTo(1);
                      }),
                      const SizedBox(width: 8),
                      _buildInteractiveKpiCard('$_saturadasCount', 'Saturadas (>8)', Colors.red.shade100, Colors.red.shade900, () {
                        _tabController.animateTo(2);
                      }),
                      const SizedBox(width: 8),
                      _buildInteractiveKpiCard('${_reglasProtegidas.length}', 'Reglas Activas', Colors.amber.shade100, Colors.amber.shade900, _abrirReglasActivas),
                    ],
                  ),
                ),

                // Progreso Mensual (Requerimiento 3): Completadas / Existentes,
                // calculado exclusivamente sobre el universo de tarjetas activas.
                Container(
                  color: const Color(0xFF1B4D2E),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Progreso mensual',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Flexible(
                            child: Text(
                              '$_direccionesCompletadas / $_direccionesExistentes  '
                              '(${(_porcentajeProgresoMensual * 100).toStringAsFixed(0)}%)'
                              '${_direccionesSinVinculo > 0 ? '  ·  ${_direccionesSinVinculo} sin vínculo' : ''}',
                              style: const TextStyle(
                                  color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _porcentajeProgresoMensual,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.amber),
                        ),
                      ),
                    ],
                  ),
                ),

                // Reglas Protegidas
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Text('Reglas Protegidas: ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _reglasProtegidas.map((tag) => Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: InkWell(
                                onTap: () => _abrirReglasActivas(tag),
                                borderRadius: BorderRadius.circular(16),
                                child: Chip(
                                  backgroundColor: Colors.amber.shade100,
                                  label: Text(tag, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  onDeleted: () {
                                    setState(() => _reglasProtegidas.remove(tag));
                                    _cargarConsolaDinamica();
                                  },
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        height: 32,
                        child: TextField(
                          controller: _nuevoFiltroController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: '+ Filtro...',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              setState(() => _reglasProtegidas.add(val.trim().toUpperCase()));
                              _nuevoFiltroController.clear();
                              _cargarConsolaDinamica();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: _escanenandoZona
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  backgroundColor: const Color(0xFF1B4D2E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: _escanearZonaConMapbox,
                                icon: const Icon(Icons.travel_explore, size: 16),
                                label: const Text('Escanear Zona con IA/Mapbox', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ],
                  ),
                ),

                // Vistas Dinámicas
                Expanded(
                  child: Container(
                    color: const Color(0xFFF2F4F3),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // 1. Bloques de Sugerencias
                        _buildBloquesSugerenciasTab(),

                        // 2. Bloques Dinámicos de Nuevas Direcciones (Reemplazado)
                        _buildBloquesNuevasDireccionesTab(),

                        // 3. Matriz Grid
                        _buildMatrizGridTab(),
                      ],
                    ),
                  ),
                ),

                // Botón Global de Acción
                Container(
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.white,
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar Operación'),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          side: const BorderSide(color: Color(0xFF1B4D2E)),
                        ),
                        onPressed: _abrirHistorialDetallado,
                        icon: const Icon(Icons.history, color: Color(0xFF1B4D2E)),
                        label: const Text('Histórico',
                            style: TextStyle(color: Color(0xFF1B4D2E))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B4D2E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed:
                            _sugerenciasSeleccionadas.isEmpty || !_iaConectada
                                ? null
                                : () {
                                    final seleccionadas = _sugerenciasLista
                                        .where((s) => _sugerenciasSeleccionadas
                                            .contains(s['id']))
                                        .toList();
                                    _solicitarPlanInteligente(seleccionadas);
                                  },
                        icon: const Icon(Icons.flash_on, color: Colors.amber),
                        label: Text('EJECUTAR REORGANIZACIÓN (${_sugerenciasSeleccionadas.length})'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInteractiveKpiCard(String valor, String titulo, Color bg, Color textCol, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
              const SizedBox(height: 2),
              Text(
                titulo,
                style: TextStyle(fontSize: 10, color: textCol),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBloquesSugerenciasTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade200,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Seleccionadas: ${_sugerenciasSeleccionadas.length} / ${_sugerenciasLista.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_sugerenciasSeleccionadas.length == _sugerenciasLista.length) {
                      _sugerenciasSeleccionadas.clear();
                    } else {
                      _sugerenciasSeleccionadas = _sugerenciasLista.map((e) => e['id'] as String).toSet();
                    }
                  });
                },
                child: Text(_sugerenciasSeleccionadas.length == _sugerenciasLista.length ? 'Desmarcar Todas' : 'Marcar Todas'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisExtent: 95,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _sugerenciasLista.length,
            itemBuilder: (context, i) {
              final item = _sugerenciasLista[i];
              final String id = item['id'];
              final bool estaMarcada = _sugerenciasSeleccionadas.contains(id);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (estaMarcada) {
                      _sugerenciasSeleccionadas.remove(id);
                    } else {
                      _sugerenciasSeleccionadas.add(id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: estaMarcada ? Colors.teal.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: estaMarcada ? Colors.teal : Colors.grey.shade300,
                      width: estaMarcada ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: estaMarcada,
                        activeColor: Colors.teal,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _sugerenciasSeleccionadas.add(id);
                            } else {
                              _sugerenciasSeleccionadas.remove(id);
                            }
                          });
                        },
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item['calle'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('Barrio: ${item['barrio']}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Bloques Dinámicos para Entrada de Nuevas Direcciones
  Widget _buildBloquesNuevasDireccionesTab() {
    return Column(
      children: [
        // Switch Asignación Automática / Manual
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _autoAsignacionActiva ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _autoAsignacionActiva ? Colors.green : Colors.grey.shade400,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _autoAsignacionActiva ? Icons.flash_on : Icons.touch_app,
                    color: _autoAsignacionActiva ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _autoAsignacionActiva ? 'Modo: Automático' : 'Modo: Manual',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _autoAsignacionActiva ? Colors.green.shade900 : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _autoAsignacionActiva,
                    activeColor: Colors.green,
                    onChanged: (val) => _toggleAutoAsignacion(val),
                  ),
                ],
              ),
            ),
          ),
        ),
        // El cuadro de "pegar direcciones desordenadas" se eliminó de acá:
        // ya existe el mismo flujo (organizado por Groq) en el botón
        // "Carga Masiva desde WhatsApp" de la barra superior, que abre
        // WhatsAppIngestionDialog. Tenerlo duplicado acá generaba confusión
        // visual y dos caminos distintos para lo mismo.

        Expanded(
          child: _nuevasDireccionesLista.isEmpty
              ? const Center(child: Text('No hay nuevas direcciones en la bandeja.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 110,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _nuevasDireccionesLista.length,
                  itemBuilder: (context, i) {
                    final item = _nuevasDireccionesLista[i];
                    final String barrio = item['barrio'] ?? 'Sin barrio';
                    final String calle = item['calle'] ??
                        item['texto_direccion'] ??
                        'Sin calle';
                    final bool esDuplicado = _esPosibleDuplicado(item);

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: esDuplicado
                            ? const BorderSide(color: Colors.redAccent, width: 1.4)
                            : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    barrio,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _eliminarSugerencia(item),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2.0),
                                    child: Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                            Text(calle, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (esDuplicado)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red.shade700),
                                    const SizedBox(width: 3),
                                    Text('Posible duplicado',
                                        style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  onTap: () => _abrirAsignacionManual(item),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Text('Manual', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(60, 24),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onPressed: () async {
                                    final doc = await _firestore.collection('sugerencias').doc(item['id']).get();
                                    if (doc.exists) {
                                      await _aprobarYProcesarAutomatica(doc);
                                    }
                                  },
                                  child: const Text('Auto-Colocar', style: TextStyle(fontSize: 10)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMatrizGridTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 144,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _tarjetasMatriz.length,
      itemBuilder: (context, index) {
        final card = _tarjetasMatriz[index];
        final maxTarjeta = (card['maxTarjeta'] as int?) ?? 0;
        final total = (card['total'] as int?) ?? 0;
        final totalTarjetas = (card['totalTarjetas'] as int?) ?? 0;
        // El dato ya se calculaba (línea ~1175: 'esProtegida': item['esProtegida'])
        // pero esta tarjeta nunca lo leía, así que zonas protegidas como
        // FARMACIAS o COMERCIOS no se distinguían visualmente en la grilla.
        final bool esProtegida = (card['esProtegida'] as bool?) ?? false;

        // Nivel de saturación por la tarjeta más cargada del territorio:
        // verde (ok, <=4), amarillo (5-8), rojo (saturada, >8).
        final Color nivelColor =
            maxTarjeta > 8 ? const Color(0xFFD32F2F) : (maxTarjeta >= 5 ? const Color(0xFFF9A825) : const Color(0xFF2E7D32));
        final String nivelTexto =
            maxTarjeta > 8 ? 'Saturada (>8)' : (maxTarjeta >= 5 ? 'Alta (5-8)' : 'OK (<=4)');
        final double progreso =
            (maxTarjeta / 10).clamp(0.0, 1.0).toDouble();

        return Card(
          elevation: 2,
          shape: esProtegida
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Colors.amber.shade700, width: 1.5),
                )
              : null,
          child: InkWell(
            onTap: () => _abrirDetalleTerritorio(context, card),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        maxTarjeta > 8
                            ? Icons.warning_amber_rounded
                            : Icons.map,
                        size: 16,
                        color: nivelColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          card['nombre'],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (esProtegida)
                        Tooltip(
                          message: 'Zona protegida (no se cuenta como '
                              'pendiente en el progreso mensual)',
                          child: Icon(Icons.lock,
                              size: 14, color: Colors.amber.shade800),
                        ),
                    ],
                  ),
                  Text(
                    '$total Direcciones · $totalTarjetas Tarjetas',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  if (esProtegida)
                    Container(
                      margin: const EdgeInsets.only(top: 2, bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PROTEGIDA',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                            letterSpacing: 0.5),
                      ),
                    ),
                  // Barra de progreso de saturación dinámica.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progreso,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade300,
                          color: nivelColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('Tarjeta más cargada: $maxTarjeta · $nivelTexto',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: nivelColor)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Abre el detalle del territorio: lista sus tarjetas con la cantidad de
  /// direcciones de cada una y señala cuáles están saturadas (>8).
  void _abrirDetalleTerritorio(BuildContext ctx, Map<String, dynamic> territorio) {
    final tarjetas =
        ((territorio['tarjetas'] ?? <Map<String, dynamic>>[]) as List).cast<Map<String, dynamic>>();
    final nombre = territorio['nombre'];

    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.map, color: Color(0xFF1B4D2E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Territorio: $nombre',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    Text('${tarjetas.length} tarjetas',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tarjetas.isEmpty
                    ? const Center(
                        child: Text('Este territorio aún no tiene tarjetas.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: tarjetas.length,
                        itemBuilder: (context, i) {
                          final t = tarjetas[i];
                          final total = (t['total'] as int?) ?? 0;
                          final saturada = (t['saturada'] as bool?) ?? false;
                          final nivelColor = saturada
                              ? const Color(0xFFD32F2F)
                              : (total >= 5
                                  ? const Color(0xFFF9A825)
                                  : const Color(0xFF2E7D32));
                          final progreso =
                              (total / 10).clamp(0.0, 1.0).toDouble();

                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        saturada
                                            ? Icons.warning_amber_rounded
                                            : Icons.credit_card,
                                        size: 18,
                                        color: nivelColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          t['nombre'].toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          '${total} dir.',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        backgroundColor: saturada
                                            ? Colors.red.shade100
                                            : Colors.teal.shade100,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progreso,
                                      minHeight: 7,
                                      backgroundColor: Colors.grey.shade300,
                                      color: nivelColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    saturada
                                        ? 'SATURADA: tiene más de 8 direcciones.'
                                        : (total >= 5
                                            ? 'Cerca de saturar: revisar.'
                                            : 'Con cupo disponible.'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: nivelColor),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Abre el listado de reglas activas (farmacias, comercios, etc.).
  /// Si se pasa [regla], muestra solo esa regla. Cada regla tiene su botón
  /// "Reorganizar local", que reorganiza SOLO las direcciones de esa zona
  /// restringida (por cercanía, agrupándolas de a 4-6 en tarjetas de la misma
  /// zona), creando tarjetas nuevas tipo "... Zona 2" si hace falta.
  Future<void> _abrirReglasActivas([String? regla]) async {
    final reglas = regla != null
        ? [regla]
        : List<String>.from(_reglasProtegidas);

    // Contador real de direcciones pendientes por zona protegida. Coteja el string
    // `barrio` (nombre del territorio), `categoria_regla`, `territorio_destino`
    // y también los ids de los territorios cuyo nombre coincide con la regla,
    // para cubrir la discrepancia entre id de documento y nombre de zona.
    final Map<String, int> pendientesPorRegla =
        await _contarPendientesProtegidas(reglas);

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.rule, color: Color(0xFFB26A00)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Reglas Activas',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  'Las direcciones de estas zonas NO se reorganizan de forma '
                  'general: se manejan de forma local por cercanía dentro de la '
                  'misma zona restringida.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: reglas.isEmpty
                    ? const Center(
                        child: Text('No hay reglas activas.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: reglas.length,
                        itemBuilder: (context, index) {
                          final r = reglas[index];
                          final pendientes =
                              pendientesPorRegla[r.toUpperCase()] ?? 0;
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.storefront,
                                      color: Color(0xFFB26A00)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(r,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                        Text(
                                            '$pendientes dirección/es pendientes',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _reorganizarZonaLocal(r);
                                    },
                                    icon: const Icon(Icons.settings_ethernet,
                                        size: 16),
                                    label: const Text('Reorganizar local',
                                        style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFB26A00),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, int>> _contarPendientesProtegidas(List<String> reglas) async {
    final map = <String, int>{
      for (final r in reglas) r.toUpperCase().trim(): 0,
    };
    try {
      final ters = await _catalogo.territorios();
      final idsPorRegla = <String, Set<String>>{};
      for (final t in ters) {
        final nombre =
            (t.data()['nombre']?.toString() ?? '').toUpperCase().trim();
        for (final r in reglas) {
          final key = r.toUpperCase().trim();
          if (key.isNotEmpty && nombre == key) {
            idsPorRegla.putIfAbsent(key, () => <String>{}).add(t.id);
          }
        }
      }

      final snap = await _firestore
          .collection('direcciones_globales')
          .where('estado_predicacion', isEqualTo: 'pendiente')
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final b = (data['barrio']?.toString() ?? '').toUpperCase().trim();
        final c =
            (data['categoria_regla']?.toString() ?? '').toUpperCase().trim();
        final td =
            (data['territorio_destino']?.toString() ?? '').toUpperCase().trim();
        final tid = data['territorio_id']?.toString() ?? '';
        for (final r in reglas) {
          final key = r.toUpperCase().trim();
          if (key.isEmpty) continue;
          if (b == key ||
              c == key ||
              td == key ||
              (idsPorRegla[key]?.contains(tid) ?? false)) {
            map[key] = map[key]! + 1;
          }
        }
      }
    } catch (_) {
      // Fallback: conteo en memoria sobre la bandeja de sugerencias.
      for (final dir in _sugerenciasLista) {
        final r = dir['barrio']?.toString().toUpperCase().trim() ?? '';
        if (map.containsKey(r)) map[r] = map[r]! + 1;
      }
    }
    return map;
  }

  /// Reorganiza de forma LOCAL las direcciones de una zona restringida
  /// (ej. FARMACIAS, COMERCIOS). Agrupa por cercanía en grupos de 4-6 y los
  /// asigna a tarjetas de ESA misma zona; crea una tarjeta nueva con nombre
  /// parecido ("... Zona 2") si la actual se satura.
  Future<void> _reorganizarZonaLocal(String regla) async {
    if (_reorganizandoZona) return;
    _reorganizandoZona = true;
    final zoneKey = regla.toUpperCase().trim();
    if (zoneKey.isEmpty) {
      _reorganizandoZona = false;
      return;
    }

    final cancelar = ValueNotifier<bool>(false);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ventanaProgresoZona(zoneKey, cancelar),
    );

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Identificar el territorio de la zona protegida. NO se crea ninguno.
      String? territorioId;
      final territorios = await _catalogo.territorios(forzar: true);
      for (final t in territorios) {
        final nombre = t.data()['nombre']?.toString().toUpperCase().trim() ?? '';
        if (t.id.toUpperCase().trim() == zoneKey || nombre == zoneKey) {
          territorioId = t.id;
          break;
        }
      }
      if (territorioId == null) {
        await _cerrarVentanaProgreso();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('La zona "$regla" aún no tiene territorio creado.')),
          );
        }
        _reorganizandoZona = false;
        return;
      }

      // 2. Cargar tarjetas de ESA zona desde la subcolección canónica
      //    `territorios/{id}/tarjetas` (la única que lee la pestaña Territorios).
      final tarjetasSnap = await firestore
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .get();
      final tarjetas = tarjetasSnap.docs.map((d) {
        final data = d.data();
        return <String, dynamic>{
          'id': d.id,
          'nombre': data['nombre'] ?? 'Sin nombre',
          'territorio_id': data['territorio_id'] ?? territorioId,
          'totalDirecciones':
              (data['totalDirecciones'] as num?)?.toInt() ?? 0,
        };
      }).toList();

      // 3. Cargar las direcciones sueltas/pendientes de esta zona (las que ya
      //    están asignadas a una tarjeta no se tocan).
      //
      // NOTA: `barrio` guarda el NOMBRE del territorio (p.ej. "FARMACIAS"),
      // no su id de Firestore. Por eso se filtra por `zoneKey` (el nombre/
      // categoría de la regla) en los campos reales (`barrio`,
      // `categoria_regla`, `territorio_destino`) y además por `territorio_id`.
      //
      // AUTO-DIVISIÓN: se toman TODAS las direcciones de la zona (recogidas
      // por cualquiera de esos campos), tengan tarjeta asignada o no. Se unen
      // por doc id (los "candidatos" de varias queries se fusionan en una sola
      // llave), se redistribuyen por cercanía y la tarjeta origen se descuenta
      // (se borra si queda en 0). Así una tarjeta saturada (p.ej. 10 dir.) se
      // reparte en varias tarjetas de la zona.
      final direccionesZona = <String, Map<String, dynamic>>{};
      final candidatosQueries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        firestore
            .collection('direcciones_globales')
            .where('barrio', isEqualTo: zoneKey)
            .get(),
        firestore
            .collection('direcciones_globales')
            .where('categoria_regla', isEqualTo: zoneKey)
            .get(),
        firestore
            .collection('direcciones_globales')
            .where('territorio_destino', isEqualTo: zoneKey)
            .get(),
        firestore
            .collection('direcciones_globales')
            .where('territorio_id', isEqualTo: territorioId)
            .limit(2000)
            .get(),
      ];
      final snaps = await Future.wait(candidatosQueries);
      for (final snap in snaps) {
        for (final d in snap.docs) {
          direccionesZona[d.id] = {'id': d.id, ...d.data()};
        }
      }
      final listaZona = direccionesZona.values.toList();

      // 3b. Descuento por tarjeta origen: cada dirección movida resta 1.
      final idsZona = tarjetas.map((t) => t['id'].toString()).toSet();
      final movidas = <String, int>{};
      for (final dir in listaZona) {
        final tid = dir['tarjeta_id']?.toString();
        if (tid != null && tid.isNotEmpty) {
          movidas[tid] = (movidas[tid] ?? 0) - 1;
        }
      }
      // Totales efectivos (total - lo que se va a mover) de las tarjetas de la
      // zona, que se usan para decidir cupo y se escriben/borran al final.
      final totales = <String, int>{
        for (final t in tarjetas)
          t['id'].toString():
              ((t['totalDirecciones'] as num?) ?? 0).toInt() +
                  (movidas[t['id'].toString()] ?? 0),
      };

      // 4. Agrupar por cercanía en grupos de 4-6 direcciones.
      final grupos =
          _agruparPorCercania(listaZona, minPorGrupo: 4, maxPorGrupo: 6);

// 5. Asignar cada grupo a una tarjeta (existente con cupo, o crear nueva).
      var batch = firestore.batch();
      int ops = 0;
      int creadas = 0;
      final tarjetasNuevas = <Map<String, dynamic>>[];

      // Commitea y reasigna una instancia nueva cuando el lote se acerca al
      // límite de Firestore (~400 ops), reiniciando el contador.
      Future<void> commitSiNecesario() async {
        if (ops >= 400) {
          await batch.commit();
          batch = firestore.batch();
          ops = 0;
        }
      }

      int siguiente = 1;
      for (final grupo in grupos) {
        if (cancelar.value) break;
        Map<String, dynamic>? destino;
        for (final t in tarjetas) {
          final id = t['id'].toString();
          final total = totales[id] ?? 0;
          if (total + grupo.length <= 7) {
            destino = t;
            totales[id] = total + grupo.length;
            break;
          }
        }
        if (destino == null) {
          // Crear nueva tarjeta "$ZONA Zona N".
          final nomExistentes = tarjetas
              .map((t) => t['nombre'].toString().toUpperCase())
              .toSet();
          String nombreNuevo = '$zoneKey Zona $siguiente';
          while (nomExistentes.contains(nombreNuevo.toUpperCase()) ||
              tarjetasNuevas
                  .any((n) => n['nombre'].toString() == nombreNuevo)) {
            siguiente++;
            nombreNuevo = '$zoneKey Zona $siguiente';
          }
          siguiente++;
          final ref = firestore
              .collection('territorios')
              .doc(territorioId)
              .collection('tarjetas')
              .doc(nombreNuevo);
          batch.set(ref, {
            'nombre': nombreNuevo,
            'territorio_id': territorioId,
            'totalDirecciones': grupo.length,
            'creado_por_ia': true,
            'origen_reorganizacion_local': zoneKey,
            'created_at': FieldValue.serverTimestamp(),
          });
          tarjetasNuevas.add({'nombre': nombreNuevo, 'cnt': grupo.length});
          destino = <String, dynamic>{
            'id': ref.id,
            'nombre': nombreNuevo,
            'totalDirecciones': grupo.length,
          };
          creadas++;
          ops++;
        } else {
          // El total real lo escribe batch2 al final con el valor acumulado en
          // `totales`; aquí solo se marcan las banderas de IA.
          final ref = firestore
              .collection('territorios')
              .doc(territorioId)
              .collection('tarjetas')
              .doc(destino['id'] as String);
          batch.update(ref, {
            'actualizado_por_ia': true,
            'updated_at': FieldValue.serverTimestamp(),
          });
          ops++;
        }

        // Asignar las direcciones del grupo a la tarjeta destino.
        for (final dir in grupo) {
          batch.update(
            firestore.collection('direcciones_globales').doc(dir['id'] as String),
            {
              'tarjeta_id': destino['id'],
              'nombre_tarjeta': destino['id'],
              'estado_predicacion': 'asignada',
              'territorio_destino': territorioId,
            },
          );
          ops++;
          await commitSiNecesario();
        }
      }

      await batch.commit();

      // 5b. Aplicar los totales finales: borrar tarjetas de la zona que quedaron
      // en 0 (auto-división) y actualizar el resto; descontar tarjetas externas.
      final batch2 = firestore.batch();
      DocumentReference<Map<String, dynamic>> tarjetaRef(String id) =>
          firestore.collection('territorios').doc(territorioId).collection('tarjetas').doc(id);
      for (final e in totales.entries) {
        if (e.value <= 0) {
          batch2.delete(tarjetaRef(e.key));
        } else {
          batch2.update(tarjetaRef(e.key), {'totalDirecciones': e.value});
        }
      }
      // Descontar tarjetas EXTERNAS (de otras zonas) por el territorio que
      // guarda la dirección origen; si no se puede ubicar, no se toca nada.
      final tarjetaTerritorio = <String, String>{};
      for (final dir in listaZona) {
        final tid = dir['tarjeta_id']?.toString() ?? '';
        final ter = dir['territorio_id']?.toString() ?? '';
        if (tid.isNotEmpty && ter.isNotEmpty) tarjetaTerritorio[tid] = ter;
      }
      for (final e in movidas.entries) {
        if (idsZona.contains(e.key)) continue;
        final terDeCard = tarjetaTerritorio[e.key];
        if (terDeCard == null || terDeCard.isEmpty) continue;
        batch2.update(
          firestore
              .collection('territorios')
              .doc(terDeCard)
              .collection('tarjetas')
              .doc(e.key),
          {'totalDirecciones': FieldValue.increment(e.value)},
        );
      }
      await batch2.commit();
      // batch y batch2 crearon, borraron y/o actualizaron tarjetas de la
      // zona y de otros territorios: invalidar la caché compartida.
      _catalogo.invalidar();

      // 6. Registrar en el historial.
      await firestore.collection('historial_reorganizaciones').add({
        'fecha': FieldValue.serverTimestamp(),
        'tipo_evento': 'REORGANIZACION_LOCAL',
        'zona': zoneKey,
        'usuario': (widget.usuarioData?['email'] as String?) ?? 'Auditor',
        'totalDireccionesProcesadas': listaZona.length,
        'tarjetasCreadas': creadas,
        'tarjetasNuevas': tarjetasNuevas,
        'resumenIA':
            'Reorganización local de la zona "$regla" por cercanía (${listaZona.length} dir. en ${grupos.length} grupo(s)).',
      });

      // 7. Notificación interna a auditores.
      try {
        await NotificacionService.enviarAAuditores(
          titulo: 'Zona reorganizada',
          cuerpo:
              'La zona "$regla" se reorganizó localmente: ${listaZona.length} dir. en ${grupos.length} grupo(s), $creadas tarjeta(s) nueva(s).',
          tipo: TipoNotificacion.alertaPredicacion,
        );
      } catch (_) {}

      await _cerrarVentanaProgreso();
      _cargarConsolaDinamica();
      _reorganizandoZona = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Zona "$regla" reorganizada: ${listaZona.length} dir. en ${grupos.length} grupo(s), $creadas tarjeta(s) nueva(s).'),
          ),
        );
      }
    } catch (e) {
      await _cerrarVentanaProgreso();
      _reorganizandoZona = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reorganizar la zona: $e')),
        );
      }
    }
  }

  /// Agrupa las direcciones de una zona por cercanía geográfica (lat/lng),
  /// formando grupos de entre [minPorGrupo] y [maxPorGrupo] direcciones.
  List<List<Map<String, dynamic>>> _agruparPorCercania(
    List<Map<String, dynamic>> direcciones, {
    int minPorGrupo = 4,
    int maxPorGrupo = 6,
  }) {
    if (direcciones.isEmpty) return [];
    final lista = List<Map<String, dynamic>>.from(direcciones);

    // Ordenar por coordenadas para que los vecinos queden juntos.
    final hasGeo = lista.every((d) => d['lat'] != null && d['lng'] != null);
    if (hasGeo) {
      lista.sort((a, b) {
        final c =
            (a['lat'] as num).compareTo((b['lat'] as num));
        return c != 0
            ? c
            : (a['lng'] as num).compareTo((b['lng'] as num));
      });
    }

    final grupos = <List<Map<String, dynamic>>>[];
    final usados = List<bool>.filled(lista.length, false);
    for (int i = 0; i < lista.length; i++) {
      if (usados[i]) continue;
      final grupo = <Map<String, dynamic>>[lista[i]];
      usados[i] = true;
      var j = i + 1;
      while (grupo.length < maxPorGrupo && j < lista.length) {
        if (!usados[j]) {
          grupo.add(lista[j]);
          usados[j] = true;
        }
        j++;
      }
      if (grupo.length < minPorGrupo && grupos.isNotEmpty) {
        // Fusionar el grupo pequeño (residuo) con el anterior si tiene cupo.
        final anterior = grupos.last;
        while (grupo.isNotEmpty && anterior.length < maxPorGrupo) {
          anterior.add(grupo.removeLast());
        }
        if (grupo.isNotEmpty) grupos.add(grupo);
      } else {
        grupos.add(grupo);
      }
    }
    return grupos;
  }

  Widget _ventanaProgresoZona(String zona, ValueNotifier<bool> cancelar) {
    return AlertDialog(
      title: Text('Reorganizando "$zona"...'),
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: cancelar,
              builder: (_, v, __) => Text(
                v ? 'Cancelando...' : 'Agrupando direcciones por cercanía...',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => cancelar.value = true,
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Future<void> _cerrarVentanaProgreso() async {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Carga los eventos históricos detallados de la matriz, juntando diversas
  /// fuentes para trazabilidad completa:
  /// - `sugerencias_enviadas`/registros de envío (direcciones nuevas)
  /// - `historial_reorganizaciones` (auto-asignación y reorganización)
  /// - `historial_auditoria` (búsquedas/POI y auditoría en general)
  ///
  /// Cada evento incluye la dirección, territorio/tarjeta destino, fecha y
  /// usuario que la envió. Retorna la lista ordenada por fecha descendente.
  Future<List<Map<String, dynamic>>> _cargarEventosHistoricos() async {
    final eventos = <Map<String, dynamic>>[];

    // 1) Reorganizaciones / auto-asignación: dónde se colocó cada dirección.
    final reorg = await _firestore
        .collection('historial_reorganizaciones')
        .orderBy('fecha', descending: true)
        .limit(100)
        .get();
    for (final d in reorg.docs) {
      final data = d.data();
      eventos.add({
        'id': d.id,
        'categoria': 'reorganizacion',
        'icono': Icons.auto_awesome,
        'tipo_evento': data['tipo_evento'] ?? 'REORGANIZACION',
        'direccion_ingresada': data['direccion_ingresada'],
        'complemento': data['complemento'],
        'barrio': data['barrio'],
        'territorio': data['territorio_destino'] ?? data['barrio'],
        'tarjeta_nombre': data['tarjeta_nombre'],
        'tarjeta_asignada_id': data['tarjeta_asignada_id'],
        'accion_tomada': data['accion_tomada'],
        'usuario': data['usuario'],
        'razonamiento_ia': data['razonamiento_ia'],
        'lat': data['lat'],
        'lng': data['lng'],
        'lugar': data['lugar_validado'],
        'fecha': data['fecha'],
      });
    }

    // 2) Auditoría (incluye búsquedas/POI).
    final histAud = await _firestore
        .collection('historial_auditoria')
        .orderBy('fecha', descending: true)
        .limit(60)
        .get();
    for (final d in histAud.docs) {
      final data = d.data();
      final tipo = (data['tipo_evento'] ?? data['accion'] ?? '').toString();
      final esPoi = tipo.toLowerCase().contains('poi') ||
          tipo.toLowerCase().contains('búsqueda') ||
          tipo.toLowerCase().contains('busqueda') ||
          tipo.toLowerCase().contains('escaneo');
      eventos.add({
        'id': d.id,
        'categoria': esPoi ? 'busqueda' : 'auditoria',
        'icono': esPoi ? Icons.travel_explore : Icons.rule,
        'tipo_evento': tipo.isNotEmpty ? tipo : 'AUDITORIA',
        'direccion_ingresada':
            data['direccion'] ?? data['calle'] ?? data['lugar_detectado'],
        'complemento': data['complemento'],
        'barrio': data['barrio'],
        'territorio': data['territorio'] ?? data['barrio'],
        'tarjeta_nombre': data['tarjeta_nombre'] ?? data['tarjeta_destino'],
        'tarjeta_asignada_id':
            data['tarjeta_id'] ?? data['tarjeta_destino_id'],
        'accion_tomada': data['accion_tomada'] ?? data['descripcion'],
        'usuario': data['usuario'] ?? data['usuario_email'],
        'razonamiento_ia': data['razonamiento_ia'],
        'lat': data['lat'],
        'lng': data['lng'],
        'lugar': data['lugar_validado'],
        'fecha': data['fecha'] ?? data['creado_en'],
      });
    }

    // 3) Direcciones nuevas enviadas (bandeja `sugerencias` y envíos).
    final suge = await _firestore
        .collection('sugerencias')
        .orderBy('creado_el', descending: true)
        .limit(40)
        .get();
    for (final d in suge.docs) {
      final data = d.data();
      eventos.add({
        'id': d.id,
        'categoria': 'nueva_direccion',
        'icono': Icons.add_location_alt,
        'tipo_evento': 'DIRECCION_NUEVA',
        'direccion_ingresada': data['texto_direccion'] ?? data['calle'],
        'complemento': data['complemento'],
        'barrio': data['barrio'],
        'territorio': data['barrio'],
        'tarjeta_nombre': data['tarjeta_nombre'] ?? data['tarjeta_destino'],
        'tarjeta_asignada_id': data['tarjeta_id'] ?? data['tarjeta_destino_id'],
        'accion_tomada':
            data['estado'] == 'PENDIENTE_AUDITORIA' ? 'En bandeja (pendiente de revisión)' : 'Procesada',
        'usuario': data['usuario'] ?? data['usuario_email'] ?? data['email_enviador'],
        'razonamiento_ia': data['razonamiento_ia'],
        'lat': data['lat'],
        'lng': data['lng'],
        'lugar': data['lugar_validado'],
        'fecha': data['creado_el'] ?? data['fecha'],
      });
    }

    // Ordenar por fecha descendente (más recientes primero).
    eventos.sort((a, b) {
      final fa = a['fecha'];
      final fb = b['fecha'];
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return (fb as dynamic).compareTo(fa as dynamic);
    });

    return eventos;
  }

  /// Abre el diálogo de histórico detallado: muestra todos los eventos de la
  /// matriz (reorganización, búsquedas/POI, direcciones nuevas) con la
  /// dirección, territorio/tarjeta destino, fecha y usuario que la envió.
  Future<void> _abrirHistorialDetallado() async {
    // Primer diálogo: cargando mientras se consultan las colecciones.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF1B4D2E)),
              SizedBox(height: 16),
              Text('Cargando histórico de eventos...',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );

    List<Map<String, dynamic>> eventos;
    try {
      eventos = await _cargarEventosHistoricos();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando histórico: $e'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!mounted) return;

    // Cerrar el diálogo de carga para abrir el detallado.
    Navigator.of(context).pop();

    final contadores = <String, int>{};
    for (final e in eventos) {
      final cat = (e['categoria'] ?? 'otro').toString();
      contadores[cat] = (contadores[cat] ?? 0) + 1;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        String filtro = 'todas';
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final actual = filtro == 'todas'
                ? eventos
                : eventos.where((e) => e['categoria'] == filtro).toList();
            return Dialog(
              insetPadding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 700, maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: Color(0xFF1B4D2E)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Histórico detallado',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Text('${actual.length} eventos',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Filtros por categoría
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          _chipHistorial(setLocalState, () => filtro = 'todas', filtro == 'todas', 'Todas (${eventos.length})', null),
                          _chipHistorial(setLocalState, () => filtro = 'reorganizacion', filtro == 'reorganizacion', 'Reorganización (${contadores['reorganizacion'] ?? 0})', Icons.auto_awesome),
                          _chipHistorial(setLocalState, () => filtro = 'nueva_direccion', filtro == 'nueva_direccion', 'Nuevas (${contadores['nueva_direccion'] ?? 0})', Icons.add_location_alt),
                          _chipHistorial(setLocalState, () => filtro = 'busqueda', filtro == 'busqueda', 'Búsquedas (${contadores['busqueda'] ?? 0})', Icons.travel_explore),
                          _chipHistorial(setLocalState, () => filtro = 'auditoria', filtro == 'auditoria', 'Auditoría (${contadores['auditoria'] ?? 0})', Icons.rule),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: actual.isEmpty
                          ? const Center(
                              child: Text('Sin eventos para este filtro.',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: actual.length,
                              itemBuilder: (context, i) =>
                                  _tarjetaEventoHistorial(context, actual[i]),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _chipHistorial(
    void Function(VoidCallback) setLocalState,
    VoidCallback onSeleccionar,
    bool seleccionado,
    String etiqueta,
    IconData? icono,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FilterChip(
        label: Text(etiqueta, style: const TextStyle(fontSize: 11)),
        avatar: icono == null ? null : Icon(icono, size: 14),
        selected: seleccionado,
        onSelected: (_) => setLocalState(onSeleccionar),
      ),
    );
  }

  Widget _tarjetaEventoHistorial(BuildContext context, Map<String, dynamic> e) {
    final direccion = (e['direccion_ingresada'] ?? '').toString();
    final complemento = (e['complemento'] ?? '').toString();
    final territorio = (e['territorio'] ?? '').toString();
    final tarjeta = (e['tarjeta_nombre'] ?? '').toString();
    final accion = (e['accion_tomada'] ?? '').toString();
    final usuario = (e['usuario'] ?? 'sistema').toString();
    final razon = (e['razonamiento_ia'] ?? '').toString();
    final lugar = (e['lugar'] ?? '').toString();
    final dinamico = e['icono'] ?? Icons.history;

    final timestamp = e['fecha'];
    String horaStr = '"';
    if (timestamp is Timestamp) {
      horaStr = _formatearFecha(timestamp.toDate());
    } else if (timestamp != null) {
      try {
        horaStr = _formatearFecha((timestamp as dynamic).toDate());
      } catch (_) {}
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(dinamico, size: 20, color: const Color(0xFF1B4D2E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    direccion.isNotEmpty ? direccion : 'Sin dirección',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Text(horaStr, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Territorio: ${territorio.isNotEmpty ? territorio : '"'}   |   Tarjeta: ${tarjeta.isNotEmpty ? tarjeta : '"'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B4D2E)),
                  ),
                  if (complemento.isNotEmpty)
                    Text('Complemento: $complemento',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  if (lugar.isNotEmpty && lugar.toLowerCase() != direccion.toLowerCase())
                    Text('Mapbox: $lugar', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  if (usuario != 'sistema')
                    Text('Enviado por: $usuario', style: TextStyle(fontSize: 11, color: Colors.black87)),
                  if (accion.isNotEmpty)
                    Text('Acción: $accion', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  if (razon.isNotEmpty)
                    Text('Razón IA: $razon', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatearFecha(DateTime dt) {
    final ahora = DateTime.now();
    final diff = ahora.difference(dt);
    if (diff.inMinutes < 1) return 'justo ahora';
    if (diff.inMinutes < 60) return 'ha ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} $hh:$mi';
  }
}

/// Estado mutable compartido entre la ventana de progreso de la reorganización
/// y el flujo de procesamiento por lotes, para refrescar la UI sin recrear el
/// diálogo.
class _ProgresoReorg {
  _ProgresoReorg({
    required this.total,
    required this.lote,
    required this.segLote,
  });

  int total;
  int lote;
  double segLote;
  VoidCallback? onUpdate;
}