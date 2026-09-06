import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/arreglo_service.dart';
import '../../data/funcion_service.dart';
import '../../data/notificacion_service.dart';
import '../../models/arreglo_model.dart';
import '../../models/funcion_model.dart';

class MisDesignacionesScreen extends StatefulWidget {
  final String usuarioUid;

  const MisDesignacionesScreen({super.key, required this.usuarioUid});

  @override
  State<MisDesignacionesScreen> createState() => _MisDesignacionesScreenState();
}

class _MisDesignacionesScreenState extends State<MisDesignacionesScreen> {
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
          context.t('eco2_mis_designaciones'),
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
      ),
      body: StreamBuilder<List<Arreglo>>(
        stream: ArregloService.obtenerConSlotParaUsuario(widget.usuarioUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final arreglos = snapshot.data ?? [];

          final pendientes = <_DesignacionInfo>[];
          final aceptadas = <_DesignacionInfo>[];
          final historial = <_DesignacionInfo>[];

          for (final arr in arreglos) {
            for (final slot in arr.slots) {
              if (slot.usuarioUid != widget.usuarioUid) continue;
              final info = _DesignacionInfo(arreglo: arr, slot: slot);

              if (slot.estaRecusado) {
                historial.add(info);
              } else if (slot.estaAceptado) {
                if (arr.fechaFin.isBefore(DateTime.now())) {
                  historial.add(info);
                } else {
                  aceptadas.add(info);
                }
              } else {
                if (arr.fechaFin.isBefore(DateTime.now())) {
                  historial.add(info);
                } else {
                  pendientes.add(info);
                }
              }
            }
          }

          if (pendientes.isEmpty &&
              aceptadas.isEmpty &&
              historial.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    context.t('eco2_sin_designaciones'),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pendientes.isNotEmpty) ...[
                _seccion(
                    context.t('eco2_pendientes'), pendientes, Colors.orange),
                const SizedBox(height: 16),
              ],
              if (aceptadas.isNotEmpty) ...[
                _seccion(
                    context.t('eco2_aceptadas'), aceptadas, Colors.green),
                const SizedBox(height: 16),
              ],
              if (historial.isNotEmpty) ...[
                _seccion(
                    context.t('eco2_historial'), historial, Colors.grey),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _seccion(
      String titulo, List<_DesignacionInfo> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$titulo (${items.length})',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((info) => _buildTarjetaDesignacion(info, color)),
      ],
    );
  }

  Widget _buildTarjetaDesignacion(_DesignacionInfo info, Color color) {
    final slot = info.slot;
    final arreglo = info.arreglo;
    final esPendiente = !slot.estaAceptado && !slot.estaRecusado;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: color, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  slot.campoId == 'audio' ? Icons.volume_up : Icons.videocam,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${slot.campoId.toUpperCase()} - ${arreglo.titulo}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      Text(
                        '${slot.diaSemana} ${slot.hora} · ${slot.reunionTipo == 'entre_semana' ? context.t('eco2_entre_semana') : context.t('eco2_fin_semana')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (slot.estaAceptado)
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                if (slot.estaRecusado)
                  Icon(Icons.cancel, color: Colors.red, size: 20),
              ],
            ),
            if (esPendiente) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _recusar(info),
                      label: Text(context.t('eco2_recusar'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _aceptar(info),
                      label: Text(context.t('eco2_aceptar'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
            if (slot.estaRecusado && slot.motivoRecusa != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${context.t("eco2_motivo_recusa")}: ${slot.motivoRecusa}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _aceptar(_DesignacionInfo info) async {
    await ArregloService.actualizarSlot(
      info.arreglo.id,
      info.slot.slotId,
      {'estado': 'aceptado'},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('eco2_designacion_aceptada')),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
    }
  }

  void _recusar(_DesignacionInfo info) {
    final motivoCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('eco2_motivo_recusa'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: context.t('eco2_motivo_recusa_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (motivoCtrl.text.trim().isEmpty) return;
                  await ArregloService.actualizarSlot(
                    info.arreglo.id,
                    info.slot.slotId,
                    {
                      'estado': 'recusado',
                      'motivo_recusa': motivoCtrl.text.trim(),
                    },
                  );
                  await NotificacionService.crearRecusa(
                    paraUid: info.arreglo.gestionadoPor,
                    deUid: info.slot.usuarioUid ?? '',
                    funcionId: info.arreglo.funcionId,
                    arregloId: info.arreglo.id,
                    slotId: info.slot.slotId,
                    titulo:
                        '${context.t("eco2_recusa_titulo")} ${info.slot.campoId.toUpperCase()}',
                    mensaje: motivoCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.t('eco2_designacion_recusada')),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                },
                child: Text(context.t('eco2_enviar_recusa')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignacionInfo {
  final Arreglo arreglo;
  final SlotArreglo slot;
  _DesignacionInfo({required this.arreglo, required this.slot});
}
