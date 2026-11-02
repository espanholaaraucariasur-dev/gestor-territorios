import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/funcion_service.dart';
import '../../data/usuario_eco2_service.dart';
import '../../models/funcion_model.dart';
import '../../models/usuario_eco2_model.dart';

class GestionDeAsignacionesScreen extends StatefulWidget {
  final String usuarioUid;
  final bool esAdmin;

  const GestionDeAsignacionesScreen({
    super.key,
    required this.usuarioUid,
    required this.esAdmin,
  });

  @override
  State<GestionDeAsignacionesScreen> createState() =>
      _GestionDeAsignacionesScreenState();
}

class _GestionDeAsignacionesScreenState
    extends State<GestionDeAsignacionesScreen> {
  static const Color _fondo = Color(0xFFF8F9FA);

  // Paleta de acento para el borde izquierdo de cada tarjeta (por índice)
  static const List<Color> _paleta = [
    Color(0xFF6B21A8), // Violeta
    Color(0xFF15803D), // Verde
    Color(0xFF1D4ED8), // Azul
    Color(0xFFEA580C), // Naranja
    Color(0xFFBE185D), // Rosa
    Color(0xFF0E7490), // Cian
  ];

  Color _colorTarjeta(int indice) => _paleta[indice % _paleta.length];

  IconData _iconoFuncion(String icono) {
    switch (icono) {
      case 'videocam':
        return Icons.videocam;
      case 'mic':
      case 'microphone':
        return Icons.mic;
      case 'door':
      case 'acomodador':
        return Icons.door_front_door;
      case 'cleaning':
      case 'limpieza':
        return Icons.cleaning_services;
      case 'platform':
        return Icons.mic_external_on;
      case 'music':
        return Icons.music_note;
      default:
        return Icons.apps;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
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
          context.t('eco2_asignaciones_titulo'),
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
      body: StreamBuilder<List<Funcion>>(
        stream: FuncionService.obtenerTodas(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(context.t('eco2_error_cargar')),
            );
          }
          final funciones = snap.data ?? [];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _crearOEditarFuncion(),
                    label: Text(context.t('eco2_crear_funcion')),
                  ),
                ),
              ),
              Expanded(
                child: funciones.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.t('eco2_sin_funciones'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: funciones.length,
                        itemBuilder: (ctx, i) => _buildFuncionCard(
                            ctx, funciones[i], i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFuncionCard(BuildContext context, Funcion funcion, int indice) {
    final color = _colorTarjeta(indice);
    return StreamBuilder<List<UsuarioEco2>>(
      stream: UsuarioEco2Service.obtenerPorRol(
          funcion.rolesRequeridos.isEmpty
              ? 'publicador'
              : funcion.rolesRequeridos.first),
      builder: (context, snapUsers) {
        final usuariosConRol = snapUsers.data ?? [];
        final encargado = usuariosConRol
            .where((u) => u.uid == funcion.gestorUid)
            .toList();
        final encargadoActual = encargado.isNotEmpty ? encargado.first : null;
        final auxiliares = usuariosConRol
            .where((u) =>
                u.funcionesAsignadas.contains(funcion.id) &&
                u.uid != funcion.gestorUid)
            .toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(color: color, width: 6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_iconoFuncion(funcion.icono),
                            color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          funcion.nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Color(0xFF0277BD), size: 20),
                        tooltip: context.t('eco2_editar'),
                        onPressed: () => _crearOEditarFuncion(funcion: funcion),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 20),
                        tooltip: context.t('eco2_eliminar'),
                        onPressed: () => _eliminarFuncion(context, funcion),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                // Encargado principal
                Text(
                  context.t('eco2_encargado_principal'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                if (encargadoActual != null)
                  _buildPersonaRow(
                      encargadoActual, color, true, funcion, context)
                else
                  _buildSinEncargado(context, funcion, color, usuariosConRol),
                const SizedBox(height: 12),
                // Auxiliares
                Text(
                  context.t('eco2_usuarios_asignados'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                if (auxiliares.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      context.t('eco2_sin_auxiliares'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  )
                else
                  ...auxiliares.map(
                      (u) => _buildAuxiliarRow(context, u, funcion, color)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(Icons.person_add_outlined,
                        color: color, size: 16),
                    style: TextButton.styleFrom(foregroundColor: color),
                    onPressed: () =>
                        _agregarAuxiliar(context, funcion, usuariosConRol, color),
                    label: Text(
                      context.t('eco2_liberar_agregar_usuario'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  Widget _buildPersonaRow(UsuarioEco2 usuario, Color color, bool esEncargado,
      Funcion funcion, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              usuario.nombre.isNotEmpty
                  ? usuario.nombre.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              usuario.nombre,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.remove_circle_outline,
                color: Colors.red.shade400, size: 18),
            tooltip: context.t('eco2_quitar'),
            onPressed: () async {
              await UsuarioEco2Service.removerFuncion(usuario.uid, funcion.id);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSinEncargado(BuildContext context, Funcion funcion, Color color,
      List<UsuarioEco2> usuariosConRol) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.t('eco2_sin_gestor'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (usuariosConRol.isNotEmpty)
            TextButton(
              onPressed: () => _seleccionarEncargado(
                  context, funcion, usuariosConRol, color),
              child: Text(
                context.t('eco2_seleccionar_encargado'),
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuxiliarRow(BuildContext context, UsuarioEco2 usuario,
      Funcion funcion, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Text(
              usuario.nombre.isNotEmpty
                  ? usuario.nombre.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(color: color, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(usuario.nombre,
                style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: Icon(Icons.remove_circle_outline,
                color: Colors.red.shade400, size: 16),
            tooltip: context.t('eco2_quitar'),
            onPressed: () async {
              await UsuarioEco2Service.removerFuncion(usuario.uid, funcion.id);
            },
          ),
        ],
      ),
    );
  }

  void _seleccionarEncargado(BuildContext context, Funcion funcion,
      List<UsuarioEco2> usuariosConRol, Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF1F8E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('eco2_seleccionar_encargado'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...usuariosConRol.map((u) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text(
                      u.nombre.isNotEmpty
                          ? u.nombre.substring(0, 1).toUpperCase()
                          : '?',
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(u.nombre),
                  subtitle: Text(
                    u.funcionesAsignadas.contains(funcion.id)
                        ? context.t('eco2_liberado')
                        : context.t('eco2_pendiente'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    // Asignar como gestor y liberar en la funcion
                    await UsuarioEco2Service.asignarFuncion(u.uid, funcion.id);
                    await FuncionService.asignarGestor(funcion.id, u.uid);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _agregarAuxiliar(BuildContext context, Funcion funcion,
      List<UsuarioEco2> usuariosConRol, Color color) {
    final noAsignados = usuariosConRol
        .where((u) =>
            !u.funcionesAsignadas.contains(funcion.id) &&
            u.uid != funcion.gestorUid)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF1F8E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('eco2_liberar_agregar_usuario'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (noAsignados.isEmpty)
                Text(
                  context.t('eco2_sin_usuarios_rol'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                )
              else
                ...noAsignados.map((u) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(
                        u.nombre.isNotEmpty
                            ? u.nombre.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(u.nombre),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () async {
                      await UsuarioEco2Service.asignarFuncion(
                          u.uid, funcion.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _crearOEditarFuncion({Funcion? funcion}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF1F8E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _FormFuncion(
          funcion: funcion,
          onGuardar: (datos) async {
            if (funcion == null) {
              await FuncionService.crear(Funcion(
                id: '',
                nombre: datos['nombre'] as String,
                descripcion: datos['descripcion'] as String,
                icono: datos['icono'] as String,
                color: datos['color'] as String,
                campos: datos['campos'] as List<CampoFuncion>,
                rolesRequeridos: datos['roles'] as List<String>,
                reuniones: datos['reuniones'] as List<String>,
              ));
            } else {
              await FuncionService.actualizar(funcion.id, {
                'nombre': datos['nombre'],
                'descripcion': datos['descripcion'],
                'icono': datos['icono'],
                'color': datos['color'],
                'campos': (datos['campos'] as List<CampoFuncion>)
                    .map((c) => c.toMap())
                    .toList(),
                'roles_requeridos': datos['roles'],
                'reuniones': datos['reuniones'],
              });
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _eliminarFuncion(BuildContext context, Funcion funcion) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t('eco2_eliminar')),
        content: Text(
          '${context.t('eco2_confirmar_eliminar')} "${funcion.nombre}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.t('cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              await FuncionService.eliminar(funcion.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(context.t('eco2_eliminar')),
          ),
        ],
      ),
    );
  }
}

class _FormFuncion extends StatefulWidget {
  final Funcion? funcion;
  final Future<void> Function(Map<String, dynamic> datos) onGuardar;

  const _FormFuncion({required this.funcion, required this.onGuardar});

  @override
  State<_FormFuncion> createState() => _FormFuncionState();
}

class _FormFuncionState extends State<_FormFuncion> {
  late TextEditingController _nombreCtrl;
  late TextEditingController _descCtrl;
  late String _icono;
  late String _color;
  late List<CampoFuncion> _campos;
  late List<String> _roles;
  late List<String> _reuniones;
  bool _guardando = false;

  final Map<String, IconData> _iconosDisponibles = {
    'videocam': Icons.videocam,
    'mic': Icons.mic,
    'door': Icons.door_front_door,
    'cleaning': Icons.cleaning_services,
    'platform': Icons.mic_external_on,
    'music': Icons.music_note,
  };

  static const List<String> _rolesDisponibles = [
    'audio_video',
    'acomodador',
    'limpieza',
    'microfono',
    'trabajador',
  ];

  @override
  void initState() {
    super.initState();
    final f = widget.funcion;
    _nombreCtrl = TextEditingController(text: f?.nombre ?? '');
    _descCtrl = TextEditingController(text: f?.descripcion ?? '');
    _icono = f?.icono ?? 'videocam';
    _color = f?.color ?? '#00695C';
    _campos = f != null ? List.from(f.campos) : [];
    _roles = f != null ? List.from(f.rolesRequeridos) : ['audio_video'];
    _reuniones = f != null ? List.from(f.reuniones) : ['entre_semana', 'fin_semana'];
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _agregarCampo() {
    setState(() {
      _campos.add(CampoFuncion(id: 'campo${_campos.length + 1}', label: '', icono: 'circle'));
    });
  }

  Widget _campoEditor(int i) {
    final campo = _campos[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: campo.label),
              decoration: InputDecoration(
                labelText: context.t('eco2_campo_label'),
                isDense: true,
              ),
              onChanged: (v) {
                _campos[i] = CampoFuncion(
                    id: campo.id, label: v, icono: campo.icono);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: () => setState(() => _campos.removeAt(i)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.funcion == null
                      ? context.t('eco2_crear_funcion')
                      : context.t('eco2_editar_funcion'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombreCtrl,
            decoration: InputDecoration(
              labelText: context.t('eco2_funcion_nombre'),
              hintText: 'Ej. Audio y Video / Acomodadores / Plataforma',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: context.t('eco2_funcion_descripcion'),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.t('eco2_icono'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _iconosDisponibles.entries.map((e) {
              final seleccionado = _icono == e.key;
              return InkWell(
                onTap: () => setState(() => _icono = e.key),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: seleccionado
                        ? Color(0xFF1B5E20).withValues(alpha: 0.15)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: seleccionado
                          ? const Color(0xFF1B5E20)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Icon(e.value,
                      color: seleccionado
                          ? const Color(0xFF1B5E20)
                          : Colors.grey.shade600),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            context.t('eco2_campo_label'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ..._campos.asMap().entries.map((e) => _campoEditor(e.key)),
          TextButton.icon(
            icon: const Icon(Icons.add),
            onPressed: _agregarCampo,
            label: Text(context.t('eco2_agregar_campo')),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            context.t('eco2_reuniones'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.t('eco2_entre_semana')),
                selected: _reuniones.contains('entre_semana'),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _reuniones.add('entre_semana');
                  } else {
                    _reuniones.remove('entre_semana');
                  }
                }),
              ),
              ChoiceChip(
                label: Text(context.t('eco2_fin_semana')),
                selected: _reuniones.contains('fin_semana'),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _reuniones.add('fin_semana');
                  } else {
                    _reuniones.remove('fin_semana');
                  }
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.t('eco2_roles_requeridos'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rolesDisponibles.map((rol) {
              final seleccionado = _roles.contains(rol);
              return ChoiceChip(
                label: Text(
                  _rolLabel(rol),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: seleccionado,
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _roles.add(rol);
                  } else {
                    _roles.remove(rol);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t('cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _guardando
                      ? null
                      : () async {
                          if (_nombreCtrl.text.trim().isEmpty) return;
                          setState(() => _guardando = true);
                          await widget.onGuardar({
                            'nombre': _nombreCtrl.text.trim(),
                            'descripcion': _descCtrl.text.trim(),
                            'icono': _icono,
                            'color': _color,
                            'campos': _campos
                                .where((c) => c.label.trim().isNotEmpty)
                                .toList(),
                            'roles': _roles,
                            'reuniones': _reuniones,
                          });
                          if (mounted) setState(() => _guardando = false);
                        },
                  child: Text(context.t('guardar')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rolLabel(String rol) {
    switch (rol) {
      case 'audio_video':
        return 'Audio y Video';
      case 'acomodador':
        return 'Acomodadores';
      case 'limpieza':
        return 'Limpieza';
      case 'microfono':
        return 'Micrófonos';
      case 'trabajador':
        return 'Trabajador';
      default:
        return rol;
    }
  }
}
