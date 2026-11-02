import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app/app.dart';
import 'core/constants/firebase_config.dart';
import 'core/services/notification_service.dart';

void main() async {
  // Edge-to-Edge configurado para Android 15 (SDK 35)
  // Evita que la interfaz se superponga con la barra de estado/navegación
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    await Firebase.initializeApp(options: FirebaseConfig.opciones);
  } catch (e) {
    debugPrint('Firebase ya estaba inicializado: $e');
  }

  // Persistencia local — solo en móvil (web no lo soporta)
  if (!kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore settings: $e');
    }
  } else {
    // Web: Configurar settings básicos para Web
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false, // Web no soporta persistence
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore web settings: $e');
    }
  }

  // En web, no bloquear el arranque con notificaciones
  if (!kIsWeb) {
    await NotificationService().initialize();
  } else {
    NotificationService().initialize().catchError((e) {
      debugPrint('Web notification init: $e');
    });
  }

  runApp(const AraucariaApp());
}