import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/l10n/translation_service.dart';

/// Mixin para diálogos de solicitar/asignar/devolver tarjetas
mixin SolicitarTerritorioMixin<T extends StatefulWidget> on State<T> {
  String get usuarioEmail;
  Map<String, dynamic> get usuarioData;

  Future<void> _mostrarDialogoSolicitarTerritorioConductor() async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Solicitar tarjeta',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Text(
                'Selecciona un territorio para ver sus tarjetas disponibles',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('territorios')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No hay territorios.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, i) {
                        final terDoc = snapshot.data!.docs[i];
                        final terData = terDoc.data() as Map<String, dynamic>;
                        final terNombre = terData['nombre'] ?? terDoc.id;
                        if (terDoc.id == 'temporales' || terDoc.id == 'campanas') return const SizedBox.shrink();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                            title: Text(terNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('Toca para ver tarjetas'),
                            children: [
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('territorios')
                                    .doc(terDoc.id)
                                    .collection('tarjetas')
                                    .where('bloqueado', isEqualTo: false)
                                    .snapshots(),
                                builder: (context, tarjetasSnap) {
                                  if (tarjetasSnap.connectionState == ConnectionState.waiting) {
                                    return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                  }
                                  // Conductor ve TODAS — incluyendo solo_conductores
                                  final tarjetas = (tarjetasSnap.data?.docs ?? []).where((doc) {
                                    final d = doc.data() as Map<String, dynamic>;
                                    final asignado = d['asignado_a']?.toString() ?? '';
                                    return asignado.isEmpty;
                                  }).toList();
                                  if (tarjetas.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No hay tarjetas disponibles.', style: TextStyle(color: Colors.grey)),
                                    );
                                  }
                                  return Column(
                                    children: tarjetas.map((tarjetaDoc) {
                                      final data = tarjetaDoc.data() as Map<String, dynamic>;
                                      final tarjetaNombre = data['nombre'] ?? tarjetaDoc.id;
                                      final soloConductores = (data['solo_conductores'] as bool?) ?? false;
                                      return StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id', isEqualTo: tarjetaDoc.id)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          final cantDir = dirSnapshot.data?.docs.length ?? 0;
                                          return ListTile(
                                            leading: Icon(
                                              soloConductores ? Icons.lock : Icons.credit_card,
                                              color: data['completada'] == true ? Colors.grey : const Color(0xFF1B5E20),
                                            ),
                                            title: Text(tarjetaNombre,
                                                style: TextStyle(color: data['completada'] == true ? Colors.grey : Colors.black)),
                                            subtitle: Text(
                                              data['completada'] == true
                                                  ? '✅ Completada este mes'
                                                  : '$cantDir direcciones${soloConductores ? ' · Solo conductores' : ''}',
                                            ),
                                            trailing: data['completada'] == true
                                                ? null
                                                : ElevatedButton(
                                                    onPressed: cantDir > 0
                                                        ? () async {
                                                            Navigator.pop(context);
                                                            await _asignarTarjetaAConductor(
                                                              terDoc.id,
                                                              tarjetaDoc.id,
                                                              tarjetaNombre,
                                                            );
                                                          }
                                                        : null,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: cantDir > 0 ? const Color(0xFF1B5E20) : Colors.grey.shade400,
                                                      foregroundColor: Colors.white,
                                                    ),
                                                    child: const Text('Tomar'),
                                                  ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _asignarTarjetaAConductor(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      final ahora = DateTime.now();
      final nombre = usuarioData['nombre'] ?? '';
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        'asignado_a': nombre,
        'enviado_nombre': nombre,
        'enviado_tipo': 'conductor',
        'conductor_email': usuarioEmail,
        'enviado_a': usuarioEmail,
        'mes_asignacion': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': false,
        'bloqueado': false,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(),
        'prioridad_admin': false,
        'mes_prioridad': null,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Tarjeta "$tarjetaNombre" tomada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _mostrarDialogoSolicitarTerritorioPublicador() async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Solicitar tarjeta',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Text(
                'Selecciona un territorio para ver sus tarjetas disponibles',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                // ✅ Sin filtro en territorios — muestra TODOS
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('territorios')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay territorios.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, i) {
                        final terDoc = snapshot.data!.docs[i];
                        final terData = terDoc.data() as Map<String, dynamic>;
                        final terNombre = terData['nombre'] ?? terDoc.id;

                        // Ocultar territorios reservados solo para conductores
                        final soloConductores = (terData['solo_conductores'] as bool?) ?? false;
                        if (soloConductores) return const SizedBox.shrink();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: const Icon(
                              Icons.folder,
                              color: Color(0xFF1B5E20),
                            ),
                            title: Text(
                              terNombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text('Toca para ver tarjetas'),
                            children: [
                              StreamBuilder<QuerySnapshot>(
                                // ✅ Filtra SOLO por bloqueado == false en tarjetas
                                stream: FirebaseFirestore.instance
                                    .collection('territorios')
                                    .doc(terDoc.id)
                                    .collection('tarjetas')
                                    .where('bloqueado', isEqualTo: false)
                                    .snapshots(),
                                builder: (context, tarjetasSnap) {
                                  if (tarjetasSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  // Filtra en memoria las que no están asignadas
                                  // ni son solo para conductores
                                  final tarjetas =
                                      (tarjetasSnap.data?.docs ?? []).where((
                                    doc,
                                  ) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final asignado =
                                        d['asignado_a']?.toString() ?? '';
                                    // Excluir tarjetas reservadas solo para conductores
                                    final soloConductores = (d['solo_conductores'] as bool?) ?? false;
                                    return asignado.isEmpty && !soloConductores;
                                  }).toList();

                                  if (tarjetas.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'No hay tarjetas disponibles.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    );
                                  }

                                  return Column(
                                    children: tarjetas.map((tarjetaDoc) {
                                      final data = tarjetaDoc.data()
                                          as Map<String, dynamic>;
                                      final tarjetaData = data;
                                      final tarjetaNombre =
                                          data['nombre'] ?? tarjetaDoc.id;

                                      // ✅ NUEVO: StreamBuilder para contar direcciones reales en tiempo real
                                      return StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id',
                                                isEqualTo: tarjetaDoc.id)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          final cantDirReal =
                                              dirSnapshot.data?.docs.length ??
                                                  0;

                                          return ListTile(
                                            leading: Icon(
                                              Icons.credit_card,
                                              color: tarjetaData['completada'] == true
                                                  ? Colors.grey
                                                  : Colors.blue,
                                            ),
                                            title: Text(
                                              tarjetaNombre,
                                              style: TextStyle(
                                                color: tarjetaData['completada'] == true
                                                    ? Colors.grey
                                                    : Colors.black,
                                              ),
                                            ),
                                            subtitle: Text(
                                              tarjetaData['completada'] == true
                                                  ? '✅ Completada este mes'
                                                  : '$cantDirReal direcciones',
                                            ),
                                            trailing: tarjetaData['completada'] == true
                                                ? OutlinedButton(
                                                    onPressed: () async {
                                                      final confirmar = await showDialog<bool>(
                                                        context: context,
                                                        builder: (c) => AlertDialog(
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                          title: const Row(children: [
                                                            Icon(Icons.refresh, color: Color(0xFF1B5E20)),
                                                            SizedBox(width: 8),
                                                            Text('Reactivar tarjeta'),
                                                          ]),
                                                          content: Text('La tarjeta "$tarjetaNombre" ya fue completada este mes.\n\n¿Deseas reactivarla para que pueda ser tomada nuevamente?'),
                                                          actions: [
                                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                                            ElevatedButton(
                                                              onPressed: () => Navigator.pop(c, true),
                                                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
                                                              child: const Text('Reactivar'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirmar == true) {
                                                        await FirebaseFirestore.instance
                                                            .collection('territorios')
                                                            .doc(terDoc.id)
                                                            .collection('tarjetas')
                                                            .doc(tarjetaDoc.id)
                                                            .update({
                                                          'completada': false,
                                                          'fecha_completada': null,
                                                          'asignado_a': null,
                                                          'publicador_email': null,
                                                          'bloqueado': false,
                                                          'disponible_para_publicadores': true,
                                                        });
                                                        if (context.mounted) Navigator.pop(context);
                                                      }
                                                    },
                                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                                                    child: const Text('Reactivar', style: TextStyle(fontSize: 12)),
                                                  )
                                                : ElevatedButton(
                                              onPressed: cantDirReal > 0
                                                  ? () async {
                                                      Navigator.pop(context);
                                                      await _asignarTarjetaAPublicador(
                                                        terDoc.id,
                                                        tarjetaDoc.id,
                                                        tarjetaNombre,
                                                      );
                                                    }
                                                  : null,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: cantDirReal > 0
                                                    ? const Color(0xFF1B5E20)
                                                    : Colors.grey.shade400,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('Tomar'),
                                            ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _asignarTarjetaAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      final ahora = DateTime.now();
      final nombre = usuarioData['nombre'] ?? '';
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        'asignado_a': nombre,
        'publicador_email': usuarioEmail,
        'publicador_nombre': nombre,
        'enviado_nombre': nombre,
        'enviado_tipo': 'publicador',
        'enviado_a': usuarioEmail,
        'mes_asignacion': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': true,
        'bloqueado': false,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(),
        'prioridad_admin': false,
        'mes_prioridad': null,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Tarjeta "$tarjetaNombre" tomada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _devolverTarjeta(String territorioId, String tarjetaId) async {
    final nombre = usuarioData['nombre'] as String? ?? usuarioEmail;
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'publicador_email': null,
        'estatus_envio': 'disponible',
        'bloqueado': true,
        'disponible_para_publicadores': false,
        'devuelta_por': nombre,
        'devuelta_en': FieldValue.serverTimestamp(),
        'completada': false,
      });

      // Notificar a admins de territorios
      final adminsSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .get();
      for (final admin in adminsSnap.docs) {
        final u = admin.data() as Map<String, dynamic>;
        if (u['es_admin'] != true && u['es_admin_territorios'] != true) continue;
        final adminEmail = u['email'] as String? ?? '';
        if (adminEmail.isEmpty) continue;
        await FirebaseFirestore.instance.collection('notificaciones').add({
          'titulo': '↩️ Tarjeta devuelta',
          'cuerpo': '$nombre devolvió la tarjeta "$tarjetaId"',
          'tipo': 'devolucion_tarjeta',
          'destinatario': adminEmail,
          'territorio_id': territorioId,
          'tarjeta_id': tarjetaId,
          'devuelta_por': nombre,
          'leida': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tarjeta devuelta correctamente'),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }


}
