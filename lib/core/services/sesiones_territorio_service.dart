import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tope de IDs que se guardan dentro de una sesión.
///
/// El alcance de la sesión se materializa como una LISTA de IDs, no como un
/// contador. Eso es deliberado: un contador se desincroniza en cuanto algo lo
/// modifica por fuera (un borrado, una reparación masiva, un proceso
/// concurrente) y ahí el porcentaje miente. Una lista de IDs no se
/// desincroniza porque no se "incrementa": se compara contra el estado actual de
/// cada documento.
///
/// A cambio, el documento crece. Con el orden de magnitud actual del proyecto
/// (unas 190 direcciones en 11 territorios) la lista completa pesa ~1 KB, muy
/// por debajo del límite de 1 MB de Firestore. Este tope es una red de
/// seguridad: si se superara, la sesión quedaría truncada y la barra dejaría de
/// ser confiable para ese territorio, así que es preferible detectarlo.
const int kMaxIdsPorSesion = 1000;

/// Estados de una sesión de territorio.
const String kSesionAbierta = 'abierta';
const String kSesionEnCurso = 'en_curso';
const String kSesionCerrada = 'cerrada';

/// El territorio ya estaba 100% predicado la primera vez que se lo miró.
///
/// No es un cierre: no hubo sesión que medir, y fingir una fecha sería
/// inventar el dato que el usuario pidió. Se muestra igual en la lista, con la
/// barra llena, para que el territorio no desaparezca; simplemente dice que no
/// hay tiempo medible. Pasa a `abierta` sola vez entra trabajo pendiente.
const String kSesionSinMedir = 'sin_medir';

/// Una dirección que llegó al territorio DESPUÉS de que arrancó el ciclo.
///
/// Es la razón visible de que la barra retroceda: el territorio es dinámico,
/// entra dirección todo el tiempo, y ese dato hay que poder mostrar de forma
/// discriminada en vez de esconderlo dentro de un total.
class DatoLlegada {
  final String id;
  final String calle;
  final DateTime? creadaEn;
  final bool completada;

  DatoLlegada({
    required this.id,
    required this.calle,
    required this.creadaEn,
    required this.completada,
  });
}

/// Progreso de "se predicó" de UN territorio, calculado en vivo.
///
/// Todo se deriva de campos que la app ya escribe. Esta clase no escribe nada
/// en `direcciones_globales`, ni en tarjetas, ni en el reinicio mensual.
class ProgresoTerritorio {
  final String territorioId;
  final String territorioNombre;

  /// Direcciones del territorio que siguen "en juego": pendientes o ya
  /// predicadas. Es el denominador de la barra.
  final List<String> idsEnJuego;

  /// Subconjunto de [idsEnJuego] con `estado_predicacion == 'completada'`.
  final List<String> idsPredicadas;

  /// Direcciones que dejaron el territorio de forma permanente (comercio
  /// cerrado, no hispano, borradas). NO cuentan en el denominador: si contaran,
  /// un comercio que cerró en mitad de ciclo dejaría la sesión sin poder cerrar
  /// nunca.
  final int retiradas;

  /// Retiradas cuyo motivo no se pudo confirmar: estaban en el alcance y ya no
  /// existen ni en `direcciones_globales` ni en `direcciones_removidas`. Se
  /// tratan como retiradas para no bloquear el cierre, pero se exponen aparte
  /// para no esconder borrados accidentales.
  final int retiradasSinRastro;

  final DateTime? primeraPredicacion;
  final DateTime? ultimaPredicacion;

  /// Tarjetas del territorio con su tiempo de ciclo.
  final List<DatosTarjetaSesion> tarjetas;

  int get totalEnJuego => idsEnJuego.length;
  int get pendientes => totalEnJuego - idsPredicadas.length;

  double get porcentaje =>
      totalEnJuego <= 0 ? 0 : (idsPredicadas.length / totalEnJuego * 100);

  ProgresoTerritorio({
    required this.territorioId,
    required this.territorioNombre,
    required this.idsEnJuego,
    required this.idsPredicadas,
    required this.retiradas,
    required this.retiradasSinRastro,
    required this.primeraPredicacion,
    required this.ultimaPredicacion,
    required this.tarjetas,
  });
}

/// Tiempo de una tarjeta. Sale de `enviado_en` y `fecha_completada`, que la app
/// ya escribe: no requiere ningún campo nuevo.
class DatosTarjetaSesion {
  final String id;
  final String nombre;
  final bool completada;
  final DateTime? enviadaEn;
  final DateTime? completadaEn;

  Duration? get duracion {
    final a = enviadaEn;
    final b = completadaEn;
    if (a == null || b == null) return null;
    final d = b.difference(a);
    return d.isNegative ? null : d;
  }

  DatosTarjetaSesion({
    required this.id,
    required this.nombre,
    required this.completada,
    required this.enviadaEn,
    required this.completadaEn,
  });
}

/// Una sesión = un territorio dentro de un ciclo (mes).
///
/// Guarda solo lo que NO se puede volver a leer después: el alcance congelado
/// del ciclo y las fechas de arranque y cierre. Todo lo demás (barras,
/// contadores, ritmo) se recalcula en vivo contra `direcciones_globales`.
///
/// Guardar esas fechas es obligatorio, no opcional: el reinicio mensual
/// (`restauracion_mensual.dart`) devuelve `activa` → `pendiente` y BORRA
/// `fecha_predicacion` y `mes_predicacion`. Si el cierre de un ciclo no se
/// archiva en el momento, se pierde para siempre y nunca más se podrá responder
/// cuánto tardamos en terminar ese territorio.
class SesionTerritorio {
  final String id;
  final String territorioId;
  final String territorioNombre;
  final String ciclo;
  final String estado;

