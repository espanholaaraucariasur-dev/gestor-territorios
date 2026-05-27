import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/notificacion_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// Traducciones
import '../../../../core/l10n/translation_service.dart';
import '../../../home/presentation/pages/home_page.dart';

class PantallaAccesoLegacy extends StatefulWidget {
  const PantallaAccesoLegacy({super.key});

  @override
  State<PantallaAccesoLegacy> createState() => _PantallaAccesoLegacyState();
}

class _PantallaAccesoLegacyState extends State<PantallaAccesoLegacy>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _db = FirebaseFirestore.instance;
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  bool _isLoading = false;
  bool _obscurePass = true;
  bool _canCheckBiometrics = false;
  bool _hasBiometricAccount = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  static const Color _verde = Color(0xFF1B5E20);
  static const Color _verdeClaro = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // BIOMETRÍA
  // ─────────────────────────────────────────────────────────

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final stored = await _secureStorage.read(key: 'biometric_email');
      final canUse = canCheck && isSupported;
      final hasAccount = stored != null && stored.isNotEmpty && canUse;
      if (!mounted) return;
      setState(() {
        _canCheckBiometrics = canUse;
        _hasBiometricAccount = hasAccount;
      });
      if (hasAccount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loginBiometrico());
      }
    } catch (_) {}
  }

  Future<void> _loginBiometrico() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!isSupported) {
        _snack('Dispositivo no soporta autenticación segura', Colors.orange);
        return;
      }
      if (!canCheck) {
        _snack('No hay biometría configurada. Usa email y contraseña', Colors.orange);
        return;
      }

      // Verificar que hay email guardado ANTES de autenticar
      final email = await _secureStorage.read(key: 'biometric_email');
      if (email == null || email.isEmpty) {
        _snack('Primero inicia sesión con email para activar biometría', Colors.orange);
        return;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'Autentícate para ingresar a Araucaria Sur',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          sensitiveTransaction: false,
        ),
      );
      if (!ok) return;
      await _loginConEmail(email);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('NotEnrolled') || msg.contains('no_enrolled')) {
        _snack('No hay huella registrada en el dispositivo', Colors.orange);
      } else if (msg.contains('LockedOut') || msg.contains('locked_out')) {
        _snack('Demasiados intentos. Intenta más tarde', Colors.red);
      } else if (msg.contains('NotAvailable') || msg.contains('not_available')) {
        _snack('Biometría no disponible. Usa email y contraseña', Colors.orange);
      } else if (msg.contains('PermanentlyLockedOut')) {
        _snack('Biometría bloqueada. Desbloquea el dispositivo primero', Colors.red);
      } else {
        _snack('Error biometría: $msg', Colors.red);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // LOGIN
  // ─────────────────────────────────────────────────────────

  Future<void> _loginConEmail(String email, {String? password}) async {
    setState(() => _isLoading = true);
    try {
      // Autenticar con Firebase Auth primero para satisfacer reglas de seguridad
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      final snap = await _db
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get();

      if (snap.docs.isEmpty) {
        _snack('Usuario no encontrado.', Colors.red);
        return;
      }

      final u = snap.docs.first.data();

      if (password != null && u['password'] != password) {
        _snack('Contraseña incorrecta.', Colors.red);
        return;
      }

      if (u['estado'] == 'pendiente') {
        _snack('Cuenta pendiente de aprobación.', Colors.orange);
        return;
      }

      if (u['estado'] != 'aprobado') {
        _snack('Cuenta no disponible.', Colors.red);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userEmail', email);

      if (_canCheckBiometrics) {
        await _secureStorage.write(key: 'biometric_email', value: email);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaHomeLegacy(usuarioData: u),
          ),
        );
      }
    } catch (_) {
      _snack('Error de conexión.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _iniciarSesion() {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _snack('Completa todos los campos.', Colors.orange);
      return;
    }
    _loginConEmail(email, password: pass);
  }

  // ─────────────────────────────────────────────────────────
  // RECUPERAR CONTRASEÑA
  // ─────────────────────────────────────────────────────────

  Future<void> _recuperarContrasena() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: _verde),
            SizedBox(width: 10),
            Text('Recuperar contraseña'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('recovery_instructions'),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: context.t('your_email'),
                prefixIcon: const Icon(Icons.email_outlined, color: _verde),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;

              // Notificar a admins sobre recuperación
              await NotificacionService.enviarAAdmins(
                titulo: '🔑 Solicitud de recuperación de contraseña',
                cuerpo: '$email solicita recuperar su contraseña.',
                tipo: TipoNotificacion.solicitudAcceso,
                extra: {'email_solicitante': email},
              );

              if (c.mounted) Navigator.pop(c);
              _snack(context.t('recovery_request_sent'), _verde);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _verde),
            child: Text(context.t('send_request')),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SOLICITAR ACCESO
  // ─────────────────────────────────────────────────────────

  Future<void> _solicitarAcceso() async {
    // PASO 1: Verificar código de 4 dígitos
    final codigoCtrl = TextEditingController();
    bool codigoValido = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: _verde),
              SizedBox(width: 10),
              Text('Código de acceso'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa el código de 4 dígitos proporcionado\npor la congregación.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: codigoCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 12),
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final codigo = codigoCtrl.text.trim();
                if (codigo.length != 4) {
                  _snack('Ingresa exactamente 4 dígitos', Colors.orange);
                  return;
                }
                // Verificar contra Firestore
                final doc = await _db.collection('configuracion').doc('codigo_acceso').get();
                final codigoCorrecto = (doc.data()?['codigo'] as String?) ?? '';
                if (codigo == codigoCorrecto) {
                  codigoValido = true;
                  Navigator.pop(c);
                } else {
                  _snack('Código incorrecto', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
              child: const Text('Verificar'),
            ),
          ],
        ),
      ),
    );

    if (!codigoValido) return;

    // PASO 2: Formulario de solicitud de acceso
    final nomCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.person_add_outlined, color: _verde),
              const SizedBox(width: 10),
              Text(context.t('request_access')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t('admin_review_approve'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _inputField(
                    ctrl: nomCtrl,
                    hint: context.t('full_name'),
                    icon: Icons.person_outline),
                const SizedBox(height: 10),
                _inputField(
                    ctrl: emailCtrl,
                    hint: 'Correo electrónico',
                    icon: Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: context.t('create_password'),
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                        size: 18,
                      ),
                      onPressed: () => setDlg(() => obscure = !obscure),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nomCtrl.text.isEmpty ||
                    emailCtrl.text.isEmpty ||
                    passCtrl.text.isEmpty) {
                  _snack('Completa todos los campos.', Colors.orange);
                  return;
                }
                try {
                  await _db.collection('usuarios').add({
                    'nombre': nomCtrl.text.trim(),
                    'email': emailCtrl.text.trim().toLowerCase(),
                    'password': passCtrl.text.trim(),
                    'estado': 'pendiente',
                    'es_admin': false,
                    'es_admin_territorios': false,
                    'es_conductor': false,
                    'es_publicador': false,
                    'idioma': 'es',
                    'created_at': FieldValue.serverTimestamp(),
                  });

                  // Notificar a todos los admins
                  await NotificacionService.enviarAAdmins(
                    titulo: '👤 Nueva solicitud de acceso',
                    cuerpo: '${nomCtrl.text.trim()} solicita acceso a la app.',
                    tipo: TipoNotificacion.solicitudAcceso,
                    extra: {
                      'solicitante_nombre': nomCtrl.text.trim(),
                      'solicitante_email': emailCtrl.text.trim(),
                    },
                  );

                  if (c.mounted) Navigator.pop(c);
                  _snack(context.t('request_sent'), _verde);
                } catch (e) {
                  _snack('Error: $e', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _verde),
              child: Text(context.t('send_request')),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _verde, width: 2),
        ),
        isDense: true,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_verde, _verdeClaro, Color(0xFF1565C0)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo ────────────────────────────────
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 2),
                      ),
                      child: const Icon(
                        Icons.explore_outlined,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Araucária Sur',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('app_subtitle'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),

                    // ── Card de login ────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 2,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('sign_in'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF263238),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.t('enter_credentials'),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 24),

                          // Email
                          Text(context.t('email'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF546E7A))),
                          const SizedBox(height: 6),
                          _inputField(
                            ctrl: _emailCtrl,
                            hint: 'tu@email.com',
                            icon: Icons.email_outlined,
                            type: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),

                          // Contraseña
                          Text(context.t('password'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF546E7A))),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            onSubmitted: (_) => _iniciarSesion(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: Colors.grey),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                  size: 18,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePass = !_obscurePass),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _verde, width: 2),
                              ),
                              isDense: true,
                            ),
                          ),

                          // Olvidé mi contraseña
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _recuperarContrasena,
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                              ),
                              child: Text(
                                context.t('forgot_password'),
                                style: const TextStyle(
                                  color: _verde,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Botón biométrico
                          if (_hasBiometricAccount) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _loginBiometrico,
                                icon: const Icon(Icons.fingerprint,
                                    color: _verde),
                                label: Text(
                                  context.t('enter_with_biometric'),
                                  style: const TextStyle(
                                    color: _verde,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _verde),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Botón iniciar sesión
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _iniciarSesion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _verde,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text(
                                      'Iniciar sesión',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),

                          // Solicitar acceso
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  context.t('first_time'),
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13),
                                ),
                                TextButton(
                                  onPressed: _solicitarAcceso,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                  ),
                                  child: Text(
                                    context.t('request_access'),
                                    style: const TextStyle(
                                      color: _verde,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      'Congregación Española Araucaria Sur',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
