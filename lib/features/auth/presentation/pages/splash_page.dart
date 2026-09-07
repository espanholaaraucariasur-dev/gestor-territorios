import 'dart:async';
import '../../../../core/services/update_service.dart';
import '../../../../core/services/auto_return_service.dart';
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
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // Verificar actualización forzada (solo Android con Play Store)
    await UpdateService.verificarActualizacion(context);
    if (!mounted) return;

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TerritoriosTab(
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
Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => TerritoriosTab(
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
              style: TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w300),
            ),
          ],
        ),
      ),
    );
  }
}
