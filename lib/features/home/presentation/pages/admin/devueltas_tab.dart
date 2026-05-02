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
  // ─────────────────────────────────────────────────────────
  // RESTAURAR — vuelve a direcciones_globales con tarjeta origen
  // ─────────────────────────────────────────────────────────

  Future<void> _restaurarDireccion(DocumentSnapshot doc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restaurar dirección'),
        content: const Text(
          'Esta dirección volverá a direcciones globales con su tarjeta original.\n\n'
          '¿Confirmar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final docIdOriginal = (data['doc_id_original'] as String?) ?? doc.id;
      final tarjetaIdOrigen = (data['tarjeta_id_origen'] as String?) ?? '';
      final territorioId = (data['territorio_id'] as String?) ?? '';
      final territorioNombre = (data['territorio_nombre'] as String?) ?? '';

      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // 1. Recrear en direcciones_globales
      batch.set(
        db.collection('direcciones_globales').doc(docIdOriginal),
        {
          'calle': data['calle'] ?? '',
          'complemento': data['complemento'] ?? '',
          'direccion_normalizada': data['direccion_normalizada'] ?? '',
          'territorio_id': territorioId,
          'territorio_nombre': territorioNombre,
          'tarjeta_id': tarjetaIdOrigen,
          'estado': 'activa',
          'estado_predicacion': 'pendiente',
          'predicado': false,
          'visitado': false,
          'es_hispano': true,
          'asignado_a': null,
          'created_at': FieldValue.serverTimestamp(),
          'restaurada_en': FieldValue.serverTimestamp(),
          'restaurada_por': widget.usuarioData['nombre'] ?? '',
        },
      );

      // 2. Eliminar de direcciones_removidas
      batch.delete(doc.reference);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Dirección restaurada correctamente'),
              ],
            ),
            backgroundColor: Color(0xFF1B5E20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al restaurar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // ELIMINAR PERMANENTEMENTE
  // ─────────────────────────────────────────────────────────

  Future<void> _eliminarPermanente(DocumentSnapshot doc) async {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final calle = (data['calle'] as String?) ?? 'esta dirección';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar permanentemente'),
        content: Text(
          '¿Eliminar "$calle" para siempre?\n\n'
          '⚠️ Esta acción NO se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar para siempre'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('direcciones_removidas')
          .doc(doc.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección eliminada permanentemente'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('direcciones_removidas')
          .orderBy('removida_en', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay direcciones removidas',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                ),
                const SizedBox(height: 6),
                Text(
                  'Las direcciones marcadas como "no hispanohablante"\naparecerán aquí',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        // Agrupar por territorio
        final Map<String, List<DocumentSnapshot>> porTerritorio = {};
        for (final doc in docs) {
          final data = (doc.data() as Map<String, dynamic>?) ?? {};
          final terNombre =
              (data['territorio_nombre'] as String?) ?? 'Sin territorio';
          porTerritorio.putIfAbsent(terNombre, () => []).add(doc);
        }

        return Column(
          children: [
            // Header con contador
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_off, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${docs.length} direcci${docs.length == 1 ? 'ón removida' : 'ones removidas'} — no hispanohablantes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista agrupada por territorio
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: porTerritorio.length,
                itemBuilder: (context, index) {
                  final terNombre = porTerritorio.keys.elementAt(index);
                  final dirs = porTerritorio[terNombre]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header territorio
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              terNombre.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${dirs.length} dir.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),

                      // Direcciones del territorio
                      ...dirs.map((doc) {
                        final data =
                            (doc.data() as Map<String, dynamic>?) ?? {};
                        final calle = (data['calle'] as String?) ?? '';
                        final complemento =
                            (data['complemento'] as String?) ?? '';
                        final tarjetaOrigen =
                            (data['tarjeta_id_origen'] as String?) ?? '';
                        final removidaPor =
                            (data['removida_por'] as String?) ?? '';
                        final removidaEn = data['removida_en'] as Timestamp?;
                        String fechaRemovida = '';
                        if (removidaEn != null) {
                          final dt = removidaEn.toDate();
                          fechaRemovida = '${dt.day}/${dt.month}/${dt.year}';
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(
                                  color: Colors.red.shade300, width: 4),
                              top: BorderSide(
                                  color: Colors.red.shade100, width: 1),
                              right: BorderSide(
                                  color: Colors.red.shade100, width: 1),
                              bottom: BorderSide(
                                  color: Colors.red.shade100, width: 1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dirección
                                Row(
                                  children: [
                                    const Icon(Icons.location_off,
                                        color: Colors.red, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Color(0xFF263238),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Info
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if (tarjetaOrigen.isNotEmpty)
                                      _infoBadge(
                                        Icons.credit_card,
                                        'Tarjeta: $tarjetaOrigen',
                                        Colors.grey,
                                      ),
                                    if (removidaPor.isNotEmpty)
                                      _infoBadge(
                                        Icons.person,
                                        removidaPor,
                                        Colors.orange,
                                      ),
                                    if (fechaRemovida.isNotEmpty)
                                      _infoBadge(
                                        Icons.calendar_today,
                                        fechaRemovida,
                                        Colors.grey,
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Botones
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _restaurarDireccion(doc),
                                        icon:
                                            const Icon(Icons.restore, size: 15),
                                        label: const Text('Restaurar',
                                            style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF1B5E20),
                                          side: const BorderSide(
                                              color: Color(0xFF1B5E20)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () =>
                                            _eliminarPermanente(doc),
                                        icon: const Icon(Icons.delete_forever,
                                            size: 15),
                                        label: const Text('Eliminar',
                                            style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
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
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
