import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usuario_eco2_model.dart';

class UsuarioEco2Service {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'usuarios';

  static Future<UsuarioEco2?> obtenerPorUid(String uid) async {
    final doc = await _db.collection(_col).doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UsuarioEco2.fromMap(doc.id, doc.data()!);
  }

  static Future<void> actualizarRoles(String uid, List<String> roles) async {
    final rolesLimpios = roles.toSet().toList();
    if (!rolesLimpios.contains('publicador')) {
      rolesLimpios.add('publicador');
    }
    await _db.collection(_col).doc(uid).update({
      'roles': rolesLimpios,
      'rol_eco2': FieldValue.delete(),
    });
  }

  static Future<void> agregarRol(String uid, String rol) async {
    await _db.collection(_col).doc(uid).update({
      'roles': FieldValue.arrayUnion([rol]),
      'rol_eco2': FieldValue.delete(),
    });
  }

  static Future<void> removerRol(String uid, String rol) async {
    if (rol == 'publicador') return;
    await _db.collection(_col).doc(uid).update({
      'roles': FieldValue.arrayRemove([rol]),
    });
  }

  static Future<void> asignarFamilia(String uid, String familiaId) async {
    await _db.collection(_col).doc(uid).update({'familia_id': familiaId});
  }

  static Future<void> removerDeFamilia(String uid) async {
    await _db.collection(_col).doc(uid).update({
      'familia_id': FieldValue.delete(),
    });
  }

  static Future<void> asignarFuncion(String uid, String funcionId) async {
    await _db.collection(_col).doc(uid).update({
      'funciones_asignadas': FieldValue.arrayUnion([funcionId]),
    });
  }

  static Future<void> removerFuncion(String uid, String funcionId) async {
    await _db.collection(_col).doc(uid).update({
      'funciones_asignadas': FieldValue.arrayRemove([funcionId]),
    });
  }

  static Stream<List<UsuarioEco2>> obtenerAprobados() {
    return _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => UsuarioEco2.fromMap(d.id, d.data()))
          .toList();
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      return lista;
    });
  }

  static Future<List<UsuarioEco2>> obtenerAprobadosUnaVez() async {
    final snap = await _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    final lista = snap.docs
        .map((d) => UsuarioEco2.fromMap(d.id, d.data()))
        .toList();
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  static Stream<List<UsuarioEco2>> obtenerPorRol(String rol) {
    return _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .where('roles', arrayContains: rol)
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => UsuarioEco2.fromMap(d.id, d.data()))
          .toList();
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      return lista;
    });
  }

  static Stream<List<UsuarioEco2>> obtenerSinFamilia() {
    return _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .where('familia_id', isNull: true)
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => UsuarioEco2.fromMap(d.id, d.data()))
          .toList();
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      return lista;
    });
  }

  static Future<List<UsuarioEco2>> obtenerPorFamilia(String familiaId) async {
    final snap = await _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .where('familia_id', isEqualTo: familiaId)
        .get();
    final lista = snap.docs
        .map((d) => UsuarioEco2.fromMap(d.id, d.data()))
        .toList();
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  static Future<int> contarPorRol(String rol) async {
    final snap = await _db
        .collection(_col)
        .where('estado', isEqualTo: 'aprobado')
        .where('roles', arrayContains: rol)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
