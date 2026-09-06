import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/usuario_eco2_service.dart';
import '../../data/familia_service.dart';
import '../../models/usuario_eco2_model.dart';

const Color _kVerde = Color(0xFF1B5E20);
const Color _kVerdeClaro = Color(0xFF43A047);
const Color _kAzul = Color(0xFF0277BD);
const Color _kNaranja = Color(0xFFE65100);

class Eco2UsuariosScreen extends StatefulWidget {
  const Eco2UsuariosScreen({super.key});

  @override
  State<Eco2UsuariosScreen> createState() => _Eco2UsuariosScreenState();
}

class _Eco2UsuariosScreenState extends State<Eco2UsuariosScreen> {
  String _busqueda = '';
  String _filtroRol = 'todos';

  Color _colorRol(String rol) {
    switch (rol) {
      case 'admin':
        return _kNaranja;
      case 'trabajador':
        return _kAzul;
      case 'limpieza':
        return const Color(0xFF6A1B9A);
      case 'audio_video':
        return const Color(0xFF00695C);
      case 'acomodador':
        return const Color(0xFFEF6C00);
      case 'microfono':
        return const Color(0xFF1565C0);
      default:
        return _kVerde;
    }
  }

  String _iconoRol(String rol) {
    switch (rol) {
      case 'admin':
        return 'A';
      case 'trabajador':
        return 'T';
      case 'limpieza':
        return 'L';
      case 'audio_video':
        return 'AV';
      case 'acomodador':
        return 'Ac';
      case 'microfono':
        return 'M';
      default:
        return 'P';
    }
  }

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
              colors: [_kVerde, _kVerdeClaro],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_usuarios_titulo'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.t('eco2_usuarios_buscar'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filtroChip('todos', context.t('eco2_usuarios_filtro_todos')),
                  const SizedBox(width: 8),
                  _filtroChip('admin', context.t('eco2_usuarios_rol_admin')),
                  const SizedBox(width: 8),
                  _filtroChip(
                      'trabajador', context.t('eco2_usuarios_rol_trabajador')),
                  const SizedBox(width: 8),
                  _filtroChip(
                      'publicador', context.t('eco2_usuarios_rol_publicador')),
                  const SizedBox(width: 8),
                  _filtroChip(
                      'limpieza', context.t('eco2_usuarios_rol_limpieza')),
                  const SizedBox(width: 8),
                  _filtroChip(
                      'audio_video', context.t('eco2_usuarios_rol_audio_video')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<UsuarioEco2>>(
              stream: UsuarioEco2Service.obtenerAprobados(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade300),
                        const SizedBox(height: 12),
                        Text(
                          context.t('eco2_usuarios_error_carga'),
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }
                final todos = snapshot.data ?? [];
                final filtrados = todos.where((u) {
                  final coincideBusqueda = _busqueda.isEmpty ||
                      u.nombre.toLowerCase().contains(_busqueda) ||
                      u.email.toLowerCase().contains(_busqueda);
                  final coincideRol = _filtroRol == 'todos' ||
                      u.roles.contains(_filtroRol);
                  return coincideBusqueda && coincideRol;
                }).toList();
                if (filtrados.isEmpty) {
                  return Center(
                    child: Text(
                      context.t('eco2_usuarios_sin_resultados'),
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtrados.length,
                  itemBuilder: (ctx, i) =>
                      _buildTarjetaUsuario(ctx, filtrados[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtroChip(String valor, String etiqueta) {
    final seleccionado = _filtroRol == valor;
    return FilterChip(
      label: Text(etiqueta, style: const TextStyle(fontSize: 11)),
      selected: seleccionado,
      selectedColor: _kVerde.withValues(alpha: 0.2),
      onSelected: (selected) {
        setState(() => _filtroRol = valor);
      },
    );
  }

  Widget _buildTarjetaUsuario(BuildContext context, UsuarioEco2 usuario) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _mostrarDialogoUsuario(context, usuario),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(
                left: BorderSide(color: _colorRol(usuario.roles.first), width: 4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _colorRol(usuario.roles.first).withValues(alpha: 0.15),
                child: Text(
                  _iconoRol(usuario.roles.first),
                  style: TextStyle(
                      color: _colorRol(usuario.roles.first),
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF263238),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      usuario.email,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: usuario.roles.map((rol) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _colorRol(rol).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _rolLabel(rol),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: _colorRol(rol),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rolLabel(String rol) {
    switch (rol) {
      case 'admin':
        return context.t('eco2_usuarios_rol_admin');
      case 'trabajador':
        return context.t('eco2_usuarios_rol_trabajador');
      case 'limpieza':
        return context.t('eco2_usuarios_rol_limpieza');
      case 'audio_video':
        return context.t('eco2_usuarios_rol_audio_video');
      case 'acomodador':
        return context.t('eco2_usuarios_rol_acomodador');
      case 'microfono':
        return context.t('eco2_usuarios_rol_microfono');
      default:
        return context.t('eco2_usuarios_rol_publicador');
    }
  }

  void _mostrarDialogoUsuario(BuildContext context, UsuarioEco2 usuario) {
    List<String> rolesSeleccionados = List.from(usuario.roles);
    String? familiaSeleccionada = usuario.familiaId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                usuario.nombre,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                usuario.email,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Text(
                context.t('eco2_usuarios_asignar_roles'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                context.t('eco2_usuarios_roles_hint'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: UsuarioEco2.rolesDisponibles.map((rol) {
                  final seleccionado = rolesSeleccionados.contains(rol);
                  final esPublicador = rol == 'publicador';
                  return FilterChip(
                    label: Text(_rolLabel(rol),
                        style: const TextStyle(fontSize: 12)),
                    selected: seleccionado,
                    selectedColor: _colorRol(rol).withValues(alpha: 0.2),
                    avatar: seleccionado
                        ? Icon(Icons.check, size: 16, color: _colorRol(rol))
                        : null,
                    onSelected: esPublicador
                        ? null
                        : (selected) {
                            setModalState(() {
                              if (selected) {
                                rolesSeleccionados.add(rol);
                              } else {
                                rolesSeleccionados.remove(rol);
                              }
                            });
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                context.t('eco2_usuarios_asignar_familia'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _familiasStream(),
                builder: (context, snap) {
                  final familias = snap.data ?? [];
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: familias.map((f) {
                      final seleccionada = familiaSeleccionada == f['id'];
                      return ChoiceChip(
                        label: Text(f['nombre'] as String,
                            style: const TextStyle(fontSize: 12)),
                        selected: seleccionada,
                        selectedColor: _kVerde.withValues(alpha: 0.2),
                        onSelected: (selected) {
                          setModalState(() {
                            familiaSeleccionada =
                                selected ? f['id'] as String : null;
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kVerde,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    try {
                      await UsuarioEco2Service.actualizarRoles(
                          usuario.uid, rolesSeleccionados);
                      if (familiaSeleccionada != null) {
                        await UsuarioEco2Service.asignarFamilia(
                            usuario.uid, familiaSeleccionada!);
                      } else {
                        await UsuarioEco2Service.removerDeFamilia(usuario.uid);
                      }
                      await Future.delayed(const Duration(milliseconds: 300));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.t('eco2_usuarios_roles_guardados')),
                            backgroundColor: _kVerde,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${context.t('eco2_usuarios_error_carga')}: $e'),
                            backgroundColor: Colors.red.shade700,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(context.t('guardar')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _familiasStream() {
    return FamiliaService.obtenerTodas().map((familias) => familias
        .map((f) => {'id': f.id, 'nombre': f.nombre})
        .toList());
  }
}