  /// Direcciones pendientes cuando arrancó el ciclo: el alcance congelado.
  final List<String> idsAlcance;

  /// Direcciones que llegaron después de arrancar el ciclo.
  final List<String> idsLlegados;

  /// Cuántas direcciones ya estaban predicadas cuando se creó la sesión. No
  /// forman parte del alcance; solo se informa para que se vea de dónde se
  /// arrancó.
  final int completadasPrevias;

  final DateTime? abiertaEn;

  /// Momento en que se predicó la PRIMERA dirección del alcance. Es el inicio
  /// real del trabajo; antes de eso la sesión solo está abierta.
  final DateTime? inicioEn;

  /// Momento en que se predicó la ÚLTIMA dirección del alcance.
  final DateTime? cierreEn;

  /// Primer cierre del ciclo. Nunca se sobrescribe aunque la sesión se reabra,
  /// porque es el dato histórico de "cuándo se terminó por primera vez".
  final DateTime? cierrePrimeraVezEn;

  final int reaperturas;
  final DateTime? ultimaLecturaEn;

  /// Direcciones del ALCANCE de esta sesión que ya están predicadas. Es el
  /// avance medible del ciclo, y la base del ritmo y de la proyección.
  ///
  /// A propósito NO es lo mismo que `progreso.idsPredicadas.length`, que cuenta
  /// el territorio entero e incluye lo que ya estaba hecho antes de que existiera
  /// la sesión. Mezclarlos daba un ritmo inflado y una proyección que prometía
  /// un cierre imposible.
  final int avanceAlcance;

  /// Direcciones vivas del alcance de esta sesión: `avanceAlcance` más las
  /// pendientes. Es el "total" de la sesión, no el del territorio.
  final int alcanceVivo;

  /// Detalle de las direcciones que llegaron, para poder mostrarlas una por
  /// una. Viene vacío si la sesión se leyó sin sincronizar.
  final List<DatoLlegada> llegadas;

  /// Progreso en vivo. `null` si no se pudo calcular.
  final ProgresoTerritorio? progreso;

  // ── Derivados ────────────────────────────────────────────────────────

  int get alcanceTotal => idsAlcance.length + idsLlegados.length;

  /// Llegadas que todavía no se predicaron. Es el número que impide declarar
  /// "100%" cuando en realidad entró trabajo nuevo.
  int get llegadosPendientes {
    final p = progreso;
    if (p == null) return 0;
    final preds = p.idsPredicadas.toSet();
    final enJuego = p.idsEnJuego.toSet();
    return idsLlegados
        .where((id) => enJuego.contains(id) && !preds.contains(id))
        .length;
  }

  Duration? get duracion {
    final a = inicioEn;
    final b = cierreEn;
    if (a == null || b == null) return null;
    final d = b.difference(a);
    return d.isNegative ? null : d;
  }

  /// Tiempo transcurrido: hasta el cierre si cerró, hasta ahora si sigue
  /// abierta.
  Duration? get transcurrido {
    final a = inicioEn;
    if (a == null) return null;
    final d = (cierreEn ?? DateTime.now()).difference(a);
    return d.isNegative ? null : d;
  }

  /// Direcciones del alcance por día. El mínimo de 6 horas evita dividir por
  /// cero el primer día en que se predica la primera dirección.
  ///
  /// Se cuenta sobre [avanceAlcance] y no sobre el avance del territorio: si no,
  /// un territorio que venía con 16 predichas de 52 reportaría "16 por día" el
  /// primer día, cuando en realidad nadie trabajó en eso.
  double get ritmo {
    final t = transcurrido;
    if (t == null) return 0;
    final dias = t.inHours / 24;
    return avanceAlcance / (dias < 0.25 ? 0.25 : dias);
  }

  /// Fecha estimada de cierre al ritmo actual. `null` si no hay con qué
  /// proyectar. Proyecta sobre lo que falta del ALCANCE, que es lo que esta
  /// sesión se ocupa de terminar.
  DateTime? get proyeccion {
    if (transcurrido == null) return null;
    final pend = alcanceVivo - avanceAlcance;
    final r = ritmo;
    if (pend <= 0 || r <= 0) return null;
    return DateTime.now().add(Duration(hours: (pend / r * 24).round()));
  }

  /// Territorio completo de verdad: todas las direcciones vivas están
  /// predicadas.
  ///
  /// Como el denominador es el territorio vivo, esto no admite un "100%" falso:
  /// si hay una sola dirección viva sin predecir, `pendientes` es 1 y da falso.
  /// Las llegadas ya están contenidas en el denominador, así que no hace falta
  /// un segundo chequeo.
  bool get completo {
    final p = progreso;
    if (p == null) return false;
    if (p.totalEnJuego <= 0) return false;
    return p.pendientes == 0;
  }

  /// El territorio ya estaba terminado cuando se lo miró por primera vez, así
  /// que no hay duración que mostrar. La barra está llena igual, pero no se
  /// puede afirmar cuánto tardó.
  bool get sinMedir => estado == kSesionSinMedir;

  /// Lo que se muestra como avance: para una sesión medible es el porcentaje
  /// real, y para una que ya estaba completa es 100% porque así es de verdad.
  double get porcentajeMostrado => sinMedir ? 100 : (progreso?.porcentaje ?? 0);

  SesionTerritorio({
    required this.id,
    required this.territorioId,
    required this.territorioNombre,
    required this.ciclo,
    required this.estado,
    required this.idsAlcance,
    required this.idsLlegados,
    required this.completadasPrevias,
    required this.abiertaEn,
    required this.inicioEn,
    required this.cierreEn,
    required this.cierrePrimeraVezEn,
    required this.reaperturas,
    required this.ultimaLecturaEn,
    required this.avanceAlcance,
    required this.alcanceVivo,
    this.llegadas = const [],
    this.progreso,
  });
}

