import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/l10n/translation_service.dart';

/// Mixin para envío de tarjetas a conductores/publicadores
mixin EnviarTarjetaMixin<T extends StatefulWidget> on State<T> {
  String get usuarioEmail;
  Map<String, dynamic> get usuarioData;

  Future<void> _mostrarDialogoEnviar({
    required String terId,
    String? tarjetaId,
    required String nombre,
  }) async {
    final conductoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    final publicadoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_publicador', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enviar: $nombre'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (conductoresSnap.docs.isEmpty)
                  const Text(
                    'No hay conductores disponibles.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  const Text(
                    'Conductores disponibles:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...conductoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.drive_eta,
                        color: Color(0xFF1B5E20),
                      ),
                      title: Text(data['nombre'] ?? 'Conductor'),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvio(
                          terId: terId,
                          tarjetaId: tarjetaId,
                          nombre: nombre,
                          destinatarioEmail: data['email'],
                          tipo: 'conductor',
                        );
                      },
                    );
                  }),
                ],
                const Divider(),
                const Text(
                  'Enviar a publicador:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (publicadoresSnap.docs.isEmpty)
                  const Text(
                    'No hay publicadores disponibles.',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...publicadoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person, color: Colors.blue),
                      title: Text(data['nombre'] ?? 'Publicador'),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvio(
                          terId: terId,
                          tarjetaId: tarjetaId,
                          nombre: nombre,
                          destinatarioEmail: data['email'],
                          tipo: 'publicador',
                        );
                      },
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _ejecutarEnvio({
    required String terId,
    String? tarjetaId,
    required String nombre,
    required String destinatarioEmail,
    required String tipo, // 'conductor' o 'publicador'
  }) async {
    try {
      // Buscar ID del documento del destinatario
      final usuarioSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: destinatarioEmail)
          .get();
      final nombreDestinatario = usuarioSnap.docs.isNotEmpty
          ? (usuarioSnap.docs.first.data()['nombre'] ?? destinatarioEmail)
          : destinatarioEmail;
      final publicadorId = usuarioSnap.docs.isNotEmpty
          ? usuarioSnap.docs.first.id
          : destinatarioEmail;

      final mesActual = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      final payload = {
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'publicador_id': tipo == 'publicador' ? publicadorId : null,
        'asignado_a': tipo == 'publicador' ? nombreDestinatario : null,
        'mes_asignacion': tipo == 'publicador' ? mesActual : null,
        'estatus_envio': 'enviado',
        'enviado_a': destinatarioEmail,
        'enviado_nombre': nombreDestinatario,
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
        'nombre': nombre,
        'bloqueado': false,
        'completada': false,
        'disponible_para_publicadores': tipo == 'publicador' ? true : false,
      };

      if (tarjetaId != null) {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .collection('tarjetas')
            .doc(tarjetaId)
            .set(payload, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .set(payload, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "$nombre" enviado a $destinatarioEmail'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

}
