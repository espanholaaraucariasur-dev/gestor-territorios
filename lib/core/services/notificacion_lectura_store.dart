import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Estado de lectura de notificaciones **por usuario**.
///
/// Las notificaciones de [NotificacionService] son documentos compartidos
/// (un broadcast por rol lo leen varios admins). Marcar `leida` en el documento
/// afectaba a todos; por eso el estado vive en el documento del propio usuario:
///
///  - `notificaciones_leidas`: IDs leídos uno a uno.
///  - `notificaciones_leidas_hasta`: todo lo creado hasta esa fecha se
///    considera leído ("Leer todas").
///  - `notificaciones_limpiadas_hasta`: todo lo creado hasta esa fecha se
///    oculta para este usuario ("Limpiar") sin borrar el documento compartido.
///
/// Se escucha en tiempo real para que dos dispositivos del mismo usuario
/// compartan el mismo estado.
class NotificacionLecturaStore extends ChangeNotifier {
  NotificacionLecturaStore._();

  static final NotificacionLecturaStore instance = NotificacionLecturaStore._();

  String? _usuarioDocId;
  Set<String> _leidas = <String>{};
  DateTime? _leidasHasta;
  DateTime? _limpiadasHasta;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  String? get usuarioDocId => _usuarioDocId;

  /// Carga el estado desde los datos ya leídos del usuario y empieza a
  /// escuchar su documento. Es idempotente para el mismo usuario.
  void inicializar(Map<String, dynamic> usuarioData) {
    final docId = (usuarioData['docId'] ?? '').toString().trim();
    if (docId.isEmpty || docId == _usuarioDocId) return;

    _usuarioDocId = docId;
    _aplicarDatos(usuarioData);
    notifyListeners();

    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(docId)
        .snapshots()
        .listen(
      (snap) {
        final datos = snap.data();
        if (datos == null) return;
        _aplicarDatos(datos);
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Lectura de notificaciones: $error');
      },
    );
  }

  void _aplicarDatos(Map<String, dynamic> datos) {
    _leidas =
        (datos['notificaciones_leidas'] as List?)?.whereType<String>().toSet() ??
            <String>{};
    _leidasHasta = _fechaDe(datos['notificaciones_leidas_hasta']);
    _limpiadasHasta = _fechaDe(datos['notificaciones_limpiadas_hasta']);
  }

  /// ¿Este usuario ya leyó la notificación?
  bool estaLeida(String id, Map<String, dynamic> data) {
    if (_leidas.contains(id)) return true;
    final fecha = _fechaDe(data['created_at'] ?? data['enviado_en']);
    final hasta = _leidasHasta;
    return fecha != null && hasta != null && !fecha.isAfter(hasta);
  }

  /// ¿El usuario la limpió de su bandeja?
  bool estaOculta(String id, Map<String, dynamic> data) {
    final fecha = _fechaDe(data['created_at'] ?? data['enviado_en']);
    final hasta = _limpiadasHasta;
    return fecha != null && hasta != null && !fecha.isAfter(hasta);
  }

  Future<void> marcarLeida(String id) async {
    if (_leidas.contains(id)) return;
    final previas = Set<String>.from(_leidas);
    _leidas.add(id);
    notifyListeners();
    try {
      await _ref().update({
        'notificaciones_leidas': FieldValue.arrayUnion([id]),
      });
    } catch (e) {
      _leidas = previas;
      notifyListeners();
      rethrow;
    }
  }

  /// Marca como leídas todas las notificaciones visibles del usuario.
  ///
  /// Con la fecha de corte no hacen falta los IDs; solo se conservan los de
  /// documentos sin fecha, que no se pueden comparar con el corte.
  Future<void> marcarTodas(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final ahora = Timestamp.now();
    final sinFecha = <String>{
      for (final d in docs)
        if (_fechaDe(d.data()['created_at'] ?? d.data()['enviado_en']) == null)
          d.id,
    };
    final previas = Set<String>.from(_leidas);
    final previoHasta = _leidasHasta;
    _leidas = sinFecha;
    _leidasHasta = ahora.toDate();
    notifyListeners();
    try {
      await _ref().update({
        'notificaciones_leidas': sinFecha.toList(),
        'notificaciones_leidas_hasta': ahora,
      });
    } catch (e) {
      _leidas = previas;
      _leidasHasta = previoHasta;
      notifyListeners();
      rethrow;
    }
  }

  /// Oculta para este usuario todo lo anterior a este momento, sin borrar
  /// documentos que otros usuarios también reciben.
  Future<void> limpiar() async {
    final ahora = Timestamp.now();
    final previas = Set<String>.from(_leidas);
    final previoLeidas = _leidasHasta;
    final previoLimpiadas = _limpiadasHasta;
    _leidas = <String>{};
    _leidasHasta = ahora.toDate();
    _limpiadasHasta = ahora.toDate();
    notifyListeners();
    try {
      await _ref().update({
        'notificaciones_leidas': <String>[],
        'notificaciones_leidas_hasta': ahora,
        'notificaciones_limpiadas_hasta': ahora,
      });
    } catch (e) {
      _leidas = previas;
      _leidasHasta = previoLeidas;
      _limpiadasHasta = previoLimpiadas;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reiniciar() async {
    await _sub?.cancel();
    _sub = null;
    _usuarioDocId = null;
    _leidas = <String>{};
    _leidasHasta = null;
    _limpiadasHasta = null;
    notifyListeners();
  }

  DocumentReference<Map<String, dynamic>> _ref() {
    final docId = _usuarioDocId;
    if (docId == null || docId.isEmpty) {
      throw StateError('No hay un usuario cargado para guardar la lectura');
    }
    return FirebaseFirestore.instance.collection('usuarios').doc(docId);
  }

  static DateTime? _fechaDe(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;
    if (valor is String) return DateTime.tryParse(valor)?.toLocal();
    return null;
  }
}
