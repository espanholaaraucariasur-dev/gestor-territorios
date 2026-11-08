import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auditor_panel_page.dart';
import '../../widgets/mensaje_animado_dialog.dart';

class MantenimientoTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const MantenimientoTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<MantenimientoTab> createState() => _MantenimientoTabState();
}

class _MantenimientoTabState extends State<MantenimientoTab> {
  bool _cargando = false;
  String? _resumenMigracion;

  /// Lógica para vaciar completamente TODAS las direcciones de Firestore
  /// preservando territorios y tarjetas (dejando contadores en 0)
  Future<void> _ejecutarResetGlobalDirecciones() async {
    final firestore = FirebaseFirestore.instance;

    // Loader de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(width: 16),
            Expanded(child: Text("Ejecutando vaciado total de direcciones en Firestore...")),
          ],
        ),
      ),
    );

    try {
      // 1. Limpiar colección 'direcciones_globales'
      final dirGlobalesSnap = await firestore.collection('direcciones_globales').get();
      WriteBatch batch1 = firestore.batch();
      int count = 0;
      for (var doc in dirGlobalesSnap.docs) {
        batch1.delete(doc.reference);
        count++;
        if (count == 400) { // Limite de lotes Firestore
          await batch1.commit();
          batch1 = firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch1.commit();

      // 2. Limpiar colección 'direcciones'
      final direccionesSnap = await firestore.collection('direcciones').get();
      WriteBatch batch2 = firestore.batch();
      count = 0;
      for (var doc in direccionesSnap.docs) {
        batch2.delete(doc.reference);
        count++;
        if (count == 400) {
          await batch2.commit();
          batch2 = firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch2.commit();

      // 3. Limpiar colección 'sugerencias'
      final sugerenciasSnap = await firestore.collection('sugerencias').get();
      WriteBatch batch3 = firestore.batch();
      count = 0;
      for (var doc in sugerenciasSnap.docs) {
        batch3.delete(doc.reference);
        count++;
        if (count == 400) {
          await batch3.commit();
          batch3 = firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch3.commit();

      // 4. Limpiar subcolecciones / arreglos de direcciones e ir a CERO en cada Tarjeta
      final tarjetasSnap = await firestore.collection('tarjetas').get();
      for (var tarjetaDoc in tarjetasSnap.docs) {
        // Eliminar subcolección 'direcciones' dentro de la tarjeta
        final subDirSnap = await tarjetaDoc.reference.collection('direcciones').get();
        WriteBatch subBatch = firestore.batch();
        int subCount = 0;
        for (var subDoc in subDirSnap.docs) {
          subBatch.delete(subDoc.reference);
          subCount++;
          if (subCount == 400) {
            await subBatch.commit();
            subBatch = firestore.batch();
            subCount = 0;
          }
        }

        // Reiniciar contador y limpiar array local de la tarjeta
        subBatch.update(tarjetaDoc.reference, {
          'totalDirecciones': 0,
          'cantidad_direcciones': 0,
          'direcciones': [],
          'ultimocambio': FieldValue.serverTimestamp(),
        });
        await subBatch.commit();
      }

      // 4b. Idem para las tarjetas canónicas (subcolección
      // territorios/{id}/tarjetas), que son las que usa la app.
      final tersSnap = await firestore.collection('territorios').get();
      for (var terDoc in tersSnap.docs) {
        final subTarjSnap = await firestore
            .collection('territorios')
            .doc(terDoc.id)
            .collection('tarjetas')
            .get();
        for (var tarjetaDoc in subTarjSnap.docs) {
          final subDirSnap =
              await tarjetaDoc.reference.collection('direcciones').get();
          WriteBatch subBatch = firestore.batch();
          int subCount = 0;
          for (var subDoc in subDirSnap.docs) {
            subBatch.delete(subDoc.reference);
            subCount++;
            if (subCount == 400) {
              await subBatch.commit();
              subBatch = firestore.batch();
              subCount = 0;
            }
          }
          subBatch.update(tarjetaDoc.reference, {
            'totalDirecciones': 0,
            'cantidad_direcciones': 0,
            'direcciones': [],
            'ultimocambio': FieldValue.serverTimestamp(),
          });
          await subBatch.commit();
        }
      }

      if (mounted) {
        Navigator.pop(context); // Cierra loader
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reset completado: Se borraron TODAS las direcciones de todas las colecciones y tarjetas.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // Refrescar UI
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en el reset: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Migra las tarjetas huérfanas de la colección raíz `tarjetas` hacia la
  /// subcolección canónica `territorios/{territorioId}/tarjetas`, preservando
  /// el doc id para no romper el `tarjeta_id` de las direcciones. Si la tarjeta
  /// raíz no declara territorio, se asocia por coincidencia de nombre con los
  /// territorios existentes. Una vez copiada, se elimina el original.
  Future<void> _migrarTarjetasLegacy() async {
    final firestore = FirebaseFirestore.instance;

    // Inventario de territorios (id por nombre normalizado) y de tarjetas
    // canónicas ya existentes para no duplicar.
    final tersSnap = await firestore.collection('territorios').get();
    final territorioIdPorNombre = <String, String>{};
    final tarjetasCanonicas = <String>{}; // 'terId/cardId'
    for (final t in tersSnap.docs) {
      final nombreTer = (t.data()['nombre']?.toString() ?? '').toUpperCase().trim();
      if (nombreTer.isNotEmpty) territorioIdPorNombre[nombreTer] = t.id;
      final sub = await firestore
          .collection('territorios')
          .doc(t.id)
          .collection('tarjetas')
          .get();
      for (final d in sub.docs) {
        tarjetasCanonicas.add('${t.id}/${d.id}');
      }
    }

    final legacySnap = await firestore.collection('tarjetas').get();
    var batch = firestore.batch();
    int ops = 0;
    int migradas = 0;
    int omitidas = 0;

    Future<void> commitSiNecesario() async {
      if (ops >= 400) {
        await batch.commit();
        batch = firestore.batch();
        ops = 0;
      }
    }

    for (final doc in legacySnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      var territorioId = (data['territorio_id']?.toString() ?? '').trim();
      if (territorioId.isEmpty) {
        final nombreTarjeta =
            (data['nombre']?.toString() ?? doc.id).toUpperCase().trim();
        territorioId = territorioIdPorNombre[nombreTarjeta] ?? '';
      }
      if (territorioId.isEmpty ||
          tarjetasCanonicas.contains('$territorioId/${doc.id}')) {
        omitidas++;
        continue;
      }
      batch.set(
        firestore
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(doc.id),
        {...data, 'territorio_id': territorioId, 'migrada_de_legacy': true},
      );
      ops++;
      batch.delete(doc.reference);
      ops++;
      migradas++;
      await commitSiNecesario();
    }
    if (ops > 0) await batch.commit();

    _resumenMigracion = 'Tarjetas migradas: $migradas · omitidas: $omitidas';
  }

  /// Elimina de `direcciones_globales` las direcciones cuyo `tarjeta_id`
  /// apunta a una tarjeta inexistente (huérfanas por vínculo roto). SEMANTICA
  /// INTENCIONAL: las direcciones SIN `tarjeta_id` (pendientes/sueltas) se
  /// CONSERVAN, porque en esta app son datos legítimos en espera de reorg.
  Future<void> _limpiarDireccionesHuerfanas() async {
    final firestore = FirebaseFirestore.instance;

    // 1. Conjunto de tarjetas válidas: subcolección canónica
    //    territorios/{id}/tarjetas + raíz legacy aún sin migrar.
    final idsTarjetasValidas = <String>{};
    final tersSnap = await firestore.collection('territorios').get();
    for (final t in tersSnap.docs) {
      final sub = await firestore
          .collection('territorios')
          .doc(t.id)
          .collection('tarjetas')
          .get();
      for (final d in sub.docs) {
        idsTarjetasValidas.add(d.id);
      }
    }
    try {
      final legacy = await firestore.collection('tarjetas').get();
      for (final d in legacy.docs) {
        idsTarjetasValidas.add(d.id);
      }
    } catch (_) {}

    // 2. Evaluar la colección global.
    final globalSnap =
        await firestore.collection('direcciones_globales').get();
    final huerfanas = <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in globalSnap.docs) {
      final tarjetaId = (doc.data()['tarjeta_id']?.toString() ?? '').trim();
      if (tarjetaId.isNotEmpty && !idsTarjetasValidas.contains(tarjetaId)) {
        huerfanas.add(doc.reference);
      }
    }

    // 3. Borrado en lotes de <=400 operaciones.
    if (huerfanas.isEmpty) {
      _resumenMigracion = 'No se encontraron direcciones huérfanas';
      return;
    }
    var batch = firestore.batch();
    int ops = 0;
    for (final ref in huerfanas) {
      batch.delete(ref);
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = firestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();

    _resumenMigracion =
        'Se eliminaron ${huerfanas.length} direcciones huérfanas de la colección global';
  }

  Future<void> _ejecutarAccion(String titulo, Future<void> Function() accion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text('¿Estás seguro de que deseas ejecutar "$titulo"? Esta acción afectará los datos en Firestore.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar y Ejecutar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);
    try {
      await accion();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_resumenMigracion?.isNotEmpty == true
                ? _resumenMigracion!
                : '$titulo ejecutado con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ejecutar $titulo: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() {
        _cargando = false;
        _resumenMigracion = null;
      });
    }
  }

  /// Abre el diálogo motivacional con un mensaje real de la base, para ver
  /// cada escena. Es solo vista previa: no envía nada ni toca tareas.
  Future<void> _vistaPreviaMotivacional() async {
    String texto =
        '¡Gracias por tu valioso apoyo hoy! Tu servicio de casa en casa es de gran ánimo. 🏠';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('mensajes_motivacionales')
          .collection('mensajes')
          .where('activo', isEqualTo: true)
          .get();
      final textos = snap.docs
          .map((d) => (d.data()['texto'] as String?)?.trim() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      if (textos.isNotEmpty) {
        textos.shuffle();
        texto = textos.first;
      }
    } catch (_) {
      // Sin red: se muestra el texto de ejemplo.
    }
    if (!mounted) return;
    const emojis = ['🌅', '📖', '🌱', '🌿', '🌍', '✨'];
    final semilla = texto.codeUnits.fold<int>(0, (a, b) => a + b);
    await MensajeAnimadoDialog.mostrar(
      context,
      titulo: '🌟 Mensaje para ti',
      cuerpo: texto,
      iconoEmoji: emojis[semilla % emojis.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Herramientas de Mantenimiento',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Acciones avanzadas para gestión de datos, vaciado global y panel de auditoría.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),

          if (_cargando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Procesando datos en Firestore...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            )
          else ...[
            // Botón de Limpieza Global de Direcciones
            _buildCardButton(
              icon: Icons.cleaning_services,
              title: 'Reset Global: Eliminar Direcciones',
              description: 'Elimina todas las direcciones de Firestore dejando intactos los nombres de Territorios y Tarjetas.',
              isDestructive: true,
              onTap: () => _ejecutarAccion(
                'Reset Global: Eliminar Direcciones',
                _ejecutarResetGlobalDirecciones,
              ),
            ),
            _buildCardButton(
              icon: Icons.health_and_safety,
              title: 'Panel de Auditoría',
              description: 'Accede a la consola de ajustes finos y registros del auditor.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuditorPanelPage(usuarioData: widget.usuarioData),
                  ),
                );
              },
            ),
            _buildCardButton(
              icon: Icons.sync,
              title: 'Reindexar Documentos',
              description: 'Sincroniza y repara registros inconsistentes en la base de datos.',
              onTap: () => _ejecutarAccion(
                'Reindexar Documentos',
                () async {
                  await FirebaseFirestore.instance.collection('system').doc('maintenance').set({
                    'last_reindex': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                },
              ),
            ),
            _buildCardButton(
              icon: Icons.import_export,
              title: 'Migrar Tarjetas Legacy',
              description: 'Copia las tarjetas huérfanas de la colección raíz a territorios/{id}/tarjetas y elimina las originales (preservando su doc id).',
              onTap: () => _ejecutarAccion(
                'Migrar Tarjetas Legacy',
                _migrarTarjetasLegacy,
              ),
            ),
            _buildCardButton(
              icon: Icons.recycling,
              title: 'Limpiar Direcciones Huérfanas',
              description: 'Elimina de direcciones_globales las direcciones cuyo tarjeta_id apunta a una tarjeta inexistente. Las pendientes sin tarjeta se conservan.',
              isDestructive: true,
              onTap: () => _ejecutarAccion(
                'Limpiar Direcciones Huérfanas',
                _limpiarDireccionesHuerfanas,
              ),
            ),
            _buildCardButton(
              icon: Icons.auto_awesome_outlined,
              title: 'Vista previa: mensaje motivacional',
              description: 'Abre el diálogo animado con un mensaje real, para ver cada escena (amanecer, bosque, atardecer, lluvia).',
              onTap: _vistaPreviaMotivacional,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardButton({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Card(
      color: isDestructive ? Colors.red.shade50 : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDestructive ? Colors.red.shade100 : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: isDestructive ? Colors.red : Colors.teal, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              label: Text(isDestructive ? 'Ejecutar Limpieza' : 'Ejecutar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDestructive ? Colors.red : null,
                foregroundColor: isDestructive ? Colors.white : null,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}