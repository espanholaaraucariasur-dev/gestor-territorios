import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'src/csv_upload.dart' if (dart.library.html) 'src/csv_upload_web.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'dart:ui';
import 'src/pantalla_verificacion.dart';
import 'src/pantalla_acceso.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAJr2vepvlf0JSwJz-v_6edHWk7uurT_6c",
      authDomain: "territorio-sur-8b72c.firebaseapp.com",
      projectId: "territorio-sur-8b72c",
      storageBucket: "territorio-sur-8b72c.firebasestorage.app",
      messagingSenderId: "288799954885",
      appId: "1:288799954885:web:32ae6dfbc7d871b30bddac",
    ),
  );
  runApp(const AraucariaApp());
}

class AraucariaApp extends StatelessWidget {
  const AraucariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Araucaría Sur',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        useMaterial3: true,
      ),
      home: const PantallaVerificacion(),
      routes: {
        '/login': (context) => const PantallaAcceso(),
      },
    );
  }
}

class PantallaVerificacionLegacy extends StatefulWidget {
  const PantallaVerificacionLegacy({super.key});

  @override
  State<PantallaVerificacionLegacy> createState() => _PantallaVerificacionLegacyState();
}

class _PantallaVerificacionLegacyState extends State<PantallaVerificacionLegacy> {
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  void _verificarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final bool yaInicioSesion = prefs.getBool('isLoggedIn') ?? false;
    final String correoGuardado = prefs.getString('userEmail') ?? '';
    
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    if (yaInicioSesion && correoGuardado.isNotEmpty) {
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: correoGuardado)
          .get();
      if (snapshot.docs.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PantallaHomeLegacy(usuarioData: snapshot.docs.first.data()),
          ),
        );
      } else {
        _irALogin();
      }
    } else {
      _irALogin();
    }
  }

  void _irALogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const PantallaAccesoLegacy()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.explore_outlined, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text('Cargando...', style: TextStyle(color: Colors.white, fontSize: 20)),
          ],
        ),
      ),
    );
  }
}

class PantallaAccesoLegacy extends StatefulWidget {
  const PantallaAccesoLegacy({super.key});

  @override
  State<PantallaAccesoLegacy> createState() => _PantallaAccesoLegacyState();
}

class _PantallaAccesoLegacyState extends State<PantallaAccesoLegacy> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isLoading = false;
  bool _canCheckBiometrics = false;
  bool _hasBiometricAccount = false;

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    bool canCheck = false;
    bool hasAccount = false;
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final storedEmail = await _secureStorage.read(key: 'biometric_email');
      canCheck = canAuthenticateWithBiometrics && isDeviceSupported;
      hasAccount = storedEmail != null && storedEmail.isNotEmpty && canCheck;
    } catch (_) {
      canCheck = false;
      hasAccount = false;
    }
    if (!mounted) return;
    setState(() {
      _canCheckBiometrics = canCheck;
      _hasBiometricAccount = hasAccount;
    });
    if (hasAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _authenticateWithBiometrics();
        }
      });
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Autentícate con huella o rostro para iniciar sesión',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!didAuthenticate) return;
      final storedEmail = await _secureStorage.read(key: 'biometric_email');
      if (storedEmail == null || storedEmail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró cuenta biométrica configurada.')));
        }
        return;
      }
      await _loginWithStoredEmail(storedEmail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error biométrico: $e')));
      }
    }
  }

  Future<void> _loginWithStoredEmail(String email) async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _db.collection('usuarios').where('email', isEqualTo: email).get();
      if (snapshot.docs.isEmpty) {
        if (mounted) _mostrarError('Usuario biométrico no encontrado.');
        return;
      }
      final u = snapshot.docs.first.data();
      if (u['estado'] == 'pendiente') {
        if (mounted) _mostrarError('Cuenta pendiente de aprobación.');
        return;
      }
      if (u['estado'] == 'aprobado') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userEmail', email);
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PantallaHomeLegacy(usuarioData: u)));
        }
      }
    } catch (_) {
      if (mounted) _mostrarError('Error de conexión biométrica.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarDialogoSolicitud(BuildContext context) {
    final nomCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_add_outlined, size: 40, color: Color(0xFF1B5E20)),
                const SizedBox(height: 16),
                const Text('Solicitar Acceso', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: nomCtrl, decoration: _inputDec('Nombre Completo')),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _inputDec('Correo electrónico')),
                const SizedBox(height: 12),
                TextField(controller: passCtrl, obscureText: true, decoration: _inputDec('Crear Contraseña')),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nomCtrl.text.isEmpty || emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa todos los campos')));
                        return;
                      }
                      try {
                        await _db.collection('usuarios').add({
                          'nombre': nomCtrl.text,
                          'email': emailCtrl.text,
                          'password': passCtrl.text,
                          'estado': 'pendiente',
                          'es_admin': false,
                          'es_conductor': false,
                          'es_publicador': false,
                          'grupo_id': null,
                          'idioma': 'es',
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('¡Solicitud enviada!'), backgroundColor: Color(0xFF1B5E20)),
                        );
                      } catch (e) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Enviar Solicitud', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _db.collection('usuarios').where('email', isEqualTo: _emailController.text.trim()).get();
      if (snapshot.docs.isEmpty) {
        _mostrarError('Usuario no encontrado.');
        return;
      }
      final u = snapshot.docs.first.data();
      if (u['password'] != _passwordController.text.trim()) {
        _mostrarError('Contraseña incorrecta');
        return;
      }
      if (u['estado'] == 'pendiente') {
        _mostrarError('Cuenta pendiente de aprobación.');
        return;
      }
      if (u['estado'] == 'aprobado') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userEmail', _emailController.text.trim());
        if (_canCheckBiometrics) {
          await _secureStorage.write(key: 'biometric_email', value: _emailController.text.trim());
          setState(() => _hasBiometricAccount = true);
        }
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PantallaHomeLegacy(usuarioData: u)));
        }
      }
    } catch (e) {
      _mostrarError('Error de conexión.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B5E20), Color(0xFF37474F)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.explore_outlined, size: 60, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      const Text('Araucária Sur', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
                      const SizedBox(height: 8),
                      const Text('Gestión Territorial · Congregación Español', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 32),
                      TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: _inputDec('Correo electrónico')),
                      const SizedBox(height: 16),
                      TextField(controller: _passwordController, obscureText: true, decoration: _inputDec('Contraseña')),
                      const SizedBox(height: 24),
                      if (_hasBiometricAccount) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _authenticateWithBiometrics,
                            icon: const Icon(Icons.fingerprint, color: Color(0xFF1B5E20)),
                            label: const Text('Iniciar con Huella/Face', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF1B5E20)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _iniciarSesion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 5,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Iniciar Sesión', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿No tienes cuenta?', style: TextStyle(color: Colors.grey)),
                          GestureDetector(
                            onTap: () => _mostrarDialogoSolicitud(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(' Solicitar acceso',
                                  style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
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
        ),
      ),
    );
  }
}

class PantallaHomeLegacy extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  const PantallaHomeLegacy({super.key, required this.usuarioData});

  @override
  State<PantallaHomeLegacy> createState() => _PantallaHomeLegacyState();
}

class _PantallaHomeLegacyState extends State<PantallaHomeLegacy> with SingleTickerProviderStateMixin {
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
  bool _cargandoConfiguracion = true;
  final TextEditingController _campanaEspecialController = TextEditingController();
  final TextEditingController _anuncioGeneralController = TextEditingController();
  final TextEditingController _localizadorController = TextEditingController();
  final TextEditingController _complementoLocalizadorController = TextEditingController();
  final TextEditingController _detallesLocalizadorController = TextEditingController();
  bool _localizadorBuscado = false;
  bool _localizadorEncontrada = false;
  String _localizadorMensaje = '';
  bool _mostrarSolicitudLocalizador = false;
  final Set<String> _solicitudTarjetasSeleccionadas = {};

