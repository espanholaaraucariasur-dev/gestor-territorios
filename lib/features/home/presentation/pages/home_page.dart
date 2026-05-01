import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'conductor/conductor_tab.dart';
import 'publicador/publicador_tab.dart';
import 'admin/admin_territorios_tab.dart';
import 'localizador/localizador_tab.dart';
import 'admin/admin_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../../../auth/presentation/pages/login_page.dart';
// CSV
import 'package:file_picker/file_picker.dart';

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
  String _idiomaActual = 'ES';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabControllerAdmin;
  String _usuarioEmail = '';
  bool _campanaEspecialActiva = false;
  String _nombreCampanaEspecial = '';
  bool _campanaGeneralActiva = false;
  String _anuncioGeneral = '';
  List<DocumentSnapshot> territoriosFiltrados = [];

  // Variables de estado para tarjetas (persistentes)
  Map<String, Map<String, String>> _estadosPorTarjeta = {};
  Map<String, Map<String, String>> _textosPorTarjeta = {};
  Map<String, Map<String, bool>> _modificadosPorTarjeta = {};
  Map<String, bool> _tarjetaModificada = {};
  Map<String, bool> _tarjetaExpandida = {};

  final TextEditingController _campanaEspecialController =
      TextEditingController();
  final TextEditingController _anuncioGeneralController =
      TextEditingController();
  final TextEditingController _localizadorController = TextEditingController();
  final TextEditingController _complementoLocalizadorController =
      TextEditingController();
  final TextEditingController _detallesLocalizadorController =
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
  }

  @override
  void dispose() {
    _tabControllerAdmin.dispose();
    _campanaEspecialController.dispose();
    _anuncioGeneralController.dispose();
    _localizadorController.dispose();
    _complementoLocalizadorController.dispose();
    _detallesLocalizadorController.dispose();
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

  String _normalizarDireccion(String direccion) {
    var texto = direccion.toLowerCase();
    texto = texto.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    texto = texto.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    texto = texto.replaceAll(RegExp(r'\b(n\.?|no\.?|nº|n°)\b'), ' ');
    texto = texto.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    texto = texto.replaceAll('apto', 'apartamento');
    texto = texto.replaceAll('apt', 'apartamento');
    texto = texto.replaceAll('ap.', 'apartamento');
    texto = texto.replaceAll('ap.', 'apartamento');
    texto = texto.replaceAll('dpto', 'departamento');
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
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

  Future<void> _programarEnvioTarjeta(
    BuildContext context,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    await _mostrarDialogoProgramarEnvio(
      terId,
      tarjetaId: tarjetaId,
      nombre: tarjetaNombre,
      isTarjeta: true,
    );
  }

  Future<void> _mostrarDialogoProgramarEnvio(
    String terId, {
    String? tarjetaId,
    required String nombre,
    required bool isTarjeta,
  }) async {
    final conductoresSnapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .get();
    final conductores = conductoresSnapshot.docs
        .map((doc) => doc.data()['email'] as String? ?? '')
        .where((email) => email.isNotEmpty)
        .toList();
    if (!mounted) return;
    String selectedConductor = conductores.isNotEmpty ? conductores.first : '';
    DateTime fechaSeleccionada = DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                isTarjeta
                    ? 'Programar envío de tarjeta'
                    : 'Programar envío de territorio',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conductores.isEmpty)
                    const Text(
                      'No hay conductores registrados. Agrega un conductor antes de programar.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedConductor,
                      items: conductores
                          .map(
                            (email) => DropdownMenuItem(
                              value: email,
                              child: Text(email),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setStateDialog(() => selectedConductor = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Conductor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: fechaSeleccionada,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setStateDialog(() => fechaSeleccionada = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Fecha de envío',
                      ),
                      child: Text(
                        '${fechaSeleccionada.day}/${fechaSeleccionada.month}/${fechaSeleccionada.year}',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: conductores.isEmpty
                      ? null
                      : () async {
                          try {
                            final data = {
                              'programado_para': Timestamp.fromDate(
                                fechaSeleccionada,
                              ),
                              'conductor_email': selectedConductor,
                              'estatus_envio': 'programado',
                              'programado_tipo':
                                  isTarjeta ? 'tarjeta' : 'territorio',
                              'programado_nombre': nombre,
                            };
                            if (isTarjeta) {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .collection('tarjetas')
                                  .doc(tarjetaId)
                                  .set(data, SetOptions(merge: true));
                            } else {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .set(data, SetOptions(merge: true));
                            }
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Programación guardada para $nombre',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al programar envío: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                  child: const Text('Programar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  InputDecoration _inputStyleHelper(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esConductor = widget.usuarioData['es_conductor'] ?? false;
    final esAdmin = widget.usuarioData['es_admin'] ?? false;
    final esAdminTerritorios =
        widget.usuarioData['es_admin_territorios'] ?? false;
    final nombre = widget.usuarioData['nombre'] ?? 'Hermano';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF1F8E9),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 12.0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF263238),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Menú de modos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications_none_outlined),
                title: const Text('Notificaciones'),
                subtitle: const Text('Ver últimas alertas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No hay notificaciones nuevas'),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Color(0xFF1B5E20)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Idioma',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('ES'),
                      selected: _idiomaActual == 'ES',
                      selectedColor: const Color(0xFF1B5E20),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey.shade200,
                      onSelected: (selected) =>
                          setState(() => _idiomaActual = 'ES'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('PT'),
                      selected: _idiomaActual == 'PT',
                      selectedColor: const Color(0xFF1B5E20),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey.shade200,
                      onSelected: (selected) =>
                          setState(() => _idiomaActual = 'PT'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Modo Admin'),
                subtitle: const Text('Acceso completo'),
                selected: _modoAdminActivo,
                onTap: esAdmin
                    ? () {
                        setState(() {
                          _modoAdminActivo = true;
                          _modoAdminTerritoriosActivo = false;
                          _modoConductorActivo = false;
                        });
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Modo Territorios'),
                subtitle: const Text('Solo lectura y envío'),
                selected: _modoAdminTerritoriosActivo,
                onTap: esAdminTerritorios
                    ? () {
                        setState(() {
                          _modoAdminTerritoriosActivo = true;
                          _modoAdminActivo = false;
                          _modoConductorActivo = false;
                        });
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.drive_eta_outlined),
                title: const Text('Modo Conductor'),
                subtitle: const Text('Panel de conductor'),
                selected: _modoConductorActivo,
                onTap: esConductor
                    ? () {
                        setState(() {
                          _modoConductorActivo = true;
                          _modoAdminActivo = false;
                          _modoAdminTerritoriosActivo = false;
                          _indiceActual = 0;
                        });
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Text(
                  'Vistas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Inicio'),
                selected: _indiceActual == 0,
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
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: const Text('Tarjetas'),
                selected: _indiceActual == 1,
                onTap: () {
                  setState(() {
                    _modoAdminActivo = false;
                    _modoAdminTerritoriosActivo = false;
                    _modoConductorActivo = false;
                    _indiceActual = 1;
                  });
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_searching),
                title: const Text('Localizador'),
                selected: _indiceActual == 2,
                onTap: () {
                  setState(() {
                    _modoAdminActivo = false;
                    _modoAdminTerritoriosActivo = false;
                    _modoConductorActivo = false;
                    _indiceActual = 2;
                  });
                  Navigator.of(context).pop();
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 8.0,
                ),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpiar modo'),
                  onPressed: () {
                    setState(() {
                      _modoAdminActivo = false;
                      _modoAdminTerritoriosActivo = false;
                      _modoConductorActivo = false;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 12.0,
                ),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Cerrar sesión',
                    style: TextStyle(color: Colors.red),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _cerrarSesion();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF263238)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Congregación Araucaria Sur',
          style: TextStyle(
            color: Color(0xFF263238),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _indiceActual,
        children: [
          _buildVistaHome(nombre, esConductor, esAdmin, esAdminTerritorios),
          _buildVistaTarjetas(),
          _buildVistaLocalizador(),
        ],
      ),
      floatingActionButton: !_modoAdminActivo &&
              !_modoAdminTerritoriosActivo &&
              !_modoConductorActivo
          ? Container(
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1B5E20),
                    Color(0xFF2E7D32),
                    Color(0xFF43A047),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _mostrarDialogoSolicitarTerritorioPublicador,
                  borderRadius: BorderRadius.circular(25),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.map, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Solicitar territorio',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
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

  Future<void> _mostrarDialogoEnviar({
    required String terId,
    String? tarjetaId,
    required String nombre,
  }) async {
    final conductoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    final publicadoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_publicador', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enviar: $nombre'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (conductoresSnap.docs.isEmpty)
                  const Text(
                    'No hay conductores disponibles.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  const Text(
                    'Conductores disponibles:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...conductoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.drive_eta,
                        color: Color(0xFF1B5E20),
                      ),
                      title: Text(data['nombre'] ?? 'Conductor'),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvio(
                          terId: terId,
                          tarjetaId: tarjetaId,
                          nombre: nombre,
                          destinatarioEmail: data['email'],
                          tipo: 'conductor',
                        );
                      },
                    );
                  }),
                ],
                const Divider(),
                const Text(
                  'Enviar a publicador:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (publicadoresSnap.docs.isEmpty)
                  const Text(
                    'No hay publicadores disponibles.',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...publicadoresSnap.docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person, color: Colors.blue),
                      title: Text(data['nombre'] ?? 'Publicador'),
                      subtitle: Text(data['email'] ?? ''),
                      onTap: () async {
                        Navigator.pop(context);
                        await _ejecutarEnvio(
                          terId: terId,
                          tarjetaId: tarjetaId,
                          nombre: nombre,
                          destinatarioEmail: data['email'],
                          tipo: 'publicador',
                        );
                      },
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enviarTarjetaIndividual(
    BuildContext context,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    await _mostrarDialogoEnviar(
      terId: terId,
      tarjetaId: tarjetaId,
      nombre: tarjetaNombre,
    );
  }

  Future<void> _ejecutarEnvio({
    required String terId,
    String? tarjetaId,
    required String nombre,
    required String destinatarioEmail,
    required String tipo, // 'conductor' o 'publicador'
  }) async {
    try {
      // Buscar nombre del destinatario por email
      final usuarioSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: destinatarioEmail)
          .get();
      final nombreDestinatario = usuarioSnap.docs.isNotEmpty
          ? (usuarioSnap.docs.first.data()['nombre'] ?? destinatarioEmail)
          : destinatarioEmail;

      final payload = {
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'estatus_envio': 'enviado',
        'enviado_a': destinatarioEmail,
        'enviado_nombre': nombreDestinatario, // ✅ nombre real del usuario
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
        'nombre': nombre,
      };

      if (tarjetaId != null) {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .collection('tarjetas')
            .doc(tarjetaId)
            .set(payload, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .set(payload, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "$nombre" enviado a $destinatarioEmail'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editarNombreTarjeta(
    String territorioId,
    String tarjetaId,
    String nombreActual,
  ) {
    final TextEditingController nombreCtrl = TextEditingController(
      text: nombreActual,
    );

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit, size: 40, color: Color(0xFF1B5E20)),
                const SizedBox(height: 16),
                const Text(
                  'Editar Tarjeta',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nombreCtrl,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Nombre de la tarjeta',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF1B5E20),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          String nuevoNombre = nombreCtrl.text.trim();
                          if (nuevoNombre.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un nombre'),
                              ),
                            );
                            return;
                          }

                          // Actualizar nombre de la tarjeta
                          await FirebaseFirestore.instance
                              .collection('territorios')
                              .doc(territorioId)
                              .collection('tarjetas')
                              .doc(tarjetaId)
                              .update({'nombre': nuevoNombre});

                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Guardar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _abrirTerritorio(
    String terId,
    String terNombre, {
    bool readOnly = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            terNombre,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(thickness: 2),
                    if (readOnly)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _mostrarDialogoEnviar(
                            terId: terId,
                            nombre: terNombre,
                          ),
                          icon: const Icon(Icons.send, color: Colors.green),
                          label: const Text(
                            'Enviar territorio completo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    if (readOnly) const SizedBox(height: 16),
                    if (!readOnly)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _mostrarDialogoCrearTarjeta(context, terId),
                          icon: const Icon(Icons.folder_open),
                          label: const Text(
                            'Crear Nueva Tarjeta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    if (!readOnly) const SizedBox(height: 16),
                    const Text(
                      'Tarjetas en este Territorio:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .doc(terId)
                            .collection('tarjetas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No hay tarjetas creadas aún.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var tarjeta = snapshot.data!.docs[index];
                              String tarjetaId = tarjeta.id;
                              final tarjetaMap =
                                  tarjeta.data() as Map<String, dynamic>;
                              String tarjetaNombre =
                                  tarjetaMap['nombre'] ?? 'Sin nombre';
                              int cantidadDir =
                                  tarjetaMap['cantidad_direcciones'] ?? 0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: Colors.blue.shade50,
                                elevation: 2,
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.folder,
                                        color: Colors.blue,
                                      ),
                                      title: Text(
                                        tarjetaNombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Dir. vinculadas: $cantidadDir'),
                                          if ((tarjetaMap['enviado_nombre'] ??
                                                  '')
                                              .toString()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  final enviadoEn =
                                                      tarjetaMap['enviado_en'];
                                                  String fechaHora = '';
                                                  if (enviadoEn != null) {
                                                    final dt =
                                                        (enviadoEn as Timestamp)
                                                            .toDate();
                                                    fechaHora =
                                                        ' · ${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                                  }
                                                  return Text(
                                                    'Enviado a: ${tarjetaMap['enviado_nombre']}$fechaHora',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .orange.shade900,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (readOnly) ...[
                                            // Enviar tarjeta
                                            IconButton(
                                              icon: const Icon(
                                                Icons.send,
                                                color: Colors.blue,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _enviarTarjetaIndividual(
                                                context,
                                                terId,
                                                tarjetaId,
                                                tarjetaNombre,
                                              ),
                                              tooltip: 'Enviar tarjeta',
                                            ),
                                            // Candado
                                            IconButton(
                                              icon: Icon(
                                                tarjetaMap['bloqueado'] == true
                                                    ? Icons.lock
                                                    : Icons.lock_open,
                                                color:
                                                    tarjetaMap['bloqueado'] ==
                                                            true
                                                        ? Colors.red
                                                        : Colors.green,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _toggleBloqueoTarjeta(
                                                terId,
                                                tarjetaId,
                                                tarjetaMap['bloqueado'] == true,
                                              ),
                                              tooltip:
                                                  tarjetaMap['bloqueado'] ==
                                                          true
                                                      ? 'Desbloquear tarjeta'
                                                      : 'Bloquear tarjeta',
                                            ),
                                            // Temporizador
                                            IconButton(
                                              icon: const Icon(
                                                Icons.schedule,
                                                color: Colors.purple,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _programarEnvioTarjeta(
                                                context,
                                                terId,
                                                tarjetaId,
                                                tarjetaNombre,
                                              ),
                                              tooltip: 'Programar envío',
                                            ),
                                          ],
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add_circle,
                                                color: Colors.green,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _agregarDireccionesATarjeta(
                                                context,
                                                terId,
                                                tarjetaId,
                                                tarjetaNombre,
                                              ),
                                              tooltip: 'Agregar dirección',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.orange,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _editarNombreTarjeta(
                                                terId,
                                                tarjetaId,
                                                tarjetaNombre,
                                              ),
                                              tooltip: 'Editar tarjeta',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_forever,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              tooltip: 'Eliminar tarjeta',
                                              onPressed: () async {
                                                bool? confirmar =
                                                    await showDialog(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                    title: const Text(
                                                      '⚠️ Eliminar Tarjeta',
                                                    ),
                                                    content: Text(
                                                      '¿Eliminar la tarjeta "$tarjetaNombre"? Esto eliminará todas sus direcciones vinculadas.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                          c,
                                                          false,
                                                        ),
                                                        child: const Text(
                                                          'Cancelar',
                                                          style: TextStyle(
                                                            color: Colors.grey,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                          c,
                                                          true,
                                                        ),
                                                        child: const Text(
                                                          'SÍ, Eliminar',
                                                          style: TextStyle(
                                                            color: Colors.red,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirmar == true) {
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('territorios')
                                                      .doc(terId)
                                                      .collection('tarjetas')
                                                      .doc(tarjetaId)
                                                      .delete();
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Scheduled send field - appears only when scheduled
                                    if (tarjetaMap['programado'] == true &&
                                        tarjetaMap['programado_envio'] != null)
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.purple.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.schedule,
                                              color: Colors.purple.shade600,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Programado para: ${_formatScheduledDate(tarjetaMap['programado_envio'])}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.purple.shade800,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                              onPressed: () =>
                                                  _cancelarProgramacionEnvio(
                                                terId,
                                                tarjetaId,
                                              ),
                                              tooltip: 'Cancelar programación',
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 8.0,
                                      ),
                                      child: StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where(
                                              'tarjeta_id',
                                              isEqualTo: tarjetaId,
                                            )
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          if (!dirSnapshot.hasData ||
                                              dirSnapshot.data!.docs.isEmpty) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text(
                                                'Sin direcciones asignadas',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            );
                                          }

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Direcciones:',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              ...dirSnapshot.data!.docs.map((
                                                dirDoc,
                                              ) {
                                                String complemento =
                                                    dirDoc['complemento'] ?? '';
                                                String informacion =
                                                    dirDoc['informacion'] ?? '';

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 10.0,
                                                  ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        10,
                                                      ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .blue.shade200,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                            alpha: 0.05,
                                                          ),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(
                                                            12,
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .location_on,
                                                                size: 18,
                                                                color:
                                                                    Colors.blue,
                                                              ),
                                                              const SizedBox(
                                                                width: 10,
                                                              ),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Text(
                                                                      dirDoc['calle'] ??
                                                                          '',
                                                                      style:
                                                                          const TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color:
                                                                            Color(
                                                                          0xFF263238,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      dirDoc['barrio'] ??
                                                                          'Sin barrio',
                                                                      style:
                                                                          const TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        color: Colors
                                                                            .grey,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 100,
                                                                child: Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .end,
                                                                  children: [
                                                                    IconButton(
                                                                      icon:
                                                                          const Icon(
                                                                        Icons
                                                                            .info_outline,
                                                                        size:
                                                                            16,
                                                                        color: Colors
                                                                            .blue,
                                                                      ),
                                                                      onPressed:
                                                                          () =>
                                                                              _mostrarDetallesDireccion(
                                                                        dirDoc,
                                                                      ),
                                                                      padding:
                                                                          EdgeInsets
                                                                              .zero,
                                                                      constraints:
                                                                          const BoxConstraints(
                                                                        minWidth:
                                                                            32,
                                                                        minHeight:
                                                                            32,
                                                                      ),
                                                                      tooltip:
                                                                          'Ver detalles',
                                                                    ),
                                                                    if (!readOnly)
                                                                      IconButton(
                                                                        icon:
                                                                            const Icon(
                                                                          Icons
                                                                              .edit,
                                                                          size:
                                                                              16,
                                                                          color:
                                                                              Colors.orange,
                                                                        ),
                                                                        onPressed:
                                                                            () =>
                                                                                _editarDireccion(
                                                                          dirDoc,
                                                                        ),
                                                                        padding:
                                                                            EdgeInsets.zero,
                                                                        constraints:
                                                                            const BoxConstraints(
                                                                          minWidth:
                                                                              32,
                                                                          minHeight:
                                                                              32,
                                                                        ),
                                                                        tooltip:
                                                                            'Editar',
                                                                      ),
                                                                    if (!readOnly)
                                                                      IconButton(
                                                                        icon:
                                                                            const Icon(
                                                                          Icons
                                                                              .delete,
                                                                          size:
                                                                              16,
                                                                          color:
                                                                              Colors.red,
                                                                        ),
                                                                        onPressed:
                                                                            () =>
                                                                                _eliminarDireccion(
                                                                          dirDoc
                                                                              .id,
                                                                          terId,
                                                                          tarjetaId,
                                                                        ),
                                                                        padding:
                                                                            EdgeInsets.zero,
                                                                        constraints:
                                                                            const BoxConstraints(
                                                                          minWidth:
                                                                              32,
                                                                          minHeight:
                                                                              32,
                                                                        ),
                                                                        tooltip:
                                                                            'Eliminar',
                                                                      ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (complemento
                                                                .isNotEmpty ||
                                                            informacion
                                                                .isNotEmpty)
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .grey.shade50,
                                                              border: Border(
                                                                top: BorderSide(
                                                                  color: Colors
                                                                      .blue
                                                                      .shade100,
                                                                ),
                                                              ),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                if (complemento
                                                                    .isNotEmpty)
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .only(
                                                                      bottom: 6,
                                                                    ),
                                                                    child: Row(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        const Icon(
                                                                          Icons
                                                                              .apartment,
                                                                          size:
                                                                              14,
                                                                          color:
                                                                              Colors.orange,
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              6,
                                                                        ),
                                                                        Expanded(
                                                                          child:
                                                                              Text(
                                                                            complemento,
                                                                            style:
                                                                                const TextStyle(
                                                                              fontSize: 11,
                                                                              color: Color(
                                                                                0xFF263238,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                if (informacion
                                                                    .isNotEmpty)
                                                                  Row(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .note,
                                                                        size:
                                                                            14,
                                                                        color: Colors
                                                                            .green,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            6,
                                                                      ),
                                                                      Expanded(
                                                                        child:
                                                                            Text(
                                                                          informacion,
                                                                          style:
                                                                              const TextStyle(
                                                                            fontSize:
                                                                                11,
                                                                            color:
                                                                                Colors.grey,
                                                                          ),
                                                                          maxLines:
                                                                              2,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          );
                                        },
                                      ),
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
            );
          },
        );
      },
    );
  }

  void _mostrarDetallesDireccion(QueryDocumentSnapshot dirDoc) {
    final data = dirDoc.data() as Map<String, dynamic>;
    final String complemento = data.containsKey('complemento')
        ? data['complemento']
        : 'No especificado';
    final String informacion = data.containsKey('informacion')
        ? data['informacion']
        : 'No especificada';
    final String calle = data.containsKey('calle') ? data['calle'] : '';
    final String barrio =
        data.containsKey('barrio') ? data['barrio'] : 'Sin barrio';
    final String estadoPredicacion = data.containsKey('estado_predicacion')
        ? data['estado_predicacion']
        : 'pendiente';
    final bool predicado =
        data.containsKey('predicado') ? data['predicado'] : false;
    final bool noPredicado =
        data.containsKey('no_predicado') ? data['no_predicado'] : false;
    final bool esHispano =
        data.containsKey('es_hispano') ? data['es_hispano'] : true;
    final bool entregoInvitacion = data.containsKey('entrego_invitacion')
        ? data['entrego_invitacion']
        : false;
    final bool campanaEspecial =
        data.containsKey('campana_especial') ? data['campana_especial'] : false;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.location_on, size: 28, color: Colors.blue),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _detalleCard(
                  '📍 Calle',
                  calle,
                  Colors.blue,
                  const Color(0xFFB3E5FC),
                ),
                const SizedBox(height: 12),
                _detalleCard(
                  '🏘️ Barrio',
                  barrio,
                  Colors.green,
                  const Color(0xFFC8E6C9),
                ),
                const SizedBox(height: 12),
                _detalleCard(
                  '🏠 Complemento',
                  complemento,
                  Colors.orange,
                  const Color(0xFFFFE0B2),
                ),
                const SizedBox(height: 12),
                _detalleCard(
                  '📝 Información',
                  informacion,
                  Colors.purple,
                  const Color(0xFFE1BEE7),
                ),
                const SizedBox(height: 12),
                _detalleCard(
                  '📌 Estado predicación',
                  estadoPredicacion,
                  Colors.teal,
                  const Color(0xFFB2DFDB),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _chipDetalle('Predicado', predicado),
                    const SizedBox(width: 8),
                    _chipDetalle('No predicado', noPredicado),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _chipDetalle(
                      esHispano ? 'Hispano' : 'No hispano',
                      esHispano,
                    ),
                    const SizedBox(width: 8),
                    _chipDetalle('Entregó invitación', entregoInvitacion),
                  ],
                ),
                if (_campanaEspecialActiva) ...[
                  const SizedBox(height: 10),
                  _chipDetalle('Campaña especial', campanaEspecial),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Entendido',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detalleCard(
    String titulo,
    String valor,
    Color iconColor,
    Color backgroundColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(fontSize: 14, color: Color(0xFF263238)),
          ),
        ],
      ),
    );
  }

  Widget _chipDetalle(String texto, bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: activo ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          color: activo ? Colors.green.shade900 : Colors.black54,
        ),
      ),
    );
  }

  void _editarDireccion(QueryDocumentSnapshot dirDoc) {
    final data = dirDoc.data() as Map<String, dynamic>;
    final TextEditingController calleCtrl = TextEditingController(
      text: data.containsKey('calle') ? data['calle'] : '',
    );
    final TextEditingController complementoCtrl = TextEditingController(
      text: data.containsKey('complemento') ? data['complemento'] : '',
    );
    final TextEditingController informacionCtrl = TextEditingController(
      text: data.containsKey('informacion') ? data['informacion'] : '',
    );
    bool predicado = data.containsKey('predicado') ? data['predicado'] : false;
    bool noPredicado =
        data.containsKey('no_predicado') ? data['no_predicado'] : false;
    bool noHispano =
        (data.containsKey('es_hispano') ? data['es_hispano'] : true) == false;
    bool entregoInvitacion = data.containsKey('entrego_invitacion')
        ? data['entrego_invitacion']
        : false;
    bool campanaEspecial =
        data.containsKey('campana_especial') ? data['campana_especial'] : false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_location,
                        size: 40,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Editar Dirección',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: calleCtrl,
                        decoration: InputDecoration(
                          hintText: 'Calle',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: complementoCtrl,
                        decoration: InputDecoration(
                          hintText: 'Complemento',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: informacionCtrl,
                        decoration: InputDecoration(
                          hintText: 'Información',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Se predicó'),
                        value: predicado,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setDialogState(() {
                            predicado = value ?? false;
                            if (predicado) noPredicado = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('No se predicó'),
                        value: noPredicado,
                        activeColor: Colors.red,
                        onChanged: (value) {
                          setDialogState(() {
                            noPredicado = value ?? false;
                            if (noPredicado) predicado = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('No vive hispanohablante'),
                        value: noHispano,
                        activeColor: Colors.orange,
                        onChanged: (value) =>
                            setDialogState(() => noHispano = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Entregó invitación'),
                        value: entregoInvitacion,
                        activeColor: Colors.blue,
                        onChanged: (value) => setDialogState(
                          () => entregoInvitacion = value ?? false,
                        ),
                      ),
                      if (_campanaEspecialActiva)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Campaña especial activa'),
                          value: campanaEspecial,
                          activeColor: Colors.deepOrange,
                          onChanged: (value) => setDialogState(
                            () => campanaEspecial = value ?? false,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final estadoPredicacion = predicado
                                    ? 'predicado'
                                    : noPredicado
                                        ? 'no_predicado'
                                        : 'pendiente';
                                await FirebaseFirestore.instance
                                    .collection('direcciones_globales')
                                    .doc(dirDoc.id)
                                    .update({
                                  'calle': calleCtrl.text.trim(),
                                  'complemento': complementoCtrl.text.trim(),
                                  'informacion': informacionCtrl.text.trim(),
                                  'direccion_normalizada': _normalizarDireccion(
                                    '${calleCtrl.text.trim()} ${complementoCtrl.text.trim()}',
                                  ),
                                  'predicado': predicado,
                                  'no_predicado': noPredicado,
                                  'es_hispano': !noHispano,
                                  'entrego_invitacion': entregoInvitacion,
                                  'campana_especial': campanaEspecial,
                                  'estado_predicacion': estadoPredicacion,
                                });
                                if (context.mounted) Navigator.pop(context);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Dirección actualizada'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              child: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _eliminarDireccion(String dirId, String terId, String tarjetaId) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('⚠️ Eliminar Dirección'),
        content: const Text(
          '¿Estás completamente seguro de que deseas eliminar esta dirección? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'SÍ, Eliminar',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .doc(dirId)
            .delete();

        DocumentSnapshot snap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .collection('tarjetas')
            .doc(tarjetaId)
            .get();
        int currentCount = snap.data() != null
            ? (snap.data() as Map)['cantidad_direcciones'] ?? 0
            : 0;

        if (currentCount > 0) {
          await FirebaseFirestore.instance
              .collection('territorios')
              .doc(terId)
              .collection('tarjetas')
              .doc(tarjetaId)
              .update({'cantidad_direcciones': currentCount - 1});
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Dirección eliminada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarDialogoCrearTarjeta(BuildContext parentContext, String terId) {
    final ctrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 40, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text(
                      'Crear Nueva Tarjeta',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ctrl,
                      textAlign: TextAlign.center,
                      decoration: _inputStyleHelper('Ej: A01 - CENTRO 1'),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor ingresa un nombre para la tarjeta',
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            String nombreTarjeta = ctrl.text.trim();
                            await FirebaseFirestore.instance
                                .collection('territorios')
                                .doc(terId)
                                .collection('tarjetas')
                                .doc(nombreTarjeta)
                                .set({
                              'nombre': nombreTarjeta,
                              'territorio_id': terId,
                              'estado': 'disponible',
                              'cantidad_direcciones': 0,
                              'barrio': '',
                              'created_at': FieldValue.serverTimestamp(),
                              'bloqueado': true,
                              'disponible_para_publicadores': false,
                              'asignado_a': '',
                              'asignado_en': null,
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                            }

                            if (parentContext.mounted) {
                              await Future.delayed(
                                const Duration(milliseconds: 500),
                              );
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ ¡Tarjeta creada con éxito!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Error al crear tarjeta: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Crear Tarjeta',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _agregarDireccionesATarjeta(
    BuildContext parentContext,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) {
    Set<String> idsSeleccionados = {};
    final TextEditingController direccionCtrl = TextEditingController();
    final TextEditingController complementoCtrl = TextEditingController();
    final TextEditingController informacionCtrl = TextEditingController();

    showDialog(
      context: parentContext,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            tarjetaNombre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Botón subir CSV
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () => _subirCSVATarjeta(
                          context,
                          terId,
                          tarjetaId,
                          tarjetaNombre,
                          setLocalState,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Subir CSV de direcciones'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.edit_document,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Crear Dirección Manual',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: direccionCtrl,
                            decoration: InputDecoration(
                              hintText: 'Ej: Calle Martín Peña 123',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: const Icon(
                                Icons.location_on,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: complementoCtrl,
                            decoration: InputDecoration(
                              hintText: 'Complemento (Apto, Casa, Lote, etc.)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: const Icon(
                                Icons.home,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: informacionCtrl,
                            decoration: InputDecoration(
                              hintText:
                                  'Información (Notas, referencias, etc.)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: const Icon(
                                Icons.info,
                                color: Colors.blue,
                              ),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                if (direccionCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Por favor ingresa una dirección',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  String nombreDireccion =
                                      direccionCtrl.text.trim();
                                  final complemento =
                                      complementoCtrl.text.trim();
                                  final timestamp =
                                      DateTime.now().millisecondsSinceEpoch;
                                  final complementoSlug = complemento.isNotEmpty
                                      ? '_${complemento.replaceAll(' ', '_')}'
                                      : '';
                                  String docId =
                                      "${terId}_${tarjetaId}_${nombreDireccion.replaceAll(' ', '_')}${complementoSlug}_$timestamp";

                                  await FirebaseFirestore.instance
                                      .collection('direcciones_globales')
                                      .doc(docId)
                                      .set({
                                    'calle': nombreDireccion,
                                    'direccion_normalizada':
                                        _normalizarDireccion(
                                      '$nombreDireccion ${complementoCtrl.text.trim()}',
                                    ),
                                    'complemento': complementoCtrl.text.trim(),
                                    'informacion': informacionCtrl.text.trim(),
                                    'barrio': terId,
                                    'lat': '0',
                                    'lon': '0',
                                    'estado': 'activa',
                                    'territorio_id': terId,
                                    'tarjeta_id': tarjetaId,
                                    'created_at': FieldValue.serverTimestamp(),
                                    'tipo': 'manual',
                                    'estado_predicacion': 'pendiente',
                                    'predicado': false,
                                    'no_predicado': false,
                                    'es_hispano': true,
                                    'entrego_invitacion': false,
                                    'campana_especial': false,
                                    'publicador_email': null,
                                  });

                                  DocumentSnapshot snap =
                                      await FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(terId)
                                          .collection('tarjetas')
                                          .doc(tarjetaId)
                                          .get();
                                  int currentCount = snap.data() != null
                                      ? (snap.data()
                                              as Map)['cantidad_direcciones'] ??
                                          0
                                      : 0;

                                  await FirebaseFirestore.instance
                                      .collection('territorios')
                                      .doc(terId)
                                      .collection('tarjetas')
                                      .doc(tarjetaId)
                                      .update({
                                    'cantidad_direcciones': currentCount + 1,
                                  });

                                  if (context.mounted) {
                                    direccionCtrl.clear();
                                    complementoCtrl.clear();
                                    informacionCtrl.clear();
                                    setLocalState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '✅ Dirección agregada correctamente',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('❌ Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar Dirección'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'O seleccionar del Directorio Global:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('direcciones_globales')
                            .where('tarjeta_id', isNull: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );

                          if (snapshot.data!.docs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.inbox,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'No hay direcciones sin asignar en el Directorio Global',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              bool isChecked = idsSeleccionados.contains(
                                doc.id,
                              );
                              return CheckboxListTile(
                                dense: true,
                                title: Text(
                                  doc['calle'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      size: 12,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      doc['barrio'] ?? 'Sin barrio',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                value: isChecked,
                                onChanged: (val) {
                                  setLocalState(() {
                                    if (val == true) {
                                      idsSeleccionados.add(doc.id);
                                    } else {
                                      idsSeleccionados.remove(doc.id);
                                    }
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton.icon(
                        onPressed: idsSeleccionados.isEmpty
                            ? null
                            : () async {
                                WriteBatch batch =
                                    FirebaseFirestore.instance.batch();

                                for (String idDir in idsSeleccionados) {
                                  batch.update(
                                    FirebaseFirestore.instance
                                        .collection('direcciones_globales')
                                        .doc(idDir),
                                    {
                                      'tarjeta_id': tarjetaId,
                                      'territorio_id': terId,
                                      'barrio': terId,
                                      'estado': 'asignada',
                                      'estado_predicacion': 'pendiente',
                                      'predicado': false,
                                      'no_predicado': false,
                                      'es_hispano': true,
                                      'entrego_invitacion': false,
                                      'campana_especial': false,
                                      'publicador_email': null,
                                    },
                                  );
                                }

                                DocumentSnapshot snap = await FirebaseFirestore
                                    .instance
                                    .collection('territorios')
                                    .doc(terId)
                                    .collection('tarjetas')
                                    .doc(tarjetaId)
                                    .get();
                                int currentCount = snap.data() != null
                                    ? (snap.data()
                                            as Map)['cantidad_direcciones'] ??
                                        0
                                    : 0;

                                batch.update(
                                  FirebaseFirestore.instance
                                      .collection('territorios')
                                      .doc(terId)
                                      .collection('tarjetas')
                                      .doc(tarjetaId),
                                  {
                                    'cantidad_direcciones':
                                        currentCount + idsSeleccionados.length,
                                  },
                                );

                                await batch.commit();

                                if (parentContext.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✅ ${idsSeleccionados.length} direcciones asignadas a $tarjetaNombre',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.add_task),
                        label: const Text(
                          'Asignar Seleccionados',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _subirCSVATarjeta(
    BuildContext context,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
    StateSetter setLocalState,
  ) {
    startCsvUpload(
      (String contenido) async {
        List<String> lineas = contenido.split('\n');
        if (lineas.isNotEmpty) lineas.removeAt(0); // quitar header

        List<Map<String, String>> direcciones = [];

        for (var linea in lineas) {
          linea = linea.trim();
          if (linea.isEmpty) continue;

          // Parseo correcto de CSV con campos entre comillas
          List<String> columnas = _parsearLineaCSV(linea);
          if (columnas.length < 3) continue;

          final calle = columnas[2].trim();
          final complemento = columnas.length > 3 ? columnas[3].trim() : '';
          final informacion = columnas.length > 4 ? columnas[4].trim() : '';

          if (calle.isEmpty) continue;
          direcciones.add({
            'calle': calle,
            'complemento': complemento,
            'informacion': informacion,
          });
        }

        if (direcciones.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontraron direcciones')),
          );
          return;
        }

        // Mostrar loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Importando direcciones...')),
              ],
            ),
          ),
        );

        try {
          final batch = FirebaseFirestore.instance.batch();

          for (final dir in direcciones) {
            final calle = dir['calle'] ?? '';
            final complemento = dir['complemento'] ?? '';
            final informacion = dir['informacion'] ?? '';
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final complementoSlug = complemento.isNotEmpty
                ? '_${complemento.replaceAll(' ', '_')}'
                : '';
            final docId =
                '${terId}_${tarjetaId}_${calle.replaceAll(' ', '_').replaceAll(',', '')}${complementoSlug}_$timestamp';

            batch.set(
              FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .doc(docId),
              {
                'calle': calle,
                'complemento': complemento,
                'informacion': informacion,
                'direccion_normalizada': _normalizarDireccion(
                  '$calle $complemento',
                ),
                'barrio': terId,
                'lat': '0',
                'lon': '0',
                'estado': 'activa',
                'territorio_id': terId,
                'tarjeta_id': tarjetaId,
                'created_at': FieldValue.serverTimestamp(),
                'tipo': 'csv',
                'estado_predicacion': 'pendiente',
                'predicado': false,
                'no_predicado': false,
                'es_hispano': true,
                'entrego_invitacion': false,
                'campana_especial': false,
                'asignado_a': null,
              },
            );
          }

          await batch.commit();

          // Actualizar contador
          await FirebaseFirestore.instance
              .collection('territorios')
              .doc(terId)
              .collection('tarjetas')
              .doc(tarjetaId)
              .update({'cantidad_direcciones': direcciones.length});

          if (context.mounted) Navigator.pop(context); // cerrar loading

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ ${direcciones.length} direcciones importadas a $tarjetaNombre',
              ),
              backgroundColor: Colors.green,
            ),
          );

          setLocalState(() {});
        } catch (e) {
          if (context.mounted) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
          );
        }
      },
    );
  }

  // Parser CSV que maneja campos entre comillas
  List<String> _parsearLineaCSV(String linea) {
    List<String> resultado = [];
    bool dentroComillas = false;
    StringBuffer campo = StringBuffer();

    for (int i = 0; i < linea.length; i++) {
      final char = linea[i];
      if (char == '"') {
        dentroComillas = !dentroComillas;
      } else if (char == ',' && !dentroComillas) {
        resultado.add(campo.toString());
        campo.clear();
      } else {
        campo.write(char);
      }
    }
    resultado.add(campo.toString());
    return resultado;
  }

  // Method to format scheduled date for display
  String _formatScheduledDate(String? isoDate) {
    if (isoDate == null) return 'No programado';

    try {
      DateTime dateTime = DateTime.parse(isoDate);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  // Method to cancel scheduled send
  void _cancelarProgramacionEnvio(String terId, String tarjetaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({'programado': false, 'programado_envio': null});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Programación de envío cancelada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al cancelar programación: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleBloqueoTarjeta(
    String terId,
    String tarjetaId,
    bool bloqueadoActual,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({'bloqueado': !bloqueadoActual});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bloqueadoActual
                ? '✅ Tarjeta desbloqueada correctamente'
                : '🔒 Tarjeta bloqueada correctamente',
          ),
          backgroundColor: bloqueadoActual ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al cambiar estado de bloqueo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
    return _buildMisTarjetas();
  }

  Widget _buildVistaLocalizador() {
    return LocalizadorTab(
      usuarioEmail: _usuarioEmail,
    );
  }

  Widget _buildContenidoAdminTerritorios() {
    return AdminTerritoriosTab(
      usuarioData: widget.usuarioData,
    );
  }

  Future<void> _mostrarDialogoSolicitarTerritorioPublicador() async {
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
                // ✅ Sin filtro en territorios — muestra TODOS
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
                        child: Text(
                          'No hay territorios.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, i) {
                        final terDoc = snapshot.data!.docs[i];
                        final terNombre =
                            (terDoc.data() as Map<String, dynamic>)['nombre'] ??
                                terDoc.id;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: const Icon(
                              Icons.folder,
                              color: Color(0xFF1B5E20),
                            ),
                            title: Text(
                              terNombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text('Toca para ver tarjetas'),
                            children: [
                              StreamBuilder<QuerySnapshot>(
                                // ✅ Filtra SOLO por bloqueado == false en tarjetas
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
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  // Filtra en memoria las que no están asignadas
                                  final tarjetas =
                                      (tarjetasSnap.data?.docs ?? []).where((
                                    doc,
                                  ) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final asignado =
                                        d['asignado_a']?.toString() ?? '';
                                    return asignado.isEmpty;
                                  }).toList();

                                  if (tarjetas.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'No hay tarjetas disponibles.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    );
                                  }

                                  return Column(
                                    children: tarjetas.map((tarjetaDoc) {
                                      final data = tarjetaDoc.data()
                                          as Map<String, dynamic>;
                                      final tarjetaNombre =
                                          data['nombre'] ?? tarjetaDoc.id;

                                      // ✅ NUEVO: StreamBuilder para contar direcciones reales en tiempo real
                                      return StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id',
                                                isEqualTo: tarjetaDoc.id)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          final cantDirReal =
                                              dirSnapshot.data?.docs.length ??
                                                  0;

                                          return ListTile(
                                            leading: const Icon(
                                              Icons.credit_card,
                                              color: Colors.blue,
                                            ),
                                            title: Text(tarjetaNombre),
                                            subtitle: Text(
                                                '$cantDirReal direcciones'), // ✅ Ahora muestra el conteo real
                                            trailing: ElevatedButton(
                                              onPressed: cantDirReal >
                                                      0 // ✅ Solo permite tomar si hay direcciones
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
                                                backgroundColor: cantDirReal > 0
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

  Future<void> _asignarTarjetaAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .set({
        'asignado_a': widget.usuarioData['nombre'] ?? '',
        'disponible_para_publicadores': false,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(), // para el timer
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Tarjeta "$tarjetaNombre" asignada a ti'),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _devolverTarjeta(String territorioId, String tarjetaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': '',
        'disponible_para_publicadores': true,
        'asignado_en': null,
        'tomado_en': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarjeta devuelta exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al devolver tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  Widget _buildMisTarjetas() {
    final nombrePublicador = widget.usuarioData['nombre'] ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where('asignado_a', isEqualTo: nombrePublicador)
          .where('completada', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No tienes tarjetas asignadas.'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, i) {
            final tarjeta = snapshot.data!.docs[i];
            final data = tarjeta.data() as Map<String, dynamic>;
            final territorioId = tarjeta.reference.parent.parent!.id;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: const Icon(Icons.credit_card, color: Colors.blue),
                title: Text(
                  data['nombre'] ?? tarjeta.id,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${data['cantidad_direcciones'] ?? 0} direcciones',
                ),
                onExpansionChanged: (expanded) {
                  setState(() {
                    _tarjetaExpandida[tarjeta.id] = expanded;
                  });
                },
                initiallyExpanded: _tarjetaExpandida[tarjeta.id] ?? false,
                trailing: TextButton(
                  onPressed: () async {
                    // Check if any checkboxes have been marked for this card
                    final estadosTarjeta = _estadosPorTarjeta[tarjeta.id] ?? {};

                    // Allow return only if no checkboxes have been marked
                    bool hayCambios = false;
                    for (final dirId in estadosTarjeta.keys) {
                      if (estadosTarjeta[dirId] != '') {
                        hayCambios = true;
                        break;
                      }
                    }

                    if (!hayCambios) {
                      // Show confirmation dialog for returning card without changes
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Devolver tarjeta'),
                          content: Text(
                            '¿Devolver "${data['nombre'] ?? tarjeta.id}"? Quedará disponible para otros.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Devolver'),
                            ),
                          ],
                        ),
                      );

                      if (confirmar == true) {
                        _devolverTarjeta(territorioId, tarjeta.id);
                      }
                    } else {
                      // Show alert for returning card with changes
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Tarjeta con cambios'),
                          content: const Text(
                            'Esta tarjeta tiene cambios marcados. Si la devuelve, los cambios se perderán. ¿Desea devolverla de todas formas?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Devolver igualmente'),
                            ),
                          ],
                        ),
                      );

                      if (confirmar == true) {
                        _devolverTarjeta(territorioId, tarjeta.id);
                      }
                    }
                  },
                  child: const Text(
                    'Devolver',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                children: [_buildDireccionesTarjeta(tarjeta.id)],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDireccionesTarjeta(String tarjetaId) {
    return StatefulBuilder(
      builder: (context, setState) {
        // Inicializar si no existe para esta tarjeta
        if (!_estadosPorTarjeta.containsKey(tarjetaId)) {
          _estadosPorTarjeta[tarjetaId] = {};
          _textosPorTarjeta[tarjetaId] = {};
          _modificadosPorTarjeta[tarjetaId] = {};
          _tarjetaModificada[tarjetaId] = false;
          _tarjetaExpandida[tarjetaId] = false;
        }

        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('tarjeta_id', isEqualTo: tarjetaId)
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Sin direcciones.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            // Inicializar estados locales si está vacío
            if (_estadosPorTarjeta[tarjetaId]!.isEmpty) {
              for (final dirDoc in snapshot.data!.docs) {
                final data = dirDoc.data() as Map<String, dynamic>;
                _estadosPorTarjeta[tarjetaId]![dirDoc.id] =
                    data['estado_predicacion'] ?? '';
                _textosPorTarjeta[tarjetaId]![dirDoc.id] =
                    data['otro_texto'] ?? '';
                _modificadosPorTarjeta[tarjetaId]![dirDoc.id] = false;
              }
            }

            return Column(
              children: [
                // Lista de direcciones con checkboxes
                ...snapshot.data!.docs.map((dirDoc) {
                  final data = dirDoc.data() as Map<String, dynamic>;
                  final estadoLocal =
                      _estadosPorTarjeta[tarjetaId]?[dirDoc.id] ?? '';
                  final otroTextoLocal =
                      _textosPorTarjeta[tarjetaId]?[dirDoc.id] ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data['calle'] ?? ''}${(data['complemento'] ?? '').isNotEmpty ? ' · ${data['complemento']}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),

                        // Radio buttons con estado local
                        RadioGroup<String>(
                          groupValue: estadoLocal,
                          onChanged: (value) async {
                            setState(() {
                              _estadosPorTarjeta[tarjetaId]![dirDoc.id] =
                                  value!;
                              _modificadosPorTarjeta[tarjetaId]![dirDoc.id] =
                                  true;
                              _tarjetaModificada[tarjetaId] = true;
                            });

                            // Guardar en Firestore según la opción seleccionada
                            if (value == 'predicado') {
                              await FirebaseFirestore.instance
                                  .collection('direcciones_globales')
                                  .doc(dirDoc.id)
                                  .update({
                                'predicado': true,
                                'no_predicado': false,
                                'es_hispano': true,
                                'estado_predicacion': 'completada',
                                'fecha_predicacion':
                                    FieldValue.serverTimestamp(),
                                'mes_predicacion':
                                    '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
                              });
                            } else if (value == 'no_predicado') {
                              await FirebaseFirestore.instance
                                  .collection('direcciones_globales')
                                  .doc(dirDoc.id)
                                  .update({
                                'predicado': false,
                                'no_predicado': true,
                                'es_hispano': true,
                                'estado_predicacion': 'pendiente',
                                'mes_predicacion':
                                    '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
                              });
                            } else if (value == 'no_hispano') {
                              await FirebaseFirestore.instance
                                  .collection('direcciones_globales')
                                  .doc(dirDoc.id)
                                  .update({
                                'predicado': false,
                                'no_predicado': false,
                                'es_hispano': false,
                                'estado_predicacion': 'no_hispano',
                                'mes_predicacion':
                                    '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
                              });
                            }
                          },
                          child: Column(
                            children: [
                              {
                                'valor': 'predicado',
                                'label': 'Se predicó',
                                'color': Colors.green,
                              },
                              {
                                'valor': 'no_predicado',
                                'label': 'No se predicó',
                                'color': Colors.red,
                              },
                              {
                                'valor': 'no_hispano',
                                'label': 'No vive hispanohablante',
                                'color': Colors.orange,
                              },
                              {
                                'valor': 'otro',
                                'label': 'Otro',
                                'color': Colors.grey,
                              },
                            ].map((opcion) {
                              return RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  opcion['label'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: opcion['color'] as Color? ??
                                        Colors.blue,
                                  ),
                                ),
                                value: opcion['valor'] as String? ?? '',
                                activeColor:
                                    opcion['color'] as Color? ?? Colors.blue,
                              );
                            }).toList(),
                          ),
                        ),

                        // Campo texto si seleccionó "otro"
                        if (estadoLocal == 'otro')
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: TextField(
                              controller:
                                  TextEditingController(text: otroTextoLocal)
                                    ..selection = TextSelection.fromPosition(
                                      TextPosition(
                                        offset: otroTextoLocal.length,
                                      ),
                                    ),
                              decoration: InputDecoration(
                                hintText: 'Describe la situación...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                              ),
                              maxLines: 2,
                              onChanged: (value) {
                                setState(() {
                                  _textosPorTarjeta[tarjetaId]![dirDoc.id] =
                                      value;
                                  _modificadosPorTarjeta[tarjetaId]![
                                      dirDoc.id] = true;
                                  _tarjetaModificada[tarjetaId] = true;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),

                // Botones de acción al final - siempre visibles
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            // Cancelar - restaurar estados originales
                            setState(() {
                              for (final dirDoc in snapshot.data!.docs) {
                                final data =
                                    dirDoc.data() as Map<String, dynamic>;
                                _estadosPorTarjeta[tarjetaId]![dirDoc.id] =
                                    data['estado_predicacion'] ?? '';
                                _textosPorTarjeta[tarjetaId]![dirDoc.id] =
                                    data['otro_texto'] ?? '';
                                _modificadosPorTarjeta[tarjetaId]![dirDoc.id] =
                                    false;
                              }
                              _tarjetaModificada[tarjetaId] = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            // Validación simple
                            final totalDirs = snapshot.data!.docs.length;
                            final estados = _estadosPorTarjeta[tarjetaId] ?? {};
                            int marcadas = 0;
                            final opcionesValidas = [
                              'predicado',
                              'no_predicado',
                              'no_hispano',
                              'otro',
                            ];

                            for (final dirId in estados.keys) {
                              final estado = estados[dirId];
                              if (estado != null &&
                                  estado.isNotEmpty &&
                                  opcionesValidas.contains(estado)) {
                                marcadas++;
                              }
                            }

                            if (marcadas < totalDirs) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Debes marcar todas las direcciones antes de confirmar',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              return;
                            }

                            // Confirmación simple
                            final confirmado = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Confirmar'),
                                content: const Text('¿Finalizar esta tarjeta?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Confirmar'),
                                  ),
                                ],
                              ),
                            );

                            if (confirmado == true) {
                              try {
                                // Obtener territorioId
                                String territorioId = '';
                                if (snapshot.data!.docs.isNotEmpty) {
                                  final firstDoc = snapshot.data!.docs.first;
                                  final data =
                                      firstDoc.data() as Map<String, dynamic>;
                                  territorioId = data['territorio_id'] ?? '';
                                }

                                // Actualizar tarjeta
                                await FirebaseFirestore.instance
                                    .collection('territorios')
                                    .doc(territorioId)
                                    .collection('tarjetas')
                                    .doc(tarjetaId)
                                    .update({
                                  'completada': true,
                                  'asignado_a': '',
                                });

                                // Mostrar éxito
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Tarjeta completada'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Confirmar'),
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
  }

  Widget _buildContenidoConductor() {
    return ConductorTab(
      usuarioData: widget.usuarioData,
      usuarioEmail: _usuarioEmail,
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
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────

  void _verificarReinicioMensual() async {
    final ahora = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Obtener el último mes de reinicio guardado
    final ultimoMesReinicio = prefs.getInt('ultimo_mes_reinicio') ?? -1;
    final mesActual = ahora.month;
    final anioActual = ahora.year;

    // Solo ejecutar el reinicio el día 1 de cada mes Y si el mes es diferente
    if (ahora.day == 1 && mesActual != ultimoMesReinicio) {
      await _logicaReinicio(silencioso: true); // Ejecutar en modo silencioso

      // Actualizar el mes guardado
      await prefs.setInt('ultimo_mes_reinicio', mesActual);
      await prefs.setInt('ultimo_anio_reinicio', anioActual);

      debugPrint(
          '🔄 Reinicio mensual automático ejecutado silenciosamente - Mes: $mesActual, Año: $anioActual');
    }
  }

  Future<void> _resetearDireccionesGlobales() async {
    debugPrint('📍 Reseteando direcciones globales...');

    // Solo resetear direcciones activas (eliminado_at == null)
    final snapshot = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('eliminado_at', isNull: true)
        .get();

    // Procesar en lotes de 500 para evitar límites de Firestore
    final totalDocs = snapshot.docs.length;
    int procesados = 0;

    while (procesados < totalDocs) {
      final batch = FirebaseFirestore.instance.batch();
      final finLote = (procesados + 500).clamp(0, totalDocs);

      for (int i = procesados; i < finLote; i++) {
        final doc = snapshot.docs[i];
        batch.update(doc.reference, {
          'tarjeta_id': null,
          'visitado': false,
          'estado': 'disponible',
          'publicador_email': null,
          'fecha_visita': null,
          'estado_predicacion': null,
          'predicado': false,
        });
      }

      await batch.commit();
      procesados = finLote;
      debugPrint('📍 Procesados $procesados/$totalDocs direcciones...');
    }

    debugPrint('✅ Direcciones globales reseteadas');
  }

  Future<void> _eliminarTarjetasTemporales() async {
    debugPrint('🗑️ Eliminando tarjetas temporales...');

    // Obtener todos los territorios
    final territoriosSnapshot =
        await FirebaseFirestore.instance.collection('territorios').get();

    int totalEliminadas = 0;

    for (final territorioDoc in territoriosSnapshot.docs) {
      // Eliminar la subcolección 'temporales' si existe
      final temporalesSnapshot =
          await territorioDoc.reference.collection('temporales').get();

      if (temporalesSnapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();

        // Eliminar todos los documentos de la subcolección temporales
        for (final tempDoc in temporalesSnapshot.docs) {
          // Eliminar la subcolección 'tarjetas' dentro de cada temporal
          final tarjetasSnapshot =
              await tempDoc.reference.collection('tarjetas').get();

          for (final tarjetaDoc in tarjetasSnapshot.docs) {
            batch.delete(tarjetaDoc.reference);
          }

          // Eliminar el documento temporal
          batch.delete(tempDoc.reference);
        }

        await batch.commit();
        totalEliminadas += temporalesSnapshot.docs.length;
      }
    }

    debugPrint('✅ Eliminadas $totalEliminadas colecciones temporales');
  }

  Future<void> _limpiarAsignacionesTarjetasFijas() async {
    debugPrint('🧹 Limpiando asignaciones de tarjetas fijas...');

    // Obtener TODAS las tarjetas (fijas y temporales) para asegurar limpieza completa
    final tarjetasSnapshot =
        await FirebaseFirestore.instance.collectionGroup('tarjetas').get();

    // Procesar en lotes de 500
    final totalDocs = tarjetasSnapshot.docs.length;
    int procesados = 0;

    while (procesados < totalDocs) {
      final batch = FirebaseFirestore.instance.batch();
      final finLote = (procesados + 500).clamp(0, totalDocs);

      for (int i = procesados; i < finLote; i++) {
        final doc = tarjetasSnapshot.docs[i];
        batch.update(doc.reference, {
          // Campos de asignación
          'asignado_a': null,
          'asignado_en': null,
          'tomado_en': null,
          'publicador_id': null,
          'publicador_nombre': null,
          'fecha_entrega': null,
          'entregado_a': null,

          // Campos de envío (completos)
          'enviado_a': null,
          'enviado_nombre': null,
          'enviado_en': null,
          'enviado_on': null,
          'enviado_por_conductor': null,
          'enviado_tipo': null,
          'estatus_envio': null,
          'conductor_email': null,
          'publicador_email': null,

          // Timestamps adicionales que podrían existir
          'enviado_timestamp': null,
          'fecha_envio': null,
          'timestamp_envio': null,
          'enviado_at': null,

          // Estado de la tarjeta
          'estado': 'disponible',
          'bloqueado': false,
          'disponible_para_publicadores': true,
          'cantidad_direcciones': 0,
        });
      }

      await batch.commit();
      procesados = finLote;
      debugPrint('🧹 Procesadas $procesados/$totalDocs tarjetas fijas...');
    }

    debugPrint('✅ Asignaciones de tarjetas fijas limpiadas');
  }

  Future<void> _logicaReinicio({bool silencioso = false}) async {
    try {
      if (!silencioso) {
        debugPrint('🧹 Iniciando lógica de reinicio...');
        debugPrint('📍 Paso 1: Resetear direcciones globales');
      }

      // 1. Resetear direcciones globales (solo activas, no removidas)
      await _resetearDireccionesGlobales();

      if (!silencioso) {
        debugPrint('📍 Paso 2: Eliminar tarjetas temporales');
      }

      // 2. Eliminar tarjetas temporales
      await _eliminarTarjetasTemporales();

      if (!silencioso) {
        debugPrint('📍 Paso 3: Limpiar asignaciones en tarjetas fijas');
      }

      // 3. Limpiar asignaciones en tarjetas fijas
      await _limpiarAsignacionesTarjetasFijas();

      if (!silencioso) {
        debugPrint('✅ Lógica de reinicio completada');

        // Forzar actualización de UI para reflejar cambios inmediatamente
        if (mounted) {
          setState(() {});

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sistema reiniciado exitosamente'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (!silencioso) {
        debugPrint('❌ Error en reinicio: $e');
        debugPrint('❌ Stack trace: ${StackTrace.current}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al reiniciar sistema: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
