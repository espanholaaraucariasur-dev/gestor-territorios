import 'dart:async';
import 'dart:convert';

// Flutter & Firebase
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

// Core Services & L10n
import 'package:araucaria_sur/core/services/navegacion_service.dart';
import 'package:araucaria_sur/core/services/notification_service.dart';
import 'package:araucaria_sur/core/services/auto_return_service.dart';
import 'package:araucaria_sur/core/services/offline_sync_service.dart';
import 'package:araucaria_sur/features/home/presentation/pages/admin/auditor_panel_page.dart';
import 'package:araucaria_sur/core/services/notificacion_service.dart';
import 'package:araucaria_sur/core/utils/transferencia_tarjeta.dart';
import '../../../../core/l10n/translation_service.dart';

// Feature: Auth & Ecosistema
import '../../../auth/presentation/pages/login_page.dart';
import '../../../ecosistema2/presentation/ecosistema2_home.dart';
import '../../../ecosistema2/presentation/sugerencias_screen.dart';

// Feature: Home Widgets
import '../widgets/notificaciones_widget.dart';

// Feature: Home Tabs, Subpáginas y Asistencia
import 'conductor/conductor_tab.dart';
import 'publicador/publicador_tab.dart';
import 'asistencia/contador.dart';

// Admin Tabs (Rutas absolutas)
import 'package:araucaria_sur/features/home/presentation/pages/admin/admin_territorios_tab.dart';
import 'package:araucaria_sur/features/home/presentation/pages/admin/admin_tab.dart';
import 'package:araucaria_sur/features/home/presentation/pages/admin/restauracion_mensual.dart';

class PantallaHomeLegacy extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  const PantallaHomeLegacy({super.key, required this.usuarioData});

  @override
  State<PantallaHomeLegacy> createState() => _PantallaHomeLegacyState();
}

