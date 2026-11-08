import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../core/services/algolia_service.dart';

/// Pestaña de "Comentarios".
///
/// Muestra las direcciones que fueron comentadas por el publicador, con:
/// dirección, tarjeta, territorio, quién la comentó y fecha/hora.
///
/// Desde aquí se puede **editar el comentario** y **mover su texto al
/// complemento** de la dirección: muchos comentarios hablan justamente de la
/// unidad ("Casa 2", "apto 121"), así que el texto se traslada al campo
/// `complemento` y se quita de la dirección para que no quede duplicado.
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

  String _texto(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  /// Texto de comentario efectivo de una dirección (cadena vacía si no tiene).
  String _comentarioDe(Map<String, dynamic> d) {
    return _texto(d, ['comentario', 'comentario_cierre']);
  }

  /// Clave del comentario que se editó: `comentario_cierre` lo escriben los
  /// cierres (comercio cerrado) y `comentario` el resto. Se respeta cuál
  /// estaba para no crear un campo nuevo que la bandeja no lea.
  String _claveComentario(Map<String, dynamic> d) {
    for (final k in ['comentario', 'comentario_cierre']) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return k;
    }
    return 'comentario';
  }

  DateTime _fecha(Map<String, dynamic> d) {
    for (final k in [
      'fecha_predicacion',
      'fecha_confirmacion',
      'fecha_actualizacion',
      'fecha_cierre',
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
    final tarjeta = _texto(d, ['tarjeta_id', 'tarjeta_nombre']);
    final territorio = _texto(d, [
      'territorio_nombre',
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
                icon: const Icon(Icons.edit_outlined,
                    color: Color(0xFF4A148C), size: 20),
                tooltip: 'Editar comentario',
                visualDensity: VisualDensity.compact,
                onPressed: () => _editarComentario(doc),
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

  /// Quita el complemento actual de la cadena de la calle.
  ///
  /// `calle` guarda la dirección completa ya formateada ("Rua Xingu, 710,
  /// Iguaçu, Araucária - PR"), así que el complemento se busca como subcadena
  /// literal y, si aparece, se elimina junto con las comas que quedan
  /// huérfanas. Si no aparece, la calle se deja intacta.
  String _quitarDeCalle(String calle, String complemento) {
    final c = complemento.trim();
    if (c.isEmpty) return calle;
    if (!calle.toLowerCase().contains(c.toLowerCase())) return calle;
    var limpia = calle.replaceFirst(RegExp(RegExp.escape(c), caseSensitive: false), '');
    limpia = limpia.replaceAll(RegExp(r'\s*,\s*,'), ',');
    limpia = limpia.replaceAll(RegExp(r'^\s*,\s*'), '');
    limpia = limpia.replaceAll(RegExp(r'\s*,\s*$'), '');
    limpia = limpia.replaceAll(RegExp(r'\s+'), ' ').trim();
    return limpia.isEmpty ? calle : limpia;
  }

  /// Edita el comentario de una dirección y permite pasarlo al complemento.
  ///
  /// Reglas:
  ///  - El texto editado se guarda en el mismo campo que ya tenía
  ///    (`comentario` o `comentario_cierre`).
  ///  - Con "Agregar al complemento", el texto pasa a `complemento`: si ya
  ///    había complemento se REEMPLAZA (es la corrección de la unidad); si no
  ///    había, se crea. El texto se quita de `comentario` para no duplicarlo.
  ///  - Si el complemento viejo estaba escrito dentro de la calle, se quita de
  ///    ahí, de modo que la dirección no quede con la unidad repetida.
  Future<void> _editarComentario(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final clave = _claveComentario(d);
    final calle = _texto(d, ['calle']);
    final complementoActual = (d['complemento'] as String?)?.trim() ?? '';
    final textoCtrl = TextEditingController(text: _comentarioDe(d));
    var alComplemento = false;
    var conservarComentario = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Editar comentario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  calle.isEmpty ? '(sin dirección)' : calle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textoCtrl,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Comentario',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: alComplemento,
                  onChanged: (v) =>
                      setDialogState(() => alComplemento = v ?? false),
                  title: const Text('Agregar el texto al complemento',
                      style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    complementoActual.isEmpty
                        ? 'La dirección no tiene complemento: se creará con este texto.'
                        : 'Complemento actual: "$complementoActual" (se reemplaza).',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
                if (alComplemento)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: conservarComentario,
                    onChanged: (v) => setDialogState(
                        () => conservarComentario = v ?? false),
                    title: const Text('Conservar también como comentario',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      conservarComentario
                          ? 'Seguirá apareciendo en esta bandeja.'
                          : 'La dirección saldrá de la bandeja de comentarios.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final texto = textoCtrl.text.trim();
    final cambios = <String, dynamic>{};

    if (alComplemento) {
      if (texto.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe el texto que irá al complemento'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      cambios['complemento'] = texto;
      cambios['complemento_actualizado_en'] = FieldValue.serverTimestamp();
      cambios['complemento_actualizado_por'] = _adminNombre;
      final calleLimpia = _quitarDeCalle(calle, complementoActual);
      if (calleLimpia != calle) cambios['calle'] = calleLimpia;
      if (!conservarComentario) {
        cambios[clave] = FieldValue.delete();
      }
    } else {
      if (texto.isEmpty) {
        cambios[clave] = FieldValue.delete();
      } else {
        cambios[clave] = texto;
      }
    }

    if (cambios.isEmpty) return;

    try {
      await doc.reference.update(cambios);
      // El complemento es parte de la dirección: Algolia tiene que verlo para
      // que la búsqueda siga encontrando la unidad.
      if (alComplemento) {
        final actualizado = {...d, ...cambios};
        actualizado.remove('complemento_actualizado_en');
        actualizado.remove('complemento_actualizado_por');
        await AlgoliaService.sincronizarUna(doc.id, actualizado);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(alComplemento
            ? 'Comentario y complemento actualizados'
            : 'Comentario actualizado'),
        backgroundColor: const Color(0xFF4A148C),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo guardar: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
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
