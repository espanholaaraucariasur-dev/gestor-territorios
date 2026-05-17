import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tipos de notificación
enum TipoNotificacion {
  solicitudAcceso,
  solicitudDireccion,
  devolucionTarjeta,
  devolucionAutomatica,
  alertaPredicacion,
  motivacional,
  avisoDevo,
  tarjetaTomada,
}

extension TipoNotificacionExt on TipoNotificacion {
  String get id {
    switch (this) {
      case TipoNotificacion.solicitudAcceso:      return 'solicitud_acceso';
      case TipoNotificacion.solicitudDireccion:   return 'solicitud_direccion';
      case TipoNotificacion.devolucionTarjeta:    return 'devolucion_tarjeta';
      case TipoNotificacion.devolucionAutomatica: return 'devolucion_automatica';
      case TipoNotificacion.alertaPredicacion:    return 'alerta_predicacion';
      case TipoNotificacion.motivacional:         return 'motivacional';
      case TipoNotificacion.avisoDevo:            return 'aviso_devolucion';
      case TipoNotificacion.tarjetaTomada:        return 'tarjeta_tomada';
    }
  }
}

class NotificacionService {
  static final _db = FirebaseFirestore.instance;

  // Enviar a un email específico
  static Future<void> enviar({
    required String destinatario,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    if (destinatario.trim().isEmpty) return;
    try {
      await _db.collection('notificaciones').add({
        'destinatario': destinatario.trim().toLowerCase(),
        'titulo': titulo,
        'cuerpo': cuerpo,
        'tipo': tipo.id,
        'leida': false,
        'created_at': FieldValue.serverTimestamp(),
        ...extra,
      });
    } catch (e) {
      debugPrint('❌ NotificacionService.enviar: $e');
    }
  }

  // Enviar a todos los admins
  static Future<void> enviarAAdmins({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final snap = await _db.collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .where('es_admin', isEqualTo: true)
          .get();
      for (final doc in snap.docs) {
        final email = (doc.data()['email'] as String? ?? '').trim().toLowerCase();
        if (email.isEmpty) continue;
        await enviar(destinatario: email, titulo: titulo, cuerpo: cuerpo, tipo: tipo, extra: extra);
      }
    } catch (e) {
      debugPrint('❌ NotificacionService.enviarAAdmins: $e');
    }
  }

  // Enviar a todos admin_territorios y admins
  static Future<void> enviarAAdminTerritorios({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final snap = await _db.collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .get();
      final Set<String> enviados = {};
      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['es_admin'] != true && u['es_admin_territorios'] != true) continue;
        final email = (u['email'] as String? ?? '').trim().toLowerCase();
        if (email.isEmpty || enviados.contains(email)) continue;
        enviados.add(email);
        await enviar(destinatario: email, titulo: titulo, cuerpo: cuerpo, tipo: tipo, extra: extra);
      }
    } catch (e) {
      debugPrint('❌ NotificacionService.enviarAAdminTerritorios: $e');
    }
  }

  // Stream de notificaciones del usuario (ordenado en memoria)
  static Stream<List<QueryDocumentSnapshot>> streamNotificaciones(String email) {
    return _db.collection('notificaciones')
        .where('destinatario', isEqualTo: email.trim().toLowerCase())
        .limit(50)
        .snapshots()
        .map((snap) {
          final docs = [...snap.docs];
          docs.sort((a, b) {
            final aT = (a.data() as Map)['created_at'] as Timestamp?;
            final bT = (b.data() as Map)['created_at'] as Timestamp?;
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });
          return docs;
        });
  }

  // Conteo de no leídas
  static Stream<int> streamConteo(String email) {
    return _db.collection('notificaciones')
        .where('destinatario', isEqualTo: email.trim().toLowerCase())
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => (d.data() as Map)['leida'] == false)
            .length);
  }

  // Marcar todas como leídas
  static Future<void> marcarLeidas(String email) async {
    try {
      final snap = await _db.collection('notificaciones')
          .where('destinatario', isEqualTo: email.trim().toLowerCase())
          .where('leida', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) batch.update(d.reference, {'leida': true});
      await batch.commit();
    } catch (e) {
      debugPrint('❌ NotificacionService.marcarLeidas: $e');
    }
  }

  // Eliminar todas las del usuario
  static Future<void> limpiar(String email) async {
    try {
      final snap = await _db.collection('notificaciones')
          .where('destinatario', isEqualTo: email.trim().toLowerCase())
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
    } catch (e) {
      debugPrint('❌ NotificacionService.limpiar: $e');
    }
  }

  // Limpieza automática: borrar más de N días
  static Future<void> limpiarAntiguos({int diasMax = 30}) async {
    try {
      final limite = Timestamp.fromDate(
          DateTime.now().subtract(Duration(days: diasMax)));
      final snap = await _db.collection('notificaciones')
          .where('created_at', isLessThan: limite)
          .limit(500).get();
      if (snap.docs.isEmpty) return;
      var batch = _db.batch();
      int n = 0;
      for (final d in snap.docs) {
        batch.delete(d.reference);
        if (++n % 400 == 0) { await batch.commit(); batch = _db.batch(); }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ NotificacionService.limpiarAntiguos: $e');
    }
  }
}