/// Dirección que quedó fuera de la medición, y por qué.
///
/// Se expone porque un total que deja 12 direcciones afuera sin decirlo es un
/// total mentiroso: la pantalla debe poder decir "de 190 direcciones, 178 se
/// miden y 12 no".
class CoberturaDirecciones {
  const CoberturaDirecciones({
    required this.total,
    required this.medidas,
    required this.enTerritoriosBase,
    required this.sinTerritorio,
  });

  /// Todas las direcciones de `direcciones_globales`.
  final int total;

  /// Las que se leyeron y cuentan en algún denominador.
  final int medidas;

  /// Las que pertenecen a FARMACIAS / MERCADOS / TALLERES, que son agrupadores
  /// de tipo `base` y no territorios de campo. Mismo criterio que ya usa la
  /// sección "Por territorio" de Estadísticas.
  final int enTerritoriosBase;

  /// Las que no matchean ningún territorio de campo. Son pocas y valen la pena
  /// nombrarlas: una tiene `territorio_id = "Sin territorio"`, que es un valor
  /// legítimo y deliberado.
  final int sinTerritorio;

  int get fueraDeMedicion => enTerritoriosBase + sinTerritorio;

  /// `true` solo si de verdad no hay direcciones escondidas. Si esto se apaga,
  /// la nota de cobertura aparece abajo.
  bool get completa => fueraDeMedicion == 0;
}

/// Resultado de cargar: las sesiones más el resumen de cobertura.
class ResumenSesionesTerritorio {
  const ResumenSesionesTerritorio({
    required this.sesiones,
    required this.cobertura,
  });

  final List<SesionTerritorio> sesiones;
  final CoberturaDirecciones cobertura;
}

/// Progreso general de la sección: la suma de todos los territorios.
///
/// Se calcula sumando los denominadores de cada territorio en vez de usar un
/// total suelto de `direcciones_globales`. La diferencia no es cosmética: el
/// total crudo incluiría las direcciones en territory agrupadores que ninguna
/// barra cuenta, y la barra general quedaría más baja que la suma de las barras
/// que tiene justo debajo. Dos números que no cuadran juntos hacen dudar de los
/// dos.
class ProgresoGeneral {
  const ProgresoGeneral({required this.completadas, required this.total});

  final int completadas;
  final int total;

  int get pendientes => total - completadas;

  double get porcentaje => total <= 0 ? 0 : completadas / total * 100;

  /// `true` si todos los territorios ya cerraron. Con `total == 0` se responde
  /// `false`: no hay nada que afirmar.
  bool get completo => total > 0 && pendientes == 0;

  /// Construye el total general a partir de las sesiones de la pantalla.
  static ProgresoGeneral deSesiones(List<SesionTerritorio> sesiones) {
    var completadas = 0;
    var total = 0;
    for (final s in sesiones) {
      final p = s.progreso;
      if (p == null) continue;
      completadas += p.idsPredicadas.length;
      total += p.totalEnJuego;
    }
    return ProgresoGeneral(completadas: completadas, total: total);
  }
}

/// Calcula y archiva la progresión de "se predicó" por territorio.
///
/// QUÉ ES Y QUÉ NO ES
///
/// Es un EXTRATO independiente dentro de Estadísticas. No reemplaza ninguna
/// estadística existente: no toca el publicador, ni las tarjetas, ni el
/// reinicio mensual, ni un solo campo de `direcciones_globales`. La única
/// escritura de todo este servicio va a la colección NUEVA `sesiones_territorio`
/// y sirve para archivar el cierre de cada ciclo antes de que el reinicio
/// mensual borre las fechas.
///
/// POR QUÉ UNA LISTA DE IDs Y NO UN CONTADOR
///
/// El problema clásico de un contador desincronizado se evita entero: el
/// alcance se guarda como la lista concreta de direcciones y el progreso sale
/// de contar cuántas de esas están `completada` hoy. No hay nada que sumar ni
/// que restar, así que ninguna reparación, borrado o proceso masivo puede
/// descuadrar el número.
class SesionesTerritorioService {
  SesionesTerritorioService._();

  static CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('sesiones_territorio');

  /// Colecciones que comparten nombre con datos reales pero no son territorios
  /// de campo.
  static const Set<String> _pseudoTerritorios = {
    'removidas',
    'estadisticas',
    'campanas',
  };

  /// Ciclo actual: el mes calendario. El reinicio mensual corre al principio
  /// del mes, así que el mes calendario coincide con la frontera real del ciclo
  /// y no depende de que el proceso llegó a ejecutarse.
  static String cicloActual() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  static String idDeSesion(String territorioId, String ciclo) =>
      '${territorioId}__$ciclo';

