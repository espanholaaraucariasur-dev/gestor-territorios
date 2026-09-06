import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/notificacion_service.dart';
import '../../models/notificacion_model.dart';

class NotificacionesScreen extends StatefulWidget {
  final String usuarioUid;

  const NotificacionesScreen({super.key, required this.usuarioUid});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_notificaciones'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificacionService.marcarTodasLeidas(widget.usuarioUid);
            },
            child: Text(
              context.t('eco2_marcar_todas_leidas'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Notificacion>>(
        stream: NotificacionService.obtenerPorUsuario(widget.usuarioUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final notificaciones = snapshot.data ?? [];
          if (notificaciones.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    context.t('eco2_sin_notificaciones'),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notificaciones.length,
            itemBuilder: (ctx, i) {
              final notif = notificaciones[i];
              return _buildTarjetaNotificacion(notif);
            },
          );
        },
      ),
    );
  }

  Widget _buildTarjetaNotificacion(Notificacion notif) {
    final iconData = notif.iconoTipo == 'assignment'
        ? Icons.assignment
        : notif.iconoTipo == 'cancel'
            ? Icons.cancel
            : notif.iconoTipo == 'alarm'
                ? Icons.alarm
                : notif.iconoTipo == 'calendar_today'
                    ? Icons.calendar_today
                    : Icons.notifications;

    final color = notif.tipo == 'recusa'
        ? Colors.red
        : notif.tipo == 'recordatorio'
            ? Colors.orange
            : const Color(0xFF1B5E20);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (!notif.leida) {
            await NotificacionService.marcarLeida(notif.id);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: notif.leida ? null : color.withValues(alpha: 0.03),
            border: Border(
              left: BorderSide(
                color: notif.leida ? Colors.grey.shade300 : color,
                width: 4,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif.titulo,
                      style: TextStyle(
                        fontWeight: notif.leida
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: 13,
                        color: const Color(0xFF263238),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notif.mensaje,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (notif.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatearTiempo(notif.createdAt!),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!notif.leida)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearTiempo(DateTime fecha) {
    final ahora = DateTime.now();
    final diff = ahora.difference(fecha);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }
}
