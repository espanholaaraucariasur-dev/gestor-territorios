import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/notificacion_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Modelo de Usuario unificado
import 'package:araucaria_sur/features/auth/data/models/user_model.dart';

// Traducciones y Navegación
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

  final _localAuth = kIsWeb ? null : LocalAuthentication();
  final _secureStorage = kIsWeb
      ? null
      : const FlutterSecureStorage(
          aOptions: AndroidOptions(
            migrateWithBackup: true,
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
    if (kIsWeb || _localAuth == null) return;
    try {
      final canCheck = await _localAuth!.canCheckBiometrics;
      final isSupported = await _localAuth!.isDeviceSupported();
      final stored = await _secureStorage!.read(key: 'biometric_email');
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
      final canCheck = await _localAuth!.canCheckBiometrics;
      final isSupported = await _localAuth!.isDeviceSupported();

      if (!isSupported) {
        _snack('Dispositivo no soporta autenticación segura', Colors.orange);
        return;
      }
      if (!canCheck) {
        _snack('No hay biometría configurada. Usa email y contraseña',
            Colors.orange);
        return;
      }

      final email = await _secureStorage!.read(key: 'biometric_email');
      if (email == null || email.isEmpty) {
        _snack('Primero inicia sesión con email para activar biometría',
            Colors.orange);
        return;
      }

      final ok = await _localAuth!.authenticate(
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
      } else if (msg.contains('NotAvailable') ||
          msg.contains('not_available')) {
        _snack(
            'Biometría no disponible. Usa email y contraseña', Colors.orange);
      } else if (msg.contains('PermanentlyLockedOut')) {
        _snack('Biometría bloqueada. Desbloquea el dispositivo primero',
            Colors.red);
      } else {
        _snack('Error biometría: $msg', Colors.red);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // LOGIN Y MIGRACIÓN DE USUARIOS
  // ─────────────────────────────────────────────────────────

  Future<void> _loginConEmail(String rawEmail, {String? password}) async {
    final email = rawEmail.trim().toLowerCase();
    setState(() => _isLoading = true);

    try {
      // La biometría solo reutiliza una contraseña ya guardada. Sin esta
      // guarda, una sesión abierta bastaba para entrar como cualquier correo
      // del directorio sin comprobar la contraseña.
      if (password == null) {
        final passGuardada = await _secureStorage?.read(key: 'biometric_pass');
        if (passGuardada == null || passGuardada.isEmpty) {
          _snack(
              'Sesión expirada. Inicia sesión con contraseña.', Colors.orange);
          return;
        }
        await _loginConEmail(email, password: passGuardada);
        return;
      }

      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        final code = e.code;
        if (code == 'invalid-email') {
          _snack('Email inválido.', Colors.red);
          return;
        } else if (code == 'user-disabled') {
          _snack('Cuenta deshabilitada.', Colors.red);
          return;
        } else if (code == 'network-request-failed') {
          _snack('Problema de conexión. Intenta de nuevo.', Colors.red);
          return;
        } else if (code == 'too-many-requests') {
          _snack('Demasiados intentos. Espera un momento e intenta de nuevo.',
              Colors.red);
          return;
        }

        // No se crea la cuenta automáticamente: cualquiera que conociera un
        // correo del directorio podía elegir la contraseña y entrar. Las
        // cuentas antiguas sin contraseña las restablece un administrador.
        if (code == 'user-not-found') {
          bool? enDirectorio;
          try {
            final snap = await _db
                .collection('usuarios')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();
            enDirectorio = snap.docs.isNotEmpty;
          } catch (_) {}
          if (enDirectorio == null) {
            _snack('No se pudo verificar tu cuenta. Intenta de nuevo.',
                Colors.red);
          } else if (enDirectorio) {
            _snack(
              'Tu cuenta existe pero no tiene contraseña configurada. '
              'Pide al administrador que restablezca tu acceso.',
              Colors.red,
            );
          } else {
            _snack('Usuario no encontrado en el directorio.', Colors.red);
          }
        } else {
          _snack(
            'Correo o contraseña incorrectos. Si tu cuenta es anterior, '
            'usa "Recuperar contraseña".',
            Colors.red,
          );
        }
        return;
      }

      // Obtener datos del usuario desde Firestore
      final snap = await _db
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get();

      if (snap.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        _snack('Usuario no encontrado en el directorio.', Colors.red);
        return;
      }

      final docSnap = snap.docs.first;
      final rawData = docSnap.data();
      final docId = docSnap.id;

      // Se valida el estado antes de escribir o dejar la sesión abierta: una
      // cuenta pendiente o desactivada no debe conservar acceso a Firestore.
      final estado = rawData['estado'] ?? 'aprobado';
      if (estado != 'aprobado') {
        await FirebaseAuth.instance.signOut();
        _snack(
          estado == 'pendiente'
              ? 'Cuenta pendiente de aprobación.'
              : 'Cuenta no disponible.',
          estado == 'pendiente' ? Colors.orange : Colors.red,
        );
        return;
      }

      if (rawData['activo'] == false) {
        await FirebaseAuth.instance.signOut();
        _snack('Cuenta desactivada. Contacta al administrador.', Colors.red);
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Deserialización mediante UserModel con fallbacks seguros
      final userModel = UserModel.fromMap(rawData, docId);

      // Auto-Healing: Corregir registros antiguos que no tengan uid o rol estructurado
      final updates = <String, dynamic>{};
      if (uid != null && !rawData.containsKey('uid')) {
        updates['uid'] = uid;
      }
      if (!rawData.containsKey('rol')) {
        // Deducir rol antiguo
        String rolAntiguo = 'publicador';
        if (rawData['es_admin'] == true ||
            rawData['es_admin_territorios'] == true) {
          rolAntiguo = 'admin';
        } else if (rawData['es_conductor'] == true) {
          rolAntiguo = 'conductor';
        }
        updates['rol'] = rolAntiguo;
      }

      if (updates.isNotEmpty) {
        await docSnap.reference.update(updates);
      }

      // Guardar sesión local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userEmail', email);

      if (_canCheckBiometrics && _secureStorage != null) {
        await _secureStorage!.write(key: 'biometric_email', value: email);
        if (password.isNotEmpty) {
          await _secureStorage!.write(key: 'biometric_pass', value: password);
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaHomeLegacy(
              usuarioData: {
                ...rawData,
                'docId': docId,
                'uid': uid ?? docId,
                'rol': userModel.rol,
                'nombre': userModel.nombre,
              },
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('LOGIN ERROR: $e');
      final code = e.code.toLowerCase();
      if (code.contains('permission-denied') ||
          code.contains('unauthenticated')) {
        _snack(
            'No se pudo verificar el usuario. Intenta de nuevo.', Colors.red);
      } else if (code.contains('unavailable') || code.contains('network')) {
        _snack('Problema de conexión. Intenta de nuevo.', Colors.red);
      } else {
        _snack('Error de base de datos. Intenta de nuevo.', Colors.red);
      }
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      _snack('Error inesperado. Intenta de nuevo.', Colors.red);
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
              final email = emailCtrl.text.trim().toLowerCase();
              if (email.isEmpty) return;

              try {
                // No requiere sesión: si la cuenta aún no existe en Auth
                // (usuario legado), Firebase responde user-not-found y se
                // deriva la solicitud al administrador.
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);
                if (c.mounted) Navigator.pop(c);
                _snack('✅ Email de recuperación enviado a $email', _verde);
              } on FirebaseAuthException catch (e) {
                if (e.code == 'user-not-found') {
                  await NotificacionService.enviarAAdmins(
                    titulo: '🔑 Solicitud recuperación contraseña',
                    cuerpo: '$email necesita recuperar su contraseña.',
                    tipo: TipoNotificacion.solicitudAcceso,
                    extra: {'email_solicitante': email},
                  );
                  if (c.mounted) Navigator.pop(c);
                  _snack('Solicitud enviada al administrador.', _verde);
                } else {
                  _snack('Error: ${e.message}', Colors.red);
                }
              } catch (e) {
                _snack('Error al enviar email de recuperación.', Colors.red);
              }
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
    final codigoCtrl = TextEditingController();
    bool codigoValido = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) {
          bool verificando = false;
          String? errorMsg;

          Future<void> verificar() async {
            if (verificando) return;
            final codigo = codigoCtrl.text.trim();
            if (codigo.length != 4 || int.tryParse(codigo) == null) {
              errorMsg = 'Ingresa un código de 4 dígitos';
              setDlg(() {});
              return;
            }
            setDlg(() => verificando = true);
            try {
              final doc = await _db
                  .collection('configuracion')
                  .doc('codigo_acceso')
                  .get();
              final codigoGuardado = doc.exists
                  ? (doc.data()?['codigo']?.toString().trim() ?? '')
                  : '';
              if (codigoGuardado.isEmpty) {
                setDlg(() {
                  verificando = false;
                  errorMsg =
                      'Código no configurado. Contacta al administrador.';
                });
                return;
              }
              if (codigo == codigoGuardado) {
                codigoValido = true;
                Navigator.pop(context);
              } else {
                setDlg(() {
                  verificando = false;
                  errorMsg = 'Código incorrecto';
                });
              }
            } catch (e, stack) {
              debugPrint('Error al verificar PIN: $e\n$stack');
              setDlg(() {
                verificando = false;
                errorMsg = 'No se pudo verificar. Revisa tu conexión.';
              });
            }
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(24),
              child: Form(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, color: _verde, size: 26),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Código de acceso',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                      autofocus: true,
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12),
                      decoration: InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onSubmitted: (_) => verificar(),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: verificando ? null : verificar,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _verde,
                              foregroundColor: Colors.white),
                          child: verificando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Verificar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!codigoValido) return;

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
                final emailNorm = emailCtrl.text.trim().toLowerCase();
                final nombre = nomCtrl.text.trim();
                final pass = passCtrl.text.trim();
                User? creado;
                bool yaExistia = false;

                try {
                  // La cuenta se crea primero porque las reglas solo permiten
                  // consultar `usuarios` con una sesión real. Si el correo ya
                  // figura en el directorio, la cuenta recién creada se borra
                  // y se cierra la sesión para no dejar una vía de acceso.
                  try {
                    final cred = await FirebaseAuth.instance
                        .createUserWithEmailAndPassword(
                      email: emailNorm,
                      password: pass,
                    );
                    creado = cred.user;
                  } on FirebaseAuthException catch (e) {
                    if (e.code != 'email-already-in-use') rethrow;
                    yaExistia = true;
                  }

                  final existentes = await _db
                      .collection('usuarios')
                      .where('email', isEqualTo: emailNorm)
                      .limit(1)
                      .get();
                  if (existentes.docs.isNotEmpty) {
                    final estadoExistente =
                        (existentes.docs.first.data()['estado'] as String?) ??
                            'pendiente';
                    if (creado != null) {
                      try {
                        await creado.delete();
                      } catch (_) {}
                    }
                    await FirebaseAuth.instance.signOut();
                    if (c.mounted) Navigator.pop(c);
                    if (estadoExistente == 'aprobado') {
                      _snack(
                          'Este correo ya tiene una cuenta aprobada. Inicia sesión.',
                          Colors.orange);
                    } else {
                      _snack(
                          'Ya enviaste una solicitud con este correo. Espera la aprobación.',
                          Colors.orange);
                    }
                    return;
                  }

                  final solicitud = <String, dynamic>{
                    'nombre': nombre,
                    'email': emailNorm,
                    'rol': 'publicador',
                    'estado': 'pendiente',
                    'es_admin': false,
                    'es_admin_territorios': false,
                    'es_conductor': false,
                    'es_publicador': true,
                    'idioma': 'es',
                    'created_at': FieldValue.serverTimestamp(),
                    if (creado != null) 'uid': creado.uid,
                  };
                  if (creado != null) {
                    await _db
                        .collection('usuarios')
                        .doc(creado.uid)
                        .set(solicitud);
                  } else {
                    await _db.collection('usuarios').add(solicitud);
                  }

                  await NotificacionService.enviarAAdmins(
                    titulo: '👤 Nueva solicitud de acceso',
                    cuerpo: '$nombre solicita acceso a la app. Toca para aprobar.',
                    tipo: TipoNotificacion.solicitudAcceso,
                    extra: {
                      'solicitante_nombre': nombre,
                      'solicitante_email': emailNorm,
                      'screen': 'usuarios_pendientes',
                      'tipo': 'solicitud_acceso',
                    },
                  );

                  await FirebaseAuth.instance.signOut();
                  if (c.mounted) Navigator.pop(c);
                  _snack(context.t('request_sent'), _verde);
                } catch (e) {
                  await FirebaseAuth.instance.signOut();
                  if (yaExistia) {
                    _snack(
                        'Ese correo ya está registrado. Inicia sesión o usa "Recuperar contraseña".',
                        Colors.orange);
                  } else {
                    _snack('Error: $e', Colors.red);
                  }
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
  // HELPERS Y BUILD
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