  @override
  void initState() {
    super.initState();
    _tabControllerAdmin = TabController(length: 4, vsync: this);
    _usuarioEmail = widget.usuarioData['email'] ?? '';
    _cargarConfiguracionComunicacion();
    _procesarEnviosProgramados();
    final esAdminTerritorios = widget.usuarioData['es_admin_territorios'] ?? false;
    final esAdmin = widget.usuarioData['es_admin'] ?? false;
    if (esAdminTerritorios && !esAdmin) {
      _modoAdminTerritoriosActivo = true;
    }
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaAccesoLegacy()));
    }
  }

  void _cargarConfiguracionComunicacion() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('configuraciones').doc('comunicacion').get();
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
          _cargandoConfiguracion = false;
        });
      } else {
        setState(() {
          _cargandoConfiguracion = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoConfiguracion = false;
      });
    }
  }

  void _guardarConfiguracionComunicacion() async {
    try {
      await FirebaseFirestore.instance.collection('configuraciones').doc('comunicacion').set({
        'campana_especial_activa': _campanaEspecialActiva,
        'nombre_campana_especial': _nombreCampanaEspecial,
        'campana_general_activa': _campanaGeneralActiva,
        'anuncio_general': _anuncioGeneral,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de comunicación guardada'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar la comunicación: $e'), backgroundColor: Colors.redAccent),
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
      final snapshot = await FirebaseFirestore.instance.collection('direcciones_globales').get();
      for (final doc in snapshot.docs) {
        final calle = (doc['calle'] ?? '') as String;
        final complemento = (doc['complemento'] ?? '') as String;
        final docNormalizada = (doc['direccion_normalizada'] as String?) ?? _normalizarDireccion('$calle $complemento');
        if (docNormalizada == normalizada) {
          setState(() {
            _localizadorEncontrada = true;
            _localizadorMensaje = 'Dirección encontrada: $calle${complemento.isNotEmpty ? ' • $complemento' : ''}';
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
          _localizadorMensaje = 'Esta dirección ya fue solicitada y está pendiente de revisión.';
          _mostrarSolicitudLocalizador = false;
        });
        return;
      }

      setState(() {
        _localizadorEncontrada = false;
        _localizadorMensaje = 'No se encontró en el directorio global. Completa el formulario para enviarla al administrador.';
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
        const SnackBar(content: Text('Ingresa una dirección antes de enviar'), backgroundColor: Colors.orange),
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
        _localizadorMensaje = 'Esta dirección ya fue solicitada y está pendiente de revisión.';
        _mostrarSolicitudLocalizador = false;
      });
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('solicitudes_direcciones').add({
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
        _localizadorMensaje = 'Solicitud enviada correctamente. El admin revisará la dirección pronto.';
        _mostrarSolicitudLocalizador = false;
        _localizadorController.clear();
        _complementoLocalizadorController.clear();
        _detallesLocalizadorController.clear();
        _localizadorBuscado = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar solicitud: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _aprobarSolicitudDireccion(DocumentSnapshot solicitudDoc) async {
    final datos = solicitudDoc.data() as Map<String, dynamic>;
    try {
      await FirebaseFirestore.instance.collection('direcciones_globales').add({
        'calle': datos['direccion_original'] ?? '',
        'direccion_normalizada': datos['direccion_normalizada'] ?? _normalizarDireccion('${datos['direccion_original'] ?? ''} ${datos['complemento'] ?? ''}'),
        'complemento': datos['complemento'] ?? '',
        'detalles_admin': datos['detalles'] ?? '',
        'estado': 'pendiente',
        'created_at': FieldValue.serverTimestamp(),
        'solicitante_email': datos['solicitante_email'] ?? '',
      });
      await FirebaseFirestore.instance.collection('solicitudes_direcciones').doc(solicitudDoc.id).update({
        'estado': 'aprobada',
        'revisado_por': _usuarioEmail,
        'revisado_en': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud aprobada y agregada al directorio global'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al aprobar solicitud: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _rechazarSolicitudDireccion(DocumentSnapshot solicitudDoc) async {
    try {
      await FirebaseFirestore.instance.collection('solicitudes_direcciones').doc(solicitudDoc.id).update({
        'estado': 'rechazada',
        'revisado_por': _usuarioEmail,
        'revisado_en': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al rechazar solicitud: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _mostrarDialogoSolicitarTarjetasPublicador() async {
    _solicitudTarjetasSeleccionadas.clear();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Solicitar tarjetas de territorio'),
              content: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collectionGroup('tarjetas').where('disponible_para_publicadores', isEqualTo: true).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return const SizedBox(height: 120, child: Center(child: Text('No hay tarjetas disponibles para solicitud por el momento.')));
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final tarjetaPath = doc.reference.path;
                        final nombre = data['nombre'] ?? 'Tarjeta';
                        final terNombre = data['territorio_nombre'] ?? data['territorio_id'] ?? 'Territorio';
                        final seleccionado = _solicitudTarjetasSeleccionadas.contains(tarjetaPath);
                        return CheckboxListTile(
                          value: seleccionado,
                          title: Text(nombre),
                          subtitle: Text('Territorio: $terNombre'),
                          onChanged: (selected) {
                            if (selected == null) return;
                            if (selected && _solicitudTarjetasSeleccionadas.length >= 2) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Solo se pueden solicitar hasta 2 tarjetas a la vez.')),
                              );
                              return;
                            }
                            setStateDialog(() {
                              if (selected) {
                                _solicitudTarjetasSeleccionadas.add(tarjetaPath);
                              } else {
                                _solicitudTarjetasSeleccionadas.remove(tarjetaPath);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: _solicitudTarjetasSeleccionadas.isEmpty
                      ? null
                      : () async {
                          final batch = FirebaseFirestore.instance.batch();
                          for (final tarjetaPath in _solicitudTarjetasSeleccionadas) {
                            final docRef = FirebaseFirestore.instance.doc(tarjetaPath);
                            batch.set(docRef, {
                              'solicitado_por_publicador_email': _usuarioEmail,
                              'solicitado_en': FieldValue.serverTimestamp(),
                              'disponible_para_publicadores': false,
                            }, SetOptions(merge: true));
                          }
                          await batch.commit();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Solicitud de tarjetas enviada.'), backgroundColor: Colors.green),
                            );
                          }
                          Navigator.of(context).pop();
                        },
                  child: const Text('Enviar solicitud'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _procesarEnviosProgramados() async {
    final now = DateTime.now();
    try {
      final queryTerritorios = await FirebaseFirestore.instance
          .collection('territorios')
          .where('programado_para', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .where('estatus_envio', isEqualTo: 'programado')
          .get();
      final queryTarjetas = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where('programado_para', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .where('estatus_envio', isEqualTo: 'programado')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in queryTerritorios.docs) {
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': doc['conductor_email'] ?? '',
        });
      }
      for (final doc in queryTarjetas.docs) {
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': doc['conductor_email'] ?? '',
        });
      }
      bool hasUpdates = queryTerritorios.docs.isNotEmpty || queryTarjetas.docs.isNotEmpty;
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {
      // No interrumpir la app si el procesamiento programado falla.
    }
  }

  Future<void> _mostrarDialogoProgramarEnvio(String terId, {String? tarjetaId, required String nombre, required bool isTarjeta}) async {
    final conductoresSnapshot = await FirebaseFirestore.instance.collection('usuarios').where('es_conductor', isEqualTo: true).get();
    final conductores = conductoresSnapshot.docs.map((doc) => doc.data()['email'] as String? ?? '').where((email) => email.isNotEmpty).toList();
    if (!mounted) return;
    String selectedConductor = conductores.isNotEmpty ? conductores.first : '';
    DateTime fechaSeleccionada = DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isTarjeta ? 'Programar envío de tarjeta' : 'Programar envío de territorio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conductores.isEmpty)
                    const Text('No hay conductores registrados. Agrega un conductor antes de programar.')
                  else
                    DropdownButtonFormField<String>(
                      value: selectedConductor,
                      items: conductores.map((email) => DropdownMenuItem(value: email, child: Text(email))).toList(),
                      onChanged: (value) {
                        if (value != null) setStateDialog(() => selectedConductor = value);
                      },
                      decoration: const InputDecoration(labelText: 'Conductor', border: OutlineInputBorder()),
                    ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: fechaSeleccionada,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setStateDialog(() => fechaSeleccionada = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Fecha de envío'),
                      child: Text('${fechaSeleccionada.day}/${fechaSeleccionada.month}/${fechaSeleccionada.year}'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: conductores.isEmpty
                      ? null
                      : () async {
                          try {
                            final data = {
                              'programado_para': Timestamp.fromDate(fechaSeleccionada),
                              'conductor_email': selectedConductor,
                              'estatus_envio': 'programado',
                              'programado_tipo': isTarjeta ? 'tarjeta' : 'territorio',
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
                              await FirebaseFirestore.instance.collection('territorios').doc(terId).set(data, SetOptions(merge: true));
                            }
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Programación guardada para $nombre'), backgroundColor: Colors.green),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al programar envío: $e'), backgroundColor: Colors.redAccent),
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

  Future<void> _solicitarTerritorioPublicador(String territorioId, String territorioNombre) async {
    try {
      await FirebaseFirestore.instance.collection('solicitudes_publicadores').add({
        'territorio_id': territorioId,
        'territorio_nombre': territorioNombre,
        'publicador_email': _usuarioEmail,
        'estado': 'pendiente',
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud enviada al administrador'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al solicitar territorio: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _guardarEstadisticasMensuales() async {
    try {
      final now = DateTime.now();
      final mesId = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final mesNombre = '${now.month.toString().padLeft(2, '0')}/${now.year}';
      final territoriosSnapshot = await FirebaseFirestore.instance.collection('territorios').get();
      final tarjetasSnapshot = await FirebaseFirestore.instance.collectionGroup('tarjetas').get();
      final direccionesSnapshot = await FirebaseFirestore.instance.collection('direcciones_globales').get();
      final solicitudesSnapshot = await FirebaseFirestore.instance.collection('solicitudes_direcciones').where('estado', isEqualTo: 'pendiente').get();
      final totalTerritorios = territoriosSnapshot.docs.length;
      final totalTarjetas = tarjetasSnapshot.docs.length;
      final totalDirecciones = direccionesSnapshot.docs.length;
      final totalSolicitudesEnviadas = solicitudesSnapshot.docs.length;
      final predicadas = direccionesSnapshot.docs.where((doc) => (doc['predicado'] ?? false) == true).length;
      final noPredicadas = direccionesSnapshot.docs.where((doc) => (doc['no_predicado'] ?? false) == true).length;
      final noHispanos = direccionesSnapshot.docs.where((doc) => (doc['es_hispano'] ?? true) == false).length;
      final invitaciones = direccionesSnapshot.docs.where((doc) => (doc['entrego_invitacion'] ?? false) == true).length;
      final usuariosActivos = direccionesSnapshot.docs.map((doc) => doc['publicador_email'] ?? '').where((email) => (email as String).isNotEmpty).toSet().length;
      final topPublicadores = <String, int>{};
      for (final doc in direccionesSnapshot.docs) {
        final email = doc['publicador_email'] ?? '';
        if ((email as String).isNotEmpty) {
          topPublicadores[email] = (topPublicadores[email] ?? 0) + 1;
        }
      }
      final topPublicador = topPublicadores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      await FirebaseFirestore.instance.collection('estadisticas_mensuales').doc(mesId).set({
        'mes': mesNombre,
        'timestamp': FieldValue.serverTimestamp(),
        'territorios': totalTerritorios,
        'tarjetas': totalTarjetas,
        'direcciones': totalDirecciones,
        'direcciones_enviadas': totalSolicitudesEnviadas,
        'predicadas': predicadas,
        'no_predicadas': noPredicadas,
        'no_hispano': noHispanos,
        'invitaciones': invitaciones,
        'usuarios_activos': usuariosActivos,
        'top_publicador': topPublicador.isNotEmpty ? topPublicador.first.key : '',
        'top_publicador_cantidad': topPublicador.isNotEmpty ? topPublicador.first.value : 0,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estadísticas mensuales guardadas'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar estadísticas: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildSeccionComunicacionAdmin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comunicación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          const SizedBox(height: 16),
          _cargandoConfiguracion
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Campaña especial', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _campanaEspecialController,
                      decoration: _inputStyleHelper('Nombre de la campaña especial'),
                      onChanged: (value) => setState(() => _nombreCampanaEspecial = value),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Activar campaña especial'),
                      value: _campanaEspecialActiva,
                      onChanged: (value) => setState(() => _campanaEspecialActiva = value),
                    ),
                    const SizedBox(height: 20),
                    const Text('Anuncio general', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _anuncioGeneralController,
                      decoration: _inputStyleHelper('Mensaje para todos los usuarios'),
                      maxLines: 3,
                      onChanged: (value) => setState(() => _anuncioGeneral = value),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Activar anuncio general'),
                      value: _campanaGeneralActiva,
                      onChanged: (value) => setState(() => _campanaGeneralActiva = value),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: _guardarConfiguracionComunicacion,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
                        child: const Text('Guardar configuración', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Direcciones enviadas por usuarios', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('solicitudes_direcciones').snapshots(),
                      builder: (context, todasSnapshot) {
                        if (!todasSnapshot.hasData) {
                          return const SizedBox(height: 16, child: Center(child: CircularProgressIndicator()));
                        }
                        final totalSolicitudes = todasSnapshot.data!.docs.length;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total solicitudes: $totalSolicitudes', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                              Chip(
                                label: Text('${todasSnapshot.data!.docs.where((doc) => (doc['estado'] ?? '') == 'pendiente').length} pendientes', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                backgroundColor: const Color(0xFF1B5E20),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('solicitudes_direcciones')
                          .where('estado', isEqualTo: 'pendiente')
                          .orderBy('created_at', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.data!.docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No hay solicitudes de direcciones pendientes.', style: TextStyle(color: Colors.grey)),
                          );
                        }
                        return Column(
                          children: snapshot.data!.docs.map((solicitud) {
                            final datos = solicitud.data() as Map<String, dynamic>;
                            final direccion = datos['direccion_original'] ?? 'Dirección';
                            final complemento = datos['complemento'] ?? '';
                            final detalles = datos['detalles'] ?? '';
                            final solicitante = datos['solicitante_email'] ?? 'Desconocido';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(direccion, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    if (complemento.isNotEmpty) Text('Complemento: $complemento', style: const TextStyle(color: Colors.black54)),
                                    if (detalles.isNotEmpty) Text('Detalle: $detalles', style: const TextStyle(color: Colors.black54)),
                                    const SizedBox(height: 8),
                                    Text('Solicitante: $solicitante', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => _rechazarSolicitudDireccion(solicitud),
                                            child: const Text('Rechazar'),
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () => _aprobarSolicitudDireccion(solicitud),
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
                                            child: const Text('Aprobar e incluir'),
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
        ],
      ),
    );
  }

  Widget _buildVistaEstadisticasAdminTerritorios() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('estadisticas_mensuales').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estadísticas y Historial', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Resumen mensual', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ElevatedButton(
                            onPressed: _guardarEstadisticasMensuales,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
                            child: const Text('Cerrar mes'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _cargarResumenEstadisticasActual(),
                        builder: (context, snapshotResumen) {
                          if (!snapshotResumen.hasData) {
                            return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CircularProgressIndicator()));
                          }
                          final data = snapshotResumen.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _filaEstadistica('Territorios', data['territorios']),
                              _filaEstadistica('Tarjetas', data['tarjetas']),
                              _filaEstadistica('Direcciones', data['direcciones']),
                              _filaEstadistica('Direcciones enviadas', data['direcciones_enviadas']),
                              _filaEstadistica('Predicadas', data['predicadas']),
                              _filaEstadistica('No predicadas', data['no_predicadas']),
                              _filaEstadistica('No hispanohablantes', data['no_hispano']),
                              _filaEstadistica('Invitaciones entregadas', data['invitaciones']),
                              _filaEstadistica('Usuarios activos', data['usuarios_activos']),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Historial de meses', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.data!.docs.isEmpty)
                const Center(child: Text('No hay registros históricos aún.', style: TextStyle(color: Colors.grey)))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final doc = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc['mes'] ?? 'Sin mes', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text('Territorios: ${doc['territorios'] ?? 0} • Tarjetas: ${doc['tarjetas'] ?? 0} • Direcciones: ${doc['direcciones'] ?? 0}'),
                              const SizedBox(height: 4),
                              Text('Predicadas: ${doc['predicadas'] ?? 0} • No predicadas: ${doc['no_predicadas'] ?? 0}'),
                              const SizedBox(height: 4),
                              Text('Top publicador: ${doc['top_publicador'] ?? '-'} (${doc['top_publicador_cantidad'] ?? 0})'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filaEstadistica(String nombre, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(nombre, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          Text(valor.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _cargarResumenEstadisticasActual() async {
    final territoriosSnapshot = await FirebaseFirestore.instance.collection('territorios').get();
    final tarjetasSnapshot = await FirebaseFirestore.instance.collectionGroup('tarjetas').get();
    final direccionesSnapshot = await FirebaseFirestore.instance.collection('direcciones_globales').get();
    final solicitudesSnapshot = await FirebaseFirestore.instance.collection('solicitudes_direcciones').where('estado', isEqualTo: 'pendiente').get();
    final totalTerritorios = territoriosSnapshot.docs.length;
    final totalTarjetas = tarjetasSnapshot.docs.length;
    final totalDirecciones = direccionesSnapshot.docs.length;
    final totalSolicitudesEnviadas = solicitudesSnapshot.docs.length;
    final predicadas = direccionesSnapshot.docs.where((doc) => (doc['predicado'] ?? false) == true).length;
    final noPredicadas = direccionesSnapshot.docs.where((doc) => (doc['no_predicado'] ?? false) == true).length;
    final noHispanos = direccionesSnapshot.docs.where((doc) => (doc['es_hispano'] ?? true) == false).length;
    final invitaciones = direccionesSnapshot.docs.where((doc) => (doc['entrego_invitacion'] ?? false) == true).length;
    final usuariosActivos = direccionesSnapshot.docs.map((doc) => doc['publicador_email'] ?? '').where((email) => (email as String).isNotEmpty).toSet().length;

    return {
      'territorios': totalTerritorios,
      'tarjetas': totalTarjetas,
      'direcciones': totalDirecciones,
      'predicadas': predicadas,
      'no_predicadas': noPredicadas,
      'no_hispano': noHispanos,
      'invitaciones': invitaciones,
      'direcciones_enviadas': totalSolicitudesEnviadas,
      'usuarios_activos': usuariosActivos,
    };
  }

  @override
  Widget build(BuildContext context) {
    final esConductor = widget.usuarioData['es_conductor'] ?? false;
    final esAdmin = widget.usuarioData['es_admin'] ?? false;
    final esAdminTerritorios = widget.usuarioData['es_admin_territorios'] ?? false;
    final nombre = widget.usuarioData['nombre'] ?? 'Hermano';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF263238)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text('Menú de modos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay notificaciones nuevas')));
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Color(0xFF1B5E20)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Idioma', style: TextStyle(fontWeight: FontWeight.bold))),
                    ChoiceChip(
                      label: const Text('ES'),
                      selected: _idiomaActual == 'ES',
                      selectedColor: const Color(0xFF1B5E20),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey.shade200,
                      onSelected: (selected) => setState(() => _idiomaActual = 'ES'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('PT'),
                      selected: _idiomaActual == 'PT',
                      selectedColor: const Color(0xFF1B5E20),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey.shade200,
                      onSelected: (selected) => setState(() => _idiomaActual = 'PT'),
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
                child: Text('Vistas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
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
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF1B5E20)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Araucária Sur', style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, letterSpacing: 0.3)),
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: !_modoAdminActivo && !_modoAdminTerritoriosActivo && !_modoConductorActivo
          ? Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: _mostrarDialogoSolicitarTarjetasPublicador,
                icon: const Icon(Icons.card_giftcard, color: Colors.white, size: 24),
                label: const Text(
                  'Solicitar Território',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                backgroundColor: const Color(0xFF0D2818).withOpacity(0.85),
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildVistaHome(String nombre, bool esConductor, bool esAdmin, bool esAdminTerritorios) {
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
                Expanded(child: Text('Administración', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF263238)))),
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
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.folder_copy, color: Color(0xFF1B5E20)), text: 'Estructura'),
                Tab(icon: Icon(Icons.map, color: Color(0xFF1B5E20)), text: 'Territorios'),
                Tab(icon: Icon(Icons.campaign, color: Color(0xFF1B5E20)), text: 'Comunicación'),
                Tab(icon: Icon(Icons.people_outline, color: Color(0xFF1B5E20)), text: 'Usuarios'),
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
                      const Text('1. Directorio Maestro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: _levantarArchivoCSV,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Subir CSV a Directorio Maestro', style: TextStyle(fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _verDirectorioGlobal,
                        icon: const Icon(Icons.list_alt, color: Color(0xFF1B5E20)),
                        label: const Text('Ver contenido del Directorio Global', style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text('2. Gestión de Territorios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _mostrarDialogoCrearTerritorio,
                          icon: const Icon(Icons.create_new_folder),
                          label: const Text('Crear Nuevo Territorio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Territorios Creados:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('territorios').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(child: Text('No hay territorios creados aún.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return GestureDetector(
                                onTap: () => _abrirTerritorio(doc.id, doc['nombre']),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  color: Colors.green.shade50,
                                  elevation: 2,
                                  child: ListTile(
                                    leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                                    title: Text(doc['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    subtitle: StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(doc.id)
                                          .collection('tarjetas')
                                          .snapshots(),
                                      builder: (context, tarjetasSnapshot) {
                                        int cantidadTarjetas = tarjetasSnapshot.data?.docs.length ?? 0;
                                        return Text('Tarjetas vinculadas: $cantidadTarjetas');
                                      },
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.orange),
                                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Editar ${doc['nombre']} (Próximo paso)'))),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                          onPressed: () => _borrarTerritorio(doc.id, doc['nombre']),
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
                      const Text('Territorios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)) ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('territorios').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(child: Text('No hay territorios creados aún.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
                            );
                          }
                                    return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return InkWell(
                                onTap: () => _abrirTerritorio(doc.id, doc['nombre'], readOnly: true),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(14)),
                                              child: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(doc['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                  const SizedBox(height: 6),
                                                  StreamBuilder<QuerySnapshot>(
                                                    stream: FirebaseFirestore.instance.collection('territorios').doc(doc.id).collection('tarjetas').snapshots(),
                                                    builder: (context, tarjetasSnapshot) {
                                                      final int cantidadTarjetas = tarjetasSnapshot.data?.docs.length ?? 0;
                                                      return Text('Tarjetas vinculadas: $cantidadTarjetas', style: const TextStyle(color: Colors.grey));
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () => _confirmarEnvioTerritorio(doc.id, doc['nombre']),
                                            icon: const Icon(Icons.send, color: Colors.green),
                                            label: const Text('Enviar territorio completo'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green,
                                              side: const BorderSide(color: Colors.green),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      const Text('Gestión de Usuarios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
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
                              child: Center(child: Text('No hay usuarios registrados.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
                            );
                          }

                          return Column(
                            children: snapshot.data!.docs.map((usuario) {
                              final data = usuario.data() as Map<String, dynamic>;
                              final String nombreUsuario = data['nombre'] ?? 'Usuario';
                              final String emailUsuario = data['email'] ?? '';
                              final String estadoUsuario = data['estado'] ?? 'pendiente';
                              final bool esAdminUsuario = data['es_admin'] ?? false;
                              final bool esConductorUsuario = data['es_conductor'] ?? false;
                              final bool esAdminTerritoriosUsuario = data['es_admin_territorios'] ?? false;
                              final bool esPublicadorUsuario = data['es_publicador'] ?? false;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(nombreUsuario, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text(emailUsuario, style: const TextStyle(color: Colors.grey)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text('Estado: $estadoUsuario', style: const TextStyle(color: Colors.black87)),
                                          ),
                                          if (estadoUsuario != 'aprobado')
                                            ElevatedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'estado': 'aprobado'});
                                              },
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                              child: const Text('Aprobar'),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SwitchListTile(
                                        title: const Text('Admin'),
                                        value: esAdminUsuario,
                                        activeColor: Colors.redAccent,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_admin': value});
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Admin Territorios'),
                                        value: esAdminTerritoriosUsuario,
                                        activeColor: Colors.purple,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_admin_territorios': value});
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Conductor'),
                                        value: esConductorUsuario,
                                        activeColor: const Color(0xFF1B5E20),
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_conductor': value});
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('Publicador'),
                                        value: esPublicadorUsuario,
                                        activeColor: Colors.blue,
                                        contentPadding: EdgeInsets.zero,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_publicador': value});
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _mostrarDialogoGestionUsuarios(),
                                              child: const Text('Gestión avanzada'),
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
        content: Text('¿Eliminar el territorio "$nombreTerritorio"? Esto NO eliminará las direcciones del directorio global.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    
    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance.collection('territorios').doc(territorioId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$nombreTerritorio eliminado correctamente')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
        }
      }
    }
  }

  void _confirmarEnvioTerritorio(String territorioId, String nombreTerritorio) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enviar Territorio'),
        content: Text('¿Deseas enviar el territorio "$nombreTerritorio" completo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se envió el territorio "$nombreTerritorio" correctamente.')),
      );
    }
  }

  void _confirmarEnvioTarjeta(String terId, String tarjetaId, String tarjetaNombre) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enviar Tarjeta'),
        content: Text('¿Deseas enviar la tarjeta "$tarjetaNombre" del territorio?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se envió la tarjeta "$tarjetaNombre" correctamente.')),
      );
    }
  }

  void _mostrarDialogoCrearTerritorio() {
    final TextEditingController nombreCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 40, color: Color(0xFF1B5E20)),
                    const SizedBox(height: 16),
                    const Text('Crear Nuevo Territorio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nombreCtrl,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Nombre del territorio',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 2)),
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
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un nombre')));
                            return;
                          }
                          await FirebaseFirestore.instance.collection('territorios').doc(nombre).set({
                            'nombre': nombre,
                            'cantidad_direcciones': 0,
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Crear Carpeta', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _mostrarDialogoGestionUsuarios() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Gestión de Usuarios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('No hay usuarios registrados.'));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final usuario = docs[index];
                          final data = usuario.data() as Map<String, dynamic>;
                          final esAdmin = data['es_admin'] ?? false;
                          final esConductor = data['es_conductor'] ?? false;
                          final esPublicador = data['es_publicador'] ?? false;
                          final esAdminTerritorios = data['es_admin_territorios'] ?? false;
                          final grupoId = data['grupo_id'] ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['nombre'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(data['email'] ?? '', style: const TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SwitchListTile(
                                          title: const Text('Admin'),
                                          value: esAdmin,
                                          contentPadding: EdgeInsets.zero,
                                          activeColor: Colors.redAccent,
                                          onChanged: (value) async {
                                            await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_admin': value});
                                          },
                                        ),
                                      ),
                                      Expanded(
                                        child: SwitchListTile(
                                          title: const Text('Conductor'),
                                          value: esConductor,
                                          contentPadding: EdgeInsets.zero,
                                          activeColor: const Color(0xFF1B5E20),
                                          onChanged: (value) async {
                                            await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_conductor': value});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  SwitchListTile(
                                    title: const Text('Publicador'),
                                    value: esPublicador,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: Colors.blue,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_publicador': value});
                                    },
                                  ),
                                  SwitchListTile(
                                    title: const Text('Admin Territorios'),
                                    value: esAdminTerritorios,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: Colors.purple,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance.collection('usuarios').doc(usuario.id).update({'es_admin_territorios': value});
                                    },
                                  ),
                                  TextField(
                                    decoration: InputDecoration(
                                      labelText: 'Grupo ID',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      isDense: true,
                                    ),
                                    controller: TextEditingController(text: grupoId.toString()),
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
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
                    child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _abrirTerritorio(String terId, String terNombre, {bool readOnly = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(terNombre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)))),
                        IconButton(icon: const Icon(Icons.close, size: 28), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(thickness: 2),
                    if (readOnly)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmarEnvioTerritorio(terId, terNombre),
                          icon: const Icon(Icons.send, color: Colors.green),
                          label: const Text('Enviar territorio completo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          onPressed: () => _mostrarDialogoCrearTarjeta(context, terId),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Crear Nueva Tarjeta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    if (!readOnly) const SizedBox(height: 16),
                    const Text('Tarjetas en este Territorio:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .doc(terId)
                            .collection('tarjetas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Center(child: Text('No hay tarjetas creadas aún.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));
                          }
                          
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var tarjeta = snapshot.data!.docs[index];
                              String tarjetaId = tarjeta.id;
                              String tarjetaNombre = tarjeta['nombre'];
                              int cantidadDir = tarjeta['cantidad_direcciones'] ?? 0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: Colors.blue.shade50,
                                elevation: 2,
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.folder, color: Colors.blue),
                                      title: Text(tarjetaNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      subtitle: Text('Dir. vinculadas: $cantidadDir'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (readOnly)
                                            IconButton(
                                              icon: const Icon(Icons.send, color: Colors.green),
                                              onPressed: () => _confirmarEnvioTarjeta(terId, tarjetaId, tarjetaNombre),
                                              tooltip: 'Enviar tarjeta',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                                              onPressed: () => _agregarDireccionesATarjeta(context, terId, tarjetaId, tarjetaNombre),
                                              tooltip: 'Agregar direcciones',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: Icon(
                                                tarjeta['disponible_para_publicadores'] == true ? Icons.lock_open : Icons.lock,
                                                color: tarjeta['disponible_para_publicadores'] == true ? Colors.green : Colors.grey,
                                              ),
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection('territorios')
                                                    .doc(terId)
                                                    .collection('tarjetas')
                                                    .doc(tarjetaId)
                                                    .set({
                                                      'disponible_para_publicadores': !(tarjeta['disponible_para_publicadores'] ?? false),
                                                    },
                                                    SetOptions(merge: true),
                                                );
                                              },
                                              tooltip: tarjeta['disponible_para_publicadores'] == true
                                                  ? 'Quitar disponibilidad para publicadores'
                                                  : 'Hacer disponible para publicadores',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(Icons.schedule, color: Colors.deepPurple),
                                              onPressed: () => _mostrarDialogoProgramarEnvio(terId, tarjetaId: tarjetaId, nombre: tarjetaNombre, isTarjeta: true),
                                              tooltip: 'Programar envío de tarjeta',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(Icons.edit, color: Colors.orange),
                                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editar Tarjeta (Próximo paso)'))),
                                              tooltip: 'Editar tarjeta',
                                            ),
                                          if (!readOnly)
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                              tooltip: 'Eliminar tarjeta',
                                              onPressed: () async {
                                                bool? confirmar = await showDialog(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                    title: const Text('⚠️ Eliminar Tarjeta'),
                                                    content: Text('¿Eliminar la tarjeta "$tarjetaNombre"? Esto eliminará todas sus direcciones vinculadas.'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(c, false),
                                                        child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                                      ),
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(c, true),
                                                        child: const Text('SÍ, Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirmar == true) {
                                                  await FirebaseFirestore.instance
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
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                      child: StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('direcciones_globales')
                                            .where('tarjeta_id', isEqualTo: tarjetaId)
                                            .snapshots(),
                                        builder: (context, dirSnapshot) {
                                          if (!dirSnapshot.hasData || dirSnapshot.data!.docs.isEmpty) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text('Sin direcciones asignadas', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                                            );
                                          }

                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Direcciones:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                                              const SizedBox(height: 8),
                                              ...dirSnapshot.data!.docs.map((dirDoc) {
                                                String complemento = dirDoc['complemento'] ?? '';
                                                String informacion = dirDoc['informacion'] ?? '';
                                                
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 10.0),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: Colors.blue.shade200),
                                                      boxShadow: [
                                                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
                                                      ],
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.all(12),
                                                          child: Row(
                                                            children: [
                                                              const Icon(Icons.location_on, size: 18, color: Colors.blue),
                                                              const SizedBox(width: 10),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(
                                                                      dirDoc['calle'] ?? '',
                                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF263238)),
                                                                    ),
                                                                    Text(
                                                                      dirDoc['barrio'] ?? 'Sin barrio',
                                                                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 100,
                                                                child: Row(
                                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                                  children: [
                                                                    IconButton(
                                                                      icon: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                                                                      onPressed: () => _mostrarDetallesDireccion(dirDoc),
                                                                      padding: EdgeInsets.zero,
                                                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                                      tooltip: 'Ver detalles',
                                                                    ),
                                                                    if (!readOnly)
                                                                      IconButton(
                                                                        icon: const Icon(Icons.edit, size: 16, color: Colors.orange),
                                                                        onPressed: () => _editarDireccion(dirDoc),
                                                                        padding: EdgeInsets.zero,
                                                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                                        tooltip: 'Editar',
                                                                      ),
                                                                    if (!readOnly)
                                                                      IconButton(
                                                                        icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                                                        onPressed: () => _eliminarDireccion(dirDoc.id, terId, tarjetaId),
                                                                        padding: EdgeInsets.zero,
                                                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                                        tooltip: 'Eliminar',
                                                                      ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (complemento.isNotEmpty || informacion.isNotEmpty)
                                                          Container(
                                                            width: double.infinity,
                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                            decoration: BoxDecoration(
                                                              color: Colors.grey.shade50,
                                                              border: Border(top: BorderSide(color: Colors.blue.shade100)),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                if (complemento.isNotEmpty)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(bottom: 6),
                                                                    child: Row(
                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                      children: [
                                                                        const Icon(Icons.apartment, size: 14, color: Colors.orange),
                                                                        const SizedBox(width: 6),
                                                                        Expanded(
                                                                          child: Text(
                                                                            complemento,
                                                                            style: const TextStyle(fontSize: 11, color: Color(0xFF263238)),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                if (informacion.isNotEmpty)
                                                                  Row(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const Icon(Icons.note, size: 14, color: Colors.green),
                                                                      const SizedBox(width: 6),
                                                                      Expanded(
                                                                        child: Text(
                                                                          informacion,
                                                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                                                          maxLines: 2,
                                                                          overflow: TextOverflow.ellipsis,
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
    final String complemento = dirDoc['complemento'] ?? 'No especificado';
    final String informacion = dirDoc['informacion'] ?? 'No especificada';
    final String calle = dirDoc['calle'] ?? '';
    final String barrio = dirDoc['barrio'] ?? 'Sin barrio';
    final String estadoPredicacion = dirDoc['estado_predicacion'] ?? 'pendiente';
    final bool predicado = dirDoc['predicado'] ?? false;
    final bool noPredicado = dirDoc['no_predicado'] ?? false;
    final bool esHispano = dirDoc['es_hispano'] ?? true;
    final bool entregoInvitacion = dirDoc['entrego_invitacion'] ?? false;
    final bool campanaEspecial = dirDoc['campana_especial'] ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                _detalleCard('📍 Calle', calle, Colors.blue, const Color(0xFFB3E5FC)),
                const SizedBox(height: 12),
                _detalleCard('🏘️ Barrio', barrio, Colors.green, const Color(0xFFC8E6C9)),
                const SizedBox(height: 12),
                _detalleCard('🏠 Complemento', complemento, Colors.orange, const Color(0xFFFFE0B2)),
                const SizedBox(height: 12),
                _detalleCard('📝 Información', informacion, Colors.purple, const Color(0xFFE1BEE7)),
                const SizedBox(height: 12),
                _detalleCard('📌 Estado predicación', estadoPredicacion, Colors.teal, const Color(0xFFB2DFDB)),
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
                    _chipDetalle(esHispano ? 'Hispano' : 'No hispano', esHispano),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detalleCard(String titulo, String valor, Color iconColor, Color backgroundColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: iconColor)),
          const SizedBox(height: 6),
          Text(valor, style: const TextStyle(fontSize: 14, color: Color(0xFF263238))),
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
      child: Text(texto, style: TextStyle(fontSize: 12, color: activo ? Colors.green.shade900 : Colors.black54)),
    );
  }

  Widget _buildDirectionStatusButton(QueryDocumentSnapshot doc, String estado, String label) {
    return ElevatedButton(
      onPressed: () async {
        final data = doc.data() as Map<String, dynamic>;
        final currentEstado = data['estado_predicacion'] ?? 'pendiente';
        if (currentEstado == estado) return;
        await doc.reference.update({
          'estado_predicacion': estado,
          'predicado': estado == 'predicado',
          'no_predicado': estado == 'no_predicado',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Estado actualizado a $label')),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade50,
        foregroundColor: const Color(0xFF1B5E20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  void _editarDireccion(QueryDocumentSnapshot dirDoc) {
    final TextEditingController calleCtrl = TextEditingController(text: dirDoc['calle'] ?? '');
    final TextEditingController complementoCtrl = TextEditingController(text: dirDoc['complemento'] ?? '');
    final TextEditingController informacionCtrl = TextEditingController(text: dirDoc['informacion'] ?? '');
    bool predicado = dirDoc['predicado'] ?? false;
    bool noPredicado = dirDoc['no_predicado'] ?? false;
    bool noHispano = (dirDoc['es_hispano'] ?? true) == false;
    bool entregoInvitacion = dirDoc['entrego_invitacion'] ?? false;
    bool campanaEspecial = dirDoc['campana_especial'] ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_location, size: 40, color: Colors.orange),
                      const SizedBox(height: 16),
                      const Text('Editar Dirección', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: calleCtrl,
                        decoration: InputDecoration(
                          hintText: 'Calle',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: complementoCtrl,
                        decoration: InputDecoration(
                          hintText: 'Complemento',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: informacionCtrl,
                        decoration: InputDecoration(
                          hintText: 'Información',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.orange, width: 2)),
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
                        onChanged: (value) => setDialogState(() => noHispano = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Entregó invitación'),
                        value: entregoInvitacion,
                        activeColor: Colors.blue,
                        onChanged: (value) => setDialogState(() => entregoInvitacion = value ?? false),
                      ),
                      if (_campanaEspecialActiva) 
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Campaña especial activa'),
                          value: campanaEspecial,
                          activeColor: Colors.deepOrange,
                          onChanged: (value) => setDialogState(() => campanaEspecial = value ?? false),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
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
                                await FirebaseFirestore.instance.collection('direcciones_globales').doc(dirDoc.id).update({
                                  'calle': calleCtrl.text.trim(),
                                  'complemento': complementoCtrl.text.trim(),
                                  'informacion': informacionCtrl.text.trim(),
                                  'direccion_normalizada': _normalizarDireccion('${calleCtrl.text.trim()} ${complementoCtrl.text.trim()}'),
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
                                    const SnackBar(content: Text('✅ Dirección actualizada'), backgroundColor: Colors.green),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
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
        content: const Text('¿Estás completamente seguro de que deseas eliminar esta dirección? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('SÍ, Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance.collection('direcciones_globales').doc(dirId).delete();

        DocumentSnapshot snap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .collection('tarjetas')
            .doc(tarjetaId)
            .get();
        int currentCount = snap.data() != null ? (snap.data() as Map)['cantidad_direcciones'] ?? 0 : 0;

        if (currentCount > 0) {
          await FirebaseFirestore.instance
              .collection('territorios')
              .doc(terId)
              .collection('tarjetas')
              .doc(tarjetaId)
              .update({
            'cantidad_direcciones': currentCount - 1,
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Dirección eliminada correctamente'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error al eliminar: $e'), backgroundColor: Colors.red),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 40, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text('Crear Nueva Tarjeta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextField(controller: ctrl, textAlign: TextAlign.center, decoration: _inputStyleHelper('Ej: A01 - CENTRO 1')),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Por favor ingresa un nombre para la tarjeta')),
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
                            });
                            
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            
                            if (parentContext.mounted) {
                              await Future.delayed(const Duration(milliseconds: 500));
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Crear Tarjeta', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _agregarDireccionesATarjeta(BuildContext parentContext, String terId, String tarjetaId, String tarjetaNombre) {
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(tarjetaNombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    
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
                              Icon(Icons.edit_document, color: Colors.blue, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Crear Dirección Manual',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
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
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.blue, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.location_on, color: Colors.blue),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: complementoCtrl,
                            decoration: InputDecoration(
                              hintText: 'Complemento (Apto, Casa, Lote, etc.)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.blue, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.home, color: Colors.blue),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: informacionCtrl,
                            decoration: InputDecoration(
                              hintText: 'Información (Notas, referencias, etc.)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.blue, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.info, color: Colors.blue),
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
                                    const SnackBar(content: Text('Por favor ingresa una dirección')),
                                  );
                                  return;
                                }

                                try {
                                  String nombreDireccion = direccionCtrl.text.trim();
                                  String docId = "${terId}_${tarjetaId}_${nombreDireccion.replaceAll(' ', '_')}";
                                  
                                  await FirebaseFirestore.instance.collection('direcciones_globales').doc(docId).set({
                                    'calle': nombreDireccion,
                                    'direccion_normalizada': _normalizarDireccion('$nombreDireccion ${complementoCtrl.text.trim()}'),
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

                                  DocumentSnapshot snap = await FirebaseFirestore.instance
                                      .collection('territorios')
                                      .doc(terId)
                                      .collection('tarjetas')
                                      .doc(tarjetaId)
                                      .get();
                                  int currentCount = snap.data() != null ? (snap.data() as Map)['cantidad_direcciones'] ?? 0 : 0;

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
                                        content: Text('✅ Dirección agregada correctamente'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('direcciones_globales')
                            .where('tarjeta_id', isNull: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          
                          if (snapshot.data!.docs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.inbox, size: 40, color: Colors.grey),
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
                              bool isChecked = idsSeleccionados.contains(doc.id);
                              return CheckboxListTile(
                                dense: true,
                                title: Text(
                                  doc['calle'],
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 12, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      doc['barrio'] ?? 'Sin barrio',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                value: isChecked,
                                activeColor: Colors.blue,
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
                                WriteBatch batch = FirebaseFirestore.instance.batch();

                                for (String idDir in idsSeleccionados) {
                                  batch.update(
                                    FirebaseFirestore.instance.collection('direcciones_globales').doc(idDir),
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

                                DocumentSnapshot snap = await FirebaseFirestore.instance
                                    .collection('territorios')
                                    .doc(terId)
                                    .collection('tarjetas')
                                    .doc(tarjetaId)
                                    .get();
                                int currentCount = snap.data() != null ? (snap.data() as Map)['cantidad_direcciones'] ?? 0 : 0;

                                batch.update(
                                  FirebaseFirestore.instance
                                      .collection('territorios')
                                      .doc(terId)
                                      .collection('tarjetas')
                                      .doc(tarjetaId),
                                  {'cantidad_direcciones': currentCount + idsSeleccionados.length},
                                );

                                await batch.commit();

                                if (parentContext.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(parentContext).showSnackBar(
                                    SnackBar(
                                      content: Text('✅ ${idsSeleccionados.length} direcciones asignadas a $tarjetaNombre'),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  InputDecoration _inputStyleHelper(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)),
    );
  }

  void _verDirectorioGlobal() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Directorio Global', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context))
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('direcciones_globales').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('El Directorio Global está vacío', style: TextStyle(color: Colors.grey)));
                      }
                      
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          var doc = snapshot.data!.docs[index];
                          String estado = doc['estado'] ?? 'desconocido';
                          Color colorEstado = estado == 'asignada' ? Colors.green : Colors.grey;
                          
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.location_on, color: colorEstado, size: 20),
                            title: Text(doc['calle'], style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              doc['barrio'] ?? 'Sin barrio',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                              onSelected: (value) async {
                                if (value == 'eliminar') {
                                  bool? confirmar = await showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Eliminar Dirección'),
                                      content: Text('¿Eliminar "${doc['calle']}" del directorio global?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    await FirebaseFirestore.instance.collection('direcciones_globales').doc(doc.id).delete();
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text('Eliminar dirección', style: TextStyle(color: Colors.red)),
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

  double _calcularDistanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return R * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  void _levantarArchivoCSV() {
    startCsvUpload(
      (String contenidoDelArchivo) {
        List<String> lineas = contenidoDelArchivo.split('\n');
        if (lineas.isNotEmpty) lineas.removeAt(0);

        List<String> direccionesExtraidas = [];

        for (var linea in lineas) {
          if (linea.trim().isEmpty) continue;

          List<String> columnas = linea.split(',');
          if (columnas.length > 1) {
            String calle = columnas[1].trim();
            if (calle.isNotEmpty) {
              direccionesExtraidas.add(calle);
            }
          }
        }

        if (mounted) {
          if (direccionesExtraidas.isNotEmpty) {
            _iniciarGeolocalizacionOSM(direccionesExtraidas);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: No se pudieron extraer calles.'), backgroundColor: Colors.redAccent),
            );
          }
        }
      },
      onUnsupported: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Carga de CSV solo está disponible en la web.'), backgroundColor: Colors.orangeAccent),
          );
        }
      },
    );
  }

  void _iniciarGeolocalizacionOSM(List<String> direcciones) async {
    List<Map<String, dynamic>> direccionesGeolocalizadas = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int progresoActual = direccionesGeolocalizadas.length;
            double porcentaje = (progresoActual / direcciones.length);

            return AlertDialog(
              title: const Text('Procesando con OpenStreetMap'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Obteniendo coordenadas exactas. Esto tomará aproximadamente 2 minutos.\n¡Por favor no cierre la app!'),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: porcentaje, backgroundColor: Colors.grey.shade300, color: const Color(0xFF1B5E20)),
                  const SizedBox(height: 10),
                  Text('Dirección $progresoActual de ${direcciones.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            );
          },
        );
      },
    );

    for (int i = 0; i < direcciones.length; i++) {
      String calle = direcciones[i];
      String busquedaCompleta = "$calle, Araucária - PR, Brasil";

      try {
        String url = 'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(busquedaCompleta)}&format=json&limit=1';
        http.Response respuesta = await http.get(Uri.parse(url));

        if (respuesta.statusCode == 200) {
          List datos = jsonDecode(respuesta.body);
          
          if (datos.isNotEmpty) {
            String latitud = datos[0]['lat'].toString();
            String longitud = datos[0]['lon'].toString();
            
            String barrio = "";
            if (datos[0].containsKey('address') && datos[0]['address'].containsKey('suburb')) {
              barrio = datos[0]['address']['suburb'].toString();
            }
            
            direccionesGeolocalizadas.add({
              'calle': calle,
              'lat': latitud,
              'lon': longitud,
              'barrio': barrio,
              'status': latitud.isNotEmpty ? 'pendiente' : 'no_encontrada',
            });
          } else {
            direccionesGeolocalizadas.add({
              'calle': calle,
              'lat': "",
              'lon': "",
              'barrio': "",
              'status': 'no_encontrada',
            });
          }
        }
      } catch (e) {
        direccionesGeolocalizadas.add({
          'calle': calle,
          'lat': "",
          'lon': "",
          'barrio': "",
          'status': 'error_gps',
        });
      }

      await Future.delayed(const Duration(milliseconds: 1100));
    }

    if (mounted) {
      Navigator.pop(context);
      
      List<Map<String, dynamic>> exitosas = direccionesGeolocalizadas
          .where((d) => d['lat'].toString().isNotEmpty)
          .toList();
      int fallidas = direcciones.length - exitosas.length;

      if (exitosas.isNotEmpty) {
        showDialog(
          context: context, 
          barrierDismissible: false, 
          builder: (c) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Guardando en Directorio Global...")
              ],
            ),
          )
        );

        WriteBatch batch = FirebaseFirestore.instance.batch();
        CollectionReference refGlobal = FirebaseFirestore.instance.collection('direcciones_globales');

        for (var dir in exitosas) {
          String docId = dir['calle'].toString().replaceAll(' ', '_');
          
          batch.set(refGlobal.doc(docId), {
            'calle': dir['calle'],
            'direccion_normalizada': _normalizarDireccion(dir['calle'].toString()),
            'complemento': '',
            'informacion': '',
            'lat': dir['lat'],
            'lon': dir['lon'],
            'barrio': dir['barrio'] ?? '',
            'estado': 'activa',
            'territorio_id': null,
            'tarjeta_id': null,
            'created_at': FieldValue.serverTimestamp(),
          });
        }

        try {
          await batch.commit();

          if (mounted) {
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('¡Guardado en la Nube!'),
                content: Text(
                  'Se guardaron ${exitosas.length} direcciones exactas en el Directorio Global.\n'
                  'Se detectaron automáticamente los barrios reales.\n\n'
                  '❌ $fallidas no se guardaron por falta de datos GPS.\n\n'
                  'Presiona "Ver contenido del Directorio Global" para revisar.'
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                ],
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
          }
        }
      }
    }
  }

  Widget _buildVistaTarjetas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.credit_card, size: 80, color: Color(0xFF1B5E20)),
          SizedBox(height: 20),
          Text('Tarjetas (En desarrollo)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildVistaLocalizador() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Localizador de direcciones', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
          const SizedBox(height: 8),
          const Text('Busca una dirección en el registro global o solicita al administrador agregarla si no existe.', style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 20),
          TextField(
            controller: _localizadorController,
            decoration: _inputStyleHelper('Ingresa calle, número o punto de referencia'),
            onChanged: (_) {
              if (_localizadorBuscado) {
                setState(() {
                  _localizadorBuscado = false;
                  _localizadorMensaje = '';
                  _mostrarSolicitudLocalizador = false;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _buscarDireccionGlobal,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Buscar dirección', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_localizadorBuscado) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: _localizadorEncontrada ? Colors.green.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizadorMensaje,
                      style: TextStyle(
                        fontSize: 14,
                        color: _localizadorEncontrada ? const Color(0xFF1B5E20) : const Color(0xFF4E342E),
                      ),
                    ),
                    if (!_localizadorEncontrada && _mostrarSolicitudLocalizador) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _complementoLocalizadorController,
                        decoration: _inputStyleHelper('Complemento / referencia adicional'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _detallesLocalizadorController,
                        maxLines: 3,
                        decoration: _inputStyleHelper('Detalles de la ubicación, piso, casa o nota para el admin'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _enviarDireccionParaRegistro,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text('Enviar solicitud al admin', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: const [
                  Icon(Icons.map, color: Color(0xFF4A148C)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Territorios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF263238)))),
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
                  Tab(icon: Icon(Icons.map, color: Color(0xFF4A148C)), text: 'Territorios'),
                  Tab(icon: Icon(Icons.timer, color: Color(0xFF4A148C)), text: 'Temporales'),
                  Tab(icon: Icon(Icons.delete_sweep, color: Color(0xFF4A148C)), text: 'Removidas'),
                  Tab(icon: Icon(Icons.bar_chart, color: Color(0xFF4A148C)), text: 'Estadísticas'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('territorios').orderBy('created_at', descending: true).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text('No hay territorios creados todavía.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: snapshot.data!.docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final territorio = snapshot.data!.docs[index];
                            final data = territorio.data() as Map<String, dynamic>;
                            final nombre = data['nombre'] ?? 'Territorio';
                            final cantidad = data['cantidad_direcciones'] ?? 0;
                            final descripcion = data['descripcion'] ?? '';
                            final ubicado = data['ubicacion'] ?? '';

                            return InkWell(
                              onTap: () => _abrirTerritorio(territorio.id, nombre, readOnly: true),
                              borderRadius: BorderRadius.circular(16),
                              child: Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
                                            child: const Icon(Icons.map, color: Color(0xFF4A148C)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                                const SizedBox(height: 4),
                                                Text('$cantidad direcciones', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              data['disponible_para_publicadores'] == true ? Icons.lock_open : Icons.lock,
                                              color: data['disponible_para_publicadores'] == true ? Colors.green : Colors.grey,
                                            ),
                                            onPressed: () async {
                                              await FirebaseFirestore.instance.collection('territorios').doc(territorio.id).set(
                                                {'disponible_para_publicadores': !(data['disponible_para_publicadores'] ?? false)},
                                                SetOptions(merge: true),
                                              );
                                            },
                                            tooltip: data['disponible_para_publicadores'] == true
                                                ? 'Quitar disponibilidad para publicadores'
                                                : 'Hacer disponible para publicadores',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.schedule, color: Color(0xFF4A148C)),
                                            onPressed: () => _mostrarDialogoProgramarEnvio(territorio.id, nombre: nombre, isTarjeta: false),
                                            tooltip: 'Programar envío de territorio',
                                          ),
                                          const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
                                        ],
                                      ),
                                      if (descripcion.isNotEmpty || ubicado.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(descripcion.isNotEmpty ? descripcion : ubicado, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                      ],
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
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.timer, size: 58, color: Color(0xFF4A148C)),
                          SizedBox(height: 16),
                          Text('Tarjetas Temporales', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
                          SizedBox(height: 10),
                          Text(
                            'Revisa aquí las tarjetas temporales pendientes para validación o reasignar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          SizedBox(height: 20),
                          Text('Este espacio mostrará tarjetas temporales disponibles.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.delete_sweep, size: 58, color: Color(0xFF4A148C)),
                          SizedBox(height: 16),
                          Text('Direcciones Removidas', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
                          SizedBox(height: 10),
                          Text(
                            'Aquí se podrán revisar direcciones que fueron removidas para restaurar o revisar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          SizedBox(height: 20),
                          Text('Ninguna dirección removida todavía.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                        ],
                      ),
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
  Widget _buildRoleChip(String text, bool enabled) {
    return Chip(
      label: Text(text, style: TextStyle(color: enabled ? Colors.white : Colors.black54, fontSize: 12)),
      backgroundColor: enabled ? const Color(0xFF1B5E20) : Colors.grey.shade200,
      side: enabled ? null : BorderSide(color: Colors.grey.shade400),
    );
  }

  Widget _buildContenidoConductor() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const Icon(Icons.directions_car, size: 58, color: Color(0xFF1B5E20)),
          const SizedBox(height: 16),
          const Text('Modo Conductor de Grupo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
          const SizedBox(height: 12),
          const Text(
            'Aquí verás territorios y tarjetas programadas para envío. Marca qué vas a recibir y gestiona tu ruta con claridad.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                const Text('Territorios asignados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('territorios').where('conductor_email', isEqualTo: _usuarioEmail).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text('No tienes territorios asignados aún.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final nombre = data['nombre'] ?? 'Territorio';
                        final fecha = data['programado_para'] is Timestamp ? (data['programado_para'] as Timestamp).toDate() : null;
                        final estatus = data['estatus_envio'] ?? 'pendiente';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.map, color: Color(0xFF1B5E20)),
                            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Estado: $estatus${fecha != null ? ' • ${fecha.day}/${fecha.month}/${fecha.year}' : ''}'),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text('Tarjetas asignadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collectionGroup('tarjetas').where('conductor_email', isEqualTo: _usuarioEmail).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text('No tienes tarjetas programadas todavía.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final nombre = data['nombre'] ?? 'Tarjeta';
                        final fecha = data['programado_para'] is Timestamp ? (data['programado_para'] as Timestamp).toDate() : null;
                        final estatus = data['estatus_envio'] ?? 'pendiente';
                        final terId = data['territorio_id'] ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.credit_card, color: Color(0xFF1B5E20)),
                            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Territorio: $terId • Estado: $estatus${fecha != null ? ' • ${fecha.day}/${fecha.month}/${fecha.year}' : ''}'),
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
    );
  }

  Widget _buildContenidoPublicador() {
    final nombrePublicador = widget.usuarioData['nombre'] ?? 'Publicador';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C), Color(0xFF43A047)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 25, offset: Offset(0, 12))],
            ),
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white24,
                  child: Text(
                    nombrePublicador.isNotEmpty ? nombrePublicador[0].toUpperCase() : 'A',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hola, $nombrePublicador', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Tu dashboard Publicador está listo para acción.', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                        child: const Text('Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _mostrarDialogoSolicitarTarjetasPublicador,
              icon: const Icon(Icons.card_giftcard, color: Colors.white),
              label: const Text(
                'Solicitar Território',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D2818),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 6,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_campanaEspecialActiva)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Campaña especial activa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFbf360c))),
                    const SizedBox(height: 8),
                    Text(_nombreCampanaEspecial.isNotEmpty ? _nombreCampanaEspecial : 'Sin nombre de campaña', style: const TextStyle(fontSize: 14, color: Color(0xFF4E342E))),
                    const SizedBox(height: 8),
                    const Text('Este mensaje se aplica a tus visitas actuales. Marca invitación y predicación con énfasis especial.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ),
          if (_campanaGeneralActiva && _anuncioGeneral.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anuncio general', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A237E))),
                    const SizedBox(height: 8),
                    Text(_anuncioGeneral, style: const TextStyle(fontSize: 14, color: Color(0xFF263238))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('direcciones_globales').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final todasDirecciones = snapshot.data!.docs;
                final totalGlobal = todasDirecciones.length;
                final predicadasGlobal = todasDirecciones.where((doc) {
                  final estado = (doc['estado_predicacion'] ?? '').toString().toLowerCase();
                  final predicado = doc['predicado'] ?? false;
                  return estado == 'completada' || predicado == true;
                }).length;
                final asignadas = todasDirecciones.where((doc) => (doc['publicador_email'] ?? '') == _usuarioEmail).toList();
                final completadas = asignadas.where((doc) {
                  final estado = (doc['estado_predicacion'] ?? '').toString().toLowerCase();
                  final predicado = doc['predicado'] ?? false;
                  return estado == 'completada' || predicado == true;
                }).length;
                final pendientes = asignadas.length - completadas;
                final avance = totalGlobal > 0 ? (predicadasGlobal / totalGlobal) * 100 : 0.0;
                final invitacionesEntregadas = asignadas.where((doc) => doc['entrego_invitacion'] == true).length;
                final campanaActiva = asignadas.where((doc) => doc['campana_especial'] == true).length;

                return ListView(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 3,
                      shadowColor: Colors.black.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Progreso global del territorio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                            const SizedBox(height: 12),
                            Text('${predicadasGlobal.toString()} de $totalGlobal direcciones predicadas', style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: LinearProgressIndicator(
                                value: totalGlobal > 0 ? predicadasGlobal / totalGlobal : 0.0,
                                minHeight: 16,
                                backgroundColor: const Color(0xFFF1F8E9),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1B5E20)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('${(totalGlobal > 0 ? (predicadasGlobal / totalGlobal) * 100 : 0).toStringAsFixed(0)}% del directorio global predicado', style: const TextStyle(color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Direcciones asignadas', style: TextStyle(fontSize: 14, color: Colors.black54)),
                                  const SizedBox(height: 8),
                                  Text('${asignadas.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                                  const SizedBox(height: 6),
                                  Text('Total asignadas', style: const TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Completadas', style: TextStyle(fontSize: 14, color: Colors.black54)),
                                  const SizedBox(height: 8),
                                  Text('$completadas', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                                  const SizedBox(height: 6),
                                  Text('$pendientes pendientes', style: const TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Colors.green.shade50,
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Progreso mensual', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(value: avance / 100, color: const Color(0xFF1B5E20), backgroundColor: Colors.green.shade100, minHeight: 10),
                            const SizedBox(height: 10),
                            Text('${avance.toStringAsFixed(0)}% completado', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Trabajo: $completadas', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                Text('Faltan: $pendientes', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('Los datos se actualizan mensualmente.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                    if (_campanaEspecialActiva) ...[
                      const SizedBox(height: 20),
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: Colors.orange.shade50,
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Campaña especial', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFbf360c))),
                              const SizedBox(height: 10),
                              Text('Direcciones en campaña: $campanaActiva', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              const SizedBox(height: 6),
                              Text('Invitaciones entregadas: $invitacionesEntregadas', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              const SizedBox(height: 8),
                              Text(_nombreCampanaEspecial.isNotEmpty ? _nombreCampanaEspecial : 'Campaña activa', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text('Mis direcciones asignadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    const SizedBox(height: 12),
                    if (asignadas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Aún no tienes direcciones asignadas.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      Column(
                        children: asignadas.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final calle = data['calle'] ?? 'Dirección';
                          final estado = data['estado_predicacion'] ?? 'pendiente';
                          final zona = data['territorio_nombre'] ?? data['territorio_id'] ?? '';
                          final isPredicado = (data['predicado'] ?? false) == true || estado == 'completada';
                          final statusLabel = isPredicado ? 'Se predicó' : estado == 'no_vive' ? 'No vive' : 'No se predicó';
                          final statusColor = isPredicado ? const Color(0xFF1B5E20) : estado == 'no_vive' ? const Color(0xFFF57C00) : const Color(0xFF757575);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 3,
                            shadowColor: Colors.black.withOpacity(0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(calle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
                                            const SizedBox(height: 8),
                                            Text(zona, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(14)),
                                        child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildDirectionStatusButton(doc, 'predicado', 'Se predicó'),
                                      _buildDirectionStatusButton(doc, 'no_predicado', 'No se predicó'),
                                      _buildDirectionStatusButton(doc, 'no_vive', 'No vive'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collectionGroup('tarjetas')
                          .where('solicitado_por_publicador_email', isEqualTo: _usuarioEmail)
                          .snapshots(),
                      builder: (context, snapshotSolicitudes) {
                        if (!snapshotSolicitudes.hasData) {
                          return const SizedBox();
                        }
                        if (snapshotSolicitudes.data!.docs.isEmpty) {
                          return const SizedBox();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const Text('Solicitudes de tarjetas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                            const SizedBox(height: 10),
                            ...snapshotSolicitudes.data!.docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final nombre = data['nombre'] ?? 'Tarjeta';
                              final territorio = data['territorio_nombre'] ?? data['territorio_id'] ?? 'Territorio';
                              final fecha = data['solicitado_en'] is Timestamp ? (data['solicitado_en'] as Timestamp).toDate() : null;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.request_page, color: Color(0xFF1B5E20)),
                                  title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('Territorio: $territorio${fecha != null ? ' • ${fecha.day}/${fecha.month}/${fecha.year}' : ''}'),
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// texto de prueba
