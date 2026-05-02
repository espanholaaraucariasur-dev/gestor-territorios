import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MantenimientoTab extends StatefulWidget {
  const MantenimientoTab({super.key});

  @override
  State<MantenimientoTab> createState() => _MantenimientoTabState();
}

class _MantenimientoTabState extends State<MantenimientoTab> {
//borrra datos globales
  Future<void> _borrarTodasDirecciones() async {
    final confirmar1 = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('⚠️ Borrar TODAS las direcciones'),
        content: const Text(
          'Esto eliminará PERMANENTEMENTE todas las direcciones del directorio global.\n\n'
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
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmar1 != true) return;

    final TextEditingController ctrl = TextEditingController();
    final confirmar2 = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmación final'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Escribe CONFIRMAR para continuar:'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'CONFIRMAR',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim() == 'CONFIRMAR'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ELIMINAR TODO'),
          ),
        ],
      ),
    );
    if (confirmar2 != true) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancelado — texto incorrecto'),
            backgroundColor: Colors.orange,
          ),
        );
      return;
    }

    try {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Eliminando direcciones...'),
            duration: Duration(seconds: 10),
          ),
        );

      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      int total = 0;
      final docs = snap.docs;
      for (int i = 0; i < docs.length; i += 100) {
        final chunk = docs.skip(i).take(100).toList();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
          total++;
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $total direcciones eliminadas'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }
// termina aqui borra datos globales

  Future<void> _restaurarTarjetaIds() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔧 Restaurar tarjeta_id'),
        content: const Text(
          'Esto restaurará el campo tarjeta_id en todas las direcciones '
          'basándose en el ID del documento.\n\n'
          'Ejemplo: "Costeira_D02_Rua_..." → tarjeta_id = "D02"\n\n'
          '¿Continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      // Get all territorios and their tarjetas to build a lookup map
      // Map: tarjetaNombre -> tarjetaId (Firestore doc id)
      final territoriosSnap =
          await FirebaseFirestore.instance.collection('territorios').get();

      // Build map of tarjetaNombre -> tarjetaDocId
      // e.g. {'D02': 'abc123firebaseid', 'D03': 'def456...'}
      final Map<String, String> nombreToId = {};
      for (final territorio in territoriosSnap.docs) {
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();
        for (final tarjeta in tarjetasSnap.docs) {
          final nombre = (tarjeta.data()['nombre'] as String? ?? '').trim();
          if (nombre.isNotEmpty) {
            nombreToId[nombre] = tarjeta.id;
          }
        }
      }

      debugPrint('Mapa de tarjetas: $nombreToId');

      // Update all direcciones with proper tarjeta_id based on document ID
      final direccionesSnap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      int batchCount = 0;
      WriteBatch currentBatch = FirebaseFirestore.instance.batch();
      int actualizadas = 0;
      int noEncontradas = 0;

      for (final doc in direccionesSnap.docs) {
        final data = doc.data();
        final territorioId = data['territorio_id'] as String?;
        if (territorioId == null) continue;

        // Extract tarjeta name from doc ID - second segment
        final docId = doc.id;
        final parts = docId.split('_');
        if (parts.length < 2) continue;

        // Try parts[1] first (e.g. "D02"), then parts[1]+parts[2] for compound names (e.g. "F01-São")
        String? tarjetaId;
        for (final entry in nombreToId.entries) {
          if ((doc.data() as Map<String, dynamic>)['calle']
              .toString()
              .toLowerCase()
              .contains(entry.key.toLowerCase())) {
            tarjetaId = entry.value;
            break;
          }
        }

        debugPrint(
            'DocId: ${doc.id}, parts: $parts, tarjetaNombre: ${parts.length >= 2 ? parts[1] : "N/A"}');

        if (tarjetaId != null) {
          currentBatch.update(doc.reference, {
            'tarjeta_id': tarjetaId,
            'estado': 'asignada',
          });
          actualizadas++;
          batchCount++;

          // Commit every 400 operations for performance
          if (batchCount >= 400) {
            await currentBatch.commit();
            currentBatch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
        } else {
          // Mark as orphan - territory or tarjeta no longer exists
          noEncontradas++;
          debugPrint(
              'Huérfana: ${doc.id} - territorioId: $territorioId - parte: ${parts[1]}');
        }
      }

      // Commit any remaining operations
      if (batchCount > 0) {
        await currentBatch.commit();
      }

      if (mounted) {
        String mensaje = actualizadas > 0
            ? '✅ $actualizadas direcciones actualizadas con tarjeta_id'
            : '⚠️ $noEncontradas direcciones no pudieron asociarse (no se encontró tarjeta coincidente)';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: actualizadas > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _limpiarDatosDinamicos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔄 Limpiar datos dinámicos'),
        content: const Text(
          'Esto reiniciará en todas las direcciones:\n\n'
          '• visitado → false\n'
          '• predicado → false\n'
          '• estado_predicacion → pendiente\n'
          '• asignado_a → null\n'
          '• tarjeta_id → null\n\n'
          'Las direcciones y territorios NO se eliminarán.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();
      final docs = snap.docs;
      for (int i = 0; i < docs.length; i += 100) {
        final chunk = docs.skip(i).take(100).toList();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'visitado': false,
            'predicado': false,
            'estado_predicacion': 'pendiente',
            'asignado_a': null,
            'asignado_en': null,
            'tarjeta_id': null,
            'entregado_a': null,
            'entregado_en': null,
            'devuelto': false,
            'devuelto_por': null,
            'devuelto_en': null,
          });
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Datos dinámicos limpiados'),
              backgroundColor: Colors.green),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _limpiarDireccionesHuerfanas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🗑️ Limpiar direcciones huérfanas'),
        content: const Text(
          'Esto eliminará todas las direcciones en direcciones_globales '
          'cuya tarjeta_id apunte a una tarjeta que ya no existe.\n\n'
          '⚠️ Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar huérfanas'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      // Get all existing tarjeta IDs from all territories
      final territoriosSnap =
          await FirebaseFirestore.instance.collection('territorios').get();
      final tarjetaIdsExistentes = <String>{};
      for (final territorio in territoriosSnap.docs) {
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();
        for (final t in tarjetasSnap.docs) {
          tarjetaIdsExistentes.add(t.id);
        }
      }
      // Find orphaned direcciones
      final direccionesSnap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isNotEqualTo: null)
          .get();
      final huerfanas = direccionesSnap.docs.where((dir) {
        final tarjetaId = dir.data()['tarjeta_id'] as String?;
        return tarjetaId != null && !tarjetaIdsExistentes.contains(tarjetaId);
      }).toList();

      int count = huerfanas.length;
      for (int i = 0; i < huerfanas.length; i += 100) {
        final chunk = huerfanas.skip(i).take(100).toList();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (final dir in chunk) {
          batch.update(
              dir.reference, {'tarjeta_id': null, 'estado': 'disponible'});
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('✅ $count direcciones huérfanas limpiadas'),
              backgroundColor: Colors.green),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Widget _buildBotonMantenimiento({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icono, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(titulo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _iniciarNuevoMes() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🗓️ Iniciar nuevo mes'),
        content: const Text(
          'Esto realizará:\n\n'
          '• Liberar todas las tarjetas (quitar asignaciones)\n'
          '• Marcar tarjetas como no completadas\n'
          '• Dejar todo listo para el nuevo ciclo\n\n'
          '⚠️ Las direcciones NO se modifican ni eliminan.',
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
            child: const Text('Iniciar nuevo mes'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Iniciando nuevo mes...'),
            duration: Duration(seconds: 10),
          ),
        );

      // SOLO resetear tarjetas — direcciones intactas
      final territoriosSnap =
          await FirebaseFirestore.instance.collection('territorios').get();

      for (final territorio in territoriosSnap.docs) {
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();

        final tarjetaDocs = tarjetasSnap.docs;
        for (int i = 0; i < tarjetaDocs.length; i += 100) {
          final chunk = tarjetaDocs.skip(i).take(100).toList();
          WriteBatch batch = FirebaseFirestore.instance.batch();
          for (final tarjeta in chunk) {
            batch.update(tarjeta.reference, {
              'asignado_a': null,
              'asignado_en': null,
              'completada': false,
              'fecha_completada': null,
              'enviado_a': null,
              'enviado_nombre': null,
              'enviado_en': null,
              'enviado_tipo': null,
              'estatus_envio': 'disponible',
              'bloqueado': true, // ✅ cerrado por defecto
              'disponible_para_publicadores':
                  false, // ✅ no visible para publicadores
              'conductor_email': null,
              'publicador_email': null,
            });
          }
          await batch.commit();
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // PASO 3: Limpiar enviado_a de territorios
      final territoriosSnap2 =
          await FirebaseFirestore.instance.collection('territorios').get();

      for (final ter in territoriosSnap2.docs) {
        // Skip colecciones especiales
        if (['temporales', 'removidas', 'estadisticas'].contains(ter.id))
          continue;

        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(ter.id)
            .update({
          'enviado_a': null,
          'enviado_nombre': null,
          'enviado_en': null,
          'conductor_email': null,
          'estatus_envio': 'disponible',
        });
      }

// PASO 4: Resetear asignado_a en direcciones_globales
      final dirs = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      for (int i = 0; i < dirs.docs.length; i += 100) {
        final chunk = dirs.docs.skip(i).take(100).toList();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'asignado_a': null,
            'predicado': false,
            'estado_predicacion': 'pendiente',
            'fecha_predicacion': null,
            'mes_predicacion': null,
          });
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 300));
      }

// PASO 5: Guardar snapshot en estadisticas antes de limpiar
      final mesAnterior =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      await FirebaseFirestore.instance
          .collection('estadisticas')
          .doc(mesAnterior)
          .set({
        'mes': mesAnterior,
        'total_direcciones': dirs.docs.length,
        'predicadas': dirs.docs.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          return data['predicado'] == true;
        }).length,
        'creado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ Nuevo mes iniciado correctamente'),
              ],
            ),
            backgroundColor: Color(0xFF1B5E20),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔧 Mantenimiento del Sistema',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B5E20)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estas acciones se ejecutan automáticamente el primer día de cada mes. También puedes ejecutarlas manualmente.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _buildBotonMantenimiento(
            icono: Icons.calendar_month,
            titulo: 'Iniciar nuevo mes',
            descripcion:
                'Resetea predicaciones, libera todas las tarjetas y deja el sistema listo para el nuevo ciclo mensual.',
            color: const Color(0xFF1B5E20),
            onPressed: _iniciarNuevoMes,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.find_replace,
            titulo: 'Restaurar tarjeta_id',
            descripcion:
                'Vincula las direcciones a sus tarjetas basándose en el ID del documento.',
            color: Colors.blue,
            onPressed: _restaurarTarjetaIds,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.refresh,
            titulo: 'Limpiar datos dinámicos',
            descripcion:
                'Reinicia visitado, predicado, asignaciones. NO elimina direcciones.',
            color: Colors.orange,
            onPressed: _limpiarDatosDinamicos,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.delete_sweep,
            titulo: 'Limpiar direcciones huérfanas',
            descripcion:
                'Elimina direcciones que apuntan a tarjetas que ya no existen.',
            color: Colors.red,
            onPressed: _limpiarDireccionesHuerfanas,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.delete_outline,
            titulo: 'Borrar todas las direcciones',
            descripcion:
                'Elimina TODAS las direcciones del directorio global permanentemente.',
            color: Colors.red.shade900,
            onPressed: _borrarTodasDirecciones,
          ),
        ],
      ),
    );
  }
}
