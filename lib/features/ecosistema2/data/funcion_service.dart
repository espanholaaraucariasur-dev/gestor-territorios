import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/funcion_model.dart';

class FuncionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'eco2_funciones';

  static Stream<List<Funcion>> obtenerTodas() {
    return _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Funcion.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      return lista;
    });
  }

  static Stream<Funcion?> obtenerPorId(String id) {
    return _db.collection(_col).doc(id).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Funcion.fromMap(doc.id, doc.data()!);
    });
  }

  static Future<Funcion?> obtenerPorIdUnaVez(String id) async {
    final doc = await _db.collection(_col).doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Funcion.fromMap(doc.id, doc.data()!);
  }

  static Future<String> crear(Funcion funcion) async {
    final doc = await _db.collection(_col).add(funcion.toMap());
    return doc.id;
  }

  static Future<void> actualizar(String id, Map<String, dynamic> datos) async {
    await _db.collection(_col).doc(id).update(datos);
  }

  static Future<void> eliminar(String id) async {
    await _db.collection(_col).doc(id).update({'activa': false});
  }

  static Future<void> asignarGestor(String funcionId, String gestorUid) async {
    await _db
        .collection(_col)
        .doc(funcionId)
        .update({'gestor_uid': gestorUid});
  }

  static Future<void> removerGestor(String funcionId) async {
    await _db.collection(_col).doc(funcionId).update({
      'gestor_uid': FieldValue.delete(),
    });
  }

  static Stream<List<Funcion>> obtenerPorGestor(String gestorUid) {
    return _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .where('gestor_uid', isEqualTo: gestorUid)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) => Funcion.fromMap(d.id, d.data())).toList();
    });
  }

  static Stream<List<Funcion>> obtenerDondeEsGestor(String uid) {
    return _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .where('gestor_uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) => Funcion.fromMap(d.id, d.data())).toList();
    });
  }

  static Stream<List<Funcion>> obtenerParaAdmin(List<String> adminUids) {
    if (adminUids.isEmpty) return const Stream.empty();
    return _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) => Funcion.fromMap(d.id, d.data())).toList();
    });
  }
}
