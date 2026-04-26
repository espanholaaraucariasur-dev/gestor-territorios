import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../home/presentation/pages/home_page.dart';

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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 4),
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
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!didAuthenticate) return;
      final storedEmail = await _secureStorage.read(key: 'biometric_email');
      if (storedEmail == null || storedEmail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontró cuenta biométrica configurada.'),
            ),
          );
        }
        return;
      }
      await _loginWithStoredEmail(storedEmail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error biométrico: $e')));
      }
    }
  }

  Future<void> _loginWithStoredEmail(String email) async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _db
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get();
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
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaHomeLegacy(usuarioData: u),
            ),
          );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.person_add_outlined,
                  size: 40,
                  color: Color(0xFF1B5E20),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Solicitar Acceso',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nomCtrl,
                  decoration: _inputDec('Nombre Completo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDec('Correo electrónico'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: _inputDec('Crear Contraseña'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nomCtrl.text.isEmpty ||
                          emailCtrl.text.isEmpty ||
                          passCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Completa todos los campos'),
                          ),
                        );
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
                          const SnackBar(
                            content: Text('¡Solicitud enviada!'),
                            backgroundColor: Color(0xFF1B5E20),
                          ),
                        );
                      } catch (e) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Enviar Solicitud',
                      style: TextStyle(fontWeight: FontWeight.bold),
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

  void _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _db
          .collection('usuarios')
          .where('email', isEqualTo: _emailController.text.trim())
          .get();
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
          await _secureStorage.write(
            key: 'biometric_email',
            value: _emailController.text.trim(),
          );
          setState(() => _hasBiometricAccount = true);
        }
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaHomeLegacy(usuarioData: u),
            ),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: Colors.redAccent),
      );
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
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.explore_outlined,
                        size: 60,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Araucária Sur',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Gestión Territorial · Congregación Español',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDec('Correo electrónico'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: _inputDec('Contraseña'),
                      ),
                      const SizedBox(height: 24),
                      if (_hasBiometricAccount) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isLoading ? null : _authenticateWithBiometrics,
                            icon: const Icon(
                              Icons.fingerprint,
                              color: Color(0xFF1B5E20),
                            ),
                            label: const Text(
                              'Iniciar con Huella/Face',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF1B5E20)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'Iniciar Sesión',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '¿No tienes cuenta?',
                            style: TextStyle(color: Colors.grey),
                          ),
                          GestureDetector(
                            onTap: () => _mostrarDialogoSolicitud(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ' Solicitar acceso',
                                style: TextStyle(
                                  color: Color(0xFF1B5E20),
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
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
