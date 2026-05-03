import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PublicadorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;
  final bool campanaEspecialActiva;
  final String nombreCampanaEspecial;
  final bool campanaGeneralActiva;
  final String anuncioGeneral;
  final VoidCallback onSolicitarTerritorio; // ✅ nuevo

  const PublicadorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
    required this.campanaEspecialActiva,
    required this.nombreCampanaEspecial,
    required this.campanaGeneralActiva,
    required this.anuncioGeneral,
    required this.onSolicitarTerritorio, // ✅ nuevo
  });

  @override
  State<PublicadorTab> createState() => _PublicadorTabState();
}

class _PublicadorTabState extends State<PublicadorTab> {
  static const List<Color> _tarjetaColores = [
    Color(0xFF1565C0), // azul
    Color(0xFF2E7D32), // verde
    Color(0xFF6A1B9A), // morado
    Color(0xFFE65100), // naranja
    Color(0xFF00695C), // teal
    Color(0xFFC62828), // rojo
    Color(0xFF4527A0), // violeta
    Color(0xFF558B2F), // verde oliva
    Color(0xFF00838F), // cyan
    Color(0xFF4E342E), // café
  ];

  final Map<String, Map<String, String>> _estadosPorTarjeta = {};
  final Map<String, Map<String, String>> _textosPorTarjeta = {};
  final Map<String, Map<String, bool>> _modificadosPorTarjeta = {};
  final Set<String> _tarjetasCompletadas = {};

  // ───────────────────────────────────────────────────────────
  // HELPERS
  // ───────────────────────────────────────────────────────────

  String _normalizarDireccion(String direccion) {
    var texto = direccion.toLowerCase();
    texto = texto.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    texto = texto.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    texto = texto.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    texto = texto.replaceAll('apto', 'apartamento');
    texto = texto.replaceAll('apt', 'apartamento');
    texto = texto.replaceAll('dpto', 'departamento');
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
  }

