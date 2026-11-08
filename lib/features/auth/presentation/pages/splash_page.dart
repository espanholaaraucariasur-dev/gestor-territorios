import 'dart:async';
import '../../../../core/l10n/translation_service.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/services/auto_return_service.dart';
import '../../../../core/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../home/presentation/pages/home_page.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _bloqueadoPorActualizacion = false;
  bool _verificandoActualizacion = false;

  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final resultado = await UpdateService.verificarActualizacion();
    if (!mounted) return;

    if (resultado == UpdateCheckResult.bloqueado) {
      setState(() => _bloqueadoPorActualizacion = true);
      return;
    }

    await _continuarConSesion();
  }

  Future<void> _reintentarActualizacion() async {
    if (_verificandoActualizacion) return;
    setState(() => _verificandoActualizacion = true);

    final resultado = await UpdateService.verificarActualizacion();
    if (!mounted) return;

    if (resultado == UpdateCheckResult.continuar) {
      setState(() {
        _verificandoActualizacion = false;
        _bloqueadoPorActualizacion = false;
      });
      await _continuarConSesion();
    } else {
      setState(() => _verificandoActualizacion = false);
    }
  }

  Future<void> _continuarConSesion() async {
    // La verificación global de vencidas se ejecuta SOLO tras autenticación y
    // para roles con acceso global (es_admin / es_auditor), evitando
    // permission-denied en web al arrancar como usuario sin permisos.

    // Esperar a que Firebase Auth inicialice
    User? firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      try {
        firebaseUser = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        _irALogin();
        return;
      }
    }

    if (firebaseUser == null) {
      _irALogin();
      return;
    }

    // Verificar SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('userEmail') ?? '';
    if (email.isEmpty) {
      _irALogin();
      return;
    }

    // Obtener datos del usuario desde Firestore
    if (!mounted) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get()
          .timeout(const Duration(seconds: 8));

      if (snap.docs.isNotEmpty && mounted) {
        final datos = snap.docs.first.data();
        if (!_cuentaHabilitada(datos)) {
          await _descartarSesionLocal();
          _irALogin();
          return;
        }
        final esAdmin = datos['es_admin'] == true;
        final esAuditor = datos['es_auditor'] == true;
        if (esAdmin || esAuditor) {
          // Solo roles con acceso global a TODAS las tarjetas ejecutan la
          // devolución automática de vencidas al abrir la app.
          AutoReturnService.verificarYDevolverVencidas().catchError((e) {
            debugPrint('Auto-return check: $e');
            return 0;
          });
        }
        unawaited(NotificationService().onUserSignedIn());
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaHomeLegacy(
              usuarioData: _conDocId(snap.docs.first),
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // Intentar con cache
      try {
        final snap = await FirebaseFirestore.instance
            .collection('usuarios')
            .where('email', isEqualTo: email)
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isNotEmpty && mounted) {
          final datos = snap.docs.first.data();
          if (!_cuentaHabilitada(datos)) {
            await _descartarSesionLocal();
            _irALogin();
            return;
          }
          unawaited(NotificationService().onUserSignedIn());
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PantallaHomeLegacy(
                usuarioData: _conDocId(snap.docs.first),
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    _irALogin();
  }

  bool _cuentaHabilitada(Map<String, dynamic> datos) {
    final estado = datos['estado'] ?? 'aprobado';
    final activo = datos['activo'] ?? true;
    return estado == 'aprobado' && activo != false;
  }

  Future<void> _descartarSesionLocal() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error al limpiar preferencias: $e');
    }
  }

  Map<String, dynamic> _conDocId(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return {...data, 'docId': doc.id};
  }

  void _irALogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PantallaAccesoLegacy()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bloqueadoPorActualizacion) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF1B5E20),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.system_update_outlined,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.t('update_required_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('update_required_message'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('update_required_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _verificandoActualizacion
                          ? null
                          : _reintentarActualizacion,
                      icon: _verificandoActualizacion
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _verificandoActualizacion
                            ? context.t('update_checking')
                            : context.t('update_now'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1B5E20),
                        disabledBackgroundColor: Colors.white24,
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      backgroundColor: Color(0xFF1B5E20),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Cargando...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w300),
            ),
          ],
        ),
      ),
    );
  }
}
