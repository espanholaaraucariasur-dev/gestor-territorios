import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app/app.dart';
import 'core/services/notification_service.dart';

const FirebaseOptions _firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyAJr2vepvlf0JSwJz-v_6edHWk7uurT_6c",
  authDomain: "territorio-sur-8b72c.firebaseapp.com",
  projectId: "territorio-sur-8b72c",
  storageBucket: "territorio-sur-8b72c.firebasestorage.app",
  messagingSenderId: "288799954885",
  appId: "1:288799954885:web:32ae6dfbc7d871b30bddac",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
  } catch (e) {
    debugPrint('Firebase ya estaba inicializado: $e');
  }

  // Persistencia local — la app funciona aunque la BD esté procesando cambios
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firestore settings: $e');
  }

  await NotificationService().initialize();
  runApp(const AraucariaApp());
}