  /// Carga el progreso de todos los territorios y sincroniza sus sesiones.
  ///
  /// [sincronizar] en `false` deja todo en modo lectura pura: calcula igual, pero
  /// no escribe ni un solo documento. Sirve para previsualizar y para pruebas.
  static Future<ResumenSesionesTerritorio> cargar({
    bool sincronizar = true,
  }) async {
    try {
      final db = FirebaseFirestore.instance;

      final terSnap = await db.collection('territorios').get();
      final dirsSnap = await db.collection('direcciones_globales').get();
      final tarjetasSnap = await db.collectionGroup('tarjetas').get();
      final removidasSnap = await db.collection('direcciones_removidas').get();

      // ── Territorios reales ─────────────────────────────────────────
      final idsTerritorio = <String>{};
      final nombrePorId = <String, String>{};
      // Índice normalizado: clave comparada -> ID real. Se indexan tanto el ID
      // como el `nombre` porque los dos sirven para identificar al territorio.
      final idTerritorioPorNorm = <String, String>{};
      final idBasePorNorm = <String, String>{};
      for (final t in terSnap.docs) {
        if (_pseudoTerritorios.contains(t.id)) continue;
        final d = t.data();
        final nombre = d['nombre']?.toString() ?? t.id;
        // Los territorios de tipo 'base' son agrupadores, no territorios de
        // campo con direcciones propias. Mismo criterio que usa la sección
        // "Por territorio" de Estadísticas, pero acá se los indexa aparte para
        // poder reportar cuántas direcciones quedan fuera en vez de perderlas.
        if (d['tipo'] == 'base') {
          idBasePorNorm[_norm(t.id)] = t.id;
          idBasePorNorm[_norm(nombre)] = t.id;
          continue;
        }
        idsTerritorio.add(t.id);
        nombrePorId[t.id] = nombre;
        idTerritorioPorNorm[_norm(t.id)] = t.id;
        idTerritorioPorNorm[_norm(nombre)] = t.id;
      }
      if (idsTerritorio.isEmpty) {
        return const ResumenSesionesTerritorio(
          sesiones: [],
          cobertura: CoberturaDirecciones(
            total: 0,
            medidas: 0,
            enTerritoriosBase: 0,
            sinTerritorio: 0,
          ),
        );
      }

      // ── Índice de direcciones ───────────────────────────────────────
      // Cada dirección se asigna a UN solo territorio y se corta en el primer
      // acierto. Si una dirección matcheara dos territorios sumaría en ambos
      // denominadores y las barras nunca cerrarían.
      final dirs = <String, _DirInfo>{};
      final territorioDeDir = <String, String>{};
      var enTerritoriosBase = 0;
      var sinTerritorio = 0;
      for (final doc in dirsSnap.docs) {
        final d = doc.data();
        final info = _DirInfo(
          id: doc.id,
          calle: d['calle']?.toString() ??
              d['direccion_normalizada']?.toString() ??
              '',
          completada: _esPredicada(d),
          cerrada: _esComercioCerrado(d),
          fechaPredicacion: _leerFecha(d['fecha_predicacion']),
          creadaEn: _leerFecha(d['created_at'] ?? d['creado_el']),
        );
        dirs[doc.id] = info;
        final ter = _resolverTerritorio(
          d,
          idTerritorioPorNorm: idTerritorioPorNorm,
        );
        if (ter != null) {
          territorioDeDir[doc.id] = ter;
          continue;
        }
        // No es de campo. Se cuenta para poder informarlo, sin inventarle un
        // territorio.
        if (_perteneceAAlgunTerritorio(d, idBasePorNorm)) {
          enTerritoriosBase++;
        } else {
          sinTerritorio++;
        }
      }

      final idsRemovidas = removidasSnap.docs.map((d) => d.id).toSet();

      // ── Tarjetas por territorio ─────────────────────────────────────
      final tarjetasPorTerritorio = <String, List<DatosTarjetaSesion>>{};
      for (final doc in tarjetasSnap.docs) {
        final d = doc.data();
        final ter = d['territorio_id']?.toString() ?? '';
        if (ter.isEmpty || !idsTerritorio.contains(ter)) continue;
        (tarjetasPorTerritorio[ter] ??= []).add(
          DatosTarjetaSesion(
            id: doc.id,
            nombre: d['nombre']?.toString() ?? doc.id,
            completada: d['completada'] == true,
            enviadaEn: _leerFecha(d['enviado_en']),
            completadaEn: _leerFecha(d['fecha_completada']),
          ),
        );
      }

      final enJuegoPorTerritorio = <String, List<String>>{};
      for (final e in territorioDeDir.entries) {
        (enJuegoPorTerritorio[e.value] ??= []).add(e.key);
      }

      // ── Sesiones del ciclo ──────────────────────────────────────────
      final ciclo = cicloActual();
      final sesSnap = await _ref.where('ciclo', isEqualTo: ciclo).get();
      final sesPorTerritorio = <String, Map<String, dynamic>>{};
      for (final doc in sesSnap.docs) {
        final d = doc.data();
        final ter = d['territorio_id']?.toString() ?? '';
        if (ter.isNotEmpty) sesPorTerritorio[ter] = d;
      }

      // ── Un resultado por territorio ─────────────────────────────────
      final resultado = <SesionTerritorio>[];
      for (final terId in idsTerritorio) {
        final enJuego = enJuegoPorTerritorio[terId] ?? const <String>[];

        // Territorio sin direcciones: no hay nada que medir. Tampoco se
        // inventa una fecha de inicio, que sería falsa.
        if (enJuego.isEmpty) continue;

        final bruto = _calcularProgreso(
          territorioId: terId,
          territorioNombre: nombrePorId[terId] ?? terId,
          idsEnJuego: enJuego,
          dirs: dirs,
          idsRemovidas: idsRemovidas,
          tarjetas: tarjetasPorTerritorio[terId] ?? const [],
        );

        final sesion = await _sincronizar(
          territorioId: terId,
          territorioNombre: nombrePorId[terId] ?? terId,
          ciclo: ciclo,
          existente: sesPorTerritorio[terId],
          bruto: bruto,
          dirs: dirs,
          idsRemovidas: idsRemovidas,
          persistir: sincronizar,
        );

        resultado.add(sesion);
      }

      // Primero lo más cerca de cerrarse; entre los completos, el que más
      // rápido se terminó.
      resultado.sort((a, b) {
        final pa = a.progreso?.porcentaje ?? 0;
        final pb = b.progreso?.porcentaje ?? 0;
        if ((pa - pb).abs() > 0.001) return pb.compareTo(pa);
        final da = a.duracion?.inHours ?? 1 << 30;
        final db_ = b.duracion?.inHours ?? 1 << 30;
        return da.compareTo(db_);
      });

      return ResumenSesionesTerritorio(
        sesiones: resultado,
        cobertura: CoberturaDirecciones(
          total: dirs.length,
          medidas: territorioDeDir.length,
          enTerritoriosBase: enTerritoriosBase,
          sinTerritorio: sinTerritorio,
        ),
      );
    } catch (e, st) {
      developer.log(
        'No se pudieron cargar las sesiones de territorio',
        name: 'SesionesTerritorio',
        error: e,
        stackTrace: st,
      );
      return const ResumenSesionesTerritorio(
        sesiones: [],
        cobertura: CoberturaDirecciones(
          total: 0,
          medidas: 0,
          enTerritoriosBase: 0,
          sinTerritorio: 0,
        ),
      );
    }
  }

