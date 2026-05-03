import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TemporalesTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const TemporalesTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<TemporalesTab> createState() => _TemporalesTabState();
}

class _TemporalesTabState extends State<TemporalesTab> {
  int _sliderValue = 5;

  // ─────────────────────────────────────────────────────────
  // CREAR TARJETA TEMPORAL
  // ─────────────────────────────────────────────────────────

  Future<void> _crearTarjetaTemporal(
    String territorioId,
    String territorioNombre,
    List<DocumentSnapshot> direccionesDisponibles,
  ) async {
    final cantidad = _sliderValue.clamp(1, direccionesDisponibles.length);
    final seleccionadas = direccionesDisponibles.take(cantidad).toList();

    // Nombre único para la tarjeta temporal
    final ahora = DateTime.now();
    final nombreTarjeta =
        'T-$territorioNombre-${ahora.day}${ahora.month}-${ahora.hour}${ahora.minute}';

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // 1. Crear tarjeta en territorios/temporales/tarjetas
      final tarjetaRef = db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(nombreTarjeta);

      batch.set(tarjetaRef, {
        'nombre': nombreTarjeta,
        'territorio_id': 'temporales',
        'territorio_nombre': territorioNombre,
        'territorio_origen_id': territorioId,
        'territorio_origen_nombre': territorioNombre,
        'es_temporal': true,
        'cantidad_direcciones': seleccionadas.length,
        'completada': false,
        'bloqueado': false,
        'disponible_para_publicadores': false,
        'estatus_envio': 'disponible',
        'asignado_a': null,
        'asignado_en': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'conductor_email': null,
        'publicador_email': null,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 2. Actualizar cada dirección seleccionada
      // tarjeta_id_origen se mantiene, tarjeta_id apunta a nueva tarjeta temporal
      for (final dir in seleccionadas) {
        final data = (dir.data() as Map<String, dynamic>?) ?? {};
        final tarjetaIdOriginal = (data['tarjeta_id'] as String?) ?? '';

        batch.update(dir.reference, {
          'tarjeta_id': nombreTarjeta, // apunta a tarjeta temporal
          'tarjeta_id_origen': tarjetaIdOriginal, // guarda origen
          'territorio_id': 'temporales',
          'estado': 'temporal_asignada',
          'estado_predicacion': 'pendiente',
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tarjeta "$nombreTarjeta" creada con ${seleccionadas.length} direcciones',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF4A148C),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear tarjeta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // ENVIAR TARJETA TEMPORAL
  // ─────────────────────────────────────────────────────────

  Future<void> _enviarTarjetaTemporal(
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    // Cargar conductores y publicadores
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enviar: $tarjetaNombre'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (conductoresSnap.docs.isNotEmpty) ...[
                  const Text('Conductores:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...conductoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.drive_eta, color: Color(0xFF1B5E20)),
                      title: Text(data['nombre'] ?? ''),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvioTemporal(
                          tarjetaId: tarjetaId,
                          tarjetaNombre: tarjetaNombre,
                          destinatarioEmail: data['email'],
                          destinatarioNombre: data['nombre'],
                          tipo: 'conductor',
                        );
                      },
                    );
                  }),
                  const Divider(),
                ],
                const Text('Publicadores:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                if (publicadoresSnap.docs.isEmpty)
                  const Text('No hay publicadores disponibles.',
                      style: TextStyle(color: Colors.grey))
                else
                  ...publicadoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person, color: Colors.blue),
                      title: Text(data['nombre'] ?? ''),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvioTemporal(
                          tarjetaId: tarjetaId,
                          tarjetaNombre: tarjetaNombre,
                          destinatarioEmail: data['email'],
                          destinatarioNombre: data['nombre'],
                          tipo: 'publicador',
                        );
                      },
                    );
                  }),
              ],
            ),
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
  }

  Future<void> _ejecutarEnvioTemporal({
    required String tarjetaId,
    required String tarjetaNombre,
    required String destinatarioEmail,
    required String destinatarioNombre,
    required String tipo,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'asignado_a': tipo == 'publicador' ? destinatarioNombre : null,
        'enviado_a': destinatarioEmail,
        'enviado_nombre': destinatarioNombre,
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
        'estatus_envio': 'enviado',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$tarjetaNombre" enviada a $destinatarioNombre'),
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

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Sub-tabs
          Container(
            color: Colors.white,
            child: const TabBar(
              indicatorColor: Color(0xFF4A148C),
              labelColor: Color(0xFF4A148C),
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(
                    text: 'Direcciones',
                    icon: Icon(Icons.location_on, size: 16)),
                Tab(
                    text: 'Tarjetas T.',
                    icon: Icon(Icons.credit_card, size: 16)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildVistaAgruparDirecciones(),
                _buildVistaTarjetasTemporales(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // VISTA 1 — Direcciones agrupadas por territorio
  // ─────────────────────────────────────────────────────────

  Widget _buildVistaAgruparDirecciones() {
    return Column(
      children: [
        // Slider global
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFF4A148C), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Direcciones por tarjeta',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A148C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_sliderValue dir.',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A148C),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _sliderValue.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: const Color(0xFF4A148C),
                onChanged: (value) =>
                    setState(() => _sliderValue = value.toInt()),
              ),
            ],
          ),
        ),

        // Lista de territorios con direcciones temporales
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('direcciones_globales')
                .where('estado', isEqualTo: 'temporal')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay direcciones temporales',
                        style: TextStyle(color: Colors.grey[500], fontSize: 15),
                      ),
                    ],
                  ),
                );
              }

              // Agrupar por territorio_nombre
              final Map<String, List<DocumentSnapshot>> porTerritorio = {};
              for (final doc in docs) {
                final data = (doc.data() as Map<String, dynamic>?) ?? {};
                final terNombre =
                    (data['territorio_nombre'] as String?)?.isNotEmpty == true
                        ? data['territorio_nombre'] as String
                        : (data['barrio'] as String?)?.isNotEmpty == true
                            ? data['barrio'] as String
                            : (data['territorio_id'] as String?)?.isNotEmpty == true
                                ? data['territorio_id'] as String
                                : 'Sin territorio';
                final terId = (data['territorio_id'] as String?) ?? 'sin_id';
                final key = '$terId||$terNombre';
                porTerritorio.putIfAbsent(key, () => []).add(doc);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: porTerritorio.length,
                itemBuilder: (context, index) {
                  final key = porTerritorio.keys.elementAt(index);
                  final parts = key.split('||');
                  final terId = parts[0];
                  final terNombre = parts.length > 1 ? parts[1] : key;
                  final dirs = porTerritorio[key]!;
                  final disponibles = _sliderValue.clamp(1, dirs.length);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(
                        left: BorderSide(
                            color: const Color(0xFF4A148C), width: 4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4A148C).withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
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
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF4A148C).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.timer,
                                    color: Color(0xFF4A148C), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      terNombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF263238),
                                      ),
                                    ),
                                    Text(
                                      '${dirs.length} direcciones pendientes',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _crearTarjetaTemporal(
                                  terId,
                                  terNombre,
                                  dirs,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(
                                  'Crear T. ($disponibles)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A148C),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Muestra primeras 3 direcciones como preview
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: dirs.take(3).map((d) {
                              final data =
                                  (d.data() as Map<String, dynamic>?) ?? {};
                              final calle = (data['calle'] as String?) ?? '';
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  calle,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                          ),
                          if (dirs.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${dirs.length - 3} más...',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
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
    );
  }

  // ─────────────────────────────────────────────────────────
  // VISTA 2 — Tarjetas temporales creadas
  // ─────────────────────────────────────────────────────────

  Widget _buildVistaTarjetasTemporales() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .where('completada', isNotEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tarjetas = snapshot.data!.docs
            .where((d) =>
                (d.data() as Map<String, dynamic>)['tipo'] != 'folder_temporal')
            .toList();

        if (tarjetas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.credit_card_off_outlined,
                    size: 56, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'No hay tarjetas temporales',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Crea tarjetas desde la pestaña Direcciones',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tarjetas.length,
          itemBuilder: (context, index) {
            final doc = tarjetas[index];
            final data = (doc.data() as Map<String, dynamic>?) ?? {};
            final nombre = (data['nombre'] as String?) ?? doc.id;
            final territorioOrigen =
                (data['territorio_origen_nombre'] as String?) ?? '';
            final enviadoNombre = (data['enviado_nombre'] as String?) ?? '';
            final asignadoA = (data['asignado_a'] as String?) ?? '';
            final yaEnviada = enviadoNombre.isNotEmpty;
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
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(
                    color: yaEnviada ? Colors.green : const Color(0xFF4A148C),
                    width: 4,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (yaEnviada
                                    ? Colors.green
                                    : const Color(0xFF4A148C))
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            yaEnviada ? Icons.outgoing_mail : Icons.credit_card,
                            color: yaEnviada
                                ? Colors.green
                                : const Color(0xFF4A148C),
                            size: 18,
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
                                  fontSize: 14,
                                  color: Color(0xFF263238),
                                ),
                              ),
                              if (territorioOrigen.isNotEmpty)
                                Text(
                                  'Origen: $territorioOrigen',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        // Contador de direcciones
                        FutureBuilder<QuerySnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('direcciones_globales')
                              .where('tarjeta_id', isEqualTo: doc.id)
                              .get(),
                          builder: (context, dirSnap) {
                            final count = dirSnap.data?.docs.length ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count dir.',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    // Badge enviado
                    if (yaEnviada) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.shade200, width: 1),
                        ),
                        child: Text(
                          'Enviada a: $enviadoNombre${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.green.shade800),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _enviarTarjetaTemporal(doc.id, nombre),
                            icon: Icon(
                              yaEnviada ? Icons.refresh : Icons.send,
                              size: 15,
                            ),
                            label: Text(
                              yaEnviada ? 'Reenviar' : 'Enviar',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: yaEnviada
                                  ? Colors.orange
                                  : const Color(0xFF4A148C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirmar = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Eliminar tarjeta'),
                                  content: Text(
                                      '¿Eliminar "$nombre"? Las direcciones volverán al estado temporal.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmar == true) {
                                await _eliminarTarjetaTemporal(doc.id, doc);
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 15),
                            label: const Text('Eliminar',
                                style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
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
    );
  }

  // ─────────────────────────────────────────────────────────
  // ELIMINAR TARJETA TEMPORAL
  // devuelve las direcciones a estado: temporal
  // ─────────────────────────────────────────────────────────

  Future<void> _eliminarTarjetaTemporal(
      String tarjetaId, DocumentSnapshot tarjetaDoc) async {
    try {
      final db = FirebaseFirestore.instance;
      final data = (tarjetaDoc.data() as Map<String, dynamic>?) ?? {};
      final territorioOrigenId =
          (data['territorio_origen_id'] as String?) ?? '';

      // Recuperar direcciones de esta tarjeta temporal
      final dirsSnap = await db
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();

      final batch = db.batch();

      // Restaurar direcciones a estado temporal con tarjeta_id_origen
      for (final dir in dirsSnap.docs) {
        final d = (dir.data() as Map<String, dynamic>?) ?? {};
        final tarjetaIdOrigen = (d['tarjeta_id_origen'] as String?) ?? '';

        batch.update(dir.reference, {
          'tarjeta_id': tarjetaIdOrigen,
          'tarjeta_id_origen': null,
          'territorio_id': territorioOrigenId,
          'estado': 'temporal',
          'estado_predicacion': 'temporal',
        });
      }

      // Eliminar tarjeta temporal
      batch.delete(tarjetaDoc.reference);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarjeta eliminada — direcciones restauradas'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
