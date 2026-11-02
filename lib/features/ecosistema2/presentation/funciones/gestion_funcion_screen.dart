import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/funcion_service.dart';
import '../../data/arreglo_service.dart';
import '../../data/usuario_eco2_service.dart';
import '../../models/funcion_model.dart';
import '../../models/arreglo_model.dart';
import '../../models/usuario_eco2_model.dart';
import 'crear_arreglo_screen.dart';

class GestionFuncionScreen extends StatefulWidget {
  final String funcionId;
  final String usuarioUid;
  final bool esAdmin;

  const GestionFuncionScreen({
    super.key,
    required this.funcionId,
    required this.usuarioUid,
    required this.esAdmin,
  });

  @override
  State<GestionFuncionScreen> createState() => _GestionFuncionScreenState();
}

class _GestionFuncionScreenState extends State<GestionFuncionScreen> {
  bool get _esAdmin => widget.esAdmin;

  Color _colorFuncion(String colorHex) {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF1B5E20);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Funcion?>(
      stream: FuncionService.obtenerPorId(widget.funcionId),
      builder: (context, snapFuncion) {
        if (snapFuncion.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final funcion = snapFuncion.data;
        if (funcion == null) {
          return Scaffold(
            body: Center(child: Text(context.t('eco2_error_cargar'))),
          );
        }

        final color = _colorFuncion(funcion.color);

        return Scaffold(
          backgroundColor: const Color(0xFFF1F8E9),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            title: Text(
              funcion.nombre,
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
              if (_esAdmin)
                IconButton(
                  icon: const Icon(Icons.people_outline, color: Colors.white),
                  tooltip: context.t('eco2_gestion_personal'),
                  onPressed: () => _configurarPersonal(funcion, color),
                ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: color.withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      funcion.descripcion,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${context.t("eco2_gestor")}: ${_esAdmin ? context.t("eco2_admin") : funcion.gestorUid ?? context.t("eco2_sin_gestor")}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Arreglo>>(
                  stream: ArregloService.obtenerPorFuncion(widget.funcionId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final arreglos = snapshot.data ?? [];
                    if (arreglos.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              context.t('eco2_sin_arreglos'),
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
                      itemCount: arreglos.length,
                      itemBuilder: (ctx, i) =>
                          _buildTarjetaArreglo(ctx, arreglos[i], color),
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: color,
            onPressed: () => _crearArreglo(funcion, color),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildTarjetaArreglo(
      BuildContext context, Arreglo arreglo, Color color) {
    final duracionLabel = {
      '1_semana': context.t('eco2_duracion_semana'),
      '1_mes': context.t('eco2_duracion_mes'),
      '3_meses': context.t('eco2_duracion_trimestre'),
    }[arreglo.duracion] ?? arreglo.duracion;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _verDetalleArreglo(arreglo, color),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                color: arreglo.publicado ? color : Colors.grey,
                width: 4,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      arreglo.titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: arreglo.publicado
                          ? color.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      arreglo.publicado
                          ? context.t('eco2_publicado')
                          : context.t('eco2_borrador'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: arreglo.publicado ? color : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$duracionLabel · ${_formatearFecha(arreglo.fechaInicio)} - ${_formatearFecha(arreglo.fechaFin)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _statBadge(
                      context.t('eco2_slots_asignados'),
                      '${arreglo.slotsAsignados}/${arreglo.totalSlots}',
                      color),
                  const SizedBox(width: 8),
                  if (arreglo.slotsRecusados > 0)
                    _statBadge(context.t('eco2_recusas'),
                        '${arreglo.slotsRecusados}', Colors.red),
                  const SizedBox(width: 8),
                  if (arreglo.slotsAceptados > 0)
                    _statBadge(context.t('eco2_aceptados'),
                        '${arreglo.slotsAceptados}', Colors.green),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  void _crearArreglo(Funcion funcion, Color color) async {
    final usuarios =
        await UsuarioEco2Service.obtenerAprobadosUnaVez();
    final usuariosConRol = usuarios
        .where((u) => funcion.rolesRequeridos
            .any((r) => u.roles.contains(r)))
        .toList();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CrearArregloScreen(
          funcion: funcion,
          usuariosDisponibles: usuariosConRol,
          color: color,
        ),
      ),
    );
  }

  void _verDetalleArreglo(Arreglo arreglo, Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                arreglo.titulo,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...arreglo.slots.map((slot) => _buildSlotDetalle(slot, color)),
              const SizedBox(height: 20),
              if (!arreglo.publicado)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.publish, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await ArregloService.publicar(arreglo.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    label: Text(context.t('eco2_publicar_arreglo')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotDetalle(SlotArreglo slot, Color color) {
    final estadoColor = slot.estaRecusado
        ? Colors.red
        : slot.estaAceptado
            ? Colors.green
            : color;
    final estadoLabel = slot.estaRecusado
        ? 'Recusado'
        : slot.estaAceptado
            ? 'Aceptado'
            : 'Asignado';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: estadoColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: estadoColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              slot.campoId == 'audio' ? Icons.volume_up : Icons.videocam,
              color: estadoColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${slot.campoId.toUpperCase()} - ${slot.reunionTipo == 'entre_semana' ? 'Entre Semana' : 'Fin de Semana'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: estadoColor,
                  ),
                ),
                Text(
                  '${slot.diaSemana} ${slot.hora} · Sem ${slot.semanaNumero}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (slot.estaRecusado && slot.motivoRecusa != null)
                  Text(
                    'Motivo: ${slot.motivoRecusa}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              estadoLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: estadoColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _configurarPersonal(Funcion funcion, Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF1F8E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('eco2_gestion_personal'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t('eco2_gestion_personal_desc'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<List<UsuarioEco2>>(
                stream: UsuarioEco2Service.obtenerPorRol(
                    funcion.rolesRequeridos.isEmpty
                        ? 'publicador'
                        : funcion.rolesRequeridos.first),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final usuarios = snap.data ?? [];
                  final liberados = usuarios
                      .where((u) => u.funcionesAsignadas.contains(funcion.id))
                      .toList();
                  final pendientes = usuarios
                      .where((u) => !u.funcionesAsignadas.contains(funcion.id))
                      .toList();

                  if (usuarios.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.t('eco2_sin_usuarios_rol'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 14),
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      if (pendientes.isNotEmpty) ...[
                        _seccionLabel(
                            context.t('eco2_pendiente').toUpperCase()),
                        ...pendientes
                            .map((u) => _buildPersonalCard(ctx, u, funcion, color, false)),
                      ],
                      if (liberados.isNotEmpty) ...[
                        if (pendientes.isNotEmpty) const SizedBox(height: 12),
                        _seccionLabel(context.t('eco2_liberado').toUpperCase()),
                        ...liberados
                            .map((u) => _buildPersonalCard(ctx, u, funcion, color, true)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildPersonalCard(BuildContext ctx, UsuarioEco2 usuario,
      Funcion funcion, Color color, bool liberado) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: (liberado ? color : Colors.grey)
                  .withValues(alpha: 0.15),
              child: Text(
                usuario.nombre.isNotEmpty
                    ? usuario.nombre.substring(0, 1).toUpperCase()
                    : '?',
                style: TextStyle(
                  color: liberado ? color : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    usuario.nombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    liberado
                        ? context.t('eco2_liberado_hint')
                        : context.t('eco2_pendiente_hint'),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Switch(
              value: liberado,
              activeColor: color,
              onChanged: (value) async {
                try {
                  if (value) {
                    await UsuarioEco2Service.asignarFuncion(
                        usuario.uid, funcion.id);
                  } else {
                    await UsuarioEco2Service.removerFuncion(
                        usuario.uid, funcion.id);
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('${context.t('eco2_error_cargar')}: $e'),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
