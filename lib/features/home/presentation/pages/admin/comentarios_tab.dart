import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Pestaña de "Comentarios".
///
/// Muestra las direcciones que fueron comentadas por el publicador, con:
/// dirección, tarjeta, territorio, quién la comentó y fecha/hora.
class ComentariosTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const ComentariosTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<ComentariosTab> createState() => _ComentariosTabState();
}

class _ComentariosTabState extends State<ComentariosTab> {
  static const Color _morado = Color(0xFF4A148C);

  static const List<String> _marcadores = [
    'no_predicado',
    'no_hispano',
    'comercio_cerrado',
    'otro',
  ];

  String _texto(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  /// Texto de comentario efectivo de una dirección (cadena vacía si no tiene).
  String _comentarioDe(Map<String, dynamic> d) {
    final c = _texto(d, ['comentario', 'comentario_cierre']);
    if (c.isNotEmpty) return c;
    final mt = (d['motivo_temporal'] as String?)?.trim() ?? '';
    if (mt.isNotEmpty && !_marcadores.contains(mt)) return mt;
    return '';
  }

  DateTime _fecha(Map<String, dynamic> d) {
    for (final k in [
      'fecha_predicacion',
      'fecha_confirmacion',
      'fecha_actualizacion',
      'fecha_cierre',
      'fecha_temporal',
      'created_at',
    ]) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _fmtFecha(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '—';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(dt.day)}/${dos(dt.month)}/${dt.year} '
        '${dos(dt.hour)}:${dos(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('direcciones_globales')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final comentadas = <QueryDocumentSnapshot>[];
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          // Las archivadas salen de la bandeja de comentarios (se conservan
          // en Firestore, recuperables a mano).
          if ((d['estado'] as String?) == 'archivada') continue;
          if (_comentarioDe(d).isNotEmpty) comentadas.add(doc);
        }
        comentadas.sort((a, b) => _fecha(b.data() as Map<String, dynamic>)
            .compareTo(_fecha(a.data() as Map<String, dynamic>)));

        if (comentadas.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.comment_outlined,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'No hay direcciones comentadas',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: comentadas.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.comment, color: _morado, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${comentadas.length} dirección(es) comentada(s)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ],
                ),
              );
            }
            return _card(comentadas[i - 1]);
          },
        );
      },
    );
  }

  Widget _card(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final calle = _texto(d, ['calle', 'direccion_normalizada']);
    final complemento = (d['complemento'] as String?)?.trim() ?? '';
    final direccion = complemento.isEmpty ? calle : '$calle, $complemento';
    final tarjeta = _texto(
        d, ['tarjeta_id', 'tarjeta_nombre', 'tarjeta_id_origen']);
    final territorio = _texto(d, [
      'territorio_nombre',
      'territorio_origen_nombre',
      'barrio',
      'territorio_id',
    ]);
    final quien = _texto(
        d, ['resultado_por', 'reportado_por', 'removida_por', 'asignado_a']);
    final comentario = _comentarioDe(d);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: _morado.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, color: _morado, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  direccion.isEmpty ? '(sin dirección)' : direccion,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.archive_outlined,
                    color: Colors.teal, size: 20),
                tooltip: 'Archivar',
                visualDensity: VisualDensity.compact,
                onPressed: () => _archivar(doc),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                tooltip: 'Eliminar',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmarEliminar(doc),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fila(Icons.credit_card, 'Tarjeta',
              tarjeta.isEmpty ? '—' : tarjeta),
          _fila(Icons.map_outlined, 'Territorio',
              territorio.isEmpty ? '—' : territorio),
          _fila(Icons.person_outline, 'Comentó',
              quien.isEmpty ? '—' : quien),
          _fila(Icons.access_time, 'Fecha y hora',
              _fmtFecha(_fecha(d))),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _morado.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              comentario,
              style: const TextStyle(fontSize: 13, color: Color(0xFF37474F)),
            ),
          ),
        ],
      ),
    );
  }

  String get _adminNombre {
    final d = widget.usuarioData;
    return (d['nombre'] as String?)?.trim().isNotEmpty == true
        ? (d['nombre'] as String).trim()
        : ((d['email'] as String?)?.trim() ?? '');
  }

  Future<void> _archivar(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final calle = _texto(d, ['calle', 'direccion_normalizada']);
    try {
      await doc.reference.update({
        'estado': 'archivada',
        'archivada_por': _adminNombre,
        'archivada_en': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Archivada: ${calle.isEmpty ? 'dirección' : calle}'),
        backgroundColor: Colors.teal,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo archivar: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _confirmarEliminar(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final calle = _texto(d, ['calle', 'direccion_normalizada']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar dirección'),
        content: Text(
            '¿Eliminar definitivamente "${calle.isEmpty ? 'esta dirección' : calle}"? '
            'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, eliminar',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await doc.reference.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dirección eliminada'),
        backgroundColor: Colors.redAccent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo eliminar: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Widget _fila(IconData icon, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(fontSize: 12, color: Color(0xFF37474F)),
            ),
          ),
        ],
      ),
    );
  }
}
