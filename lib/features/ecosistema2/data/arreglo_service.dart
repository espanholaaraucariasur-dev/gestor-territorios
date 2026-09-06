import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/arreglo_model.dart';

class ArregloService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'eco2_arreglos';

  static Stream<List<Arreglo>> obtenerPorFuncion(String funcionId) {
    return _db
        .collection(_col)
        .where('funcion_id', isEqualTo: funcionId)
        .where('activo', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Arreglo.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => b.fechaInicio.compareTo(a.fechaInicio));
      return lista;
    });
  }

  static Stream<List<Arreglo>> obtenerPublicados() {
    return _db
        .collection(_col)
        .where('publicado', isEqualTo: true)
        .where('activo', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Arreglo.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      return lista;
    });
  }

  static Stream<List<Arreglo>> obtenerPublicadosPorFecha(
      DateTime inicio, DateTime fin) {
    return _db
        .collection(_col)
        .where('publicado', isEqualTo: true)
        .where('activo', isEqualTo: true)
        .where('fecha_inicio', isGreaterThanOrEqualTo: inicio)
        .where('fecha_inicio', isLessThanOrEqualTo: fin)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Arreglo.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      return lista;
    });
  }

  static Future<Arreglo?> obtenerPorId(String id) async {
    final doc = await _db.collection(_col).doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Arreglo.fromMap(doc.id, doc.data()!);
  }

  static Stream<Arreglo?> obtenerPorIdStream(String id) {
    return _db.collection(_col).doc(id).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Arreglo.fromMap(doc.id, doc.data()!);
    });
  }

  static Future<String> crear(Arreglo arreglo) async {
    final doc = await _db.collection(_col).add(arreglo.toMap());
    return doc.id;
  }

  static Future<void> actualizar(String id, Map<String, dynamic> datos) async {
    await _db.collection(_col).doc(id).update({
      ...datos,
      'updated_at': DateTime.now(),
    });
  }

  static Future<void> eliminar(String id) async {
    await _db.collection(_col).doc(id).update({'activo': false});
  }

  static Future<void> publicar(String id) async {
    await _db.collection(_col).doc(id).update({
      'publicado': true,
      'updated_at': DateTime.now(),
    });
  }

  static Future<void> actualizarSlot(
      String arregloId, String slotId, Map<String, dynamic> datosSlot) async {
    final docRef = _db.collection(_col).doc(arregloId);
    final doc = await docRef.get();
    if (!doc.exists || doc.data() == null) return;

    final slots = (doc.data()!['slots'] as List?)
            ?.map((s) => Map<String, dynamic>.from(s))
            .toList() ??
        [];

    final idx = slots.indexWhere((s) => s['slot_id'] == slotId);
    if (idx == -1) return;

    slots[idx] = {...slots[idx], ...datosSlot};

    await docRef.update({
      'slots': slots,
      'updated_at': DateTime.now(),
    });
  }

  static Future<void> agregarSlot(
      String arregloId, Map<String, dynamic> slot) async {
    await _db.collection(_col).doc(arregloId).update({
      'slots': FieldValue.arrayUnion([slot]),
      'updated_at': DateTime.now(),
    });
  }

  static Future<void> removerSlot(
      String arregloId, Map<String, dynamic> slot) async {
    await _db.collection(_col).doc(arregloId).update({
      'slots': FieldValue.arrayRemove([slot]),
      'updated_at': DateTime.now(),
    });
  }

  static Stream<List<Arreglo>> obtenerPorGestor(String gestorUid) {
    return _db
        .collection(_col)
        .where('gestionado_por', isEqualTo: gestorUid)
        .where('activo', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Arreglo.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => b.fechaInicio.compareTo(a.fechaInicio));
      return lista;
    });
  }

  static Stream<List<Arreglo>> obtenerConSlotParaUsuario(String usuarioUid) {
    return _db
        .collection(_col)
        .where('publicado', isEqualTo: true)
        .where('activo', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => Arreglo.fromMap(d.id, d.data()))
          .where((a) => a.slots.any((s) => s.usuarioUid == usuarioUid))
          .toList();
      lista.sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      return lista;
    });
  }

  static Future<List<Arreglo>> obtenerPorVencer(int diasLimite) async {
    final ahora = DateTime.now();
    final limite = ahora.add(Duration(days: diasLimite));
    final snap = await _db
        .collection(_col)
        .where('publicado', isEqualTo: true)
        .where('activo', isEqualTo: true)
        .where('fecha_fin', isGreaterThanOrEqualTo: ahora)
        .where('fecha_fin', isLessThanOrEqualTo: limite)
        .get();
    return snap.docs.map((d) => Arreglo.fromMap(d.id, d.data())).toList();
  }
}
