import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/l10n/translation_service.dart';
import '../data/funcion_service.dart';
import '../data/recordatorio_service.dart';
import '../data/notificacion_service.dart';
import '../models/funcion_model.dart';
import '../models/usuario_eco2_model.dart';
import 'ecosistema2_mantenimiento.dart';
import 'familias/familias_screen.dart';
import 'usuarios/eco2_usuarios_screen.dart';
import 'reuniones/calendario_reuniones_screen.dart';
import 'designaciones/mis_designaciones_screen.dart';
import 'notificaciones/notificaciones_screen.dart';
import 'funciones/gestion_funcion_screen.dart';
import 'asignaciones/gestion_asignaciones_screen.dart';

const Color kEco2Verde = Color(0xFF1B5E20);
const Color kEco2VerdeClaro = Color(0xFF43A047);
const Color kEco2Azul = Color(0xFF0277BD);

class Ecosistema2HomeScreen extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  const Ecosistema2HomeScreen({super.key, required this.usuarioData});

  @override
  State<Ecosistema2HomeScreen> createState() => _Ecosistema2HomeScreenState();
}

class _Ecosistema2HomeScreenState extends State<Ecosistema2HomeScreen> {
  int _familias = 0;
  int _usuarios = 0;

  // El eco2 identifica a los usuarios por el doc.id de la colección 'usuarios'
  // (no por el uid de Firebase Auth). docId se inyecta al iniciar sesión.
  String get _uid =>
      (widget.usuarioData['docId'] as String?) ??
      (widget.usuarioData['uid'] as String? ??
          (widget.usuarioData['id'] as String?) ??
          '');
  bool esAdminEco2(UsuarioEco2? yo) =>
      (yo?.roles ?? const <String>[]).contains('admin');

  // Usuario actual reactivo (para ver roles/funciones asignadas en tiempo real)
  Stream<UsuarioEco2?> _streamUsuarioActual() {
    final uid = _uid;
    if (uid.isEmpty) return Stream<UsuarioEco2?>.value(null);
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .map((doc) =>
            doc.exists ? UsuarioEco2.fromMap(doc.id, doc.data()!) : null);
  }

  @override
  void initState() {
    super.initState();
    _cargarConteos();
    RecordatorioService.iniciar();
  }

  @override
  void dispose() {
    RecordatorioService.detener();
    super.dispose();
  }

