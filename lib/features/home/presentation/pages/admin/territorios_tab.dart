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
                          onPressed: () => _mostrarDialogoEnviar(
                              terId: terId, nombre: terNombre),
                          icon: const Icon(Icons.send, color: Colors.green),
                          label: const Text('Enviar territorio completo',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
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
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: Colors.blue.shade50,
                                elevation: 2,
                                child: ExpansionTile(
                                  leading: const Icon(Icons.folder,
                                      color: Colors.blue),
                                  title: Text(tarjetaNombre,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('direcciones_globales')
                                        .where('tarjeta_id',
                                            isEqualTo: tarjetaId)
                                        .snapshots(),
                                    builder: (context, dirSnap) {
                                      final count =
                                          dirSnap.data?.docs.length ?? 0;
                                      return Text('Dir. vinculadas: $count');
                                    },
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (readOnly) ...[
                                        IconButton(
                                            icon: const Icon(Icons.send,
                                                color: Colors.blue, size: 20),
                                            onPressed: () =>
                                                _enviarTarjetaIndividual(
                                                    context,
                                                    terId,
                                                    tarjetaId,
                                                    tarjetaNombre),
                                            tooltip: 'Enviar tarjeta'),
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
      final payload = {
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'estatus_envio': 'enviado',
        'enviado_a': destinatarioEmail,
        'enviado_nombre': nombreDestinatario,
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
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
      BuildContext context, String terId) async {}
  Future<void> _agregarDireccionesATarjeta(BuildContext context, String terId,
      String tarjetaId, String nombre) async {}
  Future<void> _editarNombreTarjeta(
      String terId, String tarjetaId, String nombre) async {}
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            nombre,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        if (data['enviado_a'] != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                8,
                                              ),
                                            ),
                                            child: Text(
                                              'Enviado a: ${data['enviado_a']}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FutureBuilder<int>(
                                      future: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('barrio', isEqualTo: nombre)
                                          .count()
                                          .get()
                                          .then((v) => v.count ?? 0),
                                      builder: (context, dirSnap) {
                                        return StreamBuilder<QuerySnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('territorios')
                                              .doc(territorio.id)
                                              .collection('tarjetas')
                                              .snapshots(),
                                          builder: (context, t) {
                                            final numTarjetas =
                                                (t.data?.docs.length ?? 0)
                                                    .toInt();
                                            final numDirs = dirSnap.data ?? 0;
                                            return Text(
                                              '$numTarjetas tarjetas · $numDirs direcciones',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 13,
                                              ),
                                            );
                                          },
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
                                    // ABRIR — liberar todas las tarjetas del territorio
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
                                        'bloqueado': false,
                                        'disponible_para_publicadores': true,
                                        'asignado_a': null,
                                        'asignado_en': null,
                                      });
                                    }
                                    batch.update(
                                      FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(territorio.id),
                                      {'disponible_para_publicadores': true},
                                    );
                                    await batch.commit();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              '✅ Territorio abierto — tarjetas liberadas'),
                                          backgroundColor: Colors.green),
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
