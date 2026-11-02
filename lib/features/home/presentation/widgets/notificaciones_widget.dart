import 'package:araucaria_sur/core/services/navegacion_service.dart';
import 'package:araucaria_sur/core/services/notificacion_service.dart';
import 'package:araucaria_sur/features/home/presentation/widgets/mensaje_animado_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificacionesBadge extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  const NotificacionesBadge({super.key, required this.usuarioData});

  @override
  State<NotificacionesBadge> createState() => _NotificacionesBadgeState();
}

class _NotificacionesBadgeState extends State<NotificacionesBadge> {
  @override
  Widget build(BuildContext context) {
    final perfil = NotificacionService.perfilDesdeUsuario(widget.usuarioData);
    return StreamBuilder<int>(
      stream: NotificacionService.streamConteo(perfil),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return IconButton(
          tooltip: 'Notificaciones',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 24),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () =>
              NotificacionesDialog.mostrar(context, widget.usuarioData),
        );
      },
    );
  }
}

class NotificacionesDialog {
  static void mostrar(BuildContext context, Map<String, dynamic> usuarioData) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NotificacionesSheet(usuarioData: usuarioData),
    );
  }
}

class _NotificacionesSheet extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  const _NotificacionesSheet({required this.usuarioData});

  @override
  State<_NotificacionesSheet> createState() => _NotificacionesSheetState();
}

class _NotificacionesSheetState extends State<_NotificacionesSheet> {
  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'motivacional':
        return Icons.emoji_emotions_outlined;
      case 'anuncio':
        return Icons.campaign_outlined;
      case 'sugerencia':
        return Icons.lightbulb_outline;
      case 'aviso_devolucion':
        return Icons.replay_circle_filled_outlined;
      case 'solicitud_direccion':
        return Icons.location_on_outlined;
      case 'nueva_direccion_enviada':
        return Icons.new_releases_outlined;
      case 'alerta_predicacion':
        return Icons.campaign_outlined;
      case 'solicitud_acceso':
        return Icons.person_add_alt_outlined;
      case 'tarjeta_tomada':
        return Icons.credit_card_outlined;
      case 'devolucion_tarjeta':
        return Icons.swap_horiz_outlined;
      case 'devolucion_automatica':
        return Icons.autorenew;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  String _formatearFecha(dynamic valor) {
    DateTime? date;
    if (valor is Timestamp) {
      date = valor.toDate();
    } else if (valor is String) {
      date = DateTime.tryParse(valor)?.toLocal();
    } else if (valor is DateTime) {
      date = valor;
    }
    if (date == null) return '';
    final ahora = DateTime.now();
    final diff = ahora.difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Comportamiento al tocar una notificación.
  ///
  /// - El motivacional no lleva a ninguna pantalla: se muestra en la ventana
  ///   animada.
  /// - Las demás se encolan en [NavegacionService] y `home_page` las ejecuta,
  ///   porque es el único que sabe cambiar de modo y de pestaña.
  void _alTocar(
    BuildContext context,
    QueryDocumentSnapshot doc,
    Map<String, dynamic> data,
    String titulo,
    String cuerpo,
    String tipo,
  ) {
    // Cierra la hoja para que el destino o la ventana animada se vean a
    // pantalla completa.
    Navigator.of(context).pop();

    if (tipo == 'anuncio') {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        showDialog<void>(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.campaign_outlined,
                color: Color(0xFF1B5E20), size: 32),
            title: Text(titulo.isEmpty ? 'Anuncio de la congregación' : titulo),
            content: Text(cuerpo),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      });
      return;
    }