  Future<void> _cargarConteos() async {
    try {
      final familiasSnap = await FirebaseFirestore.instance
          .collection('eco2_familias')
          .where('activa', isEqualTo: true)
          .count()
          .get();
      final usuariosSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('estado', isEqualTo: 'aprobado')
          .count()
          .get();
      if (mounted) {
        setState(() {
          _familias = familiasSnap.count ?? 0;
          _usuarios = usuariosSnap.count ?? 0;
        });
      }
    } catch (_) {}
  }

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pantalla),
    );
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
              colors: [kEco2Verde, kEco2Azul],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Colors.white),
                onPressed: () => _abrir(
                  context,
                  NotificacionesScreen(usuarioUid: _uid),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: StreamBuilder<int>(
                  stream: NotificacionService.contarNoLeidas(_uid),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(4),
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
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCabecera(context),
              const SizedBox(height: 20),
              Text(
                context.t('eco2_sections').toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.family_restroom_outlined,
                titulo: context.t('eco2_familias_titulo'),
                descripcion: context.t('eco2_familias_descripcion'),
                dato: _familias > 0 ? '$_familias' : null,
                color: const Color(0xFF6A1B9A),
                onTap: () => _abrir(
                  context,
                  FamiliasScreen(usuarioUid: _uid),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.calendar_month_outlined,
                titulo: context.t('eco2_reuniones_titulo'),
                descripcion: context.t('eco2_reuniones_descripcion'),
                dato: null,
                color: kEco2Verde,
                onTap: () => _abrir(
                  context,
                  const CalendarioReunionesScreen(),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.assignment_outlined,
                titulo: context.t('eco2_mis_designaciones'),
                descripcion: context.t('eco2_mis_designaciones_desc'),
                dato: null,
                color: kEco2Azul,
                onTap: () => _abrir(
                  context,
                  MisDesignacionesScreen(usuarioUid: _uid),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.t('eco2_gestion_titulo').toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Funcion>>(
                stream: FuncionService.obtenerTodas(),
                builder: (context, snapshot) {
                  final funciones = snapshot.data ?? [];

                  // Usuario actual reactivo para roles y funciones asignadas
                  return StreamBuilder<UsuarioEco2?>(
                    stream: _streamUsuarioActual(),
                    builder: (context, uSnap) {
                  final yo = uSnap.data;
                  final misRoles = yo?.roles ?? <String>[];
                  final esAdmin = esAdminEco2(yo);

                  // Admin: card central "Gestión de Asignaciones"
                  // (panel de control para crear funciones, liberar personal)
                  if (esAdmin) {
                    return Column(
                      children: [
                        _buildTarjetaAcceso(
                          context,
                          icono: Icons.person_outline,
                          titulo: context.t('eco2_usuarios_titulo'),
                          descripcion: context.t('eco2_usuarios_descripcion'),
                          dato: _usuarios > 0 ? '$_usuarios' : null,
                          color: const Color(0xFF0277BD),
                          onTap: () => _abrir(
                            context,
                            const Eco2UsuariosScreen(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTarjetaAcceso(
                          context,
                          icono: Icons.dashboard_customize_outlined,
                          titulo: context.t('eco2_asignaciones_titulo'),
                          descripcion:
                              context.t('eco2_asignaciones_desc'),
                          dato: funciones.isNotEmpty
                              ? '${funciones.length}'
                              : null,
                          color: const Color(0xFF1B5E20),
                          onTap: () => _abrir(
                            context,
                            GestionDeAsignacionesScreen(
                              usuarioUid: _uid,
                              esAdmin: esAdmin,
                            ),
                          ),
                        ),
                            const SizedBox(height: 12),
                            _buildTarjetaAcceso(
                              context,
                              icono: Icons.build_outlined,
                              titulo: context.t('eco2_section_maintenance'),
                              descripcion:
                                  context.t('eco2_section_maintenance_desc'),
                              dato: null,
                              color: Colors.deepOrange,
                              onTap: () => _abrir(
                                context,
                                const Ecosistema2MantenimientoScreen(),
                              ),
                            ),
                          ],
                        );
                      }

                      // Usuario con rol: ve las funciones donde tiene rol,
                      // distinguiendo liberadas vs pendientes
                      final misFunciones = funciones.where((f) {
                        return f.rolesRequeridos
                            .any((r) => misRoles.contains(r));
                      }).toList();

                      if (misFunciones.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.lock_outline,
                                      color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.t('eco2_pendiente_hint'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF263238),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.t('eco2_pendiente_aprobacion_desc'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          ...misFunciones.map((f) {
                            final color = _colorFuncion(f.color);
                            final liberado = yo?.funcionesAsignadas
                                    .contains(f.id) ??
                                false;
                            final puedeTrabajar = liberado;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildTarjetaAcceso(
                                context,
                                icono: _iconoFuncion(f.icono),
                                titulo:
                                    '${context.t("eco2_gestion")} ${f.nombre}',
                                descripcion: puedeTrabajar
                                    ? f.descripcion
                                    : context.t('eco2_pendiente_aprobacion'),
                                dato: !puedeTrabajar
                                    ? context.t('eco2_pendiente')
                                    : null,
                                color: puedeTrabajar ? color : Colors.grey,
                                onTap: () => _abrir(
                                  context,
                                  GestionFuncionScreen(
                                    funcionId: f.id,
                                    usuarioUid: _uid,
                                    esAdmin: esAdmin,
                                  ),
                                ),
                              ),
                            );

                          }),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  context.t('eco2_disclaimer'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFuncion(String colorHex) {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return kEco2Verde;
    }
  }

  IconData _iconoFuncion(String icono) {
    switch (icono) {
      case 'videocam':
        return Icons.videocam_outlined;
      case 'volume_up':
        return Icons.volume_up_outlined;
      case 'cleaning_services':
        return Icons.cleaning_services_outlined;
      case 'mic':
        return Icons.mic_outlined;
      case 'event_seat':
        return Icons.event_seat_outlined;
      default:
        return Icons.settings_outlined;
    }
  }

  Widget _buildCabecera(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kEco2Verde, kEco2VerdeClaro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kEco2Verde.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildLogoSalon(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('eco2_salon_titulo'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('eco2_salon_subtitulo'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSalon() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_work_outlined,
              color: kEco2Verde,
              size: 24,
            ),
            const SizedBox(height: 2),
            const Text(
              'JW',
              style: TextStyle(
                color: kEco2Verde,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaAcceso(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String descripcion,
    required String? dato,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF263238),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descripcion,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (dato != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dato,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
