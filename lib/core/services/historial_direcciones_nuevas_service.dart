import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Historial PERMANENTE de direcciones nuevas agregadas a una tarjeta.
///
/// POR QUÉ EXISTE Y POR QUÉ NO SE USÓ `historial_auditoria`
///
/// La bandeja `sugerencias` es de trabajo, no de archivo: apenas una sugerencia
/// se procesa se borra (ver `_confirmarAsignacionManual` y
/// `_guardarPlanReorganizacion` en `auditor_panel_page.dart`). Si el historial
/// se arma leyendo `sugerencias`, cada dirección nueva desaparece del historial
/// justo en el momento en que queda bien guardada, que es lo contrario de lo
/// que un historial tiene que hacer.
///
/// La auditoría tampoco servía, por dos razones concretas:
///
///  1. La asignación manual escribe `accion_tomada` pero NO `tipo_evento` ni
///     `accion`, así que el lector de la línea 5502 caía al caso 'AUDITORIA'
///     genérico y la dirección no se distinguía de una búsqueda POI.
///  2. La reorganización por IA escribe UN solo evento agregado con el plan
///     completo adentro, no un evento por dirección. Al renderizarlo se veía
///     "Sin dirección" y sin territorio.
///
/// Ninguna de las dos guardaba el ID del documento creado en
/// `direcciones_globales`, que es lo único que permite verificar años después
/// que la dirección se agregó de verdad y no solo se anotó.
///
/// QUÉ ES APEND-ONLY
///
/// Este servicio solo agrega documentos y solo los lee. Ninguna ruta borra ni
/// reescribe entradas. Eso es deliberado: un historial del que se puede
/// borrar es una lista, no un historial.

/// Cómo se originó la dirección.
const String kOrigenManual = 'asignacion_manual';
const String kOrigenIa = 'reorganizacion_ia';

/// Registro reconstruido a posteriori por migración, no por el flujo normal.
///
/// Se usa para las direcciones que YA estaban agregadas a una tarjeta antes de
/// que existiera este historial. La marca existe para no mezclar lo registrado
/// en vivo con lo reconstruido: la fecha es la de creación real de la
/// dirección, pero el momento en que seicarbonizó al historial es posterior, y
/// eso hay que poder verlo.
const String kOrigenMigracion = 'migracion_historial';

/// Una dirección nueva, ya agregada a una tarjeta, con su rastro permanente.
class RegistroDireccionNueva {
  final String id;

  /// ID del documento creado en `direcciones_globales`. Es el ancla: sin esto el
  /// historial afirma que algo se agregó sin poder probar qué.
  final String direccionId;
  final String calle;
  final String complemento;
  final String barrio;
  final String tarjetaId;
  final String territorioId;
  final String origen;
  final String usuario;

  /// Nombre real de la persona (ej. "Angel Rivas"). Se prefiere sobre
  /// [usuario] (email) al mostrar quién agregó la dirección.
  final String usuarioNombre;

  /// Quién ENVIÓ la dirección (el publicador que la reportó), distinto de
  /// [usuario], que es quien la agregó a la tarjeta. Viene de la sugerencia.
  final String enviadoPor;
  final String enviadoPorNombre;
  final DateTime? fecha;

  /// ID de la sugerencia original, para poder cruzarla con `sugerencias` si
  /// todavía existe.
  final String sugerenciaId;

  RegistroDireccionNueva({
    required this.id,
    required this.direccionId,
    required this.calle,
    required this.complemento,
    required this.barrio,
    required this.tarjetaId,
    required this.territorioId,
    required this.origen,
    required this.usuario,
    this.usuarioNombre = '',
    this.enviadoPor = '',
    this.enviadoPorNombre = '',
    required this.fecha,
    required this.sugerenciaId,
  });

