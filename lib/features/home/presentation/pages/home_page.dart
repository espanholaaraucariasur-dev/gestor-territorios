import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/normalizador.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../auth/presentation/pages/login_page.dart';
// CSV
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/csv_upload.dart'
    if (dart.library.html) '../../../../core/services/csv_upload_web.dart';

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
  bool _localizadorBuscado = false;
  bool _localizadorEncontrada = false;
  String _localizadorMensaje = '';
  bool _mostrarSolicitudLocalizador = false;

  @override
  void initState() {
    super.initState();
    _tabControllerAdmin = TabController(length: 4, vsync: this);
    _usuarioEmail = widget.usuarioData['email'] ?? '';
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

  void _guardarConfiguracionComunicacion() async {
    try {
      await FirebaseFirestore.instance
          .collection('configuraciones')
          .doc('comunicacion')
          .set({
        'campana_especial_activa': _campanaEspecialActiva,
        'nombre_campana_especial': _nombreCampanaEspecial,
        'campana_general_activa': _campanaGeneralActiva,
        'anuncio_general': _anuncioGeneral,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración de comunicación guardada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar la comunicación: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
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

  String _formatoTiempoRelativo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'unos segundos';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return minutes == 1 ? '1 minuto' : '$minutes minutos';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hora' : '$hours horas';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return days == 1 ? '1 día' : '$days días';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 semana' : '$weeks semanas';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 mes' : '$months meses';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 año' : '$years años';
    }
  }

  Future<void> _buscarDireccionGlobal() async {
    final consulta = _localizadorController.text.trim();
    if (consulta.isEmpty) {
      setState(() {
        _localizadorBuscado = true;
        _localizadorEncontrada = false;
        _localizadorMensaje = 'Ingresa una dirección para buscar.';
        _mostrarSolicitudLocalizador = false;
      });
      return;
    }

    final normalizada = _normalizarDireccion(consulta);
    setState(() {
      _localizadorBuscado = true;
      _localizadorEncontrada = false;
      _localizadorMensaje = 'Buscando en el directorio global…';
      _mostrarSolicitudLocalizador = false;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        final calle =
            (docData.containsKey('calle') ? docData['calle'] : '') as String;
        final complemento = (docData.containsKey('complemento')
            ? docData['complemento']
            : '') as String;
        final docNormalizada = (docData.containsKey('direccion_normalizada')
                ? docData['direccion_normalizada'] as String?
                : null) ??
            _normalizarDireccion('$calle $complemento');
        if (docNormalizada == normalizada) {
          setState(() {
            _localizadorEncontrada = true;
            _localizadorMensaje =
                'Dirección encontrada: $calle${complemento.isNotEmpty ? ' • $complemento' : ''}';
            _mostrarSolicitudLocalizador = false;
          });
          return;
        }
      }

      final pendientes = await FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .where('direccion_normalizada', isEqualTo: normalizada)
          .get();
      if (pendientes.docs.isNotEmpty) {
        setState(() {
          _localizadorEncontrada = false;
          _localizadorMensaje =
              'Esta dirección ya fue solicitada y está pendiente de revisión.';
          _mostrarSolicitudLocalizador = false;
        });
        return;
      }

      setState(() {
        _localizadorEncontrada = false;
        _localizadorMensaje =
            'No se encontró en el directorio global. Completa el formulario para enviarla al administrador.';
        _mostrarSolicitudLocalizador = true;
      });
    } catch (e) {
      setState(() {
        _localizadorBuscado = true;
        _localizadorEncontrada = false;
        _localizadorMensaje = 'Error buscando la dirección: $e';
        _mostrarSolicitudLocalizador = false;
      });
    }
  }

  Future<void> _enviarDireccionParaRegistro() async {
    final direccion = _localizadorController.text.trim();
    if (direccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una dirección antes de enviar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final normalizada = _normalizarDireccion(direccion);
    final existenteGlobal = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('direccion_normalizada', isEqualTo: normalizada)
        .get();
    if (existenteGlobal.docs.isNotEmpty) {
      setState(() {
        _localizadorEncontrada = true;
        _localizadorMensaje = 'La dirección ya existe en el directorio global.';
        _mostrarSolicitudLocalizador = false;
      });
      return;
    }

    final existenteSolicitud = await FirebaseFirestore.instance
        .collection('solicitudes_direcciones')
        .where('direccion_normalizada', isEqualTo: normalizada)
        .get();
    if (existenteSolicitud.docs.isNotEmpty) {
      setState(() {
        _localizadorEncontrada = false;
        _localizadorMensaje =
            'Esta dirección ya fue solicitada y está pendiente de revisión.';
        _mostrarSolicitudLocalizador = false;
      });
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .add({
        'direccion_original': direccion,
        'direccion_normalizada': normalizada,
        'direccion_consultada': direccion,
        'complemento': _complementoLocalizadorController.text.trim(),
        'detalles': _detallesLocalizadorController.text.trim(),
        'solicitante_email': _usuarioEmail,
        'estado': 'pendiente',
        'created_at': FieldValue.serverTimestamp(),
      });
      setState(() {
        _localizadorMensaje =
            'Solicitud enviada correctamente. El admin revisará la dirección pronto.';
        _mostrarSolicitudLocalizador = false;
        _localizadorController.clear();
        _complementoLocalizadorController.clear();
        _detallesLocalizadorController.clear();
        _localizadorBuscado = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar solicitud: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: const [
                Icon(Icons.admin_panel_settings, color: Color(0xFF1B5E20)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Administración',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF263238),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabControllerAdmin,
              indicatorColor: const Color(0xFF1B5E20),
              indicatorWeight: 3,
              labelColor: const Color(0xFF1B5E20),
              unselectedLabelColor: Colors.black54,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.folder_copy, color: Color(0xFF1B5E20)),
                  text: 'Estructura',
                ),
                Tab(
                  icon: Icon(Icons.map, color: Color(0xFF1B5E20)),
                  text: 'Territorios',
                ),
                Tab(
                  icon: Icon(Icons.campaign, color: Color(0xFF1B5E20)),
                  text: 'Comunicación',
                ),
                Tab(
                  icon: Icon(Icons.people_outline, color: Color(0xFF1B5E20)),
                  text: 'Usuarios',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabControllerAdmin,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1. Directorio Maestro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: _levantarArchivoCSV,
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                            'Subir CSV a Directorio Maestro',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _verDirectorioGlobal,
                        icon: const Icon(
                          Icons.list_alt,
                          color: Color(0xFF1B5E20),
                        ),
                        label: const Text(
                          'Ver contenido del Directorio Global',
                          style: TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text(
                        '2. Gestión de Territorios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _mostrarDialogoCrearTerritorio,
                          icon: const Icon(Icons.create_new_folder),
                          label: const Text(
                            'Crear Nuevo Territorio',
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
                      const SizedBox(height: 20),
                      const Text(
                        'Territorios Creados:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: Text(
                                  'No hay territorios creados aún.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return GestureDetector(
                                onTap: () => _abrirTerritorio(
                                  doc.id,
                                  (doc.data()
                                          as Map<String, dynamic>)['nombre'] ??
                                      doc.id,
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  color: Colors.green.shade50,
                                  elevation: 2,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.folder,
                                      color: Color(0xFF1B5E20),
                                    ),
                                    title: Text(
                                      (doc.data() as Map<String, dynamic>)[
                                              'nombre'] ??
                                          doc.id,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(doc.id)
                                          .collection('tarjetas')
                                          .snapshots(),
                                      builder: (context, tarjetasSnapshot) {
                                        int cantidadTarjetas = tarjetasSnapshot
                                                .data?.docs.length ??
                                            0;
                                        return Text(
                                          'Tarjetas vinculadas: $cantidadTarjetas',
                                        );
                                      },
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.orange,
                                          ),
                                          onPressed: () =>
                                              _editarNombreTerritorio(doc),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_forever,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () => _borrarTerritorio(
                                            doc.id,
                                            (doc.data() as Map<String,
                                                    dynamic>)['nombre'] ??
                                                doc.id,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Territorios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: Text(
                                  'No hay territorios creados aún.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return InkWell(
                                onTap: () => _abrirTerritorio(
                                  doc.id,
                                  (doc.data()
                                          as Map<String, dynamic>)['nombre'] ??
                                      doc.id,
                                  readOnly: true,
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: const Icon(
                                                Icons.folder,
                                                color: Color(0xFF1B5E20),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (doc.data() as Map<String,
                                                                dynamic>)[
                                                            'nombre'] ??
                                                        doc.id,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  StreamBuilder<QuerySnapshot>(
                                                    stream: FirebaseFirestore
                                                        .instance
                                                        .collection(
                                                          'territorios',
                                                        )
                                                        .doc(doc.id)
                                                        .collection('tarjetas')
                                                        .snapshots(),
                                                    builder: (
                                                      context,
                                                      tarjetasSnapshot,
                                                    ) {
                                                      int cantidadTarjetas =
                                                          tarjetasSnapshot
                                                                  .data
                                                                  ?.docs
                                                                  .length ??
                                                              0;
                                                      return Text(
                                                        'Tarjetas vinculadas: $cantidadTarjetas',
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.arrow_forward_ios,
                                              size: 18,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _mostrarDialogoEnviar(
                                              terId: doc.id,
                                              nombre: (doc.data() as Map<String,
                                                      dynamic>)['nombre'] ??
                                                  doc.id,
                                            ),
                                            icon: const Icon(
                                              Icons.send,
                                              color: Colors.green,
                                            ),
                                            label: const Text(
                                              'Enviar territorio completo',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green,
                                              side: const BorderSide(
                                                color: Colors.green,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
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
                        },
                      ),
                    ],
                  ),
                ),
                _buildSeccionComunicacionAdmin(),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gestión de Usuarios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('usuarios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: Text(
                                  'No hay usuarios registrados.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: snapshot.data!.docs.map((usuario) {
                              final data =
                                  usuario.data() as Map<String, dynamic>;
                              final String nombreUsuario =
                                  data['nombre'] ?? 'Usuario';
                              final String emailUsuario = data['email'] ?? '';
                              final String estadoUsuario =
                                  data['estado'] ?? 'pendiente';
                              final bool esAdminUsuario =
                                  data['es_admin'] ?? false;
                              final bool esConductorUsuario =
                                  data['es_conductor'] ?? false;
                              final bool esAdminTerritoriosUsuario =
                                  data['es_admin_territorios'] ?? false;
                              final bool esPublicadorUsuario =
                                  data['es_publicador'] ?? false;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombreUsuario,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        emailUsuario,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Estado: $estadoUsuario',
                                              style: const TextStyle(
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          if (estadoUsuario != 'aprobado')
                                            ElevatedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection('usuarios')
                                                    .doc(usuario.id)
                                                    .update({
                                                  'estado': 'aprobado',
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                              ),
                                              child: const Text('Aprobar'),
                                            ),
                                          if (estadoUsuario == 'aprobado')
                                            ElevatedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection('usuarios')
                                                    .doc(usuario.id)
                                                    .update({
                                                  'estado': 'pendiente',
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                              ),
                                              child: const Text('Desaprobar'),
                                            ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () async {
                                              bool? confirmar =
                                                  await showDialog(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text(
                                                    'Eliminar Usuario',
                                                  ),
                                                  content: Text(
                                                    '¿Estás seguro de eliminar a $nombreUsuario?',
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
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                        c,
                                                        true,
                                                      ),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.red,
                                                      ),
                                                      child: const Text(
                                                        'Eliminar',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmar == true) {
                                                await FirebaseFirestore.instance
                                                    .collection('usuarios')
                                                    .doc(usuario.id)
                                                    .delete();
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            child: const Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SwitchListTile(
                                        title: const Text('Admin'),
                                        value: esAdminUsuario,
                                        activeThumbColor: Colors.redAccent,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection('usuarios')
                                              .doc(usuario.id)
                                              .update({'es_admin': value});
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Admin Territorios'),
                                        value: esAdminTerritoriosUsuario,
                                        activeThumbColor: Colors.purple,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection('usuarios')
                                              .doc(usuario.id)
                                              .update({
                                            'es_admin_territorios': value,
                                          });
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Conductor'),
                                        value: esConductorUsuario,
                                        activeThumbColor: const Color(
                                          0xFF1B5E20,
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection('usuarios')
                                              .doc(usuario.id)
                                              .update({'es_conductor': value});
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Publicador'),
                                        value: esPublicadorUsuario,
                                        activeThumbColor: Colors.blue,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection('usuarios')
                                              .doc(usuario.id)
                                              .update({'es_publicador': value});
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _mostrarDialogoGestionUsuarios(),
                                              child: const Text(
                                                'Gestión avanzada',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _borrarTerritorio(String territorioId, String nombreTerritorio) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar Territorio'),
        content: Text(
          '¿Eliminar el territorio "$nombreTerritorio"? Esto NO eliminará las direcciones del directorio global.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorioId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$nombreTerritorio eliminado correctamente'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
        }
      }
    }
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

  void _mostrarDialogoCrearTerritorio() {
    final TextEditingController nombreCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder_open,
                      size: 40,
                      color: Color(0xFF1B5E20),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Crear Nuevo Territorio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nombreCtrl,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Nombre del territorio',
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
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          String nombre = nombreCtrl.text.trim();
                          if (nombre.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un nombre'),
                              ),
                            );
                            return;
                          }
                          await FirebaseFirestore.instance
                              .collection('territorios')
                              .doc(nombre)
                              .set({
                            'nombre': nombre,
                            'cantidad_direcciones': 0,
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Crear Carpeta',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
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
          ),
        );
      },
    );
  }

  void _editarNombreTerritorio(DocumentSnapshot doc) {
    final TextEditingController nombreCtrl = TextEditingController(
      text: (doc.data() as Map<String, dynamic>)['nombre'] ?? doc.id,
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
                  'Editar Territorio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nombreCtrl,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Nombre del territorio',
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

                          // Obtener todos los datos del territorio actual
                          Map<String, dynamic> datosActuales =
                              doc.data() as Map<String, dynamic>;

                          // Crear nuevo documento con el nuevo nombre
                          await FirebaseFirestore.instance
                              .collection('territorios')
                              .doc(nuevoNombre)
                              .set(datosActuales);

                          // Borrar el documento antiguo
                          await FirebaseFirestore.instance
                              .collection('territorios')
                              .doc(doc.id)
                              .delete();

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

  void _mostrarDialogoGestionUsuarios() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Gestión de Usuarios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('usuarios')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No hay usuarios registrados.'),
                        );
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final usuario = docs[index];
                          final data = usuario.data() as Map<String, dynamic>;
                          final esAdmin = data['es_admin'] ?? false;
                          final esConductor = data['es_conductor'] ?? false;
                          final esPublicador = data['es_publicador'] ?? false;
                          final esAdminTerritorios =
                              data['es_admin_territorios'] ?? false;
                          final grupoId = data['grupo_id'] ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['nombre'] ?? 'Usuario',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    data['email'] ?? '',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SwitchListTile(
                                          title: const Text('Admin'),
                                          value: esAdmin,
                                          contentPadding: EdgeInsets.zero,
                                          activeThumbColor: Colors.redAccent,
                                          onChanged: (value) async {
                                            await FirebaseFirestore.instance
                                                .collection('usuarios')
                                                .doc(usuario.id)
                                                .update({'es_admin': value});
                                          },
                                        ),
                                      ),
                                      Expanded(
                                        child: SwitchListTile(
                                          title: const Text('Conductor'),
                                          value: esConductor,
                                          contentPadding: EdgeInsets.zero,
                                          activeThumbColor: const Color(
                                            0xFF1B5E20,
                                          ),
                                          onChanged: (value) async {
                                            await FirebaseFirestore.instance
                                                .collection('usuarios')
                                                .doc(usuario.id)
                                                .update({
                                              'es_conductor': value,
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  SwitchListTile(
                                    title: const Text('Publicador'),
                                    value: esPublicador,
                                    contentPadding: EdgeInsets.zero,
                                    activeThumbColor: Colors.blue,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance
                                          .collection('usuarios')
                                          .doc(usuario.id)
                                          .update({'es_publicador': value});
                                    },
                                  ),
                                  SwitchListTile(
                                    title: const Text('Admin Territorios'),
                                    value: esAdminTerritorios,
                                    contentPadding: EdgeInsets.zero,
                                    activeThumbColor: Colors.purple,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance
                                          .collection('usuarios')
                                          .doc(usuario.id)
                                          .update({
                                        'es_admin_territorios': value,
                                      });
                                    },
                                  ),
                                  TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Grupo ID',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      isDense: true,
                                    ),
                                    controller: TextEditingController(
                                      text: grupoId.toString(),
                                    ),
                                    readOnly: true,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
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
                      'Cerrar',
                      style: TextStyle(color: Colors.white),
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

  Future<void> _liberarTodasLasTarjetasDelTerritorio(
    String territorioId,
  ) async {
    try {
      // Obtener todas las tarjetas del territorio
      final tarjetasSnapshot = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .get();

      // Actualizar todas las tarjetas para que estén disponibles
      final batch = FirebaseFirestore.instance.batch();

      for (final tarjetaDoc in tarjetasSnapshot.docs) {
        batch.update(tarjetaDoc.reference, {
          'bloqueado': false,
          'asignado_a': '',
          'asignado_en': null,
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Todas las tarjetas del territorio han sido liberadas',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al liberar tarjetas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _verDirectorioGlobal() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Directorio Global',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('direcciones_globales')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'El Directorio Global está vacío',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          var doc = snapshot.data!.docs[index];
                          String estado = doc['estado'] ?? 'desconocido';
                          Color colorEstado =
                              estado == 'asignada' ? Colors.green : Colors.grey;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.location_on,
                              color: colorEstado,
                              size: 20,
                            ),
                            title: Text(
                              doc['calle'],
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              doc['barrio'] ?? 'Sin barrio',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.grey,
                              ),
                              onSelected: (value) async {
                                if (value == 'eliminar') {
                                  bool? confirmar = await showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Eliminar Dirección'),
                                      content: Text(
                                        '¿Eliminar "${doc['calle']}" del directorio global?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Cancelar'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text(
                                            'Eliminar',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    await FirebaseFirestore.instance
                                        .collection('direcciones_globales')
                                        .doc(doc.id)
                                        .delete();
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text(
                                    'Eliminar dirección',
                                    style: TextStyle(color: Colors.red),
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

  void _levantarArchivoCSV() {
    startCsvUpload(
      (String contenidoDelArchivo) {
        List<String> lineas = contenidoDelArchivo.split('\n');
        if (lineas.isNotEmpty) lineas.removeAt(0); // quitar header

        // Estructura: { nombreTarjeta: [ {calle, complemento} ] }
        Map<String, List<Map<String, String>>> tarjetasMap = {};

        for (var linea in lineas) {
          if (linea.trim().isEmpty) continue;
          List<String> columnas = linea.split(',');
          if (columnas.length < 3) continue;

          final tarjeta = columnas[0].trim(); // TERRITORIO = nombre tarjeta
          // columnas[1] = REF (ignorar)
          final calle = columnas[2].trim();
          final complemento = columnas.length > 3 ? columnas[3].trim() : '';

          if (tarjeta.isEmpty || calle.isEmpty) continue;

          tarjetasMap.putIfAbsent(tarjeta, () => []);
          tarjetasMap[tarjeta]!.add({
            'calle': calle,
            'complemento': complemento,
          });
        }

        if (tarjetasMap.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudieron extraer datos del CSV'),
            ),
          );
          return;
        }

        // Pedir al admin a qué territorio pertenecen estas tarjetas
        _mostrarSelectorTerritorioParaCSV(tarjetasMap);
      },
    );
  }

  void _mostrarSelectorTerritorioParaCSV(
    Map<String, List<Map<String, String>>> tarjetasMap,
  ) async {
    final territoriosSnap =
        await FirebaseFirestore.instance.collection('territorios').get();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿A qué territorio pertenece este CSV?'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: territoriosSnap.docs.map((doc) {
              final nombre = (doc.data())['nombre'] ?? doc.id;
              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                title: Text(nombre),
                onTap: () {
                  Navigator.pop(context);
                  _procesarCSVEnTerritorio(doc.id, tarjetasMap);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _procesarCSVEnTerritorio(
    String territorioId,
    Map<String, List<Map<String, String>>> tarjetasMap,
  ) async {
    // Mostrar progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Creando tarjetas y direcciones...')),
          ],
        ),
      ),
    );

    try {
      int totalTarjetas = 0;
      int totalDirecciones = 0;

      for (final entry in tarjetasMap.entries) {
        final nombreTarjeta = entry.key;
        final direcciones = entry.value;

        // Crear tarjeta
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(nombreTarjeta)
            .set({
          'nombre': nombreTarjeta,
          'territorio_id': territorioId,
          'estado': 'disponible',
          'cantidad_direcciones': direcciones.length,
          'barrio': '',
          'created_at': FieldValue.serverTimestamp(),
          'bloqueado': true,
          'disponible_para_publicadores': false,
          'asignado_a': '',
          'asignado_en': null,
        }, SetOptions(merge: true));

        // Crear direcciones de esa tarjeta
        final batch = FirebaseFirestore.instance.batch();
        for (final dir in direcciones) {
          final calle = dir['calle'] ?? '';
          final complemento = dir['complemento'] ?? '';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final complementoSlug = complemento.isNotEmpty
              ? '_${complemento.replaceAll(' ', '_')}'
              : '';
          final docId =
              '${territorioId}_${nombreTarjeta}_${calle.replaceAll(' ', '_')}${complementoSlug}_$timestamp';

          batch.set(
            FirebaseFirestore.instance
                .collection('direcciones_globales')
                .doc(docId),
            {
              'calle': calle,
              'complemento': complemento,
              'direccion_normalizada': _normalizarDireccion(
                '$calle $complemento',
              ),
              'informacion': '',
              'barrio': territorioId,
              'lat': '0',
              'lon': '0',
              'estado': 'activa',
              'territorio_id': territorioId,
              'tarjeta_id': nombreTarjeta,
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
          totalDirecciones++;
        }
        await batch.commit();
        totalTarjetas++;
      }

      if (mounted) {
        Navigator.pop(context); // cerrar loading
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ CSV importado'),
            content: Text(
              '$totalTarjetas tarjetas creadas\n$totalDirecciones direcciones agregadas\n\nTerritorio: $territorioId',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildVistaTarjetas() {
    return _buildMisTarjetas();
  }

  Widget _buildVistaLocalizador() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_searching,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Localizador de direcciones',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Busca direcciones en el directorio global o solicita agregar nuevas',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),

        // Buscador
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _localizadorController,
                  decoration: InputDecoration(
                    hintText: 'Ingresa calle, número o punto de referencia',
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
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  onChanged: (_) {
                    if (_localizadorBuscado) {
                      setState(() {
                        _localizadorBuscado = false;
                        _localizadorMensaje = '';
                        _mostrarSolicitudLocalizador = false;
                      });
                    }
                  },
                  onSubmitted: (_) => _buscarDireccionGlobal(),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _buscarDireccionGlobal,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar dirección'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Resultados y formulario
        if (_localizadorBuscado)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: _localizadorEncontrada
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _localizadorEncontrada
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _localizadorEncontrada
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFFE65100),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _localizadorMensaje,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _localizadorEncontrada
                                    ? const Color(0xFF1B5E20)
                                    : const Color(0xFF4E342E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_localizadorEncontrada &&
                          _mostrarSolicitudLocalizador) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Solicitar registro de dirección',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF263238),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _complementoLocalizadorController,
                          decoration: InputDecoration(
                            hintText: 'Complemento / referencia adicional',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1B5E20),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _detallesLocalizadorController,
                          decoration: InputDecoration(
                            hintText: 'Detalles adicionales (opcional)',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1B5E20),
                                width: 2,
                              ),
                            ),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _enviarDireccionParaRegistro,
                          icon: const Icon(Icons.send),
                          label: const Text('Enviar para registro'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Historial de búsquedas recientes
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Búsquedas recientes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF263238),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('solicitudes_direcciones')
                      .where('solicitante_email', isEqualTo: _usuarioEmail)
                      .orderBy('created_at', descending: true)
                      .limit(5)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final solicitudes = snapshot.data!.docs;

                    if (solicitudes.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No hay búsquedas recientes',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      );
                    }

                    // Lógica de deduplicación
                    final Map<String, DocumentSnapshot> busquedasUnicas = {};
                    for (final doc in solicitudes) {
                      final data = doc.data() as Map<String, dynamic>;
                      final direccionNormalizada =
                          data['direccion_normalizada']?.toString() ?? '';
                      if (direccionNormalizada.isNotEmpty &&
                          !busquedasUnicas.containsKey(direccionNormalizada)) {
                        busquedasUnicas[direccionNormalizada] = doc;
                      }
                    }

                    return Column(
                      children: busquedasUnicas.values.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final direccion =
                            data['direccion_original'] ?? 'Sin dirección';
                        final estado = data['estado'] ?? 'pendiente';
                        final createdAt =
                            (data['created_at'] as Timestamp?)?.toDate();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: estado == 'aprobada'
                                      ? Colors.green
                                      : estado == 'rechazada'
                                          ? Colors.red
                                          : Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      direccion,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (createdAt != null)
                                      Text(
                                        'Hace ${_formatoTiempoRelativo(createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: estado == 'aprobada'
                                      ? Colors.green.shade100
                                      : estado == 'rechazada'
                                          ? Colors.red.shade100
                                          : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  estado.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: estado == 'aprobada'
                                        ? Colors.green
                                        : estado == 'rechazada'
                                            ? Colors.red
                                            : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionComunicacionAdmin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campaña Especial
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Color(0xFFE65100)),
                    const SizedBox(width: 12),
                    const Text(
                      'Campaña Especial',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Activar campaña especial'),
                  subtitle: const Text(
                    'Agrega campo extra dinámico en cada dirección del publicador',
                  ),
                  value: _campanaEspecialActiva,
                  activeThumbColor: const Color(0xFFE65100),
                  onChanged: (value) {
                    setState(() {
                      _campanaEspecialActiva = value;
                    });
                  },
                ),
                if (_campanaEspecialActiva) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _campanaEspecialController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la campaña especial',
                      hintText: 'Ej: Invitación Memorial 2026',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label, color: Color(0xFFE65100)),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _nombreCampanaEspecial = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _guardarConfiguracionComunicacion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Guardar Configuración',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Anuncio General
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.announcement, color: Color(0xFF1B5E20)),
                    const SizedBox(width: 12),
                    const Text(
                      'Anuncio General',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Activar anuncio general'),
                  subtitle: const Text(
                    'Mostrar banner en _buildContenidoPublicador',
                  ),
                  value: _campanaGeneralActiva,
                  activeThumbColor: const Color(0xFF1B5E20),
                  onChanged: (value) {
                    setState(() {
                      _campanaGeneralActiva = value;
                    });
                  },
                ),
                if (_campanaGeneralActiva) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _anuncioGeneralController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje del anuncio',
                      hintText:
                          'Escribe el mensaje que se mostrará a todos los publicadores',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.message, color: Color(0xFF1B5E20)),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _anuncioGeneral = value;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Direcciones Enviadas
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.send, color: Color(0xFF2196F3)),
                    const SizedBox(width: 12),
                    const Text(
                      'Direcciones Enviadas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('direcciones_globales')
                      .where('enviado_a', isNotEqualTo: null)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final direccionesEnviadas = snapshot.data!.docs;

                    if (direccionesEnviadas.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay direcciones enviadas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: direccionesEnviadas.length,
                      itemBuilder: (context, index) {
                        final doc = direccionesEnviadas[index];
                        final data = doc.data() as Map<String, dynamic>;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(
                              data['calle'] ?? 'Dirección sin nombre',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Complemento: ${data['complemento'] ?? 'N/A'}',
                                ),
                                Text('Detalles: ${data['detalles'] ?? 'N/A'}'),
                                Text(
                                  'Enviado a: ${data['enviado_a'] ?? 'N/A'}',
                                ),
                                Text(
                                  'Timestamp: ${data['enviado_timestamp']?.toString() ?? 'N/A'}',
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _mostrarSelectorTerritorio(data),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B5E20),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Agregar a territorio'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSelectorTerritorio(Map<String, dynamic> direccionData) async {
    final territoriosSnapshot =
        await FirebaseFirestore.instance.collection('territorios').get();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Territorio'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: territoriosSnapshot.docs.length,
            itemBuilder: (context, index) {
              final territorio = territoriosSnapshot.docs[index];
              final data = territorio.data();

              return ListTile(
                title: Text(data['nombre'] ?? 'Territorio sin nombre'),
                subtitle: Text('ID: ${territorio.id}'),
                onTap: () async {
                  Navigator.pop(context);
                  await _agregarDireccionATerritorio(
                    territorio.id,
                    direccionData,
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoRevision(
    List<DocumentSnapshot> direcciones,
  ) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revisión de ${direcciones.length} direcciones'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: direcciones.length,
            itemBuilder: (context, index) {
              final doc = direcciones[index];
              final data = doc.data() as Map<String, dynamic>;
              final removedAt = (data['removed_at'] as Timestamp?)?.toDate();
              final diasDesdeRemocion = removedAt != null
                  ? DateTime.now().difference(removedAt).inDays
                  : 0;

              return ListTile(
                title: Text(data['calle'] ?? 'Dirección sin nombre'),
                subtitle: Text('Removida hace $diasDesdeRemocion días'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green),
                      onPressed: () {
                        Navigator.pop(context);
                        _restaurarDireccion(doc.id);
                      },
                      tooltip: 'Restaurar',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _eliminarPermanentemente(doc.id);
                      },
                      tooltip: 'Eliminar permanentemente',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _restaurarDireccion(String direccionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(direccionId)
          .update({
        'es_hispano': true,
        'removed_at': null,
        'restored_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dirección restaurada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al restaurar dirección: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _eliminarPermanentemente(String direccionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(direccionId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dirección eliminada permanentemente'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar dirección: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _crearTarjetaTemporal(
    List<DocumentSnapshot> direcciones,
    String nombreTerritorio,
  ) async {
    try {
      // Crear nueva tarjeta temporal
      final tarjetasRef = FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales') // ID especial para tarjetas temporales
          .collection('tarjetas');

      final nuevaTarjeta = await tarjetasRef.add({
        'nombre': 'Temporal - $nombreTerritorio',
        'created_at': FieldValue.serverTimestamp(),
        'disponible_para_publicadores': false, // No disponible inicialmente
        'es_temporal': true,
        'territorio_origen': nombreTerritorio,
        'cantidad_direcciones': direcciones.length,
        'bloqueado': false, // Por defecto desbloqueado
        'programado': false, // Por defecto no programado
        'programado_envio': null, // Sin programación inicial
      });

      // Agregar las direcciones a la nueva tarjeta
      final direccionesRef = nuevaTarjeta.collection('direcciones');
      for (final direccionDoc in direcciones) {
        final direccionData = direccionDoc.data() as Map<String, dynamic>;
        await direccionesRef.add({
          ...direccionData,
          'tarjeta_temporal_id': nuevaTarjeta.id,
          'agregado_a_temporal': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tarjeta temporal creada: ${direcciones.length} direcciones',
          ),
          backgroundColor: const Color(0xFF4A148C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear tarjeta temporal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _agregarDireccionATerritorio(
    String territorioId,
    Map<String, dynamic> direccionData,
  ) async {
    try {
      // Crear nueva tarjeta en el territorio seleccionado
      final tarjetasRef = FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas');

      final nuevaTarjeta = await tarjetasRef.add({
        'nombre': 'Dirección Agregada',
        'created_at': FieldValue.serverTimestamp(),
        'disponible_para_publicadores': false,
        'bloqueado': false, // Por defecto desbloqueado
        'programado': false, // Por defecto no programado
        'programado_envio': null, // Sin programación inicial
      });

      // Agregar la dirección a la nueva tarjeta
      await nuevaTarjeta.collection('direcciones').add(direccionData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dirección agregada al territorio exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al agregar dirección: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildVistaEstadisticasAdminTerritorios() {
    return StatefulBuilder(
      builder: (context, setState) {
        String periodoSeleccionado = 'trimestral';

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selector de período
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Período de análisis',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Trimestral'),
                            selected: periodoSeleccionado == 'trimestral',
                            onSelected: (value) {
                              setState(() {
                                periodoSeleccionado = 'trimestral';
                              });
                            },
                            backgroundColor: Colors.grey.shade200,
                            selectedColor: const Color(0xFF4A148C),
                            labelStyle: TextStyle(
                              color: periodoSeleccionado == 'trimestral'
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Semestral'),
                            selected: periodoSeleccionado == 'semestral',
                            onSelected: (value) {
                              setState(() {
                                periodoSeleccionado = 'semestral';
                              });
                            },
                            backgroundColor: Colors.grey.shade200,
                            selectedColor: const Color(0xFF4A148C),
                            labelStyle: TextStyle(
                              color: periodoSeleccionado == 'semestral'
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Anual'),
                            selected: periodoSeleccionado == 'anual',
                            onSelected: (value) {
                              setState(() {
                                periodoSeleccionado = 'anual';
                              });
                            },
                            backgroundColor: Colors.grey.shade200,
                            selectedColor: const Color(0xFF4A148C),
                            labelStyle: TextStyle(
                              color: periodoSeleccionado == 'anual'
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Cards de estadísticas por territorio
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('territorios')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final territorios = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8),
                      itemCount: territorios.length,
                      itemBuilder: (context, index) {
                        final territorio = territorios[index];
                        final territorioData =
                            territorio.data() as Map<String, dynamic>;
                        final nombreTerritorio =
                            territorioData['nombre'] ?? 'Territorio sin nombre';

                        return FutureBuilder<QuerySnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('direcciones_globales')
                              .where('territorio_id', isEqualTo: territorio.id)
                              .get(),
                          builder: (context, direccionesSnapshot) {
                            if (!direccionesSnapshot.hasData) {
                              return const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              );
                            }

                            final direcciones = direccionesSnapshot.data!.docs;
                            final totalDirecciones = direcciones.length;
                            final predicadas = direcciones.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['predicado'] == true;
                            }).length;
                            final noHispanos = direcciones.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['es_hispano'] == false;
                            }).length;
                            final eliminadas = direcciones.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['removed_at'] != null;
                            }).length;
                            final agregadas = direcciones.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['created_at'] != null;
                            }).length;

                            final porcentajePredicadas = totalDirecciones > 0
                                ? (predicadas / totalDirecciones * 100)
                                    .roundToDouble()
                                : 0.0;

                            // Calcular proyección para cubrir 100%
                            final pendientes = totalDirecciones - predicadas;
                            final diasParaCompletar =
                                pendientes > 0 ? (pendientes / 2).ceil() : 0;
                            final fechaProyeccion = DateTime.now().add(
                              Duration(days: diasParaCompletar),
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header del territorio
                                    Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.analytics,
                                            color: Color(0xFF4A148C),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                nombreTerritorio,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: Color(0xFF263238),
                                                ),
                                              ),
                                              Text(
                                                '$totalDirecciones direcciones totales',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // Barra de progreso
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Progreso de predicación',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF4A148C),
                                              ),
                                            ),
                                            Text(
                                              '${porcentajePredicadas.toInt()}%',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4A148C),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: porcentajePredicadas / 100,
                                            minHeight: 8,
                                            backgroundColor:
                                                Colors.grey.shade300,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              const Color(0xFF4A148C),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // Estadísticas detalladas
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _statCardMini(
                                            'Predicadas',
                                            predicadas,
                                            Icons.check_circle,
                                            Colors.green,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _statCardMini(
                                            'No hispanos',
                                            noHispanos,
                                            Icons.person_off,
                                            Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 8),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: _statCardMini(
                                            'Eliminadas',
                                            eliminadas,
                                            Icons.delete_forever,
                                            Colors.orange,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _statCardMini(
                                            'Agregadas',
                                            agregadas,
                                            Icons.add_circle,
                                            Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Proyección
                                    if (pendientes > 0)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.trending_up,
                                              color: Colors.blue,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Proyección 100%',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.blue,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Completado aprox. el ${DateFormat('dd/MM/yyyy').format(fechaProyeccion)}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.blue,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
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
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCardMini(String title, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContenidoAdminTerritorios() {
    return DefaultTabController(
      length: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: const [
                  Icon(Icons.map, color: Color(0xFF4A148C)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Territorios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              child: const TabBar(
                indicatorColor: Color(0xFF4A148C),
                labelColor: Color(0xFF4A148C),
                unselectedLabelColor: Colors.black54,
                tabs: [
                  Tab(
                    icon: Icon(Icons.map, color: Color(0xFF4A148C)),
                    text: 'Territorios',
                  ),
                  Tab(
                    icon: Icon(Icons.timer, color: Color(0xFF4A148C)),
                    text: 'Temporales',
                  ),
                  Tab(
                    icon: Icon(Icons.delete_sweep, color: Color(0xFF4A148C)),
                    text: 'Removidas',
                  ),
                  Tab(
                    icon: Icon(Icons.bar_chart, color: Color(0xFF4A148C)),
                    text: 'Estadísticas',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('territorios')
                          .orderBy('created_at', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No hay territorios creados todavía.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: snapshot.data!.docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final territorio = snapshot.data!.docs[index];
                            final data =
                                territorio.data() as Map<String, dynamic>? ??
                                    {};
                            final nombre = data['nombre'] ?? 'Territorio';
                            final descripcion = data['descripcion'] ?? '';
                            final ubicado = data['ubicacion'] ?? '';

                            return InkWell(
                              onTap: () => _abrirTerritorio(
                                territorio.id,
                                nombre,
                                readOnly: true,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.map,
                                              color: Color(0xFF4A148C),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        nombre,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                    if (data['enviado_a'] !=
                                                        null)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .orange.shade100,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            8,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'Enviado a: ${data['enviado_a']}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.orange
                                                                .shade900,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                StreamBuilder<QuerySnapshot>(
                                                  stream: FirebaseFirestore
                                                      .instance
                                                      .collection('territorios')
                                                      .doc(territorio.id)
                                                      .collection('tarjetas')
                                                      .snapshots(),
                                                  builder: (context, t) {
                                                    final numTarjetas =
                                                        t.data?.docs.length ??
                                                            0;
                                                    final numDirs = t.data?.docs
                                                            .fold<int>(0,
                                                                (sum, d) {
                                                          final data = d.data()
                                                              as Map<String,
                                                                  dynamic>;
                                                          return sum +
                                                              ((data['cantidad_direcciones'] ??
                                                                  0) as int);
                                                        }) ??
                                                        0;
                                                    return Text(
                                                      '$numTarjetas tarjetas · $numDirs direcciones',
                                                      style: const TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 13,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              (data['disponible_para_publicadores'] ??
                                                          false) ==
                                                      true
                                                  ? Icons.lock_open
                                                  : Icons.lock,
                                              color:
                                                  (data['disponible_para_publicadores'] ??
                                                              false) ==
                                                          true
                                                      ? Colors.green
                                                      : Colors.grey,
                                            ),
                                            onPressed: () async {
                                              final estaAbierto =
                                                  (data['disponible_para_publicadores'] ??
                                                          false) ==
                                                      true;
                                              final update = estaAbierto
                                                  ? {
                                                      'disponible_para_publicadores':
                                                          false,
                                                    }
                                                  : {
                                                      'disponible_para_publicadores':
                                                          true,
                                                      'asignado_a': null,
                                                      'asignado_en': null,
                                                    };

                                              // Actualizar territorio
                                              await FirebaseFirestore.instance
                                                  .collection('territorios')
                                                  .doc(territorio.id)
                                                  .set(
                                                    update,
                                                    SetOptions(merge: true),
                                                  );

                                              // Si se está abriendo el territorio, liberar todas las tarjetas
                                              if (!estaAbierto) {
                                                await _liberarTodasLasTarjetasDelTerritorio(
                                                  territorio.id,
                                                );
                                              }
                                            },
                                            tooltip: (data['disponible_para_publicadores'] ??
                                                        false) ==
                                                    true
                                                ? 'Quitar disponibilidad para publicadores'
                                                : 'Hacer disponible para publicadores',
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.schedule,
                                              color: Color(0xFF4A148C),
                                            ),
                                            onPressed: () =>
                                                _mostrarDialogoProgramarEnvio(
                                              territorio.id,
                                              nombre: nombre,
                                              isTarjeta: false,
                                            ),
                                            tooltip:
                                                'Programar envío de territorio',
                                          ),
                                          const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),

                                      // Mostrar tarjetas disponibles
                                      const SizedBox(height: 12),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('territorios')
                                            .doc(territorio.id)
                                            .collection('tarjetas')
                                            .snapshots(),
                                        builder: (context, tarjetasSnapshot) {
                                          if (!tarjetasSnapshot.hasData) {
                                            return const SizedBox();
                                          }

                                          final tarjetas =
                                              tarjetasSnapshot.data!.docs;
                                          final tarjetasDisponibles =
                                              <DocumentSnapshot>[];

                                          for (final tarjeta in tarjetas) {
                                            final tarjetaData = tarjeta.data()
                                                as Map<String, dynamic>;
                                            if (tarjetaData[
                                                        'disponible_para_publicadores'] ==
                                                    true &&
                                                (tarjetaData['bloqueado'] ??
                                                        false) ==
                                                    false) {
                                              tarjetasDisponibles.add(tarjeta);
                                            }
                                          }

                                          if (tarjetasDisponibles.isEmpty) {
                                            return const Text(
                                              'Ninguna tarjeta liberada aún',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            );
                                          }

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Tarjetas disponibles:',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF4A148C),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              ...tarjetasDisponibles.map((
                                                tarjeta,
                                              ) {
                                                final tarjetaData =
                                                    tarjeta.data()
                                                        as Map<String, dynamic>;
                                                final nombreTarjeta =
                                                    tarjetaData['nombre'] ??
                                                        'Sin nombre';

                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 4,
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.purple.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      6,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.folder_open,
                                                        size: 14,
                                                        color: Color(
                                                          0xFF4A148C,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              nombreTarjeta,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xFF4A148C,
                                                                ),
                                                              ),
                                                            ),
                                                            // Aviso de devolución si existe
                                                            if ((tarjetaData[
                                                                        'devuelto_por'] ??
                                                                    '')
                                                                .toString()
                                                                .isNotEmpty)
                                                              Container(
                                                                margin:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  top: 2,
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .orange
                                                                      .shade50,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    6,
                                                                  ),
                                                                  border: Border
                                                                      .all(
                                                                    color: Colors
                                                                        .orange
                                                                        .shade200,
                                                                  ),
                                                                ),
                                                                child: Builder(
                                                                  builder:
                                                                      (context) {
                                                                    final devueltoEn =
                                                                        tarjetaData[
                                                                            'devuelto_en'];
                                                                    String
                                                                        fecha =
                                                                        '';
                                                                    if (devueltoEn !=
                                                                        null) {
                                                                      final dt =
                                                                          (devueltoEn as Timestamp)
                                                                              .toDate();
                                                                      fecha =
                                                                          ' · ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                                                    }
                                                                    return Text(
                                                                      '↩ Devuelta por: ${tarjetaData['devuelto_por']}$fecha',
                                                                      style:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            9,
                                                                        color: Colors
                                                                            .orange
                                                                            .shade800,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    );
                                                                  },
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Chip de programación si estatus_envio == 'programado'
                                                      if (tarjetaData[
                                                              'estatus_envio'] ==
                                                          'programado')
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .blue.shade100,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              10,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                Icons.schedule,
                                                                size: 10,
                                                                color:
                                                                    Colors.blue,
                                                              ),
                                                              const SizedBox(
                                                                width: 2,
                                                              ),
                                                              Text(
                                                                tarjetaData[
                                                                        'hora_programada'] ??
                                                                    'Programado',
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors
                                                                      .blue,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          );
                                        },
                                      ),

                                      if (descripcion.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            descripcion,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      if (ubicado.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on,
                                                size: 14,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  ubicado,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
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
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Slider para límite de direcciones
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.tune,
                                    color: Color(0xFF4A148C),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Límite de direcciones por tarjeta',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF263238),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              StatefulBuilder(
                                builder: (context, setState) {
                                  double limiteDirecciones = 10.0;
                                  return Column(
                                    children: [
                                      Slider(
                                        value: limiteDirecciones,
                                        min: 5,
                                        max: 30,
                                        divisions: 25,
                                        activeColor: const Color(0xFF4A148C),
                                        label: '${limiteDirecciones.toInt()}',
                                        onChanged: (value) {
                                          setState(() {
                                            limiteDirecciones = value;
                                          });
                                        },
                                      ),
                                      Center(
                                        child: Text(
                                          '${limiteDirecciones.toInt()} direcciones',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4A148C),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Query automática de direcciones temporales
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('direcciones_globales')
                                .where('predicado', isEqualTo: true)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final direcciones = snapshot.data!.docs;

                              // Agrupar por territorio_id
                              final Map<String, List<DocumentSnapshot>>
                                  direccionesPorTerritorio = {};
                              for (final doc in direcciones) {
                                final data = doc.data() as Map<String, dynamic>;
                                final territorioId =
                                    data['territorio_id']?.toString() ??
                                        'sin_territorio';
                                direccionesPorTerritorio
                                    .putIfAbsent(territorioId, () => [])
                                    .add(doc);
                              }

                              if (direccionesPorTerritorio.isEmpty) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.inbox_outlined,
                                        size: 64,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No hay direcciones temporales',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.only(top: 8),
                                itemCount: direccionesPorTerritorio.length,
                                itemBuilder: (context, index) {
                                  final territorioId = direccionesPorTerritorio
                                      .keys
                                      .elementAt(index);
                                  final direccionesTerritorio =
                                      direccionesPorTerritorio[territorioId]!;

                                  // Determinar nombre del territorio
                                  String nombreTerritorio =
                                      'Territorio desconocido';
                                  if (territorioId != 'sin_territorio') {
                                    // Aquí podrías hacer una consulta adicional para obtener el nombre
                                    nombreTerritorio =
                                        'Territorio $territorioId';
                                  } else {
                                    nombreTerritorio = 'Mixta';
                                  }

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: Colors.purple.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.timer,
                                                  color: Color(0xFF4A148C),
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      nombreTerritorio,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                        color: Color(
                                                          0xFF263238,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      '${direccionesTerritorio.length} direcciones disponibles',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    _crearTarjetaTemporal(
                                                  direccionesTerritorio,
                                                  nombreTerritorio,
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF4A148C,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Crear Tarjeta',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          // Mostrar algunas direcciones de ejemplo
                                          Container(
                                            height: 60,
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              itemCount:
                                                  direccionesTerritorio.length >
                                                          3
                                                      ? 3
                                                      : direccionesTerritorio
                                                          .length,
                                              itemBuilder: (context, dirIndex) {
                                                final direccion =
                                                    direccionesTerritorio[
                                                        dirIndex];
                                                final data = direccion.data()
                                                    as Map<String, dynamic>;
                                                final calle = data['calle'] ??
                                                    'Sin nombre';

                                                return Container(
                                                  width: 120,
                                                  margin: const EdgeInsets.only(
                                                    right: 8,
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      6,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    calle,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.black87,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2,
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
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tarjeta de revisión (direcciones con más de 30 días)
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('direcciones_globales')
                              .where(
                                'removed_at',
                                isLessThan: DateTime.now().subtract(
                                  const Duration(days: 30),
                                ),
                              )
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox();
                            }

                            final direccionesRevision = snapshot.data!.docs;

                            if (direccionesRevision.isEmpty) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Sin revisiones pendientes',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          const Text(
                                            'No hay direcciones que necesiten revisión (más de 30 días)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${direccionesRevision.length} direcciones para revisión',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            const Text(
                                              'Direcciones removidas hace más de 30 días',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.orange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () => _mostrarDialogoRevision(
                                      direccionesRevision,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Revisar Direcciones'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // Lista de direcciones removidas
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('direcciones_globales')
                                .where('es_hispano', isEqualTo: false)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final direccionesRemovidas = snapshot.data!.docs;

                              if (direccionesRemovidas.isEmpty) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 64,
                                        color: Colors.green,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No hay direcciones removidas',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        'Todas las direcciones son de hispanohablantes',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.only(top: 8),
                                itemCount: direccionesRemovidas.length,
                                itemBuilder: (context, index) {
                                  final doc = direccionesRemovidas[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final removedAt =
                                      (data['removed_at'] as Timestamp?)
                                          ?.toDate();
                                  final diasDesdeRemocion = removedAt != null
                                      ? DateTime.now()
                                          .difference(removedAt)
                                          .inDays
                                      : 0;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.person_off,
                                                  color: Colors.red,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      data['calle'] ??
                                                          'Dirección sin nombre',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: Color(
                                                          0xFF263238,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      'Removida hace $diasDesdeRemocion días',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            diasDesdeRemocion >
                                                                    30
                                                                ? Colors.red
                                                                : Colors.grey,
                                                        fontWeight:
                                                            diasDesdeRemocion >
                                                                    30
                                                                ? FontWeight
                                                                    .bold
                                                                : FontWeight
                                                                    .normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (diasDesdeRemocion > 30)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'Revisión',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (data['complemento'] != null &&
                                              data['complemento']
                                                  .toString()
                                                  .isNotEmpty)
                                            Text(
                                              'Complemento: ${data['complemento']}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          if (data['detalles'] != null &&
                                              data['detalles']
                                                  .toString()
                                                  .isNotEmpty)
                                            Text(
                                              'Detalles: ${data['detalles']}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () =>
                                                      _restaurarDireccion(
                                                    doc.id,
                                                  ),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.green,
                                                    side: const BorderSide(
                                                      color: Colors.green,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'Restaurar',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () =>
                                                      _eliminarPermanentemente(
                                                    doc.id,
                                                  ),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                  child: const Text('Eliminar'),
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
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildVistaEstadisticasAdminTerritorios(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFF1B5E20)),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
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
                                      final cantDir =
                                          data['cantidad_direcciones'] ?? 0;

                                      return ListTile(
                                        leading: const Icon(
                                          Icons.credit_card,
                                          color: Colors.blue,
                                        ),
                                        title: Text(tarjetaNombre),
                                        subtitle: Text('$cantDir direcciones'),
                                        trailing: ElevatedButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            await _asignarTarjetaAPublicador(
                                              terDoc.id,
                                              tarjetaDoc.id,
                                              tarjetaNombre,
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF1B5E20,
                                            ),
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Tomar'),
                                        ),
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
                        ...[
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
                              opcion['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: opcion['color'] as Color,
                              ),
                            ),
                            value: opcion['valor'] as String,
                            groupValue: estadoLocal,
                            activeColor: opcion['color'] as Color,
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
                          );
                        }).toList(),

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
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: CustomScrollView(
        slivers: [
          // Statistics Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard('Recibidos', 0, Icons.download),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Enviados', 0, Icons.upload)),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Devueltos', 0, Icons.undo)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Simple bar chart simulation
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Actividad Mensual',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(6, (index) {
                              final heights = [0.3, 0.7, 0.5, 0.9, 0.6, 0.8];
                              return Container(
                                width: 20,
                                height: 60 * heights[index],
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1B5E20,
                                  ).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Territories Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'TERRITORIOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // Territories Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('territorios')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return d['enviado_a'] == _usuarioEmail;
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(
                            color: const Color(0xFF1B5E20),
                            width: 4,
                          ),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay territorios recibidos',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Territorio';
                      final enviadoA = data['enviado_a'] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(
                              color: const Color(0xFF1B5E20),
                              width: 4,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.map,
                                    color: Color(0xFF1B5E20),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (enviadoA.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Enviado a: $enviadoA',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Botones de acción
                              if (enviadoA.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Territorio recibido — envía las tarjetas individualmente',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),

                              if (enviadoA.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _devolverTerritorio(doc.id),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.orange,
                                          side: const BorderSide(
                                            color: Colors.orange,
                                          ),
                                        ),
                                        child: const Text('Devolver'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            null, // Deshabilitado ya que está enviado
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Ya enviado'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          // Cards Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'TARJETAS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

          // Cards Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    // Recibe por email O por nombre
                    return d['enviado_a'] == _usuarioEmail ||
                        d['enviado_a'] == (widget.usuarioData['nombre'] ?? '');
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(color: Colors.blue, width: 4),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay tarjetas recibidas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Tarjeta';
                      final enviadoA = data['enviado_a'] ?? '';
                      final terId = doc.reference.parent.parent?.id ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(color: Colors.blue, width: 4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: const Icon(
                            Icons.credit_card,
                            color: Colors.blue,
                          ),
                          title: Text(
                            nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Territorio: $terId'),
                              if (enviadoA.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final enviadoEn = data['enviado_en'];
                                      String fechaHora = '';
                                      if (enviadoEn != null) {
                                        final dt =
                                            (enviadoEn as Timestamp).toDate();
                                        fechaHora =
                                            ' · ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                      }
                                      return Text(
                                        'Enviado por: ${data['enviado_nombre'] ?? enviadoA}$fechaHora',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Botón Enviar — siempre visible con estado apropiado
                              if ((data['enviado_nombre'] ?? '')
                                  .toString()
                                  .isEmpty)
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.send, size: 14),
                                  label: const Text(
                                    'Enviar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () =>
                                      _enviarTarjetaConductorAPublicador(
                                    terId,
                                    doc.id,
                                    nombre,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text(
                                    'Reenviar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () =>
                                      _enviarTarjetaConductorAPublicador(
                                    terId,
                                    doc.id,
                                    nombre,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              // Botón Devolver — siempre visible
                              OutlinedButton.icon(
                                icon: const Icon(Icons.undo, size: 14),
                                label: const Text(
                                  'Devolver',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () async {
                                  final confirmar = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Confirmar devolución'),
                                      content: Text(
                                        '¿Devolver la tarjeta "$nombre"? Volverá a estar disponible en el territorio.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text(
                                            'Cancelar',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                          ),
                                          child: const Text('Devolver'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    await FirebaseFirestore.instance
                                        .collection('territorios')
                                        .doc(terId)
                                        .collection('tarjetas')
                                        .doc(doc.id)
                                        .update({
                                      'enviado_a': null,
                                      'enviado_nombre': null,
                                      'enviado_en': null,
                                      'estatus_envio': 'devuelto',
                                      'devuelto_en':
                                          FieldValue.serverTimestamp(),
                                      'devuelto_por':
                                          widget.usuarioData['nombre'] ??
                                              _usuarioEmail,
                                    });
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Future<void> _devolverTerritorio(String territorioId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .update({
        'enviado_a': null,
        'enviado_email': null,
        'enviado_timestamp': null,
        'enviado_por': null,
        'estatus_envio': 'devuelto',
        'devuelto_timestamp': FieldValue.serverTimestamp(),
        'devuelto_por': _usuarioEmail,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Territorio devuelto exitosamente'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver territorio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildContenidoPublicador() {
    final nombrePublicador = widget.usuarioData['nombre'] ?? 'Publicador';
    final iniciales =
        nombrePublicador.isNotEmpty ? nombrePublicador[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('direcciones_globales')
            .snapshots(),
        builder: (context, snapshot) {
          final todasDirecciones = snapshot.data?.docs ?? [];

          // Obtener direcciones del usuario
          final direccionesUsuario = todasDirecciones.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['publicador_email'] == _usuarioEmail;
          }).toList();

          // Obtener tarjetas asignadas al usuario
          final tarjetasUsuario = direccionesUsuario
              .map((doc) => doc['tarjeta_id'] as String)
              .toSet();

          // Contar todas las direcciones dentro de las tarjetas asignadas
          final direccionesEnTarjetasUsuario = todasDirecciones.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return tarjetasUsuario.contains(data['tarjeta_id'] as String);
          }).toList();

          final total = direccionesEnTarjetasUsuario.length;
          final completadas = direccionesEnTarjetasUsuario.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['estado_predicacion'] == 'completada' ||
                data['predicado'] == true;
          }).length;
          final pendientes = total - completadas;

          return CustomScrollView(
            slivers: [
              // ── HEADER ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.85),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          iniciales,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, $nombrePublicador',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$completadas de $total direcciones completadas ($pendientes pendientes)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── ALERTAS ─────────────────────────────────────────
              if (_campanaEspecialActiva ||
                  (_campanaGeneralActiva && _anuncioGeneral.trim().isNotEmpty))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_campanaEspecialActiva)
                        _alertaBanner(
                          icon: Icons.campaign,
                          color: const Color(0xFFE65100),
                          bgColor: const Color(0xFFFFF3E0),
                          title: 'Campaña especial activa',
                          body: _nombreCampanaEspecial.isNotEmpty
                              ? _nombreCampanaEspecial
                              : 'Sin nombre',
                        ),
                      if (_campanaGeneralActiva &&
                          _anuncioGeneral.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _alertaBanner(
                          icon: Icons.info_outline,
                          color: const Color(0xFF1565C0),
                          bgColor: const Color(0xFFE3F2FD),
                          title: 'Anuncio',
                          body: _anuncioGeneral,
                        ),
                      ],
                    ]),
                  ),
                ),

              // ── STATS ────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .where(
                          'asignado_a',
                          isEqualTo: widget.usuarioData['nombre'] ?? '',
                        )
                        .snapshots(),
                    builder: (context, tarjetasSnap) {
                      // Total direcciones en tarjetas asignadas al usuario
                      int totalDirAsignadas = 0;
                      List<String> tarjetaIds = [];

                      if (tarjetasSnap.hasData) {
                        for (final t in tarjetasSnap.data!.docs) {
                          final d = t.data() as Map<String, dynamic>;
                          totalDirAsignadas +=
                              ((d['cantidad_direcciones'] ?? 0) as int);
                          tarjetaIds.add(t.id);
                        }
                      }

                      return FutureBuilder<QuerySnapshot?>(
                        future: tarjetaIds.isEmpty
                            ? Future.value(null)
                            : FirebaseFirestore.instance
                                .collection('direcciones_globales')
                                .where(
                                  'tarjeta_id',
                                  whereIn: tarjetaIds.take(10).toList(),
                                )
                                .get(),
                        builder: (context, dirsSnap) {
                          // Filtrar por mes actual usando mes_predicacion
                          final mesActual =
                              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

                          final completadas = dirsSnap.data?.docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return data['predicado'] == true &&
                                    data['mes_predicacion'] == mesActual;
                              }).length ??
                              0;

                          final pendientes = totalDirAsignadas - completadas;
                          final avance = totalDirAsignadas > 0
                              ? completadas / totalDirAsignadas
                              : 0.0;

                          return Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  'Dir Asignadas',
                                  totalDirAsignadas,
                                  Icons.home_work_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  'Dir Completadas',
                                  completadas,
                                  Icons.check_circle_outline,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  'Dir Pendientes',
                                  pendientes < 0 ? 0 : pendientes,
                                  Icons.schedule_outlined,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // ── PROGRESO ─────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('direcciones_globales')
                        .snapshots(),
                    builder: (context, snapTotal) {
                      final totalExistentes = snapTotal.data?.docs.length ?? 0;
                      final completadasGlobal =
                          snapTotal.data?.docs.where((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                return d['predicado'] == true;
                              }).length ??
                              0;
                      final pendientesGlobal =
                          totalExistentes - completadasGlobal;
                      final avance = totalExistentes > 0
                          ? completadasGlobal / totalExistentes
                          : 0.0;

                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Progreso mensual',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF263238),
                                  ),
                                ),
                                Text(
                                  '${(avance * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF1B5E20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: avance,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFE8F5E9),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1B5E20),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Tres contadores
                            Row(
                              children: [
                                Expanded(
                                  child: _miniStat(
                                    'Existentes',
                                    totalExistentes,
                                    Icons.home_work_outlined,
                                    Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _miniStat(
                                    'Completadas',
                                    completadasGlobal,
                                    Icons.check_circle_outline,
                                    const Color(0xFF1B5E20),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _miniStat(
                                    'Pendientes',
                                    pendientesGlobal,
                                    Icons.schedule_outlined,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── MIS TARJETAS ──────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MIS TARJETAS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collectionGroup('tarjetas')
                            .where(
                              'asignado_a',
                              isEqualTo: widget.usuarioData['nombre'] ??
                                  '', // Usar nombre para búsqueda
                            )
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
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  'No tienes tarjetas asignadas.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: snapshot.data!.docs.map((tarjetaDoc) {
                              final data =
                                  tarjetaDoc.data() as Map<String, dynamic>;
                              final nombre = data['nombre'] ?? tarjetaDoc.id;
                              final cantDir = data['cantidad_direcciones'] ?? 0;
                              final territorioId =
                                  tarjetaDoc.reference.parent.parent?.id ?? '';
                              final asignadoEn =
                                  data['asignado_en'] as Timestamp?;
                              final fecha = asignadoEn != null
                                  ? '${asignadoEn.toDate().day}/${asignadoEn.toDate().month}/${asignadoEn.toDate().year}'
                                  : '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ExpansionTile(
                                  leading: const Icon(
                                    Icons.credit_card,
                                    color: Colors.blue,
                                  ),
                                  title: Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$cantDir direcciones · $territorioId${fecha.isNotEmpty ? ' · $fecha' : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      final confirmar = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Devolver tarjeta'),
                                          content: Text(
                                            '¿Devolver "$nombre"? Quedará disponible para otros.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                              ),
                                              child: const Text('Devolver'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmar == true) {
                                        await _devolverTarjeta(
                                          territorioId,
                                          tarjetaDoc.id,
                                        );
                                      }
                                    },
                                    child: const Text(
                                      'Devolver',
                                      style: TextStyle(color: Colors.orange),
                                    ),
                                  ),
                                  children: [
                                    _buildDireccionesTarjeta(tarjetaDoc.id),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── DIRECCIONES ──────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MIS DIRECCIONES',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (direccionesUsuario.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sin direcciones asignadas',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...direccionesUsuario.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final calle = data['calle'] ?? 'Dirección';
                          final predicado = data['predicado'] ?? false;
                          final notas = data['notas'] ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: predicado,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection(
                                                'direcciones_globales',
                                              )
                                              .doc(doc.id)
                                              .update({
                                            'predicado': value ?? false,
                                            'estado_predicacion':
                                                (value ?? false)
                                                    ? 'completada'
                                                    : 'pendiente',
                                            'fecha_predicacion': (value ??
                                                    false)
                                                ? FieldValue.serverTimestamp()
                                                : null,
                                          });
                                        },
                                        activeColor: const Color(0xFF1B5E20),
                                      ),
                                      Expanded(
                                        child: Text(
                                          calle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: predicado
                                              ? const Color(0xFFE8F5E9)
                                              : const Color(0xFFFFF8E1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          predicado
                                              ? 'Completada'
                                              : 'Pendiente',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: predicado
                                                ? const Color(0xFF1B5E20)
                                                : const Color(0xFFE65100),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_campanaEspecialActiva) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFE65100,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Campaña especial:',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFE65100),
                                            ),
                                          ),
                                          TextField(
                                            controller: TextEditingController(
                                              text: data['campo_extra'] ?? '',
                                            ),
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Ingresa dato de campaña...',
                                              hintStyle: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                            onChanged: (value) async {
                                              await FirebaseFirestore.instance
                                                  .collection(
                                                    'direcciones_globales',
                                                  )
                                                  .doc(doc.id)
                                                  .update({
                                                'campo_extra': value,
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: TextEditingController(
                                      text: notas,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Agregar notas...',
                                      hintStyle: const TextStyle(fontSize: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .doc(doc.id)
                                          .update({'notas': value});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────

  Widget _alertaBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _verificarReinicioMensual() async {
    final ahora = DateTime.now();
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where(
            'enviado_en',
            isLessThan: Timestamp.fromDate(
              DateTime(ahora.year, ahora.month, 1),
            ),
          )
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'enviado_nombre': null,
          'enviado_a': null,
          'enviado_en': null,
          'estatus_envio': null,
        });
      }
      if (snap.docs.isNotEmpty) await batch.commit();
    } catch (_) {}
  }

  Future<void> _enviarTarjetaConductorAPublicador(
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    final publicadoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_publicador', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();

    if (!mounted) return;

    if (publicadoresSnap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay publicadores disponibles')),
      );
      return;
    }

    // Paso 1 — Elegir publicador
    String? nombreElegido;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enviar "$tarjetaNombre" a:'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: publicadoresSnap.docs.length,
            itemBuilder: (context, index) {
              final data = publicadoresSnap.docs[index].data();
              final nombre = data['nombre'] ?? 'Publicador';
              final email = data['email'] ?? '';
              return ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(nombre),
                subtitle: Text(email),
                onTap: () {
                  nombreElegido = nombre;
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (nombreElegido == null || !mounted) return;

    // Paso 2 — Confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: Text(
          '¿Enviar la tarjeta "$tarjetaNombre" a $nombreElegido?\n\nEsta acción asignará todas las direcciones de la tarjeta al publicador seleccionado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar envío'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      // Actualizar tarjeta
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': nombreElegido, // Usar nombre para asignación
        'enviado_nombre': nombreElegido,
        'enviado_en': FieldValue.serverTimestamp(),
        'enviado_por_conductor': _usuarioEmail,
        'asignado_en': FieldValue.serverTimestamp(),
        'tomado_en': FieldValue.serverTimestamp(),
        'disponible_para_publicadores': false,
      });

      // Vincular direcciones al publicador
      final dirs = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();

      if (dirs.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final dir in dirs.docs) {
          batch.update(dir.reference, {'asignado_a': nombreElegido});
        }
        await batch.commit();
      }

      // Remover tarjeta del conductor — limpiar enviado_a del conductor
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'enviado_a': null, // se limpia el email del conductor
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ "$tarjetaNombre" enviada a $nombreElegido con ${dirs.docs.length} direcciones',
          ),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al enviar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
