import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MantenimientoTab extends StatefulWidget {
  const MantenimientoTab({super.key});

  @override
  State<MantenimientoTab> createState() => _MantenimientoTabState();
}

class _MantenimientoTabState extends State<MantenimientoTab> {
  bool _desbloqueado = false;
  final TextEditingController _pinCtrl = TextEditingController();
  static const String _pin = '272700';

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarPin() async {
    _pinCtrl.clear();
    final ingresado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.lock, color: Color(0xFF1B5E20)),
            SizedBox(width: 8),
            Text('Área restringida'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Esta sección es solo para administradores.\nIngresa el PIN de mantenimiento.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(c, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, _pinCtrl.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
              ),
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );

    if (ingresado == null) return;

    // Verificar contra Firestore o PIN local
    final doc = await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('pin_mantenimiento')
        .get();
    final pinCorrecto = (doc.data()?['pin'] as String?) ?? _pin;

    if (ingresado == pinCorrecto) {
      setState(() => _desbloqueado = true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN incorrecto'), backgroundColor: Colors.red),
        );
      }
    }
  }
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

  List<String> _normalizarTokens(String texto) {
    var t = texto.toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íìî]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úùû]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.split(' ').where((w) => w.length >= 2).toSet().toList();
  }

  Future<void> _limpiarEstadisticas() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🗑️ Limpiar estadísticas'),
        content: const Text('Elimina todos los datos estadísticos.\nUsar antes del uso real (salir del modo prueba).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ Limpiando estadísticas...'), duration: Duration(seconds: 30)),
    );
    try {
      int total = 0;
      final snap1 = await FirebaseFirestore.instance.collection('estadisticas_mensuales').get();
      if (snap1.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap1.docs) { batch.delete(d.reference); }
        await batch.commit();
        total += snap1.docs.length;
      }
      final snap2 = await FirebaseFirestore.instance.collection('direcciones_globales').limit(500).get();
      if (snap2.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap2.docs) {
          batch.update(d.reference, {
            'predicado': false, 'no_predicado': false,
            'estado_predicacion': 'pendiente', 'entrego_invitacion': false,
            'fecha_predicacion': null, 'mes_predicacion': null,
          });
        }
        await batch.commit();
        total += snap2.docs.length;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Estadísticas limpiadas ($total registros)'), backgroundColor: Colors.deepOrange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _migrarPalabrasClave() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔍 Migrar índice de búsqueda'),
        content: const Text(
          'Esto agrega el campo palabras_clave a todas las direcciones existentes.\n\n'
          'Necesario para que el Localizador funcione con búsqueda inteligente.\n\n'
          'Solo se ejecuta una vez.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Migrar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔍 Migrando índice de búsqueda...'), duration: Duration(seconds: 60)),
    );

    try {
      final snap = await FirebaseFirestore.instance.collection('direcciones_globales').get();
      int actualizadas = 0;

      for (int i = 0; i < snap.docs.length; i += 100) {
        final chunk = snap.docs.skip(i).take(100).toList();
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          final data = doc.data();
          final calle = (data['calle'] as String?) ?? '';
          final comp = (data['complemento'] as String?) ?? '';
          if (calle.isEmpty) continue;

          final tokens = _normalizarTokens(calle);
          if (comp.isNotEmpty) tokens.addAll(_normalizarTokens(comp));

          batch.update(doc.reference, {
            'palabras_clave': tokens,
            'calle_normalizada': _normalizarTokens(calle).join(' '),
          });
          actualizadas++;
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $actualizadas direcciones indexadas'),
            backgroundColor: Colors.purple,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restaurarTarjetaIds() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔧 Restaurar tarjeta_id'),
        content: const Text(
          'Restaura el campo tarjeta_id usando el ID del documento.\n\n'
          'Ejemplo: "IGUAÇU_B02-IGUAÇU_Rua..." → tarjeta_id = "B02-IGUAÇU"\n\n'
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

    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Restaurando vínculos...'),
          duration: Duration(seconds: 30),
        ),
      );

    try {
      // Cargar todas las tarjetas para validar que existen
      final Set<String> tarjetasValidas = {};
      final territoriosSnap = await FirebaseFirestore.instance
          .collection('territorios')
          .get();
      for (final ter in territoriosSnap.docs) {
        if (['temporales', 'removidas', 'estadisticas'].contains(ter.id))
          continue;
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(ter.id)
            .collection('tarjetas')
            .get();
        for (final t in tarjetasSnap.docs) {
          tarjetasValidas.add(t.id);
        }
      }

      // Cargar todas las direcciones con tarjeta_id null
      final direccionesSnap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      int actualizadas = 0;
      int noEncontradas = 0;
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;

      for (final doc in direccionesSnap.docs) {
        final data = doc.data();
        final tarjetaIdActual = data['tarjeta_id'] as String?;

        // Para direcciones temporales, usar tarjeta_id_origen
        final tarjetaIdOrigen = data['tarjeta_id_origen'] as String?;
        if (tarjetaIdOrigen != null && tarjetaIdOrigen.isNotEmpty &&
            (tarjetaIdActual == null || tarjetaIdActual.isEmpty)) {
          batch.update(doc.reference, {
            'tarjeta_id': tarjetaIdOrigen,
            'nombre_tarjeta': tarjetaIdOrigen,
          });
          actualizadas++;
          batchCount++;
          if (batchCount >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
          continue;
        }

        // Si ya tiene tarjeta_id válido, no tocar
        if (tarjetaIdActual != null && tarjetaIdActual.isNotEmpty) continue;

        // Extraer tarjeta_id del ID del documento
        // Formato: "IGUAÇU_B02-IGUAÇU_Rua_..."
        // La tarjeta es la segunda parte: "B02-IGUAÇU"
        final docId = doc.id;
        final parts = docId.split('_');

        String? tarjetaId;

        if (parts.length >= 2) {
          // Intentar con parts[1] (ej: "B02-IGUAÇU")
          final candidato = parts[1];
          if (tarjetasValidas.contains(candidato)) {
            tarjetaId = candidato;
          } else {
            // Intentar combinando parts[1]_parts[2] si existe
            if (parts.length >= 3) {
              final candidato2 = '${parts[1]}_${parts[2]}';
              if (tarjetasValidas.contains(candidato2)) {
                tarjetaId = candidato2;
              }
            }
          }
        }

        if (tarjetaId != null) {
          batch.update(doc.reference, {
            'tarjeta_id': tarjetaId,
            'nombre_tarjeta': tarjetaId,
            'estado': 'asignada',
          });
          actualizadas++;
          batchCount++;
          if (batchCount >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
        } else {
          noEncontradas++;
        }
      }

      if (batchCount > 0) await batch.commit();

      // Actualizar contadores en tarjetas
      for (final ter in territoriosSnap.docs) {
        if (['temporales', 'removidas', 'estadisticas'].contains(ter.id))
          continue;
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(ter.id)
            .collection('tarjetas')
            .get();
        for (final t in tarjetasSnap.docs) {
          final count = await FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('tarjeta_id', isEqualTo: t.id)
              .count()
              .get();
          await FirebaseFirestore.instance
              .collection('territorios')
              .doc(ter.id)
              .collection('tarjetas')
              .doc(t.id)
              .update({'cantidad_direcciones': count.count});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $actualizadas restauradas'
              '${noEncontradas > 0 ? ' · $noEncontradas sin tarjeta' : ''}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _limpiarPendientes() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔄 Limpiar prioridades pendientes'),
        content: const Text(
          'Elimina las marcas de "pendiente del mes anterior" de:\n\n'
          '• Direcciones (prioridad_mes_anterior)\n'
          '• Tarjetas (prioridad_admin)\n\n'
          'Todo vuelve a estado normal.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔄 Limpiando pendientes...'), duration: Duration(seconds: 30)),
      );
      final db = FirebaseFirestore.instance;
      int total = 0;

      // Limpiar prioridad en TODAS las direcciones activas
      final dirs = await db.collection('direcciones_globales').get();
      for (int i = 0; i < dirs.docs.length; i += 100) {
        final chunk = dirs.docs.skip(i).take(100).toList();
        final b = db.batch();
        for (final d in chunk) {
          b.update(d.reference, {
            'prioridad_mes_anterior': false,
            'mes_pendiente': null,
          });
        }
        await b.commit();
        total += chunk.length;
      }

      // Limpiar prioridad en TODAS las tarjetas
      final ters = await db.collection('territorios').get();
      for (final ter in ters.docs) {
        if (['temporales','removidas','estadisticas','campanas'].contains(ter.id)) continue;
        final tarjetas = await db.collection('territorios').doc(ter.id)
            .collection('tarjetas').get();
        if (tarjetas.docs.isEmpty) continue;
        final b = db.batch();
        for (final t in tarjetas.docs) {
          b.update(t.reference, {
            'prioridad_admin': false,
            'mes_prioridad': null,
          });
        }
        await b.commit();
        total += tarjetas.docs.length;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $total prioridades limpiadas'),
          backgroundColor: Colors.blueGrey,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _limpiarDatosDinamicos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔄 Limpiar datos dinámicos'),
        content: const Text(
          'Esto limpiará:\n\n'
          '• predicado → false en todas las direcciones\n'
          '• estado_predicacion → pendiente\n'
          '• Notificaciones leídas → eliminadas\n'
          '• Tarjetas temporales → eliminadas\n'
          '• Direcciones temporales en direcciones_globales → eliminadas\n'
          '• Direcciones huérfanas → eliminadas\n\n'
          '⚠️ Las direcciones activas y vínculos tarjeta_id NO se modifican.',
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Limpiando datos...'),
            duration: Duration(seconds: 60),
          ),
        );

      final db = FirebaseFirestore.instance;

      // 1. Resetear predicaciones en direcciones
      final snap = await db.collection('direcciones_globales').get();
      for (int i = 0; i < snap.docs.length; i += 100) {
        final chunk = snap.docs.skip(i).take(100).toList();
        WriteBatch batch = db.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'predicado': false,
            'estado_predicacion': 'pendiente',
            'mes_predicacion': null,
            'fecha_predicacion': null,
            'motivo_temporal': null,
          });
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 2. Eliminar tarjetas temporales (con sus subcolecciones de direcciones)
      final temporalesSnap = await db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .get();
      for (final t in temporalesSnap.docs) {
        // Primero eliminar subcolección direcciones
        final dirsSubSnap = await t.reference.collection('direcciones').get();
        if (dirsSubSnap.docs.isNotEmpty) {
          for (int i = 0; i < dirsSubSnap.docs.length; i += 100) {
            final chunk = dirsSubSnap.docs.skip(i).take(100).toList();
            final b = db.batch();
            for (final d in chunk) b.delete(d.reference);
            await b.commit();
          }
        }
        // Luego eliminar el documento padre
        await t.reference.delete();
      }

      // 3. Eliminar direcciones temporales de direcciones_globales
      final dirsTemporales = await db
          .collection('direcciones_globales')
          .where('territorio_id', isEqualTo: 'temporales')
          .get();
      for (int i = 0; i < dirsTemporales.docs.length; i += 100) {
        final chunk = dirsTemporales.docs.skip(i).take(100).toList();
        WriteBatch batch = db.batch();
        for (final d in chunk) batch.delete(d.reference);
        await batch.commit();
      }

      // 4. Eliminar notificaciones leídas
      final notifSnap = await db
          .collection('notificaciones')
          .where('leida', isEqualTo: true)
          .get();
      for (int i = 0; i < notifSnap.docs.length; i += 100) {
        final chunk = notifSnap.docs.skip(i).take(100).toList();
        WriteBatch batch = db.batch();
        for (final n in chunk) batch.delete(n.reference);
        await batch.commit();
      }

      // 5. Limpiar direcciones huérfanas (tarjeta_id apunta a tarjeta inexistente)
      final todasTarjetas = <String>{};
      final terSnap = await db.collection('territorios').get();
      for (final ter in terSnap.docs) {
        if (['removidas', 'estadisticas'].contains(ter.id)) continue;
        final tarjSnap = await db
            .collection('territorios')
            .doc(ter.id)
            .collection('tarjetas')
            .get();
        for (final t in tarjSnap.docs) todasTarjetas.add(t.id);
      }

      int huerfanas = 0;
      for (int i = 0; i < snap.docs.length; i += 100) {
        final chunk = snap.docs.skip(i).take(100).toList();
        WriteBatch batch = db.batch();
        bool hasOp = false;
        for (final doc in chunk) {
          final tarjetaId = (doc.data()['tarjeta_id'] as String?) ?? '';
          if (tarjetaId.isNotEmpty && !todasTarjetas.contains(tarjetaId)) {
            batch.delete(doc.reference);
            huerfanas++;
            hasOp = true;
          }
        }
        if (hasOp) await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Limpieza completa\n'
              '• ${temporalesSnap.docs.length} tarjetas temporales\n'
              '• ${dirsTemporales.docs.length} dirs temporales\n'
              '• ${notifSnap.docs.length} notificaciones\n'
              '• $huerfanas dirs huérfanas',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
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
        color: Theme.of(context).cardColor,
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
          '• Guardar estadísticas del mes actual\n'
          '• Marcar direcciones no predicadas como prioridad\n'
          '• Devolver tarjetas incompletas al conductor\n'
          '• Resetear predicaciones del mes\n'
          '• Temporales: devolver dirs a su tarjeta/territorio de origen\n'
          '• Limpiar notificaciones antiguas\n\n'
          '⚠️ Las direcciones NO se eliminan permanentemente.',
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔄 Iniciando nuevo mes...'), duration: Duration(seconds: 60)),
      );

      final ahora = DateTime.now();
      final mesAnterior = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
      final nuevoMes = ahora.month == 12
          ? DateTime(ahora.year + 1, 1, 1)
          : DateTime(ahora.year, ahora.month + 1, 1);
      final nuevoMesStr = '${nuevoMes.year}-${nuevoMes.month.toString().padLeft(2, '0')}';

      // ── PASO 1: Guardar estadísticas ──────────────────────────
      final dirs = await FirebaseFirestore.instance
          .collection('direcciones_globales').get();
      final predicadas = dirs.docs.where((d) => (d.data())['predicado'] == true).length;
      final noPredicadas = dirs.docs.where((d) =>
          (d.data())['predicado'] != true &&
          (d.data())['estado'] == 'activa').length;

      await FirebaseFirestore.instance.collection('estadisticas').doc(mesAnterior).set({
        'mes': mesAnterior,
        'total_direcciones': dirs.docs.length,
        'predicadas': predicadas,
        'no_predicadas': noPredicadas,
        'creado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('configuraciones').doc('mes_actual').set({
        'inicio_mes': Timestamp.fromDate(nuevoMes),
        'mes_str': nuevoMesStr,
        'actualizado_en': FieldValue.serverTimestamp(),
      });

      // ── PASO 2: Marcar direcciones no predicadas como prioridad ──
      // y resetear las predicadas para el nuevo mes
      for (int i = 0; i < dirs.docs.length; i += 100) {
        final chunk = dirs.docs.skip(i).take(100).toList();
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          final d = doc.data();
          final fuePredicada = d['predicado'] == true;
          final estadoActual = d['estado'] as String? ?? 'activa';
          if (estadoActual != 'activa') continue;

          if (fuePredicada) {
            // Predicada → resetear para nuevo mes
            batch.update(doc.reference, {
              'predicado': false,
              'estado_predicacion': 'pendiente',
              'fecha_predicacion': null,
              'mes_predicacion': null,
              'prioridad_mes_anterior': false,
              'motivo_temporal': null,
            });
          } else {
            // NO predicada → marcar como prioridad del mes siguiente
            batch.update(doc.reference, {
              'predicado': false,
              'estado_predicacion': 'pendiente',
              'prioridad_mes_anterior': true,
              'mes_pendiente': mesAnterior,
              'fecha_predicacion': null,
              'mes_predicacion': null,
              'motivo_temporal': null,
            });
          }
        }
        await batch.commit();
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // ── PASO 3: Tarjetas — devolver incompletas al conductor ──
      final territoriosSnap = await FirebaseFirestore.instance
          .collection('territorios').get();

      for (final territorio in territoriosSnap.docs) {
        if (['temporales', 'removidas', 'estadisticas', 'campanas'].contains(territorio.id)) continue;

        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios').doc(territorio.id)
            .collection('tarjetas').get();

        for (int i = 0; i < tarjetasSnap.docs.length; i += 100) {
          final chunk = tarjetasSnap.docs.skip(i).take(100).toList();
          final batch = FirebaseFirestore.instance.batch();
          for (final tarjeta in chunk) {
            final td = tarjeta.data();
            final completada = td['completada'] == true;
            final asignado = (td['asignado_a'] as String?) ?? '';

            // Tarjeta con prioridad: estaba asignada y no fue completada,
            // o ya tenía flag prioridad_admin de meses anteriores
            final esPrioridad = (!completada && asignado.isNotEmpty) ||
                td['prioridad_admin'] == true;

            batch.update(tarjeta.reference, {
              'mes_anterior': mesAnterior,
              'asignado_a': null,
              'asignado_en': null,
              'mes_asignacion': null,
              'completada': false,
              'fecha_completada': null,
              'enviado_a': null,
              'enviado_nombre': null,
              'enviado_en': null,
              'enviado_tipo': null,
              'publicador_email': null,
              'publicador_nombre': null,
              'conductor_email': null,
              'estatus_envio': 'disponible',
              'bloqueado': true,
              'disponible_para_publicadores': false,
              'prioridad_admin': esPrioridad,
              'mes_prioridad': esPrioridad ? mesAnterior : null,
            });
          }
          await batch.commit();
          await Future.delayed(const Duration(milliseconds: 150));
        }

        // Resetear territorio
        await FirebaseFirestore.instance
            .collection('territorios').doc(territorio.id)
            .update({
          'enviado_a': null,
          'enviado_nombre': null,
          'enviado_en': null,
          'conductor_email': null,
          'estatus_envio': 'disponible',
          'disponible_para_publicadores': false,
        });
      }

      // ── PASO 4: Tarjetas temporales → devolver dirs a origen ──────────────
      final db = FirebaseFirestore.instance;
      final temporalesSnap = await db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .get();

      for (final tarjetaTemp in temporalesSnap.docs) {
        // Devolver cada dirección a su tarjeta/territorio de origen
        final dirsTemp = await db
            .collection('direcciones_globales')
            .where('tarjeta_id', isEqualTo: tarjetaTemp.id)
            .get();

        if (dirsTemp.docs.isNotEmpty) {
          for (int i = 0; i < dirsTemp.docs.length; i += 400) {
            final chunk = dirsTemp.docs.skip(i).take(400).toList();
            final batchDir = db.batch();
            for (final dir in chunk) {
              final dd = dir.data();
              final tarjetaOrigen = (dd['tarjeta_id_origen'] as String?) ?? '';
              final territorioOrigen = (dd['territorio_id_origen'] as String?) ?? '';
              if (tarjetaOrigen.isNotEmpty && territorioOrigen.isNotEmpty) {
                // Restaurar al origen — resetear estado predicación
                batchDir.update(dir.reference, {
                  'tarjeta_id': tarjetaOrigen,
                  'territorio_id': territorioOrigen,
                  'barrio': territorioOrigen,
                  'es_temporal': false,
                  'tarjeta_id_origen': FieldValue.delete(),
                  'territorio_id_origen': FieldValue.delete(),
                  'predicado': false,
                  'estado_predicacion': 'pendiente',
                  'asignado_a': null,
                  'motivo_temporal': null,
                });
              }
            }
            await batchDir.commit();
          }
        }

        // Eliminar la tarjeta temporal (ya no tiene direcciones)
        await tarjetaTemp.reference.delete();
      }
      debugPrint('🧹 ${temporalesSnap.docs.length} tarjetas temporales procesadas');

      // Limpiar datos basura automáticamente
      final fi = FirebaseFirestore.instance;
      final hace30dias = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
      final notifSnap = await fi.collection('notificaciones')
          .where('created_at', isLessThan: hace30dias).limit(500).get();
      if (notifSnap.docs.isNotEmpty) {
        final b = fi.batch();
        for (final d in notifSnap.docs) b.delete(d.reference);
        await b.commit();
      }
      final solVSnap = await fi.collection('solicitudes_localizador')
          .where('created_at', isLessThan: hace30dias).limit(500).get();
      final solPSnap = await fi.collection('solicitudes_localizador')
          .where('estado', whereIn: ['aprobada', 'rechazada', 'agregada']).limit(500).get();
      final solRefs = <DocumentReference>{
        ...solVSnap.docs.map((d) => d.reference),
        ...solPSnap.docs.map((d) => d.reference),
      };
      if (solRefs.isNotEmpty) {
        final b = fi.batch();
        for (final r in solRefs) b.delete(r);
        await b.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('✅ Nuevo mes $nuevoMesStr iniciado. '
                  '${noPredicadas} dirs. marcadas como prioridad.'),
            ]),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si no está desbloqueado, mostrar pantalla de bloqueo
    if (!_desbloqueado) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock, size: 48, color: Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Mantenimiento',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Área restringida — requiere PIN',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _verificarPin,
              icon: const Icon(Icons.lock_open),
              label: const Text('Ingresar PIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

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
            icono: Icons.flag_outlined,
            titulo: '🔄 Limpiar prioridades pendientes',
            descripcion:
                'Elimina las marcas de "pendiente del mes anterior" de tarjetas y direcciones. Todo vuelve a estado normal.',
            color: Colors.blueGrey,
            onPressed: _limpiarPendientes,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.bar_chart,
            titulo: '🗑️ Limpiar datos de estadísticas',
            descripcion: 'Elimina todos los datos estadísticos. Usar antes de iniciar el uso real (salir del modo de prueba).',
            color: Colors.deepOrange,
            onPressed: _limpiarEstadisticas,
          ),
          const SizedBox(height: 12),
          _buildBotonMantenimiento(
            icono: Icons.search,
            titulo: 'Migrar índice de búsqueda',
            descripcion:
                'Agrega palabras_clave a todas las direcciones existentes para que el Localizador funcione correctamente.',
            color: Colors.purple,
            onPressed: _migrarPalabrasClave,
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
