import 'dart:io';

// Flutter & Firebase
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

// Core Services & L10n
import 'package:araucaria_sur/core/services/notification_service.dart';
import 'package:araucaria_sur/core/services/notificacion_service.dart';
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
    _tabControllerAdmin = TabController(length: 4, vsync: this);
    _usuarioEmail = widget.usuarioData['email'] ?? '';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _procesarPendingAction());
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
          final roles = (snap.data()?['roles'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[];
          final esAdminEco2 = roles.contains('admin');
          if (esAdminEco2 != _esAdminEco2) {
            setState(() => _esAdminEco2 = esAdminEco2);
          }
        });
      }
    } catch (_) {}
  }

  void _procesarPendingAction() {
    final action = NotificationService.getPendingAction();
    if (action == null || !mounted) return;

    final esAdmin = widget.usuarioData['es_admin'] == true;
    if (!esAdmin) return; // Solo admin puede navegar desde notificaciones

    switch (action) {
      case 'usuarios_pendientes':
        // Navegar a la tab de Usuarios en admin
        setState(() {
          _tabControllerAdmin.animateTo(2); // Tab Usuarios
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('👤 Revisa los usuarios pendientes de aprobación'),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 'solicitudes_localizador':
        // Navegar a la tab de Comunicación en admin
        setState(() {
          _tabControllerAdmin.animateTo(1); // Tab Comunicación
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Revisa las solicitudes de direcciones'),
            backgroundColor: Colors.blue,
          ),
        );
        break;
    }
  }

  @override
  void dispose() {
    _tabControllerAdmin.dispose();
    _campanaEspecialController.dispose();
    _anuncioGeneralController.dispose();
    super.dispose();
  }

  void _cerrarSesion() async {
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
                          onPressed: () => Navigator.of(context).pop(),
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
                          Navigator.of(context).pop();
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
                            Navigator.of(context).pop();
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
                            Navigator.of(context).pop();
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
                            Navigator.of(context).pop();
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
                          Navigator.of(context).pop();
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
                          Navigator.of(context).pop();
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
                          Navigator.of(context).pop();
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
                          Navigator.of(context).pop();
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
                    Navigator.of(context).pop();
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        String fileContent = await file.readAsString();
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
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('territorios')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No hay territorios.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, i) {
                        final terDoc = snapshot.data!.docs[i];
                        final terData = terDoc.data() as Map<String, dynamic>;
                        final terNombre = terData['nombre'] ?? terDoc.id;
                        if (terDoc.id == 'temporales' || terDoc.id == 'campanas') return const SizedBox.shrink();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                            title: Text(terNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                  if (tarjetasSnap.connectionState == ConnectionState.waiting) {
                                    return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                  }
                                  // Conductor ve TODAS — incluyendo solo_conductores
                                  final tarjetas = (tarjetasSnap.data?.docs ?? []).where((doc) {
                                    final d = doc.data() as Map<String, dynamic>;
                                    final asignado = d['asignado_a']?.toString() ?? '';
                                    return asignado.isEmpty;
                                  }).toList();
                                  if (tarjetas.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No hay tarjetas disponibles.', style: TextStyle(color: Colors.grey)),
                                    );
                                  }
                                  return Column(
                                    children: tarjetas.map((tarjetaDoc) {
                                      final data = tarjetaDoc.data() as Map<String, dynamic>;
                                      final tarjetaNombre = data['nombre'] ?? tarjetaDoc.id;
                                      final soloConductores = (data['solo_conductores'] as bool?) ?? false;
                                      return StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id', isEqualTo: tarjetaDoc.id)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          final cantDir = dirSnapshot.data?.docs.length ?? 0;
                                          return ListTile(
                                            leading: Icon(
                                              soloConductores ? Icons.lock : Icons.credit_card,
                                              color: data['completada'] == true ? Colors.grey : const Color(0xFF1B5E20),
                                            ),
                                            title: Text(tarjetaNombre,
                                                style: TextStyle(color: data['completada'] == true ? Colors.grey : Colors.black)),
                                            subtitle: Text(
                                              data['completada'] == true
                                                  ? '✅ Completada este mes'
                                                  : '$cantDir direcciones${soloConductores ? ' · Solo conductores' : ''}',
                                            ),
                                            trailing: data['completada'] == true
                                                ? null
                                                : ElevatedButton(
                                                    onPressed: cantDir > 0
                                                        ? () async {
                                                            Navigator.pop(context);
                                                            await _asignarTarjetaAConductor(
                                                              terDoc.id,
                                                              tarjetaDoc.id,
                                                              tarjetaNombre,
                                                            );
                                                          }
                                                        : null,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: cantDir > 0 ? const Color(0xFF1B5E20) : Colors.grey.shade400,
                                                      foregroundColor: Colors.white,
                                                    ),
                                                    child: const Text('Tomar'),
                                                  ),
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
      ),
    );
  }

  Future<void> _mostrarDialogoSolicitarTerritorioPublicador() async {
    const especiales = ['temporales', 'removidas', 'estadisticas', 'campanas'];

    // Carga los territorios SIN orderBy (evita que Firestore excluya
    // documentos con caracteres especiales como Ç, tildes, ñ)
    final snap = await FirebaseFirestore.instance
        .collection('territorios')
        .get();

    // Solo excluir IDs especiales del sistema — NO filtrar por solo_conductores
    // (ese campo aplica a tarjetas individuales, no a territorios enteros)
    final territorios = snap.docs.where((doc) {
      return !especiales.contains(doc.id);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  child: territorios.isEmpty
                      ? const Center(
                          child: Text('No hay territorios disponibles.',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: territorios.length,
                          itemBuilder: (ctx2, index) {
                            final terDoc = territorios[index];
final terData = terDoc.data();
                            final terNombre = (terData['nombre'] as String?) ?? terDoc.id;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                                title: Text(terNombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                  final tarjetas =
                                      (tarjetasSnap.data?.docs ?? [])
                                          .where((doc) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    return !((d['solo_conductores'] as bool?) ??
                                        false);
                                  }).toList();

                                  if (tarjetas.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No hay tarjetas disponibles.',
                                          style:
                                              TextStyle(color: Colors.grey)),
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
                                          data['conductor_email']
                                                  ?.toString() ??
                                              '';
                                      final enviadoTipo =
                                          data['enviado_tipo']?.toString() ??
                                              '';
                                      final asignadoA =
                                          data['asignado_a']?.toString() ?? '';
                                      final estaConConductor =
                                          conductorEmail.isNotEmpty ||
                                              enviadoTipo == 'conductor' ||
                                              (asignadoA.isNotEmpty &&
                                                  enviadoTipo != 'publicador' &&
                                                  enviadoTipo.isNotEmpty);
                                      final enviadoNombre =
                                          data['enviado_nombre']
                                                  ?.toString() ??
                                              '';

                                      return StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id',
                                                isEqualTo: tarjetaDoc.id)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          final cantDir =
                                              dirSnapshot.data?.docs.length ??
                                                  0;

                                          // Con conductor → gris
                                          if (estaConConductor) {
                                            return Container(
                                              margin: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade300),
                                              ),
                                              child: ListTile(
                                                dense: true,
                                                leading: const Icon(
                                                    Icons.credit_card,
                                                    color: Colors.grey),
                                                title: Text(tarjetaNombre,
                                                    style: const TextStyle(
                                                        color: Colors.grey,
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
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade300,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: const Text('No disp.',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey)),
                                                ),
                                              ),
                                            );
                                          }

                                          // Completada → solo informativo (solo admin territorios puede reactivar)
                                          if (data['completada'] == true) {
                                            return ListTile(
                                              leading: const Icon(Icons.credit_card, color: Colors.grey),
                                              title: Text(tarjetaNombre, style: const TextStyle(color: Colors.grey)),
                                              subtitle: const Text('✅ Completada este mes'),
                                              trailing: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text('No disp.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                              ),
                                            );
                                          }

                                          // Disponible → Tomar
                                          return ListTile(
                                            leading: const Icon(
                                                Icons.credit_card,
                                                color: Colors.blue),
                                            title: Text(tarjetaNombre),
                                            subtitle:
                                                Text('$cantDir direcciones'),
                                            trailing: ElevatedButton(
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
                                              child: const Text('Tomar'),
                                            ),
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
      await FirebaseFirestore.instance
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
        'mes_asignacion': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': true,
        'bloqueado': false,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(),
        'prioridad_admin': false,
        'mes_prioridad': null,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Tarjeta "$tarjetaNombre" asignada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));

      // Notificar a admin_territorios
      final terDoc = await FirebaseFirestore.instance
          .collection('territorios').doc(territorioId).get();
      final terNombre = (terDoc.data()?['nombre'] as String?) ?? territorioId;
      await NotificacionService.enviarAAdminTerritorios(
        titulo: '📋 Tarjeta tomada por publicador',
        cuerpo: '$nombre tomó "$tarjetaNombre" del territorio "$terNombre"',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {'territorio_id': territorioId, 'tarjeta_id': tarjetaId, 'tomada_por': nombre},
      );
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
    String tarjetaNombre,
  ) async {
    try {
      final ahora = DateTime.now();
      final nombre = widget.usuarioData['nombre'] ?? '';
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        'asignado_a': nombre,
        'enviado_nombre': nombre,
        'enviado_tipo': 'conductor',
        'conductor_email': _usuarioEmail,
        'enviado_a': _usuarioEmail,
        'mes_asignacion': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'completada': false,
        'disponible_para_publicadores': false,
        'bloqueado': false,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(),
        'prioridad_admin': false,
        'mes_prioridad': null,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Tarjeta "$tarjetaNombre" tomada'),
        backgroundColor: const Color(0xFF1B5E20),
      ));

      // Notificar a admin_territorios
      final terDoc = await FirebaseFirestore.instance
          .collection('territorios').doc(territorioId).get();
      final terNombre = (terDoc.data()?['nombre'] as String?) ?? territorioId;
      await NotificacionService.enviarAAdminTerritorios(
        titulo: '🚚 Tarjeta tomada por conductor',
        cuerpo: '$nombre tomó "$tarjetaNombre" del territorio "$terNombre"',
        tipo: TipoNotificacion.tarjetaTomada,
        extra: {'territorio_id': territorioId, 'tarjeta_id': tarjetaId, 'tomada_por': nombre},
      );
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
        debugPrint('📔️ Día 1 detectado — ejecutando reinicio mensual automático');
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
