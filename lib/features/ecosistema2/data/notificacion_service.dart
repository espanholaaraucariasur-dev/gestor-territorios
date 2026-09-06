import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notificacion_model.dart';

class NotificacionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'eco2_notificaciones';

  static Stream<List<Notificacion>> obtenerPorUsuario(String uid) {
    return _db
        .collection(_col)
        .where('para_uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => Notificacion.fromMap(d.id, d.data()))
          .toList();
      lista.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return lista;
    });
  }

  static Stream<int> contarNoLeidas(String uid) {
    return _db
        .collection(_col)
        .where('para_uid', isEqualTo: uid)
        .where('leida', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  static Future<String> crear(Notificacion notificacion) async {
    final doc = await _db.collection(_col).add(notificacion.toMap());
    return doc.id;
  }

  static Future<void> marcarLeida(String id) async {
    await _db.collection(_col).doc(id).update({'leida': true});
  }

  static Future<void> marcarTodasLeidas(String uid) async {
    final snap = await _db
        .collection(_col)
        .where('para_uid', isEqualTo: uid)
        .where('leida', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'leida': true});
    }
    await batch.commit();
  }

  static Future<void> eliminar(String id) async {
    await _db.collection(_col).doc(id).delete();
  }

  static Future<void> crearAsignacion({
    required String paraUid,
    required String deUid,
    required String funcionId,
    required String arregloId,
    required String slotId,
    required String titulo,
    required String mensaje,
  }) async {
    await crear(Notificacion(
      id: '',
      tipo: 'asignacion',
      paraUid: paraUid,
      deUid: deUid,
      funcionId: funcionId,
      arregloId: arregloId,
      slotId: slotId,
      titulo: titulo,
      mensaje: mensaje,
    ));
  }

  static Future<void> crearRecusa({
    required String paraUid,
    required String deUid,
    required String funcionId,
    required String arregloId,
    required String slotId,
    required String titulo,
    required String mensaje,
  }) async {
    await crear(Notificacion(
      id: '',
      tipo: 'recusa',
      paraUid: paraUid,
      deUid: deUid,
      funcionId: funcionId,
      arregloId: arregloId,
      slotId: slotId,
      titulo: titulo,
      mensaje: mensaje,
    ));
  }

  static Future<void> crearRecordatorio({
    required String paraUid,
    required String funcionId,
    required String arregloId,
    required String titulo,
    required String mensaje,
  }) async {
    await crear(Notificacion(
      id: '',
      tipo: 'recordatorio',
      paraUid: paraUid,
      funcionId: funcionId,
      arregloId: arregloId,
      titulo: titulo,
      mensaje: mensaje,
    ));
  }
}
