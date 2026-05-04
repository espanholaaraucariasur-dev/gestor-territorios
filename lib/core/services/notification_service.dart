import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get messageStream => _messageStreamController.stream;

  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        debugPrint('🌐 Running on web - FCM limited functionality');
        await _getAndSaveToken();
        return;
      }
      await _requestPermissions();
      await _initializeLocalNotifications();
      RemoteMessage? initialMessage =
          await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      await _getAndSaveToken();
      debugPrint('✅ NotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing NotificationService: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) {
      await _firebaseMessaging.requestPermission(
          alert: true, badge: true, sound: true);
      return;
    }
    if (Platform.isIOS) {
      await _firebaseMessaging.requestPermission(
          alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) return;
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotifications.initialize(initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped);
  }

  void _onNotificationTapped(NotificationResponse notificationResponse) {
    debugPrint('🔔 Notification tapped: ${notificationResponse.payload}');
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 Foreground message: ${message.notification?.title}');
    if (!kIsWeb) _showLocalNotification(message);
    _messageStreamController.add(message);
  }

  void _handleMessage(RemoteMessage message) {
    debugPrint('🔔 Message handled: ${message.notification?.title}');
    _messageStreamController.add(message);
    _navigateBasedOnMessage(message);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'araucaria_sur_channel',
      'Araucaria Sur Notifications',
      channelDescription: 'Notifications from Araucaria Sur app',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'Nueva Notificación',
      message.notification?.body ?? 'Tienes una nueva notificación',
      platformDetails,
      payload: message.data.toString(),
    );
  }

  Future<void> _getAndSaveToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('🔑 FCM Token: $token');
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(currentUser.uid)
            .update({'fcm_token': token});
        debugPrint('✅ FCM token saved to Firestore');
      }
    } catch (e) {
      debugPrint('❌ Error saving FCM token to Firestore: $e');
    }
  }

  void _navigateBasedOnMessage(RemoteMessage message) {
    if (message.data['screen'] != null) {
      debugPrint('🧭 Navigating to: ${message.data['screen']}');
    }
  }

  void dispose() {
    _messageStreamController.close();
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
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
  } catch (_) {}
  debugPrint('🔔 Background message: ${message.notification?.title}');
}
