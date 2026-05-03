import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConductorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;

  const ConductorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
  });

  @override
  State<ConductorTab> createState() => _ConductorTabState();
}

class _ConductorTabState extends State<ConductorTab> {
  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF1B5E20)),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          Text(title, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _devolverTerritorio(String territorioId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .update({
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'estatus_envio': 'disponible',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Territorio devuelto correctamente'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver territorio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _enviarTarjetaConductorAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      // Query publicadores
      final publicadoresSnapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('es_publicador', isEqualTo: true)
          .where('estado', isEqualTo: 'aprobado')
          .get();

      if (publicadoresSnapshot.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay publicadores disponibles'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show selection dialog
      final selectedPublicador = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seleccionar Publicador'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: publicadoresSnapshot.docs.length,
              itemBuilder: (context, index) {
                final doc = publicadoresSnapshot.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final nombre = data['nombre'] ?? 'Sin nombre';
                final email = data['email'] ?? 'Sin email';

                return ListTile(
                  title: Text(nombre),
                  subtitle: Text(email),
                  onTap: () => Navigator.pop(context, data),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedPublicador == null) return;

      final nombreElegido = selectedPublicador['nombre'] ?? 'Publicador';

      // Show confirmation dialog
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Envío'),
          content: Text(
            '¿Enviar tarjeta "$tarjetaNombre" a $nombreElegido?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      if (confirmado != true) return;

      // Obtener nombre del territorio
      final terDoc = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .get();
      final territorioNombre =
          (terDoc.data()?['nombre'] as String?) ?? territorioId;

      // Update tarjeta document
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': nombreElegido,
        'enviado_nombre': nombreElegido,
        'enviado_en': FieldValue.serverTimestamp(),
        'disponible_para_publicadores': false,
        'territorio_nombre': territorioNombre,
      });

      // Contar direcciones reales
      final dirsCount = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .count()
          .get();

      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'cantidad_direcciones': dirsCount.count ?? 0,
      });

      // Update all direcciones_globales with tarjeta_id
      final direccionesSnapshot = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in direccionesSnapshot.docs) {
        batch.update(doc.reference, {'asignado_a': nombreElegido});
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tarjeta "$tarjetaNombre" enviada a $nombreElegido'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: CustomScrollView(
        slivers: [
          // Statistics Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .snapshots(),
                    builder: (context, snap) {
                      final todas = snap.data?.docs ?? [];

                      // Tarjetas enviadas directamente al conductor
                      final tarjetasDirectas = todas.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['conductor_email'] == widget.usuarioEmail ||
                            data['enviado_a'] == widget.usuarioEmail;
                      }).length;

                      // Tarjetas dentro de territorios recibidos por el conductor
                      // (se cuentan por separado via StreamBuilder de territorios)
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, terSnap) {
                          int tarjetasEnTerritorios = 0;
                          if (terSnap.hasData) {
                            for (final ter in terSnap.data!.docs) {
                              final td =
                                  (ter.data() as Map<String, dynamic>?) ?? {};
                              final esDelConductor = td['enviado_a'] ==
                                      widget.usuarioEmail ||
                                  td['conductor_email'] == widget.usuarioEmail;
                              if (!esDelConductor) continue;
                              // Contar tarjetas de este territorio desde collectionGroup
                              tarjetasEnTerritorios += todas
                                  .where((t) =>
                                      t.reference.parent.parent?.id == ter.id)
                                  .length;
                            }
                          }

                          final recibidas =
                              tarjetasDirectas + tarjetasEnTerritorios;
                          final enviadas = todas.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final esDelConductor =
                                data['conductor_email'] == widget.usuarioEmail ||
                                data['enviado_a'] == widget.usuarioEmail;
                            if (!esDelConductor) return false;
                            final enviadoNombre =
                                (data['enviado_nombre'] as String?) ?? '';
                            final asignadoA =
                                (data['asignado_a'] as String?) ?? '';
                            return enviadoNombre.isNotEmpty ||
                                asignadoA.isNotEmpty;
                          }).length;
                          final devueltas = todas.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            return data['devuelto_por'] ==
                                (widget.usuarioData['nombre'] ??
                                    widget.usuarioEmail);
                          }).length;

                          return Row(
                            children: [
                              Expanded(
                                  child: _statCard(
                                      'Recibidas', recibidas, Icons.download)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      'Enviadas', enviadas, Icons.upload)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      'Devueltas', devueltas, Icons.undo)),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Simple bar chart simulation
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Actividad Mensual',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(6, (index) {
                              final heights = [0.3, 0.7, 0.5, 0.9, 0.6, 0.8];
                              return Container(
                                width: 20,
                                height: 60 * heights[index],
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1B5E20,
                                  ).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Territories Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'TERRITORIOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('territorios')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text('Cargando...',
                        style: TextStyle(color: Colors.grey));
                  }
                  // Territorios donde el conductor recibió el envío
                  // Solo territorios que aún tienen tarjetas pendientes de enviar
                  final todosTerritorios = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return d['enviado_a'] == widget.usuarioEmail ||
                        d['conductor_email'] == widget.usuarioEmail;
                  }).toList();

