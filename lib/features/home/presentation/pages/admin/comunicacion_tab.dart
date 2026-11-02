import 'package:flutter/material.dart';
import '../../../../../core/services/notificacion_service.dart';
import '../../../../../core/utils/campanas_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/services/gemini_service.dart';
import '../../../../../core/services/historial_temporales_service.dart';
import '../../../../../core/l10n/translation_service.dart';

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
  final TextEditingController _codigoAccesoCtrl = TextEditingController();
  final TextEditingController _mensajeMotivacionalCtrl = TextEditingController();
  final TextEditingController _autoReturnHorasCtrl =
      TextEditingController(text: '2');
  final TextEditingController _autoReturnMinutosCtrl =
      TextEditingController(text: '0');
  final TextEditingController _autoReturnAvisoCtrl =
      TextEditingController(text: '10');
  bool _autoReturnActivo = true;
  bool _guardandoAutoReturn = false;
  bool _enviandoAnuncio = false;
  bool _guardandoCodigo = false;
  bool _mensajesMotivacionalesExpandido = false;

  static const Color _verde = Color(0xFF1B5E20);
  static const Color _naranja = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _verificarCampanasVencidas();
    _cargarConfigAutoReturn();
  }

  @override
  void dispose() {
    _anuncioCtrl.dispose();
    _codigoAccesoCtrl.dispose();
    _mensajeMotivacionalCtrl.dispose();
    _autoReturnHorasCtrl.dispose();
    _autoReturnMinutosCtrl.dispose();
    _autoReturnAvisoCtrl.dispose();
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
        'Falta entregar material de campaña';
    final mes =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

    try {
      // 1. Obtener direcciones de la carpeta de campaña
      // El nombre se convierte a ID de colección válido con el MISMO helper que
      // usa el publicador al guardar, para no leer una carpeta que no existe.
      final campId = CampanasUtils.idColeccionCampana(nombre);
      if (campId.isEmpty) return;
      final carpetaSnap = await db
          .collection('territorios')
          .doc('campanas')
          .collection(campId)
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
          final ref = await db.collection('direcciones_globales').add({
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
            'reportado_por': widget.usuarioData['nombre'] ?? '',
            'reportado_por_email': widget.usuarioData['email'] ?? '',
          });
          await registrarMovimientoTemporal(
            tipo: 'entrada',
            direccionId: ref.id,
            territorioOrigenId: data['territorio_origen_id']?.toString() ?? '',
            territorioOrigenNombre: territorioOrigen,
            calle: data['calle']?.toString(),
            motivo: 'campana_cierre',
            por: widget.usuarioData['nombre']?.toString(),
          );
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
            'Falta entregar material de campaña');
    final etiquetaEntregaCtrl = TextEditingController(
        text: datos?['etiqueta_entrega'] ?? 'material entregado');
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
                const Text('Mensaje para direcciones pendientes',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: mensajeCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ej: Falta entregar folleto / invitación',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Etiqueta de progreso (qué se está entregando/haciendo)
                const Text('Texto de progreso (qué se entrega o hace)',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: etiquetaEntregaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ej: folleto entregado / invitación entregada',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
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
                  'etiqueta_entrega': etiquetaEntregaCtrl.text.trim().isEmpty
                      ? 'material entregado'
                      : etiquetaEntregaCtrl.text.trim(),
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
      // Traducir automáticamente al portugués con Gemini AI
      String textoPT = texto;
      try {
        textoPT = await GeminiService.traducirEsPt(texto);
      } catch (_) {
        // Si falla, continuar con el original
      }

      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('anuncio_general')
          .set({
        'activo': true,
        'texto': texto,
        'texto_pt': textoPT,
        'mensaje': texto,
        'enviado_en': FieldValue.serverTimestamp(),
        'enviado_por': widget.usuarioData['nombre'] ?? '',
      }, SetOptions(merge: true));

      // Anuncio va a todos los usuarios aprobados
      final todosSnap = await FirebaseFirestore.instance
          .collection('usuarios').where('estado', isEqualTo: 'aprobado').get();
      for (final doc in todosSnap.docs) {
        final nombre = (doc.data()['nombre'] as String? ?? '').trim();
        if (nombre.isEmpty) continue;
        await NotificacionService.enviarAUser(
          destinatarioNombre: nombre,
          titulo: '📢 Anuncio de la congregación',
          cuerpo: texto,
          tipo: TipoNotificacion.anuncio,
        );
      }

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
  // DEVOLUCIÓN AUTOMÁTICA
  // ─────────────────────────────────────────────────────────

  Future<void> _cargarConfigAutoReturn() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('devolucion_automatica')
          .get();
      final data = doc.data() ?? {};
      final total = (data['tiempo_limite_minutos'] as int?) ?? 120;
      final aviso = (data['aviso_minutos'] as int?) ?? 10;
      if (!mounted) return;
      setState(() {
        _autoReturnActivo = (data['activo'] as bool?) ?? true;
        _autoReturnHorasCtrl.text = (total ~/ 60).toString();
        _autoReturnMinutosCtrl.text = (total % 60).toString();
        _autoReturnAvisoCtrl.text = aviso.toString();
      });
    } catch (_) {}
  }

  Future<void> _guardarConfigAutoReturn() async {
    final horas = int.tryParse(_autoReturnHorasCtrl.text.trim()) ?? 0;
    final minutos = int.tryParse(_autoReturnMinutosCtrl.text.trim()) ?? 0;
    final aviso = int.tryParse(_autoReturnAvisoCtrl.text.trim()) ?? 10;
    final total = horas * 60 + minutos;
    if (total < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El tiempo límite debe ser de al menos 1 minuto'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _guardandoAutoReturn = true);
    await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('devolucion_automatica')
        .set({
      'activo': _autoReturnActivo,
      'tiempo_limite_minutos': total,
      'aviso_minutos': aviso < 0 ? 0 : aviso,
      'actualizado_en': FieldValue.serverTimestamp(),
      'actualizado_por': widget.usuarioData['nombre'] ?? '',
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => _guardandoAutoReturn = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Tiempo de devolución automática guardado'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildDevolucionAutomatica() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiempo máximo que un publicador puede retener una tarjeta antes '
            'de que el sistema la devuelva automáticamente.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _autoReturnActivo,
            activeColor: const Color(0xFF1B5E20),
            title: const Text('Devolución automática activada',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _autoReturnActivo
                  ? 'Las tarjetas se devuelven solas al vencer el tiempo.'
                  : 'Desactivada: las tarjetas no se devuelven solas.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            onChanged: (v) => setState(() => _autoReturnActivo = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _autoReturnHorasCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Horas',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _autoReturnMinutosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Minutos',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _autoReturnAvisoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Aviso (min antes)',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _guardandoAutoReturn ? null : _guardarConfigAutoReturn,
              icon: _guardandoAutoReturn
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, size: 16),
              label: Text(_guardandoAutoReturn ? 'Guardando...' : 'Guardar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
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
              color: Theme.of(context).cardColor,
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

          // ── Código de acceso ─────────────────────────────
          _seccionTitulo('CÓDIGO DE ACCESO'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Código de 4 dígitos para solicitar acceso a la app.\nCompártelo en el grupo de WhatsApp de la congregación.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('configuracion').doc('codigo_acceso').snapshots(),
                  builder: (context, snap) {
                    final codigoActual = (snap.data?.data() as Map<String, dynamic>?)?['codigo'] as String? ?? '----';
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B5E20).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF1B5E20).withOpacity(0.3)),
                          ),
                          child: Text(
                            codigoActual,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                              letterSpacing: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('Código actual', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codigoAccesoCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Nuevo código (4 dígitos)',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _guardandoCodigo ? null : () async {
                        final codigo = _codigoAccesoCtrl.text.trim();
                        if (codigo.length != 4 || int.tryParse(codigo) == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('El código debe ser de exactamente 4 dígitos'), backgroundColor: Colors.red),
                          );
                          return;
                        }
                        setState(() => _guardandoCodigo = true);
                        await FirebaseFirestore.instance.collection('configuracion').doc('codigo_acceso').set({
                          'codigo': codigo,
                          'actualizado_en': FieldValue.serverTimestamp(),
                        });
                        _codigoAccesoCtrl.clear();
                        setState(() => _guardandoCodigo = false);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Código actualizado'), backgroundColor: Colors.green),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
                      child: _guardandoCodigo
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Devolución automática ────────────────────────
          _seccionTitulo('DEVOLUCIÓN AUTOMÁTICA'),
          const SizedBox(height: 10),
          _buildDevolucionAutomatica(),

          const SizedBox(height: 20),

          // ── Traducción automática ────────────────────────
          _seccionTitulo('TRADUCCIÓN AUTOMÁTICA'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.translate, color: Color(0xFF1B5E20), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gemini AI activo ✅',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      SizedBox(height: 2),
                      Text('Anuncios traducidos automáticamente\nal portugués con Google Gemini AI.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Mensajes Motivacionales ──────────────────────
          _seccionTitulo('MENSAJES MOTIVACIONALES'),
          const SizedBox(height: 6),
          const Text(
            'Se envían 10 min después de que el publicador complete todas sus tarjetas.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          _buildMensajesMotivacionales(),
          const SizedBox(height: 20),

          // ── Sugerencias recibidas ────────────────────────
          _seccionTitulo(context.t('sugerencias_recibidas')),
          const SizedBox(height: 10),
          _buildSugerencias(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SUGERENCIAS RECIBIDAS
  // ─────────────────────────────────────────────────────────

  Widget _buildSugerencias() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sugerencias')
          .orderBy('created_at', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 10),
                Text(
                  context.t('sugerencias_sin_datos'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final texto = (data['texto'] as String?) ?? '';
            final usuario = (data['usuario_nombre'] as String?) ?? '';
            final email = (data['usuario_email'] as String?) ?? '';
            final leida = (data['leida'] as bool?) ?? false;
            final ts = data['created_at'] as Timestamp?;
            final fecha = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month} ${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: leida
                        ? Colors.grey.shade300
                        : const Color(0xFFF9A825),
                    width: 3,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    leida ? Icons.lightbulb_outline : Icons.lightbulb,
                    color: leida
                        ? Colors.grey.shade400
                        : const Color(0xFFF9A825),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texto,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                leida ? FontWeight.normal : FontWeight.w600,
                            color: const Color(0xFF263238),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${usuario.isNotEmpty ? usuario : email}'
                          '${fecha.isNotEmpty ? ' · $fecha' : ''}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      leida ? Icons.mark_email_read_outlined : Icons.drafts_outlined,
                      size: 18,
                      color: leida
                          ? Colors.grey.shade400
                          : const Color(0xFF1B5E20),
                    ),
                    onPressed: () =>
                        doc.reference.update({'leida': !leida}),
                    tooltip: leida ? 'Marcar no leída' : 'Marcar leída',
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMensajesMotivacionales() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo de entrada
          Row(children: [
            Expanded(
              child: TextField(
                controller: _mensajeMotivacionalCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Ej: ¡Excelente trabajo, {nombre}! 🙏',
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              ),
              onPressed: () async {
                final texto = _mensajeMotivacionalCtrl.text.trim();
                if (texto.isEmpty) return;
                try {
                  await FirebaseFirestore.instance
                      .collection('configuracion')
                      .doc('mensajes_motivacionales')
                      .collection('mensajes')
                      .add({
                    'texto': texto,
                    'activo': true,
                    'created_at': FieldValue.serverTimestamp(),
                  });
                  _mensajeMotivacionalCtrl.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Mensaje guardado'),
                        backgroundColor: Color(0xFF1B5E20),
                        duration: Duration(seconds: 2),
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
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Usa {nombre} para incluir el nombre del publicador',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // Lista de mensajes (contraída por defecto para no ocupar tanto espacio)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('configuracion')
                .doc('mensajes_motivacionales')
                .collection('mensajes')
                .orderBy('created_at')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Sin mensajes. Agrega al menos uno.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              }

              final activos = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['activo'] as bool?) ?? true;
              }).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado clicable: resume la lista sin ocupar espacio
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _mensajesMotivacionalesExpandido =
                            !_mensajesMotivacionalesExpandido;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.format_list_bulleted,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${docs.length} mensajes guardados · $activos activos',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(
                            _mensajesMotivacionalesExpandido
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_mensajesMotivacionalesExpandido) ...[
                    const SizedBox(height: 8),
                    ...docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final texto = (d['texto'] as String?) ?? '';
                      final activo = (d['activo'] as bool?) ?? true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: activo
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: activo
                                ? Colors.green.shade200
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              texto,
                              style: TextStyle(
                                fontSize: 12,
                                color: activo ? Colors.black87 : Colors.grey,
                              ),
                            ),
                          ),
                          // Toggle activo/inactivo
                          IconButton(
                            icon: Icon(
                              activo ? Icons.toggle_on : Icons.toggle_off,
                              color: activo
                                  ? const Color(0xFF1B5E20)
                                  : Colors.grey,
                              size: 30,
                            ),
                            onPressed: () =>
                                doc.reference.update({'activo': !activo}),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          // Eliminar
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red, size: 20),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Eliminar mensaje'),
                                  content: Text('"$texto"'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancelar')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await doc.reference.delete();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ]),
                      );
                    }),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

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
            color: Theme.of(context).cardColor,
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
                          icon: const Icon(Icons.close,
                              size: 20, color: Colors.red),
                          onPressed: () async {
                            final confirmar = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(children: [
                                  Icon(Icons.warning_amber, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Cerrar campaña'),
                                ]),
                                content: Text('¿Cerrar la campaña "${data['nombre'] ?? slot}"?\nEsta acción no se puede deshacer.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    child: const Text('Cerrar campaña'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmar == true) _cerrarCampana(slot, data);
                          },
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
                            'Pendiente: "$mensaje"',
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

  // ─────────────────────────────────────────────────────────
  // WIDGET: PROGRESO GLOBAL DE CAMPAÑAS
  // ─────────────────────────────────────────────────────────

  Widget _buildProgresoGlobalCampanas() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('direcciones_globales')
          .snapshots(),
      builder: (context, snap) {
        // Campañas activas
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
                  final nombre = (data['nombre'] as String?) ?? 'Campaña';
                  final etiquetaEntrega =
                      (data['etiqueta_entrega'] as String?)?.trim().isNotEmpty ==
                              true
                          ? (data['etiqueta_entrega'] as String).trim()
                          : 'material entregado';

                  final dirs = snap.data?.docs ?? [];
                  final total = dirs.length;
                  final conInvitacion = dirs.where((d) {
                    final dd = (d.data() as Map<String, dynamic>?) ?? {};
                    return dd['campana_invitacion_$nombre'] == true;
                  }).length;
                  final pct = total > 0
                      ? (conInvitacion / total * 100).clamp(0, 100).toDouble()
                      : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
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
                            Icon(Icons.campaign, color: _naranja, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(nombre,
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
                                        : Colors.red,
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
                          '$conInvitacion de $total direcciones con $etiquetaEntrega',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            );
          },
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
