import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  void _verificarSesion() async {
    // Esperar mínimo 1 segundo para mostrar splash
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool loggedIn = prefs.getBool('isLoggedIn') ?? false;
    final String email = prefs.getString('userEmail') ?? '';

    if (!loggedIn || email.isEmpty) {
      _irALogin();
      return;
    }

    // Esperar a que Firebase Auth esté listo antes de consultar Firestore
    User? firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      // Esperar hasta 5 segundos a que Auth se inicialice
      try {
        firebaseUser = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Sin sesión de Firebase Auth — ir al login
        _irALogin();
        return;
      }
    }

    if (firebaseUser == null) {
      _irALogin();
      return;
    }

    // Ahora sí consultar Firestore (usuario autenticado)
    if (!mounted) return;
    QuerySnapshot? snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        snap = await FirebaseFirestore.instance
            .collection('usuarios')
            .where('email', isEqualTo: email)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        snap = null;
      }
    }

    if (!mounted) return;
    if (snap != null && snap.docs.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PantallaHomeLegacy(
            usuarioData: snap!.docs.first.data() as Map<String, dynamic>,
          ),
        ),
      );
    } else {
      _irALogin();
    }
  }

  void _irALogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const PantallaAccesoLegacy(),
      ),
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
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