class _PantallaHomeLegacyState extends State<PantallaHomeLegacy>
    with SingleTickerProviderStateMixin {
  int _indiceActual = 0;
  bool _modoAdminActivo = false;
  bool _modoAdminTerritoriosActivo = false;
  bool _modoConductorActivo = false;
  bool _eco2Visible = false;
  bool _esAdminEco2 = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Cierra el menú lateral SIN usar `Navigator.pop`.
  ///
  /// El `Drawer` del `Scaffold` no es una ruta: un `Navigator.pop()` genérico
  /// cerraba la ruta que estuviera encima (p. ej. la navegación minimizada),
  /// en vez del menú. Así el menú se cierra y la navegación sigue viva.
  void _cerrarDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  late TabController _tabControllerAdmin;
  String _usuarioEmail = '';
  bool _campanaEspecialActiva = false;
  String _nombreCampanaEspecial = '';
  bool _campanaGeneralActiva = false;
  String _anuncioGeneral = '';
  List<DocumentSnapshot> territoriosFiltrados = [];

  final TextEditingController _campanaEspecialController =
      TextEditingController();
  final TextEditingController _anuncioGeneralController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    OfflineSyncService.instance.observeFirestore();
    // 5 tabs: Estructura, Comunicación, Usuarios, Auditoría, Mantenimiento.
    // Debe coincidir con los 5 children del TabBarView de AdminTab; con 4
    // Flutter assertaba y `animateTo(4)` (Mantenimiento) crasheaba.
    _tabControllerAdmin = TabController(length: 5, vsync: this);
    _usuarioEmail = widget.usuarioData['email'] ?? '';
    _suscribirDestinos();
    // Initialize with safe defaults to prevent null errors
    _nombreCampanaEspecial = '';
    _anuncioGeneral = '';
    _cargarConfiguracionComunicacion();
    _procesarEnviosProgramados();
    _verificarTarjetasVencidas();
    final esAdminTerritorios =
        widget.usuarioData['es_admin_territorios'] ?? false;
    final esAdmin = widget.usuarioData['es_admin'] ?? false;
    if (esAdminTerritorios && !esAdmin) {
      _modoAdminTerritoriosActivo = true;
    }
    _verificarReinicioMensual();
    _cargarVisibilidadEcosistema2();
    // Verificar si hay acción pendiente de notificación
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _procesarPendingAction());
  }

  Future<void> _cargarVisibilidadEcosistema2() async {
    try {
      // Reactivo: actualiza la visibilidad en tiempo real cuando el admin
      // libera usuarios desde Mantenimiento (sin necesidad de reiniciar)
      FirebaseFirestore.instance
          .collection('configuracion')
          .doc('ecosistema2_visibilidad')
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        final ids = (doc.data()?['usuario_ids'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[];
        // El mantenimiento guarda los ID de documento de la colección 'usuarios'.
        // docId es el id del documento; uid es el UID de Firebase Auth.
        final idUsuario = (widget.usuarioData['docId'] as String?) ??
            (widget.usuarioData['uid'] as String?);
        if (idUsuario == null) return;
        final visible = ids.contains(idUsuario);
        if (visible != _eco2Visible) setState(() => _eco2Visible = visible);
      });

      // Admin del eco2 = el rol propio 'admin' en el campo `roles`
      // (no hereda es_admin del ecosistema primario).
      final docId = widget.usuarioData['docId'] as String?;
      if (docId != null && docId.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('usuarios')
            .doc(docId)
            .snapshots()
            .listen((snap) {
          if (!mounted) return;
          final roles =
              (snap.data()?['roles'] as List?)?.whereType<String>().toList() ??
                  const <String>[];
          final esAdminEco2 = roles.contains('admin');
          if (esAdminEco2 != _esAdminEco2) {
            setState(() => _esAdminEco2 = esAdminEco2);
          }
        });
      }
    } catch (_) {}
  }

  /// Suscripción a los destinos encolados por las notificaciones.
  StreamSubscription<DestinoNotificacion>? _subDestinos;

  void _suscribirDestinos() {
    _subDestinos = NavegacionService.destinos.listen((destino) {
      if (!mounted) return;
      _ejecutarDestino(destino);
    });
  }

  void _procesarPendingAction() {
    // Compatibilidad con el productor viejo (push del sistema).
    final antiguo = NotificationService.getPendingAction();
    if (antiguo != null) {
      final destino = switch (antiguo) {
        'usuarios_pendientes' => Pantallas.usuariosPendientes,
        'solicitudes_localizador' => Pantallas.solicitudesDirecciones,
        _ => null,
      };
      if (destino != null) _ejecutarDestino(DestinoNotificacion(destino));
      return;
    }

    // Destinos encolados desde la lista de notificaciones.
    final pendiente = NavegacionService.consumirPendiente();
    if (pendiente != null && mounted) _ejecutarDestino(pendiente);
  }

  /// Activa el modo correspondiente y salta a la pestaña destino.
  ///
  /// Importante: hay que activar el MODO primero, porque las pantallas viven
  /// dentro de un `IndexedStack` que solo construye el modo activo. Sin esto,
  /// `animateTo` no hacia nada (AdminTab ni siquiera estaba montado).
  void _ejecutarDestino(DestinoNotificacion destino) {
    if (!mounted) return;
    if (!NavegacionService.permitido(destino.pantalla, widget.usuarioData)) {
      _aviso('No tienes permisos para abrir esa notificacion', Colors.orange);
      return;
    }

    switch (destino.pantalla) {
      case Pantallas.usuariosPendientes:
        _irAAdmin(2); // 2 = Usuarios
        _aviso('Revisa los usuarios pendientes de aprobacion', Colors.orange,
            icono: '👤');
        break;

      case Pantallas.solicitudesDirecciones:
        _irAAdmin(1); // 1 = Comunicacion
        _aviso('Revisa las direcciones enviadas', Colors.blue, icono: '📍');
        break;

      case Pantallas.auditorDireccionesNuevas:
        // AuditorPanelPage tiene su propio TabController interno, asi que se
        // le deja indicado el indice antes de que se monte.
        AuditorPanelPage.solicitarTab(1);
        _irAAdmin(3); // 3 = Auditoria
        _aviso('Revisa las direcciones nuevas por auditar', Colors.teal,
            icono: '🗺️');
        break;

      case Pantallas.sugerencias:
        _irAAdmin(1); // 1 = Comunicacion
        _aviso('Revisa las sugerencias recibidas', Colors.amber, icono: '💡');
        break;

      case Pantallas.misTarjetas:
        // El modo publicador es la vista por defecto: basta con apagar los
        // modos de administracion.
        setState(() {
          _modoAdminActivo = false;
          _modoAdminTerritoriosActivo = false;
          _modoConductorActivo = false;
          _indiceActual = 0;
        });
        _aviso('Aqui estan tus tarjetas', Colors.green, icono: '💳');
        break;

      default:
        break;
    }
  }

  /// Entra al modo admin y salta a la pestaña indicada.
  void _irAAdmin(int indiceTab) {
    setState(() {
      _modoAdminActivo = true;
      _modoAdminTerritoriosActivo = false;
      _modoConductorActivo = false;
      _indiceActual = 0;
    });
    // El controller ya existe; al montar AdminTab se pintara en este indice.
    _tabControllerAdmin.animateTo(indiceTab);
  }

  void _aviso(String texto, Color color, {String? icono}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(icono == null ? texto : '$icono $texto'),
        backgroundColor: color,
      ),
    );
  }

  @override
  void dispose() {
    OfflineSyncService.instance.stopObservingFirestore();
    _subDestinos?.cancel();
    _tabControllerAdmin.dispose();
    _campanaEspecialController.dispose();
    _anuncioGeneralController.dispose();
    super.dispose();
  }

  void _cerrarSesion() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión en Firebase: $e');
    }
    try {
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'biometric_email');
      await storage.delete(key: 'biometric_pass');
    } catch (e) {
      debugPrint('Error al limpiar credenciales biométricas: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PantallaAccesoLegacy()),
      );
    }
  }

  void _mostrarNotificaciones() {
    NotificacionesDialog.mostrar(context, widget.usuarioData);
  }

  void _cargarConfiguracionComunicacion() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('configuraciones')
          .doc('comunicacion')
          .get();
      if (!mounted) return;
      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        _campanaEspecialController.text = data['nombre_campana_especial'] ?? '';
        _anuncioGeneralController.text = data['anuncio_general'] ?? '';
        setState(() {
          _campanaEspecialActiva = data['campana_especial_activa'] ?? false;
          _nombreCampanaEspecial = data['nombre_campana_especial'] ?? '';
          _campanaGeneralActiva = data['campana_general_activa'] ?? false;
          _anuncioGeneral = data['anuncio_general'] ?? '';
        });
      } else {}
    } catch (_) {
      if (!mounted) return;
    }
  }

  // ─────────────────────────────────────────────────────────
  // DRAWER HELPER METHODS
  // ─────────────────────────────────────────────────────────

  Widget _idiomaChip(String idioma) {
    final activo = context.currentLanguage == idioma;
    return GestureDetector(
      onTap: () {
        context.changeLanguage(idioma);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: activo ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          idioma,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: activo ? const Color(0xFF1B5E20) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _drawerModo({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: activo ? color.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: activo ? Border.all(color: color.withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: activo ? color : const Color(0xFF263238),
                      )),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            if (activo)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    String? subtitle,
    required Color color,
    bool activo = false,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: activo ? color.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: activo ? color : Colors.grey[600], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            activo ? FontWeight.w600 : FontWeight.normal,
                        color: activo ? color : const Color(0xFF263238),
                      )),
                  if (subtitle != null)
                    Text(subtitle,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esConductor = widget.usuarioData['es_conductor'] ?? false;
    final esAdmin = widget.usuarioData['es_admin'] ?? false;
    final esAcomodador = widget.usuarioData['es_acomodador'] ?? false;
    final esAdminTerritorios =
        widget.usuarioData['es_admin_territorios'] ?? false;
    final nombre = widget.usuarioData['nombre'] ?? 'Hermano';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF6F8F5),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header verde ─────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            (widget.usuarioData['nombre'] ?? 'U')
                                .toString()
                                .trim()
                                .split(' ')
                                .take(2)
                                .map((p) => p[0].toUpperCase())
                                .join(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white70, size: 20),
                          onPressed: () => _cerrarDrawer(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.usuarioData['nombre'] ?? 'Usuario',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      widget.usuarioData['email'] ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.language,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          context.t('language'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        _idiomaChip('ES'),
                        const SizedBox(width: 6),
                        _idiomaChip('PT'),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Contenido ────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Notificaciones
                      _drawerItem(
                        icon: Icons.notifications_none_outlined,
                        label: context.t('notifications'),
                        subtitle: context.t('last_alerts'),
                        color: const Color(0xFF1B5E20),
                        trailing: StreamBuilder<int>(
                          stream: NotificacionService.streamConteo(
                              NotificacionService.perfilDesdeUsuario(
                                  widget.usuarioData)),
                          builder: (context, snap) {
                            final count = snap.data ?? 0;
                            if (count == 0) {
                              return const Icon(Icons.chevron_right,
                                  color: Colors.grey, size: 18);
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                        onTap: () {
                          _cerrarDrawer();
                          _mostrarNotificaciones();
                        },
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                        child: Text(
                          context.t('menu_modes'),
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                      if (esAdmin)
                        _drawerModo(
                          icon: Icons.admin_panel_settings_outlined,
                          label: context.t('mode_admin'),
                          subtitle: context.t('full_access'),
                          color: Colors.red,
                          activo: _modoAdminActivo,
                          onTap: () {
                            setState(() {
                              _modoAdminActivo = true;
                              _modoAdminTerritoriosActivo = false;
                              _modoConductorActivo = false;
                              _indiceActual = 0;
                            });
                            _cerrarDrawer();
                          },
                        ),

                      if (esAdminTerritorios)
                        _drawerModo(
                          icon: Icons.map_outlined,
                          label: context.t('mode_territories'),
                          subtitle: context.t('management_sending'),
                          color: Colors.purple,
                          activo: _modoAdminTerritoriosActivo,
                          onTap: () {
                            setState(() {
                              _modoAdminTerritoriosActivo = true;
                              _modoAdminActivo = false;
                              _modoConductorActivo = false;
                              _indiceActual = 0;
                            });
                            _cerrarDrawer();
                          },
                        ),

                      if (esConductor)
                        _drawerModo(
                          icon: Icons.groups_outlined,
                          label: context.t('mode_driver'),
                          subtitle: context.t('preaching_group'),
                          color: const Color(0xFF1B5E20),
                          activo: _modoConductorActivo,
                          onTap: () {
                            setState(() {
                              _modoConductorActivo = true;
                              _modoAdminActivo = false;
                              _modoAdminTerritoriosActivo = false;
                              _indiceActual = 0;
                            });
                            _cerrarDrawer();
                          },
                        ),

                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                        child: Text(
                          'VISTAS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                      _drawerItem(
                        icon: Icons.home_outlined,
                        label: context.t('home'),
                        color: const Color(0xFF1B5E20),
                        activo: _indiceActual == 0 &&
                            !_modoAdminActivo &&
                            !_modoAdminTerritoriosActivo &&
                            !_modoConductorActivo,
                        onTap: () {
                          setState(() {
                            _modoAdminActivo = false;
                            _modoAdminTerritoriosActivo = false;
                            _modoConductorActivo = false;
                            _indiceActual = 0;
                          });
                          _cerrarDrawer();
                        },
                      ),

                      if (esAcomodador || esAdmin)
                        _drawerItem(
                          icon: Icons.calculate_outlined,
                          label: context.t('attendance_counter'),
                          color: const Color(0xFF0277BD),
                          onTap: () {
                            setState(() {
                              _modoAdminActivo = false;
                              _modoAdminTerritoriosActivo = false;
                              _modoConductorActivo = false;
                            });
                            _cerrarDrawer();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AsistenciaCounterScreen(
                                  nombreUsuario:
                                      widget.usuarioData['nombre']?.toString(),
                                ),
                              ),
                            );
                          },
                        ),

                      if (_eco2Visible || _esAdminEco2)
                        _drawerItem(
                          icon: Icons.dashboard_outlined,
                          label: context.t('eco2_title'),
                          color: const Color(0xFF0277BD),
                          onTap: () {
                            setState(() {
                              _modoAdminActivo = false;
                              _modoAdminTerritoriosActivo = false;
                              _modoConductorActivo = false;
                            });
                            _cerrarDrawer();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Ecosistema2HomeScreen(
                                  usuarioData: widget.usuarioData,
                                ),
                              ),
                            );
                          },
                        ),

                      _drawerItem(
                        icon: Icons.lightbulb_outline,
                        label: context.t('sugerencias_title'),
                        color: const Color(0xFFF9A825),
                        onTap: () {
                          setState(() {
                            _modoAdminActivo = false;
                            _modoAdminTerritoriosActivo = false;
                            _modoConductorActivo = false;
                          });
                          _cerrarDrawer();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SugerenciasScreen(
                                usuarioEmail: _usuarioEmail,
                                usuarioNombre:
                                    widget.usuarioData['nombre']?.toString() ??
                                        '',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── Cerrar sesión ─────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.red, size: 18),
                  label: Text(
                    context.t('logout'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  onPressed: () {
                    _cerrarDrawer();
                    _cerrarSesion();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Column(
          children: [
            Text(
              context.t('app_name'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              context.t('app_subtitle'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Badge de notificaciones
          NotificacionesBadge(usuarioData: widget.usuarioData),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _indiceActual,
        children: [
          _buildVistaHome(nombre, esConductor, esAdmin, esAdminTerritorios),
          _buildVistaTarjetas(),
        ],
      ),
      floatingActionButton: !_modoAdminActivo &&
              !_modoAdminTerritoriosActivo &&
              !_modoConductorActivo
          ? null
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildVistaHome(
    String nombre,
    bool esConductor,
    bool esAdmin,
    bool esAdminTerritorios,
  ) {
    if (_modoAdminActivo) {
      return SizedBox.expand(child: _buildContenidoAdmin());
    }
    if (_modoAdminTerritoriosActivo) {
      return SizedBox.expand(child: _buildContenidoAdminTerritorios());
    }
    if (_modoConductorActivo) {
      return SizedBox.expand(child: _buildContenidoConductor());
    }
    return SizedBox.expand(child: _buildContenidoPublicador());
  }

  Widget _buildContenidoAdmin() {
    return AdminTab(
      usuarioData: widget.usuarioData,
      tabController: _tabControllerAdmin,
    );
  }

  // Method to format scheduled date for display

  // Method to cancel scheduled send

  Future<void> startCsvUpload(Function(String) onFileSelected) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        final fileContent = utf8.decode(bytes);
        onFileSelected(fileContent);
      } else {
        // User cancelled the picker
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se seleccionó ningún archivo')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al leer el archivo: $e')),
        );
      }
    }
  }

  Widget _buildVistaTarjetas() {
    return _buildContenidoPublicador();
  }

  Widget _buildContenidoAdminTerritorios() {
    return AdminTerritoriosTab(
      usuarioData: widget.usuarioData,
    );
  }

  void _verificarTarjetasVencidas() async {
    final ahora = DateTime.now();
    final limite = ahora.subtract(const Duration(hours: 3));

    final snap = await FirebaseFirestore.instance
        .collectionGroup('tarjetas')
        .where('asignado_a', isGreaterThan: '')
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final tomadoEn = (data['tomado_en'] as Timestamp?)?.toDate();
      if (tomadoEn != null && tomadoEn.isBefore(limite)) {
        // alerta a los 10 min antes = 2h50min
        await doc.reference.update({
          'alerta_vencimiento': true,
          'asignado_a': '',
          'disponible_para_publicadores': true,
          'tomado_en': null,
        });
      }
    }
  }

  Widget _buildContenidoConductor() {
    return ConductorTab(
      usuarioData: widget.usuarioData,
      usuarioEmail: _usuarioEmail,
      onSolicitarTerritorio: _mostrarDialogoSolicitarTerritorioConductor,
    );
  }

  Widget _buildContenidoPublicador() {
    return PublicadorTab(
      usuarioData: widget.usuarioData,
      usuarioEmail: _usuarioEmail,
      campanaEspecialActiva: _campanaEspecialActiva,
      nombreCampanaEspecial: _nombreCampanaEspecial,
      campanaGeneralActiva: _campanaGeneralActiva,
      anuncioGeneral: _anuncioGeneral,
      onSolicitarTerritorio: _mostrarDialogoSolicitarTerritorioPublicador, // ✅
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────

  // ── _mostrarDialogoSolicitarTerritorioConductor ──
  Future<void> _mostrarDialogoSolicitarTerritorioConductor() async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Solicitar tarjeta',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Text(
                'Selecciona un territorio para ver sus tarjetas disponibles',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text('No hay territorios.',
                                  style: TextStyle(color: Colors.grey)),
                            );
                          }
                          return ListView.builder(
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, i) {
                              final terDoc = snapshot.data!.docs[i];
                              final terData =
                                  terDoc.data() as Map<String, dynamic>;
                              final terNombre = terData['nombre'] ?? terDoc.id;
                              if (terDoc.id == 'campanas')
                                return const SizedBox.shrink();
                              if (terData['tipo'] == 'base')
                                return const SizedBox.shrink();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ExpansionTile(
                                  leading: const Icon(Icons.folder,
                                      color: Color(0xFF1B5E20)),
                                  title: Text(terNombre,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle:
                                      const Text('Toca para ver tarjetas'),
                                  children: [
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(terDoc.id)
                                          .collection('tarjetas')
                                          .snapshots(),
                                      builder: (context, tarjetasSnap) {
                                        if (tarjetasSnap.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator()));
                                        }
                                        // Conductor ve TODAS las tarjetas del territorio,
                                        // incluidas las que están con un publicador u otro
                                        // conductor. Se filtra `bloqueado` en memoria para
                                        // no perder tarjetas sin ese campo.
                                        final tarjetas =
                                            (tarjetasSnap.data?.docs ?? [])
                                                .where((doc) {
                                          final d = doc.data()
                                              as Map<String, dynamic>;
                                          return d['bloqueado'] != true;
                                        }).toList();
                                        if (tarjetas.isEmpty) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text(
                                                'No hay tarjetas disponibles.',
                                                style: TextStyle(
                                                    color: Colors.grey)),
                                          );
                                        }
                                        return Column(
                                          children: tarjetas.map((tarjetaDoc) {
                                            final data = tarjetaDoc.data()
                                                as Map<String, dynamic>;
                                            final tarjetaNombre =
                                                data['nombre'] ?? tarjetaDoc.id;
                                            final soloConductores =
                                                (data['solo_conductores']
                                                        as bool?) ??
                                                    false;
                                            final nombreConductor =
                                                (widget.usuarioData['nombre'] ??
                                                        '')
                                                    .toString();
                                            return StreamBuilder<QuerySnapshot>(
                                              stream: FirebaseFirestore.instance
                                                  .collection('configuracion')
                                                  .where('activa',
                                                      isEqualTo: true)
                                                  .snapshots(),
                                              builder: (context, campSnap) {
                                                final campanasActivas = (campSnap
                                                            .data?.docs ??
                                                        [])
                                                    .map((d) => (((d.data() as Map<
                                                                        String,
                                                                        dynamic>)[
                                                                    'nombre']
                                                                as String?) ??
                                                            '')
                                                        .trim())
                                                    .where((n) => n.isNotEmpty)
                                                    .toList();
                                                final hayCampanasActivas =
                                                    campanasActivas.isNotEmpty;
                                                return StreamBuilder<
                                                    QuerySnapshot>(
                                                  stream: FirebaseFirestore
                                                      .instance
                                                      .collection(
                                                          'direcciones_globales')
                                                      .where('tarjeta_id',
                                                          isEqualTo:
                                                              tarjetaDoc.id)
                                                      .snapshots(),
                                                  builder:
                                                      (context, dirSnapshot) {
                                                    final dirs = dirSnapshot
                                                            .data?.docs ??
                                                        [];
                                                    final cantDir = dirs.length;
                                                    // Direcciones que aún NO tienen entregada
                                                    // alguna de las campañas activas.
                                                    final campanaPendientes =
                                                        dirs.where((d) {
                                                      final dd = (d.data()
                                                              as Map<String,
                                                                  dynamic>?) ??
                                                          const {};
                                                      for (final n
                                                          in campanasActivas) {
                                                        if (dd['campana_invitacion_$n'] !=
                                                            true) return true;
                                                      }
                                                      return false;
                                                    }).length;
                                                    // Direcciones de la tarjeta que todavía no
                                                    // están completadas (predicadas). Es el
                                                    // criterio para poder tomarla: si falta al
                                                    // menos una, el conductor puede tomarla.
                                                    final dirsPendientes =
                                                        dirs.where((d) {
                                                      final dd = (d.data()
                                                              as Map<String,
                                                                  dynamic>?) ??
                                                          const {};
                                                      final est = (dd['estado']
                                                              as String?) ??
                                                          '';
                                                      if (est == 'removida')
                                                        return false;
                                                      final hecha = dd[
                                                                  'predicado'] ==
                                                              true ||
                                                          (dd['estado_predicacion']
                                                                  as String?) ==
                                                              'completada';
                                                      return !hecha;
                                                    }).length;
                                                    final enviadoA =
                                                        (data['enviado_a']
                                                                as String?) ??
                                                            '';
                                                    final conductorEmail =
                                                        (data['conductor_email']
                                                                as String?) ??
                                                            '';
                                                    final asignadoA =
                                                        (data['asignado_a']
                                                                as String?) ??
                                                            '';
                                                    final esMia = enviadoA ==
                                                            _usuarioEmail ||
                                                        conductorEmail ==
                                                            _usuarioEmail;
                                                    // Se puede tomar si aún le falta alguna
                                                    // dirección por completar. Estar con otra
                                                    // persona ya NO impide tomarla (se avisa y
                                                    // se pide confirmación de transferencia).
                                                    String? motivo;
                                                    if (esMia) {
                                                      motivo = 'Ya la tienes';
                                                    } else if (cantDir == 0) {
                                                      motivo =
                                                          'Sin direcciones';
                                                    } else if (dirsPendientes ==
                                                        0) {
                                                      motivo =
                                                          'Tarjeta completa';
                                                    }
                                                    final conOtro = !esMia &&
                                                        (asignadoA.isNotEmpty ||
                                                            conductorEmail
                                                                .isNotEmpty);
                                                    return ExpansionTile(
                                                      tilePadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 16),
                                                      leading: Icon(
                                                        motivo != null
                                                            ? Icons.lock
                                                            : Icons.lock_open,
                                                        color: motivo != null
                                                            ? Colors.grey
                                                            : const Color(
                                                                0xFF1B5E20),
                                                      ),
                                                      title: Text(tarjetaNombre,
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              color: motivo !=
                                                                      null
                                                                  ? Colors.grey
                                                                  : Colors
                                                                      .black)),
                                                      subtitle: Text(
                                                        [
                                                          '$cantDir dir',
                                                          if (dirsPendientes >
                                                              0)
                                                            '$dirsPendientes por completar',
                                                          if (hayCampanasActivas)
                                                            'Campaña: $campanaPendientes sin entregar',
                                                          if (conOtro)
                                                            'Con: ${(data['enviado_nombre'] as String?)?.isNotEmpty == true ? data['enviado_nombre'] : 'otro'}',
                                                          if (soloConductores)
                                                            'Solo conductores',
                                                        ].join(' · '),
                                                        style: const TextStyle(
                                                            fontSize: 11),
                                                      ),
                                                      childrenPadding:
                                                          const EdgeInsets.only(
                                                              left: 16,
                                                              right: 16),
                                                      children: [
                                                        ...dirs.map((d) =>
                                                            _itemDireccion(
                                                                d.data() as Map<
                                                                    String,
                                                                    dynamic>)),
                                                        const SizedBox(
                                                            height: 6),
                                                        if (motivo == null)
                                                          SizedBox(
                                                            width:
                                                                double.infinity,
                                                            height: 40,
                                                            child:
                                                                ElevatedButton(
                                                              onPressed:
                                                                  () async {
                                                                final limite =
                                                                    await AutoReturnService
                                                                        .obtenerTiempoLimite();
                                                                // Dueño real: publicador
                                                                // (`asignado_a`) o conductor
                                                                // (`enviado_nombre` con
                                                                // `conductor_email`).
                                                                final duenoPublicador =
                                                                    TransferenciaTarjeta.leerDuenoActual(
                                                                        data,
                                                                        vencidoTras:
                                                                            limite);
                                                                final conductorOwner = (conductorEmail
                                                                            .isNotEmpty &&
                                                                        conductorEmail !=
                                                                            _usuarioEmail)
                                                                    ? ((data['enviado_nombre']
                                                                            as String?) ??
                                                                        '')
                                                                    : '';
                                                                final dueno = duenoPublicador ??
                                                                    (conductorOwner
                                                                            .isNotEmpty
                                                                        ? conductorOwner
                                                                        : null);
                                                                if (dueno !=
                                                                    null) {
                                                                  final ok =
                                                                      await TransferenciaTarjeta
                                                                          .confirmarTransferencia(
                                                                    context:
                                                                        context,
                                                                    tarjetaNombre:
                                                                        tarjetaNombre,
                                                                    duenoActual:
                                                                        dueno,
                                                                    nuevoDueno:
                                                                        nombreConductor,
                                                                  );
                                                                  if (!ok)
                                                                    return;
                                                                }
                                                                if (!context
                                                                    .mounted)
                                                                  return;
                                                                Navigator.pop(
                                                                    context);
                                                                await _asignarTarjetaAConductor(
                                                                  terDoc.id,
                                                                  tarjetaDoc.id,
                                                                  tarjetaNombre,
                                                                  duenoAnterior:
                                                                      dueno,
                                                                );
                                                              },
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFF1B5E20),
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                              child: const Text(
                                                                  'Tomar tarjeta'),
                                                            ),
                                                          )
                                                        else
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical:
                                                                        8),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors.grey
                                                                  .shade200,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                            child: Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                const Icon(
                                                                    Icons.block,
                                                                    size: 14,
                                                                    color: Colors
                                                                        .grey),
                                                                const SizedBox(
                                                                    width: 6),
                                                                Flexible(
                                                                  child: Text(
                                                                    'No disponible: $motivo',
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        color: Colors
                                                                            .grey),
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemDireccion(Map<String, dynamic> d) {
    final calle = (d['calle'] as String?) ?? '';
    final numero = (d['numero'] as String?) ?? '';
    final complemento = (d['complemento'] as String?) ?? '';
    final texto = [
      if (numero.isNotEmpty) numero,
      if (calle.isNotEmpty) calle,
      if (complemento.isNotEmpty) complemento,
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          texto.isNotEmpty ? texto : calle,
          style: const TextStyle(fontSize: 11.5, color: Colors.black87),
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoSolicitarTerritorioPublicador() async {
    final especiales = ['removidas', 'estadisticas', 'campanas'];

    // Carga los territorios SIN orderBy (evita que Firestore excluya
    // documentos con caracteres especiales como Ç, tildes, ñ)
    final snap =
        await FirebaseFirestore.instance.collection('territorios').get();

    // Solo excluir IDs especiales del sistema — NO filtrar por solo_conductores
    // (ese campo aplica a tarjetas individuales, no a territorios enteros)
    final territorios = snap.docs.where((doc) {
      return !especiales.contains(doc.id) && doc.data()['tipo'] != 'base';
    }).toList();

    // Ordenar en memoria
    territorios.sort((a, b) {
      final na = (a.data()['nombre'] as String? ?? a.id).toLowerCase();
      final nb = (b.data()['nombre'] as String? ?? b.id).toLowerCase();
      return na.compareTo(nb);
    });

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Solicitar tarjeta',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Text(
                    'Selecciona un territorio para ver sus tarjetas disponibles',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                // ── Lista ────────────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: territorios.length,
                    itemBuilder: (ctx2, index) {
                      final terDoc = territorios[index];
                      final terData = terDoc.data();
                      final terNombre =
                          (terData['nombre'] as String?) ?? terDoc.id;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          leading: const Icon(Icons.folder,
                              color: Color(0xFF1B5E20)),
                          title: Text(terNombre,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Toca para ver tarjetas'),
                          children: [
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terDoc.id)
                                  .collection('tarjetas')
                                  .where('bloqueado', isEqualTo: false)
                                  .snapshots(),
                              builder: (context, tarjetasSnap) {
                                if (tarjetasSnap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  );
                                }

                                // Excluir tarjetas solo para conductores
                                final tarjetas = (tarjetasSnap.data?.docs ?? [])
                                    .where((doc) {
                                  final d = doc.data() as Map<String, dynamic>;
                                  return !((d['solo_conductores'] as bool?) ??
                                      false);
                                }).toList();

                                if (tarjetas.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No hay tarjetas disponibles.',
                                        style: TextStyle(color: Colors.grey)),
                                  );
                                }

                                return Column(
                                  children: tarjetas.map((tarjetaDoc) {
                                    final data = tarjetaDoc.data()
                                        as Map<String, dynamic>;
                                    final tarjetaNombre =
                                        data['nombre'] ?? tarjetaDoc.id;

                                    // Detectar si está con conductor
                                    final conductorEmail =
                                        data['conductor_email']?.toString() ??
                                            '';
                                    final enviadoTipo =
                                        data['enviado_tipo']?.toString() ?? '';
                                    final asignadoA =
                                        data['asignado_a']?.toString() ?? '';
                                    final estaConConductor =
                                        conductorEmail.isNotEmpty ||
                                            enviadoTipo == 'conductor' ||
                                            (asignadoA.isNotEmpty &&
                                                enviadoTipo != 'publicador' &&
                                                enviadoTipo.isNotEmpty);
                                    final enviadoNombre =
                                        data['enviado_nombre']?.toString() ??
                                            '';

                                    return StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaDoc.id)
                                          .snapshots(),
                                      builder: (context, dirSnapshot) {
                                        final cantDir =
                                            dirSnapshot.data?.docs.length ?? 0;

                                        // Con conductor → gris
                                        if (estaConConductor) {
                                          final dirs =
                                              dirSnapshot.data?.docs ?? [];
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.grey.shade300),
                                            ),
                                            child: ExpansionTile(
                                              tilePadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              dense: true,
                                              leading: const Icon(Icons.lock,
                                                  color: Colors.grey),
                                              title: Text(tarjetaNombre,
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                              subtitle: Text(
                                                enviadoNombre.isNotEmpty
                                                    ? '🚚 Con conductor: $enviadoNombre'
                                                    : '🚚 Con conductor',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11),
                                              ),
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade300,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text('No disp.',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey)),
                                              ),
                                              children: [
                                                ...dirs.map((d) =>
                                                    _itemDireccion(d.data()
                                                        as Map<String,
                                                            dynamic>)),
                                              ],
                                            ),
                                          );
                                        }

                                        // Completada → solo informativo (solo admin territorios puede reactivar)
                                        if (data['completada'] == true) {
                                          final dirs =
                                              dirSnapshot.data?.docs ?? [];
                                          return ExpansionTile(
                                            tilePadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16),
                                            leading: const Icon(Icons.lock,
                                                color: Colors.grey),
                                            title: Text(tarjetaNombre,
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 13)),
                                            subtitle: const Text(
                                                '✅ Completada este mes',
                                                style: TextStyle(fontSize: 11)),
                                            trailing: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text('No disp.',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey)),
                                            ),
                                            children: [
                                              ...dirs.map((d) => _itemDireccion(
                                                  d.data()
                                                      as Map<String, dynamic>)),
                                            ],
                                          );
                                        }

                                        // Disponible → Tomar
                                        final dirs =
                                            dirSnapshot.data?.docs ?? [];
                                        return ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                          leading: const Icon(Icons.lock_open,
                                              color: Color(0xFF1B5E20)),
                                          title: Text(tarjetaNombre,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          subtitle: Text('$cantDir direcciones',
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                  left: 16, right: 16),
                                          children: [
                                            ...dirs.map((d) => _itemDireccion(
                                                d.data()
                                                    as Map<String, dynamic>)),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 40,
                                              child: ElevatedButton(
                                                onPressed: cantDir > 0
                                                    ? () async {
                                                        Navigator.pop(context);
                                                        await _asignarTarjetaAPublicador(
                                                          terDoc.id,
                                                          tarjetaDoc.id,
                                                          tarjetaNombre,
                                                        );
                                                      }
                                                    : null,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: cantDir > 0
                                                      ? const Color(0xFF1B5E20)
                                                      : Colors.grey.shade400,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child:
                                                    const Text('Tomar tarjeta'),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _asignarTarjetaAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      final ahora = DateTime.now();
      final nombre = widget.usuarioData['nombre'] ?? '';
      final write = FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        'asignado_a': nombre,
        'publicador_email': _usuarioEmail,
        'publicador_nombre': nombre,
        'enviado_nombre': nombre,
        'enviado_tipo': 'publicador',
        'enviado_a': _usuarioEmail,
        'mes_asignacion':
            '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': true,
        'bloqueado': false,
        'asignado_en': Timestamp.fromDate(ahora),
        'tomado_en': Timestamp.fromDate(ahora),
        'tomado_por': nombre,
        'prioridad_admin': false,
        'mes_prioridad': null,
      }, SetOptions(merge: true));
      unawaited(write.catchError((Object error) {
        debugPrint('Asignación de tarjeta pendiente/no confirmada: $error');
      }));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(OfflineSyncService.instance.isOffline
            ? '✅ Tarjeta "$tarjetaNombre" guardada; se sincronizará al recuperar conexión.'
            : '✅ Tarjeta "$tarjetaNombre" asignada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));

      // La notificación es secundaria: nunca debe bloquear la asignación local.
      unawaited(NotificacionService.enviarAAdminTerritorios(
        titulo: '📋 Tarjeta tomada por publicador',
        cuerpo: '$nombre tomó "$tarjetaNombre" del territorio "$territorioId"',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {
          'territorio_id': territorioId,
          'tarjeta_id': tarjetaId,
          'tomada_por': nombre,
        },
      ).catchError((Object error) {
        debugPrint('Notificación de tarjeta tomada pendiente: $error');
      }));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _asignarTarjetaAConductor(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre, {
    String? duenoAnterior,
  }) async {
    try {
      final ahora = DateTime.now();
      final nombre = widget.usuarioData['nombre'] ?? '';
      final write = FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        // El conductor tiene la tarjeta para repartirla, no la predica él.
        // `asignado_a` se reserva para el publicador que la trabaja, así que
        // aquí queda vacío para que no aparezca en el modo publicador de quien
        // sea conductor y publicador a la vez.
        'asignado_a': null,
        'enviado_nombre': nombre,
        'enviado_tipo': 'conductor',
        'conductor_email': _usuarioEmail,
        'enviado_a': _usuarioEmail,
        'estatus_envio': 'enviado',
        'mes_asignacion':
            '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': false,
        'bloqueado': false,
        // Sin `asignado_en`: la tarjeta del conductor no vence por el
        // temporizador de devolución automática del publicador.
        'asignado_en': null,
        'tomado_en': Timestamp.fromDate(ahora),
        'tomado_por': nombre,
        'prioridad_admin': false,
        'mes_prioridad': null,
        // Al pasar a manos del conductor se limpian los datos del
        // publicador anterior para que no queden "pegados".
        'publicador_email': null,
        'publicador_nombre': null,
      }, SetOptions(merge: true));
      unawaited(write.catchError((Object error) {
        debugPrint(
            'Transferencia al conductor pendiente/no confirmada: $error');
      }));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(OfflineSyncService.instance.isOffline
            ? '✅ Tarjeta "$tarjetaNombre" guardada; se sincronizará al recuperar conexión.'
            : '✅ Tarjeta "$tarjetaNombre" tomada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));

      unawaited(NotificacionService.enviarAAdminTerritorios(
        titulo: '🚚 Tarjeta tomada por conductor',
        cuerpo: '$nombre tomó "$tarjetaNombre" del territorio "$territorioId"',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {
          'territorio_id': territorioId,
          'tarjeta_id': tarjetaId,
          'tomada_por': nombre,
        },
      ).catchError((Object error) {
        debugPrint('Notificación de tarjeta tomada pendiente: $error');
      }));

      // Avisar a quien la tenía antes (publicador u otro conductor).
      if (duenoAnterior != null && duenoAnterior.trim().isNotEmpty) {
        unawaited(TransferenciaTarjeta.notificarTransferencia(
          duenoAnterior: duenoAnterior,
          nuevoDueno: nombre,
          tarjetaNombre: tarjetaNombre,
          territorioId: territorioId,
          territorioNombre: territorioId,
        ).catchError((Object error) {
          debugPrint('Notificación de transferencia pendiente: $error');
        }));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _verificarReinicioMensual() async {
    try {
      final debe = await RestauracionMensual.debeEjecutarse();
      if (debe && mounted) {
        debugPrint(
            '📔️ Día 1 detectado — ejecutando reinicio mensual automático');
        await RestauracionMensual.ejecutar(context);
      }
    } catch (e) {
      debugPrint('❌ Error verificando reinicio mensual: $e');
    }
  }

  void _procesarEnviosProgramados() async {
    final now = DateTime.now();
    try {
      final queryTerritorios = await FirebaseFirestore.instance
          .collection('territorios')
          .where(
            'programado_para',
            isLessThanOrEqualTo: Timestamp.fromDate(now),
          )
          .where('estatus_envio', isEqualTo: 'programado')
          .get();
      final queryTarjetas = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where(
            'programado_para',
            isLessThanOrEqualTo: Timestamp.fromDate(now),
          )
          .where('estatus_envio', isEqualTo: 'programado')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in queryTerritorios.docs) {
        final docData = doc.data();
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': docData.containsKey('conductor_email')
              ? docData['conductor_email']
              : '',
        });
      }
      for (final doc in queryTarjetas.docs) {
        final docData = doc.data();
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': docData.containsKey('conductor_email')
              ? docData['conductor_email']
              : '',
        });
      }
      bool hasUpdates =
          queryTerritorios.docs.isNotEmpty || queryTarjetas.docs.isNotEmpty;
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {
      // No interrumpir la app si el procesamiento programado falla.
    }
  }
}
