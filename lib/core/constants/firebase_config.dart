import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

/// Configuración de Firebase escogida según la plataforma.
///
/// - Android/iOS: usa la API key y appId del cliente nativo
///   (`google-services.json`), correcta para dispositivos.
/// - Web: usa el cliente web del mismo proyecto.
///
/// Antes se forzaba siempre la configuración **web**, lo que hacía que
/// Firebase Auth/Firestore fallaran en Android ("no se conecta a la base").
class FirebaseConfig {
  FirebaseConfig._();

  /// Cliente de dispositivos móviles (Android).
  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: "AIzaSyB2FakN7gtSzWekqRbDmKR_1WQCkBowXDs",
    authDomain: "territorio-sur-8b72c.firebaseapp.com",
    projectId: "territorio-sur-8b72c",
    storageBucket: "territorio-sur-8b72c.firebasestorage.app",
    messagingSenderId: "288799954885",
    appId: "1:288799954885:android:c76dad42f61575970bddac",
  );

  /// Cliente web del mismo proyecto.
  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: "BAP00uhT3oq7hoQFHh6zU5y6Dwt780Db2ovggL3Z3hPm6Ax845AatKZFWW47TtFukDUe_iO6Wx0MO8d4gifk_rA",
    appId: "1:288799954885:web:32ae6dfbc7d871b30bddac",
    messagingSenderId: "288799954885",
    projectId: "territorio-sur-8b72c",
    authDomain: "territorio-sur-8b72c.firebaseapp.com",
    storageBucket: "territorio-sur-8b72c.firebasestorage.app",
  );

  static FirebaseOptions get opciones => kIsWeb ? _web : _android;
}