// Usamos FutureBuilder por territorio para verificar tarjetas pendientes
// pero para mantener el stream reactivo, filtramos con un set local
                  final docs = todosTerritorios; // Se filtra visualmente abajo

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                            left: BorderSide(
                                color: const Color(0xFF1B5E20), width: 4)),
                      ),
                      child: const Center(
                        child: Text('No hay territorios recibidos',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre =
                          (data['nombre'] as String?) ?? 'Territorio';
                      final enviadoNombre =
                          (data['enviado_nombre'] as String?) ?? '';
                      final enviadoEn = data['enviado_en'] as Timestamp?;
                      String fechaHora = '';
                      if (enviadoEn != null) {
                        final dt = enviadoEn.toDate();
                        fechaHora =
                            '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border(
                              left: BorderSide(
                                  color: const Color(0xFF1B5E20), width: 4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ExpansionTile(
                          leading:
                              const Icon(Icons.map, color: Color(0xFF1B5E20)),
                          title: Text(nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: enviadoNombre.isNotEmpty
                              ? Text(
                                  'Enviado por: $enviadoNombre${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          children: [
                            // Lista de tarjetas del territorio
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(doc.id)
                                  .collection('tarjetas')
                                  .snapshots(),
                              builder: (context, tarjSnap) {
                                if (!tarjSnap.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final todasTarjetas = tarjSnap.data!.docs;
                                final pendientes = todasTarjetas.where((t) {
                                  final td =
                                      (t.data() as Map<String, dynamic>?) ?? {};
                                  // Tarjeta pendiente = no tiene asignado_a NI enviado_nombre
                                  final asignadoA =
                                      (td['asignado_a'] as String?) ?? '';
                                  final enviadoNombre =
                                      (td['enviado_nombre'] as String?) ?? '';
                                  return asignadoA.isEmpty &&
                                      enviadoNombre.isEmpty;
                                }).toList();

                                // Si todas las tarjetas están enviadas, ocultar el territorio
                                if (todasTarjetas.isNotEmpty &&
                                    pendientes.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                if (todasTarjetas.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('Sin tarjetas',
                                        style: TextStyle(color: Colors.grey)),
                                  );
                                }

                                return Column(
                                  children: pendientes.map((tarjDoc) {
                                    final td =
                                        tarjDoc.data() as Map<String, dynamic>;
                                    final tarjNombre =
                                        (td['nombre'] as String?) ?? tarjDoc.id;
                                    final yaEnviada =
                                        (td['asignado_a'] as String?)
                                                ?.isNotEmpty ==
                                            true;
                                    final asignadoA =
                                        (td['asignado_a'] as String?) ?? '';

                                    return Container(
                                      margin: const EdgeInsets.fromLTRB(
                                          12, 4, 12, 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: yaEnviada
                                            ? Colors.green.shade50
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: yaEnviada
                                              ? Colors.green.shade200
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.credit_card,
                                              color: yaEnviada
                                                  ? Colors.green
                                                  : Colors.blue,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(tarjNombre,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13)),
                                                StreamBuilder<QuerySnapshot>(
                                                  stream: FirebaseFirestore
                                                      .instance
                                                      .collection(
                                                          'direcciones_globales')
                                                      .where('tarjeta_id',
                                                          isEqualTo: tarjDoc.id)
                                                      .where('estado',
                                                          isNotEqualTo:
                                                              'removida')
                                                      .snapshots(),
                                                  builder: (context, dirSnap) {
                                                    final count = dirSnap.data
                                                            ?.docs.length ??
                                                        0;
                                                    return Text(
                                                      '$count direcciones',
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey),
                                                    );
                                                  },
                                                ),
                                                if (yaEnviada)
                                                  Text(
                                                    'Enviada a: $asignadoA',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .green.shade700),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          // Botón enviar tarjeta individual
                                          ElevatedButton(
                                            onPressed: () =>
                                                _enviarTarjetaConductorAPublicador(
                                              doc.id,
                                              tarjDoc.id,
                                              tarjNombre,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: yaEnviada
                                                  ? Colors.orange
                                                  : const Color(0xFF1B5E20),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                              yaEnviada ? 'Reenviar' : 'Enviar',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          // Cards Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'TARJETAS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

          // Cards Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final esParaEste = d['enviado_a'] == widget.usuarioEmail ||
                        d['enviado_a'] == (widget.usuarioData['nombre'] ?? '');
                    if (!esParaEste) return false;
                    // Excluir tarjetas que vienen dentro de un territorio
                    // (esas se ven en la sección TERRITORIOS)
                    final terId = doc.reference.parent.parent?.id ?? '';
                    // Si el territorio también fue enviado a este conductor, no mostrar aquí
                    final territorioEnviado = snapshot.data!.docs.any((t) =>
                        t.id == terId &&
                        ((t.data() as Map<String, dynamic>)['enviado_a'] ==
                                widget.usuarioEmail ||
                            (t.data() as Map<String, dynamic>)[
                                    'conductor_email'] ==
                                widget.usuarioEmail));
                    return !territorioEnviado;
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(color: Colors.blue, width: 4),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay tarjetas recibidas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Tarjeta';
                      final enviadoA = data['enviado_a'] ?? '';
                      final terId = doc.reference.parent.parent?.id ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(color: Colors.blue, width: 4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabecera
                              Row(
                                children: [
                                  const Icon(Icons.credit_card,
                                      color: Colors.blue),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        Text(
                                          'Territorio: ${(data['territorio_nombre'] as String?)?.isNotEmpty == true ? data['territorio_nombre'] : terId}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                        StreamBuilder<QuerySnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection(
                                                  'direcciones_globales')
                                              .where('tarjeta_id',
                                                  isEqualTo: doc.id)
                                              .where('estado',
                                                  isNotEqualTo: 'removida')
                                              .snapshots(),
                                          builder: (context, dirSnap) {
                                            final count =
                                                dirSnap.data?.docs.length ?? 0;
                                            return Text(
                                              '$count direcciones',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Badge enviado por
                              if (enviadoA.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Builder(builder: (context) {
                                  final enviadoEn = data['enviado_en'];
                                  String fechaHora = '';
                                  if (enviadoEn != null) {
                                    final dt =
                                        (enviadoEn as Timestamp).toDate();
                                    fechaHora =
                                        ' · ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  }
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Enviado por: ${data['enviado_nombre'] ?? enviadoA}$fechaHora',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900),
                                    ),
                                  );
                                }),
                              ],
                              const SizedBox(height: 12),
                              // Botones en fila
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.send, size: 14),
                                      label: Text(
                                        (data['enviado_nombre'] ?? '')
                                                .toString()
                                                .isEmpty
                                            ? 'Enviar'
                                            : 'Reenviar',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onPressed: () =>
                                          _enviarTarjetaConductorAPublicador(
                                              terId, doc.id, nombre),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            (data['enviado_nombre'] ?? '')
                                                    .toString()
                                                    .isEmpty
                                                ? const Color(0xFF1B5E20)
                                                : Colors.orange,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.undo, size: 14),
                                      label: const Text('Devolver',
                                          style: TextStyle(fontSize: 12)),
                                      onPressed: () async {
                                        final confirmar =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text(
                                                'Confirmar devolución'),
                                            content: Text(
                                                '¿Devolver la tarjeta "$nombre"? Volverá a estar disponible.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange),
                                                child: const Text('Devolver'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmar == true) {
                                          await FirebaseFirestore.instance
                                              .collection('territorios')
                                              .doc(terId)
                                              .collection('tarjetas')
                                              .doc(doc.id)
                                              .update({
                                            'enviado_a': null,
                                            'enviado_nombre': null,
                                            'enviado_en': null,
                                            'estatus_envio': 'devuelto',
                                            'devuelto_en':
                                                FieldValue.serverTimestamp(),
                                            'devuelto_por':
                                                widget.usuarioData['nombre'] ??
                                                    widget.usuarioEmail,
                                          });
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange,
                                        side: const BorderSide(
                                            color: Colors.orange),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
