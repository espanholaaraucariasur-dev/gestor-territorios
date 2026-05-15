import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TerritoriosTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const TerritoriosTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<TerritoriosTab> createState() => _TerritoriosTabState();
}

class _TerritoriosTabState extends State<TerritoriosTab> {
  Future<void> _abrirTerritorio(String terId, String terNombre,
      {bool readOnly = false}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(terNombre,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1B5E20))),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close, size: 28),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(thickness: 2),
                    // readOnly = Admin Territorios: puede enviar, bloquear, programar
                    // !readOnly = Admin: puede crear tarjetas, editar, eliminar
                    if (readOnly) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            // Verificar si hay tarjetas completadas en el territorio
                            final tarjetasSnap = await FirebaseFirestore.instance
                                .collection('territorios')
                                .doc(terId)
                                .collection('tarjetas')
                                .where('completada', isEqualTo: true)
                                .get();

                            if (tarjetasSnap.docs.isNotEmpty && mounted) {
                              final accion = await showDialog<String>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Row(children: [
                                    Icon(Icons.info_outline, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Tarjetas completadas'),
                                  ]),
                                  content: Text(
                                    'Este territorio tiene ${tarjetasSnap.docs.length} tarjeta(s) completada(s) este mes.\n\n¿Deseas reactivarlas y enviar el territorio completo?',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                                    OutlinedButton(
                                      onPressed: () => Navigator.pop(c, 'enviar_sin_reactivar'),
                                      child: const Text('Enviar sin reactivar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, 'reactivar_y_enviar'),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
                                      child: const Text('Reactivar y enviar'),
                                    ),
                                  ],
                                ),
                              );
                              if (accion == null) return;
                              if (accion == 'reactivar_y_enviar') {
                                final batch = FirebaseFirestore.instance.batch();
                                for (final t in tarjetasSnap.docs) {
                                  batch.update(t.reference, {
                                    'completada': false,
                                    'fecha_completada': null,
                                    'asignado_a': null,
                                    'publicador_email': null,
                                    'bloqueado': false,
                                  });
                                }
                                await batch.commit();
                              }
                            }
                            _mostrarDialogoEnviar(terId: terId, nombre: terNombre);
                          },
                          icon: const Icon(Icons.send, color: Colors.green),
                          label: const Text('Enviar territorio completo',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green,
                              side: const BorderSide(color: Colors.green),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!readOnly) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _mostrarDialogoCrearTarjeta(context, terId),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Crear Nueva Tarjeta',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final snap = await FirebaseFirestore.instance
                                .collection('territorios')
                                .doc(terId)
                                .collection('tarjetas')
                                .get();
                            final batch = FirebaseFirestore.instance.batch();
                            for (final t in snap.docs) {
                              final td = t.data() as Map<String, dynamic>;
                              final asignado = td['asignado_a']?.toString() ?? '';
                              final enviado = td['enviado_a']?.toString() ?? '';
                              if (asignado.isEmpty && enviado.isEmpty) {
                                batch.update(t.reference, {
                                  'bloqueado': false,
                                  'disponible_para_publicadores': true,
                                });
                              }
                            }
                            batch.update(
                              FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId),
                              {'disponible_para_publicadores': true},
                            );
                            await batch.commit();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔓 Tarjetas desbloqueadas'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.lock_open, size: 18),
                          label: const Text('Desbloquear todas las tarjetas'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text('Tarjetas en este Territorio:',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .doc(terId)
                            .collection('tarjetas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                                child: CircularProgressIndicator());
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                            return const Center(
                                child: Text('No hay tarjetas creadas aún.',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic)));
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              final tarjeta = snapshot.data!.docs[index];
                              final tarjetaId = tarjeta.id;
                              final tarjetaMap =
                                  tarjeta.data() as Map<String, dynamic>;
                              final tarjetaNombre =
                                  tarjetaMap['nombre'] as String? ??
                                      'Sin nombre';
                              final esPrioridad = tarjetaMap['prioridad_admin'] == true;
                              final mesPrioridad = tarjetaMap['mes_prioridad'] as String? ?? '';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: esPrioridad ? Colors.orange.shade50 : Colors.blue.shade50,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: esPrioridad
                                      ? const BorderSide(color: Colors.orange, width: 1.5)
                                      : BorderSide.none,
                                ),
                                child: ExpansionTile(
                                  leading: Icon(
                                    esPrioridad ? Icons.priority_high : Icons.folder,
                                    color: esPrioridad ? Colors.orange : Colors.blue,
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(tarjetaNombre,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      if (esPrioridad)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Pendiente $mesPrioridad',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('direcciones_globales')
                                        .where('tarjeta_id',
                                            isEqualTo: tarjetaId)
                                        .snapshots(),
                                    builder: (context, dirSnap) {
                                      final count =
                                          dirSnap.data?.docs.length ?? 0;
                                      final cantPrioridad = dirSnap.data?.docs
                                          .where((d) => (d.data() as Map<String,dynamic>)['prioridad_mes_anterior'] == true)
                                          .length ?? 0;
                                      final enviadoNombre = (tarjetaMap['enviado_nombre'] as String?)
                                          ?? (tarjetaMap['asignado_a'] as String?) ?? '';
                                      final enviadoEn = tarjetaMap['enviado_en'] as Timestamp?;
                                      String fechaHora = '';
                                      if (enviadoEn != null) {
                                        final dt = enviadoEn.toDate();
                                        fechaHora = ' · ${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                                      }
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Dir. vinculadas: $count'
                                              '${cantPrioridad > 0 ? " · $cantPrioridad sin predicar" : ""}'),
                                          if (esPrioridad && cantPrioridad > 0)
                                            Text(
                                              '⚠️ Enviar primero — $cantPrioridad dir. pendientes del mes anterior',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          if (enviadoNombre.isNotEmpty)
                                            Text(
                                              'Enviado a: $enviadoNombre$fechaHora',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (readOnly) ...[
                                        IconButton(
                                            icon: Icon(Icons.send,
                                                color: (tarjetaMap['completada'] as bool?) == true
                                                    ? Colors.orange
                                                    : Colors.blue,
                                                size: 20),
                                            onPressed: () async {
                                              final completada = (tarjetaMap['completada'] as bool?) == true;
                                              if (completada) {
                                                final accion = await showDialog<String>(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                    title: const Row(children: [
                                                      Icon(Icons.check_circle, color: Colors.green),
                                                      SizedBox(width: 8),
                                                      Text('Tarjeta completada'),
                                                    ]),
                                                    content: Text('La tarjeta "$tarjetaNombre" ya fue completada este mes.\n\n¿Deseas reactivarla y enviarla?'),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                                                      ElevatedButton(
                                                        onPressed: () => Navigator.pop(c, 'reactivar'),
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                                        child: const Text('Reactivar y enviar'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (accion != 'reactivar') return;
                                                await FirebaseFirestore.instance
                                                    .collection('territorios')
                                                    .doc(terId)
                                                    .collection('tarjetas')
                                                    .doc(tarjetaId)
                                                    .update({
                                                  'completada': false,
                                                  'fecha_completada': null,
                                                  'asignado_a': null,
                                                  'publicador_email': null,
                                                  'bloqueado': false,
                                                  'disponible_para_publicadores': true,
                                                });
                                              }
                                              _enviarTarjetaIndividual(context, terId, tarjetaId, tarjetaNombre);
                                            },
                                            tooltip: (tarjetaMap['completada'] as bool?) == true
                                                ? 'Tarjeta completada — toca para reactivar'
                                                : 'Enviar tarjeta'),
                                        IconButton(
                                            icon: Icon(
                                                tarjetaMap['bloqueado'] == true
                                                    ? Icons.lock
                                                    : Icons.lock_open,
                                                color:
                                                    tarjetaMap['bloqueado'] ==
                                                            true
                                                        ? Colors.grey
                                                        : Colors.green,
                                                size: 20),
                                            onPressed: () =>
                                                _toggleBloqueoTarjeta(
                                                    terId,
                                                    tarjetaId,
                                                    tarjetaMap['bloqueado'] ==
                                                        true),
                                            tooltip:
                                                tarjetaMap['bloqueado'] == true
                                                    ? 'Desbloquear tarjeta'
                                                    : 'Bloquear tarjeta'),
                                        IconButton(
                                            icon: const Icon(Icons.schedule,
                                                color: Colors.purple, size: 20),
                                            onPressed: () =>
                                                _programarEnvioTarjeta(
                                                    context,
                                                    terId,
                                                    tarjetaId,
                                                    tarjetaNombre),
                                            tooltip: 'Programar envío'),
                                      ],
                                      if (!readOnly) ...[
                                        IconButton(
                                            icon: const Icon(Icons.add_circle,
                                                color: Colors.green, size: 20),
                                            onPressed: () =>
                                                _agregarDireccionesATarjeta(
                                                    context,
                                                    terId,
                                                    tarjetaId,
                                                    tarjetaNombre),
                                            tooltip: 'Agregar dirección'),
                                        IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Colors.orange, size: 20),
                                            onPressed: () =>
                                                _editarNombreTarjeta(terId,
                                                    tarjetaId, tarjetaNombre),
                                            tooltip: 'Editar'),
                                        IconButton(
                                            icon: const Icon(
                                                Icons.delete_forever,
                                                color: Colors.redAccent,
                                                size: 20),
                                            onPressed: () async {
                                              final confirmar = await showDialog<
                                                      bool>(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                          title: const Text(
                                                              'Eliminar Tarjeta'),
                                                          content: Text(
                                                              '¿Eliminar "$tarjetaNombre"?'),
                                                          actions: [
                                                            TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                        c,
                                                                        false),
                                                                child: const Text(
                                                                    'Cancelar')),
                                                            TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                        c,
                                                                        true),
                                                                child: const Text(
                                                                    'Sí, Eliminar',
                                                                    style: TextStyle(
                                                                        color: Colors
                                                                            .red)))
                                                          ]));
                                              if (confirmar == true)
                                                await FirebaseFirestore.instance
                                                    .collection('territorios')
                                                    .doc(terId)
                                                    .collection('tarjetas')
                                                    .doc(tarjetaId)
                                                    .delete();
                                            },
                                            tooltip: 'Eliminar'),
                                      ],
                                    ],
                                  ),
                                  children: [
                                    FutureBuilder<QuerySnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaId)
                                          .get(),
                                      builder: (context, dirSnap) {
                                        if (!dirSnap.hasData)
                                          return const LinearProgressIndicator();
                                        final dirs = dirSnap.data!.docs;
                                        if (dirs.isEmpty)
                                          return const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Text(
                                                'Sin direcciones vinculadas',
                                                style: TextStyle(
                                                    color: Colors.grey)),
                                          );
                                        return Column(
                                          children: dirs.map((dir) {
                                            final d = dir.data()
                                                as Map<String, dynamic>;
                                            final calle =
                                                d['calle'] as String? ?? '';
                                            final complemento =
                                                d['complemento'] as String? ??
                                                    '';
                                            final estado =
                                                d['estado_predicacion']
                                                        as String? ??
                                                    'pendiente';
                                            return ListTile(
                                              dense: true,
                                              leading: const Icon(
                                                  Icons.location_on,
                                                  color: Colors.blue,
                                                  size: 18),
                                              title: Text(calle,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                              subtitle: complemento.isNotEmpty
                                                  ? Text(complemento,
                                                      style: const TextStyle(
                                                          fontSize: 11))
                                                  : null,
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: estado == 'completada'
                                                      ? Colors.green.shade100
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(estado,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: estado ==
                                                                'completada'
                                                            ? Colors
                                                                .green.shade800
                                                            : Colors.grey
                                                                .shade700)),
                                              ),
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
            );
          },
        );
      },
    );
  }

  Future<void> _liberarTodasLasTarjetasDelTerritorio(
      String territorioId) async {
    try {
      final tarjetasSnapshot = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final tarjetaDoc in tarjetasSnapshot.docs) {
        batch.update(tarjetaDoc.reference, {
          'disponible_para_publicadores': true,
          'bloqueado': false, // Start as unblocked when territory is opened
          'asignado_a': null,
          'asignado_en': null,
          'enviado_a': null,
          'enviado_nombre': null,
          'enviado_en': null,
          'estatus_envio': 'disponible',
        });
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('✅ Todas las tarjetas del territorio han sido liberadas'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al liberar tarjetas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
                  const Text('No hay conductores disponibles.',
                      style: TextStyle(color: Colors.grey))
                else ...[
                  const Text('Conductores disponibles:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...conductoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.drive_eta, color: Color(0xFF1B5E20)),
                      title: Text(data['nombre'] ?? 'Conductor'),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvio(
                            terId: terId,
                            tarjetaId: tarjetaId,
                            nombre: nombre,
                            destinatarioEmail: data['email'],
                            tipo: 'conductor');
                      },
                    );
                  }),
                ],
                const Divider(),
                const Text('Enviar a publicador:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                if (publicadoresSnap.docs.isEmpty)
                  const Text('No hay publicadores disponibles.',
                      style: TextStyle(color: Colors.grey))
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
                            tipo: 'publicador');
                      },
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'))
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
    required String tipo,
  }) async {
    try {
      final usuarioSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: destinatarioEmail)
          .get();
      final nombreDestinatario = usuarioSnap.docs.isNotEmpty
          ? (usuarioSnap.docs.first.data()['nombre'] ?? destinatarioEmail)
          : destinatarioEmail;
      // Obtener nombre del territorio
      String territoryNombre = nombre;
      try {
        final terDoc = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .get();
        territoryNombre = (terDoc.data()?['nombre'] as String?) ?? nombre;
      } catch (_) {}

      final payload = {
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'asignado_a': tipo == 'publicador' ? nombreDestinatario : null,
        'asignado_en': tipo == 'publicador' ? FieldValue.serverTimestamp() : null,
        'estatus_envio': 'enviado',
        'enviado_a': destinatarioEmail,
        'enviado_nombre': nombreDestinatario,
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
        'territorio_nombre': territoryNombre,
        'disponible_para_publicadores': tipo == 'publicador' ? true : null,
        'bloqueado': tipo == 'publicador' ? false : null,
        'prioridad_admin': false,   // ← limpiar al enviar
        'mes_prioridad': null,
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
              content: Text('"$nombre" enviado a $nombreDestinatario'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al enviar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _enviarTarjetaIndividual(BuildContext context, String terId,
      String tarjetaId, String tarjetaNombre) async {
    // Verificar si la tarjeta está completada
    final tarjetaDoc = await FirebaseFirestore.instance
        .collection('territorios')
        .doc(terId)
        .collection('tarjetas')
        .doc(tarjetaId)
        .get();
    final completada = (tarjetaDoc.data()?['completada'] as bool?) ?? false;

    if (completada) {
      if (!mounted) return;
      final accion = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Tarjeta completada'),
          ]),
          content: Text(
            'La tarjeta "$tarjetaNombre" ya fue completada este mes.\n\n¿Qué deseas hacer?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, 'reactivar'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
              child: const Text('Reactivar y enviar'),
            ),
          ],
        ),
      );
      if (accion != 'reactivar') return;

      // Reactivar primero
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'completada': false,
        'fecha_completada': null,
        'asignado_a': null,
        'publicador_email': null,
        'bloqueado': false,
        'disponible_para_publicadores': true,
      });
    }

    await _mostrarDialogoEnviar(
        terId: terId, tarjetaId: tarjetaId, nombre: tarjetaNombre);
  }

  Future<void> _toggleBloqueoTarjeta(
      String terId, String tarjetaId, bool bloqueadoActual) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({'bloqueado': !bloqueadoActual});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bloqueadoActual
                ? '✅ Tarjeta desbloqueada'
                : '🔒 Tarjeta bloqueada'),
            backgroundColor: bloqueadoActual ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _programarEnvioTarjeta(BuildContext context, String terId,
      String tarjetaId, String nombre) async {
    await _mostrarDialogoProgramarEnvio(terId,
        tarjetaId: tarjetaId, nombre: nombre, isTarjeta: true);
  }

  Future<void> _mostrarDialogoCrearTarjeta(
      BuildContext context, String terId) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nueva Tarjeta'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nombre de la tarjeta',
            hintText: 'Ej: A01-CENTRO',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              // Obtener nombre del territorio
              final terDoc = await FirebaseFirestore.instance
                  .collection('territorios')
                  .doc(terId)
                  .get();
              final terNombre = (terDoc.data()?['nombre'] as String?) ?? '';
              await FirebaseFirestore.instance
                  .collection('territorios')
                  .doc(terId)
                  .collection('tarjetas')
                  .doc(nombre) // ✅ ID = nombre de la tarjeta
                  .set({
                'nombre': nombre,
                'territorio_id': terId,
                'territorio_nombre': terNombre,
                'created_at': FieldValue.serverTimestamp(),
                'completada': false,
                'bloqueado': false,
                'disponible_para_publicadores': false,
                'estatus_envio': 'disponible',
                'cantidad_direcciones': 0,
              });
              if (context.mounted) Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _agregarDireccionesATarjeta(BuildContext context, String terId,
      String tarjetaId, String tarjetaNombre) async {
    final calleCtrl = TextEditingController();
    final complementoCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('Agregar dirección\n$tarjetaNombre',
              style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: calleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Calle / Dirección',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: complementoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Complemento (apto, casa, etc.)',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final calle = calleCtrl.text.trim();
                if (calle.isEmpty) return;
                final complemento = complementoCtrl.text.trim();

                // Obtener datos del territorio
                final terDoc = await FirebaseFirestore.instance
                    .collection('territorios')
                    .doc(terId)
                    .get();
                final terNombre = (terDoc.data()?['nombre'] as String?) ?? '';

                // ✅ Guardar en direcciones_globales con vínculo a tarjeta
                final calleNorm = calle.toLowerCase()
                    .replaceAll(RegExp(r'[áàâã]'), 'a')
                    .replaceAll(RegExp(r'[éèê]'), 'e')
                    .replaceAll(RegExp(r'[íìî]'), 'i')
                    .replaceAll(RegExp(r'[óòôõ]'), 'o')
                    .replaceAll(RegExp(r'[úùû]'), 'u')
                    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();

                // Generar palabras_clave para búsqueda
                final palabrasClave = calleNorm.split(' ')
                    .where((w) => w.length >= 2)
                    .toSet()
                    .toList();
                // Agregar complemento a las palabras clave
                if (complemento.isNotEmpty) {
                  final compNorm = complemento.toLowerCase()
                      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
                      .replaceAll(RegExp(r'\s+'), ' ')
                      .trim();
                  palabrasClave.addAll(compNorm.split(' ').where((w) => w.length >= 2));
                }

                await FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .add({
                  'calle': calle,
                  'calle_normalizada': calleNorm,
                  'palabras_clave': palabrasClave,
                  'complemento': complemento,
                  'tarjeta_id': tarjetaId,
                  'nombre_tarjeta': tarjetaId,
                  'territorio_id': terId,
                  'territorio_nombre': terNombre,
                  'barrio': terNombre,
                  'estado': 'asignada',
                  'estado_predicacion': 'pendiente',
                  'predicado': false,
                  'visitado': false,
                  'created_at': FieldValue.serverTimestamp(),
                });

                // Actualizar contador en la tarjeta
                final count = await FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .where('tarjeta_id', isEqualTo: tarjetaId)
                    .count()
                    .get();
                await FirebaseFirestore.instance
                    .collection('territorios')
                    .doc(terId)
                    .collection('tarjetas')
                    .doc(tarjetaId)
                    .update({'cantidad_direcciones': count.count ?? 0});

                calleCtrl.clear();
                complementoCtrl.clear();
                if (context.mounted) Navigator.pop(c);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20)),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarNombreTarjeta(
      String terId, String tarjetaId, String nombreActual) async {
    final ctrl = TextEditingController(text: nombreActual);
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar nombre'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nuevo = ctrl.text.trim();
              if (nuevo.isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('territorios')
                  .doc(terId)
                  .collection('tarjetas')
                  .doc(tarjetaId)
                  .update({'nombre': nuevo});
              if (context.mounted) Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoProgramarEnvio(String terId,
      {String? tarjetaId,
      required String nombre,
      required bool isTarjeta}) async {
    final conductoresSnapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .get();
    final conductores = conductoresSnapshot.docs
        .map((doc) => doc.data()['email'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (!mounted) return;
    String selectedConductor = conductores.isNotEmpty ? conductores.first : '';
    DateTime fechaSeleccionada = DateTime.now();
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isTarjeta
                  ? 'Programar envío de tarjeta'
                  : 'Programar envío de territorio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conductores.isEmpty)
                    const Text('No hay conductores registrados.')
                  else
                    DropdownButtonFormField<String>(
                      value: selectedConductor,
                      items: conductores
                          .map((email) => DropdownMenuItem(
                              value: email, child: Text(email)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setStateDialog(() => selectedConductor = value);
                      },
                      decoration: const InputDecoration(
                          labelText: 'Conductor', border: OutlineInputBorder()),
                    ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: fechaSeleccionada,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 1)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)));
                      if (picked != null)
                        setStateDialog(() => fechaSeleccionada = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Fecha de envío'),
                      child: Text(
                          '${fechaSeleccionada.day}/${fechaSeleccionada.month}/${fechaSeleccionada.year}'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: conductores.isEmpty
                      ? null
                      : () async {
                          try {
                            final data = {
                              'programado_para':
                                  Timestamp.fromDate(fechaSeleccionada),
                              'conductor_email': selectedConductor,
                              'estatus_envio': 'programado',
                              'programado_tipo':
                                  isTarjeta ? 'tarjeta' : 'territorio',
                              'programado_nombre': nombre,
                            };
                            if (isTarjeta) {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .collection('tarjetas')
                                  .doc(tarjetaId)
                                  .set(data, SetOptions(merge: true));
                            } else {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .set(data, SetOptions(merge: true));
                            }
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Programación guardada para $nombre'),
                                backgroundColor: Colors.green));
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error al programar: $e'),
                                backgroundColor: Colors.redAccent));
                          }
                        },
                  child: const Text('Programar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 0,
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('territorios')
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No hay territorios creados todavía.',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final territorio = snapshot.data!.docs[index];
              final data = territorio.data() as Map<String, dynamic>? ?? {};
              final nombre = data['nombre'] ?? 'Territorio';
              final descripcion = data['descripcion'] ?? '';
              final ubicado = data['ubicacion'] ?? '';

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _abrirTerritorio(
                    territorio.id,
                    nombre,
                    readOnly: true,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.map,
                                  color: Color(0xFF4A148C),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    if (data['enviado_a'] != null) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Enviado a: ${data['enviado_nombre'] ?? data['enviado_a']}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange.shade900,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(territorio.id)
                                          .collection('tarjetas')
                                          .snapshots(),
                                      builder: (context, t) {
                                        final tarjetas = t.data?.docs ?? [];
                                        final numTarjetas = tarjetas.length;
                                        final tarjetaIds = tarjetas.map((d) => d.id).toList();
                                        final cantPrioridad = tarjetas.where((d) =>
                                            (d.data() as Map<String,dynamic>)['prioridad_admin'] == true).length;

                                        if (tarjetaIds.isEmpty) {
                                          return Text(
                                            '$numTarjetas tarjetas · 0 direcciones',
                                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                                          );
                                        }

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            FutureBuilder<QuerySnapshot>(
                                              future: FirebaseFirestore.instance
                                                  .collection('direcciones_globales')
                                                  .where('tarjeta_id', whereIn: tarjetaIds.take(10).toList())
                                                  .get(),
                                              builder: (context, dirSnap) {
                                                final numDirs = dirSnap.data?.docs.length ?? 0;
                                                return Text(
                                                  '$numTarjetas tarjetas · $numDirs direcciones',
                                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                                );
                                              },
                                            ),
                                            if (cantPrioridad > 0) ...[
                                              const SizedBox(height: 3),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade100,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.orange.shade300),
                                                ),
                                                child: Text(
                                                  '⚠️ $cantPrioridad tarjeta(s) pendiente(s)',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.orange.shade900,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  (data['disponible_para_publicadores'] ??
                                              false) ==
                                          true
                                      ? Icons.lock_open
                                      : Icons.lock,
                                  color:
                                      (data['disponible_para_publicadores'] ??
                                                  false) ==
                                              true
                                          ? Colors.green
                                          : Colors.grey,
                                ),
                                onPressed: () async {
                                  final estaAbierto =
                                      (data['disponible_para_publicadores'] ??
                                              false) ==
                                          true;

                                  if (estaAbierto) {
                                    // CERRAR — bloquear todas las tarjetas del territorio
                                    final tarjetasSnap = await FirebaseFirestore
                                        .instance
                                        .collection('territorios')
                                        .doc(territorio.id)
                                        .collection('tarjetas')
                                        .get();
                                    final batch =
                                        FirebaseFirestore.instance.batch();
                                    for (final t in tarjetasSnap.docs) {
                                      batch.update(t.reference, {
                                        'bloqueado': true,
                                        'disponible_para_publicadores': false,
                                      });
                                    }
                                    batch.update(
                                      FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(territorio.id),
                                      {'disponible_para_publicadores': false},
                                    );
                                    await batch.commit();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              '🔒 Territorio cerrado — tarjetas bloqueadas'),
                                          backgroundColor: Colors.orange),
                                    );
                                  } else {
                                    // ABRIR — preguntar para quién liberar
                                    if (!mounted) return;
                                    final opcion = await showDialog<String>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        title: const Row(children: [
                                          Icon(Icons.lock_open, color: Color(0xFF1B5E20)),
                                          SizedBox(width: 8),
                                          Text('¿Para quién liberar?'),
                                        ]),
                                        content: const Text('Selecciona quién puede ver y tomar las tarjetas de este territorio.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                                          OutlinedButton.icon(
                                            onPressed: () => Navigator.pop(c, 'conductores'),
                                            icon: const Icon(Icons.directions_car, size: 16),
                                            label: const Text('Solo conductores'),
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.purple),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => Navigator.pop(c, 'todos'),
                                            icon: const Icon(Icons.people, size: 16),
                                            label: const Text('Todos'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF1B5E20),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (opcion == null) return;

                                    final soloConductores = opcion == 'conductores';
                                    final tarjetasSnap = await FirebaseFirestore
                                        .instance
                                        .collection('territorios')
                                        .doc(territorio.id)
                                        .collection('tarjetas')
                                        .get();
                                    final batch = FirebaseFirestore.instance.batch();
                                    for (final t in tarjetasSnap.docs) {
                                      final td = t.data() as Map<String, dynamic>;
                                      final asignado = td['asignado_a']?.toString() ?? '';
                                      final enviado = td['enviado_a']?.toString() ?? '';
                                      if (asignado.isEmpty && enviado.isEmpty) {
                                        batch.update(t.reference, {
                                          'bloqueado': false,
                                          'disponible_para_publicadores': !soloConductores,
                                          'solo_conductores': soloConductores,
                                        });
                                      }
                                    }
                                    batch.update(
                                      FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(territorio.id),
                                      {
                                        'disponible_para_publicadores': !soloConductores,
                                        'solo_conductores': soloConductores,
                                      },
                                    );
                                    await batch.commit();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(soloConductores
                                            ? '🔓 Territorio liberado solo para conductores'
                                            : '🔓 Territorio liberado para todos'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                tooltip: (data['disponible_para_publicadores'] ??
                                            false) ==
                                        true
                                    ? 'Cerrar territorio (bloquear tarjetas)'
                                    : 'Abrir territorio (liberar tarjetas)',
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.schedule,
                                  color: Color(0xFF4A148C),
                                ),
                                onPressed: () => _mostrarDialogoProgramarEnvio(
                                  territorio.id,
                                  nombre: nombre,
                                  isTarjeta: false,
                                ),
                                tooltip: 'Programar envío de territorio',
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 18,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                          if (descripcion.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                              ),
                              child: Text(
                                descripcion,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          if (ubicado.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      ubicado,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
