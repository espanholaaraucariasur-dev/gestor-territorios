import 'dart:async';
import '../../core/services/notificacion_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de devolución automática de tarjetas.
/// - A las 1h50min: alerta al usuario "en 10 minutos se devolverá tu tarjeta"
/// - A las 2h00min: devuelve la tarjeta automáticamente
class AutoReturnService {
  static final AutoReturnService _instance = AutoReturnService._internal();
  factory AutoReturnService() => _instance;
  AutoReturnService._internal();

  final Map<String, Timer> _timersAviso = {};
  final Map<String, Timer> _timersDevolucion = {};
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  // Callback para mostrar snackbar en la UI
  Function(String mensaje, Color color)? onMostrarAlerta;

  static const Duration _tiempoLimite = Duration(hours: 2);
  static const Duration _tiempoAviso = Duration(hours: 1, minutes: 50);

  /// Inicia el timer para una tarjeta recién asignada al publicador.
  void iniciarTimer({
    required String tarjetaId,
    required String territorioId,
    required String tarjetaNombre,
    required String usuarioNombre,
    required DateTime fechaAsignacion,
  }) {
    // Cancelar timers anteriores si existen
    cancelarTimer(tarjetaId);

    final ahora = DateTime.now();
    final tiempoTranscurrido = ahora.difference(fechaAsignacion);

    // Calcular tiempo restante
    final tiempoRestanteAviso = _tiempoAviso - tiempoTranscurrido;
    final tiempoRestanteDevolucion = _tiempoLimite - tiempoTranscurrido;

    // Si ya pasó el tiempo límite, devolver inmediatamente
    if (tiempoRestanteDevolucion.isNegative) {
      _devolverTarjeta(tarjetaId, territorioId, tarjetaNombre, usuarioNombre);
      return;
    }

    // Timer aviso (10 min antes)
    if (tiempoRestanteAviso.isNegative == false) {
      _timersAviso[tarjetaId] = Timer(tiempoRestanteAviso, () {
        _mostrarAvisoDevolucion(tarjetaNombre);
      });
    } else {
      // Ya pasó el tiempo de aviso, mostrar ahora
      _mostrarAvisoDevolucion(tarjetaNombre);
    }

    // Timer devolución automática
    _timersDevolucion[tarjetaId] = Timer(tiempoRestanteDevolucion, () {
      _devolverTarjeta(tarjetaId, territorioId, tarjetaNombre, usuarioNombre);
    });

    debugPrint(
        '⏱️ Timer iniciado para $tarjetaNombre — devuelve en ${tiempoRestanteDevolucion.inMinutes}min');
  }

  /// Cancela los timers de una tarjeta (cuando se devuelve manualmente).
  void cancelarTimer(String tarjetaId) {
    _timersAviso[tarjetaId]?.cancel();
    _timersDevolucion[tarjetaId]?.cancel();
    _timersAviso.remove(tarjetaId);
    _timersDevolucion.remove(tarjetaId);
  }

  /// Cancela todos los timers activos.
  void cancelarTodos() {
    for (final t in _timersAviso.values) t.cancel();
    for (final t in _timersDevolucion.values) t.cancel();
    _timersAviso.clear();
    _timersDevolucion.clear();
  }

  /// Muestra notificación de aviso 10 minutos antes.
  Future<void> _mostrarAvisoDevolucion(String tarjetaNombre) async {
    debugPrint('⚠️ Aviso: $tarjetaNombre se devolverá en 10 minutos');

    // Notificación local
    try {
      const androidDetails = AndroidNotificationDetails(
        'auto_return_channel',
        'Devolución automática',
        channelDescription: 'Avisos de devolución automática de tarjetas',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      await _notif.show(
        tarjetaNombre.hashCode,
        '⚠️ Tarjeta por devolver',
        'La tarjeta "$tarjetaNombre" se devolverá automáticamente en 10 minutos.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error mostrando notificación: $e');
    }

    // Alerta en UI si está disponible
    onMostrarAlerta?.call(
      '⚠️ La tarjeta "$tarjetaNombre" se devolverá en 10 minutos',
      Colors.orange,
    );
  }

  /// Devuelve la tarjeta automáticamente en Firestore.
  Future<void> _devolverTarjeta(
    String tarjetaId,
    String territorioId,
    String tarjetaNombre,
    String usuarioNombre,
  ) async {
    try {
      // Verificar si la tarjeta aún existe y no fue completada
      final doc = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .get();

      if (!doc.exists) {
        cancelarTimer(tarjetaId);
        return;
      }

      final data = doc.data() as Map<String, dynamic>?;
      final completada = data?['completada'] as bool? ?? false;
      final asignadoA = data?['asignado_a'] as String? ?? '';
      if (completada || asignadoA.isEmpty) {
        cancelarTimer(tarjetaId);
        return;
      }

      debugPrint('🔄 Devolviendo automáticamente: $tarjetaNombre');

      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'publicador_email': null,
        'estatus_envio': 'disponible',
        'bloqueado': false,
        'disponible_para_publicadores': true,
        'devuelta_auto': true,
        'devuelta_auto_en': FieldValue.serverTimestamp(),
        'devuelta_auto_por': usuarioNombre,
      });

      // Notificación de devolución completada
      try {
        const androidDetails = AndroidNotificationDetails(
          'auto_return_channel',
          'Devolución automática',
          channelDescription: 'Avisos de devolución automática de tarjetas',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );
        await _notif.show(
          tarjetaNombre.hashCode + 1,
          '📋 Tarjeta devuelta',
          'La tarjeta "$tarjetaNombre" fue devuelta automáticamente.',
          const NotificationDetails(android: androidDetails),
        );
      } catch (_) {}

      onMostrarAlerta?.call(
        '📋 La tarjeta "$tarjetaNombre" fue devuelta automáticamente',
        Colors.blue,
      );

      // Notificar a admins de territorios
      try {
        await NotificacionService.enviarAAdminTerritorios(
          titulo: '⏰ Tarjeta devuelta automáticamente',
          cuerpo: '$usuarioNombre no procesó "$tarjetaNombre" a tiempo — devuelta automáticamente',
          tipo: TipoNotificacion.devolucionAutomatica,
          extra: {'territorio_id': territorioId, 'tarjeta_id': tarjetaId},
        );
      } catch (_) {}

      cancelarTimer(tarjetaId);
    } catch (e) {
      debugPrint('❌ Error devolviendo tarjeta: $e');
    }
  }

  /// Verifica tarjetas asignadas al iniciar la app y reactiva timers si corresponde.
  Future<void> verificarTarjetasAlIniciar(String usuarioNombre) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where('asignado_a', isEqualTo: usuarioNombre)
          .where('completada', isEqualTo: false)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final asignadoEn = data['asignado_en'] as Timestamp?;
        if (asignadoEn == null) continue;

        final territorioId =
            doc.reference.parent.parent?.id ?? '';

        iniciarTimer(
          tarjetaId: doc.id,
          territorioId: territorioId,
          tarjetaNombre: data['nombre']?.toString() ?? doc.id,
          usuarioNombre: usuarioNombre,
          fechaAsignacion: asignadoEn.toDate(),
        );
      }
    } catch (e) {
      debugPrint('Error verificando tarjetas: $e');
    }
  }
}
