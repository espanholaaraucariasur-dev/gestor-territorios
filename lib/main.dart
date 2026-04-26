import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';

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