  Map<String, dynamic> _safeData(QueryDocumentSnapshot doc) {
    try {
      return (doc.data() as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  // ───────────────────────────────────────────────────────────
  // WIDGETS REUTILIZABLES
  // ───────────────────────────────────────────────────────────

  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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

  Widget _miniStat(String title, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            value.toString(),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _alertaBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style:
                        TextStyle(color: color.withOpacity(0.8), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // DEVOLVER TARJETA
  // ───────────────────────────────────────────────────────────

  Future<void> _devolverTarjeta(String territorioId, String tarjetaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'estatus_envio': 'disponible',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarjeta devuelta correctamente'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────
  // WIDGET DIRECCIONES POR TARJETA
  // ───────────────────────────────────────────────────────────

  Widget _buildDireccionesTarjeta(
      String tarjetaId, String territorioId, String tarjetaNombre) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        if (!_estadosPorTarjeta.containsKey(tarjetaId)) {
          _estadosPorTarjeta[tarjetaId] = {};
          _textosPorTarjeta[tarjetaId] = {};
          _modificadosPorTarjeta[tarjetaId] = {};
        }

        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('tarjeta_id', isEqualTo: tarjetaId)
              .where('estado', isNotEqualTo: 'removida')
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sin direcciones pendientes.',
                    style: TextStyle(color: Colors.grey)),
              );
            }

            final direcciones = snapshot.data!.docs;

            if (_estadosPorTarjeta[tarjetaId]!.isEmpty) {
              for (final dir in direcciones) {
                final data = _safeData(dir);
                _estadosPorTarjeta[tarjetaId]![dir.id] =
                    (data['estado_predicacion'] as String?) ?? 'pendiente';
                _textosPorTarjeta[tarjetaId]![dir.id] =
                    (data['motivo_temporal'] as String?) ?? '';
                _modificadosPorTarjeta[tarjetaId]![dir.id] = false;
              }
            }

            return Column(
              children: [
                // ── Lista de direcciones ──────────────────────
                ...direcciones.map((dirDoc) {
                  final data = _safeData(dirDoc);
                  final estadoLocal =
                      _estadosPorTarjeta[tarjetaId]![dirDoc.id] ?? 'pendiente';
                  final otroTexto =
                      _textosPorTarjeta[tarjetaId]![dirDoc.id] ?? '';
                  final calle = (data['calle'] as String?) ?? '';
                  final complemento = (data['complemento'] as String?) ?? '';
                  final direccionCompleta =
                      '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}';

                  // FIX 1: Color de acento según estado
                  Color accentColor = const Color(0xFFB0BEC5);
                  IconData estadoIcon = Icons.radio_button_unchecked;
                  if (estadoLocal == 'completada') {
                    accentColor = const Color(0xFF2E7D32);
                    estadoIcon = Icons.check_circle;
                  } else if (estadoLocal == 'no_predicado') {
                    accentColor = const Color(0xFFE65100);
                    estadoIcon = Icons.hourglass_empty;
                  } else if (estadoLocal == 'no_hispano') {
                    accentColor = const Color(0xFF1565C0);
                    estadoIcon = Icons.public_off;
                  } else if (estadoLocal == 'otro') {
                    accentColor = const Color(0xFF6A1B9A);
                    estadoIcon = Icons.edit_note;
                  }

                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: accentColor.withOpacity(0.25), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.15),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(21, 14, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabecera
                              Row(
                                children: [
                                  Icon(Icons.location_on,
                                      color: accentColor, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      direccionCompleta,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Color(0xFF263238),
                                      ),
                                    ),
                                  ),
                                  if (estadoLocal != 'pendiente')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accentColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Icon(estadoIcon,
                                          size: 16, color: accentColor),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade100),
                              const SizedBox(height: 6),

                              // FIX 2: Opciones limpias sin flechas
                              ...[
                                {
                                  'label': 'Se predicó',
                                  'value': 'completada',
                                  'color': const Color(0xFF2E7D32),
                                  'icon': Icons.check_circle_outline,
                                },
                                {
                                  'label': 'No se predicó',
                                  'value': 'no_predicado',
                                  'color': const Color(0xFFE65100),
                                  'icon': Icons.hourglass_empty,
                                },
                                {
                                  'label': 'No vive hispanohablante',
                                  'value': 'no_hispano',
                                  'color': const Color(0xFF1565C0),
                                  'icon': Icons.public_off,
                                },
                                {
                                  'label': 'Otro (escribir nota)',
                                  'value': 'otro',
                                  'color': const Color(0xFF6A1B9A),
                                  'icon': Icons.edit_note,
                                },
                              ].map((opcion) {
                                final val = opcion['value'] as String;
                                final color = opcion['color'] as Color;
                                final isSelected = estadoLocal == val;

                                return InkWell(
                                  onTap: () => setLocalState(() {
                                    _estadosPorTarjeta[tarjetaId]![dirDoc.id] =
                                        val;
                                    _modificadosPorTarjeta[tarjetaId]![
                                        dirDoc.id] = true;
                                  }),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Radio<String>(
                                          value: val,
                                          groupValue: estadoLocal,
                                          onChanged: (v) => setLocalState(() {
                                            _estadosPorTarjeta[tarjetaId]![
                                                dirDoc.id] = v!;
                                            _modificadosPorTarjeta[tarjetaId]![
                                                dirDoc.id] = true;
                                          }),
                                          activeColor: color,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        Icon(
                                          opcion['icon'] as IconData,
                                          size: 16,
                                          color: isSelected
                                              ? color
                                              : Colors.grey.shade400,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          opcion['label'] as String,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: isSelected
                                                ? color
                                                : const Color(0xFF546E7A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),

                              // Campo texto para "Otro"
                              if (estadoLocal == 'otro')
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 36, top: 6, bottom: 4),
                                  child: TextField(
                                    controller: TextEditingController(
                                        text: otroTexto)
                                      ..selection = TextSelection.fromPosition(
                                        TextPosition(offset: otroTexto.length),
                                      ),
                                    decoration: InputDecoration(
                                      hintText: 'Escribe el motivo o nota...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: Colors.purple.shade200),
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.purple.shade50,
                                    ),
                                    maxLines: 2,
                                    onChanged: (value) => setLocalState(() {
                                      _textosPorTarjeta[tarjetaId]![dirDoc.id] =
                                          value;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 5,
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // ── Botones ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setLocalState(() {
                            for (final dir in direcciones) {
                              final data = _safeData(dir);
                              _estadosPorTarjeta[tarjetaId]![dir.id] =
                                  (data['estado_predicacion'] as String?) ??
                                      'pendiente';
                              _textosPorTarjeta[tarjetaId]![dir.id] =
                                  (data['motivo_temporal'] as String?) ?? '';
                              _modificadosPorTarjeta[tarjetaId]![dir.id] =
                                  false;
                            }
                          }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black54,
                            side: const BorderSide(color: Colors.black26),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async => _confirmarProcesamientoTarjeta(
                            tarjetaId,
                            territorioId,
                            tarjetaNombre,
                            direcciones,
                            context,
                          ),
                          icon:
                              const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Confirmar',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────
  // CONFIRMAR PROCESAMIENTO
  // ───────────────────────────────────────────────────────────

  Future<void> _confirmarProcesamientoTarjeta(
    String tarjetaId,
    String territorioId,
    String tarjetaNombre,
    List<QueryDocumentSnapshot> direcciones,
    BuildContext context,
  ) async {
    final estados = _estadosPorTarjeta[tarjetaId] ?? {};
    final textos = _textosPorTarjeta[tarjetaId] ?? {};

    // Validar que todas tengan estado
    for (final dir in direcciones) {
      final estado = estados[dir.id];
      if (estado == null || estado == 'pendiente' || estado.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Debes seleccionar un estado para todas las direcciones'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (estado == 'otro' && (textos[dir.id]?.trim().isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Para "Otro" debes escribir un motivo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar procesamiento'),
        content: Text(
            '¿Procesar las ${direcciones.length} direcciones de "$tarjetaNombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final ahora = DateTime.now();
      final mesActual =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';

      // Verificar si existe el folder temporal para este territorio
      final folderRef = db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(territorioId);

      bool folderYaExiste = false;
      final folderSnap = await folderRef.get();
      folderYaExiste = folderSnap.exists;

      final batch = db.batch();

      for (final dir in direcciones) {
        final estado = estados[dir.id] ?? 'pendiente';
        final motivo = textos[dir.id]?.trim() ?? '';
        final data = _safeData(dir);
        final calle = (data['calle'] as String?) ?? '';
        final complemento = (data['complemento'] as String?) ?? '';
        final territorioNombre =
            (data['territorio_nombre'] as String?)?.isNotEmpty == true
                ? data['territorio_nombre'] as String
                : (data['barrio'] as String?)?.isNotEmpty == true
                    ? data['barrio'] as String
                    : territorioId;
        final tarjetaIdOriginal = (data['tarjeta_id'] as String?) ?? tarjetaId;

        if (estado == 'completada') {
          // Se predicó — completar en direcciones_globales
          // tarjeta_id se MANTIENE para que admin vea progreso por tarjeta
          batch.update(dir.reference, {
            'estado': 'activa',
            'estado_predicacion': 'completada',
            'predicado': true,
            'fecha_predicacion': FieldValue.serverTimestamp(),
            'mes_predicacion': mesActual,
          });
        } else if (estado == 'no_predicado' || estado == 'otro') {
          // No se predicó / Otro — va a temporales
          // Crear folder si no existe (sin duplicar)
          if (!folderYaExiste) {
            batch.set(folderRef, {
              'nombre_grupo': territorioNombre,
              'territorio_id': territorioId,
              'tipo': 'folder_temporal',
              'created_at': FieldValue.serverTimestamp(),
            });
            folderYaExiste = true; // evitar duplicar en el mismo batch
          }

          // Guardar dirección en el folder temporal
          batch.set(folderRef.collection('direcciones').doc(dir.id), {
            'calle': calle,
            'complemento': complemento,
            'direccion_normalizada':
                _normalizarDireccion('$calle $complemento'),
            'territorio_id': territorioId,
            'territorio_nombre': territorioNombre,
            'tarjeta_id_origen': tarjetaIdOriginal,
            'motivo': estado == 'otro' ? motivo : 'no_predicado',
            'created_at': FieldValue.serverTimestamp(),
          });

          // Actualizar en direcciones_globales — estado temporal
          // tarjeta_id se MANTIENE apuntando a tarjeta original
          batch.update(dir.reference, {
            'estado': 'temporal',
            'estado_predicacion': 'temporal',
            'motivo_temporal': estado == 'otro' ? motivo : 'no_predicado',
            'fecha_temporal': FieldValue.serverTimestamp(),
          });
        } else if (estado == 'no_hispano') {
          // No vive hispanohablante — ELIMINAR de direcciones_globales
          // y CREAR en direcciones_removidas

          // 1. Crear en direcciones_removidas
          batch.set(db.collection('direcciones_removidas').doc(dir.id), {
            'calle': calle,
            'complemento': complemento,
            'direccion_normalizada':
                _normalizarDireccion('$calle $complemento'),
            'territorio_id': territorioId,
            'territorio_nombre': territorioNombre,
            'tarjeta_id_origen': tarjetaIdOriginal,
            'motivo': 'no_hispano',
            'removida_por': widget.usuarioData['nombre'] ?? '',
            'removida_en': FieldValue.serverTimestamp(),
            'doc_id_original': dir.id,
          });

          // 2. ELIMINAR de direcciones_globales
          batch.delete(dir.reference);
        }
      }

      // Marcar tarjeta como completada
      batch.update(
        db
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(tarjetaId),
        {
          'completada': true,
          'fecha_completada': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      if (mounted) {
        setState(() {
          _tarjetasCompletadas.add(tarjetaId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('¡Tarjeta "$tarjetaNombre" completada!',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B5E20),
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
            content: Text('Error al procesar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    debugPrint('=== NOMBRE: ${widget.usuarioData['nombre']}');
    debugPrint('=== EMAIL: ${widget.usuarioEmail}');
    final nombrePublicador = widget.usuarioData['nombre'] ?? 'Publicador';
    final iniciales =
        nombrePublicador.isNotEmpty ? nombrePublicador[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // ── HEADER ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withOpacity(0.85),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      iniciales,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $nombrePublicador',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tus tarjetas asignadas este mes',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ✅ Botón solicitar territorio a la derecha
                  GestureDetector(
                    onTap: widget.onSolicitarTerritorio,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 1),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              color: Colors.white, size: 20),
                          SizedBox(height: 2),
                          Text(
                            'Solicitar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── ALERTAS ────────────────────────────────────
          if (widget.campanaEspecialActiva ||
              (widget.campanaGeneralActiva &&
                  widget.anuncioGeneral.trim().isNotEmpty))
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (widget.campanaEspecialActiva)
                    _alertaBanner(
                      icon: Icons.campaign,
                      color: const Color(0xFFE65100),
                      bgColor: const Color(0xFFFFF3E0),
                      title: 'Campaña especial activa',
                      body: widget.nombreCampanaEspecial,
                    ),
                  if (widget.campanaGeneralActiva &&
                      widget.anuncioGeneral.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _alertaBanner(
                      icon: Icons.info_outline,
                      color: const Color(0xFF1565C0),
                      bgColor: const Color(0xFFE3F2FD),
                      title: 'Anuncio',
                      body: widget.anuncioGeneral,
                    ),
                  ],
                ]),
              ),
            ),

          // ── STATS ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .where('asignado_a',
                        isEqualTo: widget.usuarioData['nombre'] ?? '')
                    .snapshots(),
                builder: (context, tarjetasSnap) {
                  int totalDirAsignadas = 0;
                  final List<String> tarjetaIds = [];

                  if (tarjetasSnap.hasData) {
                    for (final t in tarjetasSnap.data!.docs) {
                      final d = _safeData(t);
                      totalDirAsignadas +=
                          ((d['cantidad_direcciones'] ?? 0) as int);
                      tarjetaIds.add(t.id);
                    }
                  }

                  return FutureBuilder<QuerySnapshot?>(
                    future: tarjetaIds.isEmpty
                        ? Future.value(null)
                        : FirebaseFirestore.instance
                            .collection('direcciones_globales')
                            .where('tarjeta_id',
                                whereIn: tarjetaIds.take(10).toList())
                            .get(),
                    builder: (context, dirsSnap) {
                      final mesActual =
                          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

                      final completadas = dirsSnap.data?.docs.where((doc) {
                            final d = _safeData(doc);
                            return d['predicado'] == true &&
                                d['mes_predicacion'] == mesActual;
                          }).length ??
                          0;

                      final pendientes = totalDirAsignadas - completadas;

                      return Row(
                        children: [
                          Expanded(
                            child: _statCard('Dir Asignadas', totalDirAsignadas,
                                Icons.home_work_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard('Dir Completadas', completadas,
                                Icons.check_circle_outline),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                                'Dir Pendientes',
                                pendientes < 0 ? 0 : pendientes,
                                Icons.schedule_outlined),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // ── PROGRESO ───────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .snapshots(),
                builder: (context, snapTotal) {
                  final totalExistentes = snapTotal.data?.docs.length ?? 0;
                  final completadasGlobal = snapTotal.data?.docs.where((doc) {
                        final d = _safeData(doc);
                        return d['predicado'] == true;
                      }).length ??
                      0;
                  final pendientesGlobal = totalExistentes - completadasGlobal;
                  final avance = totalExistentes > 0
                      ? completadasGlobal / totalExistentes
                      : 0.0;

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Progreso mensual',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF263238),
                              ),
                            ),
                            Text(
                              '${(avance * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: avance,
                            minHeight: 10,
                            backgroundColor: const Color(0xFFE8F5E9),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF1B5E20)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _miniStat('Existentes', totalExistentes,
                                  Icons.home_work_outlined, Colors.blue),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniStat(
                                  'Completadas',
                                  completadasGlobal,
                                  Icons.check_circle_outline,
                                  const Color(0xFF1B5E20)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniStat('Pendientes', pendientesGlobal,
                                  Icons.schedule_outlined, Colors.orange),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // ── MIS TARJETAS ───────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MIS TARJETAS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .where('asignado_a',
                            isEqualTo: widget.usuarioData['nombre'] ?? '')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Text(
                              'No tienes tarjetas asignadas.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      // FIX 3: Ocultar completadas al instante
                      final tarjetasVisibles = snapshot.data!.docs.where((doc) {
                        if (_tarjetasCompletadas.contains(doc.id)) {
                          return false;
                        }
                        final d = _safeData(doc);
                        return d['completada'] != true;
                      }).toList();

                      if (tarjetasVisibles.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    const Color(0xFF1B5E20).withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  color: Color(0xFF1B5E20)),
                              SizedBox(width: 8),
                              Text(
                                '¡Todas las tarjetas completadas!',
                                style: TextStyle(
                                  color: Color(0xFF1B5E20),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children:
                            List.generate(tarjetasVisibles.length, (index) {
                          final tarjetaDoc = tarjetasVisibles[index];
                          final data = _safeData(tarjetaDoc);
                          final nombre =
                              (data['nombre'] as String?) ?? tarjetaDoc.id;
                          final territorioId =
                              tarjetaDoc.reference.parent.parent?.id ?? '';

                          // Color aleatorio pero estable por índice
                          final color =
                              _tarjetaColores[index % _tarjetaColores.length];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: color.withOpacity(0.2), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.12),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 5),
                                  child: ExpansionTile(
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.credit_card,
                                          color: color, size: 20),
                                    ),
                                    title: Text(nombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: FutureBuilder<QuerySnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaDoc.id)
                                          .where('estado',
                                              isNotEqualTo: 'removida')
                                          .get(),
                                      builder: (context, dirSnap) {
                                        final cantReal =
                                            dirSnap.data?.docs.length ?? 0;
                                        final enviadoNombre =
                                            (data['enviado_nombre']
                                                    as String?) ??
                                                '';
                                        final enviadoEn =
                                            data['enviado_en'] as Timestamp?;
                                        String fechaHora = '';
                                        if (enviadoEn != null) {
                                          final dt = enviadoEn.toDate();
                                          final h = dt.hour
                                              .toString()
                                              .padLeft(2, '0');
                                          final m = dt.minute
                                              .toString()
                                              .padLeft(2, '0');
                                          fechaHora =
                                              '${dt.day}/${dt.month}/${dt.year} $h:$m';
                                        }
                                        return Text(
                                          '$cantReal dir${enviadoNombre.isNotEmpty ? ' · $enviadoNombre' : ''}${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                                          style: const TextStyle(fontSize: 11),
                                        );
                                      },
                                    ),
                                    trailing: TextButton(
                                      onPressed: () async {
                                        final confirmar =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title:
                                                const Text('Devolver tarjeta'),
                                            content: Text(
                                              '¿Devolver "$nombre"? Quedará disponible para otros.',
                                            ),
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
                                          await _devolverTarjeta(
                                              territorioId, tarjetaDoc.id);
                                        }
                                      },
                                      child: const Text('Devolver',
                                          style:
                                              TextStyle(color: Colors.orange)),
                                    ),
                                    children: [
                                      _buildDireccionesTarjeta(
                                          tarjetaDoc.id, territorioId, nombre),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 5,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        bottomLeft: Radius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Padding para que el FAB no tape el contenido inferior
          const SliverPadding(
            padding: EdgeInsets.only(bottom: 140),
          ),
        ],
      ),
    );
  }
}
