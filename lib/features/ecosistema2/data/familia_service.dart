import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/familia_model.dart';

class FamiliaService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'eco2_familias';

  static Future<String> crear({
    required String nombre,
    required String creadoPor,
    List<String> miembros = const [],
  }) async {
    final doc = await _db.collection(_col).add({
      'nombre': nombre,
      'miembros': miembros,
      'creado_por': creadoPor,
      'activa': true,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> actualizar(String id, Map<String, dynamic> datos) async {
    await _db.collection(_col).doc(id).update(datos);
  }

  static Future<void> eliminar(String id) async {
    await _db.collection(_col).doc(id).delete();
  }

  static Future<Familia?> obtenerPorId(String id) async {
    final doc = await _db.collection(_col).doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Familia.fromMap(doc.id, doc.data()!);
  }

  static Stream<List<Familia>> obtenerTodas() {
    return _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final lista =
          snap.docs.map((d) => Familia.fromMap(d.id, d.data())).toList();
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      return lista;
    });
  }

  static Future<List<Familia>> obtenerTodasUnaVez() async {
    final snap = await _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .get();
    final lista =
        snap.docs.map((d) => Familia.fromMap(d.id, d.data())).toList();
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  static Future<void> agregarMiembro(String familiaId, String usuarioUid) async {
    await _db.collection(_col).doc(familiaId).update({
      'miembros': FieldValue.arrayUnion([usuarioUid]),
    });
  }

  static Future<void> removerMiembro(String familiaId, String usuarioUid) async {
    await _db.collection(_col).doc(familiaId).update({
      'miembros': FieldValue.arrayRemove([usuarioUid]),
    });
  }

  static Future<void> desactivar(String id) async {
    await _db.collection(_col).doc(id).update({'activa': false});
  }

  static Future<Familia?> obtenerFamiliaDeUsuario(String usuarioUid) async {
    final snap = await _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .where('miembros', arrayContains: usuarioUid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Familia.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  static Future<int> contarFamilias() async {
    final snap = await _db
        .collection(_col)
        .where('activa', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
