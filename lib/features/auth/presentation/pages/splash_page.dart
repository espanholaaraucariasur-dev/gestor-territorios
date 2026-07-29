import 'dart:async';
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaHomeLegacy(
              usuarioData: snap.docs.first.data() as Map<String, dynamic>,
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
              builder: (_) => PantallaHomeLegacy(
                usuarioData: snap.docs.first.data() as Map<String, dynamic>,
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    _irALogin();
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
