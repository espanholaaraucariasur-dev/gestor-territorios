import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ComunicacionTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const ComunicacionTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<ComunicacionTab> createState() => _ComunicacionTabState();
}

class _ComunicacionTabState extends State<ComunicacionTab> {
  final TextEditingController _anuncioCtrl = TextEditingController();
  bool _enviandoAnuncio = false;

  static const Color _verde = Color(0xFF1B5E20);
  static const Color _naranja = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _verificarCampanasVencidas();
  }

  @override
  void dispose() {
    _anuncioCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // VERIFICAR CAMPAÑAS VENCIDAS
  // ─────────────────────────────────────────────────────────

  Future<void> _verificarCampanasVencidas() async {
    final db = FirebaseFirestore.instance;
    final ahora = DateTime.now();

    for (final slot in ['campana_1', 'campana_2']) {
      final doc = await db.collection('configuracion').doc(slot).get();
      if (!doc.exists) continue;
      final data = doc.data() ?? {};
      final activa = (data['activa'] as bool?) ?? false;
      if (!activa) continue;

      final fechaFin = (data['fecha_fin'] as Timestamp?)?.toDate();
      if (fechaFin != null && ahora.isAfter(fechaFin)) {
        await _cerrarCampana(slot, data, autoCierre: true);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // CERRAR CAMPAÑA (manual o automática)
  // ─────────────────────────────────────────────────────────

  Future<void> _cerrarCampana(
    String slot,
    Map<String, dynamic> campanaData, {
    bool autoCierre = false,
  }) async {
    final db = FirebaseFirestore.instance;
    final nombre = (campanaData['nombre'] as String?) ?? slot;
    final mensajePendiente = (campanaData['mensaje_pendiente'] as String?) ??
        'Falta entregar invitación';
    final mes =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

    try {
      // 1. Obtener direcciones de la carpeta de campaña
      final carpetaSnap = await db
          .collection('territorios')
          .doc('campanas')
          .collection(nombre)
          .get();

      int totalDejadas = 0;
      int totalFaltantes = 0;
      final Map<String, int> porTerritorio = {};

      // 2. Mover faltantes a temporales y contar
      for (final dirDoc in carpetaSnap.docs) {
        final data = (dirDoc.data() as Map<String, dynamic>?) ?? {};
        final estadoCampana =
            (data['estado_campana'] as String?) ?? 'pendiente';
        final territorioOrigen = (data['territorio_origen'] as String?) ?? '';

        if (estadoCampana == 'completada') {
          totalDejadas++;
        } else {
          totalFaltantes++;
          // Mover a temporales con mensaje de campaña
          await db.collection('direcciones_globales').add({
            'calle': data['calle'] ?? '',
            'complemento': data['complemento'] ?? '',
            'direccion_normalizada': data['direccion_normalizada'] ?? '',
            'territorio_id': data['territorio_origen_id'] ?? '',
            'territorio_nombre': territorioOrigen,
            'tarjeta_id': data['tarjeta_origen'] ?? '',
            'barrio': territorioOrigen,
            'estado': 'temporal',
            'estado_predicacion': 'temporal',
            'motivo_temporal': mensajePendiente,
            'fecha_temporal': FieldValue.serverTimestamp(),
            'origen_campana': nombre,
          });
        }

        // Contar por territorio
        porTerritorio[territorioOrigen] =
            (porTerritorio[territorioOrigen] ?? 0) + 1;
      }

      // 3. Guardar estadísticas
      await db.collection('estadisticas').doc('campana_${nombre}_$mes').set({
        'nombre_campana': nombre,
        'mes': mes,
        'total_invitaciones_dejadas': totalDejadas,
        'total_faltantes': totalFaltantes,
        'total_direcciones': carpetaSnap.docs.length,
        'por_territorio': porTerritorio,
        'cerrada_en': FieldValue.serverTimestamp(),
        'cierre_automatico': autoCierre,
      }, SetOptions(merge: true));

      // 4. Eliminar carpeta de campaña (borrar docs uno a uno)
      final batch = db.batch();
      for (final dirDoc in carpetaSnap.docs) {
        batch.delete(dirDoc.reference);
      }
      await batch.commit();

      // 5. Desactivar campaña en configuración
      await db.collection('configuracion').doc(slot).update({
        'activa': false,
        'cerrada_en': FieldValue.serverTimestamp(),
      });

      if (mounted && !autoCierre) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Campaña "$nombre" cerrada — $totalFaltantes direcciones a temporales'),
            backgroundColor: _verde,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cerrando campaña: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // CREAR/EDITAR CAMPAÑA
  // ─────────────────────────────────────────────────────────

  Future<void> _mostrarDialogoCampana(String slot,
      {Map<String, dynamic>? datos}) async {
    final nombreCtrl = TextEditingController(text: datos?['nombre'] ?? '');
    final mensajeCtrl = TextEditingController(
        text: datos?['mensaje_pendiente'] ??
            'Falta entregar invitación de campaña');
    DateTime fechaInicio = datos?['fecha_inicio'] != null
        ? (datos!['fecha_inicio'] as Timestamp).toDate()
        : DateTime.now();
    DateTime fechaFin = datos?['fecha_fin'] != null
        ? (datos!['fecha_fin'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 7));

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.campaign, color: _naranja),
              const SizedBox(width: 8),
              Text(datos == null ? 'Nueva Campaña' : 'Editar Campaña'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre
                const Text('Nombre de la campaña',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: nombreCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ej: Memorial 2026',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Mensaje personalizable
                const Text('Mensaje para direcciones sin invitación',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: mensajeCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ej: Falta entregar invitación',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Fecha inicio
                const Text('Fecha de inicio',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaInicio,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDlg(() => fechaInicio = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Fecha fin
                const Text('Fecha de fin (cierre automático)',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaFin,
                      firstDate: fechaInicio,
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDlg(() => fechaFin = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange.shade50,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_busy,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          '${fechaFin.difference(fechaInicio).inDays} días',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty) return;
                await FirebaseFirestore.instance
                    .collection('configuracion')
                    .doc(slot)
                    .set({
                  'activa': true,
                  'nombre': nombre,
                  'mensaje_pendiente': mensajeCtrl.text.trim(),
                  'fecha_inicio': Timestamp.fromDate(fechaInicio),
                  'fecha_fin': Timestamp.fromDate(fechaFin),
                  'creada_por': widget.usuarioData['nombre'] ?? '',
                  'created_at': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (context.mounted) Navigator.pop(c);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _naranja),
              child: const Text('Activar campaña'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ANUNCIO GENERAL
  // ─────────────────────────────────────────────────────────

  Future<void> _enviarAnuncio() async {
    final texto = _anuncioCtrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviandoAnuncio = true);
    try {
      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('anuncio_general')
          .set({
        'activo': true,
        'mensaje': texto,
        'enviado_en': FieldValue.serverTimestamp(),
        'enviado_por': widget.usuarioData['nombre'] ?? '',
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('notificaciones').add({
        'titulo': '📢 Anuncio de la congregación',
        'cuerpo': texto,
        'tipo': 'anuncio_general',
        'leida': false,
        'created_at': FieldValue.serverTimestamp(),
        'para_todos': true,
      });

      _anuncioCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Anuncio enviado'),
            backgroundColor: _verde,
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
    setState(() => _enviandoAnuncio = false);
  }

  Future<void> _limpiarAnuncio() async {
    await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('anuncio_general')
        .set({'activo': false, 'mensaje': ''}, SetOptions(merge: true));
  }

  // ─────────────────────────────────────────────────────────
  // APROBAR SOLICITUD DE DIRECCIÓN
  // ─────────────────────────────────────────────────────────

  Future<void> _aprobarSolicitud(DocumentSnapshot solicitudDoc) async {
    final data = (solicitudDoc.data() as Map<String, dynamic>?) ?? {};
    final calle = (data['direccion_original'] as String?) ?? '';
    final complemento = (data['complemento'] as String?) ?? '';
    final detalles = (data['detalles'] as String?) ?? '';
    final esCondominio = (data['es_condominio'] as bool?) ?? false;
    final unidades = (data['unidades_condominio'] as List?) ?? [];

    final territoriosSnap =
        await FirebaseFirestore.instance.collection('territorios').get();

    if (!mounted) return;

    String? territorioIdSel;
    String? territorioNombreSel;
    String? tarjetaIdSel;

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Agregar dirección a tarjeta'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Selecciona territorio:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 6),
                  ...territoriosSnap.docs
                      .where((d) => d.id != 'temporales' && d.id != 'campanas')
                      .map((terDoc) {
                    final terData =
                        (terDoc.data() as Map<String, dynamic>?) ?? {};
                    final terNombre =
                        (terData['nombre'] as String?) ?? terDoc.id;
                    final sel = territorioIdSel == terDoc.id;
                    return GestureDetector(
                      onTap: () => setDlg(() {
                        territorioIdSel = terDoc.id;
                        territorioNombreSel = terNombre;
                        tarjetaIdSel = null;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? _verde.withOpacity(0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? _verde : Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.map,
                                size: 16, color: sel ? _verde : Colors.grey),
                            const SizedBox(width: 8),
                            Text(terNombre,
                                style: TextStyle(
                                    fontWeight: sel
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: sel ? _verde : null)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  if (territorioIdSel != null) ...[
                    const SizedBox(height: 12),
                    const Text('Selecciona tarjeta:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 6),
                    FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('territorios')
                          .doc(territorioIdSel)
                          .collection('tarjetas')
                          .get(),
                      builder: (context, tarjSnap) {
                        if (!tarjSnap.hasData) {
                          return const CircularProgressIndicator();
                        }
                        return Column(
                          children: tarjSnap.data!.docs.map((tarjDoc) {
                            final sel = tarjetaIdSel == tarjDoc.id;
                            return GestureDetector(
                              onTap: () =>
                                  setDlg(() => tarjetaIdSel = tarjDoc.id),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? Colors.blue.withOpacity(0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: sel
                                          ? Colors.blue
                                          : Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.credit_card,
                                        size: 16,
                                        color: sel ? Colors.blue : Colors.grey),
                                    const SizedBox(width: 8),
                                    Text(tarjDoc.id,
                                        style: TextStyle(
                                            fontWeight: sel
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: sel ? Colors.blue : null)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: territorioIdSel != null && tarjetaIdSel != null
                  ? () => Navigator.pop(c, true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _verde),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    if (territorioIdSel == null || tarjetaIdSel == null) return;

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      String _norm(String s) {
        var t = s.toLowerCase();
        t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
        t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
        return t;
      }

      if (esCondominio && unidades.isNotEmpty) {
        for (final u in unidades) {
          batch.set(db.collection('direcciones_globales').doc(), {
            'calle': calle,
            'complemento': u.toString(),
            'direccion_normalizada': _norm('$calle $u'),
            'territorio_id': territorioIdSel,
            'territorio_nombre': territorioNombreSel ?? '',
            'tarjeta_id': tarjetaIdSel,
            'barrio': territorioNombreSel ?? '',
            'estado': 'activa',
            'estado_predicacion': 'pendiente',
            'predicado': false,
            'es_hispano': true,
            'es_condominio': true,
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      } else {
        batch.set(db.collection('direcciones_globales').doc(), {
          'calle': calle,
          'complemento': complemento,
          'direccion_normalizada': _norm('$calle $complemento'),
          'territorio_id': territorioIdSel,
          'territorio_nombre': territorioNombreSel ?? '',
          'tarjeta_id': tarjetaIdSel,
          'barrio': territorioNombreSel ?? '',
          'estado': 'activa',
          'estado_predicacion': 'pendiente',
          'predicado': false,
          'es_hispano': true,
          'informacion': detalles,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      batch.update(solicitudDoc.reference, {
        'estado': 'aprobada',
        'aprobada_por': widget.usuarioData['nombre'] ?? '',
        'aprobada_en': FieldValue.serverTimestamp(),
        'territorio_asignado': territorioNombreSel,
        'tarjeta_asignada': tarjetaIdSel,
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(esCondominio
                ? '✅ ${unidades.length} unidades agregadas a $tarjetaIdSel'
                : '✅ Dirección agregada a $tarjetaIdSel'),
            backgroundColor: _verde,
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

  Future<void> _rechazarSolicitud(DocumentSnapshot doc) async {
    await doc.reference.update({
      'estado': 'rechazada',
      'rechazada_por': widget.usuarioData['nombre'] ?? '',
      'rechazada_en': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Campañas Especiales ──────────────────────────
          _seccionTitulo('CAMPAÑAS ESPECIALES'),
          const SizedBox(height: 10),
          _buildSlotCampana('campana_1', 'Campaña 1'),
          const SizedBox(height: 10),
          _buildSlotCampana('campana_2', 'Campaña 2'),

          const SizedBox(height: 20),

          // ── Progreso global de campañas ──────────────────
          _buildProgresoGlobalCampanas(),

          const SizedBox(height: 20),

          // ── Anuncio General ──────────────────────────────
          _seccionTitulo('ANUNCIO GENERAL'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('configuracion')
                      .doc('anuncio_general')
                      .snapshots(),
                  builder: (context, snap) {
                    final data =
                        (snap.data?.data() as Map<String, dynamic>?) ?? {};
                    final activo = (data['activo'] as bool?) ?? false;
                    final msg = (data['mensaje'] as String?) ?? '';
                    if (!activo || msg.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF1565C0).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Color(0xFF1565C0), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(msg,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF1565C0)))),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 14, color: Color(0xFF1565C0)),
                            onPressed: _limpiarAnuncio,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                TextField(
                  controller: _anuncioCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Mensaje para todos los usuarios...',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _enviandoAnuncio ? null : _enviarAnuncio,
                    icon: _enviandoAnuncio
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 16),
                    label: Text(
                        _enviandoAnuncio ? 'Enviando...' : 'Enviar anuncio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Solicitudes de direcciones ───────────────────
          _seccionTitulo('SOLICITUDES DE DIRECCIONES'),
          const SizedBox(height: 10),
          _buildSolicitudes(),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // WIDGET: SLOT DE CAMPAÑA
  // ─────────────────────────────────────────────────────────

  Widget _buildSlotCampana(String slot, String slotLabel) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('configuracion')
          .doc(slot)
          .snapshots(),
      builder: (context, snap) {
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final activa = (data['activa'] as bool?) ?? false;
        final nombre = (data['nombre'] as String?) ?? '';
        final mensaje = (data['mensaje_pendiente'] as String?) ?? '';
        final fechaInicio = (data['fecha_inicio'] as Timestamp?)?.toDate();
        final fechaFin = (data['fecha_fin'] as Timestamp?)?.toDate();
        final ahora = DateTime.now();
        final diasRestantes =
            fechaFin != null ? fechaFin.difference(ahora).inDays : null;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: activa ? _naranja.withOpacity(0.4) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: activa
                          ? _naranja.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.campaign,
                        color: activa ? _naranja : Colors.grey, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activa && nombre.isNotEmpty ? nombre : slotLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: activa ? _naranja : Colors.grey[700],
                          ),
                        ),
                        if (activa && diasRestantes != null)
                          Text(
                            diasRestantes > 0
                                ? '$diasRestantes días restantes'
                                : 'Venció hoy',
                            style: TextStyle(
                              fontSize: 11,
                              color: diasRestantes <= 3
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                          )
                        else
                          Text(
                            activa ? 'Activa' : 'Sin campaña',
                            style: TextStyle(
                              fontSize: 11,
                              color: activa ? _naranja : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!activa)
                    ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoCampana(slot),
                      icon: const Icon(Icons.add, size: 14),
                      label:
                          const Text('Crear', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _naranja,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: Colors.orange),
                          onPressed: () =>
                              _mostrarDialogoCampana(slot, datos: data),
                          tooltip: 'Editar',
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle_outlined,
                              size: 18, color: Colors.red),
                          onPressed: () => _cerrarCampana(slot, data),
                          tooltip: 'Cerrar campaña',
                        ),
                      ],
                    ),
                ],
              ),
              if (activa) ...[
                const SizedBox(height: 10),
                // Fechas
                Row(
                  children: [
                    _fechaBadge(
                      Icons.play_circle_outline,
                      fechaInicio != null
                          ? '${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year}'
                          : '-',
                      Colors.green,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward,
                        size: 12, color: Colors.grey),
                    const SizedBox(width: 8),
                    _fechaBadge(
                      Icons.stop_circle_outlined,
                      fechaFin != null
                          ? '${fechaFin.day}/${fechaFin.month}/${fechaFin.year}'
                          : '-',
                      Colors.red,
                    ),
                  ],
                ),
                if (mensaje.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.message_outlined,
                            size: 12, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Sin invitación: "$mensaje"',
                            style: TextStyle(
                                fontSize: 11, color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _fechaBadge(IconData icon, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildProgresoGlobalCampanas() {
    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance
            .collection('configuracion')
            .doc('campana_1')
            .get(),
        FirebaseFirestore.instance
            .collection('configuracion')
            .doc('campana_2')
            .get(),
      ]),
      builder: (context, campSnap) {
        if (!campSnap.hasData) return const SizedBox.shrink();

        final campanas = campSnap.data!.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          return (data['activa'] as bool?) == true;
        }).toList();

        if (campanas.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seccionTitulo('PROGRESO DE CAMPAÑAS'),
            const SizedBox(height: 10),
            ...campanas.map((campDoc) {
              final data = (campDoc.data() as Map<String, dynamic>?) ?? {};
              final nombreOriginal = (data['nombre'] as String?) ?? 'Campaña';
              final nombreCampo =
                  nombreOriginal.replaceAll(' ', '_').toLowerCase();

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .snapshots(),
                builder: (context, dirSnap) {
                  final dirs = dirSnap.data?.docs ?? [];
                  final total = dirs.length;
                  final conInvitacion = dirs.where((d) {
                    final dd = (d.data() as Map<String, dynamic>?) ?? {};
                    return dd['campana_invitacion_$nombreCampo'] == true;
                  }).length;
                  final pct = total > 0
                      ? (conInvitacion / total * 100).clamp(0, 100).toDouble()
                      : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.campaign,
                                color: Color(0xFFE65100), size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(nombreOriginal,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ),
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: pct >= 80
                                    ? _verde
                                    : pct >= 50
                                        ? Colors.orange
                                        : _naranja,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              pct >= 80
                                  ? _verde
                                  : pct >= 50
                                      ? Colors.orange
                                      : _naranja,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$conInvitacion de $total direcciones con invitación entregada',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // WIDGET: SOLICITUDES
  // ─────────────────────────────────────────────────────────

  Widget _buildSolicitudes() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .where('estado', isEqualTo: 'pendiente')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 36, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text('Sin solicitudes pendientes',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = (doc.data() as Map<String, dynamic>?) ?? {};
            final calle = (data['direccion_original'] as String?) ?? '';
            final complemento = (data['complemento'] as String?) ?? '';
            final detalles = (data['detalles'] as String?) ?? '';
            final solicitante = (data['solicitante_email'] as String?) ?? '';
            final esCondominio = (data['es_condominio'] as bool?) ?? false;
            final unidades = (data['unidades_condominio'] as List?) ?? [];
            final createdAt = data['created_at'] as Timestamp?;
            String fecha = '';
            if (createdAt != null) {
              final dt = createdAt.toDate();
              fecha =
                  '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: esCondominio ? Colors.blue : _verde,
                    width: 4,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          esCondominio ? Icons.apartment : Icons.location_on,
                          color: esCondominio ? Colors.blue : _verde,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        if (esCondominio)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '🏢 ${unidades.length} unid.',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.blue),
                            ),
                          ),
                      ],
                    ),
                    if (detalles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(detalles,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person, size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(solicitante,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500])),
                        ),
                        Text(fecha,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _aprobarSolicitud(doc),
                            icon: const Icon(Icons.add_location_alt, size: 14),
                            label: const Text('Agregar',
                                style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _verde,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _rechazarSolicitud(doc),
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text('Rechazar',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
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
    );
  }

  Widget _seccionTitulo(String titulo) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: _verde,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }
}
