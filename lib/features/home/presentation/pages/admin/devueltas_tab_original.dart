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
  // HELPERS
  // ─────────────────────────────────────────────────────────

  int _diasDesdeRemocion(Timestamp? removidaEn) {
    if (removidaEn == null) return 0;
    return DateTime.now().difference(removidaEn.toDate()).inDays;
  }

  Color _colorPorDias(int dias) {
    if (dias >= 60) return Colors.red;
    if (dias >= 30) return Colors.orange;
    return const Color(0xFF1B5E20);
  }

  String _labelPorDias(int dias) {
    if (dias >= 60) return '⚠️ Eliminar';
    if (dias >= 30) return '🔍 Verificar';
    return '${dias}d';
  }

  // ─────────────────────────────────────────────────────────
  // VERIFICAR DIRECCIÓN
  // ─────────────────────────────────────────────────────────

  Future<void> _verificarDireccion(DocumentSnapshot doc) async {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final calle = (data['calle'] as String?) ?? '';
    final notaCtrl = TextEditingController();

    final resultado = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Verificar dirección'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                calle,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            const Text('¿Resultado de la verificación?',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: notaCtrl,
              decoration: InputDecoration(
                hintText: 'Ej: Se verificó, sigue sin hispanos...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(c, 'sin_cambio'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange)),
            child: const Text('Sin cambio'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, 'restaurar'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (resultado == null) return;

    try {
      final verificadoPor = widget.usuarioData['nombre'] ?? 'Admin';

      await doc.reference.update({
        'verificaciones': FieldValue.arrayUnion([
          {
            'fecha': Timestamp.now(),
            'verificado_por': verificadoPor,
            'resultado': resultado,
            'nota': notaCtrl.text.trim(),
          }
        ]),
        'ultima_verificacion': FieldValue.serverTimestamp(),
        'estado_revision':
            resultado == 'restaurar' ? 'restaurada' : 'verificada',
      });

      if (resultado == 'restaurar') {
        await _restaurarDireccion(doc, nota: notaCtrl.text.trim());
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verificación registrada — sin cambios'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // RESTAURAR DIRECCIÓN
  // ─────────────────────────────────────────────────────────

  Future<void> _restaurarDireccion(DocumentSnapshot doc,
      {String nota = ''}) async {
    try {
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final docIdOriginal = (data['doc_id_original'] as String?) ?? doc.id;
      final tarjetaIdOrigen = (data['tarjeta_id_origen'] as String?) ?? '';
      final territorioId = (data['territorio_id'] as String?) ?? '';
      final territorioNombre = (data['territorio_nombre'] as String?) ?? '';
      final mes =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

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
          'barrio':
              territorioNombre.isNotEmpty ? territorioNombre : territorioId,
          'estado': 'activa',
          'estado_predicacion': 'pendiente',
          'predicado': false,
          'visitado': false,
          'es_hispano': true,
          'asignado_a': null,
          'created_at': FieldValue.serverTimestamp(),
          'restaurada_en': FieldValue.serverTimestamp(),
          'restaurada_por': widget.usuarioData['nombre'] ?? '',
          'nota_restauracion': nota,
        },
      );

      // 2. Guardar en estadísticas
      batch.set(
        db.collection('estadisticas').doc('removidas_$mes'),
        {
          'mes': mes,
          'restauradas': FieldValue.increment(1),
          'ultima_actualizacion': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 3. Guardar notificación en Firestore para admins
      batch.set(
        db.collection('notificaciones').doc(),
        {
          'titulo': '✅ Dirección restaurada',
          'cuerpo':
              '${data['calle']} fue restaurada al territorio $territorioNombre',
          'tipo': 'restauracion',
          'leida': false,
          'created_at': FieldValue.serverTimestamp(),
          'para_roles': ['es_admin', 'es_admin_territorios'],
        },
      );

      // 4. Eliminar de direcciones_removidas
      batch.delete(doc.reference);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Dirección restaurada a $tarjetaIdOrigen'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al restaurar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // ELIMINAR PERMANENTE
  // ─────────────────────────────────────────────────────────

  Future<void> _eliminarPermanente(DocumentSnapshot doc) async {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final calle = (data['calle'] as String?) ?? 'esta dirección';
    final mes =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar permanentemente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(calle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Esta acción NO se puede deshacer.\nLa dirección desaparecerá para siempre.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.red),
            ),
          ],
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
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // Guardar en estadísticas
      batch.set(
        db.collection('estadisticas').doc('removidas_$mes'),
        {
          'mes': mes,
          'eliminadas_permanente': FieldValue.increment(1),
          'ultima_actualizacion': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Eliminar
      batch.delete(doc.reference);

      await batch.commit();

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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // VERIFICAR ALERTAS AUTOMÁTICAS
  // ─────────────────────────────────────────────────────────

  Future<void> _verificarAlertas(List<DocumentSnapshot> docs) async {
    final db = FirebaseFirestore.instance;
    for (final doc in docs) {
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final removidaEn = data['removida_en'] as Timestamp?;
      final alerta30 = (data['alerta_30_enviada'] as bool?) ?? false;
      final alerta60 = (data['alerta_60_enviada'] as bool?) ?? false;
      final dias = _diasDesdeRemocion(removidaEn);
      final calle = (data['calle'] as String?) ?? '';

      if (dias >= 60 && !alerta60) {
        await db.collection('notificaciones').add({
          'titulo': '🚨 Dirección para eliminar',
          'cuerpo': '$calle lleva 60 días removida. Verificar urgente.',
          'tipo': 'alerta_60',
          'leida': false,
          'created_at': FieldValue.serverTimestamp(),
          'para_roles': ['es_admin', 'es_admin_territorios'],
        });
        await doc.reference.update({'alerta_60_enviada': true});
      } else if (dias >= 30 && !alerta30) {
        await db.collection('notificaciones').add({
          'titulo': '🔍 Verificar dirección removida',
          'cuerpo': '$calle lleva 30 días removida. ¿Sigue sin hispanos?',
          'tipo': 'alerta_30',
          'leida': false,
          'created_at': FieldValue.serverTimestamp(),
          'para_roles': ['es_admin', 'es_admin_territorios'],
        });
        await doc.reference.update({'alerta_30_enviada': true});
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
          .orderBy('removida_en', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _verificarAlertas(docs);
          });
        }

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
                  'Las direcciones "no hispanohablantes"\naparecerán aquí',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        // Contadores por urgencia
        final urgentes = docs.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          return _diasDesdeRemocion(data['removida_en'] as Timestamp?) >= 60;
        }).length;
        final verificar = docs.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          final dias = _diasDesdeRemocion(data['removida_en'] as Timestamp?);
          return dias >= 30 && dias < 60;
        }).length;

        // Agrupar por territorio
        final Map<String, List<DocumentSnapshot>> porTerritorio = {};
        for (final doc in docs) {
          final data = (doc.data() as Map<String, dynamic>?) ?? {};
          final terNombre =
              (data['territorio_nombre'] as String?)?.isNotEmpty == true
                  ? data['territorio_nombre'] as String
                  : (data['territorio_id'] as String?) ?? 'Sin territorio';
          porTerritorio.putIfAbsent(terNombre, () => []).add(doc);
        }

        return Column(
          children: [
            // ── Resumen ─────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: urgentes > 0
                    ? Colors.red.shade50
                    : verificar > 0
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: urgentes > 0
                      ? Colors.red.shade200
                      : verificar > 0
                          ? Colors.orange.shade200
                          : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    urgentes > 0
                        ? Icons.warning_amber
                        : verificar > 0
                            ? Icons.search
                            : Icons.check_circle_outline,
                    color: urgentes > 0
                        ? Colors.red
                        : verificar > 0
                            ? Colors.orange
                            : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${docs.length} direcci${docs.length == 1 ? 'ón removida' : 'ones removidas'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: urgentes > 0
                                ? Colors.red.shade800
                                : verificar > 0
                                    ? Colors.orange.shade800
                                    : Colors.green.shade800,
                          ),
                        ),
                        if (urgentes > 0 || verificar > 0)
                          Text(
                            '${urgentes > 0 ? '$urgentes para eliminar  ' : ''}${verificar > 0 ? '$verificar para verificar' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: urgentes > 0
                                  ? Colors.red.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (urgentes > 0) _alertaBadge('$urgentes', Colors.red),
                  if (verificar > 0) ...[
                    const SizedBox(width: 6),
                    _alertaBadge('$verificar', Colors.orange),
                  ],
                ],
              ),
            ),

            // ── Lista ────────────────────────────────────────
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
                            Text('${dirs.length} dir.',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500])),
                          ],
                        ),
                      ),
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
                        final dias = _diasDesdeRemocion(removidaEn);
                        final color = _colorPorDias(dias);
                        final label = _labelPorDias(dias);
                        final verificaciones =
                            (data['verificaciones'] as List?) ?? [];

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
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Barra de color superior
                              Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Cabecera
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
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: color.withOpacity(0.4),
                                                width: 1),
                                          ),
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (tarjetaOrigen.isNotEmpty)
                                          _infoBadge(Icons.credit_card,
                                              tarjetaOrigen, Colors.grey),
                                        if (removidaPor.isNotEmpty)
                                          _infoBadge(Icons.person, removidaPor,
                                              Colors.orange),
                                        if (fechaRemovida.isNotEmpty)
                                          _infoBadge(Icons.calendar_today,
                                              fechaRemovida, Colors.grey),
                                        if (verificaciones.isNotEmpty)
                                          _infoBadge(
                                              Icons.history,
                                              '${verificaciones.length} verif.',
                                              Colors.blue),
                                      ],
                                    ),

                                    // Historial
                                    if (verificaciones.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Historial:',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue)),
                                            ...verificaciones.take(2).map((v) {
                                              final vMap =
                                                  v as Map<String, dynamic>;
                                              final vFecha = vMap['fecha']
                                                      is Timestamp
                                                  ? (vMap['fecha'] as Timestamp)
                                                      .toDate()
                                                  : DateTime.now();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2),
                                                child: Text(
                                                  '${vFecha.day}/${vFecha.month} · ${vMap['verificado_por']} · ${vMap['resultado']}${(vMap['nota'] as String?)?.isNotEmpty == true ? ' — ${vMap['nota']}' : ''}',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.blue),
                                                ),
                                              );
                                            }).toList(),
                                          ],
                                        ),
                                      ),

                                    const SizedBox(height: 12),

                                    // Botones
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _verificarDireccion(doc),
                                            icon: Icon(
                                              dias >= 30
                                                  ? Icons.search
                                                  : Icons.check_circle_outline,
                                              size: 15,
                                            ),
                                            label: Text(
                                              dias >= 30
                                                  ? 'Verificar'
                                                  : 'Revisar',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: color,
                                              side: BorderSide(color: color),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _restaurarDireccion(doc),
                                            icon: const Icon(Icons.restore,
                                                size: 15),
                                            label: const Text('Restaurar',
                                                style: TextStyle(fontSize: 12)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFF1B5E20),
                                              side: const BorderSide(
                                                  color: Color(0xFF1B5E20)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: () =>
                                              _eliminarPermanente(doc),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            side: const BorderSide(
                                                color: Colors.red),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                          ),
                                          child: const Icon(
                                              Icons.delete_forever,
                                              size: 16),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  Widget _alertaBadge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
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