  factory RegistroDireccionNueva.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RegistroDireccionNueva(
      id: doc.id,
      direccionId: d['direccion_id']?.toString() ?? '',
      calle: d['calle']?.toString() ?? '',
      complemento: d['complemento']?.toString() ?? '',
      barrio: d['barrio']?.toString() ?? '',
      tarjetaId: d['tarjeta_id']?.toString() ?? '',
      territorioId: d['territorio_id']?.toString() ?? '',
      origen: d['origen']?.toString() ?? '',
      usuario: d['usuario']?.toString() ?? '',
      usuarioNombre: d['usuario_nombre']?.toString() ?? '',
      enviadoPor: d['enviado_por']?.toString() ?? '',
      enviadoPorNombre: d['enviado_por_nombre']?.toString() ?? '',
      sugerenciaId: d['sugerencia_id']?.toString() ?? '',
      fecha: _leerFecha(d['fecha']),
    );
  }

  /// Texto tal como lo buscaría la persona: calle + complemento.
  String get textoBusqueda =>
      complemento.isEmpty ? calle : '$calle, $complemento';

  static DateTime? _leerFecha(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

/// Estado actual de una dirección registrada, contrastado contra
/// `direcciones_globales` en el momento de verificar.
class VerificacionDireccion {
  final String direccionId;
  final String calle;

  /// `false` si el documento ya no existe: la dirección se registró pero no
  /// llegó a crearse, o se borró después.
  final bool existe;

  /// Territorio actual, que puede diferir del que se le asignó al crearla.
  final String territorioActual;

  /// Tarjeta actual. Si está vacía la dirección quedó sin tarjeta.
  final String tarjetaActual;

  final String estadoActual;
  final String estadoPredicacion;
  final bool predicado;

  VerificacionDireccion({
    required this.direccionId,
    required this.calle,
    required this.existe,
    required this.territorioActual,
    required this.tarjetaActual,
    required this.estadoActual,
    required this.estadoPredicacion,
    required this.predicado,
  });

  /// `true` si la dirección está Created pero todavía no se predicó. No es un
  /// error: es el estado normal de una dirección recién agregada.
  bool get pendienteDePredicar => existe && !predicado;

  /// `true` solo si el documento desapareció. Eso sí merece atención.
  bool get desaparecida => !existe;
}

class HistorialDireccionesNuevasService {
  HistorialDireccionesNuevasService._();

  static CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('historial_direcciones_nuevas');

  /// Registra UNA dirección nueva ya agregada a una tarjeta.
  ///
  /// [direccionId] debe ser el ID real del documento creado en
  /// `direcciones_globales`. Si se pasa vacío, el registro se guarda igual pero
  /// marcado como no verificable: es preferible un registro sin ancla a ningún
  /// registro, porque el síntoma que querés evitar es justo que las direcciones
  /// nuevas desaparezcan del historial.
  ///
  /// Devuelve `true` solo si la escritura quedó confirmada.
  static Future<bool> registrar({
    required String direccionId,
    required String calle,
    String complemento = '',
    String barrio = '',
    String tarjetaId = '',
    String territorioId = '',
    required String origen,
    String usuario = '',
    String usuarioNombre = '',
    String enviadoPor = '',
    String enviadoPorNombre = '',
    String sugerenciaId = '',
  }) async {
    try {
      await _ref.add({
        'direccion_id': direccionId,
        'calle': calle,
        'complemento': complemento,
        'barrio': barrio,
        'tarjeta_id': tarjetaId,
        'territorio_id': territorioId,
        'origen': origen,
        'usuario': usuario,
        'usuario_nombre': usuarioNombre,
        'enviado_por': enviadoPor,
        'enviado_por_nombre': enviadoPorNombre,
        'sugerencia_id': sugerenciaId,
        'fecha': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      developer.log(
        'No se pudo registrar en el historial la direccion nueva "$calle" '
        '($direccionId). La direccion quedo agregada a la tarjeta pero sin '
        'rastro permanente, asi que el historial no la va a mostrar.',
        name: 'historial_direcciones_nuevas',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Historial completo, más reciente primero.
  ///
  /// [limite] existe para que la pantalla no traiga el archivo entero de
  /// golpe. El historial ya NO se corta de forma silenciosa como antes: la
  /// respuesta incluye cuántos hay en total, así la interfaz puede decir
  /// "mostrando 200 de 1.500" en vez de hacer creer que son 200.
  static Future<HistorialPaginado> historial({int limite = 200}) async {
    try {
      final snap =
          await _ref.orderBy('fecha', descending: true).limit(limite).get();
      final registros =
          snap.docs.map(RegistroDireccionNueva.fromDoc).toList(growable: false);

      // Total real, para noMentirle al usuario con el corte.
      var total = registros.length;
      if (snap.size == limite) {
        try {
          total = (await _ref.count().get()).count ?? registros.length;
        } catch (_) {
          // Sin permiso de conteo se degrada al total visible en vez de fallar.
          total = registros.length;
        }
      }

      return HistorialPaginado(
          registros: registros, total: total, hayMas: total > registros.length);
    } catch (e, st) {
      developer.log('No se pudo leer el historial de direcciones nuevas',
          name: 'historial_direcciones_nuevas', error: e, stackTrace: st);
      return const HistorialPaginado(registros: [], total: 0, hayMas: false);
    }
  }

  /// Cruza los registros contra `direcciones_globales` y dice, una por una, si
  /// la dirección realmente existe hoy y en qué estado está.
  ///
  /// Esto es lo que permite verificar que las direcciones nuevas se agregaron
  /// bien: sin este contraste, el historial solo afirma que algo se hizo.
  static Future<List<VerificacionDireccion>> verificar(
    List<RegistroDireccionNueva> registros,
  ) async {
    if (registros.isEmpty) return const [];
    final db = FirebaseFirestore.instance;
    final out = <VerificacionDireccion>[];
    try {
      // Se leen en lotes porque `getAll` sobre cientos de IDs de una vez es
      // lento; el historial se abre a menudo y no puede bloquear la pantalla.
      for (final chunk in _trocear(registros, 40)) {
        final ids = chunk
            .map((r) => r.direccionId)
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.isEmpty) {
          for (final r in chunk) {
            out.add(VerificacionDireccion(
              direccionId: r.direccionId,
              calle: r.textoBusqueda,
              existe: false,
              territorioActual: '',
              tarjetaActual: '',
              estadoActual: 'sin_ancla',
              estadoPredicacion: '',
              predicado: false,
            ));
          }
          continue;
        }
        final snaps = await db
            .collection('direcciones_globales')
            .where(FieldPath.documentId, isEqualTo: ids)
            .get();
        final porId = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final s in snaps.docs) {
          porId[s.id] = s;
        }
        for (final r in chunk) {
          final s = r.direccionId.isEmpty ? null : porId[r.direccionId];
          final d = s?.data();
          out.add(VerificacionDireccion(
            direccionId: r.direccionId,
            calle: r.textoBusqueda,
            existe: d != null,
            territorioActual: d?['territorio_id']?.toString() ?? '',
            tarjetaActual: d?['tarjeta_id']?.toString() ?? '',
            estadoActual: d?['estado']?.toString() ?? '',
            estadoPredicacion: d?['estado_predicacion']?.toString() ?? '',
            predicado: d?['estado_predicacion'] == 'completada' ||
                d?['predicado'] == true,
          ));
        }
      }
    } catch (e, st) {
      developer.log('No se pudo verificar el historial de direcciones nuevas',
          name: 'historial_direcciones_nuevas', error: e, stackTrace: st);
    }
    return out;
  }

  static List<List<T>> _trocear<T>(List<T> items, int porLote) {
    final out = <List<T>>[];
    for (var i = 0; i < items.length; i += porLote) {
      out.add(items.sublist(i, (i + porLote).clamp(0, items.length)));
    }
    return out;
  }
}

/// Resultado paginado: lo que se trajo y lo que hay en total.
class HistorialPaginado {
  const HistorialPaginado({
    required this.registros,
    required this.total,
    required this.hayMas,
  });

  final List<RegistroDireccionNueva> registros;

  /// Total real de documentos en la colección.
  final int total;

  /// `true` si hay más registros de los que se trajo.
  final bool hayMas;
}
