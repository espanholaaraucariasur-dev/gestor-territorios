import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    final prefs = await SharedPreferences.getInstance();
    final bool loggedIn = prefs.getBool('isLoggedIn') ?? false;
    final String email = prefs.getString('userEmail') ?? '';

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    if (loggedIn && email.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaHomeLegacy(
              usuarioData: snap.docs.first.data(),
            ),
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
