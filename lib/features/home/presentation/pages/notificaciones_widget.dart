import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/notificacion_service.dart';
import '../../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// Badge del AppBar
// ─────────────────────────────────────────────────────────────
class NotificacionesBadge extends StatelessWidget {
  final String usuarioEmail;
  const NotificacionesBadge({super.key, required this.usuarioEmail});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificacionService.streamConteo(usuarioEmail),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_outlined, color: Colors.white),
              onPressed: () => NotificacionesDialog.mostrar(context, usuarioEmail),
            ),
            if (count > 0)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('$count',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Diálogo de notificaciones
// ─────────────────────────────────────────────────────────────
class NotificacionesDialog {
  static void mostrar(BuildContext context, String usuarioEmail) {
    showDialog(
      context: context,
      builder: (_) => _NotificacionesDialog(usuarioEmail: usuarioEmail),
    );
  }
}

class _NotificacionesDialog extends StatelessWidget {
  final String usuarioEmail;
  const _NotificacionesDialog({required this.usuarioEmail});

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'motivacional':          return Icons.star;
      case 'aviso_devolucion':      return Icons.timer;
      case 'solicitud_direccion':   return Icons.add_location_alt;
      case 'alerta_predicacion':    return Icons.warning_amber;
      case 'solicitud_acceso':      return Icons.person_add;
      case 'devolucion_tarjeta':    return Icons.assignment_return;
      case 'devolucion_automatica': return Icons.assignment_late;
      default:                      return Icons.notifications;
    }
  }

  Color _color(String tipo) {
    switch (tipo) {
      case 'motivacional':          return Colors.amber;
      case 'aviso_devolucion':      return Colors.orange;
      case 'solicitud_direccion':   return Colors.blue;
      case 'alerta_predicacion':    return Colors.red;
      case 'solicitud_acceso':      return Colors.purple;
      case 'devolucion_tarjeta':    return Colors.orange;
      case 'devolucion_automatica': return Colors.deepOrange;
      default:                      return const Color(0xFF1B5E20);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.notifications, color: Color(0xFF1B5E20)),
        SizedBox(width: 8),
        Text('Notificaciones'),
      ]),
      content: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: NotificacionService.streamNotificaciones(usuarioEmail),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(height: 100,
                child: Center(child: CircularProgressIndicator()));
          }
          final docs = snap.data!;
          if (docs.isEmpty) {
            return SizedBox(height: 120, child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.notifications_none_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(context.t('no_new_notifications'),
                    style: const TextStyle(color: Colors.grey)),
              ]),
            ));
          }
          return SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final titulo = data['titulo'] as String? ?? '';
                final cuerpo = data['cuerpo'] as String? ?? '';
                final leida = data['leida'] == true;
                final tipo = data['tipo'] as String? ?? '';
                final ts = data['created_at'] as Timestamp?;
                final fecha = ts != null
                    ? '${ts.toDate().day}/${ts.toDate().month} '
                      '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                    : '';
                final color = _color(tipo);
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
                      child: Icon(_icono(tipo),
                          color: leida ? Colors.grey : color, size: 18),
                    ),
                    title: Text(titulo,
                        style: TextStyle(
                          fontWeight: leida ? FontWeight.normal : FontWeight.bold,
                          fontSize: 13,
                          color: leida ? Colors.grey.shade600 : Colors.black,
                        )),
                    subtitle: cuerpo.isNotEmpty
                        ? Text(cuerpo,
                            style: TextStyle(
                              fontSize: 12,
                              color: leida ? Colors.grey.shade500 : Colors.black87,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Text(fecha,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                    onTap: () async {
                      if (!leida) {
                        await docs[i].reference.update({'leida': true});
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
          onPressed: () => NotificacionService.marcarLeidas(usuarioEmail),
          child: const Text('Marcar leídas', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Limpiar notificaciones'),
                content: const Text('¿Eliminar todas tus notificaciones?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await NotificacionService.limpiar(usuarioEmail);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Limpiar', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () {
            NotificacionService.marcarLeidas(usuarioEmail);
            Navigator.pop(context);
          },
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
