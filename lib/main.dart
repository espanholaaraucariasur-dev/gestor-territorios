import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app/app.dart';
import 'core/constants/firebase_config.dart';
import 'core/services/notification_service.dart';
import 'core/services/offline_sync_service.dart';

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

  // Persistencia local y cola durable de escrituras.
  if (kIsWeb) {
    try {
      // Hace falta synchronizeTabs para que varias pestañas compartan IndexedDB
      // y ninguna caiga silenciosamente a caché de memoria.
      // ignore: deprecated_member_use
      await FirebaseFirestore.instance.enablePersistence(
        const PersistenceSettings(synchronizeTabs: true),
      );
    } catch (e) {
      debugPrint('Firestore IndexedDB persistence: $e');
    }
  } else {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore persistence settings: $e');
    }
  }

  OfflineSyncService.instance.start();

  // Edge-to-edge explícito mediante Flutter/WindowCompat. Android 15+ lo exige;
  // este modo también lo activa en versiones anteriores sin llamar a las APIs
  // obsoletas de color de las barras.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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