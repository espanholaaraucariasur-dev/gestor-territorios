import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// BADGE de notificaciones para el AppBar
// ─────────────────────────────────────────────────────────────
class NotificacionesBadge extends StatelessWidget {
  final String usuarioEmail;

  const NotificacionesBadge({super.key, required this.usuarioEmail});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notificaciones')
          .where('destinatario', isEqualTo: usuarioEmail)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final count = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['leida'] == false;
        }).length;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none_outlined,
                color: Colors.white,
              ),
              onPressed: () => NotificacionesDialog.mostrar(context, usuarioEmail),
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIALOG completo de notificaciones
// ─────────────────────────────────────────────────────────────
class NotificacionesDialog {
  static void mostrar(BuildContext context, String usuarioEmail) {
    showDialog(
      context: context,
      builder: (context) => _NotificacionesDialogContent(
        usuarioEmail: usuarioEmail,
      ),
    );
  }
}

class _NotificacionesDialogContent extends StatelessWidget {
  final String usuarioEmail;

  const _NotificacionesDialogContent({required this.usuarioEmail});

  IconData _iconoPorTipo(String tipo) {
    switch (tipo) {
      case 'motivacional': return Icons.star;
      case 'auto_devolucion': return Icons.timer;
      case 'solicitud_direccion': return Icons.add_location_alt;
      case 'alerta_predicacion': return Icons.warning_amber;
      case 'nueva_solicitud_usuario': return Icons.person_add;
      case 'devolucion_tarjeta': return Icons.assignment_return;
      case 'devolucion_automatica': return Icons.assignment_late;
      default: return Icons.notifications;
    }
  }

  Color _colorPorTipo(String tipo) {
    switch (tipo) {
      case 'motivacional': return Colors.amber;
      case 'auto_devolucion': return Colors.orange;
      case 'solicitud_direccion': return Colors.blue;
      case 'alerta_predicacion': return Colors.red;
      case 'nueva_solicitud_usuario': return Colors.purple;
      case 'devolucion_tarjeta': return Colors.orange;
      case 'devolucion_automatica': return Colors.deepOrange;
      default: return const Color(0xFF1B5E20);
    }
  }

  Future<void> _marcarTodasLeidas() async {
    final snap = await FirebaseFirestore.instance
        .collection('notificaciones')
        .where('destinatario', isEqualTo: usuarioEmail)
        .where('leida', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'leida': true});
    }
    await batch.commit();
  }

  Future<void> _limpiarTodas(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Limpiar notificaciones'),
        content: const Text('¿Eliminar todas las notificaciones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final snap = await FirebaseFirestore.instance
        .collection('notificaciones')
        .where('destinatario', isEqualTo: usuarioEmail)
        .limit(200)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.notifications, color: Color(0xFF1B5E20)),
          SizedBox(width: 8),
          Text('Notificaciones'),
        ],
      ),
      content: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notificaciones')
            .where('destinatario', isEqualTo: usuarioEmail)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          // Ordenar en memoria — más reciente primero
          final docs = [...snapshot.data!.docs];
          docs.sort((a, b) {
            final aT = (a.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
            final bT = (b.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });

          if (docs.isEmpty) {
            return SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_none_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      context.t('no_new_notifications'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final titulo = data['titulo'] as String? ?? 'Sin título';
                final cuerpo = data['cuerpo'] as String? ?? '';
                final leida = data['leida'] == true;
                final tipo = data['tipo'] as String? ?? '';
                final createdAt = data['created_at'] as Timestamp?;

                String fecha = '';
                if (createdAt != null) {
                  final dt = createdAt.toDate();
                  fecha =
                      '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                }

                final icono = _iconoPorTipo(tipo);
                final color = _colorPorTipo(tipo);

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: leida ? Colors.grey.shade50 : Colors.white,
                  elevation: leida ? 0 : 1,
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: leida
                          ? Colors.grey.shade200
                          : color.withOpacity(0.12),
                      child: Icon(
                        icono,
                        color: leida ? Colors.grey : color,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      titulo,
                      style: TextStyle(
                        fontWeight:
                            leida ? FontWeight.normal : FontWeight.bold,
                        fontSize: 13,
                        color: leida ? Colors.grey.shade600 : Colors.black,
                      ),
                    ),
                    subtitle: cuerpo.isNotEmpty
                        ? Text(
                            cuerpo,
                            style: TextStyle(
                              color: leida
                                  ? Colors.grey.shade500
                                  : Colors.black87,
                              fontSize: 12,
                            ),
                            maxLines: tipo == 'alerta_predicacion' ? 5 : 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Text(
                      fecha,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    onTap: () async {
                      if (!leida) {
                        await doc.reference.update({'leida': true});
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _marcarTodasLeidas,
          child: const Text('Marcar leídas',
              style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => _limpiarTodas(context),
          child: const Text('Limpiar',
              style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () {
            _marcarTodasLeidas();
            Navigator.pop(context);
          },
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
