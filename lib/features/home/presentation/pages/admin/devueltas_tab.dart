import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DevueltasTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const DevueltasTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<DevueltasTab> createState() => _DevueltasTabState();
}

class _DevueltasTabState extends State<DevueltasTab> {
  Future<void> _mostrarDialogoRevision(
      List<DocumentSnapshot> direcciones) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Revisión de ${direcciones.length} direcciones en desarrollo'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _restaurarDireccion(String direccionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(direccionId)
          .update({
        'es_hispano': true,
        'removed_at': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dirección restaurada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al restaurar dirección: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _eliminarPermanentemente(String direccionId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Permanentemente'),
        content: const Text(
            '¿Está seguro de que desea eliminar esta dirección permanentemente? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(direccionId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dirección eliminada permanentemente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al eliminar dirección: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjeta de revisión (direcciones con más de 30 días)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('direcciones_globales')
                .where(
                  'removed_at',
                  isLessThan: DateTime.now().subtract(
                    const Duration(days: 30),
                  ),
                )
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox();
              }

              final direccionesRevision = snapshot.data!.docs;

              if (direccionesRevision.isEmpty) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sin revisiones pendientes',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const Text(
                              'No hay direcciones que necesiten revisión (más de 30 días)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${direccionesRevision.length} direcciones para revisión',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const Text(
                                'Direcciones removidas hace más de 30 días',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _mostrarDialogoRevision(
                        direccionesRevision,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Revisar Direcciones'),
                    ),
                  ],
                ),
              );
            },
          ),

          // Lista de direcciones removidas
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .where('es_hispano', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final direccionesRemovidas = snapshot.data!.docs;

                if (direccionesRemovidas.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.green,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay direcciones removidas',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Todas las direcciones son de hispanohablantes',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: direccionesRemovidas.length,
                  itemBuilder: (context, index) {
                    final doc = direccionesRemovidas[index];
                    final data =
                        doc.data() as Map<String, dynamic>;
                    final removedAt =
                        (data['removed_at'] as Timestamp?)
                            ?.toDate();
                    final diasDesdeRemocion = removedAt != null
                        ? DateTime.now()
                            .difference(removedAt)
                            .inDays
                        : 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.person_off,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['calle'] ??
                                            'Dirección sin nombre',
                                        style: const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(
                                            0xFF263238,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Removida hace $diasDesdeRemocion días',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              diasDesdeRemocion >
                                                      30
                                                  ? Colors.red
                                                  : Colors.grey,
                                          fontWeight:
                                              diasDesdeRemocion >
                                                      30
                                                  ? FontWeight
                                                      .bold
                                                  : FontWeight
                                                      .normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (diasDesdeRemocion > 30)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius:
                                          BorderRadius.circular(
                                        10,
                                      ),
                                    ),
                                    child: const Text(
                                      'Revisión',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (data['complemento'] != null &&
                                data['complemento']
                                    .toString()
                                    .isNotEmpty)
                              Text(
                                'Complemento: ${data['complemento']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            if (data['detalles'] != null &&
                                data['detalles']
                                    .toString()
                                    .isNotEmpty)
                              Text(
                                'Detalles: ${data['detalles']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _restaurarDireccion(
                                      doc.id,
                                    ),
                                    style:
                                        OutlinedButton.styleFrom(
                                      foregroundColor:
                                          Colors.green,
                                      side: const BorderSide(
                                        color: Colors.green,
                                      ),
                                    ),
                                    child: const Text(
                                      'Restaurar',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _eliminarPermanentemente(
                                      doc.id,
                                    ),
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor:
                                          Colors.white,
                                    ),
                                    child: const Text('Eliminar'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