    if (tipo == 'motivacional') {
      // Solo naturaleza, luz y mundo. Sin cruces, templos ni símbolos de
      // iglesias (tampoco palomas).
      const emojis = ['🌅', '📖', '🌱', '🌿', '🌍', '✨'];
      // El emoji se deriva del TEXTO del mensaje (no del título, que es fijo
      // para todos los motivacionales) para que cada mensaje enviado se sienta
      // distinto. Si no hay texto, cae de vuelta al título.
      final baseEmoji = cuerpo.trim().isNotEmpty ? cuerpo : titulo;
      final semilla = baseEmoji.isEmpty
          ? 0
          : baseEmoji.codeUnits.fold<int>(0, (a, b) => a + b);
      // Contexto del Navigator raíz, capturado AHORA (antes de que se cierre
      // la hoja). Antes se usaba `if (!mounted) return;` con el contexto de
      // la hoja: pero la hoja ya fue cerrada con el pop de arriba, y su State
      // se destruye al terminar de animarse el cierre (~200 ms). Con el
      // delay de 260 ms, `mounted` ya era false y la ventana nunca se abría.
      final raiz = Navigator.of(context, rootNavigator: true).context;
      Future.delayed(const Duration(milliseconds: 220), () {
        MensajeAnimadoDialog.mostrar(
          // ignore: use_build_context_synchronously
          raiz,
          titulo: titulo.isEmpty ? '¡Vamos con todo!' : titulo,
          cuerpo: cuerpo,
          iconoEmoji: emojis[semilla % emojis.length],
          onVerTarjetas: () =>
              NavegacionService.solicitar(Pantallas.misTarjetas),
        );
      });
      return;
    }

    final pantalla = NavegacionService.resolverPantalla(
      tipo,
      data,
      widget.usuarioData,
    );
    if (pantalla == null || !Pantallas.todas.contains(pantalla)) return;

    if (!NavegacionService.permitido(pantalla, widget.usuarioData)) {
      final extra = data['extra'];
      final contexto = extra is Map ? extra['solicitante_nombre'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            contexto != null
                ? 'Esta notificacion es sobre "$contexto" y no te corresponde revisarla'
                : 'No tienes permisos para abrir esta notificacion',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final extra = data['extra'];
    NavegacionService.solicitar(pantalla,
        extra is Map ? Map<String, dynamic>.from(extra) : const {});
  }

  @override
  Widget build(BuildContext context) {
    final altura = MediaQuery.of(context).size.height * 0.7;
    final perfil = NotificacionService.perfilDesdeUsuario(widget.usuarioData);
    return Container(
      height: altura,
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    color: Color(0xFF1B5E20)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Notificaciones',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await NotificacionService.marcarLeidas(perfil);
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Leer todas'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Limpiar notificaciones'),
                        content: const Text(
                            '¿Deseas eliminar todas tus notificaciones? Esta acción no se puede deshacer.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Limpiar',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await NotificacionService.limpiar(perfil);
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: NotificacionService.streamNotificaciones(perfil),
              builder: (context, snap) {
                if (snap.hasError) {
                  debugPrint('Error notificaciones: ${snap.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 40, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            'No se pudieron cargar las notificaciones',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Revisa la consola para el detalle (posible índice compuesto de Firestore).',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No tienes notificaciones',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, index) =>
                      const Divider(height: 1, indent: 68),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final titulo = (data['titulo'] as String?) ?? '';
                    final cuerpo = (data['cuerpo'] as String?) ?? '';
                    final tipo = (data['tipo'] as String?) ?? '';
                    final leida = (data['leida'] as bool?) ?? false;
                    final fecha = _formatearFecha(data['created_at']);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: leida
                            ? Colors.grey.shade200
                            : const Color(0xFF1B5E20).withValues(alpha: 0.12),
                        child: Icon(
                          _iconoTipo(tipo),
                          color: leida
                              ? Colors.grey
                              : const Color(0xFF1B5E20),
                          size: 22,
                        ),
                      ),
                      title: Text(
                        titulo,
                        style: TextStyle(
                          fontWeight:
                              leida ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: cuerpo.isNotEmpty
                          ? Text(cuerpo, maxLines: 2,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: leida
                          ? Text(fecha,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(fecha,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                      onTap: () {
                        if (!leida) {
                          doc.reference.update({'leida': true});
                        }
                        _alTocar(context, doc, data, titulo, cuerpo, tipo);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}