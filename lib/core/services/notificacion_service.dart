import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Servicio centralizado de notificaciones.
/// Toda notificación DEBE pasar por aquí para garantizar
/// que llegue a la persona correcta.
class NotificacionService {
  static final _db = FirebaseFirestore.instance;

  // ── Enviar a un destinatario específico ──────────────────
  static Future<void> enviarA({
    required String destinatarioEmail,
    required String titulo,
    required String cuerpo,
    required String tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    if (destinatarioEmail.isEmpty) return;
    try {
      await _db.collection('notificaciones').add({
        'titulo': titulo,
        'cuerpo': cuerpo,
        'tipo': tipo,
        'destinatario': destinatarioEmail,
        'leida': false,
        'created_at': FieldValue.serverTimestamp(),
        ...extra,
      });
    } catch (e) {
      debugPrint('Error enviando notificación: $e');
    }
  }

  // ── Enviar a todos los admins ────────────────────────────
  static Future<void> enviarAAdmins({
    required String titulo,
    required String cuerpo,
    required String tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final snap = await _db.collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .get();
      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['es_admin'] != true) continue;
        final email = u['email'] as String? ?? '';
        if (email.isEmpty) continue;
        await enviarA(
          destinatarioEmail: email,
          titulo: titulo,
          cuerpo: cuerpo,
          tipo: tipo,
          extra: extra,
        );
      }
    } catch (e) {
      debugPrint('Error enviando a admins: $e');
    }
  }

  // ── Enviar a todos los admin_territorios ─────────────────
  static Future<void> enviarAAdminTerritorios({
    required String titulo,
    required String cuerpo,
    required String tipo,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final snap = await _db.collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .get();
      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['es_admin'] != true && u['es_admin_territorios'] != true) continue;
        final email = u['email'] as String? ?? '';
        if (email.isEmpty) continue;
        await enviarA(
          destinatarioEmail: email,
          titulo: titulo,
          cuerpo: cuerpo,
          tipo: tipo,
          extra: extra,
        );
      }
    } catch (e) {
      debugPrint('Error enviando a admin_territorios: $e');
    }
  }
}