  /// ¿La dirección apunta a un territorio agrupador de tipo `base`?
  static bool _perteneceAAlgunTerritorio(
    Map<String, dynamic> d,
    Map<String, String> idBasePorNorm,
  ) {
    for (final campo in const [
      'territorio_id',
      'territorio_nombre',
      'barrio',
    ]) {
      if (idBasePorNorm.containsKey(_norm(d[campo]?.toString()))) return true;
    }
    return false;
  }

  /// Sesiones ya cerradas de un territorio, para comparar "este mes 9 días, el
  /// anterior 12". Se consulta al abrir el detalle, no en la carga general.
  static Future<List<SesionTerritorio>> historial(String territorioId) async {
    try {
      final snap = await _ref
          .where('territorio_id', isEqualTo: territorioId)
          .limit(200)
          .get();
      final lista =
          snap.docs.map((doc) => _desdeMapa(doc.id, doc.data())).toList();
      lista.sort((a, b) => b.ciclo.compareTo(a.ciclo));
      return lista;
    } catch (e, st) {
      developer.log('No se pudo leer el historial de sesiones',
          name: 'SesionesTerritorio', error: e, stackTrace: st);
      return const [];
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // INTERNO
  // ────────────────────────────────────────────────────────────────────

  /// Calcula el estado de la sesión y la persiste SOLO si algo cambió de
  /// verdad. Si no cambió, no escribe: así abrir Estadísticas cien veces no
  /// genera cien escrituras.
  static Future<SesionTerritorio> _sincronizar({
    required String territorioId,
    required String territorioNombre,
    required String ciclo,
    required Map<String, dynamic>? existente,
    required ProgresoTerritorio bruto,
    required Map<String, _DirInfo> dirs,
    required Set<String> idsRemovidas,
    required bool persistir,
  }) async {
    final id = idDeSesion(territorioId, ciclo);

    final alcanceInicial = existente == null
        // Sesión nueva: el alcance es lo pendiente HOY. Lo ya predicado queda
        // fuera y se informa aparte, para que la barra arranque en 0% en vez de
        // medir un trabajo que empezó antes de existir la sesión.
        ? (bruto.idsEnJuego.toList()
          ..removeWhere(bruto.idsPredicadas.toSet().contains))
        : _listaIds(existente['ids_alcance']);

    var llegados =
        existente == null ? <String>[] : _listaIds(existente['ids_llegados']);
    final yaContadas = {...alcanceInicial, ...llegados};
    final enJuegoBruto = bruto.idsEnJuego.toSet();

    // Direcciones que entraron al territorio DESPUÉS de que arrancó el ciclo.
    //
    // Solo tiene sentido calcularlas si la sesión ya existía. En una sesión
    // nueva, el alcance es por definición todo lo pendiente, así que todo lo
    // demás que aparezca sería o bien algo ya predicado (falso "llegado") o
    // bien algo que ya estaba antes. Sin este filtro, un territorio que ya
    // estaba 100% al abrir la app cerraba solo, con duración cero.
    final nuevos = <String>[];
    if (existente != null) {
      for (final idDir in bruto.idsEnJuego) {
        if (yaContadas.contains(idDir)) continue;
        if (llegados.length + nuevos.length >= kMaxIdsPorSesion) break;
        nuevos.add(idDir);
      }
    }
    llegados = [...llegados, ...nuevos];

    // ── Recalcular el alcance de la sesión ───────────────────────────
    final alcance = <String>{...alcanceInicial, ...llegados};
    final preds = <String>[];
    final retiradasIds = <String>{};
    var sinRastro = 0;
    DateTime? inicio;
    DateTime? cierre;

    for (final idDir in alcance) {
      final info = dirs[idDir];
      if (info == null) {
        // Ya no existe en `direcciones_globales`. Sale del denominador para no
        // dejar la sesión colgada; si tampoco está en `direcciones_removidas`
        // se marca como sin rastro para que el dato no se esconda.
        retiradasIds.add(idDir);
        if (!idsRemovidas.contains(idDir)) sinRastro++;
        continue;
      }
      if (!enJuegoBruto.contains(idDir)) {
        // Sigue existiendo pero dejó de ser de este territorio: se mudó. No es
        // una baja, es una reasignación, pero para esta sesión también sale.
        retiradasIds.add(idDir);
        continue;
      }
      if (info.cerrada) {
        retiradasIds.add(idDir);
        continue;
      }
      if (info.completada) {
        preds.add(idDir);        final f = info.fechaPredicacion;
        if (f != null) {
          if (inicio == null || f.isBefore(inicio)) inicio = f;
          if (cierre == null || f.isAfter(cierre)) cierre = f;
        }
      }
    }

    // El alcance de la SESIÓN excluye las retiradas: un comercio cerrado en
    // mitad de ciclo no puede dejar la sesión colgada para siempre.
    //
    // Ojo con la diferencia entre los dos denominadores, que es deliberada:
    //
    //   `alcanceVivo` = el trabajo congelado de ESTA sesión. Es lo que se mide
    //                   en el tiempo y lo que decide si la sesión cierra.
    //   `bruto`       = TODO el territorio vivo, incluidas las direcciones que
    //                   ya estaban predicadas antes de existir la sesión. Es lo
    //                   que se muestra en la barra.
    //
    // Confundirlos hacía que una barra arrancara en 0% aunque el territorio
    // tuviera 16 de 52 predichos, que es justo lo que el usuario pidió ver.
    final retiradasDeAmbito = retiradasIds.length;
    final alcanceVivo =
        alcance.where((x) => !retiradasIds.contains(x)).toList();

    // Avance DENTRO del alcance de la sesión: lo único que sirve para calcular
    // ritmo y proyección. Medir el ritmo sobre el avance del territorio daría
    // un número inflado por todo lo que ya estaba hecho antes de arrancar.
    final avanceAlcance = preds.length;

    // El territorio está completo cuando TODO lo que sigue vivo está
    // predicado. Como el denominador es el territorio vivo, decir 100% no
    // admite excepciones: o se predijo todo, o no se llegó.
    final territorioVivo = bruto.idsEnJuego.length;
    final territorioCompleto =
        territorioVivo > 0 && bruto.idsPredicadas.length >= territorioVivo;

    // Territorio que ya estaba terminado antes de existir la sesión: no hay
    // trabajo pendiente que medir, así que se muestra con la barra llena pero
    // SIN fecha de cierre, que sería inventada.
    final yaEstabaCompleto =
        existente == null && alcanceVivo.isEmpty && territorioCompleto;

    // Espejo del getter `SesionTerritorio.llegadosPendientes`. Se calcula acá
    // porque la máquina de estados lo necesita antes de armar el objeto.
    // Mismo criterio: contra el territorio vivo, que es lo que la barra muestra.
    final predsTerritorio = bruto.idsPredicadas.toSet();
    final enJuegoTerritorio = bruto.idsEnJuego.toSet();
    final llegadosPendientesEnBruto = llegados
        .where((id) =>
            enJuegoTerritorio.contains(id) && !predsTerritorio.contains(id))
        .length;

    // ── Máquina de estados ───────────────────────────────────────────
    final cambios = <String, dynamic>{};
    if (nuevos.isNotEmpty) cambios['ids_llegados'] = llegados;

    // El avance de la sesión se archiva para que el historial pueda mostrar
    // ritmo y duración de ciclos ya cerrados. Se escribe solo cuando cambia,
    // junto con el resto, para no generar una escritura por cada apertura de
    // Estadísticas.
    final avanceGuardado = (existente?['avance_alcance'] as num?)?.toInt();
    if (existente == null || avanceGuardado != avanceAlcance) {
      cambios['avance_alcance'] = avanceAlcance;
      cambios['alcance_vivo'] = alcanceVivo.length;
    }

    var inicioFinal = _leerFecha(existente?['inicio_en']) ?? inicio;
    if (inicio != null && inicioFinal == null) {
      inicioFinal = inicio;
      cambios['inicio_en'] = inicio;
    }

    var cierreFinal = _leerFecha(existente?['cierre_en']);
    var cierrePrimera = _leerFecha(existente?['cierre_primera_vez_en']);
    var reaperturas = (existente?['reaperturas'] as num?)?.toInt() ?? 0;
    String estadoFinal;
    DateTime? ahora = DateTime.now();

    if (yaEstabaCompleto) {
      // No hay ciclo que cerrar ni que abrir: el trabajo ya estaba hecho antes
      // de que existiera la sesión. No se escribe `inicio_en` ni `cierre_en`.
      estadoFinal = kSesionSinMedir;
      if (existente?['estado'] != kSesionSinMedir) {
        cambios['estado'] = estadoFinal;
      }
    } else if (territorioCompleto && llegadosPendientesEnBruto == 0) {
      estadoFinal = kSesionCerrada;
      if (existente == null || existente['estado'] != kSesionCerrada) {
        cambios['estado'] = estadoFinal;
        cierreFinal = cierre ?? ahora;
        cambios['cierre_en'] = cierreFinal;
        // El primer cierre del ciclo es dato histórico: se escribe una vez.
        if (cierrePrimera == null) {
          cierrePrimera = cierreFinal;
          cambios['cierre_primera_vez_en'] = cierrePrimera;
        }
      }
    } else {
      estadoFinal = inicioFinal != null ? kSesionEnCurso : kSesionAbierta;
      if (existente == null || existente['estado'] != estadoFinal) {
        cambios['estado'] = estadoFinal;
        if (existente?['estado'] == kSesionCerrada) {
          // El ciclo se rompió: entraron direcciones nuevas. Se reabre, pero el
          // cierre original se conserva.
          reaperturas++;
          cambios['reaperturas'] = reaperturas;
        }
      }
      if (cierreFinal != null) {
        cierreFinal = null;
        cambios['cierre_en'] = null;
      }
    }

    // ── Persistir, solo si hay algo que cambiar ──────────────────────
    if (existente != null && cambios.isEmpty) {
      return _armar(
        id: id,
        territorioId: territorioId,
        territorioNombre: territorioNombre,
        ciclo: ciclo,
        estado: estadoFinal,
        alcance: alcanceInicial,
        llegados: llegados,
        previas: (existente['completadas_previas'] as num?)?.toInt() ??
            bruto.idsPredicadas.length,
        abiertaEn: _leerFecha(existente['abierta_en']),
        inicio: inicioFinal,
        cierre: cierreFinal,
        cierrePrimera: cierrePrimera,
        reaperturas: reaperturas,
        ultimaLectura: _leerFecha(existente['ultima_lectura_en']),
        avanceAlcance: avanceAlcance,
        alcanceVivo: alcanceVivo.length,
        idsEnJuego: bruto.idsEnJuego,
        preds: bruto.idsPredicadas,
        retiradas: retiradasDeAmbito,
        sinRastro: sinRastro + bruto.retiradasSinRastro,
        inicioPred: bruto.primeraPredicacion,
        finPred: bruto.ultimaPredicacion,
        tarjetas: bruto.tarjetas,
        dirs: dirs,
      );
    }

    if (persistir) {
      cambios['ultima_lectura_en'] = FieldValue.serverTimestamp();

      try {
        if (existente == null) {
          await _ref.doc(id).set({
            'sesion_id': id,
            'territorio_id': territorioId,
            'territorio_nombre': territorioNombre,
            'ciclo': ciclo,
            'estado': estadoFinal,
            'ids_alcance': alcanceInicial,
            'ids_llegados': llegados,
            'completadas_previas': bruto.idsPredicadas.length,
            'avance_alcance': avanceAlcance,
            'alcance_vivo': alcanceVivo.length,
            'abierta_en': FieldValue.serverTimestamp(),
            ...cambios,
          });
        } else {
          await _ref.doc(id).set(cambios, SetOptions(merge: true));
        }
      } catch (e, st) {
        // Si el archivo falla, la barra se sigue mostrando. La pantalla no puede
        // quedar en blanco por no poder escribir la sesión.
        developer.log('No se pudo archivar la sesión de $territorioId',
            name: 'SesionesTerritorio', error: e, stackTrace: st);
      }
    }

    return _armar(
      id: id,
      territorioId: territorioId,
      territorioNombre: territorioNombre,
      ciclo: ciclo,
      estado: estadoFinal,
      alcance: alcanceInicial,
      llegados: llegados,
      previas: (existente?['completadas_previas'] as num?)?.toInt() ??
          bruto.idsPredicadas.length,
      abiertaEn: existente != null
          ? _leerFecha(existente['abierta_en'])
          : DateTime.now(),
      inicio: inicioFinal,
      cierre: cierreFinal,
      cierrePrimera: cierrePrimera,
      reaperturas: reaperturas,
      ultimaLectura: DateTime.now(),
      avanceAlcance: avanceAlcance,
      alcanceVivo: alcanceVivo.length,
      idsEnJuego: bruto.idsEnJuego,
      preds: bruto.idsPredicadas,
      retiradas: retiradasDeAmbito,
      sinRastro: sinRastro + bruto.retiradasSinRastro,
      inicioPred: bruto.primeraPredicacion,
      finPred: bruto.ultimaPredicacion,
      tarjetas: bruto.tarjetas,
      dirs: dirs,
    );
  }

  static SesionTerritorio _armar({
    required String id,
    required String territorioId,
    required String territorioNombre,
    required String ciclo,
    required String estado,
    required List<String> alcance,
    required List<String> llegados,
    required int previas,
    required DateTime? abiertaEn,
    required DateTime? inicio,
    required DateTime? cierre,
    required DateTime? cierrePrimera,
    required int reaperturas,
    required DateTime? ultimaLectura,
    required int avanceAlcance,
    required int alcanceVivo,
    required List<String> idsEnJuego,
    required List<String> preds,
    required int retiradas,
    required int sinRastro,
    required DateTime? inicioPred,
    required DateTime? finPred,
    required List<DatosTarjetaSesion> tarjetas,
    required Map<String, _DirInfo> dirs,
  }) {
    final predsSet = preds.toSet();
    final enJuegoSet = idsEnJuego.toSet();
    return SesionTerritorio(
      id: id,
      territorioId: territorioId,
      territorioNombre: territorioNombre,
      ciclo: ciclo,
      estado: estado,
      idsAlcance: alcance,
      idsLlegados: llegados,
      completadasPrevias: previas,
      abiertaEn: abiertaEn,
      inicioEn: inicio,
      cierreEn: cierre,
      cierrePrimeraVezEn: cierrePrimera,
      reaperturas: reaperturas,
      ultimaLecturaEn: ultimaLectura,
      avanceAlcance: avanceAlcance,
      alcanceVivo: alcanceVivo,
      llegadas: llegados.map((l) {
        final info = dirs[l];
        return DatoLlegada(
          id: l,
          calle: info?.calle ?? '(dirección eliminada)',
          creadaEn: info?.creadaEn,
          completada: predsSet.contains(l) && enJuegoSet.contains(l),
        );
      }).toList(),
      progreso: ProgresoTerritorio(
        territorioId: territorioId,
        territorioNombre: territorioNombre,
        // Todo lo de este bloque es de TERRITORIO, no de sesión: son los mismos
        // números que alimentan la barra, y el `retiradas` que acompaña a la
        // barra tiene que ser del mismo universo. `_sincronizar` ya lo pasa
        // con ese criterio.
        idsEnJuego: idsEnJuego,
        idsPredicadas: preds,
        retiradas: retiradas,
        retiradasSinRastro: sinRastro,
        primeraPredicacion: inicioPred,
        ultimaPredicacion: finPred,
        tarjetas: tarjetas,
      ),
    );
  }

  static ProgresoTerritorio _calcularProgreso({
    required String territorioId,
    required String territorioNombre,
    required List<String> idsEnJuego,
    required Map<String, _DirInfo> dirs,
    required Set<String> idsRemovidas,
    required List<DatosTarjetaSesion> tarjetas,
  }) {
    final preds = <String>[];
    // El denominador de la barra son las direcciones del territorio que SIGUEN
    // vivas. Los comercios cerrados salen: si contaran, una barra nunca podría
    // llegar a 100% y el cierre de la sesión no llegaría nunca.
    final vivos = <String>[];
    var sinRastro = 0;
    DateTime? primera;
    DateTime? ultima;

    for (final id in idsEnJuego) {
      final info = dirs[id];
      if (info == null) {
        if (!idsRemovidas.contains(id)) sinRastro++;
        continue;
      }
      if (info.cerrada) continue;
      vivos.add(id);
      if (info.completada) {
        preds.add(id);
        final f = info.fechaPredicacion;
        if (f != null) {
          if (primera == null || f.isBefore(primera)) primera = f;
          if (ultima == null || f.isAfter(ultima)) ultima = f;
        }
      }
    }

    return ProgresoTerritorio(
      territorioId: territorioId,
      territorioNombre: territorioNombre,
      idsEnJuego: vivos,
      idsPredicadas: preds,
      // En el paso bruto solo se detectan los cierros de comercio; las bajas y
      // mudanzas de territorio se recalculan por sesión en `_sincronizar`.
      retiradas: idsEnJuego.length - vivos.length,
      retiradasSinRastro: sinRastro,
      primeraPredicacion: primera,
      ultimaPredicacion: ultima,
      tarjetas: tarjetas,
    );
  }

  static SesionTerritorio _desdeMapa(String id, Map<String, dynamic> d) {
    return SesionTerritorio(
      id: d['sesion_id']?.toString() ?? id,
      territorioId: d['territorio_id']?.toString() ?? '',
      territorioNombre: d['territorio_nombre']?.toString() ?? '',
      ciclo: d['ciclo']?.toString() ?? '',
      estado: d['estado']?.toString() ?? kSesionAbierta,
      idsAlcance: _listaIds(d['ids_alcance']),
      idsLlegados: _listaIds(d['ids_llegados']),
      completadasPrevias: (d['completadas_previas'] as num?)?.toInt() ?? 0,
      abiertaEn: _leerFecha(d['abierta_en']),
      inicioEn: _leerFecha(d['inicio_en']),
      cierreEn: _leerFecha(d['cierre_en']),
      cierrePrimeraVezEn: _leerFecha(d['cierre_primera_vez_en']),
      reaperturas: (d['reaperturas'] as num?)?.toInt() ?? 0,
      ultimaLecturaEn: _leerFecha(d['ultima_lectura_en']),
      // El historial se archivó cuando el avance era del ALCANCE, así que acá
      // `avanceAlcance` es el que quedó guardado. Sin ese campo, documentos
      // viejos devolverían 0 y el ritmo histórico saldría en cero.
      avanceAlcance: (d['avance_alcance'] as num?)?.toInt() ??
          (d['ids_alcance'] as List?)?.length ??
          0,
      alcanceVivo: (d['alcance_vivo'] as num?)?.toInt() ??
          (d['ids_alcance'] as List?)?.length ??
          0,
    );
  }

  static List<String> _listaIds(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  /// Normaliza un nombre o ID de territorio para poder compararlo.
  ///
  /// Los datos reales no son consistentes entre sí. Medido contra Firestore:
  /// hay direcciones con `barrio = "Iguaçu"` frente a un territorio `IGUAÇU`,
  /// `barrio = "Costeira"` frente a `COSTEIRA`, y
  /// `barrio = "Campina Da Barra"` frente al documento `CAMPINA_DA_BARRA`, cuyo
  /// campo `nombre` es `CAMPINA DA BARRA`. Sin normalizar, esas direcciones no
  /// matchean ningún territorio y desaparecen de todos los denominadores: la
  /// barra mostraría un número más bajo que la realidad.
  ///
  /// El guion bajo y el espacio se tratan como el mismo separador justamente
  /// por el caso `CAMPINA_DA_BARRA` / `CAMPINA DA BARRA`, que son el mismo
  /// territorio escrito de dos formas.
  static String _norm(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '';
    return s.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  /// Determina a qué territorio de campo pertenece una dirección, cortando en
  /// el primer acierto para que nunca cuente en dos denominadores.
  ///
  /// El orden de los campos ES la prioridad. `territorio_id` manda y después
  /// quedan los nombres.
  static String? _resolverTerritorio(
    Map<String, dynamic> d, {
    required Map<String, String> idTerritorioPorNorm,
  }) {
    for (final campo in const [
      'territorio_id',
      'barrio',
      'territorio_nombre',
    ]) {
      final id = idTerritorioPorNorm[_norm(d[campo]?.toString())];
      if (id != null) return id;
    }
    return null;
  }

  static bool _esPredicada(Map<String, dynamic> d) =>
      d['estado_predicacion'] == 'completada' || d['predicado'] == true;

  static bool _esComercioCerrado(Map<String, dynamic> d) =>
      d['estado'] == 'comercio_cerrado' ||
      d['estado_predicacion'] == 'comercio_cerrado';

  static DateTime? _leerFecha(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) {
      if (v <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

/// Estado mínimo de una dirección para el cálculo.
class _DirInfo {
  final String id;
  final String calle;
  final bool completada;
  final bool cerrada;
  final DateTime? fechaPredicacion;
  final DateTime? creadaEn;

  _DirInfo({
    required this.id,
    required this.calle,
    required this.completada,
    required this.cerrada,
    required this.fechaPredicacion,
    required this.creadaEn,
  });
}
